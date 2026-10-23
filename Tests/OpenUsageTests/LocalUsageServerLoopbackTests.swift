import XCTest
@testable import OpenUsage

/// The real listener on a free loopback port: who may drive the accounts sign-in routes, the usage
/// routes' CORS, and the request-body loop.
@MainActor
final class LocalUsageServerLoopbackTests: XCTestCase {
    private var server: LocalUsageServer!
    private var launcher: FakeLauncher!
    private var port: UInt16 = 0

    override func setUp() async throws {
        launcher = FakeLauncher()
        let signIn = AccountSignIn(
            seats: AccountSeats(home: "/Users/me", files: FakeSeatFiles(existing: [".claude"])),
            launcher: launcher,
            resolveExecutable: { _ in "/opt/bin/claude" },
            environment: { [:] },
            signedOutLocations: { [:] },
            onSignedIn: { _, _ in true }
        )
        server = LocalUsageServer(
            state: { LocalUsageAPI.State(enabledOrderedIDs: [], knownIDs: [], snapshots: [:]) },
            accounts: signIn,
            port: 0
        )
        server.start()
        for _ in 0..<500 where !(server.isListening && server.listeningPort != nil) {
            try await Task.sleep(for: .milliseconds(10))
        }
        port = try XCTUnwrap(server.listeningPort, "the test listener never came up")
    }

    override func tearDown() async throws {
        server.stop()
        server = nil
    }

    private var host: String { "127.0.0.1:\(port)" }
    private var origin: String { "http://127.0.0.1:\(port)" }

    private func send(_ chunks: String...) async throws -> RawHTTP.Answer {
        try await RawHTTP.exchange(port: port, chunks: chunks)
    }

    // MARK: Who may use the sign-in routes

    func testAnotherSitesOriginIsRefused() async throws {
        let answer = try await send(RawHTTP.request(
            "POST", "/v1/accounts/add", host: host, origin: "https://evil.example", contentType: "application/json", body: #"{"tool":"claude"}"#
        ))
        XCTAssertEqual(answer.status, 403)
        XCTAssertEqual(answer.json?["error"] as? String, "forbidden_origin")
        XCTAssertNil(answer.headers["access-control-allow-origin"])
        XCTAssertTrue(launcher.launches.isEmpty, "a refused request starts no login")

        // Its preflight is refused too, and a lookalike of this server's own address is still foreign.
        let preflight = try await send(RawHTTP.request("OPTIONS", "/v1/accounts/add", host: host, origin: "https://evil.example"))
        XCTAssertEqual(preflight.status, 403)
        let otherPort = try await send(RawHTTP.request(
            "POST", "/v1/accounts/signin/cancel", host: host, origin: "http://127.0.0.1:3000", contentType: "application/json", body: "{}"
        ))
        XCTAssertEqual(otherPort.status, 403)
    }

    func testARebindingHostNameIsRefused() async throws {
        for badHost in ["evil.example:\(port)", "127.0.0.1:1", "127.0.0.1"] {
            let answer = try await send(RawHTTP.request("GET", "/v1/accounts/signin", host: badHost))
            XCTAssertEqual(answer.status, 403, badHost)
            XCTAssertEqual(answer.json?["error"] as? String, "forbidden_host", badHost)
        }
        let noHost = try await send(RawHTTP.request("GET", "/v1/accounts/signin", host: nil))
        XCTAssertEqual(noHost.status, 403)
        let post = try await send(RawHTTP.request(
            "POST", "/v1/accounts/add", host: "evil.example:\(port)", contentType: "application/json", body: #"{"tool":"claude"}"#
        ))
        XCTAssertEqual(post.status, 403)
        XCTAssertTrue(launcher.launches.isEmpty)
    }

    func testAPostThatIsntJSONIsRefused() async throws {
        for type in ["text/plain", "application/x-www-form-urlencoded", nil] as [String?] {
            let answer = try await send(RawHTTP.request(
                "POST", "/v1/accounts/add", host: host, origin: origin, contentType: type, body: #"{"tool":"claude"}"#
            ))
            XCTAssertEqual(answer.status, 415, type ?? "no type")
            XCTAssertEqual(answer.json?["error"] as? String, "unsupported_media_type")
        }
        XCTAssertTrue(launcher.launches.isEmpty)
    }

    func testThePagesOwnJSONPostIsAccepted() async throws {
        let answer = try await send(RawHTTP.request(
            "POST", "/v1/accounts/add", host: host, origin: origin, contentType: "application/json", body: #"{"tool":"claude"}"#
        ))
        XCTAssertEqual(answer.status, 202)
        XCTAssertEqual(answer.json?["phase"] as? String, "waiting")
        XCTAssertNil(answer.headers["access-control-allow-origin"], "no other site may read a sign-in answer")
        XCTAssertEqual(launcher.launches.count, 1)

        // `localhost`, a charset parameter, and a same-origin GET (browsers send no Origin) all pass.
        let cancel = try await send(RawHTTP.request(
            "POST", "/v1/accounts/signin/cancel", host: "localhost:\(port)", origin: "http://localhost:\(port)",
            contentType: "application/json; charset=utf-8", body: "{}"
        ))
        XCTAssertEqual(cancel.status, 200)
        let status = try await send(RawHTTP.request("GET", "/v1/accounts/signin", host: host))
        XCTAssertEqual(status.status, 200)
        XCTAssertEqual(status.json?["phase"] as? String, "idle")
    }

    func testUsageRoutesKeepPermissiveCORS() async throws {
        let answer = try await send(RawHTTP.request("GET", "/v1/usage", host: "anything.example", origin: "https://dashboard.example"))
        XCTAssertEqual(answer.status, 200)
        XCTAssertEqual(answer.headers["access-control-allow-origin"], "*")
        let limits = try await send(RawHTTP.request("GET", "/v1/limits", host: host))
        XCTAssertEqual(limits.headers["access-control-allow-origin"], "*")
    }

    // MARK: The request-body loop

    func testABodySplitAcrossTwoWritesIsReadWhole() async throws {
        let body = #"{"code":"abc"}"#
        let head = RawHTTP.request(
            "POST", "/v1/accounts/signin/code", host: host, origin: origin, contentType: "application/json",
            body: "", contentLength: body.utf8.count
        )
        let answer = try await send(head + String(body.prefix(5)), String(body.dropFirst(5)))
        // A half-read body would be malformed JSON (400); the whole one reaches the route (no sign-in yet).
        XCTAssertEqual(answer.status, 409)
        XCTAssertEqual(answer.json?["error"] as? String, "no_sign_in")
    }

    func testABodyOverTheCapIsRefused() async throws {
        let head = RawHTTP.request(
            "POST", "/v1/accounts/signin/code", host: host, origin: origin, contentType: "application/json",
            body: "", contentLength: LocalUsageServer.bodyLimit + 1
        )
        // Refused from the head alone, before any of the body is read.
        let answer = try await send(head)
        XCTAssertEqual(answer.status, 413)
        XCTAssertEqual(answer.json?["error"] as? String, "request_body_too_large")
    }
}
