import AppKit
import SwiftUI

enum SidebarMetrics {
    /// Local brand band under the native unified toolbar. Kept as a content-area
    /// spacer (not fullSizeContentView overlay); slightly under 48pt so the
    /// brand + search slab reads as one header rather than a second titlebar.
    static let titlebarHeight: CGFloat = 40
    static let brandHorizontalPadding: CGFloat = 16
    static let searchHorizontalPadding: CGFloat = 12
    static let searchTopPadding: CGFloat = 0
    static let searchBottomPadding: CGFloat = 8
    static let disclosureGroupSpacing: CGFloat = 5
    static let expandedGroupBottomPadding: CGFloat = 4
    static let groupHeaderHeight: CGFloat = 30
    static let groupHeaderToItemsSpacing: CGFloat = 3
    static let expandedRowHeight: CGFloat = 32
    static let interRowSpacing: CGFloat = 1
    static let iconSize: CGFloat = 16
    static let toolRowHorizontalPadding: CGFloat = 9
    static let toolRowHierarchyIndent: CGFloat = 16
    static let rowCornerRadius: CGFloat = 7
    static let searchSurfaceHeight: CGFloat = 32
    static let searchContentSpacing: CGFloat = 8
    static let searchLeadingPadding: CGFloat = 10
    static let searchTrailingPadding: CGFloat = 4
    static let searchIconWidth: CGFloat = 12
    static let searchClearButtonSize: CGFloat = 24
    static let searchLeadingContentInset: CGFloat = searchLeadingPadding + searchIconWidth + searchContentSpacing
    static let searchTrailingContentInset: CGFloat = searchTrailingPadding + searchClearButtonSize + searchContentSpacing
}

struct SidebarView: View {
    static let idealWidth: CGFloat = 220

    let projection: ToolNavigationProjection
    let selectedToolID: ToolID?
    let favoriteOrder: [ToolID]
    @Binding var searchText: String
    let searchFocusToken: Int
    let onSelectTool: (ToolID) -> Void
    let onOpenDashboard: () -> Void
    let onToggleFavorite: (ToolID) -> Void
    let isSectionExpanded: (ToolNavigationSection) -> Bool
    let onToggleSection: (ToolNavigationSection) -> Void
    var onToggleSectionExclusive: ((ToolNavigationSection) -> Void)? = nil
    let onToggleTheme: () -> Void
    let onPreferences: () -> Void
    let themeTitle: String
    let themeIcon: String

    @State private var isSearchFocused = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    private var isSearchActive: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            sidebarHeader
            dashboardEntry
            expandedToolList
            Spacer(minLength: 0)
            sidebarFooter
        }
        .frame(width: Self.idealWidth, alignment: .top)
        .frame(maxHeight: .infinity, alignment: .top)
        .toolSurface(.sidebar, fallback: ToolTheme.sidebarBackground, in: Rectangle())
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(ToolTheme.border)
                .frame(width: 0.5)
        }
    }

    private var dashboardEntry: some View {
        Button(action: onOpenDashboard) {
            HStack(spacing: 9) {
                Image(systemName: "square.grid.3x3")
                    .font(.system(size: ToolMetrics.IconSize.small, weight: .semibold))
                    .frame(width: SidebarMetrics.iconSize)
                Text("工作台")
                    .font(ToolTypography.label)
                Spacer(minLength: 0)
                Text("⌘0")
                    .font(ToolTypography.caption)
                    .foregroundStyle(ToolTheme.textTertiary)
            }
            .foregroundStyle(selectedToolID == nil ? ToolTheme.accent : ToolTheme.textSecondary)
            .padding(.horizontal, SidebarMetrics.toolRowHorizontalPadding)
            .frame(height: SidebarMetrics.expandedRowHeight)
            .background(
                selectedToolID == nil ? ToolTheme.accent.opacity(0.12) : Color.clear,
                in: RoundedRectangle(cornerRadius: SidebarMetrics.rowCornerRadius, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .toolInteractionFeedback()
        .accessibilityIdentifier("sidebar.dashboard")
        .accessibilityLabel("工作台")
        .help("打开个人工作台")
        .padding(.horizontal, SidebarMetrics.toolRowHorizontalPadding)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    private var sidebarHeader: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Local content-area brand band under the native unified toolbar (no
            // fullSizeContentView). Compact height + zero gap into search so the
            // header reads as one unit instead of a second titlebar slab.
            HStack(spacing: 8) {
                BrandMark()

                (Text("~/")
                    .foregroundColor(ToolTheme.textTertiary)
                 + Text("devtools")
                    .foregroundColor(ToolTheme.accent))
                    .font(ToolTypography.brandMark)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, SidebarMetrics.brandHorizontalPadding)
            .frame(height: SidebarMetrics.titlebarHeight, alignment: .center)

            searchField
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(ToolTheme.border)
                .frame(height: 0.5)
        }
    }

    private var searchField: some View {
        ZStack {
            SidebarSearchTextField(
                placeholder: "搜索工具…",
                text: $searchText,
                focusToken: searchFocusToken,
                contentInsets: IndexTextFieldContentInsets(
                    leading: SidebarMetrics.searchLeadingContentInset,
                    trailing: SidebarMetrics.searchTrailingContentInset
                ),
                onFocusChange: { isSearchFocused = $0 }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .help("输入关键词搜索工具")

            HStack(spacing: SidebarMetrics.searchContentSpacing) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(ToolTheme.textSecondary)
                    .font(.system(size: ToolMetrics.IconSize.small, weight: .medium))
                    .frame(width: SidebarMetrics.searchIconWidth)
                    .allowsHitTesting(false)

                Spacer(minLength: 0)

                ZStack {
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(ToolTheme.textSecondary)
                                .frame(
                                    width: SidebarMetrics.searchClearButtonSize,
                                    height: SidebarMetrics.searchClearButtonSize
                                )
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .toolInteractionFeedback()
                        .accessibilityIdentifier("sidebar.search.clear")
                        .help("清除搜索")
                        .accessibilityLabel("清除搜索")
                    }
                }
                .frame(
                    width: SidebarMetrics.searchClearButtonSize,
                    height: SidebarMetrics.searchClearButtonSize
                )
                .allowsHitTesting(!searchText.isEmpty)
                .toolAnimation(ToolMotion.Preset.controlFeedback, value: searchText.isEmpty)
            }
            .padding(.leading, SidebarMetrics.searchLeadingPadding)
            .padding(.trailing, SidebarMetrics.searchTrailingPadding)
        }
        .frame(height: SidebarMetrics.searchSurfaceHeight)
        .background(
            ToolTheme.editorBackground,
            in: RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.field, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.field, style: .continuous)
                .strokeBorder(isSearchFocused ? ToolTheme.accentBorder : ToolTheme.border, lineWidth: isSearchFocused ? 1 : 0.5)
        }
        .toolAnimation(ToolMotion.Preset.controlFeedback, value: isSearchFocused)
        .padding(.horizontal, SidebarMetrics.searchHorizontalPadding)
        .padding(.top, SidebarMetrics.searchTopPadding)
        .padding(.bottom, SidebarMetrics.searchBottomPadding)
    }

    private var expandedToolList: some View {
        SidebarNavigationList(configuration: SidebarNavigationListConfiguration(
            entries: sidebarEntries,
            selectedToolID: selectedToolID,
            selectedSection: projection.selectedSection,
            favoriteOrder: favoriteOrder,
            isSearchActive: isSearchActive,
            reduceMotion: reduceMotion,
            colorScheme: colorScheme,
            onSelectTool: onSelectTool,
            onToggleFavorite: onToggleFavorite,
            onToggleSection: { section in
                guard !isSearchActive else { return }
                onToggleSection(section)
            },
            onToggleSectionExclusive: { section in
                guard !isSearchActive else { return }
                onToggleSectionExclusive?(section)
            }
        ))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .layoutPriority(1)
        .overlay(alignment: .top) {
            if isSearchActive && projection.sidebarGroups.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: ToolMetrics.IconSize.medium, weight: .medium))
                        .foregroundStyle(ToolTheme.textTertiary)
                    Text("没有匹配的工具")
                        .font(ToolTypography.label)
                        .foregroundStyle(ToolTheme.textSecondary)
                }
                .frame(maxWidth: .infinity, minHeight: 72, alignment: .center)
                .background(
                    ToolTheme.panelBackground,
                    in: RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.field, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.field, style: .continuous)
                        .strokeBorder(ToolTheme.border, lineWidth: 0.5)
                }
                .padding(.horizontal, 12)
                .padding(.top, 12)
            }
        }
    }

    private var sidebarFooter: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(ToolTheme.border)
                .frame(height: 0.5)

            HStack(spacing: 6) {
                SidebarFooterButton(title: themeTitle, systemImage: themeIcon, action: onToggleTheme)
                SidebarFooterButton(title: "设置", systemImage: "gearshape", action: onPreferences)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
    }

    private var sidebarEntries: [SidebarNavigationEntry] {
        SidebarNavigationEntryProjection.entries(
            groups: projection.sidebarGroups,
            isSearchActive: isSearchActive,
            isSectionExpanded: { isSectionExpanded($0) }
        )
    }

}

private struct SidebarSearchTextField: NSViewRepresentable {
    let placeholder: String
    @Binding var text: String
    let focusToken: Int
    let contentInsets: IndexTextFieldContentInsets
    let onFocusChange: (Bool) -> Void

    private var configuration: AppKitSearchFieldConfiguration {
        AppKitSearchFieldConfiguration(
            placeholder: placeholder,
            font: .systemFont(ofSize: 12.5),
            contentInsets: contentInsets
        )
    }

    func makeCoordinator() -> AppKitSearchFieldCoordinator {
        AppKitSearchFieldCoordinator(
            text: $text,
            processedFocusToken: 0,
            focusRetryDelays: [0.05]
        )
    }

    func makeNSView(context: Context) -> NSTextField {
        let textField = AppKitSearchFieldLifecycle.makeTextField(
            configuration: configuration,
            text: $text,
            focusToken: focusToken,
            coordinator: context.coordinator,
            onFocusChange: onFocusChange
        )
        textField.setAccessibilityIdentifier("sidebar.search")
        return textField
    }

    func updateNSView(_ textField: NSTextField, context: Context) {
        textField.setAccessibilityIdentifier("sidebar.search")
        AppKitSearchFieldLifecycle.update(
            textField,
            configuration: configuration,
            text: $text,
            focusToken: focusToken,
            coordinator: context.coordinator,
            onFocusChange: onFocusChange
        )
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        nsView textField: NSTextField,
        context: Context
    ) -> CGSize? {
        guard let height = proposal.height else { return nil }
        return CGSize(width: proposal.width ?? textField.fittingSize.width, height: height)
    }

    static func dismantleNSView(
        _ textField: NSTextField,
        coordinator: AppKitSearchFieldCoordinator
    ) {
        coordinator.invalidateFocusRequests()
    }
}

struct SidebarGroupHeader: View {
    let title: String
    let systemImage: String
    let isFavorites: Bool
    let section: ToolNavigationSection
    let isExpanded: Bool
    let isSearchActive: Bool
    let reduceMotion: Bool
    let action: () -> Void

    @StateObject private var hoverState = SidebarHoverState()

    private var foreground: Color {
        if isFavorites {
            return hoverState.isHovered || isExpanded ? ToolTheme.accentHover : ToolTheme.accent
        }
        if hoverState.isHovered || isExpanded {
            return ToolTheme.textSecondary
        }
        return ToolTheme.textTertiary
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "chevron.right")
                    .font(.system(size: ToolMetrics.IconSize.micro, weight: .bold))
                    .foregroundStyle(foreground)
                    .frame(width: 10, height: 12)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))

                Image(systemName: systemImage)
                    .symbolRenderingMode(.monochrome)
                    .font(.system(size: ToolMetrics.IconSize.medium, weight: .medium))
                    .foregroundStyle(isFavorites ? ToolTheme.accent : foreground)
                    .frame(width: SidebarMetrics.iconSize, height: SidebarMetrics.iconSize)

                Text(title)
                    .font(ToolTypography.groupHeader)
                    .tracking(0.2)
                    .foregroundStyle(foreground)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 0)

                // Arc Spaces 式分类身份点：低饱和渐变，仅非收藏分组。
                if !isFavorites, case .category(let categoryID) = section {
                    Circle()
                        .fill(ToolTheme.categoryGradient(categoryID))
                        .frame(width: 7, height: 7)
                        .opacity(isExpanded ? 0.95 : 0.55)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 8)
            .frame(height: SidebarMetrics.groupHeaderHeight)
            .background(
                backgroundFill,
                in: RoundedRectangle(cornerRadius: SidebarMetrics.rowCornerRadius, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(isExpanded ? "已展开" : "已收起")
        .help(accessibilityLabel)
        .onHover { hoverState.isHovered = $0 }
        // Search / Reduce Motion land immediately; otherwise share accordion timing
        // with the AppKit track owner (ADR-0015) via ToolMotion.animation.
        .animation(
            ToolMotion.animation(
                ToolMotion.Preset.accordion,
                reduceMotion: reduceMotion || isSearchActive
            ),
            value: isExpanded
        )
        .toolAnimation(ToolMotion.Preset.controlFeedback, value: hoverState.isHovered)
    }

    private var accessibilityLabel: String {
        if isSearchActive {
            return "搜索时保持展开\(title)"
        }
        return "\(isExpanded ? "折叠" : "展开")\(title)"
    }

    private var backgroundFill: Color {
        if isFavorites && (isExpanded || hoverState.isHovered) {
            return ToolTheme.accentSoft
        }
        if hoverState.isHovered {
            return ToolTheme.hoverFill
        }
        return .clear
    }
}

private struct BrandMark: View {
    var body: some View {
        // Terminal prompt glyph. Solid accent, no glow (Ink Terminal Pro avoids
        // the Linear-style purple gradient + bloom — SPEC §7, anti-slop).
        Image(systemName: "chevron.right")
            .font(.system(size: ToolMetrics.IconSize.small, weight: .bold))
            .foregroundStyle(ToolTheme.onAccent)
            .frame(width: 22, height: 22)
            .background(ToolTheme.accent, in: RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.nestedControl, style: .continuous))
    }
}

private struct SidebarFooterButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    @StateObject private var hoverState = SidebarHoverState()

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: ToolMetrics.IconSize.medium, weight: .regular))
                    .frame(width: 15)

                Text(title)
                    .font(ToolTypography.label)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .foregroundStyle(hoverState.isHovered ? ToolTheme.textPrimary : ToolTheme.textSecondary)
            .frame(maxWidth: .infinity)
            .frame(height: 30)
            .background(
                hoverState.isHovered ? ToolTheme.hoverFill : Color.clear,
                in: RoundedRectangle(cornerRadius: SidebarMetrics.rowCornerRadius, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .toolInteractionFeedback()
        .onHover { hoverState.isHovered = $0 }
        .toolAnimation(ToolMotion.Preset.controlFeedback, value: hoverState.isHovered)
    }
}

struct SidebarToolRow: View {
    let toolID: ToolID
    let title: String
    let systemImage: String
    let isSelected: Bool
    let isInActiveSection: Bool
    let isFavorite: Bool
    @ObservedObject var hoverState: SidebarNavigationTrackHoverState
    let onToggleFavorite: () -> Void
    let action: () -> Void

    private var shouldHighlight: Bool {
        isSelected && isInActiveSection
    }

    var body: some View {
        HStack(spacing: 0) {
            Button(action: action) {
                HStack(spacing: 8) {
                    Image(systemName: systemImage)
                        .symbolRenderingMode(.monochrome)
                        .font(.system(size: ToolMetrics.IconSize.large, weight: .regular))
                        .foregroundStyle(shouldHighlight ? ToolTheme.accentHover : ToolTheme.textSecondary)
                        .frame(width: 18, height: SidebarMetrics.iconSize)

                    Text(title)
                        .font(ToolTypography.bodyLarge)
                        .fontWeight(shouldHighlight ? .medium : .regular)
                        .foregroundStyle(shouldHighlight ? ToolTheme.textPrimary : ToolTheme.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)

                    Spacer(minLength: 0)
                }
                .padding(.leading, SidebarMetrics.toolRowHorizontalPadding + SidebarMetrics.toolRowHierarchyIndent)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: SidebarMetrics.expandedRowHeight)
            }
            .buttonStyle(.plain)
            // The navigation control owns every point up to the reserved
            // favorite slot.  Without an explicit frame SwiftUI may size the
            // Button to its label's ideal width, leaving the trailing blank
            // area inert even though the row itself is full width.
            .frame(maxWidth: .infinity, alignment: .leading)
            .toolInteractionFeedback()
            .contentShape(Rectangle())
            .accessibilityLabel(title)
            .accessibilityValue(shouldHighlight ? "已选择" : "")

            // Favorite toggle: keep the favorite action as a sibling of the tool button. Nested
            // SwiftUI Buttons have ambiguous event and accessibility behavior.
            Button(action: onToggleFavorite) {
                Image(systemName: isFavorite ? "star.fill" : "star")
                    .font(.system(size: ToolMetrics.IconSize.micro))
                    .foregroundStyle(isFavorite ? ToolTheme.accent : ToolTheme.textSecondary)
                    .frame(width: 14, height: 14)
                    .toolMotionIconSwap(id: isFavorite)
            }
            .frame(width: 24, height: 24)
            .contentShape(Rectangle())
            .buttonStyle(.plain)
            .toolInteractionFeedback()
            .accessibilityIdentifier("sidebar.favorite.\(toolID.rawValue)")
            .help(isFavorite ? "取消收藏" : "加入收藏")
            .accessibilityLabel(isFavorite ? "取消收藏\(title)" : "收藏\(title)")
            .opacity(isFavorite || hoverState.isHovered ? 1 : 0)
            .allowsHitTesting(isFavorite || hoverState.isHovered)
            .accessibilityHidden(!(isFavorite || hoverState.isHovered))
            .toolAnimation(ToolMotion.Preset.controlFeedback, value: isFavorite || hoverState.isHovered)
            .padding(.trailing, SidebarMetrics.toolRowHorizontalPadding)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: SidebarMetrics.expandedRowHeight)
        .background(rowBackground, in: RoundedRectangle(cornerRadius: SidebarMetrics.rowCornerRadius, style: .continuous))
        .overlay(alignment: .leading) {
            if shouldHighlight {
                RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.nestedControl, style: .continuous)
                    .fill(ToolTheme.accent)
                    .frame(width: 3, height: 17)
                    .offset(x: -SidebarMetrics.toolRowHorizontalPadding)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: SidebarMetrics.rowCornerRadius, style: .continuous))
        .toolAnimation(ToolMotion.Preset.controlFeedback, value: hoverState.isHovered)
        .toolAnimation(ToolMotion.Preset.controlFeedback, value: isSelected)
        .contextMenu {
            Button(isFavorite ? "取消收藏" : "加入收藏", action: onToggleFavorite)
        }
    }

    private var rowBackground: Color {
        if shouldHighlight {
            return ToolTheme.selectionFill
        }

        if hoverState.isHovered {
            return ToolTheme.hoverFill
        }

        return .clear
    }
}

@MainActor
private final class SidebarHoverState: ObservableObject {
    @Published var isHovered = false
}
