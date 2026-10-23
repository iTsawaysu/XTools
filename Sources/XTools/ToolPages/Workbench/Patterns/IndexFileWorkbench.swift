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

    /// Optional paper head. Workflows whose parameters do not fit a pane head
    /// (text encryption: mode + algorithm + secret + run) put them here so the
    /// paper still starts at the same rail as every other tool instead of
    /// growing a separate band above it (audit S-09).
    private let head: AnyView?

    private let leading: Leading
    private let trailing: Trailing

    @State private var workspaceDiagnostic: IndexWorkspaceDiagnosticPayload?
    @State private var diagnosticPresentation = IndexWorkspaceDiagnosticPresentationState()
    @Environment(\.toolToastCenter) private var toastCenter

    /// Layout contract. File workloads use the 1 : 1.05 / 900pt split; the
    /// pair family keeps its equal-column / 720pt contract. Both share this
    /// paper, its diagnostic slot and the pane chrome.
    enum SplitMode: Equatable {
        case file
        case pair(threshold: CGFloat)
    }

    private let splitMode: SplitMode
    private let layoutPolicy: IndexFileWorkbenchLayoutPolicy

    init(
        diagnostic: String?,
        splitMode: SplitMode = .file,
        @ViewBuilder head: () -> some View,
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.diagnostic = diagnostic
        self.splitMode = splitMode
        self.layoutPolicy = IndexFileWorkbenchLayoutPolicy()
        self.head = AnyView(head())
        self.leading = leading()
        self.trailing = trailing()
    }

    init(
        diagnostic: String?,
        splitMode: SplitMode = .file,
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.diagnostic = diagnostic
        self.splitMode = splitMode
        self.layoutPolicy = IndexFileWorkbenchLayoutPolicy()
        self.head = nil
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

            if let head {
                head
                    .padding(.horizontal, ToolMetrics.Spacing.panelInset)
                    .padding(.vertical, ToolMetrics.Spacing.xs)
                    .frame(maxWidth: .infinity, minHeight: ToolMetrics.Workbench.paperHeadHeight, alignment: .leading)
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(ToolTheme.border).frame(height: ToolMetrics.Spacing.hairline)
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
                proxy.size.height - IndexWorkbenchPaneMetrics.inset
            )
            let pairPolicy: IndexPairWorkbenchLayoutPolicy? = {
                if case let .pair(threshold) = splitMode {
                    return IndexPairWorkbenchLayoutPolicy(threshold: threshold)
                }
                return nil
            }()

            if let pairPolicy {
                pairContent(policy: pairPolicy, proxy: proxy)
            } else if let widths = layoutPolicy.columnWidths(for: proxy.size.width) {
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
                .padding(.horizontal, IndexWorkbenchPaneMetrics.inset)
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
                    .padding(.horizontal, IndexWorkbenchPaneMetrics.inset)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .scrollIndicators(.automatic)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func pairContent(
        policy: IndexPairWorkbenchLayoutPolicy,
        proxy: GeometryProxy
    ) -> some View {
        let paneHeight = max(
            IndexPairWorkbenchLayoutPolicy.minimumPaneHeight,
            proxy.size.height - IndexWorkbenchPaneMetrics.inset
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
            .padding(.horizontal, IndexWorkbenchPaneMetrics.inset)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            VStack(spacing: IndexPairWorkbenchLayoutPolicy.columnSpacing) {
                leading
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                trailing
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .padding(.horizontal, IndexWorkbenchPaneMetrics.inset)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
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
    private let terminalTag: String?
    private let stretchContent: Bool
    private let accessory: Accessory
    private let content: Content

    init(
        title: String,
        footer: IndexWorkbenchFooter? = nil,
        terminalTag: String? = nil,
        stretchContent: Bool = true,
        @ViewBuilder accessory: () -> Accessory,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.footer = footer
        self.terminalTag = terminalTag
        self.stretchContent = stretchContent
        self.accessory = accessory()
        self.content = content()
    }

    /// Convenience init for bands without header controls (parameters,
    /// single-surface strips): the head keeps title-only spacing.
    init(
        title: String,
        footer: IndexWorkbenchFooter? = nil,
        terminalTag: String? = nil,
        stretchContent: Bool = true,
        @ViewBuilder content: () -> Content
    ) where Accessory == EmptyView {
        self.init(
            title: title,
            footer: footer,
            terminalTag: terminalTag,
            stretchContent: stretchContent,
            accessory: { EmptyView() },
            content: content
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            IndexWorkbenchHeader(title: title, terminalTag: terminalTag) { accessory }

            content
                .frame(
                    maxWidth: .infinity,
                    maxHeight: stretchContent ? .infinity : nil,
                    alignment: .topLeading
                )
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
    private let terminalTag: String?
    private let accessory: Accessory

    init(title: String, terminalTag: String? = nil, @ViewBuilder accessory: () -> Accessory) {
        self.title = title
        self.terminalTag = terminalTag
        self.accessory = accessory()
    }

    var body: some View {
        HStack(spacing: ToolMetrics.Spacing.sm) {
            if let terminalTag {
                IndexBadge(terminalTag, tone: .accent, isCapsule: true)
                    .layoutPriority(3)
            }

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

/// Equal-column split contract inherited from the regex page: at or above the
/// configured content width (720pt by default) the two panes share the row
/// through a 14pt gap and fill the residual height; below it they stack and
/// halve the band. Pure values so the contract tests can exercise the math.
struct IndexPairWorkbenchLayoutPolicy {
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

enum IndexPairWorkbenchLayoutMode: Equatable {
    case stacked
    case horizontal
}
