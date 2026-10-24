import AppKit
import Combine
import Foundation

// MARK: - 旧仪表盘活动日志载荷（迁移只读）

/// 旧 `tools.dashboard.preferences.v1` 的事件条目。阶段③ frecency 单源后
/// 仪表盘数据并入 `ToolUsageFrequencyStore`；本结构仅用于首读迁移解码，
/// 不再产生新的持久化写入。
struct DashboardActivityEvent: Codable, Equatable {
    let id: UUID
    let toolID: ToolID
    let timestamp: Date

    init(id: UUID = UUID(), toolID: ToolID, timestamp: Date) {
        self.id = id
        self.toolID = toolID
        self.timestamp = timestamp
    }
}

/// 旧仪表盘持久化载荷。`cards` 键在 v1 历史数据中存在过(卡片布局系统
/// 已删);合成解码忽略未知键,旧持久化数据无需额外处理即可读入。
struct DashboardPreferences: Codable, Equatable {
    static let currentVersion = 1
    var version: Int = currentVersion
    var activity: [DashboardActivityEvent] = []
}

// MARK: - ToolUsageFrequencyStore

/// 全壳单一使用频率源（阶段③ 治理速赢 / PRD「双 frecency 引擎合一」）。
///
/// 吸收原 `DashboardStore` 与 `PaletteRecentsStore` 各自维护的同一指数衰减
/// 公式（半衰期 7 天：`0.5^(age / 7d)`）与事件环，两个消费方改为委托：
/// - `.navigation` 通道：全部导航路径（侧栏/工作台/⌘K 都经 selectTool 落
///   此），供仪表盘「最近/常用」读取；90 天日历保留（沿用 DashboardStore
///   语义，保留窗口锚定本地日 startOfDay）。
/// - `.palette` 通道：仅 ⌘K 激活（`RootView.launchFromPalette` 记录），供
///   面板落地页「最近使用」与 tier 内加权读取；96 条环上限（沿用原环
///   容量，~4KB JSON）。
///
/// 持久化沿用 `tools.palette.recents.v1`（JSON 数组，元素为
/// `{toolID, epochSeconds, channel?}`）。旧文件无 channel 字段——该键历史
/// 上只存 ⌘K 激活，解码缺省视为 `.palette`，天然兼容；写出时 Optional
/// channel 缺省省略，旧条目落盘形态不变。
///
/// 旧 JSON 首读迁移：`tools.dashboard.preferences.v1`（旧仪表盘自有活动
/// 日志）在首次构造时一次性导入为 `.navigation` 事件（该日志本就记录所有
/// 导航路径），随后以 `tools.usage.frequency.dashboardImport.v1` 位图键
/// 防止重复导入——否则已按 90 天窗口裁剪掉的旧事件会在每次重启时复活。
/// 旧键本身保留不删（只读迁移，可人工回滚）。
///
/// 本类型不是 ObservableObject：记录 launch 绝不触发壳层失效（⌘K 面板
/// 同步读取）；观察语义由 `DashboardStore` 门面的 `launchToken` 保留。
@MainActor
final class ToolUsageFrequencyStore {
    enum Channel: String, Codable {
        /// 仅 ⌘K 激活（面板落地页语义边界，见 PaletteRecentsStore）。
        case palette
        /// 全部导航路径（仪表盘「最近/常用」语义）。
        case navigation
    }

    struct UsageEvent: Codable, Equatable {
        let toolID: String
        let epochSeconds: TimeInterval
        /// 旧格式（无此字段）解码为 nil；nil 事件按 `.palette` 解读。
        var channel: Channel?

        /// 旧格式缺省通道：tools.palette.recents.v1 历史上只存 ⌘K 激活。
        var resolvedChannel: Channel { channel ?? .palette }
    }

    /// palette 环上限（沿用 PaletteRecentsStore.Metrics.eventCap）。
    static let paletteEventCap = 96
    /// navigation 通道保留窗口天数（沿用 DashboardStore.retentionDays）。
    static let navigationRetentionDays = 90
    /// 单源衰减半衰期（天）：`score += 0.5^(age / halfLife)`。
    static let halfLifeDays: Double = 7
    /// 旧仪表盘日志键（迁移只读；原 DashboardStore.persistenceKey）。
    static let legacyDashboardLogKey = "tools.dashboard.preferences.v1"
    /// 旧仪表盘日志一次性导入的位图键。
    static let dashboardImportFlagKey = "tools.usage.frequency.dashboardImport.v1"

    private(set) var events: [UsageEvent]
    private let persistence: ToolUsagePersistence?
    private let calendar: Calendar
    private let now: () -> Date
    private var terminationObserver: AnyCancellable?

    /// `defaults` 为 nil 时进入纯内存模式（单测/无持久化环境）：不读不写。
    init(defaults: UserDefaults?, calendar: Calendar = .current, now: @escaping () -> Date = Date.init) {
        self.calendar = calendar
        self.now = now
        let preferences = defaults.map { ToolPreferenceStore(defaults: $0) }
        self.persistence = defaults.map {
            ToolUsagePersistence(defaults: $0, key: AppShellPreferenceKeys.paletteRecents.rawKey)
        }
        var loaded = Self.loadPaletteRing(preferences: preferences)
        let imported = Self.importLegacyDashboardLog(defaults: defaults)
        loaded.append(contentsOf: imported)
        self.events = loaded
        terminationObserver = NotificationCenter.default
            .publisher(for: NSApplication.willTerminateNotification)
            .sink { [weak persistence] _ in persistence?.flush() }
        // 导入或修剪发生时立即落盘：迁移结果不能只活在内存里，否则下一次
        // 启动会因位图键已置位而丢失导入的历史。
        if !imported.isEmpty || trim(now: now()) { persist() }
    }

    deinit {
        persistence?.flush()
    }

    // MARK: 写入

    /// 记录一次启动。`date` 缺省用注入时钟（测试可注入确定时间）。
    func recordLaunch(_ toolID: ToolID, channel: Channel, at date: Date? = nil) {
        let timestamp = date ?? now()
        events.append(
            UsageEvent(
                toolID: toolID.rawValue,
                epochSeconds: timestamp.timeIntervalSince1970,
                channel: channel
            )
        )
        trim(now: now())
        persist()
    }

    // MARK: 读取（公式与聚合的唯一实现，两消费方委托至此）

    /// 指数衰减 frecency：每次启动贡献 `0.5^(age / 7天)`，今天用两次的工具
    /// 排在上周用过一次的前面。单源公式（原 DashboardStore:72-78 与
    /// PaletteRecentsStore 公式合并于此）。
    func frecencyScore(for toolID: ToolID, in channel: Channel, now: Date) -> Double {
        let rawID = toolID.rawValue
        let nowSeconds = now.timeIntervalSince1970
        let halfLifeSeconds = Self.halfLifeDays * 24 * 3600
        return events.reduce(into: 0.0) { score, event in
            guard event.toolID == rawID, event.resolvedChannel == channel else { return }
            let age = max(0, nowSeconds - event.epochSeconds)
            score += pow(0.5, age / halfLifeSeconds)
        }
    }

    /// 各工具最近一次启动时间（按通道过滤）——仪表盘「最近」行需要时间戳。
    func latestLaunchDates(in channel: Channel) -> [ToolID: Date] {
        var latestByID: [ToolID: Date] = [:]
        for event in events where event.resolvedChannel == channel {
            let date = Date(timeIntervalSince1970: event.epochSeconds)
            // 事件按时间追加，后来的时间戳无条件覆盖即保留最近一次。
            if let previous = latestByID[ToolID(rawValue: event.toolID)], previous >= date {
                continue
            }
            latestByID[ToolID(rawValue: event.toolID)] = date
        }
        return latestByID
    }

    /// 区分工具、按最近启动倒序的前 `limit` 个 ID（⌘K 落地页「最近使用」）。
    func recentToolIDs(in channel: Channel, limit: Int, now: Date) -> [ToolID] {
        guard limit > 0 else { return [] }
        return latestLaunchDates(in: channel)
            .sorted { lhs, rhs in lhs.value > rhs.value }
            .prefix(limit)
            .map(\.key)
    }

    /// Distinct tool IDs ordered by frecency (descending), filtered to the
    /// current registry. Ties break by most-recent launch.
    ///
    /// 性能：先在单次遍历里为每个 toolID 预计算 frecency 总分与最近时间戳，
    /// 再排序——避免 `sorted` 闭包对每对元素重复调用 O(events) 的
    /// `frecencyScore`（那会退化成 O(n² · events)）。
    func frecencyRankedToolIDs(
        in channel: Channel,
        knownToolIDs: Set<ToolID>,
        limit: Int,
        now: Date
    ) -> [ToolID] {
        guard limit > 0 else { return [] }

        let nowSeconds = now.timeIntervalSince1970
        let halfLifeSeconds = Self.halfLifeDays * 24 * 3600

        // 单次遍历聚合：score 累加 + latest 取最大时间戳。
        var scoreByID: [ToolID: Double] = [:]
        var latestByID: [ToolID: Date] = [:]
        for event in events where event.resolvedChannel == channel {
            let toolID = ToolID(rawValue: event.toolID)
            guard knownToolIDs.contains(toolID) else { continue }
            let age = max(0, nowSeconds - event.epochSeconds)
            scoreByID[toolID, default: 0] += pow(0.5, age / halfLifeSeconds)
            let timestamp = Date(timeIntervalSince1970: event.epochSeconds)
            if let previous = latestByID[toolID], previous >= timestamp {
                continue
            }
            latestByID[toolID] = timestamp
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

    // MARK: 保留窗口与持久化

    /// 双通道各自沿用旧保留语义；返回是否发生了修剪。
    @discardableResult
    private func trim(now reference: Date) -> Bool {
        var changed = false

        // navigation：90 天日历保留。窗口锚定当前本地日；导入或测试注入的
        // 事件时间戳不能把保留窗口拉向过去。
        if let cutoff = calendar.date(
            byAdding: .day,
            value: -(Self.navigationRetentionDays - 1),
            to: calendar.startOfDay(for: reference)
        ) {
            let cutoffSeconds = cutoff.timeIntervalSince1970
            let filtered = events.filter { event in
                event.resolvedChannel == .palette || event.epochSeconds >= cutoffSeconds
            }
            if filtered.count != events.count {
                events = filtered
                changed = true
            }
        }

        // palette：96 条环上限。事件按时间追加，顺序丢弃最旧的溢出条目
        // （等价旧实现 removeFirst(count - cap)）。
        let paletteCount = events.reduce(0) { $0 + ($1.resolvedChannel == .palette ? 1 : 0) }
        if paletteCount > Self.paletteEventCap {
            let overflow = paletteCount - Self.paletteEventCap
            var seenPaletteEvents = 0
            events = events.filter { event in
                guard event.resolvedChannel == .palette else { return true }
                seenPaletteEvents += 1
                return seenPaletteEvents > overflow
            }
            changed = true
        }

        return changed
    }

    private func persist() {
        persistence?.enqueue(events)
    }

    private static func loadPaletteRing(preferences: ToolPreferenceStore?) -> [UsageEvent] {
        guard let preferences else { return [] }
        let stored = preferences.value(for: AppShellPreferenceKeys.paletteRecents)
        guard let data = stored.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([UsageEvent].self, from: data)) ?? []
    }

    /// 旧仪表盘活动日志的一次性首读迁移（详见类型注释）。无论解码成败都
    /// 落位图键：损坏的旧日志不值得每次启动重试。
    private static func importLegacyDashboardLog(defaults: UserDefaults?) -> [UsageEvent] {
        guard let defaults, !defaults.bool(forKey: dashboardImportFlagKey) else { return [] }
        defer { defaults.set(true, forKey: dashboardImportFlagKey) }
        guard let data = defaults.data(forKey: legacyDashboardLogKey),
              let legacy = try? JSONDecoder().decode(DashboardPreferences.self, from: data),
              legacy.version == DashboardPreferences.currentVersion
        else { return [] }
        return legacy.activity.map { event in
            UsageEvent(
                toolID: event.toolID.rawValue,
                epochSeconds: event.timestamp.timeIntervalSince1970,
                channel: .navigation
            )
        }
    }
}

// MARK: - ToolUsagePersistence

/// 编码和 UserDefaults 写入串行执行；最多保留当前写入与最新待写两个快照。
/// 锁保护队列交接，UserDefaults 写入仅发生在串行 writer 上。
///
/// 写入直连 UserDefaults（utility 队列）而非 MainActor 的
/// `ToolPreferenceStore.set`：navigation 事件随每次工具切换追加，主线程
/// 逐次编码整本日志会拖慢切页热路径（沿用旧 DashboardStore 的后台写纪律，
/// 配套 willTerminate/deinit flush 保证发布前可见）。键字符串仍单源自
/// `AppShellPreferenceKeys.paletteRecents.rawKey`，schema 归属不变。
private final class ToolUsagePersistence: @unchecked Sendable {
    private let defaults: UserDefaults
    private let key: String
    private let queue = DispatchQueue(label: "XTools.ToolUsagePersistence", qos: .utility)
    private let lock = NSLock()
    private var latest: [ToolUsageFrequencyStore.UsageEvent]?
    private var isDraining = false

    init(defaults: UserDefaults, key: String) {
        self.defaults = defaults
        self.key = key
    }

    func enqueue(_ events: [ToolUsageFrequencyStore.UsageEvent]) {
        let shouldStart = lock.withLock {
            latest = events
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
        while let snapshot = lock.withLock({ () -> [ToolUsageFrequencyStore.UsageEvent]? in
            guard let snapshot = latest else {
                isDraining = false
                return nil
            }
            latest = nil
            return snapshot
        }) {
            if let data = try? JSONEncoder().encode(snapshot),
               let stored = String(data: data, encoding: .utf8) {
                defaults.set(stored, forKey: key)
            }
        }
    }
}
