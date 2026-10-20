import SwiftUI
import XToolsDesign

struct IndexTextStatsPage: View {
    var body: some View {
        ToolWorkspaceHost(key: TextStatisticsWorkspaceModel.key) { workspace, _ in
            IndexTextStatsWorkspaceContent(workspace: workspace)
        }
    }
}

private struct IndexTextStatsWorkspaceContent: View {
    @ObservedObject var workspace: TextStatisticsWorkspaceModel

    private var stats: [(String, String)] {
        let summary = workspace.stats
        return [
            ("字符", summary.characters),
            ("不含空格", summary.nonWhitespaceCharacters),
            ("单词", summary.words),
            ("行数", summary.lines),
            ("句子", summary.sentences),
            ("字节", summary.bytes)
        ]
            .map { ($0.0, NumberFormatter.localizedString(from: NSNumber(value: $0.1), number: .decimal)) }
    }

    var body: some View {
        IndexPage("文本统计", subtitle: "统计字符、单词、行数、字节等。", workspaceSemantic: .fixedInputWorkspace) {
            IndexInputResultWorkbench(
                inputTitle: "输入",
                resultTitle: "统计",
                inputGrows: true
            ) {
                HStack(spacing: ToolMetrics.Spacing.sm) {
                    Spacer(minLength: ToolMetrics.Spacing.sm)
                    IndexClearButton(isDisabled: workspace.text.isEmpty) { workspace.text = "" }
                }
            } resultControls: {
                TextStatisticsAnalysisStatus(isAnalyzing: workspace.isAnalyzing)
            } input: {
                IndexWorkspaceTextArea(
                    placeholder: "粘贴文本，实时统计…",
                    text: $workspace.text,
                    minHeight: 160,
                    fillsHeight: true,
                    autoFocus: true,
                    embedsFlat: true,
                    workspaceSemantic: .fixedInputWorkspace
                )
            } result: {
                IndexResultSurface(
                    content: .stats(stats.map { IndexResultStatItem(label: $0.0, value: $0.1) })
                )
            }
        }
    }
}

private struct TextStatisticsAnalysisStatus: View {
    let isAnalyzing: Bool

    var body: some View {
        ZStack(alignment: .trailing) {
            if isAnalyzing {
                IndexProgressLabel(message: "统计中")
            }
        }
        .frame(width: 64, height: 18, alignment: .trailing)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("正在统计")
        .accessibilityHidden(!isAnalyzing)
    }
}
