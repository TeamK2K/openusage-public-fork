import Darwin
import Foundation

// MARK: - The real login process behind `AccountSignIn`

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
    /// How long a finished login may still hold its output open (a helper it started keeping the pipe)
    /// before the exit is reported anyway.
    var drainLimit: DispatchTimeInterval = .seconds(2)

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
        // The exit waits for both pipes' last output, so the sign-in never handles the exit before the
        // final lines (the error, or the end of the link) have arrived.
        let exit = ExitAfterDrain(openPipes: 2, onExit: onExit)
        for pipe in [stdout, stderr] {
            pipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if data.isEmpty {
                    handle.readabilityHandler = nil
                    exit.pipeClosed()
                } else {
                    onOutput(String(decoding: data, as: UTF8.self))
                }
            }
        }
        let drainLimit = drainLimit
        process.terminationHandler = { process in exit.exited(process.terminationStatus, drainLimit: drainLimit) }
        // Arg values carry no secrets here, but keep the runner's convention: basename + count only.
        AppLog.debug(.subprocess, "launch \((executable as NSString).lastPathComponent) (\(arguments.count) args)")
        try process.run()
        return SystemSignInProcess(process: process, input: stdin.fileHandleForWriting)
    }
}

/// Reports a login's exit once, after it exited and every output pipe reached its end — or `drainLimit`
/// after the exit when a pipe stays open.
final class ExitAfterDrain: @unchecked Sendable {
    private let lock = NSLock()
    private var openPipes: Int
    private var status: Int32?
    private var reported = false
    private let onExit: @Sendable (Int32) -> Void

    init(openPipes: Int, onExit: @escaping @Sendable (Int32) -> Void) {
        self.openPipes = openPipes
        self.onExit = onExit
    }

    func pipeClosed() {
        report(lock.withLock { () -> Int32? in
            openPipes -= 1
            return takeIfReady(force: false)
        })
    }

    func exited(_ code: Int32, drainLimit: DispatchTimeInterval) {
        report(lock.withLock { () -> Int32? in
            status = code
            return takeIfReady(force: false)
        })
        DispatchQueue.global().asyncAfter(deadline: .now() + drainLimit) { [self] in
            let late = lock.withLock { takeIfReady(force: true) }
            if late != nil {
                AppLog.warn(.subprocess, "sign-in login exited but kept its output open; reporting the exit anyway")
            }
            report(late)
        }
    }

    /// Call with `lock` held.
    private func takeIfReady(force: Bool) -> Int32? {
        guard !reported, let status, force || openPipes <= 0 else { return nil }
        reported = true
        return status
    }

    private func report(_ code: Int32?) {
        if let code { onExit(code) }
    }
}
