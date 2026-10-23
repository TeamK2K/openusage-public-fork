import Foundation
import Network

/// Resumes a continuation at most once, whichever callback gets there first.
private final class ResumeOnce<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, Error>?

    init(_ continuation: CheckedContinuation<T, Error>) { self.continuation = continuation }

    func resume(_ result: Result<T, Error>) {
        let pending = lock.withLock { () -> CheckedContinuation<T, Error>? in
            defer { continuation = nil }
            return continuation
        }
        pending?.resume(with: result)
    }
}

/// A raw HTTP/1.1 exchange over loopback TCP, so a test controls every header (`Host` included, which
/// URLSession won't let a caller set) and how the request is split into writes.
enum RawHTTP {
    struct Answer {
        let status: Int
        /// Lowercased names.
        let headers: [String: String]
        let body: Data

        var json: [String: Any]? { (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] }
    }

    /// A request head plus body; `nil` headers are left out.
    static func request(
        _ method: String, _ path: String, host: String?, origin: String? = nil, contentType: String? = nil,
        body: String = "", contentLength: Int? = nil
    ) -> String {
        var head = "\(method) \(path) HTTP/1.1\r\n"
        if let host { head += "Host: \(host)\r\n" }
        if let origin { head += "Origin: \(origin)\r\n" }
        if let contentType { head += "Content-Type: \(contentType)\r\n" }
        head += "Content-Length: \(contentLength ?? body.utf8.count)\r\n\r\n"
        return head + body
    }

    /// Sends `chunks` as separate writes (`gap` apart, so they reach the server as separate reads) and
    /// reads the answer until the server closes the connection.
    static func exchange(port: UInt16, chunks: [String], gap: Duration = .milliseconds(50)) async throws -> Answer {
        let connection = NWConnection(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!, using: .tcp)
        defer { connection.cancel() }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let once = ResumeOnce(continuation)
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready: once.resume(.success(()))
                case .failed(let error), .waiting(let error): once.resume(.failure(error))
                default: break
                }
            }
            connection.start(queue: DispatchQueue(label: "raw-http-client"))
        }
        for (index, chunk) in chunks.enumerated() {
            if index > 0 { try await Task.sleep(for: gap) }
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                connection.send(content: Data(chunk.utf8), completion: .contentProcessed { error in
                    if let error { continuation.resume(throwing: error) } else { continuation.resume() }
                })
            }
        }
        var received = Data()
        while true {
            let (data, done) = await receive(connection)
            received += data
            if done { break }
        }
        return parse(received)
    }

    /// One read; `done` once the server closed (or reset) the connection.
    private static func receive(_ connection: NWConnection) async -> (Data, Bool) {
        await withCheckedContinuation { continuation in
            connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { data, _, isComplete, error in
                continuation.resume(returning: (data ?? Data(), isComplete || error != nil))
            }
        }
    }

    private static func parse(_ data: Data) -> Answer {
        guard let split = data.range(of: Data("\r\n\r\n".utf8)) else { return Answer(status: 0, headers: [:], body: data) }
        let lines = String(decoding: data[..<split.lowerBound], as: UTF8.self).components(separatedBy: "\r\n")
        let status = lines.first?.split(separator: " ").dropFirst().first.flatMap { Int($0) } ?? 0
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            headers[line[..<colon].lowercased()] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        return Answer(status: status, headers: headers, body: data.subdata(in: split.upperBound..<data.count))
    }
}

/// A tiny HTTP server on a free loopback port that records each request's path and answers it with
/// `answer(path, port)` (a whole raw response).
final class StubHTTPServer: @unchecked Sendable {
    private let lock = NSLock()
    private var paths: [String] = []
    private let listener: NWListener
    private let queue = DispatchQueue(label: "stub-http-server")
    private let answer: @Sendable (String, UInt16) -> String

    var requests: [String] { lock.withLock { paths } }
    var port: UInt16 { listener.port?.rawValue ?? 0 }

    init(answer: @escaping @Sendable (String, UInt16) -> String) throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: .any)
        listener = try NWListener(using: parameters)
        self.answer = answer
    }

    func start() async throws {
        listener.newConnectionHandler = { [weak self] connection in self?.serve(connection) }
        let listener = listener
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let once = ResumeOnce(continuation)
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready: once.resume(.success(()))
                case .failed(let error): once.resume(.failure(error))
                default: break
                }
            }
            listener.start(queue: queue)
        }
    }

    func stop() { listener.cancel() }

    private func serve(_ connection: NWConnection) {
        connection.start(queue: queue)
        read(connection, buffered: Data())
    }

    private func read(_ connection: NWConnection, buffered: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            let buffered = buffered + (data ?? Data())
            guard let end = buffered.range(of: Data("\r\n\r\n".utf8)) else {
                if isComplete || error != nil { connection.cancel() } else { self.read(connection, buffered: buffered) }
                return
            }
            let line = String(decoding: buffered[..<end.lowerBound], as: UTF8.self).components(separatedBy: "\r\n").first ?? ""
            let path = line.split(separator: " ").dropFirst().first.map(String.init) ?? ""
            self.lock.withLock { self.paths.append(path) }
            connection.send(content: Data(self.answer(path, self.port).utf8), completion: .contentProcessed { _ in
                connection.cancel()
            })
        }
    }
}
