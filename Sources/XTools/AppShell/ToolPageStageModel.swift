import SwiftUI

/// ToolPageStage 的挂载簿记：显示中的页面 + 有界 LRU 停靠页。
///
/// 01 景深沉降 的双事务编排（离开 220ms productiveExit / 到达 300ms smoothOut）
/// 由视图层按原语义驱动；本类型只决定「谁在树上、谁停靠、何时静默淘汰」。
/// 停靠页留在 ZStack 里（透明、不可命中、无障碍隐藏、环境代际恒为 0），
/// 再次进入时无需重建整棵页面树——重页面的回访成本从建树级降到接近零。
/// 淘汰按最久显示优先，在禁用动画的事务里静默进行，不重播任何过渡。
@MainActor
final class ToolPageStageModel: ObservableObject {
    /// 同时停靠（挂载但非显示）的最大页面数；超出按 LRU 静默淘汰。
    /// 3 个停靠 + 1 个显示页在「常用页面往返」与常驻内存之间取得平衡；
    /// 停靠页仍随 workspace 模型响应更新，容量越大常驻渲染树越多。
    static let parkedCapacity = 3

    @Published private(set) var mounted: [ToolPageKey] = []
    @Published private(set) var parked: Set<ToolPageKey> = []
    @Published private(set) var displayed: ToolPageKey?

    /// 每次到达（含回访停靠页）递增；视图层把它注入显示页的环境，供
    /// 「每次进入都要发生」的行为（页头逐字动画、自动聚焦等）以
    /// onChange 驱动，保持与整页重建时代完全一致的进入语义。
    @Published private(set) var generation = 1

    /// 最久显示优先的顺序表（尾部 = 最近显示）。
    private var displayOrder: [ToolPageKey] = []
    /// 回访停靠页前的一次性形态：视图层据此无动画跳到到达起始姿态。
    @Published private(set) var pendingArrivals: Set<ToolPageKey> = []

    func isParked(_ key: ToolPageKey) -> Bool {
        parked.contains(key)
    }

    /// 首次挂载或 Reduce Motion：无动画直达。停靠页全部释放（Reduce Motion
    /// 路径不保留渲染树，回到单页挂载的最小形态）。
    func swapImmediately(to key: ToolPageKey) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            mounted = [key]
            parked = []
            pendingArrivals = []
            displayOrder = [key]
            displayed = key
            generation &+= 1
        }
    }

    /// 离开事务（pageDeparture）内调用：旧页从显示转为停靠。
    func depart(_ key: ToolPageKey) {
        guard key == displayed else { return }
        displayed = nil
        parked.insert(key)
        pendingArrivals.remove(key)
    }

    /// 离开动画（220ms productiveExit）结束后调用：将停靠页无动画静默置入到达起始姿态
    /// （透明 + 上浮 10pt + 0.995 缩放）。因透明度已为 0，静默置位在屏幕上完全不可见；
    /// 之后用户再次回访该页时，视图层即可从该起始姿态播放完整到达动画（含 10pt 浮起与缩放回正）。
    func settleParkedForArrival(_ key: ToolPageKey) {
        guard parked.contains(key), displayed != key else { return }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            _ = pendingArrivals.insert(key)
        }
    }

    /// 到达事务（pageArrival）内调用：呈现新页或唤回停靠页。
    func arrive(_ key: ToolPageKey) {
        if !mounted.contains(key) {
            mounted.append(key)
        }
        parked.remove(key)
        pendingArrivals.remove(key)
        displayOrder.removeAll { $0 == key }
        displayOrder.append(key)
        displayed = key
        generation &+= 1
    }

    /// 唤回停靠页的事务前调用：标记一次性到达起始姿态（透明 + 上浮 +
    /// 99.5% 缩放），使唤回动画与全新插入的到达过渡逐帧一致。
    func stageArrivalStart(_ key: ToolPageKey) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            _ = pendingArrivals.insert(key)
        }
    }

    /// 超出停靠容量的页面按 LRU 静默淘汰（透明页移除无可见过渡）。
    func evictOverflow() {
        guard parked.count > Self.parkedCapacity else { return }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            while parked.count > Self.parkedCapacity,
                  let victim = displayOrder.first(where: parked.contains) ?? parked.first {
                parked.remove(victim)
                pendingArrivals.remove(victim)
                mounted.removeAll { $0 == victim }
                displayOrder.removeAll { $0 == victim }
            }
        }
    }
}
