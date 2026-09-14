import XToolsCore
import SwiftUI

@MainActor
final class TextEncryptionToolWorkspaceModel: ObservableObject {
    static let key = ToolWorkspaceKey<TextEncryptionToolWorkspaceModel>(toolID: "text-encryption") { _ in
        TextEncryptionToolWorkspaceModel()
    }

    @Published var mode = "enc"
    @Published var algorithm = TextEncryptionService.Algorithm.aesGCM.rawValue
    @Published var password = ""
    @Published var input = ""
    @Published var output = ""
    @Published var error: String?
    private var selectedAlgorithm: TextEncryptionService.Algorithm {
        TextEncryptionService.Algorithm(rawValue: algorithm) ?? .aesGCM
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
        clearResult()
    }

    func changeAlgorithm(to newAlgorithm: String) {
        guard newAlgorithm != algorithm else {
            return
        }

        algorithm = newAlgorithm
        clearResult()
    }

    func clearSensitiveState() {
        input = ""
        output = ""
        error = nil
        password = ""
    }

    func clearResult() {
        output = ""
        error = nil
    }

    /// Computes the cipher/plaintext once and stores it. `output` must be stored
    /// state, not a `body`-read computed property: encryption uses a fresh random
    /// salt each call, so recomputing on every re-render would make the displayed
    /// (and copied) ciphertext change unpredictably between frames.
    func run() {
        guard !input.isEmpty else { output = ""; error = nil; return }
        guard !password.isEmpty else { output = ""; error = "加密口令不能为空。"; return }

        do {
            output = mode == "enc"
                ? try TextEncryptionService.encrypt(input, password: password, algorithm: selectedAlgorithm)
                : try TextEncryptionService.decrypt(input, password: password, algorithm: selectedAlgorithm)
            error = nil
        } catch let err as TextEncryptionService.Error {
            output = ""
            error = err.errorDescription ?? (mode == "enc" ? "加密操作失败。" : "解密操作失败。")
        } catch {
            output = ""
            self.error = mode == "enc" ? "加密操作失败。" : "解密操作失败。"
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
            IndexWorkbenchControlBar {
                wideControls
            } compactControls: {
                compactControls
            }

            IndexTextConversionWorkbench(
                inputTitle: mode == "enc" ? "明文" : "密文",
                outputTitle: mode == "enc" ? "密文" : "明文",
                placeholder: inputPlaceholder,
                input: $workspace.input,
                output: output,
                inputError: error,
                onClear: clearSensitiveState,
                clearDisabled: input.isEmpty && output.isEmpty && error == nil && password.isEmpty,
                workspaceSemantic: .securityTransformWorkspace
            )
                .onChange(of: input) { _ in clearResult() }
                .onChange(of: password) { _ in clearResult() }
        }
        .onChange(of: weakAlgorithmDiagnostic) { diagnostic in
            if let announcement = weakAlgorithmPresentation.update(to: diagnostic) {
                toastCenter?.show(announcement.text, tone: announcement.tone)
            }
        }
    }

    private var wideControls: some View {
        HStack(spacing: 9) {
            modeControl
            algorithmControlGroup
            widePasswordInput
                .layoutPriority(1)
            primaryActionButton
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var compactControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                modeControl
                algorithmControlGroup
            }

            HStack(spacing: 9) {
                compactPasswordInput
                primaryActionButton
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var modeControl: some View {
        IndexSegmentedControl(items: [("enc", "加密"), ("dec", "解密")], selection: modeSelection)
            .frame(width: 110, height: 38)
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
        HStack(spacing: 6) {
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
            .frame(minWidth: 76)
            .keyboardShortcut(.return, modifiers: .command)
    }

    private var widePasswordInput: some View {
        passwordInput
            .frame(minWidth: 160, idealWidth: 220, maxWidth: .infinity)
    }

    private var compactPasswordInput: some View {
        passwordInput
            .frame(minWidth: 160, idealWidth: 220, maxWidth: 280)
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

    private func clearResult() {
        workspace.clearResult()
    }

    private func run() {
        workspace.run()
    }
}
