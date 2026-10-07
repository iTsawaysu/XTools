import AppKit
import SwiftUI

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
                IndexKeycap(label: "⌘0")
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

            HStack(spacing: SidebarMetrics.searchContentSpacing) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(ToolTheme.textSecondary)
                    .font(.system(size: ToolMetrics.IconSize.small, weight: .medium))
                    .frame(width: SidebarMetrics.searchIconWidth)
                    .allowsHitTesting(false)
                    .arrowCursorOnHover()

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
                        .arrowCursorOnHover()
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
