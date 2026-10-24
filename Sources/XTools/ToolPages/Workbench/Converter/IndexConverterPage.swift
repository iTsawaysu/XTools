import XToolsCore
import SwiftUI
import XToolsDesign

enum IndexConverterFailure: Error, Sendable {
    case invalidInput
}

typealias IndexConverterOperation = @Sendable (
    _ input: String,
    _ mode: String
) throws -> String

typealias IndexConverterEmptyInput = @Sendable (
    _ input: String,
    _ mode: String
) -> Bool

typealias IndexConverterErrorMessage = @Sendable (
    _ error: Error
) -> String

struct IndexConverterMode: Hashable, Identifiable {
    let id: String
    let label: String
}

struct IndexConverterRequest: Equatable, Hashable, Sendable {
    let input: String
    let mode: String

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.mode == rhs.mode && ExactUTF8Identity.isExactlyEqual(lhs.input, rhs.input)
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(mode)
        hasher.combine(ExactUTF8Identity(input))
    }

    var inputByteCount: Int {
        input.utf8.count
    }
}

enum IndexConverterExecutionResult: Equatable, Sendable {
    case success(String)
    case failure(String)
}

typealias IndexConverterBackgroundExecutor = @Sendable (
    _ request: IndexConverterRequest
) async -> IndexConverterExecutionResult

@MainActor
final class IndexConverterToolWorkspaceModel: ObservableObject {
    static let defaultSynchronousInputByteLimit = 4 * 1024
    static let defaultBackgroundDebounce: Duration = .milliseconds(120)

    @Published var mode: String {
        didSet {
            guard mode != oldValue, !isApplyingControlledMutation else { return }
            refresh()
        }
    }
    @Published var input = "" {
        didSet {
            guard !ExactUTF8Identity.isExactlyEqual(input, oldValue), !isApplyingControlledMutation else { return }
            inputReplacementToken = 0
            refresh()
        }
    }
    @Published private(set) var output = ""
    @Published private(set) var error: String?
    @Published private(set) var isProcessing = false
    @Published private(set) var inputReplacementToken = 0

    private let synchronousInputByteLimit: Int
    private let backgroundDebounce: Duration
    private let isEmptyInput: IndexConverterEmptyInput
    private let errorMessage: IndexConverterErrorMessage
    private let convert: IndexConverterOperation
    private let backgroundExecutor: IndexConverterBackgroundExecutor?

    private let workGate = AsyncWorkGate()
    private var completedRequest: IndexConverterRequest?
    private var isApplyingControlledMutation = false
    private var inputReplacementSequence = 0

    init(
        initialMode: String,
        synchronousInputByteLimit: Int = IndexConverterToolWorkspaceModel.defaultSynchronousInputByteLimit,
        backgroundDebounce: Duration = IndexConverterToolWorkspaceModel.defaultBackgroundDebounce,
        isEmptyInput: @escaping IndexConverterEmptyInput = { input, _ in input.isEmpty },
        errorMessage: @escaping IndexConverterErrorMessage = { _ in "转换失败。" },
        convert: @escaping IndexConverterOperation,
        backgroundExecutor: IndexConverterBackgroundExecutor? = nil
    ) {
        mode = initialMode
        self.synchronousInputByteLimit = synchronousInputByteLimit
        self.backgroundDebounce = backgroundDebounce
        self.isEmptyInput = isEmptyInput
        self.errorMessage = errorMessage
        self.convert = convert
        self.backgroundExecutor = backgroundExecutor
    }

    deinit {
        // AsyncWorkGate cancels its task when deallocated with the model.
    }

    func clear() {
        guard !input.isEmpty else {
            invalidateCurrentRequest()
            clearDerivedState()
            return
        }
        input = ""
    }

    func changeMode(
        to newMode: String,
        backfillModeTransition: @escaping (String, String) -> Bool
    ) {
        guard newMode != mode else { return }

        // 只有 backfill 语义会替换输入（output → input）；其余情形一律保留
        // 用户文本——出错后切方向是为了换方向重试，清空输入反而丢上下文。
        // 出错态 output 为空、completedRequest 为 nil，backfill 守卫自然拦下。
        let nextInput: String?
        if backfillModeTransition(mode, newMode),
           !isProcessing,
           !output.isEmpty,
           completedRequest == IndexConverterRequest(input: input, mode: mode) {
            nextInput = output
        } else {
            nextInput = nil
        }

        isApplyingControlledMutation = true
        mode = newMode
        if let nextInput {
            input = nextInput
            inputReplacementSequence &+= 1
            inputReplacementToken = inputReplacementSequence
        }
        isApplyingControlledMutation = false
        refresh()
    }

    private func refresh() {
        invalidateCurrentRequest()

        let request = IndexConverterRequest(input: input, mode: mode)
        guard !isEmptyInput(request.input, request.mode) else {
            clearDerivedState()
            return
        }

        guard request.inputByteCount > synchronousInputByteLimit else {
            publish(Self.execute(request, convert: convert, errorMessage: errorMessage), for: request)
            return
        }

        output = ""
        error = nil
        completedRequest = nil
        isProcessing = true
        scheduleBackgroundExecution(for: request)
    }

    private func scheduleBackgroundExecution(for request: IndexConverterRequest) {
        let debounce = backgroundDebounce
        let backgroundExecutor = backgroundExecutor
        let convert = convert
        let errorMessage = errorMessage
        let token = workGate.token

        workGate.schedule(debounce: debounce) { [weak self] in
            guard let self, self.workGate.isCurrent(token) else { return }

            let result: IndexConverterExecutionResult
            if let backgroundExecutor {
                result = await backgroundExecutor(request)
            } else {
                result = await Task.detached(priority: .userInitiated) {
                    Self.execute(request, convert: convert, errorMessage: errorMessage)
                }.value
            }

            guard self.workGate.isCurrent(token) else { return }
            self.publish(result, for: request)
        }
    }

    private func invalidateCurrentRequest() {
        workGate.invalidate()
    }

    private func clearDerivedState() {
        output = ""
        error = nil
        completedRequest = nil
        isProcessing = false
    }

    private func publish(
        _ result: IndexConverterExecutionResult,
        for request: IndexConverterRequest
    ) {
        switch result {
        case .success(let output):
            self.output = output
            error = nil
            completedRequest = request
        case .failure(let message):
            output = ""
            error = message
            completedRequest = nil
        }
        isProcessing = false
    }

    nonisolated private static func execute(
        _ request: IndexConverterRequest,
        convert: @escaping IndexConverterOperation,
        errorMessage: @escaping IndexConverterErrorMessage
    ) -> IndexConverterExecutionResult {
        do {
            return .success(try convert(request.input, request.mode))
        } catch {
            return .failure(errorMessage(error))
        }
    }
}

struct IndexConverterPage: View {
    let modes: [IndexConverterMode]
    let placeholder: String
    let outputPresentation: IndexTextConversionOutputPresentation
    let backfillModeTransition: (String, String) -> Bool

    private let workspaceKey: ToolWorkspaceKey<IndexConverterToolWorkspaceModel>

    static func resolvedInitialMode(
        requested initialMode: String?,
        modes: [IndexConverterMode]
    ) -> String {
        let fallback = modes.first?.id ?? ""
        guard let initialMode,
              modes.contains(where: { $0.id == initialMode }) else {
            return fallback
        }
        return initialMode
    }

    /// page-rollout B1 简化：旧 `embedsPageShell` 双装配路径退役。全部调用
    /// 方（文本编码 Hub 的四个分段）都以 `false` 使用本页——页面壳由所属
    /// Hub 的 `HubSegmentPage` 提供，本页只装配 `WorkbenchSurface` 工作台
    /// 主体；`title`/`subtitle` 只服务过壳内嵌 IndexPage 分支，随之移除
    /// （Hub 分段副标题由 `EncodingHubWorkspaceModel.Segment.subtitle` 声明）。
    init(
        toolID: ToolID,
        slot: String = "main",
        modes: [IndexConverterMode],
        initialMode: String? = nil,
        placeholder: String,
        outputPresentation: IndexTextConversionOutputPresentation = .standard,
        backfillsOutputOnModeChange: Bool = false,
        backfillModeTransition: ((String, String) -> Bool)? = nil,
        isEmptyInput: @escaping @Sendable (String) -> Bool = { $0.isEmpty },
        isEmptyInputForMode: IndexConverterEmptyInput? = nil,
        errorMessage: @escaping IndexConverterErrorMessage = { _ in "转换失败。" },
        convert: @escaping IndexConverterOperation
    ) {
        self.modes = modes
        self.placeholder = placeholder
        self.outputPresentation = outputPresentation
        self.backfillModeTransition = backfillModeTransition ?? { _, _ in backfillsOutputOnModeChange }

        let resolvedEmptyInput: IndexConverterEmptyInput = isEmptyInputForMode ?? { input, _ in isEmptyInput(input) }
        let resolvedInitialMode = Self.resolvedInitialMode(requested: initialMode, modes: modes)
        workspaceKey = ToolWorkspaceKey(toolID: toolID, slot: slot) { _ in
            IndexConverterToolWorkspaceModel(
                initialMode: resolvedInitialMode,
                isEmptyInput: resolvedEmptyInput,
                errorMessage: errorMessage,
                convert: convert
            )
        }
    }

    var body: some View {
        ToolWorkspaceHost(key: workspaceKey) { workspace, _ in
            IndexConverterWorkspaceContent(
                modes: modes,
                placeholder: placeholder,
                outputPresentation: outputPresentation,
                backfillModeTransition: backfillModeTransition,
                workspace: workspace
            )
        }
    }
}

private struct IndexConverterWorkspaceContent: View {
    let modes: [IndexConverterMode]
    let placeholder: String
    let outputPresentation: IndexTextConversionOutputPresentation
    let backfillModeTransition: (String, String) -> Bool

    @ObservedObject var workspace: IndexConverterToolWorkspaceModel
    /// 输入 pane 的文本文件拖入会话（旧壳能力等价随行：接收写入 + 拒判
    /// 经诊断单轨 + 悬停 wash，见 `WorkbenchInputDropSupport`）。
    @StateObject private var droppedFile = IndexDroppedTextFile()

    private var modeSelection: Binding<String> {
        Binding(
            get: { workspace.mode },
            set: { workspace.changeMode(to: $0, backfillModeTransition: backfillModeTransition) }
        )
    }

    /// 旧 clearDisabled 等价迁移：输入、输出与错误诊断全部为空时清空不可用。
    private var clearDisabled: Bool {
        workspace.input.isEmpty && workspace.output.isEmpty && workspace.error == nil
    }

    var body: some View {
        // 统一壳装配（page-rollout B1）：模式分段（编码/解码等方向切换，
        // 即时参数）归标题行 accessory（Batch A 页面级模式分段配方）；清空
        // 归输入 pane 尾 ActionBar，复制归输出 pane 尾 ActionBar（⇧⌘C 由
        // IOPair 根部的页面级代理持有，页面只在 IOPair 声明一次）；转换
        // 错误走 preference 单轨（旧 IndexFormatWorkbench 参数轨终结）。
        WorkbenchSurface(
            title: nil,
            shape: .inputOutput,
            titleAccessory: { modeSegment },
            content: {
                WorkbenchIOPair(
                    leadingTitle: "输入",
                    trailingTitle: "输出",
                    leadingActions: [
                        .clear(enabled: !clearDisabled, onPerform: workspace.clear)
                    ],
                    trailingActions: [
                        .copy(text: workspace.output, help: "复制全部 (⇧⌘C)")
                    ],
                    leadingAccessory: { stdinCluster },
                    leading: { inputPane },
                    trailingAccessory: { stdoutBadge },
                    trailing: { outputPane }
                )
                // 诊断单轨：拖入拒判优先（旧壳状态槽同序），其后是转换错误；
                // 经 preference 聚合到纸顶单槽（同一文本、同一错误描边；新增
                // 「变化才播报」toast，与全部其他页对齐）。
                .indexWorkspaceDiagnostic(
                    droppedFile.rejection?.message ?? workspace.error,
                    tone: .error
                )
            }
        )
    }

    /// 模式分段：Mode chrome motion 由 IndexSegmentedControl（Preset.tabs）
    /// 自持；模式切换不动画固定双栏布局（quality hot-path ban），pane 内容
    /// 即时更新——沿用旧页注释语义。
    private var modeSegment: some View {
        IndexSegmentedControl(
            items: modes.map { ($0.id, $0.label) },
            selection: modeSelection,
            density: .compact
        )
    }

    /// 输入 pane 头附件：STDIN 徽章 + 实时字符计数（旧工具栏 STDIN 簇的
    /// 计数，pane 头附件承载）。
    private var stdinCluster: some View {
        HStack(spacing: ToolMetrics.Spacing.fine) {
            IndexBadge("STDIN", tone: .neutral, isCapsule: true)
            IndexInputCountLabel(
                text: IndexInputCountPresentation.characters.label(for: workspace.input)
            )
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var stdoutBadge: some View {
        IndexBadge("STDOUT", tone: .neutral, isCapsule: true)
            .fixedSize(horizontal: true, vertical: false)
    }

    /// 输入 pane 内容：受控 AppKit 编辑器填满 pane；模式回填（backfill）
    /// 的一次性光标落位 token 原样保留；文本文件拖入接收后经 didSet 照常
    /// 重算，拒判提示并入纸顶诊断单轨。
    private var inputPane: some View {
        IndexWorkspaceTextArea(
            placeholder: placeholder,
            text: $workspace.input,
            fillsHeight: true,
            autoFocus: true,
            caretPlacementRequestToken: workspace.inputReplacementToken == 0 ? nil : workspace.inputReplacementToken,
            embedsFlat: true,
            lineNumbers: false,
            onFileDrop: { content in
                workspace.input = content
            },
            droppedFile: droppedFile,
            workspaceSemantic: .copyTransformWorkspace
        )
        .workbenchInputDropSupport(text: $workspace.input, droppedFile: droppedFile)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // 焦点契约（阶段③ C3）：页面首个输入 = 输入编辑器。
        .workbenchFocusTarget()
    }

    @ViewBuilder
    private var outputPane: some View {
        if workspace.isProcessing {
            IndexTextConversionProcessingSurface(text: "正在转换…")
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        } else {
            switch outputPresentation {
            case .standard:
                IndexOutputSurface(
                    text: workspace.output,
                    lineNumbers: false,
                    fillsHeight: true,
                    embedsFlat: true
                )
            case .nativeReadOnlyText:
                IndexOutputSurface(
                    text: workspace.output,
                    presentation: .plain,
                    lineNumbers: false,
                    fillsHeight: true
                )
            case .markdownPreview:
                IndexMarkdownPreviewSurface(
                    text: workspace.output,
                    fillsHeight: true,
                    accessibilityTitle: "输出"
                )
            }
        }
    }
}
