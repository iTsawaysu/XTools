import Foundation
import Testing
@testable import XTools

/// Palette frecency: decay scoring, recents ordering, ring cap, persistence
/// round-trip, and the landing-page/boost composition built on top of it.
@MainActor
struct PaletteRecentsStoreTests {
    private static func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "PaletteRecentsStoreTests.\(UUID().uuidString)")!
    }

    private static func store() -> PaletteRecentsStore {
        PaletteRecentsStore(preferences: ToolPreferenceStore(defaults: makeDefaults()))
    }

    private static func daysAgo(_ days: Double, from now: Date) -> Date {
        now.addingTimeInterval(-days * 24 * 3600)
    }

    // MARK: - Scoring

    @Test func frecencyScoreDecaysWithAge() {
        let store = Self.store()
        let now = Date()

        store.recordLaunch(.json, at: now)
        store.recordLaunch(.regex, at: Self.daysAgo(7, from: now))

        let fresh = store.frecencyScore(for: .json, now: now)
        let weekOld = store.frecencyScore(for: .regex, now: now)

        #expect(fresh == 1)
        #expect(weekOld > 0.49 && weekOld < 0.51)
        #expect(fresh > weekOld)
    }

    @Test func repeatedLaunchesAccumulateWithinTheDecayWindow() {
        let store = Self.store()
        let now = Date()

        for _ in 0..<3 {
            store.recordLaunch(.json, at: Self.daysAgo(1, from: now))
        }

        let score = store.frecencyScore(for: .json, now: now)
        #expect(score > 2.71 && score < 2.72)
        #expect(store.frecencyScore(for: .regex, now: now) == 0)
    }

    @Test func recentsOrderByMostRecentLaunchAndCapTheLimit() {
        let store = Self.store()
        let now = Date()

        store.recordLaunch(.json, at: Self.daysAgo(3, from: now))
        store.recordLaunch(.regex, at: Self.daysAgo(1, from: now))
        store.recordLaunch(.jwt, at: now)
        store.recordLaunch(.cafe, at: Self.daysAgo(2, from: now))

        #expect(store.recentToolIDs(limit: 3, now: now) == [.jwt, .regex, .cafe])
        #expect(store.recentToolIDs(limit: 1, now: now) == [.jwt])
        #expect(store.recentToolIDs(limit: 0, now: now).isEmpty)
    }

    @Test func relaunchingAMovesToolToTheFrontOfRecents() {
        let store = Self.store()
        let now = Date()

        store.recordLaunch(.regex, at: Self.daysAgo(3, from: now))
        store.recordLaunch(.jwt, at: Self.daysAgo(2, from: now))
        store.recordLaunch(.regex, at: now)

        #expect(store.recentToolIDs(limit: 3, now: now) == [.regex, .jwt])
    }

    @Test func eventRingKeepsOnlyTheLatestWindow() {
        let store = Self.store()
        let now = Date()

        for index in 0..<(96 + 10) {
            store.recordLaunch(
                ToolID(rawValue: "tool-\(index)"),
                at: Self.daysAgo(Double(200 - index), from: now)
            )
        }

        // The oldest tools dropped out of the ring; the newest survive.
        #expect(store.recentToolIDs(limit: 200, now: now).count == 96)
        #expect(store.recentToolIDs(limit: 1, now: now) == [ToolID(rawValue: "tool-105")])
    }

    // MARK: - Persistence

    @Test func launchesPersistAcrossStoreInstances() throws {
        let defaults = Self.makeDefaults()
        let preferences = ToolPreferenceStore(defaults: defaults)
        let now = Date()

        let first = PaletteRecentsStore(preferences: preferences)
        first.recordLaunch(.json, at: now)
        first.recordLaunch(.regex, at: Self.daysAgo(1, from: now))

        let restored = PaletteRecentsStore(preferences: preferences)
        #expect(restored.recentToolIDs(limit: 5, now: now) == [.json, .regex])
        #expect(restored.frecencyScore(for: .json, now: now) == 1)
    }

    @Test func corruptedStorageFallsBackToEmpty() {
        let defaults = Self.makeDefaults()
        defaults.set("not-json", forKey: AppShellPreferenceKeys.paletteRecents.rawKey)
        let preferences = ToolPreferenceStore(defaults: defaults)

        let store = PaletteRecentsStore(preferences: preferences)

        #expect(store.recentToolIDs(limit: 5, now: Date()).isEmpty)
    }

    @Test func missingPreferencesKeepTheStoreInMemoryOnly() {
        let store = PaletteRecentsStore(preferences: nil)
        store.recordLaunch(.json)

        #expect(store.recentToolIDs(limit: 5, now: Date()) == [.json])
    }

    // MARK: - Landing page composition

    @Test func blankQueryLandsOnRecentsActionsThenCategories() {
        let usage = FixedUsage(
            recents: [.jwt, .json],
            scores: [:]
        )
        let model = CommandPaletteSessionModel(
            registry: .default,
            actions: [
                CommandActionEntry(
                    id: .toggleAppearance,
                    title: "切换主题",
                    subtitle: nil,
                    systemImage: "circle.lefthalf.filled"
                )
            ],
            usage: usage
        )

        let rows = model.snapshot.rows
        let titles = rows.compactMap { row -> String? in
            guard case .sectionTitle(let title) = row else { return nil }
            return title
        }

        #expect(titles.first == "最近使用")
        #expect(titles.contains("动作"))
        #expect(titles.dropFirst().first == "动作")
        #expect(titles.count == 2 + ToolRegistry.default.categoryGroups().count)

        // Recents lead the selectable list: ⌘K ↩ opens the most-recent tool.
        #expect(model.navigationState.activeRowID(in: model.snapshot) == "tool.jwt-parser")
        #expect(model.snapshot.sectionCountsByTitle["最近使用"] == 2)
        #expect(model.snapshot.sectionCountsByTitle["动作"] == 1)
    }

    @Test func blankQueryWithoutUsageSkipsTheRecentsSection() {
        let model = CommandPaletteSessionModel(registry: .default, actions: [])

        let titles = model.snapshot.rows.compactMap { row -> String? in
            guard case .sectionTitle(let title) = row else { return nil }
            return title
        }

        #expect(!titles.contains("最近使用"))
        #expect(titles.count == ToolRegistry.default.categoryGroups().count)
        #expect(model.snapshot.sectionCountsByTitle["最近使用"] == nil)
    }

    @Test func landingPageRowsHaveUniqueIDs() {
        let usage = FixedUsage(recents: [.jwt, .json], scores: [:])
        let model = CommandPaletteSessionModel(
            registry: .default,
            actions: [],
            usage: usage
        )

        let ids = model.snapshot.rows.map(\.id)
        #expect(Set(ids).count == ids.count)
        #expect(ids.filter { $0 == "tool.jwt-parser" }.count == 1)
    }

    /// Warm ⌘K sessions ship a fresh preview UUID per open. The landing
    /// cache keys on the STABLE actions (preview excluded) plus recents, so
    /// the sections must be served from cache while the preview row still
    /// carries each session's own UUID — never a stale one.
    @Test func landingCacheServesWarmSessionsWithFreshPreviewSubtitles() {
        let usage = FixedUsage(recents: [.jwt, .json], scores: [:])
        let baseActions: [CommandActionEntry] = [
            CommandActionEntry(
                id: .toggleAppearance,
                title: "切换主题",
                subtitle: nil,
                systemImage: "circle.lefthalf.filled"
            )
        ]

        func previewActions(_ previewValue: String?) -> [CommandActionEntry] {
            CommandActionEntry.paletteActions(
                baseActions: baseActions,
                previewValue: previewValue
            )
        }

        let model = CommandPaletteSessionModel(
            registry: .default,
            actions: previewActions("uuid-first"),
            session: 1,
            usage: usage
        )
        // The first composition is a cold build: no cache hit yet.
        #expect(model.landingCacheHitCount == 0)
        #expect(Self.previewSubtitle(in: model.snapshot) == "uuid-first")

        model.beginSession(2, actions: previewActions("uuid-second"))
        #expect(model.landingCacheHitCount == 1)
        #expect(Self.previewSubtitle(in: model.snapshot) == "uuid-second")

        model.beginSession(3, actions: previewActions("uuid-third"))
        #expect(model.landingCacheHitCount == 2)
        #expect(Self.previewSubtitle(in: model.snapshot) == "uuid-third")

        // The same rule applies through replaceActions: a preview-only
        // change (stable actions unchanged) hits the cache — the exact
        // warm-reopen scenario the cache exists for.
        model.replaceActions(previewActions("uuid-fourth"))
        #expect(model.landingCacheHitCount == 3)
        #expect(Self.previewSubtitle(in: model.snapshot) == "uuid-fourth")
    }

    private static func previewSubtitle(
        in snapshot: CommandPaletteRowSnapshot
    ) -> String? {
        for row in snapshot.rows {
            if case .command(let entry) = row, entry.id == .copyGeneratedUUID {
                return entry.subtitle
            }
        }
        return nil
    }

    @Test func queryRankingStaysIdenticalWithoutUsageData() {
        let model = CommandPaletteSessionModel(registry: .default, actions: [])

        #expect(model.setQuery("json"))

        let ids = model.snapshot.rows.compactMap { row -> ToolID? in
            guard case .tool(let entry) = row else { return nil }
            return entry.toolID
        }
        #expect(ids == ToolRegistry.default.matchingTools(query: "json").map(\.id))
    }

    @Test func frecencyBoostRefinesWithinTiersOnly() {
        // "generate" is an exact keyword of both 生成器 and JWT (identical
        // keyword-tier base scores, registration order breaks the tie), so a
        // frecency boost on JWT must flip them inside the tier.
        let usage = FixedUsage(
            recents: [],
            scores: [.jwt: 100]
        )
        let model = CommandPaletteSessionModel(registry: .default, actions: [], usage: usage)

        #expect(model.setQuery("generate"))

        let ids = model.snapshot.rows.compactMap { row -> ToolID? in
            guard case .tool(let entry) = row else { return nil }
            return entry.toolID
        }
        #expect(ids.first == .jwt)
        #expect(ids.contains(.generator))

        // Without usage data the same query keeps registration order.
        let bare = CommandPaletteSessionModel(registry: .default, actions: [])
        #expect(bare.setQuery("generate"))
        let bareIDs = bare.snapshot.rows.compactMap { row -> ToolID? in
            guard case .tool(let entry) = row else { return nil }
            return entry.toolID
        }
        #expect(bareIDs.first == .generator)
    }

    /// Deterministic scoring double: fixed recents and score table.
    private struct FixedUsage: PaletteUsageScoring {
        let recents: [ToolID]
        let scores: [ToolID: Double]

        func frecencyScore(for toolID: ToolID, now: Date) -> Double {
            scores[toolID] ?? 0
        }

        func recentToolIDs(limit: Int, now: Date) -> [ToolID] {
            Array(recents.prefix(limit))
        }
    }
}

private extension ToolID {
    static let json = ToolID(rawValue: "formatter")
    static let regex = ToolID(rawValue: "regex-tester")
    static let jwt = ToolID(rawValue: "jwt-parser")
    static let cafe = ToolID(rawValue: "color-picker")
    static let generator = ToolID(rawValue: "generator")
}
