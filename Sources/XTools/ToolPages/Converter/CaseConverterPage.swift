import XToolsCore
import SwiftUI
import XToolsDesign

typealias CaseConversionStyleRow = (label: String, value: String)

typealias CaseConversionStyleRenderer = @Sendable (
    _ input: String
) -> [CaseConversionStyleRow]

typealias CaseConversionBackgroundRenderer = @Sendable (
    _ input: String
) async -> [CaseConversionStyleRow]

/// 大小写转换工作台模型：套用同域 IndexConverterToolWorkspaceModel 的完整
/// 方案（4KB 同步阈值 + 后台执行 + 防抖 + 过期结果丢弃）。阈值/防抖直接
/// 引用转换族的校准常量，不另立档位——大小写转换的整串分词 + 8 路拼接
/// 与 StringObfuscator 的单遍线性扫描不同量级（1MB 输入实测 215–264ms
/// 主线程），适合保守的 4KB 边界。
@MainActor
final class CaseConverterToolWorkspaceModel: ObservableObject {
    static let synchronousInputByteLimit = IndexConverterToolWorkspaceModel.defaultSynchronousInputByteLimit
    static let backgroundDebounce = IndexConverterToolWorkspaceModel.defaultBackgroundDebounce

    static let key = ToolWorkspaceKey<CaseConverterToolWorkspaceModel>(toolID: "case-converter") { _ in
        CaseConverterToolWorkspaceModel()
    }

    @Published var text = "" {
        didSet {
            guard !ExactUTF8Identity.isExactlyEqual(text, oldValue) else { return }
            refresh()
        }
    }
    @Published private(set) var styles: [CaseConversionStyleRow] = []
    @Published private(set) var isProcessing = false

    private let synchronousInputByteLimit: Int
    private let backgroundDebounce: Duration
    private let renderer: CaseConversionStyleRenderer
    private let backgroundRenderer: CaseConversionBackgroundRenderer
    private let workGate = AsyncWorkGate()

    init(
        synchronousInputByteLimit: Int = CaseConverterToolWorkspaceModel.synchronousInputByteLimit,
        backgroundDebounce: Duration = CaseConverterToolWorkspaceModel.backgroundDebounce,
        renderer: @escaping CaseConversionStyleRenderer = CaseConversion.styles,
        backgroundRenderer: CaseConversionBackgroundRenderer? = nil
    ) {
        self.synchronousInputByteLimit = synchronousInputByteLimit
        self.backgroundDebounce = backgroundDebounce
        self.renderer = renderer
        let capturedRenderer = renderer
        self.backgroundRenderer = backgroundRenderer ?? { input in
            await Task.detached(priority: .userInitiated) {
                capturedRenderer(input)
            }.value
        }
    }

    private func refresh() {
        workGate.invalidate()

        guard !text.isEmpty else {
            styles = []
            isProcessing = false
            return
        }

        guard text.utf8.count > synchronousInputByteLimit else {
            // 小输入同步即时：交互与既有行为一致，避免每帧 body 重算即可。
            styles = renderer(text)
            isProcessing = false
            return
        }

        styles = []
        isProcessing = true
        scheduleBackgroundRender(for: text)
    }

    private func scheduleBackgroundRender(for input: String) {
        let debounce = backgroundDebounce
        let backgroundRenderer = backgroundRenderer
        let token = workGate.token

        workGate.schedule(debounce: debounce) { [weak self] in
            guard let self, self.workGate.isCurrent(token) else { return }

            let styles = await backgroundRenderer(input)

            guard self.workGate.isCurrent(token) else { return }
            self.styles = styles
            self.isProcessing = false
        }
    }
}

/// Deliberately not IndexConverterPage: all 8 case styles must stay visible at
/// once in a multi-row table, not one mode-switched output.
struct IndexCaseConverterPage: View {
    var body: some View {
        ToolWorkspaceHost(key: CaseConverterToolWorkspaceModel.key) { workspace, _ in
            IndexCaseConverterWorkspaceContent(workspace: workspace)
        }
    }
}

/// 统一壳装配（page-rollout A0）：输入/转换结果对等双栏。纯清空钮形态的
/// 标准配方——旧 inputControls 槽的清空钮归输入 pane 尾部 ActionBar，
/// resultControls 槽的复制钮归输出 pane 尾部 ActionBar（首个 copy 同步
/// 声明在壳级 actions 上注册 ⇧⌘C；.inputOutput 形态壳层不渲染 actions，
/// 只消费其页面级快捷键）。
private struct IndexCaseConverterWorkspaceContent: View {
    @ObservedObject var workspace: CaseConverterToolWorkspaceModel

    /// 全部复制只带结果值（标签是字段名，不进剪贴板），与 Hash 页的
    /// 「全部复制」按行拼接语义一致；输入为空时按钮经 IndexCopyButton
    /// 自身的空文本禁用语义自动置灰。
    private var allResultsText: String {
        workspace.styles.map(\.value).joined(separator: "\n")
    }

    private var copyAction: WorkbenchActionBarAction {
        .copy(text: allResultsText, title: "全部复制")
    }

    var body: some View {
        IndexPage("大小写转换", subtitle: "在 camelCase、snake_case、kebab-case 等之间转换。", workspaceSemantic: .queryListWorkspace) {
            WorkbenchSurface(title: nil, shape: .inputOutput, actions: [copyAction]) {
                WorkbenchIOPair(
                    leadingTitle: "输入",
                    trailingTitle: "转换结果",
                    leadingActions: [
                        .clear(enabled: !workspace.text.isEmpty, onPerform: { workspace.text = "" })
                    ],
                    trailingActions: [copyAction]
                ) {
                    inputPane
                } trailing: {
                    IndexResultSurface(
                        content: .kv(
                            workspace.styles.map { IndexResultKVItem(key: $0.label, value: $0.value) }
                        ),
                        emptyText: IndexEmptyStateCopy.autoShow("文本")
                    )
                }
            }
        }
    }

    /// 输入 pane 内容（原 IndexInputResultWorkbench input 槽投影）：
    /// 受控 AppKit 编辑器填满 pane（双栏 pane 几何）。
    private var inputPane: some View {
        IndexWorkspaceTextArea(
            placeholder: "输入文本，自动转换所有格式…",
            text: $workspace.text,
            minHeight: 76,
            fillsHeight: true,
            autoFocus: true,
            embedsFlat: true,
            workspaceSemantic: .queryListWorkspace
        )
        // 焦点契约（阶段③ C3）：页面首个输入 = 文本输入区。
        .workbenchFocusTarget()
    }
}
