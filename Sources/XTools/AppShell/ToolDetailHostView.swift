import SwiftUI

/// 工具页列的动作出口。动作经一个生命周期与视图一致的对象转发，而不是
/// 每次 body 重估都生成新闭包：SwiftUI 按值比较子视图输入，新闭包必然
/// 判定不等，会让 detail 列（含当前工具页整棵树）在每次 shell 抖动（侧栏
/// 键入、toast、建议横幅）时整链重估并重跑 makePage()。引用类型的路由盒
/// 让输入退化为可指针比较的稳定值。
@MainActor
protocol DetailActionRouting: AnyObject {
    func selectTool(_ toolID: ToolID)
    func selectCategory(_ categoryID: ToolCategoryID)
    func openCommandPalette()
}

struct ToolDetailHostView: View {
    let registry: ToolRegistry
    let selectedToolID: ToolID?
    let dashboardStore: DashboardStore?
    let favorites: FavoritesStore
    let routing: any DetailActionRouting
    let clipboardSuggestion: SmartPasteMonitor.Suggestion?
    let onOpenClipboardSuggestion: ((SmartPasteMonitor.Suggestion) -> Void)?
    let onDismissClipboardSuggestion: (() -> Void)?

    init(
        registry: ToolRegistry,
        selectedToolID: ToolID?,
        dashboardStore: DashboardStore? = nil,
        favorites: FavoritesStore,
        routing: any DetailActionRouting,
        clipboardSuggestion: SmartPasteMonitor.Suggestion? = nil,
        onOpenClipboardSuggestion: ((SmartPasteMonitor.Suggestion) -> Void)? = nil,
        onDismissClipboardSuggestion: (() -> Void)? = nil
    ) {
        self.registry = registry
        self.selectedToolID = selectedToolID
        self.dashboardStore = dashboardStore
        self.favorites = favorites
        self.routing = routing
        self.clipboardSuggestion = clipboardSuggestion
        self.onOpenClipboardSuggestion = onOpenClipboardSuggestion
        self.onDismissClipboardSuggestion = onDismissClipboardSuggestion
    }

    var body: some View {
        // 01 景深沉降: every navigation path lands here as one `target` key,
        // so tool pages, the dashboard, and the empty state share the same
        // page swap choreography (see `ToolPageStage`).
        ToolPageStage(target: pageKey) { key in
            ToolPageHostedItem(
                key: key,
                registry: registry,
                dashboardStore: dashboardStore,
                favorites: favorites,
                routing: routing,
                clipboardSuggestion: clipboardSuggestion,
                onOpenClipboardSuggestion: onOpenClipboardSuggestion,
                onDismissClipboardSuggestion: onDismissClipboardSuggestion
            )
            .equatable()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ToolTheme.workspaceBackground)
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
        // registry 不参与比较：ToolRegistry 是不可变值（RootView 持有
        // ToolRegistry.default），页面内容只随 key/dashboardStore/favorites/routing 变化。
        lhs.key == rhs.key &&
        lhs.dashboardStore === rhs.dashboardStore &&
        lhs.favorites === rhs.favorites &&
        lhs.clipboardSuggestion == rhs.clipboardSuggestion &&
        MainActor.assumeIsolated { lhs.routing === rhs.routing }
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
