import Foundation

struct DashboardRecentTool: Codable, Equatable, Identifiable {
    let toolID: ToolID
    let lastOpenedAt: Date
    var id: ToolID { toolID }
}

/// 仪表盘「最近/常用」的门面（阶段③ frecency 单源）：事件环、指数衰减
/// 公式与持久化全部在 `ToolUsageFrequencyStore`，本类型只保留
/// ObservableObject 观察语义与投影 API，读写一律委托。
@MainActor
final class DashboardStore: ObservableObject {
    /// 每接受一次 launch 自增：保留旧「activity 日志变更即发布」的观察
    /// 语义（RootView 以 @StateObject 订阅，工具切换照常令壳层失效一次；
    /// 单源 store 本身刻意不发布，面板记录路径不受影响）。
    @Published private(set) var launchToken = 0

    private let usage: ToolUsageFrequencyStore

    init(usage: ToolUsageFrequencyStore) {
        self.usage = usage
    }

    /// 最近使用的工具（navigation 通道）：按各工具最近一次启动时间倒序。
    var recentTools: [DashboardRecentTool] {
        usage.latestLaunchDates(in: .navigation)
            .map { DashboardRecentTool(toolID: $0.key, lastOpenedAt: $0.value) }
            .sorted { $0.lastOpenedAt > $1.lastOpenedAt }
    }

    /// Recent tools whose IDs are present in the current registry. Persisted
    /// history may outlive a removed tool; callers can pass the registry IDs
    /// before presenting rows so stale entries never reach the UI.
    func recentTools(knownToolIDs: Set<ToolID>) -> [DashboardRecentTool] {
        recentTools.filter { knownToolIDs.contains($0.toolID) }
    }

    /// Distinct tool IDs ordered by frecency (descending), filtered to the
    /// current registry. Ties break by most-recent launch.
    ///
    /// 衰减公式、单次遍历聚合与 90 天保留窗口都在单源
    /// `ToolUsageFrequencyStore`（性能注释随实现）。
    func frecencyRankedToolIDs(knownToolIDs: Set<ToolID>, limit: Int, now: Date = Date()) -> [ToolID] {
        usage.frecencyRankedToolIDs(
            in: .navigation,
            knownToolIDs: knownToolIDs,
            limit: limit,
            now: now
        )
    }

    func recordLaunch(toolID: ToolID, at date: Date? = nil) {
        usage.recordLaunch(toolID, channel: .navigation, at: date)
        launchToken += 1
    }

    func recordLaunchIfChanged(toolID: ToolID, previousToolID: ToolID?, at date: Date? = nil) {
        guard previousToolID != toolID else { return }
        recordLaunch(toolID: toolID, at: date)
    }
}
