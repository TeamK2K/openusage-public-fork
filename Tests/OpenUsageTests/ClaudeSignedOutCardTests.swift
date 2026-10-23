import XCTest
@testable import OpenUsage

/// A remembered Claude account that no login holds this launch stays on the page as a "Signed Out"
/// card instead of vanishing, and never reads any other account's credentials.
@MainActor
final class ClaudeSignedOutCardTests: XCTestCase {
    private let home = URL(fileURLWithPath: "/Users/dev")
    private let userA = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
    private let dune = "dddddddd-dddd-dddd-dddd-dddddddddddd|11111111-1111-1111-1111-111111111111"

    private func scratchStore() throws -> ProviderAccountsStore {
        let suite = "ClaudeSignedOutCard.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return ProviderAccountsStore(defaults: defaults)
    }

    private func remember(_ store: ProviderAccountsStore, identity: String, label: String, anchor: String) {
        store.reconcile(with: [ProviderAccountsStore.Observation(
            family: "claude", identityKey: identity, label: label,
            sources: [ProviderAccountSource(kind: .defaultHome, anchor: anchor, holdsDefaultSource: true)]
        )])
    }

    private func assemble(_ store: ProviderAccountsStore, files: FakeFiles, folders: [String] = []) async -> ProviderAccountAssembly {
        let observer = DefaultAccountObserver(
            environment: FakeEnvironment(), files: files, keychain: FakeKeychain(),
            homeDirectory: { [home] in home }
        )
        return await ProviderAccountAssembly.make(
            observer: observer, accountsStore: store,
            listCodexHomeDirectories: { _ in [] },
            listClaudeHomeDirectories: { $0 == "/Users/dev" ? folders : [] },
            listDesktopOrganizationDirectories: { _ in [] }
        )
    }

    private func defaultLogin(_ uuid: String) -> FakeFiles {
        FakeFiles(["/Users/dev/.claude.json": #"{"oauthAccount":{"accountUuid":"\#(uuid)","emailAddress":"now@test"}}"#])
    }

    func testRememberedAccountWithNoLoginBecomesASignedOutCard() async throws {
        let store = try scratchStore()
        remember(store, identity: dune, label: "dune@test (Dune Capital)", anchor: "/Users/dev/.claude")

        // The default home was re-logged to another account since.
        let assembly = await assemble(store, files: defaultLogin(userA))

        XCTAssertEqual(assembly.claudeCards.count, 2)
        let ghost = try XCTUnwrap(assembly.claudeCards.first { $0.identityKey == dune })
        XCTAssertEqual(ghost.id, "claude")
        XCTAssertEqual(ghost.signedOutLocation, "/Users/dev/.claude")
        XCTAssertEqual(ghost.displayName, "Claude: dune@test (Dune Capital)")
        XCTAssertNil(ghost.configDirectory)
        XCTAssertNil(assembly.identityKeysByCard[ghost.id], "a signed-out card has no identity to stamp cached data with")
        let live = try XCTUnwrap(assembly.claudeCards.first { $0.identityKey == userA })
        XCTAssertNil(live.signedOutLocation)
        XCTAssertEqual(assembly.identityKeysByCard[live.id], userA)
    }

    func testSignedOutCardFailsWithItsMessageAndNamesWhereToSignIn() async throws {
        let store = try scratchStore()
        remember(store, identity: dune, label: "dune@test (Dune Capital)", anchor: "/Users/dev/.claude-dune")
        let assembly = await assemble(store, files: defaultLogin(userA))

        let providers = ProviderCatalog.make(
            claudeCards: assembly.claudeCards, claudeIdentityKeys: assembly.identityKeysByCard
        )
        let runtime = try XCTUnwrap(providers.first { $0.provider.id == "claude" })
        let snapshot = await runtime.refresh()

        XCTAssertEqual(runtime.signedOutMessage, "Signed Out. Last signed in at /Users/dev/.claude-dune.")
        guard case .badge(_, let text, _, _) = try XCTUnwrap(snapshot.lines.first) else {
            return XCTFail("expected an error badge")
        }
        XCTAssertEqual(text, runtime.signedOutMessage)
        XCTAssertEqual(snapshot.errorCategory, .notLoggedIn)
        let hasCredentials = await runtime.hasLocalCredentials()
        XCTAssertFalse(hasCredentials)
        let live = try XCTUnwrap(providers.first { $0.provider.id != "claude" && $0.provider.id.hasPrefix("claude@") })
        XCTAssertNil(live.signedOutMessage)
    }

    func testSignedOutCardNamesClaudeDesktopForTheDesktopDataFolder() async throws {
        let store = try scratchStore()
        remember(store, identity: dune, label: "dune@test", anchor: "/Users/dev/Library/Application Support/Claude")

        let assembly = await assemble(store, files: defaultLogin(userA))

        XCTAssertEqual(assembly.claudeCards.first { $0.identityKey == dune }?.signedOutLocation, "Claude Desktop")
    }

    func testSignedOutCardStoreNeverReadsAnyOtherAccountsCredentials() throws {
        let credentials = #"{"claudeAiOauth":{"accessToken":"default-token","expiresAt":4102444800000,"scopes":["user:profile"]}}"#
        let files = FakeFiles(["~/.claude/.credentials.json": credentials])
        let keychain = ServiceKeychain(
            values: ["Claude Code-credentials": credentials],
            currentUserValues: ["Claude Code-credentials": credentials]
        )
        let store = ClaudeAuthStore(
            environment: FakeEnvironment(["CLAUDE_CODE_OAUTH_TOKEN": "env-token"]), files: files, keychain: keychain,
            configDirectory: ClaudeAuthStore.signedOutConfigDirectory
        )

        for load in [store.loadCredentialSet(), store.loadCredentialSet(forceDesktopFallback: true)] {
            XCTAssertTrue(load.candidates.isEmpty)
            XCTAssertEqual(load.desktopStatus, .notChecked)
        }
    }

    func testTombstonedAndObservedAccountsGetNoSignedOutCard() async throws {
        let store = try scratchStore()
        remember(store, identity: dune, label: "dune@test", anchor: "/Users/dev/.claude")
        remember(store, identity: userA, label: "a@test", anchor: "/Users/dev/.claude")
        // userA is logged in at the default home right now; dune is tombstoned.
        let tombstoned = ProviderAccountsStore(defaults: scratchDefaults(from: store, tombstoning: dune))

        let assembly = await assemble(tombstoned, files: defaultLogin(userA))

        XCTAssertTrue(assembly.claudeCards.allSatisfy { $0.signedOutLocation == nil })
        XCTAssertFalse(assembly.claudeCards.contains { $0.identityKey == dune })
    }

    func testOlderRecordWithoutAnOrganizationIsNotAGhostOfItsOrganizationCard() async throws {
        let store = try scratchStore()
        remember(store, identity: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb", label: "b@test", anchor: "/Users/dev/.claude")
        let orgIdentity = "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb|22222222-2222-2222-2222-222222222222"
        let files = FakeFiles([
            "/Users/dev/.claude.json": #"{"oauthAccount":{"accountUuid":"bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb","organizationUuid":"22222222-2222-2222-2222-222222222222","emailAddress":"b@test"}}"#,
        ])

        let assembly = await assemble(store, files: files)

        XCTAssertEqual(assembly.claudeCards.map(\.identityKey), [orgIdentity])
        XCTAssertTrue(assembly.claudeCards.allSatisfy { $0.signedOutLocation == nil })
    }

    func testSingleAccountMachineKeepsTheSingleProviderPath() async throws {
        let store = try scratchStore()

        let assembly = await assemble(store, files: defaultLogin(userA))

        XCTAssertTrue(assembly.claudeCards.isEmpty)
        XCTAssertEqual(assembly.identityKeysByCard["claude"], userA)
    }

    /// A scratch defaults domain holding `store`'s records with one identity tombstoned.
    private func scratchDefaults(from store: ProviderAccountsStore, tombstoning identity: String) -> UserDefaults {
        let suite = "ClaudeSignedOutCard.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        let records = store.records.map { record -> ProviderAccountRecord in
            var record = record
            if record.identityKey == identity { record.removedTombstone = true }
            return record
        }
        defaults.set(try? JSONEncoder().encode(records), forKey: ProviderAccountsStore.storageKey)
        return defaults
    }
}
