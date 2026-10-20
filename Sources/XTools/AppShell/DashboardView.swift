import SwiftUI

@MainActor
struct DashboardView: View {
    @ObservedObject private var store: DashboardStore
    @ObservedObject private var favorites: FavoritesStore
    private let registry: ToolRegistry
    private let routing: any DetailActionRouting
    private let categoryGroups: [ToolRegistryCategoryGroup]
    private let knownToolIDs: Set<ToolID>
    private let totalToolCount: Int

    init(
        store: DashboardStore,
        registry: ToolRegistry,
        favorites: FavoritesStore,
        routing: any DetailActionRouting
    ) {
        self.store = store
        self.registry = registry
        self.favorites = favorites
        self.routing = routing
        let groups = registry.categoryGroups()
        self.categoryGroups = groups
        self.knownToolIDs = Set(groups.flatMap { $0.tools.map(\.id) })
        self.totalToolCount = groups.reduce(0) { $0 + $1.tools.count }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                WorkbenchHeader()
                WorkbenchSearchHero(action: routing.openCommandPalette)
                    .padding(.top, ToolMetrics.Workbench.sectionGap)

                HStack(alignment: .top, spacing: 16) {
                    recentPanel
                    favoritesPanel
                }
                .padding(.top, ToolMetrics.Workbench.sectionGap)

                categorySection
                    .padding(.top, 24)
            }
            .frame(maxWidth: ToolMetrics.Workbench.mainMaxWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .top)
            .padding(.horizontal, ToolMetrics.Workbench.horizontalInset)
            .padding(.top, ToolMetrics.Workbench.topInset)
            .padding(.bottom, ToolMetrics.Spacing.page)
        }
        .background(ToolTheme.Workbench.canvas)
    }

    // MARK: - Recent / favorites

    private var recentPanel: some View {
        WorkbenchPanel(title: "最近使用", detail: "本机使用记录") {
            if recentTools.isEmpty {
                IndexEmptyState(
                    title: "暂无记录",
                    systemImage: "clock",
                    message: "打开工具后会显示在这里。",
                    density: .list
                )
            } else {
                LazyVGrid(columns: toolCardGrid, spacing: 8) {
                    ForEach(recentTools) { item in
                        WorkbenchToolCard(
                            tool: item.tool,
                            detail: "\(registry.categoryTitle(for: item.tool.categoryID) ?? item.tool.categoryID.rawValue) · \(WorkbenchRelativeTime.text(for: item.recent.lastOpenedAt))",
                            identifier: "dashboard.recent.\(item.tool.id.rawValue)",
                            action: { routing.selectTool(item.tool.id) }
                        )
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private var favoritesPanel: some View {
        WorkbenchPanel(
            title: "收藏",
            detail: favoriteTools.isEmpty ? "置顶工具" : "\(favoriteTools.count) 个置顶"
        ) {
            if favoriteTools.isEmpty {
                IndexEmptyState(
                    title: "暂无收藏",
                    systemImage: "star",
                    message: "在侧栏点星标收藏工具。",
                    density: .list
                )
            } else {
                LazyVGrid(columns: toolCardGrid, spacing: 8) {
                    ForEach(favoriteTools) { tool in
                        WorkbenchToolCard(
                            tool: tool,
                            detail: registry.categoryTitle(for: tool.categoryID) ?? tool.categoryID.rawValue,
                            identifier: "dashboard.favorite.\(tool.id.rawValue)",
                            action: { routing.selectTool(tool.id) }
                        )
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    // MARK: - Categories

    private var categorySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            WorkbenchSectionHeader(
                title: "分类",
                detail: "\(categoryGroups.count) 个分类 · \(totalToolCount) 个工具"
            )

            LazyVGrid(columns: fourColumnGrid, spacing: 8) {
                ForEach(categoryGroups, id: \.category.id) { group in
                    WorkbenchCategoryChip(
                        category: group.category,
                        count: group.tools.count,
                        action: { routing.selectCategory(group.category.id) }
                    )
                }
            }
        }
    }

    private var recentTools: [DashboardRecentItem] {
        store.recentTools(knownToolIDs: knownToolIDs)
            .prefix(4)
            .compactMap { recent in
                registry.tool(for: recent.toolID).map {
                    DashboardRecentItem(recent: recent, tool: $0)
                }
            }
    }

    private var favoriteTools: [RegisteredTool] {
        favorites.favoriteIDs.prefix(4).compactMap(registry.tool(for:))
    }

    private var toolCardGrid: [GridItem] {
        [GridItem(.adaptive(minimum: 200), spacing: 8)]
    }

    private var fourColumnGrid: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)
    }
}

private struct DashboardRecentItem: Identifiable {
    let recent: DashboardRecentTool
    let tool: RegisteredTool

    var id: ToolID { tool.id }
}

// MARK: - Header

private struct WorkbenchHeader: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var arrived = false

    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 6) {
                Text("工作台")
                    .font(ToolTypography.Workbench.title)
                    .foregroundStyle(ToolTheme.Workbench.textPrimary)
                Text("搜索、最近与收藏——任何工具两步内到达。")
                    .font(ToolTypography.Workbench.subtitle)
                    .foregroundStyle(ToolTheme.Workbench.textSecondary)
            }

            Spacer(minLength: 12)

            Label("内容只在当前页面处理", systemImage: "lock")
                .font(ToolTypography.Workbench.caption)
                .foregroundStyle(ToolTheme.Workbench.textFaint)
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.bottom, 18)
        .overlay(alignment: .bottom) {
            Rectangle().fill(ToolTheme.border).frame(height: 0.5)
        }
        .opacity(arrived ? 1 : 0)
        .offset(y: arrived ? 0 : ToolMotion.Distance.headerRise)
        .animation(
            ToolMotion.animation(ToolMotion.Preset.pageHeader, reduceMotion: reduceMotion),
            value: arrived
        )
        .onAppear { arrived = true }
    }
}

// MARK: - Search entry

private struct WorkbenchSearchHero: View {
    let action: () -> Void

    @State private var isHovering = false
    @FocusState private var isFocused: Bool

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: ToolMetrics.IconSize.large, weight: .medium))
                    .foregroundStyle(ToolTheme.accent)

                Text("搜索工具、命令或操作…")
                    .font(ToolTypography.bodyMedium)
                    .foregroundStyle(ToolTheme.textSecondary)

                Spacer(minLength: 0)

                HStack(spacing: 8) {
                    Text("工具").foregroundStyle(ToolTheme.textPrimary)
                    Text("命令").foregroundStyle(ToolTheme.textTertiary)
                    Text("收藏").foregroundStyle(ToolTheme.textTertiary)
                }
                .font(ToolTypography.caption)

                IndexKeycap(label: "⌘K")
            }
            .padding(.horizontal, 14)
            .frame(height: ToolMetrics.Workbench.searchHeroHeight)
            .background(
                isHovering ? ToolTheme.utilityBackground : ToolTheme.panelBackground,
                in: RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.field, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.field, style: .continuous)
                    .strokeBorder(ToolTheme.accentBorder, lineWidth: 1.5)
            }
            .contentShape(RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.field, style: .continuous))
        }
        .buttonStyle(IndexBareButtonStyle())
        .focused($isFocused)
        .indexFocusRing(active: isFocused, cornerRadius: ToolMetrics.CornerRadius.field)
        .onHover { isHovering = $0 }
        .accessibilityIdentifier("dashboard.search")
        .accessibilityLabel("搜索工具、命令或操作")
        .accessibilityHint("打开命令面板，快捷键 Command-K")
        .help("打开命令面板（⌘K）")
    }
}

// MARK: - Panel and cards

private struct WorkbenchPanel<Content: View>: View {
    let title: String
    let detail: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title)
                    .font(ToolTypography.sectionTitle)
                    .foregroundStyle(ToolTheme.textPrimary)
                Spacer(minLength: 8)
                Text(detail)
                    .font(ToolTypography.caption)
                    .foregroundStyle(ToolTheme.textTertiary)
                    .lineLimit(1)
            }

            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: ToolMetrics.Workbench.panelMinHeight, alignment: .topLeading)
        .background(
            ToolTheme.panelBackground,
            in: RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.panel, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.panel, style: .continuous)
                .strokeBorder(ToolTheme.border, lineWidth: 0.5)
        }
    }
}

private struct WorkbenchSectionHeader: View {
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(ToolTypography.Workbench.sectionTitle)
                .foregroundStyle(ToolTheme.Workbench.textPrimary)
            Spacer()
            Text(detail)
                .font(ToolTypography.Workbench.caption)
                .foregroundStyle(ToolTheme.Workbench.textFaint)
        }
    }
}

private struct WorkbenchToolCard: View {
    let tool: RegisteredTool
    let detail: String
    let identifier: String
    let action: () -> Void

    @State private var isHovering = false
    @FocusState private var isFocused: Bool

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: tool.systemImage)
                    .font(.system(size: ToolMetrics.IconSize.medium, weight: .medium))
                    .foregroundStyle(ToolTheme.accent)
                    .frame(width: ToolMetrics.Workbench.toolCardIconBox, height: ToolMetrics.Workbench.toolCardIconBox)
                    .background(
                        ToolTheme.selectionFill,
                        in: RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.control, style: .continuous)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(tool.title)
                        .font(ToolTypography.bodyMedium.weight(.semibold))
                        .foregroundStyle(ToolTheme.textPrimary)
                        .lineLimit(1)
                    Text(detail)
                        .font(ToolTypography.caption)
                        .foregroundStyle(ToolTheme.textTertiary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(ToolTheme.textTertiary)
            }
            .padding(.horizontal, 10)
            .frame(height: ToolMetrics.Workbench.toolCardHeight)
            .background(
                isHovering ? ToolTheme.utilityBackground : ToolTheme.panelBackground,
                in: RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.field, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.field, style: .continuous)
                    .strokeBorder(ToolTheme.border, lineWidth: 0.5)
            }
            .contentShape(RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.field, style: .continuous))
        }
        .buttonStyle(IndexBareButtonStyle())
        .focused($isFocused)
        .indexFocusRing(active: isFocused, cornerRadius: ToolMetrics.CornerRadius.field)
        .onHover { isHovering = $0 }
        .accessibilityLabel("打开\(tool.title)")
        .accessibilityIdentifier(identifier)
    }
}

private struct WorkbenchCategoryChip: View {
    let category: ToolCategory
    let count: Int
    let action: () -> Void

    @State private var isHovering = false
    @FocusState private var isFocused: Bool

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: category.systemImage)
                    .font(.system(size: ToolMetrics.IconSize.small, weight: .medium))
                    .foregroundStyle(ToolTheme.textSecondary)
                    .frame(width: 16)

                Text(category.title)
                    .font(ToolTypography.bodyPlain)
                    .foregroundStyle(ToolTheme.textPrimary)
                    .lineLimit(1)

                Spacer(minLength: 0)

                Circle()
                    .fill(ToolTheme.categoryGradient(category.id))
                    .frame(width: 5, height: 5)
                    .accessibilityHidden(true)

                Text("\(count)")
                    .font(ToolTypography.caption)
                    .foregroundStyle(ToolTheme.textTertiary)
                    .monospacedDigit()
            }
            .padding(.horizontal, 10)
            .frame(height: ToolMetrics.Workbench.categoryChipHeight)
            .background(
                isHovering ? ToolTheme.utilityBackground : ToolTheme.panelBackground,
                in: RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.field, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.field, style: .continuous)
                    .strokeBorder(ToolTheme.border, lineWidth: 0.5)
            }
            .contentShape(RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.field, style: .continuous))
        }
        .buttonStyle(IndexBareButtonStyle())
        .focused($isFocused)
        .indexFocusRing(active: isFocused, cornerRadius: ToolMetrics.CornerRadius.field)
        .onHover { isHovering = $0 }
        .accessibilityLabel("打开\(category.title)")
        .accessibilityHint("打开该分类的第一个工具")
        .accessibilityIdentifier("dashboard.category.\(category.id.rawValue)")
    }
}

// MARK: - Relative time

private enum WorkbenchRelativeTime {
    static func text(for date: Date, now: Date = Date()) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        if seconds < 60 { return "刚刚" }
        if seconds < 3600 { return "\(Int(seconds / 60)) 分钟前" }
        if seconds < 86400 { return "\(Int(seconds / 3600)) 小时前" }
        return "\(Int(seconds / 86400)) 天前"
    }
}
