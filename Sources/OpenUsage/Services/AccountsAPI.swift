import Foundation

/// The accounts page's sign-in routes under `/v1/accounts` (docs/local-http-api.md): read the sign-in
/// state, Add Account, Sign In on a signed-out card, Paste Code, Cancel. Every answer is the sign-in
/// status JSON, plus an `error` code when the request was refused. No password or token, by the owner's
/// call: instead `refusal` lets only the page this server serves use them (see docs § CORS and privacy).
@MainActor
enum AccountsAPI {
    /// Longest pasted code or callback address accepted.
    static let maxCodeLength = 8 * 1024

    nonisolated static func handles(path: String) -> Bool {
        let segments = path.split(separator: "?", maxSplits: 1).first.map { $0.split(separator: "/") } ?? []
        return segments.count >= 2 && segments[0] == "v1" && segments[1] == "accounts"
    }

    /// Refuses a request that didn't come from the accounts page this server serves on `port`:
    /// a `Host` other than `127.0.0.1:<port>` / `localhost:<port>` (DNS rebinding), an `Origin` other
    /// than that same address (another website), or a POST that isn't `application/json` (a plain form
    /// or `text/plain` post skips the browser's CORS preflight). `nil` lets the request through.
    nonisolated static func refusal(method: String, head: String, port: UInt16) -> LocalUsageAPI.Response? {
        let hosts = ["127.0.0.1:\(port)", "localhost:\(port)"]
        let host = LocalUsageServer.headerValues("host", in: head)
        guard host.count == 1, hosts.contains(host[0].lowercased()) else {
            return refuse(403, "forbidden_host")
        }
        let origin = LocalUsageServer.headerValues("origin", in: head)
        guard origin.isEmpty || (origin.count == 1 && hosts.map { "http://" + $0 }.contains(origin[0].lowercased())) else {
            return refuse(403, "forbidden_origin")
        }
        if method == "POST" {
            let type = LocalUsageServer.headerValues("content-type", in: head)
            let media = type.first?.split(separator: ";", maxSplits: 1).first?.trimmingCharacters(in: .whitespaces).lowercased()
            guard type.count == 1, media == "application/json" else {
                return refuse(415, "unsupported_media_type")
            }
        }
        return nil
    }

    private nonisolated static func refuse(_ status: Int, _ code: String) -> LocalUsageAPI.Response {
        AppLog.warn(.localAPI, "accounts route refused: \(code)")
        return LocalUsageAPI.Response(status: status, body: Data(#"{"error":"\#(code)"}"#.utf8), allowsAnyOrigin: false)
    }

    static func respond(method: String, path: String, body: Data, signIn: AccountSignIn) -> LocalUsageAPI.Response {
        if method == "OPTIONS" { return LocalUsageAPI.Response(status: 204, body: nil, allowsAnyOrigin: false) }
        let route = path.split(separator: "?", maxSplits: 1)[0].split(separator: "/").dropFirst(2).map(String.init)
        let known: [[String]] = [["signin"], ["add"], ["signin", "code"], ["signin", "cancel"]]
        guard known.contains(route) else { return reply(signIn, status: 404, error: "not_found") }

        switch (method, route) {
        case ("GET", ["signin"]):
            return reply(signIn, status: 200)
        case ("POST", ["add"]):
            guard let tool = field("tool", in: body).flatMap(SeatTool.init(rawValue:)) else {
                return reply(signIn, status: 400, error: "bad_request")
            }
            return act(signIn, accepted: 202) { () throws(AccountSignIn.Refusal) in try signIn.add(tool) }
        case ("POST", ["signin"]):
            guard let providerID = field("providerId", in: body), !providerID.isEmpty else {
                return reply(signIn, status: 400, error: "bad_request")
            }
            return act(signIn, accepted: 202) { () throws(AccountSignIn.Refusal) in try signIn.signIn(providerID: providerID) }
        case ("POST", ["signin", "code"]):
            guard let code = field("code", in: body), code.count <= maxCodeLength else {
                return reply(signIn, status: 400, error: "bad_request")
            }
            return act(signIn, accepted: 202) { () throws(AccountSignIn.Refusal) in try signIn.submit(code: code) }
        case ("POST", ["signin", "cancel"]):
            signIn.cancel()
            return reply(signIn, status: 200)
        default:
            return reply(signIn, status: 405, error: "method_not_allowed")
        }
    }

    private static func act(
        _ signIn: AccountSignIn,
        accepted: Int,
        _ action: () throws(AccountSignIn.Refusal) -> Void
    ) -> LocalUsageAPI.Response {
        do {
            try action()
            return reply(signIn, status: accepted)
        } catch {
            return switch error {
            case .busy: reply(signIn, status: 409, error: "sign_in_in_progress", message: "Another sign-in is still running. Finish or cancel it first.")
            case .notWaiting: reply(signIn, status: 409, error: "no_sign_in", message: "No sign-in is waiting for a code.")
            case .unknownProvider: reply(signIn, status: 404, error: "provider_not_found", message: "That account isn't signed out, so there's nothing to sign in.")
            case .emptyCode: reply(signIn, status: 400, error: "bad_request", message: "Paste the code first.")
            case .foreignAddress: reply(signIn, status: 400, error: "bad_callback", message: "That address isn't this sign-in's own return address, so OpenUsage didn't open it. Paste the code instead.")
            case .startFailed: reply(signIn, status: 500, error: "sign_in_failed")
            }
        }
    }

    /// The status JSON. A refusal that leaves a sign-in running keeps that sign-in's state and carries
    /// its own `message` (the page shows it as a notice); a failed start already wrote its message.
    private static func reply(
        _ signIn: AccountSignIn, status code: Int, error: String? = nil, message: String? = nil
    ) -> LocalUsageAPI.Response {
        var status = signIn.status
        status.error = error
        if let message { status.message = message }
        let body = (try? JSONEncoder().encode(status)) ?? Data(#"{"error":"encoding_failed"}"#.utf8)
        return LocalUsageAPI.Response(status: code, body: body, allowsAnyOrigin: false)
    }

    /// One string field of a JSON object body; `nil` for anything else (the 400 path).
    private static func field(_ name: String, in body: Data) -> String? {
        guard let object = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] else { return nil }
        return object[name] as? String
    }
}

/// Accounts signed in from the accounts page this session. They aren't in the launch registry, so a
/// second `WidgetDataStore` refreshes them (the same refresh, cache, timeout and error rules) and the
/// local API merges them in; the menu-bar panel picks them up on the next launch. Swapping the panel's
/// own registry in place would touch the layout, enablement and every observing view, so it isn't done.
@MainActor
final class AddedAccounts {
    /// One account card as the pick sees it: no runtime needed, so the rule is testable on its own.
    struct Card: Equatable, Sendable {
        let id: String
        let identityKey: String?
        let signedOut: Bool
    }

    private(set) var store: WidgetDataStore?
    private var registry: WidgetRegistry?
    /// The main store's cache instance: its snapshots live in one UserDefaults payload, so a second
    /// instance would overwrite the main store's entries with its own (and the other way round).
    private let cache: ProviderSnapshotCache
    private let defaults: UserDefaults

    init(cache: ProviderSnapshotCache, defaults: UserDefaults = .standard) {
        self.cache = cache
        self.defaults = defaults
    }

    var providerIDs: Set<String> { Set(registry?.providers.map(\.id) ?? []) }

    /// Cards to add: Claude/Codex accounts with a login now that no live launch card already shows —
    /// by id, or by account (the launch card for the same account may have another id). A launch card
    /// that was signed out counts as not shown, so its account comes back under the same id.
    static func pick(fresh: [Card], launch: [Card]) -> [String] {
        let live = launch.filter { !$0.signedOut }
        let liveIDs = Set(live.map(\.id))
        let liveIdentities = Set(live.compactMap(\.identityKey))
        return fresh.filter { card in
            ProviderAccountID.families.contains(ProviderAccountID.family(of: card.id))
                && !card.signedOut
                && !liveIDs.contains(card.id)
                && !(card.identityKey.map(liveIdentities.contains) ?? false)
        }.map(\.id)
    }

    static func cards(_ runtimes: [ProviderRuntime], identityKeys: [String: String]) -> [Card] {
        runtimes.map {
            Card(id: $0.provider.id, identityKey: identityKeys[$0.provider.id], signedOut: $0.signedOutMessage != nil)
        }
    }

    /// Re-runs account discovery after a sign-in and installs every newly signed-in card. `false` when
    /// discovery found no new account (the sign-in reports that; it logs it).
    @discardableResult
    func reload(launch: [Card]) async -> Bool {
        let assembly = await ProviderAccountAssembly.make(waitsForLoginShell: true)
        let runtimes = ProviderCatalog.make(
            claudeCards: assembly.claudeCards, codex: assembly.codex, claudeIdentityKeys: assembly.identityKeysByCard
        )
        let added = Set(Self.pick(fresh: Self.cards(runtimes, identityKeys: assembly.identityKeysByCard), launch: launch))
        guard !added.isEmpty else { return false }
        AppLog.info(.config, "accounts page: added \(added.sorted().joined(separator: ", ")) without a restart")
        await install(runtimes.filter { added.contains($0.provider.id) }, identityKeys: assembly.identityKeysByCard)
        return true
    }

    /// Writes through the main store's cache and defaults, so the next launch paints these cards from
    /// what this session fetched.
    func install(_ runtimes: [ProviderRuntime], identityKeys: [String: String]) async {
        let registry = WidgetRegistry.from(runtimes)
        let store = WidgetDataStore(
            registry: registry, providers: runtimes, cache: cache, defaults: defaults,
            providerIdentityKeys: identityKeys.filter { id, _ in registry.provider(id: id) != nil }
        )
        self.registry = registry
        self.store = store
        await store.refreshAll(force: true)
    }

    func refreshAll() async {
        await store?.refreshAll()
    }

    /// Lays the added cards over the launch state: their data and errors replace a signed-out launch
    /// card's "Signed Out", and a brand-new card joins the end of the list.
    func merge(into state: inout LocalUsageAPI.State) {
        guard let registry, let store else { return }
        for provider in registry.providers {
            let id = provider.id
            state.knownIDs.insert(id)
            if !state.enabledOrderedIDs.contains(id) { state.enabledOrderedIDs.append(id) }
            state.snapshots[id] = store.snapshots[id]
            state.errors[id] = store.providerErrors[id]
            state.displayNames[id] = provider.displayName
            state.limitDescriptors[id] = registry.limitDescriptorsByProvider[id]
            state.usageRoseAt[id] = store.usageRoseAt[id]
        }
    }
}
