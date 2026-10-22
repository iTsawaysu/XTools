import SwiftUI
import XToolsDesign

/// P5 stacked workbench.
///
/// One natural-height paper for scroll-height pages whose workflow stacks
/// several working bands: parameters above, sibling preview columns in the
/// middle, the derived output below. The shell owns the paper chrome, the
/// paper-top diagnostic slot and the single-file drop target; every band is
/// composed from the shared `IndexWorkbenchPane` (44pt title row closed by a
/// hairline), so stacked-band pages cannot drift back into separate cards.
struct IndexStackedWorkbench<Bands: View>: View {
    /// Diagnostic text rendered in the paper-top slot.
    let diagnostic: String?
    /// Stretch the paper over the residual page height (fill-height pages).
    let fillsHeight: Bool

    @ViewBuilder private let bands: () -> Bands

    @State private var workspaceDiagnostic: IndexWorkspaceDiagnosticPayload?
    @State private var diagnosticPresentation = IndexWorkspaceDiagnosticPresentationState()
    @Environment(\.toolToastCenter) private var toastCenter

    private var activeDiagnostic: IndexWorkspaceDiagnosticPayload? {
        if let workspaceDiagnostic { return workspaceDiagnostic }
        guard let diagnostic, !diagnostic.isEmpty else { return nil }
        return IndexWorkspaceDiagnosticPayload(text: diagnostic, tone: .error, maxWidth: 460)
    }

    init(
        diagnostic: String? = nil,
        fillsHeight: Bool = false,
        @ViewBuilder bands: @escaping () -> Bands
    ) {
        self.diagnostic = diagnostic
        self.fillsHeight = fillsHeight
        self.bands = bands
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            IndexDiagnosticStatusSlot(isActive: activeDiagnostic != nil) {
                if let activeDiagnostic {
                    IndexDiagnosticBanner(
                        diagnostic: nil,
                        message: activeDiagnostic.text,
                        tone: activeDiagnostic.tone
                    )
                }
            }
            if let diagnostic, !diagnostic.isEmpty {
                bands()
                    .indexWorkspaceDiagnostic(diagnostic)
            } else {
                // Publish nothing at this level: an explicit nil preference
                // would shadow the per-band `indexWorkspaceDiagnostic` values
                // that panes inside the paper publish (JWT parse errors).
                bands()
            }
        }
        .frame(
            maxWidth: .infinity,
            maxHeight: fillsHeight ? .infinity : nil,
            alignment: .topLeading
        )
        // Scroll pages still propose a finite viewport height, which would let
        // the panes' stretch frames grab a share of it and strand empty bands.
        // A stacked paper takes its ideal height and lets the page background
        // breathe underneath instead.
        .fixedSize(horizontal: false, vertical: !fillsHeight)
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
        .onPreferenceChange(IndexWorkspaceDiagnosticPreferenceKey.self) { preference in
            if let announcement = diagnosticPresentation.update(to: preference) {
                toastCenter?.show(announcement.text, tone: announcement.tone)
            }
            workspaceDiagnostic = preference
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}
