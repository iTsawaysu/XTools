import SwiftUI
import XToolsDesign

// MARK: - IndexPageArrivalScrollerSuppressor

/// Hides the outer page scroll indicators while a freshly switched page
/// settles. Applying the toolbar safe-area inset to a brand-new ScrollView
/// makes AppKit perform an animated correction scroll that explicitly flashes
/// the overlay scroller knobs (`_scrollTo:animateScroll:flashScrollerKnobs:`),
/// which reads as a one-off scrollbar flash on the right edge of every tool
/// switch. The indicators return to `.automatic` once the arrival has finished;
/// scrolling afterwards shows them as usual according to system conventions.
struct IndexPageArrivalScrollerSuppressor: ViewModifier {
    let title: String
    @Environment(\.toolPageEntryGeneration) private var entryGeneration: Int
    @State private var settledGeneration: Int = 0

    /// The inset correction rides the page-arrival animation (~0.2s); keep the
    /// indicators hidden slightly past it.
    static let settleDelay: TimeInterval = ToolMotion.Duration.arrival + 0.15

    nonisolated static func indicatorVisibility(entryGeneration: Int, settledGeneration: Int) -> ScrollIndicatorVisibility {
        guard entryGeneration > 0, settledGeneration == entryGeneration else {
            return .hidden
        }
        return .automatic
    }

    func body(content: Content) -> some View {
        content
            .scrollIndicators(Self.indicatorVisibility(entryGeneration: entryGeneration, settledGeneration: settledGeneration))
            .task(id: "\(title)\u{1}\(entryGeneration)") {
                guard entryGeneration > 0 else {
                    settledGeneration = 0
                    return
                }
                settledGeneration = 0
                try? await Task.sleep(nanoseconds: UInt64(Self.settleDelay * 1_000_000_000))
                guard !Task.isCancelled else { return }
                settledGeneration = entryGeneration
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
        case .standard, .compactWorkspace, .dashboard: return 30
        }
    }

    /// Space between the native unified toolbar bottom and the page title.
    /// Asymmetric from bottom padding so identity sits tighter under chrome
    /// without pinching the workbench against the window edge.
    ///
    /// `compactWorkspace` is kept as a call-site semantic, but its chrome now
    /// resolves to the same values as `.standard`: the old 5/8/9/4 variants
    /// shifted every compact paper 7pt upward, making paper heads disagree
    /// across pages (audit H-02 / rules §2.2).
    var topPadding: CGFloat {
        switch self {
        case .standard, .compactWorkspace: return 6
        case .dashboard: return 2
        }
    }

    var bottomPadding: CGFloat {
        switch self {
        case .standard, .compactWorkspace: return ToolMetrics.Spacing.panelSection
        case .dashboard: return ToolMetrics.Spacing.xxxl
        }
    }

    var sectionSpacing: CGFloat {
        switch self {
        case .standard, .compactWorkspace: return ToolMetrics.Spacing.panelSection
        case .dashboard: return ToolMetrics.Spacing.lg
        }
    }

    var headerBottomPadding: CGFloat {
        switch self {
        case .standard, .compactWorkspace: return 5
        case .dashboard: return 7
        }
    }

    /// Small identity rail keeps the page title anchored without adding a
    /// second toolbar or competing with the native window chrome.
    var headerLeadingPadding: CGFloat { ToolMetrics.Spacing.sm }
    var headerRailWidth: CGFloat { ToolMetrics.Spacing.xs / 2 }
}

/// Page-header composition rule, kept separate from the view so the threshold
/// can be exercised without hosting SwiftUI.
enum IndexPageHeaderLayout {
    /// Below this content width the accessory moves under the title: the title
    /// keeps its reading measure instead of being squeezed by the control.
    static let inlineAccessoryMinimumWidth: CGFloat = 760

    /// A zero width means the measurement has not landed yet; keep the inline
    /// arrangement for the first frame so wide windows do not flash a stack.
    static func stacksAccessory(forContentWidth width: CGFloat) -> Bool {
        width > 0 && width < inlineAccessoryMinimumWidth
    }
}

private struct IndexPageHeaderWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// Shared identity rail used by tool pages and the personal dashboard.
/// Keeping this header separate lets dashboard content own its single
/// ScrollView without recreating a second page shell or toolbar.
struct IndexPageHeader<Accessory: View>: View {
    let title: String
    let subtitle: String
    let chrome: IndexPageChrome
    let contentWidth: CGFloat
    private let accessory: Accessory
    private let hasAccessory: Bool

    init(
        _ title: String,
        subtitle: String,
        chrome: IndexPageChrome = .standard,
        contentWidth: CGFloat = 0,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.title = title
        self.subtitle = subtitle
        self.chrome = chrome
        self.contentWidth = contentWidth
        self.accessory = accessory()
        self.hasAccessory = true
    }

    init(
        _ title: String,
        subtitle: String,
        chrome: IndexPageChrome = .standard,
        contentWidth: CGFloat = 0
    ) where Accessory == EmptyView {
        self.title = title
        self.subtitle = subtitle
        self.chrome = chrome
        self.contentWidth = contentWidth
        self.accessory = EmptyView()
        self.hasAccessory = false
    }

    private var headerText: some View {
        IndexPageHeaderText(
            title: title,
            subtitle: subtitle,
            leadingPadding: chrome.headerLeadingPadding,
            railWidth: chrome.headerRailWidth
        )
        // 阶段③ 决策 9：逐字入场退役后页头不再以「标题 + 进入代际」重建
        // 身份——停靠回访直接呈现已到达的页头，进场表现交给页面级
        // crossfade；新页面首次挂载时由 IndexPageHeaderText 播一次淡入。
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    var body: some View {
        Group {
            if hasAccessory {
                if IndexPageHeaderLayout.stacksAccessory(forContentWidth: contentWidth) {
                    VStack(alignment: .leading, spacing: ToolMetrics.Spacing.sm) {
                        headerText
                        accessory.fixedSize(horizontal: true, vertical: true)
                    }
                } else {
                    HStack(alignment: .top, spacing: ToolMetrics.Spacing.md) {
                        headerText
                        accessory.fixedSize(horizontal: true, vertical: true)
                    }
                }
            } else {
                headerText
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(.bottom, chrome.headerBottomPadding)
        .overlay(alignment: .bottom) {
            Rectangle().fill(ToolTheme.border).frame(height: ToolMetrics.Spacing.hairline)
        }
    }
}

/// v3 页头到入场效（阶段③ 决策 9 收敛）：标题/副标题/accent 竖轨整块一次性
/// 0.18s 纯 opacity 淡入。原「逐字弹簧 + 副标题延迟跟随 + 轨生长」的 0.48s
/// 编排已退役——它与停靠保活模型相抵（每次切换重播、与全库 ≤0.35 节奏
/// 割裂）。仅页面首次挂载播放一次；Reduce Motion 直接呈现最终布局。
private struct IndexPageHeaderText: View {
    let title: String
    let subtitle: String
    let leadingPadding: CGFloat
    let railWidth: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var arrived = false

    var body: some View {
        VStack(alignment: .leading, spacing: ToolMetrics.Spacing.xxs) {
            Text(title)
                .font(ToolTypography.pageTitle)
                .foregroundStyle(ToolTheme.textPrimary)
                .lineLimit(1)
                .accessibilityAddTraits(.isHeader)
            Text(subtitle)
                .font(ToolTypography.pageSubtitle)
                .foregroundStyle(ToolTheme.textSecondary)
                .lineSpacing(1)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 720, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, leadingPadding)
        .overlay(alignment: .leading) {
            Capsule(style: .continuous)
                .fill(ToolTheme.accent)
                .frame(width: railWidth)
                .padding(.vertical, ToolMetrics.Spacing.xs)
        }
        // 整块纯 opacity（无位移/缩放）：accent 轨与文字同一淡入，
        // 不再单独走 settle 生长弧。
        .opacity(arrived ? 1 : 0)
        .animation(
            ToolMotion.animation(ToolMotion.Preset.contentCrossfade, reduceMotion: reduceMotion),
            value: arrived
        )
        .onAppear { arrived = true }
    }
}

struct IndexPage<Content: View, HeaderAccessory: View>: View {
    let title: String
    let subtitle: String
    var layout: IndexPageLayout = .fill
    var chrome: IndexPageChrome = .standard
    // 原始 layout 构造保留铺满视口的行为；语义构造按工作区类型选择。
    private var fillsScrollViewport = true
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
        fillsScrollViewport = workspaceSemantic == .imagePreviewStage
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
        fillsScrollViewport = workspaceSemantic == .imagePreviewStage
    }

    private func framedHeader(availableWidth: CGFloat) -> some View {
        let contentWidth = max(0, availableWidth - chrome.horizontalPadding * 2)
        return Group {
            if hasHeaderAccessory {
                IndexPageHeader(
                    title,
                    subtitle: subtitle,
                    chrome: chrome,
                    contentWidth: contentWidth
                ) { headerAccessory }
            } else {
                IndexPageHeader(
                    title,
                    subtitle: subtitle,
                    chrome: chrome,
                    contentWidth: contentWidth
                )
            }
        }
    }

    var body: some View {
        GeometryReader { proxy in
            Group {
                switch layout {
                case .fill:
                    // 无外层 ScrollView：标题固定，content 里声明 maxHeight:.infinity
                    // 的主面板吃掉剩余高度。SwiftUI 实测剩余空间，不再用 chrome 估算。
                    VStack(alignment: .leading, spacing: chrome.sectionSpacing) {
                        framedHeader(availableWidth: proxy.size.width)
                        content
                    }
                    .padding(.horizontal, chrome.horizontalPadding)
                    .padding(.top, chrome.topPadding)
                    .padding(.bottom, chrome.bottomPadding)
                    .frame(maxWidth: ToolMetrics.Workbench.paperMaxWidth, alignment: .topLeading)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                case .scroll:
                    ScrollView {
                        VStack(alignment: .leading, spacing: chrome.sectionSpacing) {
                            framedHeader(availableWidth: proxy.size.width)
                            content
                        }
                        .padding(.horizontal, chrome.horizontalPadding)
                        .padding(.top, chrome.topPadding)
                        .padding(.bottom, chrome.bottomPadding)
                        .frame(maxWidth: ToolMetrics.Workbench.paperMaxWidth, alignment: .topLeading)
                        .frame(
                            maxWidth: .infinity,
                            minHeight: fillsScrollViewport ? proxy.size.height : nil,
                            alignment: .top
                        )
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
                    .strokeBorder(diagnostic.tone.borderTint, lineWidth: 1)
            } else if colorScheme == .dark {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(ToolTheme.border, lineWidth: 0.5)
            }
        }
    }
}
