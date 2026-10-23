import JavaScriptCore
import XCTest
@testable import OpenUsage

/// In-memory home folder: records every folder and file the seat code makes.
private final class FakeSeatFiles: SeatFileSystem, @unchecked Sendable {
    private let lock = NSLock()
    private var paths: Set<String>
    private(set) var createdDirectories: [String] = []
    private(set) var createdFiles: [String] = []
    let home: String

    init(home: String = "/Users/me", existing: [String] = []) {
        self.home = home
        self.paths = Set(existing.map { home + "/" + $0 })
    }

    func entries(inDirectory path: String) throws -> [String] {
        lock.withLock {
            paths.filter { URL(fileURLWithPath: $0).deletingLastPathComponent().path == path }
                .map { URL(fileURLWithPath: $0).lastPathComponent }
        }
    }

    func exists(_ path: String) -> Bool { lock.withLock { paths.contains(path) } }

    func createPrivateDirectory(_ path: String) throws {
        try lock.withLock {
            guard paths.insert(path).inserted else { throw SeatError.exists(path) }
            createdDirectories.append(path)
        }
    }

    func createEmptyFile(_ path: String) throws {
        lock.withLock {
            paths.insert(path)
            createdFiles.append(path)
        }
    }
}

@MainActor
private final class FakeProcess: SignInProcess {
    var written: [String] = []
    var terminated = false
    func write(_ text: String) throws { written.append(text) }
    func terminate() { terminated = true }
}

@MainActor
private final class FakeLauncher: SignInLaunching {
    struct Launch {
        let executable: String
        let arguments: [String]
        let environment: [String: String]
        let process: FakeProcess
        let output: @Sendable (String) -> Void
        let exit: @Sendable (Int32) -> Void
    }
    var launches: [Launch] = []

    func launch(
        executable: String, arguments: [String], environment: [String: String],
        onOutput: @escaping @Sendable (String) -> Void, onExit: @escaping @Sendable (Int32) -> Void
    ) throws -> any SignInProcess {
        let process = FakeProcess()
        launches.append(Launch(executable: executable, arguments: arguments, environment: environment,
                               process: process, output: onOutput, exit: onExit))
        return process
    }
}

/// Lets the test release the sign-in timeout on demand instead of waiting ten minutes.
private final class TimeoutGate: @unchecked Sendable {
    private let lock = NSLock()
    private var waiters: [CheckedContinuation<Void, Error>] = []

    func sleep(_: Duration) async throws {
        try await withCheckedThrowingContinuation { continuation in
            lock.withLock { waiters.append(continuation) }
        }
    }

    func fire() {
        let pending = lock.withLock { () -> [CheckedContinuation<Void, Error>] in
            defer { waiters.removeAll() }
            return waiters
        }
        pending.forEach { $0.resume() }
    }
}

@MainActor
final class AccountSignInTests: XCTestCase {
    private var files: FakeSeatFiles!
    private var launcher: FakeLauncher!
    private var gate: TimeoutGate!
    private var signedIn: [(SeatTool, String)] = []
    private var replayed: [URL] = []
    private var signedOut: [String: String] = [:]
    private var executables: [SeatTool: String] = [.claude: "/opt/bin/claude", .codex: "/opt/bin/codex"]

    override func setUp() async throws {
        files = FakeSeatFiles(existing: [".claude", ".codex", ".claude-seat1", ".codex-seat3", ".claude-work"])
        launcher = FakeLauncher()
        gate = TimeoutGate()
        signedIn = []
        replayed = []
        signedOut = [:]
    }

    private func makeSignIn() -> AccountSignIn {
        let gate = gate!
        return AccountSignIn(
            seats: AccountSeats(home: files.home, files: files),
            launcher: launcher,
            resolveExecutable: { [unowned self] in self.executables[$0] },
            environment: { ["PATH": "/opt/bin", "ANTHROPIC_API_KEY": "sk-test", "CODEX_HOME": "/elsewhere", "HOME": "/Users/me"] },
            signedOutLocations: { [unowned self] in self.signedOut },
            onSignedIn: { [unowned self] tool, folder in self.signedIn.append((tool, folder)) },
            replayCallback: { @MainActor [unowned self] url in self.replayed.append(url); return 200 },
            sleep: { try await gate.sleep($0) },
            now: { Date(timeIntervalSince1970: 1_800_000_000) }
        )
    }

    /// The process hooks hop to the main actor; give those hops a chance to run.
    private func settle(until done: () -> Bool) async {
        for _ in 0..<500 where !done() { await Task.yield() }
    }

    // MARK: Seat naming (machine-config `seat add`)

    func testNextSeatNameIsOnePastTheHighestAcrossBothTools() throws {
        let seats = AccountSeats(home: files.home, files: files)
        XCTAssertEqual(try seats.nextFreeName(), "seat4")
        XCTAssertEqual(try AccountSeats(home: "/Users/me", files: FakeSeatFiles(existing: [".claude"])).nextFreeName(), "seat1")
        // Folders that only look like seats don't count.
        let lookalikes = FakeSeatFiles(existing: [".claude-seat", ".claude-seatx", ".codex-seat2a", ".claude-myseat9"])
        XCTAssertEqual(try AccountSeats(home: "/Users/me", files: lookalikes).nextFreeName(), "seat1")
    }

    func testCreateMakesTheFolderAndMarkerAndRefusesAnExistingOne() throws {
        let seats = AccountSeats(home: files.home, files: files)
        XCTAssertEqual(try seats.create(.codex, name: "seat4"), "/Users/me/.codex-seat4")
        XCTAssertEqual(files.createdDirectories, ["/Users/me/.codex-seat4"])
        XCTAssertEqual(files.createdFiles, ["/Users/me/.codex-seat4/.seat"])
        XCTAssertThrowsError(try seats.create(.claude, name: "seat1")) { XCTAssertEqual($0 as? SeatError, .exists("/Users/me/.claude-seat1")) }
        XCTAssertThrowsError(try seats.create(.claude, name: "-bad")) { XCTAssertEqual($0 as? SeatError, .badName("-bad")) }
    }

    func testRealSeatFolderIsPrivateWithAnEmptyMarker() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("seat-\(UUID().uuidString)").path
        try FileManager.default.createDirectory(atPath: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: home) }
        let folder = try AccountSeats(home: home).create(.claude, name: "seat1")
        let mode = try FileManager.default.attributesOfItem(atPath: folder)[.posixPermissions] as? Int
        XCTAssertEqual(mode, 0o700)
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: folder + "/.seat")), Data())
    }

    func testSignedOutLocationNamesItsSeatOnlyForAClaudeSeatFolder() {
        let seats = AccountSeats(home: "/Users/me", files: files)
        XCTAssertEqual(seats.claudeSeat(forSignedOutLocation: "~/.claude-seat2"), "seat2")
        XCTAssertEqual(seats.claudeSeat(forSignedOutLocation: "/Users/me/.claude-work"), "work")
        XCTAssertNil(seats.claudeSeat(forSignedOutLocation: "~/.claude"))
        XCTAssertNil(seats.claudeSeat(forSignedOutLocation: "Claude Desktop"))
        XCTAssertNil(seats.claudeSeat(forSignedOutLocation: "/tmp/.claude-seat2"))
        XCTAssertNil(seats.claudeSeat(forSignedOutLocation: "~/.claude-swap-backup"))
    }

    // MARK: The sign-in flow

    func testAddAccountCreatesTheSeatAndRunsTheLoginScopedToIt() async throws {
        let signIn = makeSignIn()
        try signIn.add(.claude)

        XCTAssertEqual(files.createdDirectories, ["/Users/me/.claude-seat4"])
        let launch = try XCTUnwrap(launcher.launches.first)
        XCTAssertEqual(launch.executable, "/opt/bin/claude")
        XCTAssertEqual(launch.arguments, ["auth", "login"])
        XCTAssertEqual(launch.environment["CLAUDE_CONFIG_DIR"], "/Users/me/.claude-seat4")
        XCTAssertNil(launch.environment["ANTHROPIC_API_KEY"], "a key in the environment would skip the browser login")
        XCTAssertNil(launch.environment["CODEX_HOME"])
        XCTAssertEqual(launch.environment["PATH"], "/opt/bin")
        XCTAssertEqual(signIn.status.phase, .waiting)
        XCTAssertEqual(signIn.status.folder, "~/.claude-seat4")
        XCTAssertEqual(signIn.status.message, "Waiting for sign-in…")

        launch.output("\u{1B}[1mOpening browser…\u{1B}[0m\nIf the browser didn't open, visit: https://claude.ai/oauth/authorize?code=true&state=abc\n")
        await settle { signIn.status.url != nil }
        XCTAssertEqual(signIn.status.url, "https://claude.ai/oauth/authorize?code=true&state=abc")

        try signIn.submit(code: "  abc#def \n")
        XCTAssertEqual(launch.process.written, ["abc#def\n"])

        launch.exit(0)
        await settle { signIn.status.phase == .succeeded }
        XCTAssertEqual(signIn.status.phase, .succeeded)
        XCTAssertEqual(signedIn.map(\.1), ["/Users/me/.claude-seat4"])
    }

    func testCodexLoginUsesCodexHome() throws {
        let signIn = makeSignIn()
        try signIn.add(.codex)
        let launch = try XCTUnwrap(launcher.launches.first)
        XCTAssertEqual(launch.arguments, ["login"])
        XCTAssertEqual(launch.environment["CODEX_HOME"], "/Users/me/.codex-seat4")
        XCTAssertNil(launch.environment["CLAUDE_CONFIG_DIR"])
    }

    func testOneSignInAtATime() throws {
        let signIn = makeSignIn()
        try signIn.add(.claude)
        XCTAssertThrowsError(try signIn.add(.codex)) { XCTAssertEqual($0 as? AccountSignIn.Refusal, .busy) }
        XCTAssertEqual(launcher.launches.count, 1)
        XCTAssertEqual(files.createdDirectories.count, 1, "a refused Add Account makes no folder")
    }

    func testMissingCLIFailsWithoutMakingAFolder() {
        executables[.codex] = nil
        let signIn = makeSignIn()
        XCTAssertThrowsError(try signIn.add(.codex)) { XCTAssertEqual($0 as? AccountSignIn.Refusal, .startFailed) }
        XCTAssertEqual(signIn.status.phase, .failed)
        XCTAssertTrue(signIn.status.message?.contains("isn't installed") == true)
        XCTAssertTrue(files.createdDirectories.isEmpty)
        XCTAssertTrue(launcher.launches.isEmpty)
    }

    func testFailedLoginShowsItsLastLine() async throws {
        let signIn = makeSignIn()
        try signIn.add(.claude)
        let launch = try XCTUnwrap(launcher.launches.first)
        launch.output("Error: OAuth error: invalid code\n")
        await settle { false }
        launch.exit(1)
        await settle { signIn.status.phase == .failed }
        XCTAssertEqual(signIn.status.phase, .failed)
        XCTAssertEqual(signIn.status.message, "Sign-in didn't finish (claude exited with code 1): Error: OAuth error: invalid code")
        XCTAssertTrue(signedIn.isEmpty)
    }

    func testTimeoutStopsTheLogin() async throws {
        let signIn = makeSignIn()
        try signIn.add(.claude)
        let process = try XCTUnwrap(launcher.launches.first?.process)
        await settle { false }
        gate.fire()
        await settle { signIn.status.phase == .failed }
        XCTAssertTrue(process.terminated)
        XCTAssertTrue(signIn.status.message?.contains("timed out") == true)
        // The killed process exiting afterwards changes nothing.
        launcher.launches[0].exit(15)
        await settle { false }
        XCTAssertTrue(signIn.status.message?.contains("timed out") == true)
    }

    func testCancelStopsTheLoginAndFreesTheSlot() throws {
        let signIn = makeSignIn()
        try signIn.add(.claude)
        signIn.cancel()
        XCTAssertTrue(try XCTUnwrap(launcher.launches.first).process.terminated)
        XCTAssertEqual(signIn.status.phase, .idle)
        XCTAssertNoThrow(try signIn.add(.codex))
    }

    func testPastingAFailedLocalhostPageReplaysItInsteadOfTypingIt() async throws {
        let signIn = makeSignIn()
        try signIn.add(.codex)
        try signIn.submit(code: "http://localhost:1455/auth/callback?code=xyz&state=s")
        await settle { !replayed.isEmpty }
        XCTAssertEqual(replayed.map(\.absoluteString), ["http://localhost:1455/auth/callback?code=xyz&state=s"])
        XCTAssertTrue(try XCTUnwrap(launcher.launches.first).process.written.isEmpty)
        // Never this app's own port, never another host.
        XCTAssertNil(AccountSignIn.loopbackCallback("http://127.0.0.1:6736/v1/accounts/add"))
        XCTAssertNil(AccountSignIn.loopbackCallback("http://example.com/callback"))
    }

    func testCodeWithNoSignInIsRefused() {
        XCTAssertThrowsError(try makeSignIn().submit(code: "abc")) { XCTAssertEqual($0 as? AccountSignIn.Refusal, .notWaiting) }
    }

    func testSignInReusesTheSignedOutSeatOrMakesANewOne() throws {
        signedOut = ["claude@aa": "~/.claude-seat1", "claude@bb": "Claude Desktop", "claude@cc": "~/.claude-seat7"]
        let signIn = makeSignIn()
        XCTAssertEqual(signIn.status.signInProviderIds, ["claude@aa", "claude@bb", "claude@cc"])

        try signIn.signIn(providerID: "claude@aa")
        XCTAssertTrue(files.createdDirectories.isEmpty, "the seat folder is still there")
        XCTAssertEqual(launcher.launches.last?.environment["CLAUDE_CONFIG_DIR"], "/Users/me/.claude-seat1")
        signIn.cancel()

        try signIn.signIn(providerID: "claude@cc")
        XCTAssertEqual(files.createdDirectories, ["/Users/me/.claude-seat7"], "a removed seat is made again under its name")
        signIn.cancel()

        try signIn.signIn(providerID: "claude@bb")
        XCTAssertEqual(files.createdDirectories.last, "/Users/me/.claude-seat8", "Desktop's login is never replaced: a new seat")
        signIn.cancel()

        XCTAssertThrowsError(try signIn.signIn(providerID: "claude@zz")) {
            XCTAssertEqual($0 as? AccountSignIn.Refusal, .unknownProvider)
        }
    }

    func testFindExecutableSearchesTheLoginShellPathThenInstallFolders() {
        let found = AccountSignIn.findExecutable(
            "claude", path: "/usr/bin:/custom/bin", home: "/Users/me",
            isExecutable: { $0 == "/custom/bin/claude" || $0 == "/Users/me/.local/bin/claude" }
        )
        XCTAssertEqual(found, "/custom/bin/claude")
        XCTAssertEqual(AccountSignIn.findExecutable("claude", path: nil, home: "/Users/me", isExecutable: { $0 == "/Users/me/.local/bin/claude" }),
                       "/Users/me/.local/bin/claude")
        XCTAssertNil(AccountSignIn.findExecutable("codex", path: "/usr/bin", home: "/Users/me", isExecutable: { _ in false }))
    }

    // MARK: HTTP routes

    private func call(_ signIn: AccountSignIn, _ method: String, _ path: String, _ body: String = "") throws -> (Int, [String: Any]) {
        let response = AccountsAPI.respond(method: method, path: path, body: Data(body.utf8), signIn: signIn)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: XCTUnwrap(response.body)) as? [String: Any])
        return (response.status, object)
    }

    func testRoutes() throws {
        signedOut = ["claude@aa": "~/.claude-seat1"]
        let signIn = makeSignIn()

        var (status, json) = try call(signIn, "GET", "/v1/accounts/signin")
        XCTAssertEqual(status, 200)
        XCTAssertEqual(json["phase"] as? String, "idle")
        XCTAssertEqual(json["signInProviderIds"] as? [String], ["claude@aa"])

        (status, json) = try call(signIn, "POST", "/v1/accounts/add", #"{"tool":"cursor"}"#)
        XCTAssertEqual(status, 400)
        XCTAssertEqual(json["error"] as? String, "bad_request")
        (status, _) = try call(signIn, "POST", "/v1/accounts/add", "not json")
        XCTAssertEqual(status, 400)

        (status, json) = try call(signIn, "POST", "/v1/accounts/signin/code", #"{"code":"x"}"#)
        XCTAssertEqual(status, 409)
        XCTAssertEqual(json["error"] as? String, "no_sign_in")

        (status, json) = try call(signIn, "POST", "/v1/accounts/add", #"{"tool":"claude"}"#)
        XCTAssertEqual(status, 202)
        XCTAssertEqual(json["phase"] as? String, "waiting")
        XCTAssertEqual(json["folder"] as? String, "~/.claude-seat4")

        (status, json) = try call(signIn, "POST", "/v1/accounts/signin", #"{"providerId":"claude@aa"}"#)
        XCTAssertEqual(status, 409)
        XCTAssertEqual(json["error"] as? String, "sign_in_in_progress")
        XCTAssertEqual(json["phase"] as? String, "waiting", "the running sign-in is untouched")

        (status, _) = try call(signIn, "POST", "/v1/accounts/signin/code", #"{"code":"abc"}"#)
        XCTAssertEqual(status, 202)
        XCTAssertEqual(launcher.launches.first?.process.written, ["abc\n"])

        (status, json) = try call(signIn, "POST", "/v1/accounts/signin/cancel")
        XCTAssertEqual(status, 200)
        XCTAssertEqual(json["phase"] as? String, "idle")

        (status, json) = try call(signIn, "POST", "/v1/accounts/signin", #"{"providerId":"claude@zz"}"#)
        XCTAssertEqual(status, 404)
        XCTAssertEqual(json["error"] as? String, "provider_not_found")

        (status, _) = try call(signIn, "DELETE", "/v1/accounts/add")
        XCTAssertEqual(status, 405)
        (status, _) = try call(signIn, "GET", "/v1/accounts/nope")
        XCTAssertEqual(status, 404)
        XCTAssertEqual(AccountsAPI.respond(method: "OPTIONS", path: "/v1/accounts/add", body: Data(), signIn: signIn).status, 204)
    }

    func testServerReadsContentLength() {
        XCTAssertTrue(AccountsAPI.handles(path: "/v1/accounts/signin?x=1"))
        XCTAssertFalse(AccountsAPI.handles(path: "/v1/limits"))
        XCTAssertEqual(LocalUsageServer.contentLength("POST /v1/accounts/add HTTP/1.1\r\nHost: x\r\ncontent-length: 17"), 17)
        XCTAssertEqual(LocalUsageServer.contentLength("GET / HTTP/1.1\r\nHost: x"), 0)
        XCTAssertNil(LocalUsageServer.contentLength("POST / HTTP/1.1\r\nContent-Length: -4"))
        XCTAssertNil(LocalUsageServer.contentLength("POST / HTTP/1.1\r\nContent-Length: lots"))
    }

    // MARK: New cards without a restart

    func testPickAddsOnlyAccountsNoLiveLaunchCardShows() {
        let launch: [AddedAccounts.Card] = [
            .init(id: "claude", identityKey: "u1", signedOut: false),
            .init(id: "claude@bb", identityKey: nil, signedOut: true),
            .init(id: "codex", identityKey: "acct-1", signedOut: false),
            .init(id: "cursor", identityKey: nil, signedOut: false),
        ]
        let fresh: [AddedAccounts.Card] = [
            .init(id: "claude@aa", identityKey: "u1", signedOut: false),      // the launch default, new id
            .init(id: "claude@bb", identityKey: "u2", signedOut: false),      // signed out at launch, now back
            .init(id: "claude@cc", identityKey: "u3", signedOut: false),      // a brand-new seat
            .init(id: "claude@dd", identityKey: "u4", signedOut: true),       // still signed out
            .init(id: "codex@ee", identityKey: "acct-1", signedOut: false),   // the launch codex account
            .init(id: "codex@ff", identityKey: "acct-2", signedOut: false),   // a new codex seat
            .init(id: "cursor", identityKey: nil, signedOut: false),
        ]
        XCTAssertEqual(AddedAccounts.pick(fresh: fresh, launch: launch), ["claude@bb", "claude@cc", "codex@ff"])
    }

    func testAddedCardsReplaceTheSignedOutCardInTheAPIState() async throws {
        let provider = StubAccountProvider(id: "claude@bb", name: "Claude: new@test")
        let suite = "AccountSignInTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let added = AddedAccounts()
        await added.install(
            [provider], identityKeys: ["claude@bb": "u2"],
            cache: ProviderSnapshotCache(userDefaults: defaults, storageKey: "snapshots", ttl: 600, now: { Date() }),
            defaults: defaults
        )

        var state = LocalUsageAPI.State(
            enabledOrderedIDs: ["claude"], knownIDs: ["claude", "claude@bb"], snapshots: [:],
            errors: ["claude@bb": "Signed Out. Last signed in at ~/.claude-seat1."]
        )
        added.merge(into: &state)
        XCTAssertEqual(state.enabledOrderedIDs, ["claude", "claude@bb"])
        XCTAssertNil(state.errors["claude@bb"])
        XCTAssertEqual(state.snapshots["claude@bb"]?.displayName, "Claude: new@test")
        XCTAssertEqual(state.displayNames["claude@bb"], "Claude: new@test")
        XCTAssertEqual(added.providerIDs, ["claude@bb"])
    }

    // MARK: The page's time format

    func testPageTimesAreRelativeInOneFormat() throws {
        let page = String(decoding: SeatsPage.html, as: UTF8.self)
        let start = try XCTUnwrap(page.range(of: "// <time-format>"))
        let end = try XCTUnwrap(page.range(of: "// </time-format>"))
        let context = try XCTUnwrap(JSContext())
        context.evaluateScript(String(page[start.lowerBound..<end.lowerBound]))
        func left(_ ms: Double) -> String? { context.objectForKeyedSubscript("left")?.call(withArguments: [ms])?.toString() }
        let minute = 60_000.0, hour = 60 * minute, day = 24 * hour

        XCTAssertEqual(left(45 * minute), "45m")
        XCTAssertEqual(left(2 * hour + 29 * minute), "2h 29m")
        XCTAssertEqual(left(12 * hour + 48 * minute), "12h 48m")
        XCTAssertEqual(left(3 * hour), "3h")
        XCTAssertEqual(left(2 * day + 4 * hour + 20 * minute), "2d 4h", "minutes go once it is a day away")
        XCTAssertEqual(left(6 * day), "6d")
        XCTAssertEqual(left(13 * day + 5 * hour), "13d", "hours go once it is ten days away")
        XCTAssertEqual(left(0), "now")
        let soon = context.evaluateScript("when(Date.now() + \(2 * hour + 29 * minute + 20_000))")?.toString()
        XCTAssertEqual(soon, "in 2h 29m")
        XCTAssertEqual(context.evaluateScript("when(Date.now() - 1000)")?.toString(), "now")
        // No clock times or dates anywhere on the cards.
        XCTAssertFalse(page.contains("toLocaleTimeString"))
        XCTAssertFalse(page.contains("toLocaleDateString"))
    }

    func testPageScriptsParse() throws {
        let page = String(decoding: SeatsPage.html, as: UTF8.self)
        let scripts = page.components(separatedBy: "<script>").dropFirst()
            .map { $0.components(separatedBy: "</script>")[0] }
        XCTAssertEqual(scripts.count, 2)
        for script in scripts {
            let context = try XCTUnwrap(JSContext())
            var thrown: String?
            context.exceptionHandler = { _, exception in thrown = exception?.toString() }
            // Compile only: `new Function` parses the body without running it (no DOM here).
            context.setObject(script, forKeyedSubscript: "source" as NSString)
            context.evaluateScript("new Function(source)")
            XCTAssertNil(thrown)
        }
    }

    func testPageHasTheTopBarAndSignInPanel() throws {
        let page = String(decoding: SeatsPage.html, as: UTF8.self)
        XCTAssertTrue(page.contains(">AI Accounts<"))
        XCTAssertTrue(page.contains(">Add Account<"))
        XCTAssertTrue(page.contains("\"Waiting for sign-in…\""))
        XCTAssertTrue(page.contains(">Paste Code<"))
        XCTAssertTrue(page.contains("\"Sign In\""))
        XCTAssertTrue(page.contains("/v1/accounts/add"))
        XCTAssertTrue(page.contains("/v1/accounts/signin/code"))
        // The sign-in script is appended inside the one document, which it closes.
        XCTAssertTrue(page.hasSuffix("</body>\n</html>"))
        XCTAssertEqual(page.components(separatedBy: "<html").count, 2)
        XCTAssertLessThan(try XCTUnwrap(page.range(of: "function fit()")).lowerBound,
                          try XCTUnwrap(page.range(of: "\nrefresh();")).lowerBound, "the refresh loop starts after both scripts")
    }
}

/// A Claude-family card with a fixed snapshot, for the added-accounts store.
@MainActor
private final class StubAccountProvider: ProviderRuntime {
    let provider: Provider
    init(id: String, name: String) {
        provider = Provider(id: id, displayName: name, icon: .providerMark("claude"))
    }
    var widgetDescriptors: [WidgetDescriptor] { [] }
    func refresh() async -> ProviderSnapshot {
        ProviderSnapshot(providerID: provider.id, displayName: provider.displayName, lines: [
            .progress(label: "Session", used: 10, limit: 100, format: .percent)
        ], refreshedAt: Date())
    }
    func hasLocalCredentials() async -> Bool { true }
}
