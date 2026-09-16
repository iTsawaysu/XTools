import SwiftUI

struct IndexTextDiffPage: View {
    private static let key = ToolWorkspaceKey<DiffToolWorkspaceModel>(toolID: "text-diff") { _ in
        DiffToolWorkspaceModel(kind: .text)
    }

    var body: some View {
        ToolWorkspaceHost(key: Self.key) { workspace, _ in
            IndexTextDiffWorkspaceContent(
                workspace: workspace,
                execution: workspace.execution
            )
        }
    }
}

private struct IndexTextDiffWorkspaceContent: View {
    @ObservedObject var workspace: DiffToolWorkspaceModel
    @ObservedObject var execution: DiffExecutionSession

    var body: some View {
        IndexPage(
            "文本对比",
            subtitle: "逐行对比两段文本的差异。",
            workspaceSemantic: .editableDiffWorkspace
        ) {
            IndexEditableDiffWorkspace(
                inputTitle: "原始文本",
                outputTitle: "对比文本",
                leftPlaceholder: "原始文本…",
                rightPlaceholder: "对比文本…",
                left: $workspace.left,
                right: $workspace.right,
                rows: execution.binding.rows,
                syntax: .plain,
                error: execution.binding.error,
                onClear: workspace.clear,
                clearDisabled: !workspace.hasAnyContent
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }
}
