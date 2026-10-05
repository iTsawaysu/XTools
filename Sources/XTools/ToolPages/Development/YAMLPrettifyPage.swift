import XToolsCore
import SwiftUI

@MainActor
final class YAMLPrettifyToolWorkspaceModel: ObservableObject {
    static let key = ToolWorkspaceKey<YAMLPrettifyToolWorkspaceModel>(toolID: "yaml-prettify") { preferences in
        YAMLPrettifyToolWorkspaceModel(preferences: preferences)
    }

    @Published var input = "" {
        didSet {
            guard !JSONExactTextIdentity.isExactlyEqual(input, oldValue) else { return }
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

/// 「格式化」Hub 的 YAML 分段。workspace key 沿用 toolID "yaml-prettify"，
/// 输入与执行状态由 ToolWorkspaceRepository 保活，分段切换不丢。
struct IndexYAMLPrettifySegment: View {
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

    var body: some View {
        IndexFormatWorkbench(
            inputTitle: "输入",
            outputTitle: "输出",
            input: $workspace.input,
            output: execution.binding.output,
            inputPlaceholder: "key:   value\nlist:\n   - a\n   - b",
            diagnostic: execution.binding.error ?? execution.binding.warning,
            diagnosticTone: execution.binding.error == nil ? .warning : .error,
            diagnosticDetail: execution.diagnostic,
            diagnosticMarker: execution.diagnosticMarker,
            outputLineNumbers: true,
            outputSyntax: .yaml,
            isRunning: execution.isRunning,
            isOutputFresh: execution.isOutputFresh,
            clearDisabled: workspace.input.isEmpty && !execution.hasClearableContent,
            onFormat: format,
            onClear: workspace.clear,
            leadingControl: {
                IndexOptionSwitch(title: "Key 排序", style: .button, isOn: $workspace.sortKeys)
            }
        )
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

        let options = YAMLPrettifier.Options(
            indent: 2,
            sortKeys: workspace.sortKeys
        )
        let snapshot = (input: workspace.input, options: options)
        execution.schedule(snapshot: snapshot, sourceText: snapshot.input, delay: .zero, cooperativeCancellation: true) { snapshot in
            FormatRunner.run(snapshot.input) {
                try YAMLPrettifier.formatValidated($0, options: snapshot.options)
            }
            .binding(text: { $0 })
        }
    }
}
