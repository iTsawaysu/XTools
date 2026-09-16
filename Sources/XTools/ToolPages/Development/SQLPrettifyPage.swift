import XToolsCore
import SwiftUI

@MainActor
final class SQLPrettifyToolWorkspaceModel: ObservableObject {
    static let key = ToolWorkspaceKey<SQLPrettifyToolWorkspaceModel>(toolID: "sql-prettify") { preferences in
        SQLPrettifyToolWorkspaceModel(preferences: preferences)
    }

    @Published var input = ""
    @Published var keywordCase: SQLFormatting.KeywordCase {
        didSet { preferences.set(keywordCase, for: TextDevelopmentToolPreferenceKeys.sqlKeywordCase) }
    }

    let execution = IndexFormatExecutionSession()
    private let preferences: ToolPreferenceStore

    var output: String { execution.binding.output }
    var error: String? { execution.binding.error }

    init(preferences: ToolPreferenceStore) {
        self.preferences = preferences
        keywordCase = preferences.value(for: TextDevelopmentToolPreferenceKeys.sqlKeywordCase)
    }

    func clear() {
        execution.invalidate()
        input = ""
    }
}

struct IndexSQLPrettifyPage: View {
    var body: some View {
        ToolWorkspaceHost(key: SQLPrettifyToolWorkspaceModel.key) { workspace, _ in
            IndexSQLPrettifyWorkspaceContent(
                workspace: workspace,
                execution: workspace.execution
            )
        }
    }
}

private struct IndexSQLPrettifyWorkspaceContent: View {
    private static let maxHighlightedOutputCharacters = 200_000

    @ObservedObject var workspace: SQLPrettifyToolWorkspaceModel
    @ObservedObject var execution: IndexFormatExecutionSession
    @State private var formatAttempt = 0

    var body: some View {
        IndexPage("SQL 格式化", subtitle: "格式化 SQL，支持关键字大小写和基础校验。缩进固定2空格，逗号固定行尾。", workspaceSemantic: .structuredEditorTransform) {
            IndexFormatWorkbench(
                inputTitle: "输入",
                outputTitle: "输出",
                input: $workspace.input,
                output: execution.binding.output,
                inputPlaceholder: "with active_users as (select id,name from users where deleted_at is null) select * from active_users order by name",
                diagnostic: execution.binding.error,
                formatAttempt: formatAttempt,
                // SQL output is line-oriented; keep the gutter aligned with syntax colors.
                outputLineNumbers: true,
                outputColorize: outputColorizer,
                clearDisabled: workspace.input.isEmpty && execution.binding.output.isEmpty && execution.binding.error == nil,
                onFormat: format,
                onClear: workspace.clear,
                leadingControl: {
                    IndexSegmentedControl(
                        items: [("upper", "大写"), ("lower", "小写")],
                        selection: keywordCaseSelection,
                        density: .compact
                    )
                    .help("关键字大小写 (UPPER / lower)")
                }
            )
        }
    }

    private var keywordCaseSelection: Binding<String> {
        Binding(
            get: { workspace.keywordCase.rawValue },
            set: { value in
                workspace.keywordCase = value == "lower" ? .lower : .upper
            }
        )
    }

    private var outputColorizer: ((String) -> AttributedString)? {
        if execution.binding.output.count > Self.maxHighlightedOutputCharacters {
            return nil
        }
        return { StructuredSyntaxHighlighter.sql(line: $0) }
    }

    private func format() {
        guard !workspace.input.isEmpty else {
            execution.invalidate()
            return
        }

        formatAttempt += 1
        let snapshot = (
            input: workspace.input,
            options: SQLFormatting.Options(keywordCase: workspace.keywordCase, indentWidth: 2, commaStyle: .trailing)
        )
        execution.schedule(snapshot: snapshot, delay: .zero) { snapshot in
            FormatRunner.run(snapshot.input) {
                try SQLFormatting.format($0, options: snapshot.options)
            }
            .binding(text: { $0 })
        }
    }
}
