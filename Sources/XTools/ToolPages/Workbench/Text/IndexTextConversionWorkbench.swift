import SwiftUI
import UniformTypeIdentifiers

enum IndexTextConversionOutputPresentation: Equatable, Sendable {
    case standard
    case nativeReadOnlyText
    case markdownPreview
}

@MainActor
final class IndexTextTransformWorkspaceModel: ObservableObject {
    @Published var input = ""

    let execution = IndexFormatExecutionSession()
    var output: String { execution.binding.output }
    var error: String? { execution.binding.error }
    var warning: String? { execution.binding.warning }

    func clear() {
        execution.invalidate()
        input = ""
    }
}

enum IndexTextConversionSaveResult: Equatable, Sendable {
    case saved
    case cancelled
    case failed
}

enum IndexTextConversionSaveContentType {
    static func contentType(for fileName: String) -> UTType? {
        let fileExtension = URL(fileURLWithPath: fileName).pathExtension
        guard !fileExtension.isEmpty else {
            return nil
        }
        return UTType(filenameExtension: fileExtension)
    }
}

@MainActor
protocol IndexTextConversionTextSaving {
    func saveText(_ text: String, fileName: String, outputPanel: FileOutputPanelClient) async -> IndexTextConversionSaveResult
}

/// Sheet-based saver: selection suspends instead of running a synchronous
/// modal event loop.
@MainActor
struct AppKitIndexTextConversionTextSaver: IndexTextConversionTextSaving {
    func saveText(
        _ text: String,
        fileName: String,
        outputPanel: FileOutputPanelClient
    ) async -> IndexTextConversionSaveResult {
        guard !text.isEmpty else { return .failed }

        let request = FileOutputPanelRequest(
            defaultFilename: fileName,
            allowedContentTypes: [
                IndexTextConversionSaveContentType.contentType(for: fileName) ?? .plainText
            ],
            prompt: "存储"
        )
        guard let url = try? await outputPanel.selectFile(request) else {
            return .cancelled
        }

        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            return .saved
        } catch {
            return .failed
        }
    }
}

/// Shared editor workbench for text-input -> text-output conversion tools.
///
/// This is an explicit foundation for the semantic text conversion workspace:
/// stable controls sit outside this view, while the workbench owns pane-local
/// actions, internal editor/output scrolling, a fixed equal horizontal pair,
/// and pane-local copy/clear actions.
struct IndexTextConversionWorkbench: View {
    let inputTitle: String
    let outputTitle: String
    let placeholder: String
    @Binding var input: String
    let output: String
    var inputError: String? = nil
    var inputWarning: String? = nil
    var outputLineNumbers = false
    var outputColorize: ((String) -> AttributedString)? = nil
    var outputProcessingText: String? = nil
    var outputPresentation: IndexTextConversionOutputPresentation = .standard
    var showsInputCount = true
    var inputCountPresentation: IndexInputCountPresentation = .characters
    var onClear: (() -> Void)? = nil
    var clearDisabled: Bool? = nil
    var inputCaretPlacementRequestToken: Int? = nil
    var inputRenderingMode: IndexTextAreaRenderingMode? = nil
    var autoFocus = true
    var outputFileName = "output.txt"
    var showsOutputSave = false
    var workspaceSemantic: IndexWorkspaceSemantic = .copyTransformWorkspace
    var saveClient: any IndexTextConversionTextSaving = AppKitIndexTextConversionTextSaver()

    private var isClearDisabled: Bool {
        clearDisabled ?? (input.isEmpty && output.isEmpty && inputError == nil && inputWarning == nil)
    }

    private var visibleInputError: String? {
        guard let inputError, !inputError.isEmpty else {
            return nil
        }
        return inputError
    }

    private var visibleInputWarning: String? {
        guard let inputWarning, !inputWarning.isEmpty else {
            return nil
        }
        return inputWarning
    }

    private var inputDiagnosticText: String? {
        visibleInputError ?? visibleInputWarning
    }

    private var inputDiagnosticTone: ToolFeedbackTone {
        visibleInputError == nil && visibleInputWarning != nil ? .warning : .error
    }

    var body: some View {
        workbenchBody
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var workbenchBody: some View {
        // Clay Warmth: 12pt breathing gutter between the two editor cards.
        HStack(spacing: 12) {
            inputPanel
            staticDivider

            outputPanel
        }
    }

    private var staticDivider: some View {
        Rectangle()
            .fill(ToolTheme.border)
            .frame(width: 0.5)
            .accessibilityHidden(true)
    }

    private var inputPanel: some View {
        IndexPanel(inputTitle) {
            IndexWorkspaceTextArea(
                placeholder: placeholder,
                text: $input,
                fillsHeight: true,
                autoFocus: autoFocus,
                caretPlacementRequestToken: inputCaretPlacementRequestToken,
                inputRenderingMode: inputRenderingMode,
                workspaceSemantic: workspaceSemantic
            )
            .indexWorkspaceDiagnostic(inputDiagnosticText, tone: inputDiagnosticTone)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } accessory: {
            inputHeaderAccessory
        }
        .terminal("STDIN")
        .verticallyFilling()
    }

    private var outputPanel: some View {
        IndexPanel(outputTitle) {
            outputSurface
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } accessory: {
            outputHeaderActions
        }
        .terminal("STDOUT")
        .verticallyFilling()
    }

    @ViewBuilder
    private var outputSurface: some View {
        if let outputProcessingText {
            IndexTextConversionProcessingSurface(text: outputProcessingText)
        } else {
            switch outputPresentation {
            case .standard:
                IndexWorkspaceOutputSurface(
                    text: output,
                    placeholder: IndexEmptyStateCopy.outputWillShowHere,
                    fillsHeight: true,
                    lineNumbers: outputLineNumbers,
                    colorize: outputColorize,
                    workspaceSemantic: workspaceSemantic
                )
            case .nativeReadOnlyText:
                IndexReadOnlyTextSurface(
                    text: output,
                    placeholder: IndexEmptyStateCopy.outputWillShowHere,
                    fillsHeight: true
                )
            case .markdownPreview:
                IndexMarkdownPreviewSurface(
                    text: output,
                    placeholder: IndexEmptyStateCopy.outputWillShowHere,
                    fillsHeight: true
                )
            }
        }
    }

    private var inputHeaderAccessory: some View {
        IndexInputHeaderAccessory(
            countText: inputCountPresentation.label(for: input),
            showsInputCount: showsInputCount,
            clearDisabled: isClearDisabled,
            onClear: onClear
        ) { EmptyView() } compactControl: { EmptyView() }
    }

    private var outputHeaderActions: some View {
        HStack(spacing: 8) {
            IndexCopyButton(text: output, iconOnly: true)
            if showsOutputSave {
                IndexSaveTextButton(text: output, fileName: outputFileName, iconOnly: true, saveClient: saveClient)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

}

struct IndexSaveTextButton: View {
    let text: String
    let fileName: String
    var iconOnly = false
    var showsIcon = true
    var framed = false
    var saveClient: any IndexTextConversionTextSaving = AppKitIndexTextConversionTextSaver()

    @State private var feedback = IndexEphemeralActionFeedbackState()
    @Environment(\.toolToastCenter) private var toastCenter
    @Environment(\.fileOutputPanelClient) private var fileOutputPanelClient

    private var saved: Bool { feedback.isPresented }

    var body: some View {
        Button {
            saveText()
        } label: {
            if iconOnly {
                Image(systemName: saved ? "checkmark" : IndexActionSymbol.save)
                    .frame(width: 16, height: 16)
                    .toolMotionSuccessSwap(id: saved)
            } else {
                Label {
                    Text(saved ? "已保存" : "保存")
                        .toolMotionTextSwap(id: saved)
                } icon: {
                    if showsIcon {
                        Image(systemName: saved ? "checkmark" : IndexActionSymbol.save)
                            .toolMotionIconSwap(id: saved)
                    }
                }
            }
        }
        .buttonStyle(IndexSmallButtonStyle(done: saved, framed: framed))
        .disabled(text.isEmpty)
        .help(saved ? "已保存" : "保存输出")
        .accessibilityLabel(saved ? "已保存" : "保存输出")
        .task(id: feedback.generation) {
            let generation = feedback.generation
            guard feedback.isPresented else { return }

            do {
                try await Task.sleep(for: IndexEphemeralActionFeedbackState.holdDuration)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            feedback.finish(generation: generation)
        }
    }

    private func saveText() {
        guard !text.isEmpty else { return }

        Task { @MainActor in
            switch await saveClient.saveText(text, fileName: fileName, outputPanel: fileOutputPanelClient) {
            case .saved:
                toastCenter?.show(ToolFeedbackCopy.savedOutput, tone: .success)
                feedback.trigger()
            case .cancelled:
                return
            case .failed:
                toastCenter?.show("无法保存输出", tone: .error)
            }
        }
    }
}

/// In-pane processing state for workbench outputs (debounced conversion,
/// URL fetches): replaces the pane content without covering text.
struct IndexTextConversionProcessingSurface: View {
    let text: String

    var body: some View {
        IndexProgressLabel(message: text, layout: .centered)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .background(ToolTheme.editorBackground, in: RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.field, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.field, style: .continuous)
                .strokeBorder(ToolTheme.border, lineWidth: 0.5)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(text)
    }
}
