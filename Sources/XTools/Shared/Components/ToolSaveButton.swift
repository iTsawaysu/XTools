import SwiftUI

// Shared save-output action for text workbenches. Keeps the success tick,
// toast feedback and file-panel behavior in one component.

struct ToolSaveButton: View {
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
        .buttonStyle(ToolSmallButtonStyle(done: saved, framed: framed))
        .disabled(text.isEmpty)
        .accessibilityLabel(saved ? "已保存" : "保存输出")
        .accessibilityHint(saved ? "已保存" : "保存输出")
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

@available(*, deprecated, renamed: "ToolSaveButton")
typealias IndexSaveTextButton = ToolSaveButton
