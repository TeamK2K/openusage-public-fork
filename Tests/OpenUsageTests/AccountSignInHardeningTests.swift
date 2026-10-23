import XCTest
@testable import OpenUsage

/// The sign-in link Codex prints: its return address is its own helper at localhost:1455.
extension AccountSignInTests {
    static let codexLink = "https://auth.openai.com/oauth/authorize?response_type=code&client_id=app_x"
        + "&redirect_uri=http%3A%2F%2Flocalhost%3A1455%2Fauth%2Fcallback&state=s1"

    /// The process hooks hop to the main actor; give those hops a chance to run.
    private func settleHere(until done: () -> Bool) async {
        for _ in 0..<500 where !done() { await Task.yield() }
    }

    // MARK: The sign-in link

    func testALinkSplitAcrossReadsIsShownOnlyOnceWhole() async throws {
        let signIn = makeSignIn()
        try signIn.add(.claude)
        let launch = try XCTUnwrap(launcher.launches.first)
        launch.output("If the browser didn't open, visit: https://claude.ai/oauth/auth")
        await settleHere { false }
        XCTAssertNil(signIn.status.url, "half a link is never shown")
        launch.output("orize?code=true&state=abc")
        await settleHere { false }
        XCTAssertNil(signIn.status.url)
        launch.output("\nPaste code here if prompted > ")
        await settleHere { signIn.status.url != nil }
        XCTAssertEqual(signIn.status.url, "https://claude.ai/oauth/authorize?code=true&state=abc")
    }

    func testALinkEndingTheOutputCountsOnceTheLoginEnded() {
        XCTAssertNil(AccountSignIn.firstSignInURL(in: "visit: https://x.test/a?b=c"))
        XCTAssertEqual(AccountSignIn.firstSignInURL(in: "visit: https://x.test/a?b=c", ended: true), "https://x.test/a?b=c")
        XCTAssertEqual(AccountSignIn.firstSignInURL(in: "visit: \"https://x.test/a\""), "https://x.test/a")
    }

    // MARK: How it ends

    func testALoginThatAddsNoCardFailsWithAFriendlyMessage() async throws {
        addsCard = false
        let signIn = makeSignIn()
        try signIn.add(.claude)
        launcher.launches[0].exit(0)
        await settleHere { signIn.status.phase != .waiting }
        XCTAssertEqual(signIn.status.phase, .failed)
        XCTAssertEqual(
            signIn.status.message,
            "Signed in, but no new account was found. It may already be on the page, or the login wasn't saved."
        )
        XCTAssertEqual(signedIn.count, 1, "the app still looked for the account")
        XCTAssertNoThrow(try signIn.add(.codex), "the slot is free again")
    }

    func testCancelAnswersPlainIdleOverHTTP() throws {
        let signIn = makeSignIn()
        try signIn.add(.claude)
        let (status, json) = try call(signIn, "POST", "/v1/accounts/signin/cancel", "{}")
        XCTAssertEqual(status, 200)
        XCTAssertEqual(json["phase"] as? String, "idle")
        XCTAssertNil(json["message"], "a message would keep the page's dialog open")
    }

    // MARK: Pasted addresses

    func testOnlyTheSignInsOwnReturnAddressIsOpened() throws {
        let link = Self.codexLink
        let own = "http://localhost:1455/auth/callback?code=xyz&state=s1"
        XCTAssertEqual(SignInCallback.classify(own, signInURL: link), .callback(try XCTUnwrap(URL(string: own))))
        XCTAssertEqual(SignInCallback.classify("abc#def", signInURL: link), .code)
        for foreign in [
            "http://localhost:1456/auth/callback?code=xyz&state=s1",     // another port
            "http://localhost:1455/admin?code=xyz&state=s1",             // another path
            "http://127.0.0.1:1455/auth/callback?code=xyz&state=s1",     // another host name
            "https://localhost:1455/auth/callback?code=xyz&state=s1",    // another scheme
            "http://localhost:1455/auth/callback?state=s1",              // no code
            "http://localhost:1455/auth/callback?code=xyz",              // no state
            "http://localhost:1455/auth/callback?code=xyz&state=other",  // not this sign-in's state
            "http://me@localhost:1455/auth/callback?code=xyz&state=s1",  // credentials in the address
            "http://example.com/callback?code=xyz&state=s1",
        ] {
            XCTAssertEqual(SignInCallback.classify(foreign, signInURL: link), .foreign, foreign)
        }
        // No link printed yet, a link whose return address isn't on this Mac, or one naming this app's own
        // port: nothing is ever opened.
        XCTAssertEqual(SignInCallback.classify(own, signInURL: nil), .foreign)
        let console = "https://claude.ai/oauth/authorize?code=true&redirect_uri=https%3A%2F%2Fconsole.anthropic.com%2Foauth%2Fcode%2Fcallback&state=s1"
        XCTAssertNil(SignInCallback.callback("https://console.anthropic.com/oauth/code/callback?code=a&state=s1", signInURL: console))
        let selfLink = "https://x.test/authorize?redirect_uri=http%3A%2F%2F127.0.0.1%3A6736%2Fv1%2Faccounts%2Fadd&state=s1"
        XCTAssertNil(SignInCallback.callback("http://127.0.0.1:6736/v1/accounts/add?code=a&state=s1", signInURL: selfLink))
    }

    func testAForeignAddressIsRefusedNeitherOpenedNorTyped() async throws {
        let signIn = makeSignIn()
        try signIn.add(.codex)
        let launch = try XCTUnwrap(launcher.launches.first)
        launch.output("navigate to this URL to authenticate: \(Self.codexLink)\n")
        await settleHere { signIn.status.url != nil }

        XCTAssertThrowsError(try signIn.submit(code: "http://127.0.0.1:8080/admin?code=x&state=s1")) {
            XCTAssertEqual($0 as? AccountSignIn.Refusal, .foreignAddress)
        }
        let (status, json) = try call(signIn, "POST", "/v1/accounts/signin/code", #"{"code":"http://localhost:9/x?code=a&state=s1"}"#)
        XCTAssertEqual(status, 400)
        XCTAssertEqual(json["error"] as? String, "bad_callback")
        XCTAssertEqual(json["phase"] as? String, "waiting", "the sign-in keeps running")
        await settleHere { false }
        XCTAssertTrue(replayed.isEmpty)
        XCTAssertTrue(launch.process.written.isEmpty)
    }

    func testTheReplayNeverFollowsARedirect() async throws {
        let stub = try StubHTTPServer { path, port in
            path.hasPrefix("/auth/callback")
                ? "HTTP/1.1 302 Found\r\nLocation: http://127.0.0.1:\(port)/elsewhere\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
                : "HTTP/1.1 200 OK\r\nContent-Length: 2\r\nConnection: close\r\n\r\nok"
        }
        try await stub.start()
        defer { stub.stop() }
        let url = try XCTUnwrap(URL(string: "http://127.0.0.1:\(stub.port)/auth/callback?code=x&state=s1"))
        let status = try await SignInCallback.replay(url)
        XCTAssertEqual(status, 302, "the helper's own answer, not where it points")
        XCTAssertEqual(stub.requests, ["/auth/callback?code=x&state=s1"])
    }

    // MARK: The real login process

    func testTheRealLoginsExitComesAfterItsLastOutput() async throws {
        let box = OutputBox()
        let exited = expectation(description: "exit reported")
        // End-to-end smoke: plenty of output, ending in a link with no line break after it, then an
        // immediate exit. The race it guards is timing-bound; `ExitAfterDrain`'s own test pins the rule.
        let script = "i=0; while [ $i -lt 3000 ]; do echo line-$i-of-filler-text; i=$((i+1)); done; printf 'https://x.test/end'"
        let process = try SystemSignInLauncher().launch(
            executable: "/bin/sh", arguments: ["-c", script], environment: [:],
            onOutput: { box.append($0) },
            onExit: { code in box.exit(code); exited.fulfill() }
        )
        await fulfillment(of: [exited], timeout: 20)
        withExtendedLifetime(process) {}
        XCTAssertEqual(box.exitCode, 0)
        XCTAssertEqual(box.textAtExit?.hasSuffix("line-2999-of-filler-text\nhttps://x.test/end"), true)
    }

    func testAnExitWaitsForBothPipesButNotForever() async {
        let early = OutputBox()
        let drained = ExitAfterDrain(openPipes: 2) { early.exit($0) }
        drained.exited(0, drainLimit: .seconds(30))
        drained.pipeClosed()
        XCTAssertNil(early.exitCode, "one pipe is still open")
        drained.pipeClosed()
        XCTAssertEqual(early.exitCode, 0)

        let held = OutputBox()
        let reported = expectation(description: "reported despite an open pipe")
        let stuck = ExitAfterDrain(openPipes: 2) { held.exit($0); reported.fulfill() }
        stuck.exited(3, drainLimit: .milliseconds(20))
        await fulfillment(of: [reported], timeout: 5)
        XCTAssertEqual(held.exitCode, 3)
    }

    // MARK: Added cards and the main store

    func testAddedCardsShareTheMainStoresCacheSoNeitherOverwritesTheOther() async throws {
        let suite = "AccountSignInTests.cache.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let makeCache = { ProviderSnapshotCache(userDefaults: defaults, storageKey: "snapshots", ttl: 600, now: { Date() }) }
        let cache = makeCache()
        let main = StubAccountProvider(id: "claude", name: "Claude: main@test")
        let mainStore = WidgetDataStore(registry: WidgetRegistry.from([main]), providers: [main], cache: cache, defaults: defaults)
        await mainStore.refreshAll(force: true)

        let added = AddedAccounts(cache: cache, defaults: defaults)
        await added.install([StubAccountProvider(id: "claude@bb", name: "Claude: new@test")], identityKeys: [:])
        // The main store writes again after the added one: both entries must survive.
        await mainStore.refreshAll(force: true)

        let stored = makeCache().loadSnapshots(providerIDs: ["claude", "claude@bb"])
        XCTAssertEqual(Set(stored.keys), ["claude", "claude@bb"])
    }
}

/// Collects a real process's output and what had arrived when its exit was reported.
private final class OutputBox: @unchecked Sendable {
    private let lock = NSLock()
    private var text = ""
    private var exitText: String?
    private var code: Int32?

    func append(_ chunk: String) { lock.withLock { text += chunk } }
    func exit(_ status: Int32) { lock.withLock { code = status; exitText = text } }
    var exitCode: Int32? { lock.withLock { code } }
    var textAtExit: String? { lock.withLock { exitText } }
}
