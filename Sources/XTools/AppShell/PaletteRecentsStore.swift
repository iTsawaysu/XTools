import Foundation

/// Read-side usage scoring the palette ranks with (recents list + frecency
/// boost). MainActor-isolated because the write side owns mutable state; the
/// palette consumes it from its session model.
@MainActor
protocol PaletteUsageScoring {
    /// Exponential-decay frecency: each launch contributes 0.5^(age / 7 days),
    /// so a tool used twice today outranks one used once last week.
    func frecencyScore(for toolID: ToolID, now: Date) -> Double

    /// Distinct tools ordered by most-recent launch, oldest last.
    func recentToolIDs(limit: Int, now: Date) -> [ToolID]
}

/// Zero-usage stand-in: fresh installs and unit tests keep the registry's
/// curated ordering untouched.
struct NoPaletteUsage: PaletteUsageScoring {
    func frecencyScore(for toolID: ToolID, now: Date) -> Double {
        0
    }

    func recentToolIDs(limit: Int, now: Date) -> [ToolID] {
        []
    }
}

/// ⌘K 面板使用频率的门面（阶段③ frecency 单源后）：事件环、指数衰减公式
/// 与持久化全部在 `ToolUsageFrequencyStore`，本适配器只把「仅 ⌘K 激活」的
/// 语义固定为 `.palette` 通道委托——侧栏与工作台启动刻意不入此通道，落地
/// 页「最近使用」反映 ⌘K 使用本身而非一般导航。
///
/// 非 ObservableObject 的契约不变：记录 launch 绝不令壳层失效，面板组装
/// 快照时同步读取。持久化沿用 `tools.palette.recents.v1`（单源 store 统一
/// 读写；旧 JSON 首读迁移见 `ToolUsageFrequencyStore` 类型注释）。
@MainActor
final class PaletteRecentsStore: PaletteUsageScoring {
    private let usage: ToolUsageFrequencyStore

    init(usage: ToolUsageFrequencyStore) {
        self.usage = usage
    }

    func recordLaunch(_ toolID: ToolID, at date: Date = Date()) {
        usage.recordLaunch(toolID, channel: .palette, at: date)
    }

    func frecencyScore(for toolID: ToolID, now: Date) -> Double {
        usage.frecencyScore(for: toolID, in: .palette, now: now)
    }

    func recentToolIDs(limit: Int, now: Date) -> [ToolID] {
        usage.recentToolIDs(in: .palette, limit: limit, now: now)
    }
}
