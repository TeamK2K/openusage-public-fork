import Foundation
import Network

/// Loopback-only HTTP/1.1 listener for the usage API on `127.0.0.1:6736` (read-only, except the
/// accounts page's sign-in routes in `AccountsAPI`). Starts with
/// the app; when the port is already taken the feature is silently disabled for the session
/// (matching the original app). At most 16 requests are served concurrently — beyond that a
/// connection gets `503 {"error":"server_busy"}` immediately.
@MainActor
final class LocalUsageServer {
    nonisolated static let port: UInt16 = 6736
    private static let maxConcurrentConnections = 16
    /// Browsers send every cookie set for `127.0.0.1` by any local dev server, whatever its port, so
    /// a real Chrome request head runs to tens of KB. 8 KB reset those connections ("This site can't
    /// be reached") while curl worked; this matches Chrome's own 256 KB request-header cap.
    private static let headLimit = 256 * 1024
    private static let receiveChunk = 64 * 1024
    /// The accounts page's POST bodies are a few short JSON fields; a pasted code is far below this.
    static let bodyLimit = 16 * 1024

    private let state: @MainActor () -> LocalUsageAPI.State
    /// The accounts page's sign-in flow (`/v1/accounts/…`); `nil` leaves those routes unserved.
    private let accounts: AccountSignIn?
    /// `port` normally; tests pass 0 for any free port (`listeningPort` then names it).
    private let requestedPort: UInt16
    private let queue = DispatchQueue(label: "openusage.local-api")
    private var listener: NWListener?
    private var activeConnections = 0
    /// True once the listener is bound and accepting; false before that, after a bind failure (the
    /// port taken), or once the listener stops.
    private(set) var isListening = false

    init(
        state: @escaping @MainActor () -> LocalUsageAPI.State,
        accounts: AccountSignIn? = nil,
        port: UInt16 = LocalUsageServer.port
    ) {
        self.state = state
        self.accounts = accounts
        self.requestedPort = port
    }

    /// The port actually bound, once listening.
    var listeningPort: UInt16? { listener?.port?.rawValue }

    func start() {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = NWEndpoint.hostPort(
            host: "127.0.0.1",
            port: NWEndpoint.Port(rawValue: requestedPort) ?? .any
        )

        let listener: NWListener
        do {
            listener = try NWListener(using: parameters)
        } catch {
            AppLog.info(.localAPI, "disabled: \(error.localizedDescription)")
            return
        }

        listener.stateUpdateHandler = { [weak self] state in
            let listening: Bool
            switch state {
            case .ready:
                listening = true
            case .failed(let error):
                // Most commonly the port is already in use — silently disable for this session.
                AppLog.info(.localAPI, "disabled: \(error.localizedDescription)")
                listening = false
            case .waiting, .cancelled:
                listening = false
            default:
                return
            }
            Task { @MainActor in
                self?.isListening = listening
            }
        }
        listener.newConnectionHandler = { connection in
            Task { @MainActor [weak self] in
                self?.accept(connection)
            }
        }
        listener.start(queue: queue)
        self.listener = listener
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private func accept(_ connection: NWConnection) {
        connection.start(queue: queue)
        guard activeConnections < Self.maxConcurrentConnections else {
            Self.send(LocalUsageAPI.busy, over: connection)
            return
        }
        activeConnections += 1
        receiveHead(connection, buffered: Data())
    }

    /// Reads until the end of the request head (`\r\n\r\n`), then its `Content-Length` body (the
    /// accounts page's POSTs; GET/OPTIONS carry none), bounded by `bodyLimit`.
    private func receiveHead(_ connection: NWConnection, buffered: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: Self.receiveChunk) { data, _, isComplete, error in
            Task { @MainActor [weak self] in
                guard let self else {
                    connection.cancel()
                    return
                }
                var buffered = buffered
                if let data {
                    buffered.append(data)
                }
                if let headEnd = buffered.range(of: Data("\r\n\r\n".utf8)) {
                    let head = String(data: buffered[..<headEnd.lowerBound], encoding: .utf8) ?? ""
                    guard let length = Self.contentLength(head) else {
                        self.finish(connection, with: LocalUsageAPI.badRequest)
                        return
                    }
                    guard length <= Self.bodyLimit else {
                        self.finish(connection, with: LocalUsageAPI.bodyTooLarge)
                        return
                    }
                    let received = buffered.count - headEnd.upperBound
                    if received >= length {
                        let body = buffered.subdata(in: headEnd.upperBound..<(headEnd.upperBound + length))
                        self.finish(connection, with: self.route(head: head, body: body))
                    } else if error != nil || isComplete {
                        self.finish(connection, with: nil)
                    } else {
                        self.receiveHead(connection, buffered: buffered)
                    }
                } else if buffered.count >= Self.headLimit {
                    self.finish(connection, with: LocalUsageAPI.headTooLarge)
                } else if error != nil || isComplete {
                    self.finish(connection, with: nil)
                } else {
                    self.receiveHead(connection, buffered: buffered)
                }
            }
        }
    }

    private func route(head: String, body: Data) -> LocalUsageAPI.Response {
        let (method, path) = Self.parseRequestLine(head)
        // Path is secret-free (the loopback API serves only normalized usage); Debug-only. The body
        // (a pasted sign-in code) is never logged.
        AppLog.debug(.localAPI, "\(method) \(path)")
        if let accounts, AccountsAPI.handles(path: path) {
            // Only the page this server serves may drive a sign-in: no other site, no rebound host name.
            if let refusal = AccountsAPI.refusal(method: method, head: head, port: listeningPort ?? requestedPort) {
                return refusal
            }
            return AccountsAPI.respond(method: method, path: path, body: body, signIn: accounts)
        }
        return LocalUsageAPI.respond(method: method, path: path, state: state())
    }

    /// The request's `Content-Length` (0 when absent); `nil` for a malformed value.
    nonisolated static func contentLength(_ head: String) -> Int? {
        guard let raw = headerValues("content-length", in: head).first else { return 0 }
        guard let value = Int(raw), value >= 0 else { return nil }
        return value
    }

    /// Every value of the header `name` (case-insensitive) in the request head, trimmed, in order.
    nonisolated static func headerValues(_ name: String, in head: String) -> [String] {
        head.split(separator: "\r\n").dropFirst().compactMap { line in
            guard let colon = line.firstIndex(of: ":"),
                  line[..<colon].trimmingCharacters(in: .whitespaces).lowercased() == name
            else { return nil }
            return line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
    }

    /// Parse the HTTP request line into `(method, path)`. Tolerates an empty/malformed head: a
    /// request that begins with `\r\n\r\n`, or carries invalid UTF-8 (decoded to `""` at the call
    /// site), yields no request line — which must route to a normal `404` rather than trap. The
    /// previous `head.split(...)[0]` force-index crashed the whole `@MainActor` menu-bar process on
    /// any such loopback payload. `nonisolated` + pure so it's unit-testable without the listener.
    nonisolated static func parseRequestLine(_ head: String) -> (method: String, path: String) {
        guard let requestLine = head.split(separator: "\r\n", maxSplits: 1).first else {
            return ("", "/")
        }
        let parts = requestLine.split(separator: " ")
        let method = parts.indices.contains(0) ? String(parts[0]) : ""
        let path = parts.indices.contains(1) ? String(parts[1]) : "/"
        return (method, path)
    }

    private func finish(_ connection: NWConnection, with response: LocalUsageAPI.Response?) {
        activeConnections -= 1
        if let response {
            Self.send(response, over: connection)
        } else {
            connection.cancel()
        }
    }

    private nonisolated static func send(_ response: LocalUsageAPI.Response, over connection: NWConnection) {
        let reason: String = switch response.status {
        case 200: "OK"
        case 202: "Accepted"
        case 204: "No Content"
        case 400: "Bad Request"
        case 403: "Forbidden"
        case 404: "Not Found"
        case 405: "Method Not Allowed"
        case 409: "Conflict"
        case 413: "Content Too Large"
        case 415: "Unsupported Media Type"
        case 431: "Request Header Fields Too Large"
        case 500: "Internal Server Error"
        case 503: "Service Unavailable"
        default: "OK"
        }
        var head = "HTTP/1.1 \(response.status) \(reason)\r\n"
        if response.allowsAnyOrigin {
            head += "Access-Control-Allow-Origin: *\r\n"
            head += "Access-Control-Allow-Methods: GET, OPTIONS\r\n"
            head += "Access-Control-Allow-Headers: Content-Type\r\n"
        }
        head += "Connection: close\r\n"
        if let body = response.body {
            head += "Content-Type: \(response.contentType)\r\n"
            head += "Content-Length: \(body.count)\r\n\r\n"
            connection.send(content: Data(head.utf8) + body, completion: .contentProcessed { _ in
                connection.cancel()
            })
        } else {
            head += "Content-Length: 0\r\n\r\n"
            connection.send(content: Data(head.utf8), completion: .contentProcessed { _ in
                connection.cancel()
            })
        }
    }
}
