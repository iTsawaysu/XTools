import XToolsCore
import SwiftUI

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
            guard input != oldValue, !isApplyingControlledMutation else { return }
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
    let title: String
    let subtitle: String
    let modes: [IndexConverterMode]
    let placeholder: String
    let outputPresentation: IndexTextConversionOutputPresentation
    let backfillModeTransition: (String, String) -> Bool
    let embedsPageShell: Bool

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

    init(
        toolID: ToolID,
        slot: String = "main",
        embedsPageShell: Bool = true,
        title: String,
        subtitle: String,
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
        self.title = title
        self.subtitle = subtitle
        self.modes = modes
        self.placeholder = placeholder
        self.outputPresentation = outputPresentation
        self.backfillModeTransition = backfillModeTransition ?? { _, _ in backfillsOutputOnModeChange }
        self.embedsPageShell = embedsPageShell

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
                title: title,
                subtitle: subtitle,
                modes: modes,
                placeholder: placeholder,
                outputPresentation: outputPresentation,
                backfillModeTransition: backfillModeTransition,
                embedsPageShell: embedsPageShell,
                workspace: workspace
            )
        }
    }
}

private struct IndexConverterWorkspaceContent: View {
    let title: String
    let subtitle: String
    let modes: [IndexConverterMode]
    let placeholder: String
    let outputPresentation: IndexTextConversionOutputPresentation
    let backfillModeTransition: (String, String) -> Bool
    /// 是否内嵌 IndexPage 页面壳：true（默认）时本视图独立成页；false 时
    /// 页面壳由所属 Hub 提供，本视图只贡献工作台主体（四个转换分段复用）。
    let embedsPageShell: Bool

    @ObservedObject var workspace: IndexConverterToolWorkspaceModel
    private var modeSelection: Binding<String> {
        Binding(
            get: { workspace.mode },
            set: { workspace.changeMode(to: $0, backfillModeTransition: backfillModeTransition) }
        )
    }

    var body: some View {
        if embedsPageShell {
            IndexPage(title, subtitle: subtitle, workspaceSemantic: .copyTransformWorkspace) {
                workbenchBody
            }
        } else {
            workbenchBody
        }
    }

    /// 壳内作为 IndexPage 的内容闭包，嵌入态直接挂到 Hub 的内容闭包——
    /// 两者同为 VStack 上下文。工作台与「格式化」/「对比」同构：单一面板
    /// + 统一工具栏，模式切换落在 STDIN 槽位（同 JSON 缩进控制），转换
    /// 错误走工具栏下的诊断状态行。
    private var workbenchBody: some View {
        IndexFormatWorkbench(
            inputTitle: "输入",
            outputTitle: "输出",
            input: $workspace.input,
            output: workspace.output,
            inputPlaceholder: placeholder,
            diagnostic: workspace.error,
            diagnosticTone: .error,
            outputLineNumbers: false,
            inputLineNumbers: false,
            inputCaretPlacementRequestToken: workspace.inputReplacementToken == 0 ? nil : workspace.inputReplacementToken,
            inputCountPresentation: .characters,
            autoFocus: true,
            clearDisabled: workspace.input.isEmpty && workspace.output.isEmpty && workspace.error == nil,
            onClear: workspace.clear,
            outputPresentation: outputPresentation,
            outputProcessingText: workspace.isProcessing ? "正在转换…" : nil,
            leadingControl: {
                // Mode chrome motion is owned by IndexSegmentedControl (Preset.tabs).
                // Do not animate the fixed text-conversion pair layout on mode change
                // (quality hot-path ban). Pane content updates stay immediate.
                IndexSegmentedControl(items: modes.map { ($0.id, $0.label) }, selection: modeSelection, density: .compact)
            },
            workspaceSemantic: .copyTransformWorkspace
        )
    }
}
