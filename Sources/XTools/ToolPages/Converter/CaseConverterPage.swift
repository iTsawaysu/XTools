import XToolsCore
import SwiftUI

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
            guard text != oldValue else { return }
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

private struct IndexCaseConverterWorkspaceContent: View {
    @ObservedObject var workspace: CaseConverterToolWorkspaceModel

    private var rows: [(String, String, Color?)] {
        workspace.styles.map { ($0.label, $0.value, nil) }
    }

    var body: some View {
        // 输入即时反应：派生结果由 workspace 持有，输入变化时重算（大输入
        // 后台 + 防抖），不再随每帧 body 重算。
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
