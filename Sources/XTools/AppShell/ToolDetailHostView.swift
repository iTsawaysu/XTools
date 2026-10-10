import SwiftUI

/// 工具页列的动作出口。动作经一个生命周期与视图一致的对象转发，而不是
/// 每次 body 重估都生成新闭包：SwiftUI 按值比较子视图输入，新闭包必然
/// 判定不等，会让 detail 列（含当前工具页整棵树）在每次 shell 抖动（侧栏
/// 键入、toast、建议横幅）时整链重估并重跑 makePage()。引用类型的路由盒
/// 让输入退化为可指针比较的稳定值。
@MainActor
protocol DetailActionRouting: AnyObject {
    func selectTool(_ toolID: ToolID)
}

struct ToolDetailHostView: View {
    let registry: ToolRegistry
    let selectedToolID: ToolID?
    let dashboardStore: DashboardStore?
    let routing: any DetailActionRouting

    init(
        registry: ToolRegistry,
        selectedToolID: ToolID?,
        dashboardStore: DashboardStore? = nil,
        routing: any DetailActionRouting
    ) {
        self.registry = registry
        self.selectedToolID = selectedToolID
        self.dashboardStore = dashboardStore
        self.routing = routing
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
                routing: routing
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
    let routing: any DetailActionRouting

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.key == rhs.key &&
        lhs.dashboardStore === rhs.dashboardStore &&
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
                        Color.clear
                            .frame(width: 0, height: 0)
                            .id(tool.id)
                            .onAppear { ToolPageEntryTrace.pageAppeared(traceContext) }
                    }
                    .toolPageArrival(id: tool.id.rawValue)
            }
        case .dashboard:
            if let dashboardStore {
                DashboardView(
                    store: dashboardStore,
                    registry: registry,
                    onSelectTool: { routing.selectTool($0) }
                )
                .toolPageArrival(id: "dashboard")
            }
        case .emptySelection:
            EmptyToolSelectionView()
                .toolPageArrival(id: "empty-selection")
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
