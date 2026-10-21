import SwiftUI
import XToolsDesign

/// P5 file workbench.
///
/// One paper for workflows whose input and result are two sibling workspaces:
/// the page shell keeps the title, subtitle and the mode control, and this
/// paper fills the residual band with the two panes. Wide windows keep the
/// panes side by side with a 14pt gap and a `1 : 1.05` width split (398pt row
/// minimum); narrower windows stack them in workspace order (280pt pane
/// minimum) and scroll inside the paper instead of the page.
///
/// Pages own the workflow session, the diagnostic text, pane titles and
/// accessories, the file picker, preview surfaces and save actions; this shell
/// owns the paper, the split policy, the one paper-level diagnostic slot and
/// the pane head/foot frames so file pages cannot drift back into separate
/// cards.
struct IndexFileWorkbench<Leading: View, Trailing: View>: View {
    /// Diagnostic text of the active workflow. The shell renders it in the one
    /// paper-top slot (an encode workflow passes the file error, a decode
    /// workflow the reverse error) instead of per-pane diagnostic slots.
    let diagnostic: String?

    private let leading: Leading
    private let trailing: Trailing

    @State private var workspaceDiagnostic: IndexWorkspaceDiagnosticPayload?
    @State private var diagnosticPresentation = IndexWorkspaceDiagnosticPresentationState()
    @Environment(\.toolToastCenter) private var toastCenter

    private let layoutPolicy = IndexFileWorkbenchLayoutPolicy()

    init(
        diagnostic: String?,
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.diagnostic = diagnostic
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
    // band (min 398pt); stacked mode keeps one outer ScrollView so both
    // complete panes remain reachable. ScrollView alone cannot propose a finite
    // height, which previously pinned wide panes to the 398pt floor and left a
    // large empty slab under the workbench.
    @ViewBuilder
    private var content: some View {
        GeometryReader { proxy in
            let horizontalHeight = max(
                IndexFileWorkbenchLayoutPolicy.minimumHorizontalHeight,
                proxy.size.height
            )

            if let widths = layoutPolicy.columnWidths(for: proxy.size.width) {
                HStack(spacing: IndexFileWorkbenchLayoutPolicy.columnSpacing) {
                    leading
                        .frame(
                            width: widths.leading,
                            height: horizontalHeight,
                            alignment: .topLeading
                        )
                    trailing
                        .frame(
                            width: widths.trailing,
                            height: horizontalHeight,
                            alignment: .topLeading
                        )
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                ScrollView {
                    VStack(spacing: IndexFileWorkbenchLayoutPolicy.columnSpacing) {
                        leading
                            .frame(
                                maxWidth: .infinity,
                                minHeight: IndexFileWorkbenchLayoutPolicy.minimumStackedPaneHeight,
                                alignment: .topLeading
                            )
                        trailing
                            .frame(
                                maxWidth: .infinity,
                                minHeight: IndexFileWorkbenchLayoutPolicy.minimumStackedPaneHeight,
                                alignment: .topLeading
                            )
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .scrollIndicators(.automatic)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// One pane of a paper workbench: the 44pt head (title + accessory), the
/// stretching content and the optional session-derived foot. Workbench shells
/// assembled from this pane chrome (Base64 files, the regex pair and friends)
/// keep the same geometry in every state; panes without a session-derived
/// status close their content with the standard inset instead.
struct IndexWorkbenchPane<Accessory: View, Content: View>: View {
    private let title: String
    private let footer: IndexWorkbenchFooter?
    private let accessory: Accessory
    private let content: Content

    init(
        title: String,
        footer: IndexWorkbenchFooter? = nil,
        @ViewBuilder accessory: () -> Accessory,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.footer = footer
        self.accessory = accessory()
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            IndexWorkbenchHeader(title: title) { accessory }

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.horizontal, IndexWorkbenchPaneMetrics.inset)
                .padding(.top, IndexWorkbenchPaneMetrics.inset)
                .padding(.bottom, footer == nil ? IndexWorkbenchPaneMetrics.inset : 0)

            if let footer {
                footer
            }
        }
    }
}

/// Pane head: the 44pt title/control row closed by a hairline — the pane-level
/// counterpart of the shared panel head.
private struct IndexWorkbenchHeader<Accessory: View>: View {
    private let title: String
    private let accessory: Accessory

    init(title: String, @ViewBuilder accessory: () -> Accessory) {
        self.title = title
        self.accessory = accessory()
    }

    var body: some View {
        HStack(spacing: ToolMetrics.Spacing.sm) {
            Text(title)
                .font(ToolTypography.panelTitle)
                .foregroundStyle(ToolTheme.textSecondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(1)

            Spacer(minLength: ToolMetrics.Spacing.sm)

            accessory
                .layoutPriority(2)
        }
        .padding(.horizontal, IndexWorkbenchPaneMetrics.inset)
        .frame(height: IndexWorkbenchPaneMetrics.headerHeight)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(ToolTheme.border)
                .frame(height: 0.5)
        }
    }
}

/// Pane foot: one session-derived status (optional tone dot) with trailing
/// guidance on a 16pt caption row. The foot geometry (14pt side insets, an
/// 11pt gap above, a 14pt inset below) lives here so pane feet stay aligned
/// without per-page spacing math.
struct IndexWorkbenchFooter: View {
    let status: String
    var statusTone: Color? = nil
    let trailingText: String

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                if let statusTone {
                    Circle()
                        .fill(statusTone)
                        .frame(width: 6, height: 6)
                        .accessibilityHidden(true)
                }
                Text(status)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Text(trailingText)
                .lineLimit(1)
                .truncationMode(.tail)
                .multilineTextAlignment(.trailing)
        }
        .font(ToolTypography.caption)
        .foregroundStyle(ToolTheme.textTertiary)
        .frame(maxWidth: .infinity, minHeight: IndexWorkbenchPaneMetrics.footerMinHeight)
        .padding(.horizontal, IndexWorkbenchPaneMetrics.inset)
        .padding(.top, IndexWorkbenchPaneMetrics.footerGap)
        .padding(.bottom, IndexWorkbenchPaneMetrics.inset)
        .accessibilityElement(children: .combine)
    }
}

private enum IndexWorkbenchPaneMetrics {
    /// The approved 44pt pane-head row from the file workbench contract.
    static let headerHeight: CGFloat = 44
    static let inset: CGFloat = ToolMetrics.Spacing.panelInset
    /// Space between the stretching content and the pane foot.
    static let footerGap: CGFloat = 11
    static let footerMinHeight: CGFloat = 16
}

enum IndexFileWorkbenchLayoutMode: Equatable {
    case stacked
    case horizontal
}

struct IndexFileWorkbenchColumnWidths: Equatable {
    let leading: CGFloat
    let trailing: CGFloat
}

/// Split contract for the two file-workspace panes, inherited from the Base64
/// file page: from 900pt of workbench width the panes share the row with a
/// 14pt gap in a `1 : 1.05` ratio and the row keeps a 398pt minimum height;
/// below the split each stacked pane asks for 280pt. Pure values, no SwiftUI
/// hosting; internal so the contract tests can exercise the math.
struct IndexFileWorkbenchLayoutPolicy: Equatable {
    static let minimumHorizontalWidth: CGFloat = 900
    static let columnSpacing: CGFloat = 14
    static let leadingWeight: CGFloat = 1
    static let trailingWeight: CGFloat = 1.05
    static let minimumStackedPaneHeight: CGFloat = 280
    static let minimumHorizontalHeight: CGFloat = 398

    func mode(for availableWidth: CGFloat) -> IndexFileWorkbenchLayoutMode {
        availableWidth >= Self.minimumHorizontalWidth ? .horizontal : .stacked
    }

    func columnWidths(for availableWidth: CGFloat) -> IndexFileWorkbenchColumnWidths? {
        guard mode(for: availableWidth) == .horizontal else { return nil }

        let distributableWidth = max(0, availableWidth - Self.columnSpacing)
        let totalWeight = Self.leadingWeight + Self.trailingWeight
        let leading = distributableWidth * Self.leadingWeight / totalWeight
        return IndexFileWorkbenchColumnWidths(
            leading: leading,
            trailing: distributableWidth - leading
        )
    }
}
