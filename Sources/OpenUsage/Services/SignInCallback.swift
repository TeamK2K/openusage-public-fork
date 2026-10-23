import Foundation

/// A browser address pasted into Paste Code. When the browser's return to the login CLI's own helper
/// failed (Chrome answers HTTP 431 when localhost cookies are too big), the app opens that address
/// itself, without cookies. Only the exact return address the sign-in link named is ever opened, so a
/// pasted address can't make the app call anything else on this Mac.
enum SignInCallback {
    enum Paste: Equatable {
        /// Not an address: typed into the CLI.
        case code
        /// This sign-in's own return address: opened by the app.
        case callback(URL)
        /// Some other address: refused, never opened or typed.
        case foreign
    }

    private static let loopbackHosts: Set<String> = ["localhost", "127.0.0.1", "::1", "[::1]"]

    /// What `text` is for the sign-in whose link is `signInURL` (the link the CLI printed).
    static func classify(_ text: String, signInURL: String?) -> Paste {
        let lowered = text.lowercased()
        guard lowered.hasPrefix("http://") || lowered.hasPrefix("https://") else { return .code }
        guard let url = callback(text, signInURL: signInURL) else { return .foreign }
        return .callback(url)
    }

    /// `text` when it is the `redirect_uri` the sign-in link names, on this Mac — same scheme, host,
    /// port and path — carrying the `code` and `state` the browser was sent back with (that `state`
    /// being the link's own, when the link has one). Never this app's own port.
    static func callback(_ text: String, signInURL: String?) -> URL? {
        guard let signInURL, let link = URLComponents(string: signInURL),
              let redirectText = link.queryItems?.first(where: { $0.name == "redirect_uri" })?.value,
              let redirect = URLComponents(string: redirectText),
              redirect.scheme?.lowercased() == "http",
              let host = redirect.host?.lowercased(), loopbackHosts.contains(host),
              (redirect.port ?? 80) != Int(LocalUsageServer.port)
        else { return nil }
        guard let pasted = URLComponents(string: text),
              pasted.scheme?.lowercased() == "http",
              pasted.host?.lowercased() == host,
              (pasted.port ?? 80) == (redirect.port ?? 80),
              pasted.path == redirect.path,
              pasted.user == nil, pasted.password == nil,
              let code = query("code", in: pasted), !code.isEmpty,
              let state = query("state", in: pasted), !state.isEmpty
        else { return nil }
        if let expected = query("state", in: link), expected != state { return nil }
        return pasted.url
    }

    private static func query(_ name: String, in components: URLComponents) -> String? {
        components.queryItems?.first(where: { $0.name == name })?.value
    }

    /// Opens a pasted return address with no cookies (the whole point: the browser's cookies were what
    /// made it fail) and no redirects followed, and returns the HTTP status (a redirect's own 3xx).
    @Sendable static func replay(_ url: URL) async throws -> Int {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.timeoutIntervalForRequest = 15
        let session = URLSession(configuration: configuration, delegate: RefuseRedirects(), delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        let (_, response) = try await session.data(from: url)
        return (response as? HTTPURLResponse)?.statusCode ?? 0
    }
}

/// Answers every redirect with "don't follow": the replay talks to the login helper and nothing else.
private final class RefuseRedirects: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest
    ) async -> URLRequest? {
        nil
    }
}
