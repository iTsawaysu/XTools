import Combine
import Foundation
import AppKit

struct DashboardActivityEvent: Codable, Equatable, Identifiable {
    let id: UUID
    let toolID: ToolID
    let timestamp: Date

    init(id: UUID = UUID(), toolID: ToolID, timestamp: Date) {
        self.id = id
        self.toolID = toolID
        self.timestamp = timestamp
    }
}

struct DashboardRecentTool: Codable, Equatable, Identifiable {
    let toolID: ToolID
    let lastOpenedAt: Date
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
    private let persistence: DashboardPersistence
    private var terminationObserver: AnyCancellable?
    private let calendar: Calendar
    private let now: () -> Date

    init(defaults: UserDefaults = .standard, calendar: Calendar = .current, now: @escaping () -> Date = Date.init) {
        let persistence = DashboardPersistence(defaults: defaults, key: Self.persistenceKey)
        self.persistence = persistence
        self.calendar = calendar
        self.now = now
        let loaded = Self.load(from: defaults) ?? DashboardPreferences()
        self.preferences = loaded
        if trimActivity(reference: now()) { persist() }
        terminationObserver = NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)
            .sink { _ in persistence.flush() }
    }

    deinit {
        persistence.flush()
    }

    var recentTools: [DashboardRecentTool] {
        Dictionary(grouping: preferences.activity, by: \.toolID).compactMap { toolID, events in
            guard let latest = events.max(by: { $0.timestamp < $1.timestamp }) else { return nil }
            return DashboardRecentTool(toolID: toolID, lastOpenedAt: latest.timestamp)
        }.sorted { $0.lastOpenedAt > $1.lastOpenedAt }
    }

    /// Recent tools whose IDs are present in the current registry. Persisted
    /// history may outlive a removed tool; callers can pass the registry IDs
    /// before presenting rows so stale entries never reach the UI.
    func recentTools(knownToolIDs: Set<ToolID>) -> [DashboardRecentTool] {
        recentTools.filter { knownToolIDs.contains($0.toolID) }
    }

    /// Exponential-decay frecency over the full launch activity (sidebar,
    /// dashboard and palette navigation alike): each launch contributes
    /// `0.5^(age / 7 days)`, so a tool used twice today outranks one used once
    /// last week. Same formula as `PaletteRecentsStore` so the two reads agree
    /// numerically; the dashboard is the richer source because it sees every
    /// navigation path, not just ⌘K activations.
    func frecencyScore(for toolID: ToolID, now: Date = Date()) -> Double {
        let nowSeconds = now.timeIntervalSince1970
        let halfLifeSeconds = 7.0 * 24 * 3600
        return preferences.activity.reduce(into: 0.0) { score, event in
            guard event.toolID == toolID else { return }
            let age = max(0, nowSeconds - event.timestamp.timeIntervalSince1970)
            score += pow(0.5, age / halfLifeSeconds)
        }
    }

    /// Distinct tool IDs ordered by frecency (descending), filtered to the
    /// current registry. Ties break by most-recent launch.
    ///
    /// 性能：先在单次遍历里为每个 toolID 预计算 frecency 总分与最近时间戳，
    /// 再排序——避免 `sorted` 闭包对每对元素重复调用 O(activity) 的
    /// `frecencyScore`（那会退化成 O(n² · activity)）。activity 攒到几百条
    /// 后每帧卡顿就来自这里。
    func frecencyRankedToolIDs(knownToolIDs: Set<ToolID>, limit: Int, now: Date = Date()) -> [ToolID] {
        guard limit > 0 else { return [] }

        let nowSeconds = now.timeIntervalSince1970
        let halfLifeSeconds = 7.0 * 24 * 3600

        // 单次遍历聚合：score 累加 + latest 取最大时间戳。
        var scoreByID: [ToolID: Double] = [:]
        var latestByID: [ToolID: Date] = [:]
        for event in preferences.activity {
            guard knownToolIDs.contains(event.toolID) else { continue }
            let age = max(0, nowSeconds - event.timestamp.timeIntervalSince1970)
            scoreByID[event.toolID, default: 0] += pow(0.5, age / halfLifeSeconds)
            if let prev = latestByID[event.toolID], prev >= event.timestamp {
                continue
            }
            latestByID[event.toolID] = event.timestamp
        }

        return scoreByID.keys.sorted { lhs, rhs in
            let lhsScore = scoreByID[lhs] ?? 0
            let rhsScore = scoreByID[rhs] ?? 0
            if lhsScore != rhsScore { return lhsScore > rhsScore }
            return (latestByID[lhs] ?? .distantPast) > (latestByID[rhs] ?? .distantPast)
        }
        .prefix(limit)
        .map { $0 }
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

    @discardableResult
    private func trimActivity(reference: Date) -> Bool {
        guard let cutoff = calendar.date(byAdding: .day, value: -(Self.retentionDays - 1), to: calendar.startOfDay(for: reference)),
              preferences.activity.contains(where: { $0.timestamp < cutoff }) else { return false }
        preferences.activity.removeAll { $0.timestamp < cutoff }
        return true
    }

    private func persist() {
        persistence.enqueue(preferences)
    }

    private static func load(from defaults: UserDefaults) -> DashboardPreferences? {
        guard let data = defaults.data(forKey: persistenceKey), let decoded = try? JSONDecoder().decode(DashboardPreferences.self, from: data), decoded.version == DashboardPreferences.currentVersion else { return nil }
        return decoded
    }
}

/// 编码和 UserDefaults 写入串行执行；最多保留当前写入与最新待写两个快照。
/// 锁保护队列交接，UserDefaults 写入仅发生在串行 writer 上。
private final class DashboardPersistence: @unchecked Sendable {
    private let defaults: UserDefaults
    private let key: String
    private let queue = DispatchQueue(label: "XTools.DashboardPersistence", qos: .utility)
    private let lock = NSLock()
    private var latest: DashboardPreferences?
    private var isDraining = false

    init(defaults: UserDefaults, key: String) {
        self.defaults = defaults
        self.key = key
    }

    func enqueue(_ preferences: DashboardPreferences) {
        let shouldStart = lock.withLock {
            latest = preferences
            guard !isDraining else { return false }
            isDraining = true
            return true
        }
        if shouldStart { queue.async { self.drain() } }
    }

    func flush() {
        queue.sync {}
    }

    private func drain() {
        while let snapshot = lock.withLock({ () -> DashboardPreferences? in
            guard let snapshot = latest else {
                isDraining = false
                return nil
            }
            latest = nil
            return snapshot
        }) {
            if let data = try? JSONEncoder().encode(snapshot) {
                defaults.set(data, forKey: key)
            }
        }
    }
}
