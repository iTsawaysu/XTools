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
                resultState: execution.resultState,
                syntax: .plain,
                foldUnchanged: workspace.foldUnchanged,
                error: execution.binding.error,
                onClear: workspace.clear,
                clearDisabled: !workspace.hasAnyContent,
                leadingControl: {
                    HStack(spacing: 6) {
                        IndexOptionSwitch(title: "忽略空白", style: .button, isOn: $workspace.ignoreWhitespace)
                        IndexOptionSwitch(title: "忽略大小写", style: .button, isOn: $workspace.ignoreCase)
                        IndexIconButton(
                            systemImage: "chevron.up.chevron.down",
                            help: "折叠未变更行",
                            isActive: workspace.foldUnchanged
                        ) {
                            workspace.foldUnchanged.toggle()
                        }
                        .fixedSize(horizontal: true, vertical: false)
                    }
                }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }
}
