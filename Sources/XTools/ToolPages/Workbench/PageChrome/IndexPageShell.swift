import AppKit
import SwiftUI

// MARK: - IndexPageArrivalScrollerSuppressor

/// Hides the outer page scroll indicators while a freshly switched page
/// settles. Applying the toolbar safe-area inset to a brand-new ScrollView
/// makes AppKit perform an animated correction scroll that explicitly flashes
/// the overlay scroller knobs (`_scrollTo:animateScroll:flashScrollerKnobs:`),
/// which reads as a one-off scrollbar flash on the right edge of every tool
/// switch. The indicators return once the inset scroll has finished; scrolling
/// afterwards shows them as usual.
private struct IndexPageArrivalScrollerSuppressor: ViewModifier {
    let title: String
    @State private var hasSettled = false

    /// The inset correction rides the page-arrival animation (~0.2s); keep the
    /// indicators hidden slightly past it.
    private static let settleDelay: TimeInterval = ToolMotion.Duration.arrival + 0.15

    func body(content: Content) -> some View {
        content
            .scrollIndicators(hasSettled ? .visible : .hidden)
            .task(id: title) {
                guard !hasSettled else { return }
                try? await Task.sleep(nanoseconds: UInt64(Self.settleDelay * 1_000_000_000))
                hasSettled = true
            }
    }
}

// MARK: - IndexPage

/// 工具页的布局范式及布局安全护栏。
///
/// ## 默认值安全规则
/// 默认值 `fill` 确保未点名页面不会被自动迁移到外层滚动模型。
///
/// ## 布局安全合同
/// 受保护：固定输入工作区、复制型转换工作区、查询列表工作区。
/// 不通过 spacer、空白占位、额外容器或整体下移制造外层滚动效果。
enum IndexPageLayout: Equatable {
    /// 固定铺满视口、整页不滚动。默认值。未点名页面不会被自动迁移。
    case fill
    /// 由外层 ScrollView 承载整页滚动。须显式选择。
    case scroll

    var scrollsExternally: Bool {
        switch self {
        case .fill: return false
        case .scroll: return true
        }
    }
}

enum IndexPageChrome: Equatable {
    case standard
    case compactWorkspace
    /// Dashboard chrome shares the tool-page title rail, while using a tighter
    /// top rhythm so the first action stays visible above the fold.
    case dashboard

    var horizontalPadding: CGFloat {
        switch self {
        case .standard, .compactWorkspace: return 30
        case .dashboard: return 30
        }
    }

    /// Space between the native unified toolbar bottom and the page title.
    /// Asymmetric from bottom padding so identity sits tighter under chrome
    /// without pinching the workbench against the window edge.
    var topPadding: CGFloat {
        switch self {
        case .standard: return 6
        case .compactWorkspace: return 5
        case .dashboard: return 2
        }
    }

    var bottomPadding: CGFloat {
        switch self {
        case .standard: return ToolMetrics.Spacing.panelSection
        case .compactWorkspace: return 8
        case .dashboard: return ToolMetrics.Spacing.page
        }
    }

    var sectionSpacing: CGFloat {
        switch self {
        case .standard: return 10
        case .compactWorkspace: return 9
        case .dashboard: return ToolMetrics.Spacing.lg
        }
    }

    var headerBottomPadding: CGFloat {
        switch self {
        case .standard: return 5
        case .compactWorkspace: return 4
        case .dashboard: return 7
        }
    }

    /// Small identity rail keeps the page title anchored without adding a
    /// second toolbar or competing with the native window chrome.
    var headerLeadingPadding: CGFloat { ToolMetrics.Spacing.sm }
    var headerRailWidth: CGFloat { ToolMetrics.Spacing.xs / 2 }
}

/// v3 continuity flight: anchor of the page identity rail. RootView resolves
/// it as the landing point when a tool is launched from the command palette.
struct PageTitleRailAnchorKey: PreferenceKey {
    static let defaultValue: Anchor<CGRect>? = nil

    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = nextValue() ?? value
    }
}

/// Shared identity rail used by tool pages and the personal dashboard.
/// Keeping this header separate lets dashboard content own its single
/// ScrollView without recreating a second page shell or toolbar.
struct IndexPageHeader<Accessory: View>: View {
    let title: String
    let subtitle: String
    let chrome: IndexPageChrome
    private let accessory: Accessory
    private let hasAccessory: Bool

    init(
        _ title: String,
        subtitle: String,
        chrome: IndexPageChrome = .standard,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.title = title
        self.subtitle = subtitle
        self.chrome = chrome
        self.accessory = accessory()
        self.hasAccessory = true
    }

    init(_ title: String, subtitle: String, chrome: IndexPageChrome = .standard)
    where Accessory == EmptyView {
        self.title = title
        self.subtitle = subtitle
        self.chrome = chrome
        self.accessory = EmptyView()
        self.hasAccessory = false
    }

    private var headerText: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(ToolTypography.pageTitle)
                .foregroundStyle(ToolTheme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.9)
            Text(subtitle)
                .font(ToolTypography.pageSubtitle)
                .foregroundStyle(ToolTheme.textSecondary)
                .lineSpacing(1)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 720, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, chrome.headerLeadingPadding)
        .anchorPreference(key: PageTitleRailAnchorKey.self, value: .bounds) { $0 }
        .overlay(alignment: .leading) {
            Capsule(style: .continuous)
                .fill(ToolTheme.accent)
                .frame(width: chrome.headerRailWidth)
                .padding(.vertical, ToolMetrics.Spacing.xs)
        }
    }

    var body: some View {
        Group {
            if hasAccessory {
                HStack(alignment: .top, spacing: ToolMetrics.Spacing.md) {
                    headerText
                    accessory.fixedSize(horizontal: true, vertical: true)
                }
            } else {
                headerText
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(.bottom, chrome.headerBottomPadding)
        .overlay(alignment: .bottom) {
            Rectangle().fill(ToolTheme.border).frame(height: 0.5)
        }
    }
}

struct IndexPage<Content: View, HeaderAccessory: View>: View {
    let title: String
    let subtitle: String
    var layout: IndexPageLayout = .fill
    var chrome: IndexPageChrome = .standard
    private let headerAccessory: HeaderAccessory
    private let hasHeaderAccessory: Bool
    private let content: Content

    private init(
        _ title: String,
        subtitle: String,
        layout: IndexPageLayout,
        chrome: IndexPageChrome,
        headerAccessory: HeaderAccessory,
        hasHeaderAccessory: Bool,
        content: Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.layout = layout
        self.chrome = chrome
        self.headerAccessory = headerAccessory
        self.hasHeaderAccessory = hasHeaderAccessory
        self.content = content
    }

    init(
        _ title: String,
        subtitle: String,
        layout: IndexPageLayout = .fill,
        chrome: IndexPageChrome = .standard,
        @ViewBuilder content: () -> Content
    ) where HeaderAccessory == EmptyView {
        self.init(
            title,
            subtitle: subtitle,
            layout: layout,
            chrome: chrome,
            headerAccessory: EmptyView(),
            hasHeaderAccessory: false,
            content: content()
        )
    }

    init(
        _ title: String,
        subtitle: String,
        layout: IndexPageLayout = .fill,
        chrome: IndexPageChrome = .standard,
        @ViewBuilder headerAccessory: () -> HeaderAccessory,
        @ViewBuilder content: () -> Content
    ) {
        self.init(
            title,
            subtitle: subtitle,
            layout: layout,
            chrome: chrome,
            headerAccessory: headerAccessory(),
            hasHeaderAccessory: true,
            content: content()
        )
    }

    init(
        _ title: String,
        subtitle: String,
        workspaceSemantic: IndexWorkspaceSemantic,
        @ViewBuilder content: () -> Content
    ) where HeaderAccessory == EmptyView {
        let shell = workspaceSemantic.resolvedWorkspace.pageShell
        self.init(
            title,
            subtitle: subtitle,
            layout: shell.layout,
            chrome: shell.chrome,
            content: content
        )
    }

    init(
        _ title: String,
        subtitle: String,
        workspaceSemantic: IndexWorkspaceSemantic,
        @ViewBuilder headerAccessory: () -> HeaderAccessory,
        @ViewBuilder content: () -> Content
    ) {
        let shell = workspaceSemantic.resolvedWorkspace.pageShell
        self.init(
            title,
            subtitle: subtitle,
            layout: shell.layout,
            chrome: shell.chrome,
            headerAccessory: headerAccessory,
            content: content
        )
    }

    @ViewBuilder
    private var header: some View {
        if hasHeaderAccessory {
            IndexPageHeader(title, subtitle: subtitle, chrome: chrome) { headerAccessory }
        } else {
            IndexPageHeader(title, subtitle: subtitle, chrome: chrome)
        }
    }

    private var framedHeader: some View { header }

    var body: some View {
        GeometryReader { proxy in
            Group {
                switch layout {
                case .fill:
                    // 无外层 ScrollView：标题固定，content 里声明 maxHeight:.infinity
                    // 的主面板吃掉剩余高度。SwiftUI 实测剩余空间，不再用 chrome 估算。
                    VStack(alignment: .leading, spacing: chrome.sectionSpacing) {
                        framedHeader
                        content
                    }
                    .padding(.horizontal, chrome.horizontalPadding)
                    .padding(.top, chrome.topPadding)
                    .padding(.bottom, chrome.bottomPadding)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                case .scroll:
                    ScrollView {
                        VStack(alignment: .leading, spacing: chrome.sectionSpacing) {
                            framedHeader
                            content
                        }
                        .padding(.horizontal, chrome.horizontalPadding)
                        .padding(.top, chrome.topPadding)
                        .padding(.bottom, chrome.bottomPadding)
                        .frame(maxWidth: .infinity, minHeight: proxy.size.height, alignment: .topLeading)
                    }
                    .modifier(IndexPageArrivalScrollerSuppressor(title: title))
                    // v3 header-rhythm unification: the window safe area already
                    // excludes the unified toolbar band (fill-layout pages never
                    // reserved it), so scroll pages no longer add a second 52pt
                    // inset — every page's title rail now starts at the same
                    // distance below the toolbar. Scrolled content passes under
                    // the translucent toolbar, the standard macOS behavior.
                }
            }
            // 视口高仍下发：.scroll 对比页（TextDiff/JSONDiff）的 split 高度还要用。
            .environment(\.pageAvailableHeight, proxy.size.height)
            .background(ToolTheme.workspaceBackground)
        }
    }
}

// MARK: - IndexPanel

/// Single-density Clay Panel metrics (Arc/Craft proportions): a quiet 12.5pt
/// medium label, a compact 38pt header, and a generously rounded container.
private enum IndexPanelMetrics {
    static let headerHeight: CGFloat = 38
    static let headerHorizontalPadding: CGFloat = ToolMetrics.Spacing.panelInset
    static let contentPadding: CGFloat = ToolMetrics.Spacing.panelInset
    static var cornerRadius: CGFloat { ToolMetrics.CornerRadius.panel }
}

/// Panel container with header and optional accessory.
struct IndexPanel<Content: View, Accessory: View>: View {
    let title: String
    var fillsHeight = false
    var reservesDiagnosticStatusSlot = true
    /// Optional terminal-stream tag (e.g. `STDIN` / `STDOUT`) shown as a soft
    /// accent capsule before the title. Only set on true I/O panels — most
    /// panels leave it nil (SPEC §7.5: labels only on I/O pairs).
    var terminalTag: String? = nil
    var customContentInsets: EdgeInsets? = nil
    @State private var workspaceDiagnostic: IndexWorkspaceDiagnosticPayload?
    @State private var diagnosticPresentation = IndexWorkspaceDiagnosticPresentationState()
    @Environment(\.toolToastCenter) private var toastCenter
    private let accessory: Accessory
    private let content: Content

    init(
        _ title: String,
        @ViewBuilder accessory: () -> Accessory,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.accessory = accessory()
        self.content = content()
    }

    func verticallyFilling() -> IndexPanel {
        var copy = self
        copy.fillsHeight = true
        return copy
    }

    /// Hide the leading diagnostic reserve for panels whose surfaces never
    /// publish panel diagnostics.
    func withoutDiagnosticStatusSlot() -> IndexPanel {
        var copy = self
        copy.reservesDiagnosticStatusSlot = false
        return copy
    }

    /// Attach a terminal-stream tag (`STDIN` / `STDOUT`) to the panel head.
    func terminal(_ tag: String) -> IndexPanel {
        var copy = self
        copy.terminalTag = tag
        return copy
    }

    /// Custom content insets overriding the default panel padding.
    func contentInsets(_ insets: EdgeInsets) -> IndexPanel {
        var copy = self
        copy.customContentInsets = insets
        return copy
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                if let terminalTag {
                    IndexBadge(terminalTag, tone: .accent, isCapsule: true)
                        .layoutPriority(3)
                }
                panelTitle
                Spacer(minLength: 8)
                // Keep the trailing diagnostic slot stable for every panel
                // that can publish a workspace diagnostic. The payload is
                // optional inside the slot, so nil → error/success never
                // moves the title or accessory cluster horizontally.
                if reservesDiagnosticStatusSlot {
                    IndexPanelWorkspaceDiagnostic(payload: workspaceDiagnostic)
                }
                accessory
                    .layoutPriority(2)
            }
            .frame(height: IndexPanelMetrics.headerHeight)
            .padding(.horizontal, IndexPanelMetrics.headerHorizontalPadding)
            .overlay(alignment: .bottom) {
                Rectangle().fill(ToolTheme.border).frame(height: 0.5)
            }

            content
                .padding(customContentInsets ?? EdgeInsets(
                    top: IndexPanelMetrics.contentPadding,
                    leading: IndexPanelMetrics.contentPadding,
                    bottom: IndexPanelMetrics.contentPadding,
                    trailing: IndexPanelMetrics.contentPadding
                ))
                .frame(maxWidth: .infinity, maxHeight: fillsHeight ? .infinity : nil, alignment: .topLeading)
        }
        .frame(maxHeight: fillsHeight ? .infinity : nil, alignment: .top)
        .background(
            ToolTheme.panelBackground,
            in: RoundedRectangle(cornerRadius: IndexPanelMetrics.cornerRadius, style: .continuous)
        )
        .modifier(
            IndexPanelOutline(
                cornerRadius: IndexPanelMetrics.cornerRadius,
                diagnostic: workspaceDiagnostic
            )
        )
        .toolShadow(ToolTheme.Shadow.panel)
        .onPreferenceChange(IndexWorkspaceDiagnosticPreferenceKey.self) { diagnostic in
            if let announcement = diagnosticPresentation.update(to: diagnostic) {
                toastCenter?.show(announcement.text, tone: announcement.tone)
            }
            workspaceDiagnostic = diagnostic
        }
    }

    private var panelTitle: some View {
        Text(title)
            .font(ToolTypography.panelTitle)
            .foregroundStyle(ToolTheme.textSecondary)
            .lineLimit(1)
            .truncationMode(.tail)
            .layoutPriority(1)
    }
}

extension IndexPanel where Accessory == EmptyView {
    init(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) {
        self.init(
            title,
            accessory: { EmptyView() },
            content: content
        )
    }

    /// Panel that declares its fill behavior at the call site, for pages whose
    /// single upload panel owns the empty state (fills) but yields height to a
    /// result panel once a source exists (natural height). Equivalent to
    /// `.verticallyFilling()` on a conditionally rendered panel, without
    /// duplicating the panel branch.
    init(
        _ title: String,
        fillsHeight: Bool,
        @ViewBuilder content: () -> Content
    ) {
        self.init(
            title,
            accessory: { EmptyView() },
            content: content
        )
        self.fillsHeight = fillsHeight
    }
}

extension IndexPanel {
    init(
        _ title: String,
        @ViewBuilder content: () -> Content,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.init(
            title,
            accessory: accessory,
            content: content
        )
    }
}

// MARK: - IndexActionBar

/// Responsive action bar that stacks vertically on narrow screens
struct IndexActionBar<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 9) { content }
            VStack(alignment: .leading, spacing: 9) { content }
        }
        .padding(.horizontal, 2)
        .padding(.vertical, 1)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - IndexWorkbenchControlBar

/// Responsive control area for text conversion editor workbenches.
///
/// Callers provide explicit control and primary-action slots so horizontal
/// spacer behavior stays inside this component and is never reused as vertical
/// fallback layout.
struct IndexWorkbenchControlBar<Controls: View, CompactControls: View, PrimaryAction: View>: View {
    private let controls: Controls
    private let compactControls: CompactControls
    private let primaryAction: PrimaryAction

    init(
        @ViewBuilder controls: () -> Controls,
        @ViewBuilder compactControls: () -> CompactControls,
        @ViewBuilder primaryAction: () -> PrimaryAction
    ) {
        self.controls = controls()
        self.compactControls = compactControls()
        self.primaryAction = primaryAction()
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 9) {
                controls
                Spacer(minLength: 9)
                primaryAction
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(alignment: .center, spacing: 9) {
                compactControls
                Spacer(minLength: 9)
                primaryAction
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 9) {
                compactControls
                primaryAction
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension IndexWorkbenchControlBar where CompactControls == Controls {
    init(
        @ViewBuilder controls: () -> Controls,
        @ViewBuilder primaryAction: () -> PrimaryAction
    ) {
        self.init(
            controls: controls,
            compactControls: controls,
            primaryAction: primaryAction
        )
    }
}

extension IndexWorkbenchControlBar where PrimaryAction == EmptyView {
    init(
        @ViewBuilder controls: () -> Controls,
        @ViewBuilder compactControls: () -> CompactControls
    ) {
        self.init(
            controls: controls,
            compactControls: compactControls,
            primaryAction: { EmptyView() }
        )
    }
}

// MARK: - Workspace semantic surfaces

/// Applies a glossary-named workspace semantic to a text input surface.
/// Page-local custom workspaces can keep their own panel/header composition
/// while letting the shared semantic layer own growth and wrapping behavior.


/// Panel outline: light mode separates via the surface ladder (no hairline);
/// dark mode keeps a 0.5pt hairline; diagnostics always tint the outline.
private struct IndexPanelOutline: ViewModifier {
    let cornerRadius: CGFloat
    let diagnostic: IndexWorkspaceDiagnosticPayload?
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content.overlay {
            if let diagnostic {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(diagnostic.tone.tint.opacity(0.55), lineWidth: 1)
            } else if colorScheme == .dark {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(ToolTheme.border, lineWidth: 0.5)
            }
        }
    }
}
