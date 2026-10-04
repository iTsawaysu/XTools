import Combine
import Foundation

struct DashboardActivityEvent: Codable, Equatable, Identifiable {
    let id: UUID
    let toolID: ToolID
    let timestamp: Date
    var count: Int

    init(id: UUID = UUID(), toolID: ToolID, timestamp: Date, count: Int = 1) {
        self.id = id
        self.toolID = toolID
        self.timestamp = timestamp
        self.count = max(1, count)
    }
}

struct DashboardRecentTool: Codable, Equatable, Identifiable {
    let toolID: ToolID
    let lastOpenedAt: Date
    let launchCount: Int
    var id: ToolID { toolID }
}

/// `cards` 键在 v1 历史数据中存在过(卡片布局系统已删);合成解码忽略
/// 未知键,旧持久化数据无需迁移即可继续作为活动记录读入。
struct DashboardPreferences: Codable, Equatable {
    static let currentVersion = 1
    var version: Int = currentVersion
    var activity: [DashboardActivityEvent] = []
}

@MainActor
final class DashboardStore: ObservableObject {
    static let persistenceKey = "tools.dashboard.preferences.v1"
    static let retentionDays = 90

    @Published private(set) var preferences: DashboardPreferences
    private let defaults: UserDefaults
    private let calendar: Calendar
    private let now: () -> Date

    init(defaults: UserDefaults = .standard, calendar: Calendar = .current, now: @escaping () -> Date = Date.init) {
        self.defaults = defaults
        self.calendar = calendar
        self.now = now
        let loaded = Self.load(from: defaults) ?? DashboardPreferences()
        self.preferences = loaded
        trimActivity(reference: now())
    }

    var recentTools: [DashboardRecentTool] {
        Dictionary(grouping: preferences.activity, by: \.toolID).compactMap { toolID, events in
            guard let latest = events.max(by: { $0.timestamp < $1.timestamp }) else { return nil }
            return DashboardRecentTool(toolID: toolID, lastOpenedAt: latest.timestamp, launchCount: events.reduce(0) { $0 + $1.count })
        }.sorted { $0.lastOpenedAt > $1.lastOpenedAt }
    }

    /// Recent tools whose IDs are present in the current registry. Persisted
    /// history may outlive a removed tool; callers can pass the registry IDs
    /// before presenting rows so stale entries never reach the UI.
    func recentTools(knownToolIDs: Set<ToolID>) -> [DashboardRecentTool] {
        recentTools.filter { knownToolIDs.contains($0.toolID) }
    }

    func recordLaunch(toolID: ToolID, at date: Date? = nil) {
        let timestamp = date ?? now()
        // Retention is anchored to the current local day; an imported or
        // test event timestamp must not move the retention window backwards.
        preferences.activity.append(DashboardActivityEvent(toolID: toolID, timestamp: timestamp))
        trimActivity(reference: now())
        persist()
    }

    func recordLaunchIfChanged(toolID: ToolID, previousToolID: ToolID?, at date: Date? = nil) {
        guard previousToolID != toolID else { return }
        recordLaunch(toolID: toolID, at: date)
    }

    private func trimActivity(reference: Date) {
        guard let cutoff = calendar.date(byAdding: .day, value: -(Self.retentionDays - 1), to: calendar.startOfDay(for: reference)) else { return }
        let trimmed = preferences.activity.filter { $0.timestamp >= cutoff }
        if trimmed.count != preferences.activity.count { preferences.activity = trimmed; persist() }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(preferences) else { return }
        defaults.set(data, forKey: Self.persistenceKey)
        objectWillChange.send()
    }

    private static func load(from defaults: UserDefaults) -> DashboardPreferences? {
        guard let data = defaults.data(forKey: persistenceKey), let decoded = try? JSONDecoder().decode(DashboardPreferences.self, from: data), decoded.version == DashboardPreferences.currentVersion else { return nil }
        return decoded
    }
}
