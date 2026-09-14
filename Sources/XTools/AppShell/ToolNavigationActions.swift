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

    func selectDefaultToolIfNeeded(_ defaultToolID: ToolID?) {
        if viewModel.autoResumeLastTool,
           let selectedToolID = viewModel.selectedToolID,
           registry.tool(for: selectedToolID) != nil { return }

        guard viewModel.autoResumeLastTool, let defaultToolID else {
            viewModel.selectedToolID = nil
            return
        }
        _ = selectTool(defaultToolID)
    }

    @discardableResult
    func selectTool(_ toolID: ToolID, dismissCommandPalette: Bool = false) -> Bool {
        guard let tool = registry.tool(for: toolID),
              let section = section(for: toolID) else { return false }

        let previousToolID = viewModel.selectedToolID
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
