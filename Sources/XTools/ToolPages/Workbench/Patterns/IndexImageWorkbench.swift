import SwiftUI
import XToolsDesign

/// P5 image workbench: the only paper used by the five image segments.
///
/// One paper, one 44pt head carrying the segment title, optional parameters
/// and the save action, the paper-top diagnostic slot and one content stage.
/// The former compare / batch / single-preview / artifact shells are variants
/// of this implementation and must not be re-forked (audit H-01).
struct IndexImageWorkbench<Parameters: View, Content: View>: View {
    let title: String
    /// Segment parameters shown in the 44pt head; scrolls horizontally on
    /// narrow papers instead of wrapping or squeezing the save action.
    private let parameters: Parameters
    private let hasParameters: Bool
    private let trailingActions: AnyView?
    private let content: Content

    @State private var workspaceDiagnostic: IndexWorkspaceDiagnosticPayload?
    @State private var diagnosticPresentation = IndexWorkspaceDiagnosticPresentationState()
    @Environment(\.toolToastCenter) private var toastCenter

    init(
        title: String,
        trailingActions: AnyView? = nil,
        @ViewBuilder parameters: () -> Parameters,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.trailingActions = trailingActions
        self.parameters = parameters()
        self.hasParameters = !(Parameters.self == EmptyView.self)
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            head
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

    private var head: some View {
        HStack(spacing: ToolMetrics.Spacing.sm) {
            Text(title)
                .font(ToolTypography.panelTitle)
                .foregroundStyle(ToolTheme.textPrimary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)

            if hasParameters {
                ScrollView(.horizontal, showsIndicators: false) {
                    // One row on purpose: a parameter tuple must not become a
                    // vertical stack inside the 44pt head (audit H-02).
                    HStack(spacing: ToolMetrics.Spacing.sm) {
                        parameters
                    }
                    .padding(.leading, ToolMetrics.Spacing.sm)
                }
                .scrollBounceBehavior(.basedOnSize)
            }

            Spacer(minLength: ToolMetrics.Spacing.sm)

            if let trailingActions {
                trailingActions
            }
        }
        .padding(.horizontal, ToolMetrics.Spacing.panelInset)
        .frame(height: ToolMetrics.Workbench.paperHeadHeight)
        .overlay(alignment: .bottom) { divider }
    }

    private var divider: some View {
        Rectangle()
            .fill(ToolTheme.border)
            .frame(height: 0.5)
    }
}

extension IndexImageWorkbench where Parameters == EmptyView {
    init(
        title: String,
        trailingActions: AnyView? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.init(
            title: title,
            trailingActions: trailingActions,
            parameters: { EmptyView() },
            content: content
        )
    }
}
