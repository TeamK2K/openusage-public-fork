import CryptoKit
import XCTest
@testable import OpenUsage

/// Sibling Claude Code config folders (`~/.claude-<name>`) becoming their own Claude cards.
@MainActor
final class ClaudeHomeDiscoveryTests: XCTestCase {
    private let home = URL(fileURLWithPath: "/Users/dev")
    private let userA = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
    private let userB = "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"
    private let userC = "cccccccc-cccc-cccc-cccc-cccccccccccc"

    private func state(_ uuid: String, email: String?) -> String {
        let emailPart = email.map { #","emailAddress":"\#($0)""# } ?? ""
        return #"{"oauthAccount":{"accountUuid":"\#(uuid)"\#(emailPart)}}"#
    }

    private func credentials(_ token: String) -> String {
        #"{"claudeAiOauth":{"accessToken":"\#(token)","expiresAt":4102444800000,"scopes":["user:profile"]}}"#
    }

    /// A signed-in folder: state file naming the account plus a credential file.
    private func signedIn(_ folder: String, uuid: String, email: String?, token: String = "tok") -> [String: String] {
        ["/Users/dev/\(folder)/.claude.json": state(uuid, email: email),
         "/Users/dev/\(folder)/.credentials.json": credentials(token)]
    }

    private func scanner(
        environment: [String: String] = [:],
        files: FakeFiles,
        keychain: KeychainAccessing = FakeKeychain(),
        folders: [String]
    ) -> ClaudeHomeScanner {
        ClaudeHomeScanner(
            environment: FakeEnvironment(environment), files: files, keychain: keychain,
            homeDirectory: { [home] in home },
            listDirectories: { $0 == "/Users/dev" ? folders : [] }
        )
    }

    func testSiblingsAreFoundSortedAndSwapBackupAndPlainFoldersAreSkipped() {
        let files = FakeFiles(
            signedIn(".claude-b", uuid: userB, email: "b@test")
                .merging(signedIn(".claude-a", uuid: userA, email: "a@test")) { $1 }
                .merging(signedIn(".claude-swap-backup", uuid: userC, email: "swap@test")) { $1 }
                .merging(signedIn(".config", uuid: userC, email: "plain@test")) { $1 }
        )

        let scanner = scanner(files: files, folders: [".claude-b", ".claude-swap-backup", ".config", ".claude-a"])

        XCTAssertEqual(scanner.candidateDirectories(), ["/Users/dev/.claude-a", "/Users/dev/.claude-b"])
        XCTAssertEqual(scanner.scan().map(\.directory), ["/Users/dev/.claude-a", "/Users/dev/.claude-b"])
        XCTAssertEqual(scanner.scan().map(\.email), ["a@test", "b@test"])
    }

    func testSymlinkedAndFileEntriesAreNeverListed() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let real = root.appendingPathComponent(".claude-real")
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: false)
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent(".claude-link"), withDestinationURL: real
        )
        try Data().write(to: root.appendingPathComponent(".claude-file"))

        let scanner = ClaudeHomeScanner(
            files: FakeFiles(), keychain: FakeKeychain(), homeDirectory: { root }
        )

        XCTAssertEqual(scanner.candidateDirectories(), [real.path])
    }

    func testConfiguredDefaultHomeIsNotASibling() {
        for configured in ["/Users/dev/.claude-work", "~/.claude-work", "/Users/dev/.claude-work/"] {
            let scanner = scanner(
                environment: ["CLAUDE_CONFIG_DIR": " \(configured) "], files: FakeFiles(),
                folders: [".claude-work", ".claude-play"]
            )
            XCTAssertEqual(scanner.candidateDirectories(), ["/Users/dev/.claude-play"], configured)
        }
    }

    func testSiblingHoldingTheDefaultsIdentityOrAnEarlierFolderIdentityIsNotAnotherCard() {
        let files = FakeFiles(
            signedIn(".claude-a", uuid: userA, email: "default@test")
                .merging(signedIn(".claude-b", uuid: userB, email: "b@test")) { $1 }
                .merging(signedIn(".claude-c", uuid: userB, email: "b@test")) { $1 }
        )

        let logins = scanner(files: files, folders: [".claude-a", ".claude-b", ".claude-c"])
            .scan(excludingIdentity: userA)

        XCTAssertEqual(logins.map(\.directory), ["/Users/dev/.claude-b"])
    }

    func testFolderWithoutStateFileAccountOrCredentialsYieldsNoLogin() {
        let files = FakeFiles([
            // credentials but no state file
            "/Users/dev/.claude-nostate/.credentials.json": credentials("tok"),
            // state file without an account
            "/Users/dev/.claude-noaccount/.claude.json": "{}",
            "/Users/dev/.claude-noaccount/.credentials.json": credentials("tok"),
            // unparseable state file
            "/Users/dev/.claude-garbled/.claude.json": "not json",
            "/Users/dev/.claude-garbled/.credentials.json": credentials("tok"),
            // account but no credentials anywhere
            "/Users/dev/.claude-nocreds/.claude.json": state(userA, email: "a@test"),
            // account but an empty access token
            "/Users/dev/.claude-notoken/.claude.json": state(userB, email: "b@test"),
            "/Users/dev/.claude-notoken/.credentials.json": credentials(""),
        ])

        let logins = scanner(
            files: files,
            folders: [".claude-nostate", ".claude-noaccount", ".claude-garbled", ".claude-nocreds",
                      ".claude-notoken", ".claude-empty"]
        ).scan()

        XCTAssertTrue(logins.isEmpty)
    }

    func testKeychainOnlyCredentialsCountButOnlyUnderTheFoldersOwnService() throws {
        let files = FakeFiles(["/Users/dev/.claude-a/.claude.json": state(userA, email: "a@test"),
                               "/Users/dev/.claude-b/.claude.json": state(userB, email: "b@test")])
        let ownService = "Claude Code-credentials-\(Self.hashSuffix("/Users/dev/.claude-a"))"
        let keychain = ServiceKeychain(values: [ownService: credentials("tok"),
                                                "Claude Code-credentials": credentials("default")])

        let logins = scanner(files: files, keychain: keychain, folders: [".claude-a", ".claude-b"]).scan()

        XCTAssertEqual(logins.map(\.directory), ["/Users/dev/.claude-a"])
    }

    func testKeychainServiceMatchesClaudeCodesHashOfTheAbsolutePathAndIsScopedOnly() {
        let directory = "/Users/x/.claude-a"
        let store = ClaudeAuthStore(
            environment: FakeEnvironment(["CLAUDE_CONFIG_DIR": "/Users/x/.claude-other"]),
            files: FakeFiles(), keychain: FakeKeychain(), configDirectory: directory
        )

        XCTAssertEqual(store.claudeHomeOverride(), directory)
        XCTAssertEqual(store.keychainServiceCandidates(),
                       ["Claude Code-credentials-\(Self.hashSuffix(directory))"])
        XCTAssertEqual(
            ClaudeHomeScanner.keychainServices(
                configDirectory: directory, environment: FakeEnvironment(), files: FakeFiles(),
                keychain: FakeKeychain()
            ),
            ["Claude Code-credentials-\(Self.hashSuffix(directory))"]
        )
    }

    func testSiblingStoreNeverReadsTheDefaultLoginOrEnvironmentToken() {
        let files = FakeFiles(["/Users/dev/.claude-a/.credentials.json": credentials("seat")])
        let keychain = ServiceKeychain(currentUserValues: ["Claude Code-credentials": credentials("default")])
        let environment = FakeEnvironment(["CLAUDE_CODE_OAUTH_TOKEN": "env-token"])

        let seat = ClaudeAuthStore(
            environment: environment, files: files, keychain: keychain, configDirectory: "/Users/dev/.claude-a"
        )
        let other = ClaudeAuthStore(
            environment: environment, files: files, keychain: keychain, configDirectory: "/Users/dev/.claude-b"
        )

        XCTAssertEqual(seat.loadCredentialCandidates().map(\.oauth.accessToken), ["seat"])
        XCTAssertTrue(other.loadCredentialCandidates().isEmpty)
    }

    // MARK: - Cards

    private func assemble(
        files: FakeFiles, folders: [String]
    ) async throws -> ProviderAccountAssembly {
        let suite = "ClaudeHomeDiscovery.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        let observer = DefaultAccountObserver(
            environment: FakeEnvironment(), files: files, keychain: FakeKeychain(),
            homeDirectory: { [home] in home }
        )
        return await ProviderAccountAssembly.make(
            observer: observer, accountsStore: ProviderAccountsStore(defaults: defaults),
            listCodexHomeDirectories: { _ in [] },
            listClaudeHomeDirectories: { $0 == "/Users/dev" ? folders : [] },
            listDesktopOrganizationDirectories: { _ in [] }
        )
    }

    func testEachSiblingFolderBecomesItsOwnCardAlongsideTheDefault() async throws {
        var contents = ["/Users/dev/.claude.json": state(userA, email: "default@test")]
        contents.merge(signedIn(".claude-b", uuid: userB, email: "b@test")) { $1 }
        contents.merge(signedIn(".claude-seat", uuid: userC, email: nil)) { $1 }

        let assembly = try await assemble(files: FakeFiles(contents), folders: [".claude-seat", ".claude-b"])

        XCTAssertEqual(assembly.claudeCards.count, 3)
        XCTAssertEqual(assembly.claudeCards.first { $0.identityKey == userA }?.id, "claude")
        let siblings = assembly.claudeCards.filter { $0.configDirectory != nil }
        XCTAssertEqual(siblings.map(\.configDirectory), ["/Users/dev/.claude-b", "/Users/dev/.claude-seat"])
        XCTAssertEqual(siblings.map(\.displayName), ["Claude: b@test", "Claude: seat"])
        XCTAssertTrue(assembly.claudeCards.allSatisfy {
            $0.additionalLogDirectories == ["/Users/dev/.claude-b", "/Users/dev/.claude-seat"]
        })
        for card in assembly.claudeCards {
            XCTAssertEqual(assembly.identityKeysByCard[card.id], card.identityKey)
        }

        let providers = ProviderCatalog.make(claudeCards: assembly.claudeCards).compactMap { $0 as? ClaudeProvider }
        XCTAssertEqual(
            Set(providers.compactMap(\.authStore.configDirectory)),
            ["/Users/dev/.claude-b", "/Users/dev/.claude-seat"]
        )
    }

    func testSiblingRepeatingTheDefaultAccountKeepsTheSingleDefaultCard() async throws {
        var contents = ["/Users/dev/.claude.json": state(userA, email: "default@test")]
        contents.merge(signedIn(".claude-same", uuid: userA, email: "default@test")) { $1 }

        let assembly = try await assemble(files: FakeFiles(contents), folders: [".claude-same"])

        XCTAssertTrue(assembly.claudeCards.isEmpty)
        XCTAssertEqual(assembly.identityKeysByCard["claude"], userA)
    }

    func testSiblingOnlyMachineStillBuildsACard() async throws {
        let contents = signedIn(".claude-solo", uuid: userB, email: "solo@test")

        let assembly = try await assemble(files: FakeFiles(contents), folders: [".claude-solo"])

        XCTAssertEqual(assembly.claudeCards.map(\.configDirectory), ["/Users/dev/.claude-solo"])
    }

    private static func hashSuffix(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined().prefix(8).description
    }
}

extension ClaudeDesktopAuthStoreTests {
    @MainActor
    func testSiblingFolderWithADesktopOrganizationsIdentityTakesOverThatCard() async throws {
        let fixture = try makeFixture(
            activeOrganization: otherOrganization,
            v2: [
                cacheKey(organization: organization): tokenEntry("personal-token", expiresIn: 3_600),
                cacheKey(organization: otherOrganization): tokenEntry("work-token", expiresIn: 3_600),
            ],
            accountUUID: accountUUID
        )
        let siblingIdentity = "\(accountUUID)|\(organization)"
        let seat = "\(home.path)/.claude-seat"
        fixture.files.files["\(home.path)/.claude.json"] =
            #"{"oauthAccount":{"accountUuid":"\#(accountUUID)","organizationUuid":"\#(otherOrganization)","emailAddress":"work@example.com","organizationName":"SUNSTORY"}}"#
        fixture.files.files[seat + "/.claude.json"] =
            #"{"oauthAccount":{"accountUuid":"\#(accountUUID)","organizationUuid":"\#(organization)","emailAddress":"seat@example.com"}}"#
        fixture.files.files[seat + "/.credentials.json"] =
            #"{"claudeAiOauth":{"accessToken":"seat-token","expiresAt":4102444800000,"scopes":["user:profile"]}}"#
        let suite = "OpenUsageTests.SiblingTakeover.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let fixtureHome = home
        let observer = DefaultAccountObserver(
            environment: FakeEnvironment(), files: fixture.files, keychain: FakeKeychain(),
            homeDirectory: { fixtureHome }
        )
        let organizations = [organization, otherOrganization]

        let assembly = await ProviderAccountAssembly.make(
            observer: observer, accountsStore: ProviderAccountsStore(defaults: defaults), families: ["claude"],
            listClaudeHomeDirectories: { $0 == fixtureHome.path ? [".claude-seat"] : [] },
            desktop: fixture.store, listDesktopOrganizationDirectories: { _ in organizations }
        )

        XCTAssertEqual(assembly.claudeCards.count, 2)
        let matching = assembly.claudeCards.filter { $0.identityKey == siblingIdentity }
        XCTAssertEqual(matching.count, 1)
        let card = try XCTUnwrap(matching.first)
        XCTAssertEqual(card.configDirectory, seat)
        XCTAssertFalse(card.usesDesktopCredentials)
        XCTAssertEqual(card.organizationID, organization)
        XCTAssertEqual(card.displayName, "Claude: seat@example.com")
        XCTAssertEqual(assembly.identityKeysByCard[card.id], siblingIdentity)

        let providers = ProviderCatalog.make(
            claudeCards: assembly.claudeCards, claudeIdentityKeys: assembly.identityKeysByCard
        ).compactMap { $0 as? ClaudeProvider }
        let store = try XCTUnwrap(providers.first { $0.provider.id == card.id }?.authStore)
        XCTAssertFalse(store.desktopOnly)
        XCTAssertEqual(store.configDirectory, seat)
        XCTAssertEqual(store.desktopOrganization, organization)
        // Same configuration over fixture files: the folder login is read first, and the Desktop
        // token for the same account stays behind it as a fallback.
        let configured = ClaudeAuthStore(
            environment: FakeEnvironment(), files: fixture.files, keychain: FakeKeychain(),
            desktop: fixture.store, desktopOrganization: store.desktopOrganization,
            expectedIdentityKey: store.expectedIdentityKey, desktopOnly: store.desktopOnly,
            preferOrganizationScopedDesktop: store.preferOrganizationScopedDesktop,
            configDirectory: store.configDirectory
        )
        XCTAssertEqual(configured.loadCredentialCandidates().first?.oauth.accessToken, "seat-token")
        fixture.files.files[seat + "/.credentials.json"] = nil
        XCTAssertEqual(configured.loadCredentialCandidates().map(\.oauth.accessToken), ["personal-token"])
    }
}
