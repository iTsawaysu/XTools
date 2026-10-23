import SwiftUI
import XToolsDesign

/// Single-result workbench for tools without an input: one paper, a 44pt head
/// with the actions, the paper-top diagnostic slot, and the result surface
/// filling the rest.
struct IndexResultWorkbench<Controls: View, Content: View>: View {
    let title: String
    private let controls: Controls
    private let content: Content

    @State private var workspaceDiagnostic: IndexWorkspaceDiagnosticPayload?
    @State private var diagnosticPresentation = IndexWorkspaceDiagnosticPresentationState()
    @Environment(\.toolToastCenter) private var toastCenter

    init(
        title: String,
        @ViewBuilder controls: () -> Controls,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.controls = controls()
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: ToolMetrics.Spacing.sm) {
                Text(title)
                    .font(ToolTypography.panelTitle)
                    .foregroundStyle(ToolTheme.textPrimary)
                Spacer(minLength: ToolMetrics.Spacing.sm)
                controls
            }
            .padding(.horizontal, ToolMetrics.Spacing.panelInset)
            .frame(height: ToolMetrics.Workbench.paperHeadHeight)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(ToolTheme.border)
                    .frame(height: ToolMetrics.Spacing.hairline)
            }

            IndexDiagnosticStatusSlot(isActive: workspaceDiagnostic != nil) {
                if let diagnostic = workspaceDiagnostic {
                    IndexDiagnosticBanner(
                        diagnostic: nil,
                        message: diagnostic.text,
                        tone: diagnostic.tone
                    )
                }
            }

            content
                .padding(.horizontal, ToolMetrics.Spacing.panelInset)
                .padding(.bottom, ToolMetrics.Spacing.panelInset)
                .padding(.top, ToolMetrics.Spacing.sm)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background(
            ToolTheme.panelBackground,
            in: RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.panel, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.panel, style: .continuous)
                .strokeBorder(ToolTheme.border, lineWidth: 0.5)
        }
        .toolErrorTint(active: workspaceDiagnostic?.tone == .error, cornerRadius: ToolMetrics.CornerRadius.panel)
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
}
