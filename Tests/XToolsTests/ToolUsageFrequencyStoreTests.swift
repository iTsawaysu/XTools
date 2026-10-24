import Foundation
import Testing
@testable import XTools

/// 全壳单一使用频率源（阶段③ frecency 单源）的行为合同：衰减公式跨通道
/// 等价、双通道隔离、palette 环上限、navigation 90 天窗口、旧 JSON 首读
/// 迁移与后台写排空。DashboardStore / PaletteRecentsStore 的门面测试建立
/// 在这些语义之上。
@MainActor
struct ToolUsageFrequencyStoreTests {
    private static func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "ToolUsageFrequencyStoreTests.\(UUID().uuidString)")!
    }

    private static func daysAgo(_ days: Double, from now: Date) -> Date {
        now.addingTimeInterval(-days * 24 * 3600)
    }

    // MARK: - 单源公式（衰减等价性）

    /// 同一时间戳的事件在两个通道贡献同一分数：公式只有一份，不得因
    /// 读取通道分叉出第二套衰减参数。
    @Test func decayFormulaIsIdenticalAcrossChannels() {
        let store = ToolUsageFrequencyStore(defaults: Self.makeDefaults())
        let now = Date()
        store.recordLaunch(.json, channel: .navigation, at: Self.daysAgo(7, from: now))
        store.recordLaunch(.json, channel: .palette, at: Self.daysAgo(7, from: now))

        let navigationScore = store.frecencyScore(for: .json, in: .navigation, now: now)
        let paletteScore = store.frecencyScore(for: .json, in: .palette, now: now)

        #expect(navigationScore == paletteScore)
        // 半衰期语义：恰好 7 天前的一次启动贡献 0.5。
        #expect(abs(navigationScore - 0.5) < 0.000_001)
    }

    @Test func repeatedLaunchesAccumulateWithinTheDecayWindow() {
        let store = ToolUsageFrequencyStore(defaults: Self.makeDefaults())
        let now = Date()
        for _ in 0..<3 {
            store.recordLaunch(.json, channel: .navigation, at: Self.daysAgo(1, from: now))
        }

        let score = store.frecencyScore(for: .json, in: .navigation, now: now)
        #expect(score > 2.71 && score < 2.72)
        #expect(store.frecencyScore(for: .regex, in: .navigation, now: now) == 0)
    }

    /// 通道即语义边界：仪表盘读 navigation、⌘K 落地页读 palette，互相
    /// 看不到对方的启动记录。
    @Test func channelsStayIsolated() {
        let store = ToolUsageFrequencyStore(defaults: Self.makeDefaults())
        let now = Date()
        store.recordLaunch(.json, channel: .navigation, at: now)
        store.recordLaunch(.regex, channel: .palette, at: now)

        #expect(store.recentToolIDs(in: .navigation, limit: 5, now: now) == [.json])
        #expect(store.recentToolIDs(in: .palette, limit: 5, now: now) == [.regex])
        #expect(store.frecencyScore(for: .json, in: .palette, now: now) == 0)
        #expect(store.frecencyScore(for: .regex, in: .navigation, now: now) == 0)
    }

    @Test func recentsOrderByMostRecentLaunchAndCapTheLimit() {
        let store = ToolUsageFrequencyStore(defaults: Self.makeDefaults())
        let now = Date()

        store.recordLaunch(.json, channel: .navigation, at: Self.daysAgo(3, from: now))
        store.recordLaunch(.regex, channel: .navigation, at: Self.daysAgo(1, from: now))
        store.recordLaunch(.jwt, channel: .navigation, at: now)
        store.recordLaunch(.cafe, channel: .navigation, at: Self.daysAgo(2, from: now))

        #expect(store.recentToolIDs(in: .navigation, limit: 3, now: now) == [.jwt, .regex, .cafe])
        #expect(store.recentToolIDs(in: .navigation, limit: 0, now: now).isEmpty)
    }

    @Test func relaunchingAMovesToolToTheFrontOfRecents() {
        let store = ToolUsageFrequencyStore(defaults: Self.makeDefaults())
        let now = Date()

        store.recordLaunch(.regex, channel: .palette, at: Self.daysAgo(3, from: now))
        store.recordLaunch(.jwt, channel: .palette, at: Self.daysAgo(2, from: now))
        store.recordLaunch(.regex, channel: .palette, at: now)

        #expect(store.recentToolIDs(in: .palette, limit: 3, now: now) == [.regex, .jwt])
    }

    // MARK: - 保留窗口

    /// palette 环 96 条上限（沿用旧 PaletteRecentsStore 容量）。
    @Test func paletteRingKeepsOnlyTheLatestWindow() {
        let store = ToolUsageFrequencyStore(defaults: Self.makeDefaults())
        let now = Date()

        for index in 0..<(ToolUsageFrequencyStore.paletteEventCap + 10) {
            store.recordLaunch(
                ToolID(rawValue: "tool-\(index)"),
                channel: .palette,
                at: Self.daysAgo(Double(200 - index), from: now)
            )
        }

        #expect(store.recentToolIDs(in: .palette, limit: 500, now: now).count == ToolUsageFrequencyStore.paletteEventCap)
        #expect(store.recentToolIDs(in: .palette, limit: 1, now: now) == [ToolID(rawValue: "tool-\(ToolUsageFrequencyStore.paletteEventCap + 9)")])
    }

    /// navigation 90 天日历窗口（沿用旧 DashboardStore 语义）；palette
    /// 事件不受该日历窗口影响，只受环上限约束。
    @Test func navigationHistoryTrimsAtNinetyDaysButPaletteSurvives() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let store = ToolUsageFrequencyStore(
            defaults: Self.makeDefaults(),
            calendar: calendar,
            now: { base }
        )
        store.recordLaunch(.json, channel: .navigation, at: base)
        store.recordLaunch(.json, channel: .navigation, at: calendar.date(byAdding: .hour, value: 1, to: base)!)
        store.recordLaunch(.jwt, channel: .navigation, at: calendar.date(byAdding: .day, value: -89, to: base)!)
        store.recordLaunch(.regex, channel: .navigation, at: calendar.date(byAdding: .day, value: -90, to: base)!)
        store.recordLaunch(.cafe, channel: .palette, at: Self.daysAgo(200, from: base))

        #expect(store.latestLaunchDates(in: .navigation).count == 2)
        #expect(store.recentToolIDs(in: .palette, limit: 5, now: base) == [.cafe])
    }

    // MARK: - 旧 JSON 首读迁移

    /// 旧仪表盘日志（tools.dashboard.preferences.v1）一次性导入为
    /// navigation 事件；旧 palette 环（无 channel 字段）按 .palette 解读。
    /// 位图键置位后重启（重建实例）不重复导入、已裁剪事件不复活。
    @Test func legacyLogsMigrateOnceIntoTheirChannels() throws {
        let defaults = Self.makeDefaults()
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let legacy = DashboardPreferences(activity: [
            DashboardActivityEvent(toolID: .json, timestamp: base),
            DashboardActivityEvent(toolID: .regex, timestamp: base.addingTimeInterval(3600)),
        ])
        defaults.set(try JSONEncoder().encode(legacy), forKey: ToolUsageFrequencyStore.legacyDashboardLogKey)
        defaults.set(
            #"[{"toolID":"jwt-parser","epochSeconds":\#((base.timeIntervalSince1970 + 7200).description)}]"#,
            forKey: AppShellPreferenceKeys.paletteRecents.rawKey
        )

        // 注入时钟锚定迁移时刻：真实 now 会把 2023 年的旧事件按 90 天窗口
        // 裁剪掉，无法验证迁移本身。
        var store: ToolUsageFrequencyStore? = ToolUsageFrequencyStore(
            defaults: defaults,
            now: { base.addingTimeInterval(7200) }
        )
        #expect(store?.recentToolIDs(in: .navigation, limit: 5, now: base.addingTimeInterval(7200)) == [.regex, .json])
        #expect(store?.recentToolIDs(in: .palette, limit: 5, now: base.addingTimeInterval(7200)) == [.jwt])
        #expect(defaults.bool(forKey: ToolUsageFrequencyStore.dashboardImportFlagKey))

        // 重启：合并日志已落盘（deinit flush 排空），位图键阻止二次导入。
        store = nil
        let reloaded = ToolUsageFrequencyStore(
            defaults: defaults,
            now: { base.addingTimeInterval(7200) }
        )
        #expect(reloaded.latestLaunchDates(in: .navigation).count == 2)
        #expect(reloaded.recentToolIDs(in: .palette, limit: 5, now: base.addingTimeInterval(7200)) == [.jwt])
    }

    /// 损坏的旧日志只导入一次：位图键照常置位，不做每次启动重试。
    @Test func corruptedLegacyLogDoesNotRetryImport() {
        let defaults = Self.makeDefaults()
        defaults.set("not-json", forKey: ToolUsageFrequencyStore.legacyDashboardLogKey)

        _ = ToolUsageFrequencyStore(defaults: defaults)

        #expect(defaults.bool(forKey: ToolUsageFrequencyStore.dashboardImportFlagKey))
    }

    // MARK: - 持久化

    /// 无 defaults（纯内存模式）不落盘也不迁移，行为与旧
    /// `PaletteRecentsStore(preferences: nil)` 等价。
    @Test func ephemeralStoreKeepsEventsInMemoryOnly() {
        let store = ToolUsageFrequencyStore(defaults: nil)
        store.recordLaunch(.json, channel: .palette)

        #expect(store.recentToolIDs(in: .palette, limit: 5, now: Date()) == [.json])
    }
}

private extension ToolID {
    static let json = ToolID(rawValue: "formatter")
    static let regex = ToolID(rawValue: "regex-tester")
    static let jwt = ToolID(rawValue: "jwt-parser")
    static let cafe = ToolID(rawValue: "color-picker")
}
