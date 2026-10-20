import XToolsCore
import SwiftUI

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
        IndexPage(
            "随机端口",
            subtitle: "生成 1024-65535 范围内的随机端口号。",
            workspaceSemantic: .naturalHeightShortResultPanel
        ) {
            IndexPanel("结果") {
                if let output = workspace.output {
                    IndexHeroStat(value: output, design: .rounded)
                } else {
                    IndexEmptyState(
                        title: "等待生成",
                        systemImage: "number",
                        message: "点击重新生成获取随机端口。",
                        density: .list
                    )
                    .frame(minHeight: 96)
                }
            } accessory: {
                Button { workspace.generate() } label: {
                    Label("重新生成", systemImage: IndexActionSymbol.refresh)
                        .font(ToolTypography.buttonSmall)
                }
                .buttonStyle(IndexSmallButtonStyle())
            }
        }
    }
}
