import XToolsCore
import SwiftUI

@MainActor
final class YAMLPrettifyToolWorkspaceModel: ObservableObject {
    static let key = ToolWorkspaceKey<YAMLPrettifyToolWorkspaceModel>(toolID: "yaml-prettify") { preferences in
        YAMLPrettifyToolWorkspaceModel(preferences: preferences)
    }

    @Published var input = "" {
        didSet {
            guard input != oldValue else { return }
            execution.sourceDidChange()
        }
    }
    @Published var sortKeys: Bool = false {
        didSet {
            guard sortKeys != oldValue else { return }
            execution.sourceDidChange()
            preferences.set(sortKeys, for: TextDevelopmentToolPreferenceKeys.yamlSortKeys)
        }
    }

    let execution = IndexFormatExecutionSession()
    private let preferences: ToolPreferenceStore

    var output: String { execution.binding.output }
    var error: String? { execution.binding.error }
    var warning: String? { execution.binding.warning }

    init(preferences: ToolPreferenceStore) {
        self.preferences = preferences
        sortKeys = preferences.value(for: TextDevelopmentToolPreferenceKeys.yamlSortKeys)
    }

    func clear() {
        execution.invalidate()
        input = ""
    }
}

struct IndexYAMLPrettifyPage: View {
    var body: some View {
        ToolWorkspaceHost(key: YAMLPrettifyToolWorkspaceModel.key) { workspace, _ in
            IndexYAMLPrettifyWorkspaceContent(
                workspace: workspace,
                execution: workspace.execution
            )
        }
    }
}

private struct IndexYAMLPrettifyWorkspaceContent: View {
    @ObservedObject var workspace: YAMLPrettifyToolWorkspaceModel
    @ObservedObject var execution: IndexFormatExecutionSession
    @State private var formatAttempt = 0

    var body: some View {
        IndexPage("YAML 格式化", subtitle: "规整 YAML 空白与键值间距，支持 Key 排序。", workspaceSemantic: .structuredEditorTransform) {
            IndexFormatWorkbench(
                inputTitle: "输入",
                outputTitle: "输出",
                input: $workspace.input,
                output: execution.binding.output,
                inputPlaceholder: "key:   value\nlist:\n   - a\n   - b",
                diagnostic: execution.binding.error ?? execution.binding.warning,
                diagnosticTone: execution.binding.error == nil ? .warning : .error,
                diagnosticDetail: execution.diagnostic,
                formatAttempt: formatAttempt,
                outputLineNumbers: true,
                outputSyntax: .yaml,
                isRunning: execution.isRunning,
                isOutputFresh: execution.isOutputFresh,
                clearDisabled: workspace.input.isEmpty && execution.binding.output.isEmpty && execution.binding.error == nil && execution.binding.warning == nil,
                onFormat: format,
                onClear: workspace.clear,
                leadingControl: {
                    IndexOptionSwitch(title: "Key 排序", style: .button, isOn: $workspace.sortKeys)
                }
            )
        }
        .onChange(of: workspace.sortKeys) { _ in
            if !workspace.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                format()
            }
        }
    }

    private func format() {
        guard !workspace.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            execution.invalidate()
            return
        }

        formatAttempt += 1
        let options = YAMLPrettifier.Options(
            indent: 2,
            sortKeys: workspace.sortKeys
        )
        let snapshot = (input: workspace.input, options: options)
        execution.schedule(snapshot: snapshot, delay: .zero) { snapshot in
            FormatRunner.run(snapshot.input) {
                try YAMLPrettifier.formatValidated($0, options: snapshot.options)
            }
            .binding(text: { $0 })
        }
    }
}
