import Foundation

@MainActor
struct ToolNavigationActions {
    let registry: ToolRegistry
    let viewModel: RootViewModel
    let favorites: FavoritesStore
    let sidebarSections: SidebarSectionExpansionStore
    let dashboardStore: DashboardStore?

    init(registry: ToolRegistry, viewModel: RootViewModel, favorites: FavoritesStore,
         sidebarSections: SidebarSectionExpansionStore, dashboardStore: DashboardStore? = nil) {
        self.registry = registry
        self.viewModel = viewModel
        self.favorites = favorites
        self.sidebarSections = sidebarSections
        self.dashboardStore = dashboardStore
    }

    func selectDefaultToolIfNeeded(_ registryDefaultToolID: ToolID?) {
        if viewModel.autoResumeLastTool,
           let selectedToolID = viewModel.selectedToolID,
           registry.tool(for: selectedToolID) != nil { return }

        // 收藏优先的默认落点（注册表序首个收藏 → 注册表序首个工具）。
        // 原投影的 favorite-first 语义平移到动作层：投影自阶段③ B 起不读
        // 收藏（rootBody=0 契约，收藏切换不触发壳层重估）。
        let defaultToolID = registry.tools(for: favorites.favoriteIDs).first?.id
            ?? registryDefaultToolID

        guard viewModel.autoResumeLastTool, let defaultToolID else {
            viewModel.selectedToolID = nil
            return
        }
        _ = selectTool(defaultToolID)
    }

    @discardableResult
    func selectTool(
        _ toolID: ToolID,
        dismissCommandPalette: Bool = false,
        intent: ToolPageTransitionIntent? = nil
    ) -> Bool {
        guard let tool = registry.tool(for: toolID),
              let section = section(for: toolID) else { return false }

        let previousToolID = viewModel.selectedToolID
        let previousCategory = previousToolID.flatMap { registry.tool(for: $0)?.categoryID }
        viewModel.pageTransitionIntent = intent ?? .resolved(
            previousCategory: previousCategory,
            nextCategory: tool.categoryID
        )
        ToolPageEntryTrace.toolSelected(tool)
        viewModel.selectedToolID = toolID
        dashboardStore?.recordLaunchIfChanged(toolID: toolID, previousToolID: previousToolID)
        sidebarSections.expand(section.groupID)

        if dismissCommandPalette {
            viewModel.closeCommandPalette()
        }

        return true
    }

    @discardableResult
    func toggleFavorite(_ toolID: ToolID) -> Bool? {
        guard let tool = registry.tool(for: toolID) else { return nil }

        let isFavorite = favorites.toggle(toolID)
        let section: ToolNavigationSection = isFavorite
            ? .favorites
            : .category(tool.categoryID)
        sidebarSections.expand(section.groupID)
        return isFavorite
    }

    /// ⌘1…⌘8 category jumps: open the first tool of the nth category in
    /// registry order. The jump runs through `selectTool`, so section
    /// expansion and launch tracking stay on the shared path.
    @discardableResult
    func selectCategory(at index: Int) -> Bool {
        let groups = registry.categoryGroups()
        guard groups.indices.contains(index),
              let firstTool = groups[index].tools.first
        else {
            return false
        }
        return selectTool(firstTool.id)
    }

    /// 收藏区拖拽排序写回（原生 List `.onMove` → 动作缝 → FavoritesStore；
    /// 数组序即 tools.favorites.v1 持久化序，格式兼容）。
    func moveFavorites(_ fromOffsets: IndexSet, toOffset: Int) {
        favorites.move(fromOffsets: fromOffsets, toOffset: toOffset)
    }

    func isSectionExpanded(_ section: ToolNavigationSection) -> Bool {
        sidebarSections.isExpanded(section.groupID)
    }

    func toggleSection(_ section: ToolNavigationSection, exclusive: Bool = false) {
        if exclusive {
            let allGroupIDs = registry.categoryGroups().map { ToolNavigationSection.category($0.category.id).groupID }
                + [ToolNavigationSection.favorites.groupID]
            sidebarSections.toggleSolo(section.groupID, allGroupIDs: allGroupIDs)
        } else {
            sidebarSections.toggle(section.groupID)
        }
    }

    func openCommandPalette() {
        viewModel.openCommandPalette()
    }

    func toggleCommandPalette() {
        viewModel.toggleCommandPalette()
    }

    func openDashboard() {
        viewModel.closeCommandPalette()
        viewModel.selectedToolID = nil
    }

    func closeCommandPalette() {
        viewModel.closeCommandPalette()
    }

    private func section(for toolID: ToolID) -> ToolNavigationSection? {
        guard let tool = registry.tool(for: toolID) else { return nil }
        return favorites.isFavorite(toolID)
            ? .favorites
            : .category(tool.categoryID)
    }
}
