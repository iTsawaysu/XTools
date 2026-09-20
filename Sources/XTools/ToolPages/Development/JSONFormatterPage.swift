import XToolsCore
import SwiftUI

@MainActor
final class JSONFormatterToolWorkspaceModel: ObservableObject {
    static let key = ToolWorkspaceKey<JSONFormatterToolWorkspaceModel>(toolID: "json-formatter") { preferences in
        JSONFormatterToolWorkspaceModel(preferences: preferences)
    }

    enum FormatMode: String, CaseIterable, Sendable {
        case two = "2"
        case four = "4"
        case compact = "compact"

        var id: String { rawValue }
        var label: String {
            switch self {
            case .two: return "2"
            case .four: return "4"
            case .compact: return "压缩"
            }
        }
    }

    enum IndentOption: Int, CaseIterable, Sendable {
        case two = 2
        case four = 4

        var id: String { String(rawValue) }
        var label: String { "\(rawValue) 空格" }
    }

    var indentOption: IndentOption {
        get {
            switch formatMode {
            case .two: return .two
            case .four, .compact: return .four
            }
        }
        set {
            formatMode = newValue == .two ? .two : .four
        }
    }

    @Published var input = "" {
        didSet {
            guard input != oldValue else { return }
            execution.sourceDidChange()
        }
    }
    @Published var escape: Bool = false {
        didSet {
            guard escape != oldValue else { return }
            execution.sourceDidChange()
            if escape && unescape { unescape = false }
            preferences.set(escape, for: TextDevelopmentToolPreferenceKeys.jsonEscape)
        }
    }
    @Published var unescape: Bool = false {
        didSet {
            guard unescape != oldValue else { return }
            execution.sourceDidChange()
            if unescape && escape { escape = false }
            preferences.set(unescape, for: TextDevelopmentToolPreferenceKeys.jsonUnescape)
        }
    }
    @Published var formatMode: FormatMode {
        didSet {
            guard formatMode != oldValue else { return }
            execution.sourceDidChange()
            preferences.set(formatMode.id, for: TextDevelopmentToolPreferenceKeys.jsonIndent)
        }
    }
    @Published var sortKeys: Bool = false {
        didSet {
            guard sortKeys != oldValue else { return }
            execution.sourceDidChange()
        }
    }

    let execution = IndexFormatExecutionSession()
    private let preferences: ToolPreferenceStore

    var output: String { execution.binding.output }
    var error: String? { execution.binding.error }
    var warning: String? { execution.binding.warning }

    init(preferences: ToolPreferenceStore) {
        self.preferences = preferences
        let saved = preferences.value(for: TextDevelopmentToolPreferenceKeys.jsonIndent)
        formatMode = FormatMode(rawValue: saved) ?? .four
        unescape = preferences.value(for: TextDevelopmentToolPreferenceKeys.jsonUnescape)
        escape = preferences.value(for: TextDevelopmentToolPreferenceKeys.jsonEscape)
    }

    func clear() {
        execution.invalidate()
        input = ""
    }
}

struct IndexJSONFormatterPage: View {
    var body: some View {
        ToolWorkspaceHost(key: JSONFormatterToolWorkspaceModel.key) { workspace, _ in
            IndexJSONFormatterWorkspaceContent(
                workspace: workspace,
                execution: workspace.execution
            )
        }
    }
}

/// Prototype v3 (Clay 收敛) body: one framed workbench whose toolbar carries
/// STDIN/STDOUT identities, the 2/4-space indent control, the inline
/// diagnostic, and 清空 · 复制 · 格式化(⌘↩). Formatting is explicit — button or
/// Command-Return; indent applies at the next format. A failed format tints
/// the panel outline, rings it, and shakes once per attempt.
private struct IndexJSONFormatterWorkspaceContent: View {
    private struct Snapshot: Sendable {
        let input: String
        let mode: JSONFormatterToolWorkspaceModel.FormatMode
        let sortKeys: Bool
        let unescape: Bool
        let escape: Bool
    }

    @ObservedObject var workspace: JSONFormatterToolWorkspaceModel
    @ObservedObject var execution: IndexFormatExecutionSession
    @State private var formatAttempt = 0

    var body: some View {
        IndexPage("JSON 格式化", subtitle: "格式化、压缩和验证 JSON，支持自定义选项。", workspaceSemantic: .structuredEditorTransform) {
            IndexFormatWorkbench(
                inputTitle: "输入",
                outputTitle: "输出",
                input: $workspace.input,
                output: execution.binding.output,
                inputPlaceholder: #"{"name":"XTools","tags":["dev","macos"]}"#,
                diagnostic: execution.binding.error ?? execution.binding.warning,
                diagnosticTone: execution.binding.error == nil ? .warning : .error,
                diagnosticDetail: execution.diagnostic,
                formatAttempt: formatAttempt,
                outputLineNumbers: true,
                outputSyntax: .json,
                isRunning: execution.isRunning,
                isOutputFresh: execution.isOutputFresh,
                clearDisabled: workspace.input.isEmpty && execution.binding.output.isEmpty && execution.binding.error == nil && execution.binding.warning == nil,
                onFormat: format,
                onClear: workspace.clear,
                leadingControl: {
                    HStack(spacing: 6) {
                        IndexSegmentedControl(
                            items: JSONFormatterToolWorkspaceModel.FormatMode.allCases.map { ($0.id, $0.label) },
                            selection: formatModeSelection,
                            density: .compact
                        )
                        IndexOptionSwitch(title: "Key 排序", style: .embeddedSwitch, isOn: $workspace.sortKeys)
                        IndexIconButton(
                            systemImage: "text.quote",
                            help: "去除转义",
                            isActive: workspace.unescape
                        ) {
                            workspace.unescape.toggle()
                        }
                        IndexIconButton(
                            systemImage: "quote.opening",
                            help: "转义为字符串",
                            isActive: workspace.escape
                        ) {
                            workspace.escape.toggle()
                        }
                    }
                }
            )
        }
        .onChange(of: workspace.sortKeys) { _ in
            if !execution.binding.output.isEmpty {
                format()
            }
        }
        .onChange(of: workspace.unescape) { _ in
            if !execution.binding.output.isEmpty {
                format()
            }
        }
        .onChange(of: workspace.escape) { _ in
            if !execution.binding.output.isEmpty {
                format()
            }
        }
    }

    private var formatModeSelection: Binding<String> {
        Binding(
            get: { workspace.formatMode.id },
            set: { value in
                guard let newMode = JSONFormatterToolWorkspaceModel.FormatMode(rawValue: value) else { return }
                workspace.formatMode = newMode
                if !execution.binding.output.isEmpty {
                    format()
                }
            }
        )
    }

    private func format() {
        guard !workspace.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            execution.invalidate()
            return
        }

        formatAttempt += 1
        let snapshot = Snapshot(
            input: workspace.input,
            mode: workspace.formatMode,
            sortKeys: workspace.sortKeys,
            unescape: workspace.unescape,
            escape: workspace.escape
        )
        execution.schedule(snapshot: snapshot, delay: .zero) { snapshot in
            var textToFormat = snapshot.input
            if snapshot.unescape {
                textToFormat = JSONFormatting.unescapeJSON(textToFormat)
            }
            return FormatRunner.run(textToFormat) { value -> JSONFormatting.FormattingResult in
                let formattedResult: JSONFormatting.FormattingResult
                switch snapshot.mode {
                case .two:
                    formattedResult = try JSONFormatting.formatResult(
                        value,
                        sortKeys: snapshot.sortKeys,
                        indentWidth: 2
                    )
                case .four:
                    formattedResult = try JSONFormatting.formatResult(
                        value,
                        sortKeys: snapshot.sortKeys,
                        indentWidth: 4
                    )
                case .compact:
                    formattedResult = try JSONFormatting.minifyResult(
                        value,
                        sortKeys: snapshot.sortKeys
                    )
                }

                if snapshot.escape {
                    let escaped = JSONFormatting.escapeJSON(formattedResult.text)
                    return JSONFormatting.FormattingResult(
                        text: escaped,
                        warning: formattedResult.warning,
                        duplicateKeys: formattedResult.duplicateKeys
                    )
                }
                return formattedResult
            }
            .binding(text: { $0.text }, warning: { $0.warning })
        }
    }
}
