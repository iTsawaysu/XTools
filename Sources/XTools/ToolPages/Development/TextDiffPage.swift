import SwiftUI

/// 「对比」Hub 的文本分段，与 JSON 分段共用工具身份，分别保留草稿。
struct IndexTextDiffSegment: View {
    static let key = ToolWorkspaceKey<DiffToolWorkspaceModel>(toolID: "diff", slot: "text") { _ in
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
                    ToolButton(
                        systemImage: "chevron.up.chevron.down",
                        role: .secondary,
                        size: .compact28,
                        state: workspace.foldUnchanged ? .active : .idle,
                        help: "折叠未变更行",
                        accessibilityLabel: "折叠未变更行"
                    ) {
                        workspace.foldUnchanged.toggle()
                    }
                    .fixedSize(horizontal: true, vertical: false)
                }
            }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear(perform: workspace.restoreResultIfNeeded)
    }
}
