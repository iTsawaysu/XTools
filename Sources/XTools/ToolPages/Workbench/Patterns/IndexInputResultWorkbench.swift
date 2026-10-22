import SwiftUI
import XToolsDesign

/// P3 input → result workbench.
///
/// One paper instead of stacked cards: a 44pt paper head carrying the input
/// identity and its controls, the paper-top diagnostic slot, the input
/// surface, a hairline, a 44pt result strip and the result surface. The input
/// owns the top half; the result takes the remaining height so short results
/// never leave an empty card behind.
struct IndexInputResultWorkbench<
    InputControls: View,
    ResultControls: View,
    Input: View,
    Result: View
>: View {
    let inputTitle: String
    let resultTitle: String
    /// Text-statistics style: the input owns the remaining height and the
    /// result stays at its natural height.
    var inputGrows = false
    private let inputControls: InputControls
    private let resultControls: ResultControls
    private let input: Input
    private let result: Result

    @State private var workspaceDiagnostic: IndexWorkspaceDiagnosticPayload?
    @State private var diagnosticPresentation = IndexWorkspaceDiagnosticPresentationState()
    @Environment(\.toolToastCenter) private var toastCenter

    init(
        inputTitle: String,
        resultTitle: String,
        inputGrows: Bool = false,
        @ViewBuilder inputControls: () -> InputControls,
        @ViewBuilder resultControls: () -> ResultControls,
        @ViewBuilder input: () -> Input,
        @ViewBuilder result: () -> Result
    ) {
        self.inputTitle = inputTitle
        self.resultTitle = resultTitle
        self.inputGrows = inputGrows
        self.inputControls = inputControls()
        self.resultControls = resultControls()
        self.input = input()
        self.result = result()
    }

    var body: some View {
        VStack(spacing: 0) {
            inputStrip
            divider
            IndexDiagnosticStatusSlot(isActive: workspaceDiagnostic != nil) {
                if let diagnostic = workspaceDiagnostic {
                    IndexDiagnosticBanner(
                        diagnostic: nil,
                        message: diagnostic.text,
                        tone: diagnostic.tone
                    )
                }
            }
            inputSlot
                .padding(.horizontal, ToolMetrics.Spacing.xs)
            divider
            resultStrip
            resultSlot
        }
        .background(
            ToolTheme.panelBackground,
            in: RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.panel, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.panel, style: .continuous)
                .strokeBorder(ToolTheme.border, lineWidth: 0.5)
        }
        .clipShape(RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.panel, style: .continuous))
        .toolAnimation(ToolMotion.Preset.diagnostic, value: workspaceDiagnostic != nil)
        .onPreferenceChange(IndexWorkspaceDiagnosticPreferenceKey.self) { diagnostic in
            if let announcement = diagnosticPresentation.update(to: diagnostic) {
                toastCenter?.show(announcement.text, tone: announcement.tone)
            }
            workspaceDiagnostic = diagnostic
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var inputSlot: some View {
        if inputGrows {
            input
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            input
        }
    }

    @ViewBuilder
    private var resultSlot: some View {
        if inputGrows {
            result
        } else {
            result
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var inputStrip: some View {
        HStack(spacing: ToolMetrics.Spacing.sm) {
            stripTitle(inputTitle)
            inputControls
        }
        .padding(.horizontal, ToolMetrics.Spacing.panelInset)
        .frame(height: ToolMetrics.Workbench.paperHeadHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) { divider }
    }

    private var resultStrip: some View {
        HStack(spacing: ToolMetrics.Spacing.sm) {
            stripTitle(resultTitle)
            Spacer(minLength: ToolMetrics.Spacing.sm)
            resultControls
        }
        .padding(.horizontal, ToolMetrics.Spacing.panelInset)
        .frame(height: ToolMetrics.Workbench.paperHeadHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) { divider }
    }

    private func stripTitle(_ title: String) -> some View {
        Text(title)
            .font(ToolTypography.panelTitle)
            .foregroundStyle(ToolTheme.textPrimary)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
    }

    private var divider: some View {
        Rectangle()
            .fill(ToolTheme.border)
            .frame(height: 0.5)
    }
}
