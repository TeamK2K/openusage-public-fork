import Darwin
import Foundation

/// A running login CLI the accounts page can type into (a pasted code) and stop (Cancel, timeout).
@MainActor
protocol SignInProcess: AnyObject {
    func write(_ text: String) throws
    func terminate()
}

/// Starts the login CLI. Output and exit arrive on background threads through the `@Sendable` hooks.
@MainActor
protocol SignInLaunching {
    func launch(
        executable: String,
        arguments: [String],
        environment: [String: String],
        onOutput: @escaping @Sendable (String) -> Void,
        onExit: @escaping @Sendable (Int32) -> Void
    ) throws -> any SignInProcess
}

/// Signs an account in from the accounts page without a terminal: makes the seat folder (Add Account)
/// or reuses a signed-out card's seat (Sign In), runs `claude auth login` / `codex login` with only that
/// folder as its home, shows the sign-in link the CLI prints, feeds a pasted code to it, and on success
/// asks the app to pick the new account up. One sign-in at a time, bounded by `timeout`.
@MainActor
final class AccountSignIn {
    enum Phase: String, Encodable, Sendable { case idle, waiting, succeeded, failed }

    /// What the page shows. `signInProviderIds` are the signed-out cards that get a Sign In button.
    struct Status: Encodable, Equatable, Sendable {
        var phase: Phase = .idle
        var tool: String?
        var seat: String?
        var folder: String?
        var url: String?
        var message: String?
        var startedAt: String?
        var signInProviderIds: [String] = []
        var error: String?
    }

    /// A request the page can't have right now; the API maps each to an HTTP status and error code.
    enum Refusal: Error, Equatable {
        case busy, notWaiting, unknownProvider, emptyCode, startFailed
    }

    static let defaultTimeout: Duration = .seconds(600)
    /// Output kept per sign-in, enough for the link and the last error line.
    private static let outputLimit = 64 * 1024

    private struct Session {
        let id: Int
        let tool: SeatTool
        let folder: String
        let process: any SignInProcess
        var output = ""
        var timeoutTask: Task<Void, Never>?
    }

    private let seats: AccountSeats
    private let launcher: SignInLaunching
    private let resolveExecutable: @MainActor (SeatTool) -> String?
    private let environment: @MainActor () -> [String: String]
    private let signedOutLocations: @MainActor () -> [String: String]
    private let onSignedIn: @MainActor (SeatTool, String) async -> Void
    private let replayCallback: @Sendable (URL) async throws -> Int
    private let sleep: @Sendable (Duration) async throws -> Void
    private let timeout: Duration
    private let now: () -> Date

    private var current = Status()
    private var session: Session?
    private var lastSessionID = 0

    init(
        seats: AccountSeats,
        launcher: SignInLaunching = SystemSignInLauncher(),
        resolveExecutable: @escaping @MainActor (SeatTool) -> String? = { AccountSignIn.findExecutable($0.rawValue) },
        environment: @escaping @MainActor () -> [String: String] = { AccountSignIn.loginEnvironment() },
        signedOutLocations: @escaping @MainActor () -> [String: String],
        onSignedIn: @escaping @MainActor (SeatTool, String) async -> Void,
        replayCallback: @escaping @Sendable (URL) async throws -> Int = AccountSignIn.replay,
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
        timeout: Duration = AccountSignIn.defaultTimeout,
        now: @escaping () -> Date = Date.init
    ) {
        self.seats = seats
        self.launcher = launcher
        self.resolveExecutable = resolveExecutable
        self.environment = environment
        self.signedOutLocations = signedOutLocations
        self.onSignedIn = onSignedIn
        self.replayCallback = replayCallback
        self.sleep = sleep
        self.timeout = timeout
        self.now = now
    }

    var status: Status {
        var status = current
        status.signInProviderIds = signedOutLocations().keys.sorted()
        return status
    }

    // MARK: - Page actions

    /// Add Account: a new `seatN` folder for `tool`, then its login.
    func add(_ tool: SeatTool) throws(Refusal) {
        guard session == nil else { throw .busy }
        guard let executable = resolve(tool) else { throw .startFailed }
        let name: String
        let folder: String
        do {
            name = try seats.nextFreeName()
            folder = try seats.create(tool, name: name)
        } catch {
            fail(tool, seat: nil, folder: nil, "Couldn't create the account folder: \(error.localizedDescription)")
            throw .startFailed
        }
        AppLog.info(.config, "accounts page: created \(tool.rawValue) seat \(name) at \(seats.shortened(folder))")
        try start(tool, seat: name, folder: folder, executable: executable)
    }

    /// Sign In on a signed-out Claude card: its own seat folder when it was a `~/.claude-<name>` seat
    /// (recreated, marker included, if it was removed), otherwise a new seat.
    func signIn(providerID: String) throws(Refusal) {
        guard session == nil else { throw .busy }
        guard let location = signedOutLocations()[providerID] else { throw .unknownProvider }
        guard let name = seats.claudeSeat(forSignedOutLocation: location) else {
            try add(.claude)
            return
        }
        guard let executable = resolve(.claude) else { throw .startFailed }
        var folder = seats.folder(for: .claude, name: name)
        if !seats.files.exists(folder) {
            do {
                folder = try seats.create(.claude, name: name)
            } catch {
                fail(.claude, seat: name, folder: folder, "Couldn't recreate \(seats.shortened(folder)): \(error.localizedDescription)")
                throw .startFailed
            }
        }
        try start(.claude, seat: name, folder: folder, executable: executable)
    }

    /// Paste Code: a code goes to the CLI's input. A `http://localhost…` address is the browser's failed
    /// return to the CLI (Chrome answers HTTP 431 when localhost cookies are too big), so the app opens
    /// that address itself, without cookies, which completes the same step.
    func submit(code raw: String) throws(Refusal) {
        guard var session else { throw .notWaiting }
        let code = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else { throw .emptyCode }
        if let url = Self.loopbackCallback(code) {
            let name = session.tool.displayName
            current.message = "Sending the sign-in page's address to \(name)…"
            let id = session.id
            let replay = replayCallback
            Task { [weak self] in
                do {
                    let status = try await replay(url)
                    self?.noteReplay("Sent. Finishing sign-in…", ok: (200..<400).contains(status), status: status, session: id)
                } catch {
                    AppLog.warn(.config, "accounts page: sign-in callback replay failed: \(error.localizedDescription)")
                    self?.noteReplay("Couldn't reach \(name)'s sign-in helper. Paste the code instead, or try again.", ok: false, status: nil, session: id)
                }
            }
            return
        }
        do {
            try session.process.write(code + "\n")
            session.output += "\n"
            self.session = session
            current.message = "Code sent. Finishing sign-in…"
        } catch {
            AppLog.error(.config, "accounts page: couldn't pass the code to \(session.tool.rawValue) login: \(error.localizedDescription)")
            current.message = "Couldn't pass the code to \(session.tool.displayName). Try again or cancel."
        }
    }

    /// Cancel a running sign-in (the CLI is stopped), or dismiss a finished one.
    func cancel() {
        if let session {
            session.timeoutTask?.cancel()
            session.process.terminate()
            self.session = nil
            AppLog.info(.config, "accounts page: \(session.tool.rawValue) sign-in cancelled")
            current = Status(message: "Sign-in cancelled.")
        } else {
            current = Status()
        }
    }

    // MARK: - Process lifecycle

    private func resolve(_ tool: SeatTool) -> String? {
        if let executable = resolveExecutable(tool) { return executable }
        fail(tool, seat: nil, folder: nil, "\(tool.displayName) isn't installed on this Mac (no `\(tool.rawValue)` on your shell's PATH). Install it, then try again.")
        return nil
    }

    private func start(_ tool: SeatTool, seat: String, folder: String, executable: String) throws(Refusal) {
        var env = environment()
        for key in Self.strippedKeys { env.removeValue(forKey: key) }
        env[tool.homeVariable] = folder
        lastSessionID += 1
        let id = lastSessionID
        let process: any SignInProcess
        do {
            process = try launcher.launch(
                executable: executable, arguments: tool.loginArguments, environment: env,
                onOutput: { [weak self] text in Task { @MainActor in self?.received(text, session: id) } },
                onExit: { [weak self] code in Task { @MainActor in await self?.exited(code, session: id) } }
            )
        } catch {
            fail(tool, seat: seat, folder: folder, "Couldn't start \(tool.displayName)'s sign-in: \(error.localizedDescription)")
            throw .startFailed
        }
        let timeout = timeout
        let sleep = sleep
        let timeoutTask = Task { [weak self] in
            do { try await sleep(timeout) } catch { return }
            self?.timedOut(session: id)
        }
        session = Session(id: id, tool: tool, folder: folder, process: process, timeoutTask: timeoutTask)
        current = Status(
            phase: .waiting, tool: tool.rawValue, seat: seat, folder: seats.shortened(folder),
            message: "Waiting for sign-in…", startedAt: OpenUsageISO8601.string(from: now())
        )
        AppLog.info(.config, "accounts page: \(tool.rawValue) sign-in started in \(seats.shortened(folder))")
    }

    func received(_ text: String, session id: Int) {
        guard var session, session.id == id else { return }
        session.output = String((session.output + Self.stripANSI(text)).suffix(Self.outputLimit))
        self.session = session
        if current.url == nil, let url = Self.firstSignInURL(in: session.output) {
            current.url = url
        }
    }

    func exited(_ code: Int32, session id: Int) async {
        guard let session, session.id == id else { return }
        session.timeoutTask?.cancel()
        let folder = seats.shortened(session.folder)
        guard code == 0 else {
            self.session = nil
            let detail = Self.lastLine(of: session.output).map { ": \($0)" } ?? "."
            AppLog.error(.config, "accounts page: \(session.tool.rawValue) login in \(folder) exited \(code)")
            current.phase = .failed
            current.message = "Sign-in didn't finish (\(session.tool.rawValue) exited with code \(code))\(detail)"
            return
        }
        current.message = "Signed in. Loading the account…"
        await onSignedIn(session.tool, session.folder)
        // Cancel pressed while the account loaded already reset the page; leave that as is.
        guard self.session?.id == id else { return }
        self.session = nil
        AppLog.info(.config, "accounts page: \(session.tool.rawValue) signed in at \(folder)")
        current.phase = .succeeded
        current.message = "Signed in at \(folder). The account's card is below."
    }

    private func timedOut(session id: Int) {
        guard let session, session.id == id else { return }
        session.process.terminate()
        self.session = nil
        AppLog.error(.config, "accounts page: \(session.tool.rawValue) sign-in timed out after \(timeout)")
        current.phase = .failed
        current.message = "Sign-in timed out after 10 minutes, so it was stopped. Try again."
    }

    private func noteReplay(_ message: String, ok: Bool, status: Int?, session id: Int) {
        guard let session, session.id == id else { return }
        if ok {
            current.message = message
        } else if let status {
            AppLog.warn(.config, "accounts page: \(session.tool.rawValue) sign-in helper answered HTTP \(status)")
            current.message = "\(session.tool.displayName)'s sign-in helper answered HTTP \(status). Paste the code instead, or try again."
        } else {
            current.message = message
        }
    }

    private func fail(_ tool: SeatTool, seat: String?, folder: String?, _ message: String) {
        AppLog.error(.config, "accounts page: \(tool.rawValue) sign-in failed to start: \(message)")
        current = Status(
            phase: .failed, tool: tool.rawValue, seat: seat, folder: folder.map(seats.shortened),
            message: message, startedAt: OpenUsageISO8601.string(from: now())
        )
    }

    // MARK: - Pure helpers

    /// Credentials that would make the CLI skip or misdirect the browser login, plus any inherited home.
    static let strippedKeys = ["ANTHROPIC_API_KEY", "CLAUDE_CODE_OAUTH_TOKEN", "CLAUDE_CONFIG_DIR", "CODEX_HOME"]

    /// The app's environment with the user's login-shell PATH (a Finder launch has only launchd's).
    static func loginEnvironment(
        base: [String: String] = ProcessInfo.processInfo.environment,
        loginShellPath: String? = LoginShellEnvironment.shared.cachedValue(for: "PATH")
    ) -> [String: String] {
        var env = base
        if let loginShellPath { env["PATH"] = loginShellPath }
        return env
    }

    /// `name` on the login-shell PATH, then the usual install folders.
    static func findExecutable(
        _ name: String,
        path: String? = LoginShellEnvironment.shared.cachedValue(for: "PATH") ?? ProcessInfo.processInfo.environment["PATH"],
        home: String = FileManager.default.homeDirectoryForCurrentUser.path,
        isExecutable: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }
    ) -> String? {
        let folders = (path ?? "").split(separator: ":").map(String.init)
            + [home + "/.local/bin", home + "/.claude/local", "/opt/homebrew/bin", "/usr/local/bin"]
        return folders.lazy.filter { !$0.isEmpty }.map { $0 + "/" + name }.first(where: isExecutable)
    }

    static func firstSignInURL(in output: String) -> String? {
        guard let range = output.range(of: #"https://[^\s"'<>]+"#, options: .regularExpression) else { return nil }
        return String(output[range])
    }

    /// A browser address back to a login CLI's own helper on this Mac (never this app's port).
    static func loopbackCallback(_ text: String) -> URL? {
        guard let url = URL(string: text), url.scheme == "http",
              let host = url.host, ["localhost", "127.0.0.1", "::1"].contains(host),
              url.port != Int(LocalUsageServer.port)
        else { return nil }
        return url
    }

    static func stripANSI(_ text: String) -> String {
        text.replacingOccurrences(of: #"\u{1B}\[[0-9;?]*[A-Za-z]"#, with: "", options: .regularExpression)
    }

    static func lastLine(of output: String) -> String? {
        output.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .last(where: { !$0.isEmpty })
            .map { String($0.prefix(300)) }
    }

    /// Opens a pasted callback address with no cookies (the whole point: the browser's cookies were
    /// what made it fail) and returns the HTTP status.
    @Sendable static func replay(_ url: URL) async throws -> Int {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.timeoutIntervalForRequest = 15
        let session = URLSession(configuration: configuration)
        defer { session.finishTasksAndInvalidate() }
        let (_, response) = try await session.data(from: url)
        return (response as? HTTPURLResponse)?.statusCode ?? 0
    }
}

// MARK: - The real process

final class SystemSignInProcess: SignInProcess {
    private let process: Process
    private let input: FileHandle

    init(process: Process, input: FileHandle) {
        self.process = process
        self.input = input
    }

    func write(_ text: String) throws {
        guard process.isRunning else { throw CocoaError(.fileWriteUnknown) }
        try input.write(contentsOf: Data(text.utf8))
    }

    func terminate() {
        guard process.isRunning else { return }
        SystemProcessRunner.terminateProcessTree(rootPID: process.processIdentifier)
        process.terminate()
    }
}

struct SystemSignInLauncher: SignInLaunching {
    func launch(
        executable: String,
        arguments: [String],
        environment: [String: String],
        onOutput: @escaping @Sendable (String) -> Void,
        onExit: @escaping @Sendable (Int32) -> Void
    ) throws -> any SignInProcess {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.environment = environment
        let stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
        // A code pasted after the CLI quit must fail the write, not SIGPIPE the whole app.
        _ = fcntl(stdin.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr
        for pipe in [stdout, stderr] {
            pipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if data.isEmpty {
                    handle.readabilityHandler = nil
                } else {
                    onOutput(String(decoding: data, as: UTF8.self))
                }
            }
        }
        process.terminationHandler = { process in onExit(process.terminationStatus) }
        // Arg values carry no secrets here, but keep the runner's convention: basename + count only.
        AppLog.debug(.subprocess, "launch \((executable as NSString).lastPathComponent) (\(arguments.count) args)")
        try process.run()
        return SystemSignInProcess(process: process, input: stdin.fileHandleForWriting)
    }
}
