import SwiftUI

/// ToolPageStage 的挂载簿记：显示中的页面 + 有界 LRU 停靠页。
///
/// 01 景深沉降 的编排（离开 220ms productiveExit / 到达 300ms smoothOut）
/// 由视图层按原语义驱动；本类型只决定「谁在树上、谁停靠、何时静默淘汰」。
/// 停靠页留在 ZStack 里（透明、不可命中、无障碍隐藏、环境代际恒为 0），
/// 再次进入时复用原有页面身份，避免重建页面的本地状态与原生视图。
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
    /// 冷进入和回访共用的起始姿态，直到视图层接收这一代页面才释放。
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

    /// 登记新页或唤回停靠页；下一次视图更新先接收透明的到达起始姿态。
    func arrive(_ key: ToolPageKey) {
        if !mounted.contains(key) {
            mounted.append(key)
        }
        parked.remove(key)
        pendingArrivals.insert(key)
        displayOrder.removeAll { $0 == key }
        displayOrder.append(key)
        displayed = key
        generation &+= 1
    }

    /// 页面树接收起始姿态后开启到达动画；已离开或已换代的任务无效。
    func finishArrival(_ key: ToolPageKey, generation: Int) {
        guard displayed == key, self.generation == generation,
              pendingArrivals.contains(key) else { return }
        pendingArrivals.remove(key)
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
