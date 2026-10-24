import AppKit
import SwiftUI
import XToolsDesign

// MARK: - B0 材质决策
//
// `List(.sidebar)` 自带的材质只覆盖列表区（NSScrollView 内的视觉材质视图），
// 直接塞进现有 VStack 会把侧栏切成「中段系统材质 + 头尾自绘暖墨填充」的
// 双拼表面。决策：整列铺**一块全高的系统 sidebar 材质**（NSVisualEffectView，
// material .sidebar / blending .behindWindow，即系统侧栏的原生配方），List 加
// `.scrollContentBackground(.hidden)` 只保留行级样式（选中药丸/hover/type-ahead
// 全部原生）。头部品牌带、搜索框与底部按钮因此与列表共用同一张材质面，
// 与右侧 `workspaceBackground` 的分层契约继续由 0.5pt 发丝线承担。
// 真窗口验证项：材质与 HiddenTitleBar 原生工具栏的衔接、失焦/非 key 态的
// 材质降饱和表现。

/// 整列系统侧栏材质铺底（见文件头 B0 决策注释）。
struct SidebarMaterialBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .sidebar
        view.blendingMode = .behindWindow
        view.state = .active
        view.wantsLayer = true
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

// MARK: - List 选中值

/// List 选中哈希键：工作台行（`selectedToolID == nil` 的壳层语义）与工具行
/// 统一进一个原生 `List(selection:)` 绑定，键盘 ↑↓/回车/type-ahead 由 List
/// 原生接管，⌘0 的落点因此也能被方向键抵达。
enum SidebarListSelection: Hashable {
    case dashboard
    case tool(ToolID)
}

// MARK: - SidebarNativeList

/// 原生侧栏列表（阶段③ 决策 8）：SwiftUI `List` + `.listStyle(.sidebar)`。
///
/// 区块：工作台行（独立 Section 顶行）→ 收藏（手动序，`.onMove` 仅此区）→
/// 最近使用（frecency 只读，<2 条隐藏，搜索时隐藏）→ 分类 ×7（收藏工具
/// 保留在分类中）。Section 折叠直接观察 `SidebarSectionExpansionStore`
/// （持久化键 tools.sidebar.collapsedSections.v1 兼容读取；动作层的
/// `expand` 写入——⌘1-9 跳转、选中工具——即时反映到 List）。
///
/// 性能契约（B4）：hover / 选中 / 拖拽状态全部在 List 与行内部（行 hover
/// 是行视图私有 `@State`，永不外溢）；本视图持有收藏与折叠两个观察，
/// 收藏切换/Section 折叠只重估列表区，RootView 不重估。
struct SidebarNativeList: View {
    let projection: ToolNavigationProjection
    let registry: ToolRegistry
    @ObservedObject var favorites: FavoritesStore
    @ObservedObject var sidebarSections: SidebarSectionExpansionStore
    /// 最近使用 top5（navigation 通道，最新优先；RootView 侧随导航刷新）。
    let recentToolIDs: [ToolID]
    let selectedToolID: ToolID?
    let isSearchActive: Bool
    let onSelectTool: (ToolID) -> Void
    let onOpenDashboard: () -> Void
    let onToggleFavorite: (ToolID) -> Void
    let onMoveFavorites: (IndexSet, Int) -> Void
    /// Bool = option 点击（旧版头部 option-click 单区独占语义，原生保留）。
    let onToggleSection: (ToolNavigationSection, Bool) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        List(selection: selectionBinding) {
            dashboardSection
            favoritesSection
            recentsSection
            categorySections
        }
        .listStyle(.sidebar)
        // B0：材质由整列 SidebarMaterialBackground 统一铺底，List 只画行。
        .scrollContentBackground(.hidden)
        // 折叠/展开与收藏增删的结构变化共享 accordion 节奏（PRD：收藏反馈
        // 轻量化——星标瞬时翻转、列表平滑重排、无飞行）；搜索强制展开与
        // RM 落帧。
        .animation(
            ToolMotion.animation(
                ToolMotion.Preset.accordion,
                reduceMotion: reduceMotion || isSearchActive
            ),
            value: sidebarSections.collapsedGroupIDs
        )
        .animation(
            ToolMotion.animation(
                ToolMotion.Preset.accordion,
                reduceMotion: reduceMotion || isSearchActive
            ),
            value: favorites.favoriteIDs
        )
        .overlay(alignment: .top) { emptySearchOverlay }
    }

    // MARK: 选中绑定

    private var selectionBinding: Binding<SidebarListSelection> {
        Binding(
            get: { selectedToolID.map(SidebarListSelection.tool) ?? .dashboard },
            set: { selection in
                switch selection {
                case .dashboard:
                    onOpenDashboard()
                case .tool(let toolID):
                    onSelectTool(toolID)
                }
            }
        )
    }

    // MARK: 工作台顶行

    private var dashboardSection: some View {
        Section {
            HStack(spacing: ToolMetrics.Spacing.sm) {
                Label("工作台", systemImage: "square.grid.3x3")
                    .symbolRenderingMode(.monochrome)
                    .font(ToolTypography.bodyLarge)
                Spacer(minLength: 0)
                IndexKeycap(label: "⌘0")
            }
            .tag(SidebarListSelection.dashboard)
            .accessibilityIdentifier("sidebar.dashboard")
            .accessibilityLabel("工作台")
        }
    }

    // MARK: 收藏区（拖拽排序仅此区）

    @ViewBuilder
    private var favoritesSection: some View {
        let items = favoriteItems
        if !items.isEmpty {
            Section {
                ForEach(items) { item in
                    toolRow(item)
                }
                .onMove(perform: onMoveFavorites)
            } header: {
                sectionHeader(
                    title: "收藏",
                    systemImage: "star.fill",
                    section: .favorites,
                    isFavoritesHeader: true
                )
            }
        }
    }

    /// 收藏区 = 收藏序（tools.favorites.v1 数组序）× 搜索匹配过滤。
    private var favoriteItems: [ToolNavigationItem] {
        registry.tools(for: favorites.favoriteIDs)
            .filter { isSearchMatch($0) }
            .map { Self.item(for: $0, section: .favorites) }
    }

    // MARK: 最近使用区（只读，无拖拽）

    @ViewBuilder
    private var recentsSection: some View {
        // 搜索时隐藏（等价旧版：搜索结果只含收藏上浮 + 分类过滤，无重复行）；
        // 不足 2 条同样隐藏，避免单行「伪区」。
        if !isSearchActive, recentToolIDs.count >= 2 {
            Section {
                ForEach(recentItems) { item in
                    toolRow(item)
                }
            } header: {
                sectionHeader(
                    title: "最近使用",
                    systemImage: "clock",
                    section: .recents,
                    isFavoritesHeader: false
                )
            }
        }
    }

    private var recentItems: [ToolNavigationItem] {
        registry.tools(for: recentToolIDs)
            .map { Self.item(for: $0, section: .recents) }
    }

    // MARK: 分类区（收藏工具保留在分类中）

    @ViewBuilder
    private var categorySections: some View {
        ForEach(projection.sidebarGroups) { group in
            let items = categoryItems(in: group)
            if !items.isEmpty {
                Section {
                    // 折叠 = 只渲染头行（搜索强制展开，等价旧版）。
                    if isSectionExpanded(group.section) {
                        ForEach(items) { item in
                            toolRow(item)
                        }
                    }
                } header: {
                    sectionHeader(
                        title: group.title,
                        systemImage: group.systemImage,
                        section: group.section,
                        isFavoritesHeader: false
                    )
                }
            }
        }
    }

    /// 分类行装配：非搜索 = 全部工具（收藏不移出，PRD 决策 8）；
    /// 搜索 = 命中且非收藏（命中的收藏上浮到收藏区，等价旧版去重）。
    private func categoryItems(in group: ToolNavigationGroup) -> [ToolNavigationItem] {
        guard isSearchActive else { return group.items }
        return group.items.filter { !favorites.isFavorite($0.id) }
    }

    // MARK: 行与头

    private func toolRow(_ item: ToolNavigationItem) -> some View {
        SidebarToolListRow(
            toolID: item.id,
            title: item.title,
            systemImage: item.systemImage,
            isFavorite: favorites.isFavorite(item.id),
            onToggleFavorite: { onToggleFavorite(item.id) }
        )
        .tag(SidebarListSelection.tool(item.id))
        .accessibilityIdentifier("sidebar.tool.\(item.id.rawValue)")
    }

    private func sectionHeader(
        title: String,
        systemImage: String,
        section: ToolNavigationSection,
        isFavoritesHeader: Bool
    ) -> some View {
        SidebarListSectionHeader(
            title: title,
            systemImage: systemImage,
            section: section,
            isFavorites: isFavoritesHeader,
            isExpanded: isSectionExpanded(section),
            isSearchActive: isSearchActive,
            onToggle: { optionPressed in
                onToggleSection(section, optionPressed)
            }
        )
    }

    private func isSectionExpanded(_ section: ToolNavigationSection) -> Bool {
        // 搜索时全部 Section 强制展开（等价旧版；组头同时禁用）。
        isSearchActive || sidebarSections.isExpanded(section.groupID)
    }

    private func isSearchMatch(_ tool: RegisteredTool) -> Bool {
        projection.matchingToolIDs?.contains(tool.id) ?? true
    }

    private static func item(
        for tool: RegisteredTool,
        section: ToolNavigationSection
    ) -> ToolNavigationItem {
        ToolNavigationItem(
            id: tool.id,
            title: tool.title,
            categoryID: tool.categoryID,
            systemImage: tool.systemImage,
            section: section
        )
    }

    // MARK: 空搜索态

    /// 搜索无命中浮层（文案沿用旧版「没有匹配的工具」）。
    @ViewBuilder
    private var emptySearchOverlay: some View {
        if isSearchActive, visibleItemCountInSearch == 0 {
            VStack(spacing: ToolMetrics.Spacing.fine) {
                Image(systemName: "magnifyingglass")
                    .font(ToolTypography.icon(ToolMetrics.IconSize.medium, .medium))
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
                    .strokeBorder(ToolTheme.border, lineWidth: ToolMetrics.Spacing.hairline)
            }
            .padding(.horizontal, ToolMetrics.Spacing.md)
            .padding(.top, ToolMetrics.Spacing.md)
        }
    }

    /// 搜索态可见行数：收藏区命中 + 分类区去重后剩余（最近使用区搜索时隐藏）。
    private var visibleItemCountInSearch: Int {
        favoriteItems.count + projection.sidebarGroups.reduce(0) { count, group in
            count + categoryItems(in: group).count
        }
    }
}

// MARK: - Section 头

/// List Section 头：chevron 折叠指示 + 图标 + 标题。点击折叠/展开，
/// option 点击单区独占（旧版头部语义经 NSEvent 修饰键等价保留）。
/// 搜索时禁用并强制呈现展开态。
struct SidebarListSectionHeader: View {
    let title: String
    let systemImage: String
    let section: ToolNavigationSection
    let isFavorites: Bool
    let isExpanded: Bool
    let isSearchActive: Bool
    /// 参数 = 是否按住 option（单区独占折叠）。
    let onToggle: (Bool) -> Void

    // 行内私有 hover 状态：只重估头行自身（B4 契约，永不外溢）。
    @State private var isHovered = false

    var body: some View {
        Button {
            onToggle(NSEvent.modifierFlags.contains(.option))
        } label: {
            HStack(spacing: ToolMetrics.Spacing.sm) {
                Image(systemName: "chevron.right")
                    .font(ToolTypography.icon(ToolMetrics.IconSize.micro, .semibold))
                    .foregroundStyle(foreground)
                    .frame(width: 10, height: 12)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))

                Image(systemName: systemImage)
                    .symbolRenderingMode(.monochrome)
                    .font(ToolTypography.icon(ToolMetrics.IconSize.medium, .medium))
                    .foregroundStyle(iconForeground)

                Text(title)
                    .font(ToolTypography.groupHeader)
                    .tracking(0.2)
                    .foregroundStyle(foreground)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, ToolMetrics.Spacing.sm)
            .indexRowHoverBackground(isHovered)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isSearchActive)
        .onHover { isHovered = $0 }
        .toolAnimation(ToolMotion.Preset.controlFeedback, value: isHovered)
        .accessibilityIdentifier("sidebar.group.\(section.groupID)")
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(isExpanded ? "已展开" : "已收起")
    }

    private var foreground: Color {
        if isSearchActive {
            return ToolTheme.textTertiary
        }
        if isHovered || isExpanded {
            return ToolTheme.textSecondary
        }
        return ToolTheme.textTertiary
    }

    private var iconForeground: Color {
        if isFavorites {
            return ToolTheme.accent
        }
        return foreground
    }

    private var accessibilityLabel: String {
        if isSearchActive {
            return "搜索时保持展开\(title)"
        }
        return "\(isExpanded ? "折叠" : "展开")\(title)"
    }
}

// MARK: - 工具行

/// 原生侧栏工具行：`Label`（单色图标，Tahoe 惯例）+ 尾部收藏星。
/// 选中药丸由 `List(selection:)` 系统绘制（自绘 CASpring 选中条与 rail
/// 竖条已退役）；hover 星标显隐是行私有 `@State`，只重估本行。
struct SidebarToolListRow: View {
    let toolID: ToolID
    let title: String
    let systemImage: String
    let isFavorite: Bool
    let onToggleFavorite: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: ToolMetrics.Spacing.sm) {
            Label {
                Text(title)
                    .lineLimit(1)
                    .truncationMode(.tail)
            } icon: {
                Image(systemName: systemImage)
                    .symbolRenderingMode(.monochrome)
            }
            .font(ToolTypography.bodyLarge)

            Spacer(minLength: 0)

            // 收藏星：hover 显 / 已收藏常显；作为行的兄弟控件（嵌套按钮的
            // 命中/无障碍歧义先例见旧 SidebarToolRow 注释），星标点击不改变
            // 选中。`IndexFavoriteButton` 持有星标语义与 accent 激活色。
            IndexFavoriteButton(
                isFavorite: isFavorite,
                density: .compact,
                help: isFavorite ? "取消收藏\(title)" : "收藏\(title)"
            ) {
                onToggleFavorite()
            }
            .accessibilityIdentifier("sidebar.favorite.\(toolID.rawValue)")
            .opacity(isFavorite || isHovered ? 1 : 0)
            .allowsHitTesting(isFavorite || isHovered)
            .accessibilityHidden(!(isFavorite || isHovered))
            .toolAnimation(ToolMotion.Preset.controlFeedback, value: isFavorite || isHovered)
        }
        .onHover { isHovered = $0 }
        .contextMenu {
            Button(isFavorite ? "取消收藏" : "加入收藏", action: onToggleFavorite)
        }
    }
}
