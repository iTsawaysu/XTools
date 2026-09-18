import XToolsCore
import SwiftUI

@MainActor
final class DiffToolWorkspaceModel: ObservableObject {
    @Published var left = "" {
        didSet { draftDidChange() }
    }
    @Published var right = "" {
        didSet { draftDidChange() }
    }
    @Published var ignoreWhitespace: Bool = false {
        didSet { optionDidChange() }
    }
    @Published var ignoreCase: Bool = false {
        didSet { optionDidChange() }
    }
    @Published var ignoreArrayOrder: Bool = false {
        didSet { optionDidChange() }
    }
    @Published var foldUnchanged: Bool = false

    let execution: DiffExecutionSession
    let kind: DiffExecutionKind
    private let operation: DiffExecutionOperation
    private let debounce: Duration
    private var isMutatingDrafts = false

    init(
        kind: DiffExecutionKind = .text,
        debounce: Duration = .milliseconds(200),
        operation: @escaping DiffExecutionOperation = DiffExecutionSession.defaultOperation
    ) {
        self.kind = kind
        self.debounce = debounce
        self.operation = operation
        self.execution = DiffExecutionSession()
    }

    var leftDisplayText: String? { execution.binding.leftDisplayText }
    var rightDisplayText: String? { execution.binding.rightDisplayText }
    var diffRows: [DiffAlignedRow] { execution.binding.rows }
    var error: String? { execution.binding.error }
    var warning: String? { execution.binding.warning }

    var hasAnyContent: Bool {
        !left.isEmpty
            || !right.isEmpty
            || execution.binding != DiffExecutionBinding()
            || execution.isRunning
    }

    func clear() {
        execution.invalidate()
        mutateDrafts {
            left = ""
            right = ""
        }
    }

    private func draftDidChange() {
        guard !isMutatingDrafts else { return }
        scheduleCurrent()
    }

    private func optionDidChange() {
        guard !isMutatingDrafts else { return }
        scheduleCurrent()
    }

    private func mutateDrafts(_ mutation: () -> Void) {
        isMutatingDrafts = true
        mutation()
        isMutatingDrafts = false
    }

    private func scheduleCurrent() {
        let effectiveKind: DiffExecutionKind
        switch kind {
        case .text:
            effectiveKind = .text(options: TextDiffOptions(
                ignoreWhitespace: ignoreWhitespace,
                ignoreCase: ignoreCase
            ))
        case .json(let labels, _):
            effectiveKind = .json(
                labels: labels,
                options: JSONDiffOptions(
                    ignoreArrayOrder: ignoreArrayOrder,
                    foldUnchanged: false
                )
            )
        }
        let request = DiffExecutionRequest(kind: effectiveKind, left: left, right: right)
        execution.schedule(
            request: request,
            delay: debounce,
            operation: operation
        )
    }
}

struct IndexJSONDiffPage: View {
    private static let key = ToolWorkspaceKey<DiffToolWorkspaceModel>(toolID: "json-diff") { _ in
        DiffToolWorkspaceModel(
            kind: .json(labels: .init(left: "原始 JSON", right: "对比 JSON"))
        )
    }

    var body: some View {
        ToolWorkspaceHost(key: Self.key) { workspace, _ in
            IndexJSONDiffWorkspaceContent(
                workspace: workspace,
                execution: workspace.execution
            )
        }
    }
}

private struct IndexJSONDiffWorkspaceContent: View {
    @ObservedObject var workspace: DiffToolWorkspaceModel
    @ObservedObject var execution: DiffExecutionSession

    var body: some View {
        IndexPage(
            "JSON 对比",
            subtitle: "对比两段 JSON，以左右对齐视图显示差异。",
            workspaceSemantic: .editableDiffWorkspace
        ) {
            IndexEditableDiffWorkspace(
                inputTitle: "原始 JSON",
                outputTitle: "对比 JSON",
                leftPlaceholder: #"{"name":"Alice","age":30}"#,
                rightPlaceholder: #"{"name":"Bob","age":30,"city":"NY"}"#,
                leftDisplayText: execution.binding.leftDisplayText,
                rightDisplayText: execution.binding.rightDisplayText,
                left: $workspace.left,
                right: $workspace.right,
                rows: execution.binding.rows,
                resultState: execution.resultState,
                syntax: .json,
                foldUnchanged: workspace.foldUnchanged,
                error: execution.binding.error,
                warning: execution.binding.warning,
                onClear: workspace.clear,
                clearDisabled: !workspace.hasAnyContent,
                leadingControl: {
                    HStack(spacing: 8) {
                        IndexOptionSwitch(title: "忽略数组顺序", style: .embeddedSwitch, isOn: $workspace.ignoreArrayOrder)
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
