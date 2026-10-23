import XCTest
@testable import OpenUsage

final class LocalLimitsAPITests: XCTestCase {
    private let fetchedAt = OpenUsageISO8601.date(from: "2026-07-13T01:39:30.000Z")!
    private let generatedAt = OpenUsageISO8601.date(from: "2026-07-13T01:40:00.000Z")!

    private func json(_ data: Data?) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(data)) as? [String: Any])
    }

    func testLimitsEnvelopeCarriesRawScalarsAndFreshnessWithoutUIPresentation() throws {
        let provider = Provider(id: "codex", displayName: "Codex", icon: .providerMark("codex"))
        let session = WidgetDescriptor.percent(id: "codex.session", provider: provider, title: "Session")
            .exportingLimit("session", unit: "percent")
        let credits = WidgetDescriptor.combined(
            id: "codex.credits", provider: provider, title: "Extra Usage", metricLabel: "Credits"
        )
        .exportingLimit("credits", kind: .balance, unit: "credits", source: .value(kind: .count, label: "credits"))
        .exportingLimit("creditValue", kind: .balance, unit: "usd", source: .value(kind: .dollars))
        let snapshot = ProviderSnapshot(
            providerID: "codex",
            displayName: "Codex",
            plan: "Pro 200",
            lines: [
                .progress(
                    label: "Session", used: 42, limit: 100, format: .percent,
                    resetsAt: OpenUsageISO8601.date(from: "2026-07-13T06:00:00.000Z"),
                    periodDurationMs: 18_000_000,
                    colorHex: "#ff0000"
                ),
                .values(label: "Credits", values: [
                    MetricValue(number: 32.84, kind: .dollars),
                    MetricValue(number: 821, kind: .count, label: "credits")
                ]),
                .chart(label: "Usage Trend", points: [], note: "UI only")
            ],
            refreshedAt: fetchedAt
        )
        let state = makeState(snapshot: snapshot, descriptors: [session, credits])

        let response = LocalUsageAPI.respond(method: "GET", path: "/v1/limits", state: state)
        let root = try json(response.body)
        let providerJSON = try XCTUnwrap((root["providers"] as? [String: Any])?["codex"] as? [String: Any])
        let resources = try XCTUnwrap(providerJSON["resources"] as? [String: Any])
        let sessionJSON = try XCTUnwrap(resources["session"] as? [String: Any])
        let creditsJSON = try XCTUnwrap(resources["credits"] as? [String: Any])

        XCTAssertEqual(response.status, 200)
        XCTAssertEqual(root["schema"] as? String, "openusage.limits.v1")
        XCTAssertEqual(root["generatedAt"] as? String, "2026-07-13T01:40:00.000Z")
        XCTAssertEqual(providerJSON["plan"] as? String, "Pro 200")
        XCTAssertEqual(providerJSON["fetchedAt"] as? String, "2026-07-13T01:39:30.000Z")
        XCTAssertEqual(providerJSON["expiresAt"] as? String, "2026-07-13T01:44:30.000Z")
        XCTAssertEqual(providerJSON["stale"] as? Bool, false)
        XCTAssertEqual(sessionJSON["kind"] as? String, "consumption")
        XCTAssertEqual(sessionJSON["unit"] as? String, "percent")
        XCTAssertEqual(sessionJSON["used"] as? Double, 42)
        XCTAssertEqual(sessionJSON["limit"] as? Double, 100)
        XCTAssertEqual(sessionJSON["remaining"] as? Double, 58)
        XCTAssertEqual(try XCTUnwrap(sessionJSON["utilization"] as? Double), 0.42, accuracy: 0.000_001)
        XCTAssertEqual(sessionJSON["windowSeconds"] as? Double, 18_000)
        XCTAssertEqual(creditsJSON["kind"] as? String, "balance")
        XCTAssertEqual(creditsJSON["available"] as? Double, 821)
        XCTAssertNotNil(resources["creditValue"])
        XCTAssertNil(resources["Usage Trend"])
        XCTAssertNil(sessionJSON["color"])
        XCTAssertNil(sessionJSON["subtitle"])
        XCTAssertNil(sessionJSON["label"])

        var expiredState = state
        expiredState.generatedAt = fetchedAt.addingTimeInterval(RefreshSetting.interval)
        let expiredRoot = try json(LocalUsageAPI.respond(method: "GET", path: "/v1/limits", state: expiredState).body)
        let expiredProviders = try XCTUnwrap(expiredRoot["providers"] as? [String: Any])
        let expiredProvider = try XCTUnwrap(expiredProviders["codex"] as? [String: Any])
        XCTAssertEqual(expiredProvider["stale"] as? Bool, true)
    }

    func testUsageAndLimitsProjectTheSameRenderedSnapshot() throws {
        let provider = Provider(id: "codex", displayName: "Codex", icon: .providerMark("codex"))
        let session = WidgetDescriptor.percent(id: "codex.session", provider: provider, title: "Session")
            .exportingLimit("session", unit: "percent")
        let snapshot = ProviderSnapshot(
            providerID: "codex",
            displayName: "Codex",
            lines: [.progress(label: "Session", used: 73, limit: 100, format: .percent)],
            refreshedAt: fetchedAt
        )
        let state = makeState(snapshot: snapshot, descriptors: [session])

        let usage = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: XCTUnwrap(LocalUsageAPI.respond(method: "GET", path: "/v1/usage", state: state).body)
            ) as? [[String: Any]]
        )
        let usageLine = try XCTUnwrap((usage.first?["lines"] as? [[String: Any]])?.first)
        let limitsRoot = try json(LocalUsageAPI.respond(method: "GET", path: "/v1/limits", state: state).body)
        let limitsProvider = try XCTUnwrap((limitsRoot["providers"] as? [String: Any])?["codex"] as? [String: Any])
        let limitsSession = try XCTUnwrap((limitsProvider["resources"] as? [String: Any])?["session"] as? [String: Any])

        XCTAssertEqual(usageLine["used"] as? Double, 73)
        XCTAssertEqual(limitsSession["used"] as? Double, 73)
    }

    func testKnownProviderRouteUsesSameEnvelopeAndReportsMissingSnapshotAsEmpty() throws {
        var state = LocalUsageAPI.State(
            enabledOrderedIDs: [],
            knownIDs: ["codex"],
            snapshots: [:],
            generatedAt: generatedAt
        )
        // Known but never fetched → the shape never changes: 200 with an empty envelope.
        let pending = LocalUsageAPI.respond(method: "GET", path: "/v1/limits/codex", state: state)
        XCTAssertEqual(pending.status, 200)
        let pendingRoot = try json(pending.body)
        XCTAssertTrue((pendingRoot["providers"] as? [String: Any])?.isEmpty == true)
        XCTAssertEqual(LocalUsageAPI.respond(method: "GET", path: "/v1/limits/nope", state: state).status, 404)

        state.errors["codex"] = "Not logged in"
        let failed = LocalUsageAPI.respond(method: "GET", path: "/v1/limits/codex", state: state)
        let root = try json(failed.body)
        let errors = try XCTUnwrap(root["errors"] as? [[String: Any]])
        XCTAssertEqual(failed.status, 200)
        XCTAssertTrue((root["providers"] as? [String: Any])?.isEmpty == true)
        XCTAssertEqual(errors.first?["providerId"] as? String, "codex")
        XCTAssertEqual(errors.first?["message"] as? String, "Not logged in")
    }

    func testErrorNamesTheCardSoACardWithNoDataCanStillBeListed() throws {
        var state = LocalUsageAPI.State(
            enabledOrderedIDs: ["claude"], knownIDs: ["claude"], snapshots: [:], generatedAt: generatedAt
        )
        state.errors["claude"] = "Signed Out. Last signed in at ~/.claude."
        state.displayNames["claude"] = "Claude: dune@test"

        let root = try json(LocalUsageAPI.respond(method: "GET", path: "/v1/limits", state: state).body)
        let errors = try XCTUnwrap(root["errors"] as? [[String: Any]])

        XCTAssertTrue((root["providers"] as? [String: Any])?.isEmpty == true)
        XCTAssertEqual(errors.first?["displayName"] as? String, "Claude: dune@test")
        XCTAssertEqual(errors.first?["message"] as? String, "Signed Out. Last signed in at ~/.claude.")
    }

    func testFlexibleConsumptionExportsUncappedValueWithoutInventingLimit() throws {
        let provider = Provider(id: "claude", displayName: "Claude", icon: .providerMark("claude"))
        let extra = WidgetDescriptor.boundedDollars(
            id: "claude.extra", provider: provider, title: "Extra Usage",
            metricLabel: "Extra usage spent", limit: 100
        ).exportingLimit("extraUsage", unit: "usd", source: .progressOrValue(kind: .dollars))
        let snapshot = ProviderSnapshot(
            providerID: "claude",
            displayName: "Claude",
            lines: [.values(label: "Extra usage spent", values: [MetricValue(number: 12.5, kind: .dollars)])],
            refreshedAt: fetchedAt
        )
        let resource = try limitResource("extraUsage", snapshot: snapshot, descriptors: [extra])

        XCTAssertEqual(resource["used"] as? Double, 12.5)
        XCTAssertNil(resource["limit"])
        XCTAssertNil(resource["remaining"])
        XCTAssertNil(resource["utilization"])
    }

    @MainActor
    func testCopilotPremiumCreditsExportsPersonalCountAndPaidPercent() throws {
        let credits = CopilotProvider().widgetDescriptors.first { $0.id == "copilot.premium" }!
        let personal = ProviderSnapshot(
            providerID: "copilot",
            displayName: "Copilot",
            plan: "Business",
            lines: [.values(label: "Credits", values: [MetricValue(number: 2111, kind: .count)])],
            refreshedAt: fetchedAt
        )
        let paid = ProviderSnapshot(
            providerID: "copilot",
            displayName: "Copilot",
            plan: "Pro",
            lines: [.progress(label: "Credits", used: 59, limit: 100, format: .percent)],
            refreshedAt: fetchedAt
        )

        let count = try limitResource("premiumCredits", snapshot: personal, descriptors: [credits])
        XCTAssertEqual(count["used"] as? Double, 2111)
        XCTAssertEqual(count["unit"] as? String, "credits")
        XCTAssertNil(count["limit"])

        let percent = try limitResource("premiumCredits", snapshot: paid, descriptors: [credits])
        XCTAssertEqual(percent["used"] as? Double, 59)
        XCTAssertEqual(percent["unit"] as? String, "percent")
        XCTAssertEqual(percent["limit"] as? Double, 100)
    }

    func testProgressResourceUnitFollowsRuntimeMetricFormat() throws {
        let provider = Provider(id: "cursor", displayName: "Cursor", icon: .providerMark("cursor"))
        let total = WidgetDescriptor.percent(
            id: "cursor.usage", provider: provider, title: "Total Usage", metricLabel: "Total usage"
        ).exportingLimit("totalUsage", unit: "percent")
        let snapshot = ProviderSnapshot(
            providerID: "cursor",
            displayName: "Cursor",
            lines: [.progress(
                label: "Total usage", used: 37, limit: 750,
                format: .count(suffix: "requests")
            )],
            refreshedAt: fetchedAt
        )
        let resource = try limitResource("totalUsage", snapshot: snapshot, descriptors: [total])

        XCTAssertEqual(resource["unit"] as? String, "requests")
        XCTAssertEqual(resource["used"] as? Double, 37)
        XCTAssertEqual(resource["limit"] as? Double, 750)
    }

    @MainActor
    func testAntigravityArgonWeeklyExportsSeparatelyAndIsOmittedWhenAbsent() throws {
        let descriptors = AntigravityProvider().widgetDescriptors
        let reset = OpenUsageISO8601.date(from: "2026-07-20T01:39:30.000Z")!
        var snapshot = ProviderSnapshot(
            providerID: "antigravity",
            displayName: "Antigravity",
            plan: "Pro",
            lines: [
                .progress(label: "Weekly", used: 10, limit: 100, format: .percent,
                          periodDurationMs: MetricPeriod.weekMs),
                .progress(label: "Argon Weekly", used: 75, limit: 100, format: .percent,
                          resetsAt: reset, periodDurationMs: MetricPeriod.weekMs)
            ],
            refreshedAt: fetchedAt
        )
        let argon = try limitResource("argonWeekly", snapshot: snapshot, descriptors: descriptors)
        let gemini = try limitResource("geminiWeekly", snapshot: snapshot, descriptors: descriptors)

        XCTAssertEqual(argon["unit"] as? String, "percent")
        XCTAssertEqual(argon["used"] as? Double, 75)
        XCTAssertEqual(argon["remaining"] as? Double, 25)
        XCTAssertEqual(argon["windowSeconds"] as? Double, 604_800)
        XCTAssertEqual(argon["resetsAt"] as? String, OpenUsageISO8601.string(from: reset))
        XCTAssertEqual(gemini["used"] as? Double, 10)

        // Older endpoints or accounts without the separate quota retain their existing resources.
        snapshot.lines.removeAll { $0.label == "Argon Weekly" }
        let state = makeState(snapshot: snapshot, descriptors: descriptors)
        let root = try json(LocalUsageAPI.respond(method: "GET", path: "/v1/limits", state: state).body)
        let provider = try XCTUnwrap((root["providers"] as? [String: Any])?["antigravity"] as? [String: Any])
        let resources = try XCTUnwrap(provider["resources"] as? [String: Any])
        XCTAssertEqual(Set(resources.keys), ["geminiWeekly"])
    }

    @MainActor
    func testEveryProviderDeclaresTheApprovedPublicResourceKeys() {
        let defaults = UserDefaults(suiteName: "LocalLimitsAPITests.\(UUID().uuidString)")!
        let registry = WidgetRegistry.from(ProviderCatalog.make(defaults: defaults))
        let actual = registry.limitDescriptorsByProvider.mapValues { descriptors in
            Set(descriptors.flatMap(\.limitResources).map(\.key))
        }
        let expected: [String: Set<String>] = [
            "claude": ["session", "weekly", "sonnet", "fable", "extraUsage", "rateLimitResets"],
            "codex": ["session", "weekly", "spark", "sparkWeekly", "credits", "creditValue", "rateLimitResets"],
            "cursor": ["totalUsage", "grokBot", "autoUsage", "apiUsage", "onDemand", "requests", "credits"],
            "antigravity": ["geminiSession", "geminiWeekly", "argonWeekly", "nonGeminiSession", "nonGeminiWeekly"],
            "copilot": ["premiumCredits", "extraUsage", "orgCredits", "orgSpend", "chat", "completions"],
            "devin": ["daily", "weekly", "extraUsageBalance"],
            "grok": ["weekly"],
            "ollama": ["session", "weekly", "monthly", "purchasedCredits"],
            "opencode": ["session", "weekly", "monthly"],
            "openrouter": ["credits", "balance", "keyLimit"],
            "zai": ["session", "weekly", "webSearches"]
        ]

        XCTAssertEqual(actual, expected)
    }

    func testUsageRoseOnlyWhenAConsumptionTotalGrewBetweenCloseRefreshes() {
        let provider = Provider(id: "claude", displayName: "Claude", icon: .providerMark("claude"))
        let session = WidgetDescriptor.percent(id: "claude.session", provider: provider, title: "Session")
            .exportingLimit("session", unit: "percent")
        let credits = WidgetDescriptor.combined(
            id: "claude.credits", provider: provider, title: "Extra Usage", metricLabel: "Credits"
        )
        .exportingLimit("credits", kind: .balance, unit: "credits", source: .value(kind: .count, label: "credits"))
        let weekly = WidgetDescriptor.percent(id: "claude.weekly", provider: provider, title: "Weekly")
            .exportingLimit("weekly", unit: "percent")
        func snapshot(
            used: Double?, limit: Double = 100, credits: Double = 500, name: String = "Claude: a@example.com",
            after seconds: TimeInterval
        ) -> ProviderSnapshot {
            var lines: [MetricLine] = [
                .progress(label: "Weekly", used: 20, limit: 100, format: .percent),
                .values(label: "Credits", values: [MetricValue(number: credits, kind: .count, label: "credits")])
            ]
            if let used { lines.append(.progress(label: "Session", used: used, limit: limit, format: .count(suffix: "requests"))) }
            return ProviderSnapshot(
                providerID: "claude", displayName: name, lines: lines, refreshedAt: fetchedAt.addingTimeInterval(seconds)
            )
        }
        let old = snapshot(used: 40, after: 0)
        let descriptors = [session, weekly, credits]

        XCTAssertTrue(LocalLimitsAPI.usageRose(from: old, to: snapshot(used: 43, after: 300), descriptors: descriptors))
        XCTAssertFalse(LocalLimitsAPI.usageRose(from: old, to: snapshot(used: 40, after: 300), descriptors: descriptors),
                       "no change is not use")
        XCTAssertFalse(LocalLimitsAPI.usageRose(from: old, to: snapshot(used: 3, after: 300), descriptors: descriptors),
                       "a window reset lowers the total")
        XCTAssertFalse(LocalLimitsAPI.usageRose(from: old, to: snapshot(used: 40, credits: 200, after: 300),
                                                descriptors: descriptors), "a balance moving is not usage")
        XCTAssertFalse(LocalLimitsAPI.usageRose(from: old, to: snapshot(used: 60, after: LocalLimitsAPI.activityGap + 1),
                                                descriptors: descriptors), "usage made while the app was closed")
        XCTAssertFalse(LocalLimitsAPI.usageRose(from: snapshot(used: 43, after: 300), to: old, descriptors: descriptors),
                       "an older snapshot never counts")
        XCTAssertTrue(LocalLimitsAPI.usageRose(from: snapshot(used: nil, after: 0), to: snapshot(used: 2, after: 300),
                                               descriptors: descriptors), "an idle window that appears in use")
        XCTAssertFalse(LocalLimitsAPI.usageRose(from: snapshot(used: nil, after: 0), to: snapshot(used: 0, after: 300),
                                                descriptors: descriptors), "an idle window that appears unused")
        XCTAssertFalse(LocalLimitsAPI.usageRose(from: old, to: snapshot(used: 45, limit: 50, after: 300),
                                                descriptors: descriptors), "a plan change moves the limit")
        XCTAssertFalse(LocalLimitsAPI.usageRose(from: old, to: snapshot(used: 45, name: "Claude: b@example.com", after: 300),
                                                descriptors: descriptors), "a different account on the same card")
    }

    func testLimitsEnvelopeCarriesUsageRoseAtOnlyWhenKnown() throws {
        let provider = Provider(id: "codex", displayName: "Codex", icon: .providerMark("codex"))
        let session = WidgetDescriptor.percent(id: "codex.session", provider: provider, title: "Session")
            .exportingLimit("session", unit: "percent")
        let snapshot = ProviderSnapshot(
            providerID: "codex",
            displayName: "Codex",
            lines: [.progress(label: "Session", used: 42, limit: 100, format: .percent)],
            refreshedAt: fetchedAt
        )
        var state = makeState(snapshot: snapshot, descriptors: [session])
        func providerJSON() throws -> [String: Any] {
            let root = try json(LocalUsageAPI.respond(method: "GET", path: "/v1/limits", state: state).body)
            return try XCTUnwrap((root["providers"] as? [String: Any])?["codex"] as? [String: Any])
        }

        XCTAssertNil(try providerJSON()["usageRoseAt"])
        state.usageRoseAt = ["codex": fetchedAt]
        XCTAssertEqual(try providerJSON()["usageRoseAt"] as? String, "2026-07-13T01:39:30.000Z")
    }

    private func makeState(snapshot: ProviderSnapshot, descriptors: [WidgetDescriptor]) -> LocalUsageAPI.State {
        LocalUsageAPI.State(
            enabledOrderedIDs: [snapshot.providerID],
            knownIDs: [snapshot.providerID],
            snapshots: [snapshot.providerID: snapshot],
            limitDescriptors: [snapshot.providerID: descriptors],
            generatedAt: generatedAt
        )
    }

    private func limitResource(
        _ key: String,
        snapshot: ProviderSnapshot,
        descriptors: [WidgetDescriptor]
    ) throws -> [String: Any] {
        let state = makeState(snapshot: snapshot, descriptors: descriptors)
        let root = try json(LocalUsageAPI.respond(method: "GET", path: "/v1/limits", state: state).body)
        let provider = try XCTUnwrap((root["providers"] as? [String: Any])?[snapshot.providerID] as? [String: Any])
        return try XCTUnwrap((provider["resources"] as? [String: Any])?[key] as? [String: Any])
    }
}
