import XToolsCore
import SwiftUI

/// Deliberately not IndexConverterPage: all 8 case styles must stay visible at
/// once in a multi-row table, not one mode-switched output.
struct IndexCaseConverterPage: View {
    private static let key = ToolWorkspaceKey<IndexTextDraftWorkspaceModel>(toolID: "case-converter") { _ in
        IndexTextDraftWorkspaceModel()
    }

    var body: some View {
        ToolWorkspaceHost(key: Self.key) { workspace, _ in
            IndexCaseConverterWorkspaceContent(workspace: workspace)
        }
    }
}

private struct IndexCaseConverterWorkspaceContent: View {
    @ObservedObject var workspace: IndexTextDraftWorkspaceModel

    private var rows: [(String, String, Color?)] {
        CaseConversion.styles(workspace.text).map { ($0.label, $0.value, nil) }
    }

    var body: some View {
        // 输入即时反应：rows 是计算属性，无需主动作按钮。
        // 「清空」收进输入面板标题栏，不单独占行（SPEC §P5b）。
        IndexPage("大小写转换", subtitle: "在 camelCase、snake_case、kebab-case 等之间转换。", workspaceSemantic: .longTextNaturalInput) {
            IndexPanel("输入") {
                IndexWorkspaceTextArea(
                    placeholder: "输入文本，自动转换所有格式…",
                    text: $workspace.text,
                    minHeight: 76,
                    autoFocus: true,
                    workspaceSemantic: .longTextNaturalInput
                )
            } accessory: {
                IndexClearButton(isDisabled: workspace.text.isEmpty) {
                    workspace.text = ""
                }
            }
            // 短派生结果自然展开，由页面外层滚动承载长值换行后的高度。
            IndexPanel("转换结果") {
                IndexShortResultKV(rows: rows, emptyText: IndexEmptyStateCopy.autoShow("文本"), valueMotion: .immediate)
            }
        }
    }
}
