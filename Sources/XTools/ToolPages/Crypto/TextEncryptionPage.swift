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

    var body: some View {
        IndexPage("文本加密", subtitle: "默认使用 AES-GCM 认证加密，并保留 OpenSSL 旧格式兼容。", workspaceSemantic: .securityTransformWorkspace) {
            IndexTextConversionWorkbench(
                inputTitle: mode == "enc" ? "明文" : "密文",
                outputTitle: mode == "enc" ? "密文" : "明文",
                placeholder: inputPlaceholder,
                input: $workspace.input,
                output: output,
                inputError: error,
                onClear: clearSensitiveState,
                clearDisabled: input.isEmpty && output.isEmpty && error == nil && password.isEmpty,
                workspaceSemantic: .securityTransformWorkspace,
                headControls: AnyView(encryptionHeadControls)
            )
        }
        .onChange(of: entryGeneration) { generation in
            if generation == 0 { showsPassword = false }
        }
        .onChange(of: weakAlgorithmDiagnostic) { diagnostic in
            if let announcement = weakAlgorithmPresentation.update(to: diagnostic) {
                toastCenter?.show(announcement.text, tone: announcement.tone)
            }
        }
    }

    /// Paper-head row: mode + algorithm + secret + run, one line, exactly the
    /// 44pt rail every other tool uses.
    private var encryptionHeadControls: some View {
        HStack(spacing: ToolMetrics.Spacing.sm) {
            modeControl
            algorithmControlGroup
            widePasswordInput
                .layoutPriority(1)
            primaryActionButton
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var compactControls: some View {
        VStack(alignment: .leading, spacing: ToolMetrics.Spacing.sm) {
            HStack(spacing: ToolMetrics.Spacing.sm) {
                modeControl
                algorithmControlGroup
            }

            HStack(spacing: ToolMetrics.Spacing.sm) {
                compactPasswordInput
                primaryActionButton
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

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

    private var primaryActionButton: some View {
        Button { run() } label: { Label(primaryActionTitle, systemImage: "play.fill") }
            .buttonStyle(IndexButtonStyle(primary: true))
            .frame(minWidth: ToolMetrics.Control.actionMinWidth)
            .disabled(primaryActionDisabled)
            .keyboardShortcut(entryGeneration > 0 ? KeyboardShortcut(.return, modifiers: .command) : nil)
    }

    /// The operation needs both a payload and a password; without either the
    /// button must read as unavailable instead of accepting a silent no-op
    /// (audit C-03 / I-01).
    private var primaryActionDisabled: Bool {
        workspace.input.isEmpty || workspace.password.isEmpty
    }

    private var widePasswordInput: some View {
        passwordInput
            .frame(minWidth: ToolMetrics.Control.fieldMinWidth, idealWidth: ToolMetrics.Control.passwordIdealWidth, maxWidth: .infinity)
    }

    private var compactPasswordInput: some View {
        passwordInput
            .frame(minWidth: ToolMetrics.Control.fieldMinWidth, idealWidth: ToolMetrics.Control.passwordIdealWidth, maxWidth: ToolMetrics.Control.passwordMaxWidth)
    }

    private var passwordInput: some View {
        IndexSecureInput(
            placeholder: "加密口令",
            text: $workspace.password,
            showsSecret: $showsPassword,
            secretNoun: "加密口令"
        )
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
