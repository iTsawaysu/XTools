import SwiftUI

/// 工具页列的动作出口。动作经一个生命周期与视图一致的对象转发，而不是
/// 每次 body 重估都生成新闭包：SwiftUI 按值比较子视图输入，新闭包必然
/// 判定不等，会让 detail 列（含当前工具页整棵树）在每次 shell 抖动（侧栏
/// 键入、toast、建议横幅）时整链重估并重跑 makePage()。引用类型的路由盒
/// 让输入退化为可指针比较的稳定值。
@MainActor
protocol DetailActionRouting: AnyObject, Sendable {
    func selectTool(_ toolID: ToolID)
    func selectCategory(_ categoryID: ToolCategoryID)
    func openCommandPalette()
}

struct ToolDetailHostView: View {
    let registry: ToolRegistry
    let selectedToolID: ToolID?
    let dashboardStore: DashboardStore?
    let workspaceRepository: ToolWorkspaceRepository
    let favorites: FavoritesStore
    let routing: any DetailActionRouting
    let smartPaste: SmartPasteMonitor
    let onOpenClipboardSuggestion: (SmartPasteMonitor.Suggestion) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let suggestion = smartPaste.suggestion
        VStack(spacing: 0) {
            ToolPageStage(target: pageKey, workspaceRepository: workspaceRepository) { key in
                ToolPageHostedItem(
                    key: key,
                    registry: registry,
                    dashboardStore: dashboardStore,
                    favorites: favorites,
                    routing: routing,
                    clipboardSuggestion: suggestion,
                    onOpenClipboardSuggestion: onOpenClipboardSuggestion,
                    onDismissClipboardSuggestion: smartPaste.dismiss
                )
                .equatable()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(ToolTheme.workspaceBackground)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ToolTheme.workspaceBackground)
        .toolAnimation(ToolMotion.Preset.pageEnter, value: selectedToolID)
        .overlay(alignment: .top) {
            if selectedToolID != nil, let suggestion {
                SmartPasteSuggestionBanner(
                    suggestion: suggestion,
                    onOpen: { onOpenClipboardSuggestion(suggestion) },
                    onDismiss: smartPaste.dismiss
                )
                .id(suggestion)
                .padding(.top, ToolMetrics.Spacing.md)
                .padding(.horizontal, ToolMetrics.Spacing.lg)
                .toolTransition(ToolMotion.Transition.toastPanel, reduceMotion: reduceMotion)
            }
        }
        .toolAnimation(ToolMotion.Preset.panelReveal, reduceMotion: reduceMotion, value: suggestion)
    }

    private var pageKey: ToolPageKey {
        if let selectedToolID,
           let tool = registry.tool(for: selectedToolID) {
            return .tool(tool.id)
        }
        return dashboardStore != nil ? .dashboard : .emptySelection
    }

    static func tracedPage(for tool: RegisteredTool) -> AnyView {
        ToolPageEntryTrace.makePageStarted(tool)
        let page = tool.makePage()
        ToolPageEntryTrace.makePageFinished(tool)
        return page
    }
}

private struct ToolPageHostedItem: View, Equatable {
    let key: ToolPageKey
    let registry: ToolRegistry
    let dashboardStore: DashboardStore?
    let favorites: FavoritesStore
    let routing: any DetailActionRouting
    let clipboardSuggestion: SmartPasteMonitor.Suggestion?
    let onOpenClipboardSuggestion: ((SmartPasteMonitor.Suggestion) -> Void)?
    let onDismissClipboardSuggestion: (() -> Void)?

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.key == rhs.key else { return false }
        guard lhs.key == .dashboard else { return true }
        return lhs.dashboardStore === rhs.dashboardStore
            && lhs.favorites === rhs.favorites
            && lhs.clipboardSuggestion == rhs.clipboardSuggestion
            && lhs.routing === rhs.routing
    }

    var body: some View {
        switch key.payload {
        case .tool(let toolID):
            if let tool = registry.tool(for: toolID) {
                let traceContext = ToolPageEntryTraceContext(toolID: tool.id, title: tool.title)
                ToolDetailHostView.tracedPage(for: tool)
                    .environment(\.toolPageEntryTraceContext, traceContext)
                    .background {
                        ToolPageEntryTraceProbe(context: traceContext)
                    }
            }
        case .dashboard:
            if let dashboardStore {
                DashboardView(
                    store: dashboardStore,
                    registry: registry,
                    favorites: favorites,
                    routing: routing,
                    clipboardSuggestion: clipboardSuggestion,
                    onOpenClipboardSuggestion: onOpenClipboardSuggestion,
                    onDismissClipboardSuggestion: onDismissClipboardSuggestion
                )
            }
        case .emptySelection:
            EmptyToolSelectionView()
        }
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
