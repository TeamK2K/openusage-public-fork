import Foundation

/// Machine-facing limits serializer shared by the one-shot CLI and local HTTP API.
/// Provider refresh/mapping remains the single source of truth; this edge only selects scalar resources
/// explicitly declared on `WidgetDescriptor` and gives them stable public names.
enum LocalLimitsAPI {
    static let schema = "openusage.limits.v1"

    static func encode(providerIDs: [String], state: LocalUsageAPI.State) -> Data {
        var providers: [String: WireProvider] = [:]
        for providerID in providerIDs {
            guard let snapshot = state.snapshots[providerID] else { continue }
            let descriptors = state.limitDescriptors[providerID] ?? []
            providers[providerID] = WireProvider(
                snapshot: snapshot,
                descriptors: descriptors,
                usageRoseAt: state.usageRoseAt[providerID],
                generatedAt: state.generatedAt
            )
        }
        let errors = providerIDs.compactMap { providerID in
            state.errors[providerID].map { WireError(providerID: providerID, message: $0) }
        }
        return encode(WireEnvelope(
            schema: schema,
            generatedAt: OpenUsageISO8601.string(from: state.generatedAt),
            providers: providers,
            errors: errors
        ))
    }

    /// Refreshes further apart than this are never compared for activity: usage made while the app
    /// was closed (a launch-cached snapshot hours old) must not read as "in use now". Three refresh
    /// intervals, so one slow or failed pass doesn't break the chain.
    static let activityGap: TimeInterval = 3 * RefreshSetting.interval

    /// Whether an account's usage went up between two of its refreshes: any consumption total the
    /// envelope publishes grew, or a window that was absent (idle) appeared already in use. Balances
    /// are left out — a credit top-up or a reset pass isn't usage — and so are a total that fell (a
    /// window reset), a total whose limit changed (a plan change moves a percentage with no use), and
    /// a card whose account changed in between (its display name names the account).
    static func usageRose(from old: ProviderSnapshot, to new: ProviderSnapshot, descriptors: [WidgetDescriptor]) -> Bool {
        let gap = new.refreshedAt.timeIntervalSince(old.refreshedAt)
        guard gap > 0, gap <= activityGap, old.displayName == new.displayName else { return false }
        let before = consumption(of: old, descriptors: descriptors)
        return consumption(of: new, descriptors: descriptors).contains { key, now in
            guard let then = before[key] else { return !before.isEmpty && now.used > 0 }
            return then.limit == now.limit && now.used > then.used
        }
    }

    private static func consumption(
        of snapshot: ProviderSnapshot,
        descriptors: [WidgetDescriptor]
    ) -> [String: (used: Double, limit: Double?)] {
        var totals: [String: (used: Double, limit: Double?)] = [:]
        for descriptor in descriptors {
            guard let line = snapshot.line(label: descriptor.metricLabel) else { continue }
            for resource in descriptor.limitResources where resource.kind == .consumption {
                guard let wire = WireResource(resource: resource, line: line), let used = wire.used else { continue }
                totals[resource.key] = (used, wire.limit)
            }
        }
        return totals
    }

    private static func encode(_ value: some Encodable) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return (try? encoder.encode(value)) ?? Data(#"{"errors":[],"providers":{},"schema":"openusage.limits.v1"}"#.utf8)
    }

    private struct WireEnvelope: Encodable {
        let schema: String
        let generatedAt: String
        let providers: [String: WireProvider]
        let errors: [WireError]
    }

    private struct WireError: Encodable {
        let providerID: String
        let message: String

        enum CodingKeys: String, CodingKey {
            case providerID = "providerId"
            case message
        }
    }

    private struct WireProvider: Encodable {
        let displayName: String
        let plan: String?
        let fetchedAt: String
        let expiresAt: String
        let stale: Bool
        /// The latest refresh at which this account's usage went up; omitted until one is seen.
        let usageRoseAt: String?
        let resources: [String: WireResource]

        init(snapshot: ProviderSnapshot, descriptors: [WidgetDescriptor], usageRoseAt: Date?, generatedAt: Date) {
            displayName = snapshot.displayName
            plan = snapshot.plan
            fetchedAt = OpenUsageISO8601.string(from: snapshot.refreshedAt)
            self.usageRoseAt = usageRoseAt.map(OpenUsageISO8601.string(from:))
            let expiry = snapshot.refreshedAt.addingTimeInterval(RefreshSetting.interval)
            expiresAt = OpenUsageISO8601.string(from: expiry)
            stale = generatedAt >= expiry

            var resources: [String: WireResource] = [:]
            for descriptor in descriptors {
                guard let line = snapshot.line(label: descriptor.metricLabel) else { continue }
                for resource in descriptor.limitResources {
                    if let value = WireResource(resource: resource, line: line) {
                        resources[resource.key] = value
                    }
                }
            }
            self.resources = resources
        }
    }

    private struct WireResource: Encodable {
        let kind: LimitResourceDescriptor.Kind
        let unit: String
        var used: Double?
        var available: Double?
        var limit: Double?
        var remaining: Double?
        var utilization: Double?
        var resetsAt: String?
        var windowSeconds: Double?
        var expiresAt: [String]?
        var estimated: Bool?

        init?(resource: LimitResourceDescriptor, line: MetricLine) {
            kind = resource.kind
            unit = Self.progressUnit(line) ?? resource.unit

            switch (resource.source, line) {
            case (.progress, .progress(_, let rawUsed, let rawLimit, _, let reset, let periodMs, _)):
                applyProgress(
                    used: rawUsed, limit: rawLimit, reset: reset, periodMs: periodMs,
                    resource: resource
                )

            case (.progressOrValue(_, _),
                  .progress(_, let rawUsed, let rawLimit, _, let reset, let periodMs, _)):
                applyProgress(
                    used: rawUsed, limit: rawLimit, reset: reset, periodMs: periodMs,
                    resource: resource
                )

            case (.value(let expectedKind, let expectedLabel),
                  .values(_, let values, _, let expiries, _, _)),
                 (.progressOrValue(let expectedKind, let expectedLabel),
                  .values(_, let values, _, let expiries, _, _)):
                guard let metric = values.first(where: { value in
                    value.kind == expectedKind && (expectedLabel == nil || value.label == expectedLabel)
                }) else { return nil }
                if resource.kind == .balance {
                    available = metric.number
                } else {
                    used = metric.number
                }
                expiresAt = expiries.isEmpty ? nil : expiries.sorted().map(OpenUsageISO8601.string(from:))
                estimated = resource.estimated || metric.estimated ? true : nil

            default:
                return nil
            }
        }

        /// A descriptor names the stable resource and supplies a fallback unit for value rows. Progress
        /// rows carry their actual runtime unit, which can vary by plan (for example Cursor Total Usage
        /// is percent on individual plans and requests on request-based Enterprise plans).
        private static func progressUnit(_ line: MetricLine) -> String? {
            guard case .progress(_, _, _, let format, _, _, _) = line else { return nil }
            switch format {
            case .percent:
                return "percent"
            case .dollars:
                return "usd"
            case .count(let suffix):
                return suffix.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            }
        }

        private mutating func applyProgress(
            used rawUsed: Double,
            limit rawLimit: Double,
            reset: Date?,
            periodMs: Int?,
            resource: LimitResourceDescriptor
        ) {
            let boundedLimit = max(0, rawLimit)
            let boundedUsed = max(0, rawUsed)
            used = resource.kind == .consumption ? boundedUsed : nil
            available = resource.kind == .balance ? boundedUsed : nil
            limit = boundedLimit
            remaining = max(0, boundedLimit - boundedUsed)
            utilization = boundedLimit > 0 ? boundedUsed / boundedLimit : nil
            resetsAt = reset.map(OpenUsageISO8601.string(from:))
            windowSeconds = periodMs.map { Double($0) / 1_000 }
            estimated = resource.estimated ? true : nil
        }
    }
}
