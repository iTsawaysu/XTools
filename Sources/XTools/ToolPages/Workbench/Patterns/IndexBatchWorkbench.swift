import SwiftUI
import XToolsDesign

/// P5 batch workbench: one paper whose top strip carries the batch parameters,
/// a hairline, the shared diagnostic slot and the drop target / selection list.
///
/// Pages own the parameter controls, import session and save action; this shell
/// owns the paper, the scrolling parameter strip and the diagnostic anchor so
/// batch pages cannot drift back to a toolbar floating outside the surface.
struct IndexBatchWorkbench<Parameters: View, Content: View>: View {
    let title: String
    private let parameters: Parameters
    private let content: Content

    @State private var workspaceDiagnostic: IndexWorkspaceDiagnosticPayload?
    @State private var diagnosticPresentation = IndexWorkspaceDiagnosticPresentationState()
    @Environment(\.toolToastCenter) private var toastCenter

    init(
        title: String,
        @ViewBuilder parameters: () -> Parameters,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.parameters = parameters()
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            parameterBar
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
            content
                .padding(ToolMetrics.Spacing.panelInset)
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

    /// The strip scrolls horizontally on narrow windows instead of wrapping
    /// into the content or squeezing the title; controls keep their intrinsic
    /// widths at every window size.
    private var parameterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: ToolMetrics.Spacing.md) {
                Text(title)
                    .font(ToolTypography.panelTitle)
                    .foregroundStyle(ToolTheme.textPrimary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)

                parameters
            }
            .padding(.horizontal, ToolMetrics.Spacing.md)
            .frame(height: 44)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private var divider: some View {
        Rectangle()
            .fill(ToolTheme.border)
            .frame(height: 0.5)
    }
}
