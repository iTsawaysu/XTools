import Foundation

/// 多窗口共享单例束（阶段③ Batch D，design.md §9）：WindowGroup 化后每个
/// 窗口一棵 RootView，收藏 / 使用频率 / 偏好 / 侧栏折叠 / 工作台仓库必须
/// 跨窗口一致——App 层构造一份，经 RootView init 注入每个窗口（B/C 批
/// 「init 构造 + 引用透传」范式的多窗口升级）。
///
/// 每窗口独立的部分（刻意不在这里）：ShellNavigationModel（选中/搜索/
/// 面板）、Toast/HUD、SmartPaste、DashboardStore 门面（数据仍走共享
/// usageFrequency 单源，观察语义每窗口自有）。
///
/// `launchedWindowCount` 驱动「新窗口默认仪表盘」：首个 RootView（首窗）
/// 保留恢复语义（autoResume/收藏优先默认落点），后续窗口不恢复——选中
/// 保持 nil，落到仪表盘。测试构造（每次传独立 store 实例）天然是「首窗」，
/// 行为与旧单窗口版等价。
@MainActor
final class ShellSharedStores {
    let preferences: ToolPreferenceStore
    let usageFrequency: ToolUsageFrequencyStore
    let paletteRecents: PaletteRecentsStore
    let favorites: FavoritesStore
    let sidebarSections: SidebarSectionExpansionStore
    let workspaceRepository: ToolWorkspaceRepository

    private(set) var launchedWindowCount = 0

    init(defaults: UserDefaults = .standard) {
        let preferences = ToolPreferenceStore(defaults: defaults)
        self.preferences = preferences
        self.usageFrequency = ToolUsageFrequencyStore(defaults: defaults)
        self.paletteRecents = PaletteRecentsStore(usage: usageFrequency)
        let validToolIDs = Set(
            ToolRegistry.default.categoryGroups().flatMap { $0.tools.map(\.id) }
        )
        self.favorites = FavoritesStore(defaults: defaults, validToolIDs: validToolIDs)
        self.sidebarSections = SidebarSectionExpansionStore(defaults: defaults)
        self.workspaceRepository = ToolWorkspaceRepository(preferences: preferences)
    }

    /// 窗口认领：返回是否为本 store 的首个窗口（true = 保留恢复语义）。
    func claimWindowLaunch() -> Bool {
        let isFirst = launchedWindowCount == 0
        launchedWindowCount += 1
        return isFirst
    }
}
