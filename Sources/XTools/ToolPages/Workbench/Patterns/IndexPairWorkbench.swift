import SwiftUI
import XToolsDesign

/// P5 paired workbench.
///
/// One paper for fill-height pages whose two workspaces sit side by side on
/// wide windows (an expression and its sample text, and similar pairs). The
/// shell measures the residual band: at or above the configured threshold
/// both panes share the row equally through a 14pt gap and fill the height
/// (280pt minimum); below it the panes split the remaining height in half so
/// the inner surfaces keep their own scrolling.
///
/// Pages own the workflow session, the diagnostic text, pane titles and
/// accessories, and the content; the shell owns the paper, the split point
/// and the one paper-level diagnostic slot so pair pages cannot drift back
/// into separate cards.
struct IndexPairWorkbench<Leading: View, Trailing: View>: View {
    /// Diagnostic text of the active workflow rendered in the paper-top slot.
    let diagnostic: String?
    /// Content width where the panes pass from stacked halves to one row.
    let horizontalThreshold: CGFloat

    private let leading: Leading
    private let trailing: Trailing

    @State private var workspaceDiagnostic: IndexWorkspaceDiagnosticPayload?
    @State private var diagnosticPresentation = IndexWorkspaceDiagnosticPresentationState()
    @Environment(\.toolToastCenter) private var toastCenter

    private let layoutPolicy = IndexPairWorkbenchLayoutPolicy()

    init(
        diagnostic: String? = nil,
        horizontalThreshold: CGFloat = IndexPairWorkbenchLayoutPolicy.defaultThreshold,
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.diagnostic = diagnostic
        self.horizontalThreshold = horizontalThreshold
        self.leading = leading()
        self.trailing = trailing()
    }

    var body: some View {
        VStack(spacing: 0) {
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
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .indexWorkspaceDiagnostic(diagnostic)
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

    // GeometryReader owns the residual page height. Horizontal mode fills that
    // band with two equal panes; stacked mode splits the band in half so each
    // pane's inner surfaces (note list, text editor) keep scrolling themselves.
    @ViewBuilder
    private var content: some View {
        GeometryReader { proxy in
            let policy = IndexPairWorkbenchLayoutPolicy(
                threshold: horizontalThreshold
            )
            let paneHeight = max(
                IndexPairWorkbenchLayoutPolicy.minimumPaneHeight,
                proxy.size.height
            )

            if policy.mode(for: proxy.size.width) == .horizontal {
                HStack(spacing: IndexPairWorkbenchLayoutPolicy.columnSpacing) {
                    leading
                        .frame(
                            width: policy.paneWidth(for: proxy.size.width),
                            height: paneHeight,
                            alignment: .topLeading
                        )
                    trailing
                        .frame(
                            width: policy.paneWidth(for: proxy.size.width),
                            height: paneHeight,
                            alignment: .topLeading
                        )
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                VStack(spacing: IndexPairWorkbenchLayoutPolicy.columnSpacing) {
                    leading
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    trailing
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

enum IndexPairWorkbenchLayoutMode: Equatable {
    case stacked
    case horizontal
}

/// Split contract for the paired paper workbench, inherited from the regex
/// page: from the configured content width (720pt by default) the two panes
/// share the row equally through a 14pt gap and fill the residual height —
/// under the split they stack and halve the band. Pure values, no SwiftUI
/// hosting; internal so the contract tests can exercise the math.
struct IndexPairWorkbenchLayoutPolicy {
    /// Legacy `IndexPairLayout(collapseWidth: 720)` breakpoint of the regex
    /// page, kept as the shell default.
    static let defaultThreshold: CGFloat = 720
    static let columnSpacing: CGFloat = 14
    static let minimumPaneHeight: CGFloat = 280

    let threshold: CGFloat

    init(threshold: CGFloat = Self.defaultThreshold) {
        self.threshold = threshold
    }

    func mode(for availableWidth: CGFloat) -> IndexPairWorkbenchLayoutMode {
        availableWidth >= threshold ? .horizontal : .stacked
    }

    func paneWidth(for availableWidth: CGFloat) -> CGFloat {
        max(0, (availableWidth - Self.columnSpacing) / 2)
    }
}
