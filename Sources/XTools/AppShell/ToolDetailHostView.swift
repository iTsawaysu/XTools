import SwiftUI

struct ToolDetailHostView: View {
    let registry: ToolRegistry
    let selectedToolID: ToolID?
    let dashboardStore: DashboardStore?
    let favoriteIDs: [ToolID]
    let onSelectTool: (ToolID) -> Void
    let onOpenCommandPalette: () -> Void
    let autoResumeLastTool: Bool
    let onSetAutoResumeLastTool: @MainActor @Sendable (Bool) -> Void

    init(registry: ToolRegistry, selectedToolID: ToolID?, dashboardStore: DashboardStore? = nil,
         favoriteIDs: [ToolID] = [], onSelectTool: @escaping (ToolID) -> Void = { _ in },
         onOpenCommandPalette: @escaping () -> Void = {}, autoResumeLastTool: Bool = false,
         onSetAutoResumeLastTool: @escaping @MainActor @Sendable (Bool) -> Void = { _ in }) {
        self.registry = registry; self.selectedToolID = selectedToolID; self.dashboardStore = dashboardStore
        self.favoriteIDs = favoriteIDs; self.onSelectTool = onSelectTool; self.onOpenCommandPalette = onOpenCommandPalette
        self.autoResumeLastTool = autoResumeLastTool; self.onSetAutoResumeLastTool = onSetAutoResumeLastTool
    }

    var body: some View {
        Group {
            if let selectedToolID,
               let tool = registry.tool(for: selectedToolID) {
                let traceContext = ToolPageEntryTraceContext(toolID: tool.id, title: tool.title)
                tracedPage(for: tool)
                    .environment(\.toolPageEntryTraceContext, traceContext)
                    .background {
                        Color.clear
                            .frame(width: 0, height: 0)
                            .id(tool.id)
                            .onAppear { ToolPageEntryTrace.pageAppeared(traceContext) }
                    }
            } else {
                if let dashboardStore {
                    DashboardView(store: dashboardStore, registry: registry, favoriteIDs: favoriteIDs,
                                  onSelectTool: onSelectTool, onOpenCommandPalette: onOpenCommandPalette,
                                  autoResumeLastTool: autoResumeLastTool,
                                  onSetAutoResumeLastTool: onSetAutoResumeLastTool)
                } else {
                    EmptyToolSelectionView()
                }
            }
        }
        .toolPageArrival(id: pageArrivalID)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ToolTheme.workspaceBackground)
    }

    /// Identity of the currently presented page: one tool id, or the dashboard
    /// bucket when no tool is selected. Tool switches (and tool↔dashboard
    /// swaps) replay the shared `pageArrival` transition through this id.
    private var pageArrivalID: String {
        selectedToolID?.rawValue ?? "dashboard"
    }

    private func tracedPage(for tool: RegisteredTool) -> AnyView {
        ToolPageEntryTrace.makePageStarted(tool)
        let page = tool.makePage()
        ToolPageEntryTrace.makePageFinished(tool)
        return page
    }
}

private struct EmptyToolSelectionView: View {
    var body: some View {
        IndexEmptyState(
            title: "选择一个工具",
            systemImage: "wrench.and.screwdriver",
            message: "从侧边栏选择工具，或按 ⌘K 搜索。"
        )
    }
}
