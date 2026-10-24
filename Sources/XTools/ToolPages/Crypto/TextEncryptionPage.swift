import XToolsCore
import SwiftUI
import XToolsDesign

struct TextEncryptionRequest: Sendable {
    let input: String
    let password: String
    let mode: String
    let algorithm: String
}

struct TextEncryptionOutcome: Sendable {
    let output: String
    let error: String?
}

typealias TextEncryptionOperation = @Sendable (TextEncryptionRequest) -> TextEncryptionOutcome

@MainActor
final class TextEncryptionToolWorkspaceModel: ObservableObject {
    static let key = ToolWorkspaceKey<TextEncryptionToolWorkspaceModel>(toolID: "text-encryption") { _ in
        TextEncryptionToolWorkspaceModel()
    }

    @Published var mode = "enc" {
        didSet { if mode != oldValue { clearResult() } }
    }
    @Published var algorithm = TextEncryptionService.Algorithm.aesGCM.rawValue {
        didSet { if algorithm != oldValue { clearResult() } }
    }
    @Published var password = "" {
        didSet { if !password.utf8.elementsEqual(oldValue.utf8) { clearResult() } }
    }
    @Published var input = "" {
        didSet { if !input.utf8.elementsEqual(oldValue.utf8) { clearResult() } }
    }
    @Published var output = ""
    @Published var error: String?

    private let execution = SupersedingExecutionSession(cancelInFlight: true)
    private let operation: TextEncryptionOperation

    convenience init() {
        self.init(operation: Self.defaultOperation)
    }

    init(operation: @escaping TextEncryptionOperation) {
        self.operation = operation
    }

    func changeMode(to newMode: String) {
        guard newMode != mode else {
            return
        }

        let nextInput = error == nil && !output.isEmpty ? output : nil
        mode = newMode
        if let nextInput {
            input = nextInput
        }
    }

    func changeAlgorithm(to newAlgorithm: String) {
        guard newAlgorithm != algorithm else {
            return
        }

        algorithm = newAlgorithm
    }

    func clearSensitiveState() {
        clearResult()
        input = ""
        password = ""
    }

    func clearResult() {
        execution.invalidate()
        output = ""
        error = nil
    }

    /// Computes the cipher/plaintext once and stores it. `output` must be stored
    /// state, not a `body`-read computed property: encryption uses a fresh random
    /// salt each call, so recomputing on every re-render would make the displayed
    /// (and copied) ciphertext change unpredictably between frames.
    func run() {
        guard !input.isEmpty else { clearResult(); return }
        guard !password.isEmpty else { clearResult(); error = "加密口令不能为空。"; return }

        let request = TextEncryptionRequest(input: input, password: password, mode: mode, algorithm: algorithm)
        let operation = self.operation
        output = ""
        error = nil
        execution.schedule(operation: { _ in operation(request) }) { [weak self] _, outcome in
            guard let self else { return }
            self.output = outcome.output
            self.error = outcome.error
        }
    }

    nonisolated private static let defaultOperation: TextEncryptionOperation = { request in
        let algorithm = TextEncryptionService.Algorithm(rawValue: request.algorithm) ?? .aesGCM
        do {
            let output = request.mode == "enc"
                ? try TextEncryptionService.encrypt(request.input, password: request.password, algorithm: algorithm)
                : try TextEncryptionService.decrypt(request.input, password: request.password, algorithm: algorithm)
            return TextEncryptionOutcome(output: output, error: nil)
        } catch let err as TextEncryptionService.Error {
            return TextEncryptionOutcome(
                output: "",
                error: err.errorDescription ?? (request.mode == "enc" ? "加密操作失败。" : "解密操作失败。")
            )
        } catch {
            DiagnosticFallbackLog.record(error, context: "TextEncryptionPage.convert")
            return TextEncryptionOutcome(output: "", error: request.mode == "enc" ? "加密操作失败。" : "解密操作失败。")
        }
    }
}

struct IndexTextEncryptionPage: View {
    var body: some View {
        ToolWorkspaceHost(key: TextEncryptionToolWorkspaceModel.key) { workspace, _ in
            IndexTextEncryptionWorkspaceContent(workspace: workspace)
        }
    }
}

/// 统一壳装配（page-rollout D1）：加密/解密方向分段是页面级模式（changeMode
/// 自带回填语义：有输出时密文回填为反向输入），归标题行 titleAccessory
/// （Base64File 编码/解码分段先例）；算法菜单 + 弱算法提示 + 口令字段是
/// 影响当下加解密的即时参数，归弹性参数区（SecureInput 唯一安全输入面保留）；
/// 「加密/解密 ⌘↩」走壳级 primaryAction（enabled 门控同旧 disabled 按钮）；
/// 方向互换动作（design-system 挂账「.swap 已建待接入」的兑现）接入输出
/// pane ActionBar 的 `.swap`——与分段同走 changeMode（回填语义一致），方向
/// 状态仍由分段持续可见；清空归输入 pane 尾 ActionBar，复制归输出 pane 尾
/// ActionBar（⇧⌘C 由 IOPair 根部代理持有，页面只在 IOPair 声明一次）；转换
/// 错误走 preference 单轨（旧 IndexTextConversionWorkbench 的纸顶槽等价平移）。
private struct IndexTextEncryptionWorkspaceContent: View {
    @Environment(\.toolPageEntryGeneration) private var entryGeneration
    @ObservedObject var workspace: TextEncryptionToolWorkspaceModel
    @State private var showsPassword = false
    @State private var weakAlgorithmPresentation = IndexWorkspaceDiagnosticPresentationState()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.toolToastCenter) private var toastCenter

    private let weakAlgorithmMessage = "当前算法安全性较弱。"

    private var mode: String { workspace.mode }
    private var algorithm: String { workspace.algorithm }
    private var password: String { workspace.password }
    private var input: String { workspace.input }
    private var output: String { workspace.output }
    private var error: String? { workspace.error }

    private var inputPlaceholder: String {
        guard mode == "dec" else { return "输入要加密的文本…" }
        return selectedAlgorithm == .aesGCM
            ? "输入 DT-AES-GCM-v1 密文…"
            : "输入 OpenSSL Salted__ Base64 密文…"
    }

    private var selectedAlgorithm: TextEncryptionService.Algorithm {
        TextEncryptionService.Algorithm(rawValue: algorithm) ?? .aesGCM
    }

    private var modeSelection: Binding<String> {
        Binding(get: { mode }, set: { changeMode(to: $0) })
    }

    private var algorithmSelection: Binding<String> {
        Binding(get: { algorithm }, set: { changeAlgorithm(to: $0) })
    }

    private var algorithmItems: [(String, String)] {
        TextEncryptionService.Algorithm.allCases.map { ($0.rawValue, $0.displayName) }
    }

    private var primaryActionTitle: String {
        mode == "enc" ? "加密" : "解密"
    }

    private var primaryActionHelp: String {
        mode == "enc" ? "加密（⌘↩）" : "解密（⌘↩）"
    }

    private var showsWeakAlgorithmWarning: Bool {
        mode == "enc" && selectedAlgorithm.isInsecure
    }

    private var weakAlgorithmDiagnostic: IndexWorkspaceDiagnosticPayload? {
        guard showsWeakAlgorithmWarning else { return nil }
        return IndexWorkspaceDiagnosticPayload(
            text: weakAlgorithmMessage,
            tone: .warning,
            maxWidth: 320
        )
    }

    /// 旧 clearDisabled 表达式（显式传入旧壳的同条件）：输入、输出、错误与
    /// 口令全部为空时清空不可用。
    private var clearDisabled: Bool {
        input.isEmpty && output.isEmpty && error == nil && password.isEmpty
    }

    var body: some View {
        IndexPage("文本加密", subtitle: "默认使用 AES-GCM 认证加密，并保留 OpenSSL 旧格式兼容。", workspaceSemantic: .securityTransformWorkspace) {
            WorkbenchSurface(
                title: nil,
                primaryAction: WorkbenchPrimaryAction(
                    title: primaryActionTitle,
                    help: primaryActionHelp,
                    enabled: !primaryActionDisabled,
                    perform: run
                ),
                shape: .inputOutput,
                titleAccessory: { modeControl },
                parameters: { parameterFlow }
            ) {
                WorkbenchIOPair(
                    leadingTitle: mode == "enc" ? "明文" : "密文",
                    trailingTitle: mode == "enc" ? "密文" : "明文",
                    leadingActions: [
                        .clear(enabled: !clearDisabled, onPerform: clearSensitiveState)
                    ],
                    trailingActions: [
                        .swap(onPerform: swapDirection, directionLabel: "加密 ↔ 解密"),
                        .copy(text: output)
                    ],
                    leadingAccessory: { stdinCluster },
                    leading: { inputPane },
                    trailingAccessory: { stdoutBadge },
                    trailing: { outputPane }
                )
                // 诊断单轨：加解密错误（旧壳 inputError 纸顶槽等价平移）。
                .indexWorkspaceDiagnostic(error, tone: .error)
            }
        }
        .onChange(of: entryGeneration) {
            if entryGeneration == 0 { showsPassword = false }
        }
        .onChange(of: weakAlgorithmDiagnostic) {
            if let announcement = weakAlgorithmPresentation.update(to: weakAlgorithmDiagnostic) {
                toastCenter?.show(announcement.text, tone: announcement.tone)
            }
        }
    }

    /// 弹性参数区：算法菜单（弱算法时 tone 警告描边）与条件在场的弱算法
    /// 状态钮同组（旧 headControls 算法簇等价平移）；口令字段随行（放不下
    /// 换行，永不横滚）。
    private var parameterFlow: some View {
        WorkbenchParameterFlow {
            WorkbenchParameterGroup {
                WorkbenchParameterItem {
                    algorithmControlGroup
                }
                WorkbenchParameterItem {
                    passwordInput
                        .frame(
                            minWidth: ToolMetrics.Control.fieldMinWidth,
                            idealWidth: ToolMetrics.Control.passwordIdealWidth,
                            maxWidth: ToolMetrics.Control.passwordMaxWidth
                        )
                }
            }
        }
    }

    /// 加密/解密方向分段（页面级模式，标题行承载；当前方向状态持续可见）。
    private var modeControl: some View {
        IndexSegmentedControl(items: [("enc", "加密"), ("dec", "解密")], selection: modeSelection)
            .frame(width: ToolMetrics.Control.modeSegment, height: ToolMetrics.Control.modeSegmentHeight)
    }

    private var algorithmSelector: some View {
        IndexOptionMenu(
            items: algorithmItems,
            selection: algorithmSelection,
            title: "算法",
            tone: showsWeakAlgorithmWarning ? .warning : nil
        )
    }

    private var algorithmControlGroup: some View {
        HStack(spacing: ToolMetrics.Spacing.fine) {
            algorithmSelector
            if let weakAlgorithmDiagnostic {
                IndexDiagnosticStatusButton(payload: weakAlgorithmDiagnostic)
                    .toolTransition(ToolMotion.Transition.diagnostic, reduceMotion: reduceMotion)
            }
        }
    }

    /// The operation needs both a payload and a password; without either the
    /// button must read as unavailable instead of accepting a silent no-op
    /// (audit C-03 / I-01).
    private var primaryActionDisabled: Bool {
        workspace.input.isEmpty || workspace.password.isEmpty
    }

    private var passwordInput: some View {
        IndexSecureInput(
            placeholder: "加密口令",
            text: $workspace.password,
            showsSecret: $showsPassword,
            secretNoun: "加密口令"
        )
    }

    /// 输入 pane 头附件：STDIN 徽章 + 实时字符计数（旧 pane terminalTag 与
    /// IndexInputHeaderAccessory 计数等价平移）。
    private var stdinCluster: some View {
        HStack(spacing: ToolMetrics.Spacing.fine) {
            IndexBadge("STDIN", tone: .neutral, isCapsule: true)
            IndexInputCountLabel(
                text: IndexInputCountPresentation.characters.label(for: input)
            )
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var stdoutBadge: some View {
        IndexBadge("STDOUT", tone: .neutral, isCapsule: true)
            .fixedSize(horizontal: true, vertical: false)
    }

    /// 输入 pane 内容（旧壳 input 槽投影）：受控 AppKit 编辑器填满 pane。
    private var inputPane: some View {
        IndexWorkspaceTextArea(
            placeholder: inputPlaceholder,
            text: $workspace.input,
            fillsHeight: true,
            autoFocus: true,
            workspaceSemantic: .securityTransformWorkspace
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // 焦点契约（阶段③ C3）：页面首个输入 = 输入编辑器。
        .workbenchFocusTarget()
    }

    /// 输出 pane 内容（旧壳 output 槽投影）：standard 呈现（无行号/无着色）。
    private var outputPane: some View {
        IndexOutputSurface(
            text: output,
            placeholder: IndexEmptyStateCopy.outputWillShowHere,
            lineNumbers: false,
            fillsHeight: true,
            workspaceSemantic: .securityTransformWorkspace
        )
    }

    /// 方向互换（ActionBar .swap 入口）：与分段同走 changeMode，回填语义
    /// （有输出时密文回填为反向输入）一致。
    private func swapDirection() {
        changeMode(to: mode == "enc" ? "dec" : "enc")
    }

    private func changeMode(to newMode: String) {
        workspace.changeMode(to: newMode)
    }

    private func changeAlgorithm(to newAlgorithm: String) {
        workspace.changeAlgorithm(to: newAlgorithm)
    }

    private func clearSensitiveState() {
        workspace.clearSensitiveState()
        showsPassword = false
    }

    private func run() {
        workspace.run()
    }
}
