import AppKit
import SwiftUI
import XToolsDesign

/// 侧栏壳（阶段③ 原生侧栏重组）：品牌带 + 搜索框 + 原生列表 + 底部主题/设置。
///
/// 本视图刻意**不持有任何观察**：收藏与 Section 折叠由 `SidebarNativeList`
/// 直接观察（收藏切换/折叠只重估列表区，RootView 不重估——B4 契约）；
/// 搜索过滤沿用 `SidebarSearchTextField` + `ToolSearchEngine` 投影（拼音/fzf
/// 不变），强制展开/组头禁用/空态浮层的等价行为都在 `SidebarNativeList`。
struct SidebarView: View {
    static let idealWidth: CGFloat = 220

    let projection: ToolNavigationProjection
    let registry: ToolRegistry
    /// 引用透传（观察在 SidebarNativeList）。
    let favorites: FavoritesStore
    let sidebarSections: SidebarSectionExpansionStore
    /// 最近使用 top5（navigation 通道，最新优先；RootView 随导航刷新）。
    let recentToolIDs: [ToolID]
    let selectedToolID: ToolID?
    @Binding var searchText: String
    let searchFocusToken: Int
    let onSelectTool: (ToolID) -> Void
    let onOpenDashboard: () -> Void
    let onToggleFavorite: (ToolID) -> Void
    let onMoveFavorites: (IndexSet, Int) -> Void
    /// Bool = option 点击（单区独占折叠，原生保留旧版头部语义）。
    let onToggleSection: (ToolNavigationSection, Bool) -> Void
    let onToggleTheme: () -> Void
    let onPreferences: () -> Void
    let themeTitle: String
    let themeIcon: String

    @State private var isSearchFocused = false

    private var isSearchActive: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            sidebarHeader
            SidebarNativeList(
                projection: projection,
                registry: registry,
                favorites: favorites,
                sidebarSections: sidebarSections,
                recentToolIDs: recentToolIDs,
                selectedToolID: selectedToolID,
                isSearchActive: isSearchActive,
                onSelectTool: onSelectTool,
                onOpenDashboard: onOpenDashboard,
                onToggleFavorite: onToggleFavorite,
                onMoveFavorites: onMoveFavorites,
                onToggleSection: onToggleSection
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .layoutPriority(1)
            sidebarFooter
        }
        .frame(width: Self.idealWidth, alignment: .top)
        .frame(maxHeight: .infinity, alignment: .top)
        // B0 材质决策（见 SidebarNativeList.swift 文件头）：整列系统 sidebar
        // 材质铺底，替代旧的不透明暖墨填充（toolSurface(.sidebar) 已退役）。
        .background(SidebarMaterialBackground())
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(ToolTheme.border)
                .frame(width: ToolMetrics.Spacing.hairline)
        }
    }

    private var sidebarHeader: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Local content-area brand band under the native unified toolbar (no
            // fullSizeContentView). Compact height + zero gap into search so the
            // header reads as one unit instead of a second titlebar slab.
            HStack(spacing: ToolMetrics.Spacing.sm) {
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
                .frame(height: ToolMetrics.Spacing.hairline)
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
                    .font(ToolTypography.icon(ToolMetrics.IconSize.small, .medium))
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
                .strokeBorder(isSearchFocused ? ToolTheme.accentBorder : ToolTheme.border, lineWidth: isSearchFocused ? 1 : ToolMetrics.Spacing.hairline)
        }
        .toolAnimation(ToolMotion.Preset.controlFeedback, value: isSearchFocused)
        .padding(.horizontal, SidebarMetrics.searchHorizontalPadding)
        .padding(.top, SidebarMetrics.searchTopPadding)
        .padding(.bottom, SidebarMetrics.searchBottomPadding)
    }

    private var sidebarFooter: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(ToolTheme.border)
                .frame(height: ToolMetrics.Spacing.hairline)

            HStack(spacing: ToolMetrics.Spacing.fine) {
                SidebarFooterButton(title: themeTitle, systemImage: themeIcon, action: onToggleTheme)
                SidebarFooterButton(title: "设置", systemImage: "gearshape", action: onPreferences)
            }
            .padding(.horizontal, ToolMetrics.Spacing.compact)
            .padding(.vertical, ToolMetrics.Spacing.sm)
        }
    }
}
