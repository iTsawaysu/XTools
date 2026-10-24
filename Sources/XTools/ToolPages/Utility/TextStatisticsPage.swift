import SwiftUI
import XToolsDesign

struct IndexTextStatsPage: View {
    var body: some View {
        ToolWorkspaceHost(key: TextStatisticsWorkspaceModel.key) { workspace, _ in
            IndexTextStatsWorkspaceContent(workspace: workspace)
        }
    }
}

/// 统一壳装配（page-rollout A2，inputGrows 语义迁移）：旧壳 inputGrows
/// 「输入主导高度、结果自然高度」在新壳表达为——输入编辑器填满 pane
/// （fillsHeight，对等双栏的 pane 主导侧），统计网格在输出 pane 内自然
/// 高度呈现；清空归输入 pane 尾部 ActionBar，统计中进度归输出 pane 头
/// 附件。语义 fixedInputWorkspace 本就是 fill 布局，保持不变。
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
            WorkbenchSurface(title: nil, shape: .inputOutput) {
                WorkbenchIOPair(
                    leadingTitle: "输入",
                    trailingTitle: "统计",
                    leadingActions: [
                        .clear(enabled: !workspace.text.isEmpty, onPerform: { workspace.text = "" })
                    ],
                    leadingAccessory: { EmptyView() },
                    leading: {
                        IndexWorkspaceTextArea(
                            placeholder: "粘贴文本，实时统计…",
                            text: $workspace.text,
                            minHeight: 160,
                            fillsHeight: true,
                            autoFocus: true,
                            embedsFlat: true,
                            workspaceSemantic: .fixedInputWorkspace
                        )
                        .workbenchFocusTarget()
                    },
                    trailingAccessory: { TextStatisticsAnalysisStatus(isAnalyzing: workspace.isAnalyzing) },
                    trailing: {
                        IndexResultSurface(
                            content: .stats(stats.map { IndexResultStatItem(label: $0.0, value: $0.1) })
                        )
                    }
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
        .frame(width: ToolMetrics.Control.thumbnail, height: ToolMetrics.Control.badge, alignment: .trailing)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("正在统计")
        .accessibilityHidden(!isAnalyzing)
    }
}
