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

    var copyText: String {
        output ?? ""
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
                IndexHeroStat(value: workspace.output ?? "尚未生成", tone: workspace.output == nil ? .primary : .accent, copyable: workspace.output != nil, design: .rounded)
            } accessory: {
                Button { workspace.generate() } label: {
                    Label("重新生成", systemImage: IndexActionSymbol.refresh)
                        .font(ToolTypography.buttonSmall)
                }
                .buttonStyle(IndexSmallButtonStyle())
                .help("重新生成端口")
            }
        }
    }
}
