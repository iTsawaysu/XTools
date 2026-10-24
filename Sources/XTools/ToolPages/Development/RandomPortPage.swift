import XToolsCore
import SwiftUI
import XToolsDesign

@MainActor
final class RandomPortToolWorkspaceModel: ObservableObject {
    typealias Generator = () -> Int

    static let key = ToolWorkspaceKey<RandomPortToolWorkspaceModel>(toolID: "random-port-generator") { _ in
        RandomPortToolWorkspaceModel()
    }

    @Published private(set) var output: String?
    @Published private(set) var hasAttemptedGeneration = false

    private let generatePort: Generator

    init(_ generatePort: @escaping Generator = { Int.random(in: 1024...65535) }) {
        self.generatePort = generatePort
    }

    func generate() {
        hasAttemptedGeneration = true
        output = String(generatePort())
    }
}

struct IndexPortPage: View {
    var body: some View {
        ToolWorkspaceHost(key: RandomPortToolWorkspaceModel.key) { workspace, _ in
            IndexPortWorkspaceContent(workspace: workspace)
                .onAppear {
                    if !workspace.hasAttemptedGeneration { workspace.generate() }
                }
        }
    }
}

private struct IndexPortWorkspaceContent: View {
    @ObservedObject var workspace: RandomPortToolWorkspaceModel

    var body: some View {
        // 统一壳装配（page-rollout D3）：.result 形态，hero 呈现逐字保留。
        // 「重新生成」是页面级刷新动作（非 ActionBar 六种声明、旧页无 ⌘↩
        // 主操作），归标题行 titleAccessory（旧 44pt 纸头 controls 槽原位等价，
        // Crontab「刷新→pane 附件」同族先例）；不新增快捷键（等价优先）。
        IndexPage(
            "随机端口",
            subtitle: "生成 1024-65535 范围内的随机端口号。",
            workspaceSemantic: .naturalHeightShortResultPanel
        ) {
            WorkbenchSurface(
                title: "结果",
                shape: .result,
                titleAccessory: { regenerateButton }
            ) {
                IndexResultSurface(
                    content: .hero(
                        IndexResultHeroItem(
                            value: workspace.output ?? "",
                            tone: workspace.output == nil ? .primary : .accent,
                            copyable: workspace.output != nil,
                            design: .rounded
                        )
                    ),
                    emptyText: "点击重新生成"
                )
            }
        }
    }

    private var regenerateButton: some View {
        Button { workspace.generate() } label: {
            Label("重新生成", systemImage: IndexActionSymbol.refresh)
                .font(ToolTypography.buttonSmall)
        }
        .buttonStyle(IndexButtonStyle(compact: true))
    }
}
