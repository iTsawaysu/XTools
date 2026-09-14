import SwiftUI

struct DashboardCardContent: Identifiable, Equatable {
    enum Action: Equatable {
        case openCard
        case openTool(ToolID)
        case openCommandPalette
    }

    enum Size: Equatable { case small, medium, large }
    struct ToolItem: Identifiable, Equatable {
        let id: ToolID; let title: String; let systemImage: String; let subtitle: String; let launchCount: Int
        init(id: ToolID, title: String, systemImage: String, subtitle: String = "", launchCount: Int = 0) { self.id = id; self.title = title; self.systemImage = systemImage; self.subtitle = subtitle; self.launchCount = launchCount }
    }
    struct CategoryItem: Identifiable, Equatable { let id: String; let title: String; let systemImage: String; let count: Int }
    let id: String; let title: String; let subtitle: String; let systemImage: String; let value: String?; let size: Size; let tint: Color; let detail: String?; let trend: [Int]; let tools: [ToolItem]; let categories: [CategoryItem]; let action: Action?
    init(id: String, title: String, subtitle: String = "", systemImage: String, value: String? = nil, size: Size = .medium, tint: Color = ToolTheme.accent, detail: String? = nil, trend: [Int] = [], tools: [ToolItem] = [], categories: [CategoryItem] = [], action: Action? = nil) { self.id = id; self.title = title; self.subtitle = subtitle; self.systemImage = systemImage; self.value = value; self.size = size; self.tint = tint; self.detail = detail; self.trend = trend; self.tools = tools; self.categories = categories; self.action = action }
}

private struct DashboardCardSpanKey: LayoutValueKey {
    static let defaultValue: DashboardCardContent.Size = .medium
}

struct DashboardWaterfallPlacement: Equatable {
    let index: Int
    let column: Int
    let columnSpan: Int
    let row: Int
}

/// Computes the discrete placement used by `DashboardWaterfallLayout`.
/// Keeping this separate makes the no-hole and compact-breakpoint rules
/// testable without constructing a SwiftUI view hierarchy.
enum DashboardWaterfallPlanner {
    static func placements(for sizes: [DashboardCardContent.Size], compact: Bool) -> [DashboardWaterfallPlacement] {
        guard !sizes.isEmpty else { return [] }
        if compact {
            return sizes.indices.map { DashboardWaterfallPlacement(index: $0, column: 0, columnSpan: 1, row: $0) }
        }

        var heights = [0, 0]
        return sizes.enumerated().map { index, size in
            if size == .large {
                let row = max(heights[0], heights[1])
                heights = [row + 1, row + 1]
                return DashboardWaterfallPlacement(index: index, column: 0, columnSpan: 2, row: row)
            }
            let column = heights[0] <= heights[1] ? 0 : 1
            let row = heights[column]
            heights[column] += 1
            return DashboardWaterfallPlacement(index: index, column: column, columnSpan: 1, row: row)
        }
    }
}

struct DashboardWaterfallLayout: Layout {
    var spacing: CGFloat = ToolMetrics.Spacing.md
    var collapseWidth: CGFloat = 720

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        guard !subviews.isEmpty else { return .zero }
        let width = resolvedWidth(proposal.width)
        let compact = width < collapseWidth
        let columnWidth = max(0, (width - spacing) / 2)
        var heights = [CGFloat](repeating: 0, count: 2)

        for subview in subviews {
            let size = subview[DashboardCardSpanKey.self]
            if compact {
                let measured = subview.sizeThatFits(ProposedViewSize(width: width, height: nil))
                heights[0] += measured.height + (heights[0] > 0 ? spacing : 0)
            } else if size == .large {
                let y = max(heights[0], heights[1])
                let measured = subview.sizeThatFits(ProposedViewSize(width: width, height: nil))
                heights = [y + measured.height + spacing, y + measured.height + spacing]
            } else {
                let column = heights[0] <= heights[1] ? 0 : 1
                let measured = subview.sizeThatFits(ProposedViewSize(width: columnWidth, height: nil))
                heights[column] += measured.height + (heights[column] > 0 ? spacing : 0)
            }
        }
        let height = max(0, (compact ? heights[0] : max(heights[0], heights[1])) - spacing)
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        guard !subviews.isEmpty else { return }
        let compact = bounds.width < collapseWidth
        let columnWidth = max(0, (bounds.width - spacing) / 2)
        var heights = [CGFloat](repeating: 0, count: 2)

        for subview in subviews {
            let size = subview[DashboardCardSpanKey.self]
            if compact {
                let measured = subview.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
                subview.place(at: CGPoint(x: bounds.minX, y: bounds.minY + heights[0]), anchor: .topLeading, proposal: ProposedViewSize(width: bounds.width, height: measured.height))
                heights[0] += measured.height + spacing
            } else if size == .large {
                let y = max(heights[0], heights[1])
                let measured = subview.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
                subview.place(at: CGPoint(x: bounds.minX, y: bounds.minY + y), anchor: .topLeading, proposal: ProposedViewSize(width: bounds.width, height: measured.height))
                heights = [y + measured.height + spacing, y + measured.height + spacing]
            } else {
                let column = heights[0] <= heights[1] ? 0 : 1
                let measured = subview.sizeThatFits(ProposedViewSize(width: columnWidth, height: nil))
                subview.place(at: CGPoint(x: bounds.minX + CGFloat(column) * (columnWidth + spacing), y: bounds.minY + heights[column]), anchor: .topLeading, proposal: ProposedViewSize(width: columnWidth, height: measured.height))
                heights[column] += measured.height + spacing
            }
        }
    }

    private func resolvedWidth(_ proposed: CGFloat?) -> CGFloat {
        guard let proposed, proposed.isFinite else { return collapseWidth * 2 + spacing }
        return max(0, proposed)
    }
}

struct DashboardView: View {
    let cards: [DashboardCardContent]; let onOpenCard: (String) -> Void; let onSelectTool: (ToolID) -> Void; let onOpenCommandPalette: () -> Void; let onEditLayout: () -> Void
    private let layoutStore: DashboardStore?; private let registry: ToolRegistry?; private let autoResumeLastTool: Bool; private let onSetAutoResumeLastTool: @MainActor @Sendable (Bool) -> Void
    @State private var searchText = ""; @State private var selectedSearchIndex = 0; @State private var isSearchFocused = false; @State private var isEditing = false; @State private var showsLayoutEditor = false
    @FocusState private var searchFieldFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(cards: [DashboardCardContent] = [], onOpenCard: @escaping (String) -> Void = { _ in }, onSelectTool: @escaping (ToolID) -> Void = { _ in }, onOpenCommandPalette: @escaping () -> Void = {}, onEditLayout: @escaping () -> Void = {}, layoutStore: DashboardStore? = nil, registry: ToolRegistry? = nil, autoResumeLastTool: Bool = false, onSetAutoResumeLastTool: @escaping @MainActor @Sendable (Bool) -> Void = { _ in }) { self.cards = cards; self.onOpenCard = onOpenCard; self.onSelectTool = onSelectTool; self.onOpenCommandPalette = onOpenCommandPalette; self.onEditLayout = onEditLayout; self.layoutStore = layoutStore; self.registry = registry; self.autoResumeLastTool = autoResumeLastTool; self.onSetAutoResumeLastTool = onSetAutoResumeLastTool }

    var body: some View {
        GeometryReader { geometry in
            let chrome = IndexPageChrome.dashboard
            let compact = geometry.size.width < 720
            ScrollView {
                VStack(alignment: .leading, spacing: chrome.sectionSpacing) {
                    dashboardHeader
                    commandBox
                    if cards.isEmpty { emptyState } else { cardGrid(compact: compact) }
                    privacyNote
                }
                    .frame(maxWidth: 1_060, alignment: .leading).frame(maxWidth: .infinity, alignment: .top)
                    .padding(.horizontal, compact ? ToolMetrics.Spacing.lg : chrome.horizontalPadding)
                    .padding(.top, chrome.topPadding)
                    .padding(.bottom, compact ? ToolMetrics.Spacing.xl : chrome.bottomPadding)
            }
        }
        .background(ToolTheme.workspaceBackground).accessibilityIdentifier("personal-dashboard")
        .sheet(isPresented: $showsLayoutEditor) { if let layoutStore { DashboardLayoutEditor(store: layoutStore, autoResumeLastTool: autoResumeLastTool, onSetAutoResumeLastTool: onSetAutoResumeLastTool) } }
    }

    private var dashboardHeader: some View {
        IndexPageHeader(
            "工作台",
            subtitle: "个人行动面板 · 今天先从上次停下的地方继续。",
            chrome: .dashboard
        ) {
            HStack(spacing: ToolMetrics.Spacing.sm) {
                Button { onOpenCommandPalette() } label: {
                    Label("命令面板", systemImage: "keyboard")
                }
                .buttonStyle(IndexButtonStyle())
                .toolInteractionFeedback()

                Button {
                    withToolAnimation(ToolMotion.Preset.controlFeedback, reduceMotion: reduceMotion) {
                        isEditing.toggle()
                    }
                    showsLayoutEditor = true
                    onEditLayout()
                } label: {
                    Label("编辑卡片", systemImage: "gearshape")
                }
                .buttonStyle(IndexButtonStyle(primary: true))
                .toolInteractionFeedback()
            }
        }
        .accessibilityIdentifier("dashboard.header")
    }

    private var commandBox: some View {
        VStack(alignment: .leading, spacing: 0) {
            searchFieldRow
            searchResultsOverlay
        }.accessibilityIdentifier("dashboard.command-search")
    }

    private var searchFieldRow: some View {
        HStack(spacing: ToolMetrics.Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(isSearchFocused ? ToolTheme.accent : ToolTheme.textTertiary)
            TextField("搜索工具", text: $searchText)
                .textFieldStyle(.plain)
                .font(ToolTypography.bodyPlain)
                .focused($searchFieldFocused)
                .onChange(of: searchText) { _ in selectedSearchIndex = 0 }
                .onSubmit { openSelectedSearchResult() }
                .onMoveCommand { direction in
                    switch direction {
                    case .up: moveSearchSelection(-1)
                    case .down: moveSearchSelection(1)
                    default: break
                    }
                }
            Spacer(minLength: ToolMetrics.Spacing.xs)
            Text("⌘K")
                .font(ToolTypography.tagMicro)
                .foregroundStyle(ToolTheme.textTertiary)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(ToolTheme.utilityBackground, in: RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.nestedControl, style: .continuous))
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .indexSurface(.field, fill: ToolTheme.panelBackground, border: isSearchFocused ? ToolTheme.accentBorder : ToolTheme.border, borderWidth: isSearchFocused ? 1.2 : 0.5)
        .onChange(of: searchFieldFocused) { focused in isSearchFocused = focused }
    }

    @ViewBuilder
    private var searchResultsOverlay: some View {
        if isSearchFocused, !searchText.isEmpty, let registry {
            let entries = Array(searchProjection?.commandPaletteEntries.prefix(6) ?? [])
                .compactMap { registry.tool(for: $0.toolID).map { ($0, $0.categoryID) } }
            VStack(spacing: ToolMetrics.Spacing.xs) {
                if entries.isEmpty {
                    HStack {
                        Text("没有匹配工具").foregroundStyle(ToolTheme.textSecondary)
                        Spacer()
                        Button("打开命令面板", action: onOpenCommandPalette)
                            .buttonStyle(IndexSmallButtonStyle())
                    }
                    .font(ToolTypography.compactBody)
                    .padding(ToolMetrics.Spacing.md)
                } else {
                    ForEach(Array(entries.enumerated()), id: \.offset) { index, pair in
                        searchResultRow(index: index, tool: pair.0, categoryID: pair.1, registry: registry)
                    }
                }
            }
            .padding(5)
            .background(ToolTheme.panelBackground, in: RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.control, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.control, style: .continuous).stroke(ToolTheme.border))
            .toolShadow(ToolTheme.Shadow.floating)
            .transition(reduceMotion ? .identity : .opacity.combined(with: .move(edge: .top)))
        }
    }

    private func searchResultRow(
        index: Int,
        tool: RegisteredTool,
        categoryID: ToolCategoryID,
        registry: ToolRegistry
    ) -> some View {
        IndexSelectableRow(
            isSelected: index == selectedSearchIndex,
            action: {
                onSelectTool(tool.id)
                searchFieldFocused = false
                searchText = ""
            }
        ) {
            HStack(spacing: ToolMetrics.Spacing.sm) {
                Image(systemName: tool.systemImage)
                    .frame(width: 20)
                    .foregroundStyle(ToolTheme.accent)
                VStack(alignment: .leading, spacing: ToolMetrics.Spacing.xs) {
                    Text(tool.title)
                        .font(ToolTypography.bodyMedium)
                        .foregroundStyle(ToolTheme.textPrimary)
                    Text(registry.categoryTitle(for: categoryID) ?? "工具")
                        .font(ToolTypography.caption)
                        .foregroundStyle(ToolTheme.textTertiary)
                }
                Spacer()
            }
        }
        .accessibilityIdentifier("dashboard.search.result.\(index)")
    }

    private func cardGrid(compact: Bool) -> some View {
        DashboardWaterfallLayout(collapseWidth: 720) {
            ForEach(cards) { card in
                DashboardCardView(card: card, onOpenCard: { onOpenCard(card.id) }, onOpenTool: onSelectTool, onOpenCommandPalette: onOpenCommandPalette)
                    .layoutValue(key: DashboardCardSpanKey.self, value: card.size)
                    .accessibilityIdentifier("dashboard.card.\(card.id)")
            }
        }
        // v3 cardResize: span/order/visibility edits replay the waterfall as
        // one continuous settle; the custom Layout interpolates placements
        // inside the animation transaction. Keyed on card content so page
        // entry never animates.
        .toolAnimation(ToolMotion.Preset.settle, value: cards)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
    private var emptyState: some View { VStack(alignment: .leading, spacing: 12) { Image(systemName: "arrow.right.circle").font(.system(size: ToolMetrics.IconSize.display, weight: .medium)).foregroundStyle(ToolTheme.accent); Text("从一个动作开始").font(ToolTypography.sectionHeader).foregroundStyle(ToolTheme.textPrimary); Text("搜索工具或打开命令面板。使用后，收藏、最近使用和活动趋势会自动出现在这里。").font(ToolTypography.bodyPlain).foregroundStyle(ToolTheme.textSecondary); Button("打开命令面板", action: onOpenCommandPalette).buttonStyle(IndexButtonStyle(primary: true)).toolInteractionFeedback() }.padding(24).frame(maxWidth: .infinity, alignment: .leading).indexSurface(.modal) }
    private var privacyNote: some View { Label("活动统计仅保存在本机，不记录输入、输出、文件或剪贴板内容。", systemImage: "lock.shield").font(ToolTypography.caption).foregroundStyle(ToolTheme.textTertiary) }
    private var searchProjection: ToolNavigationProjection? { registry.map { ToolNavigationProjection(registry: $0, favoriteIDs: [], selectedToolID: nil, query: searchText) } }
    private func moveSearchSelection(_ offset: Int) { let count = min(searchProjection?.commandPaletteEntries.count ?? 0, 6); guard count > 0 else { return }; selectedSearchIndex = (selectedSearchIndex + offset + count) % count }
    private func openSelectedSearchResult() { guard let entry = searchProjection?.commandPaletteEntries.dropFirst(selectedSearchIndex).first else { onOpenCommandPalette(); return }; onSelectTool(entry.toolID); searchText = ""; searchFieldFocused = false }
}

extension DashboardView {
    @MainActor init(store: DashboardStore, registry: ToolRegistry, favoriteIDs: [ToolID] = [], onSelectTool: @escaping (ToolID) -> Void = { _ in }, onOpenCommandPalette: @escaping () -> Void = {}, onEditLayout: @escaping () -> Void = {}, autoResumeLastTool: Bool = false, onSetAutoResumeLastTool: @escaping @MainActor @Sendable (Bool) -> Void = { _ in }) {
        let known = Set(registry.categoryGroups().flatMap { $0.tools.map(\.id) })
        let recent = store.recentTools(knownToolIDs: known).compactMap { item in registry.tool(for: item.toolID).map { DashboardCardContent.ToolItem(id: $0.id, title: $0.title, systemImage: $0.systemImage, subtitle: registry.categoryTitle(for: $0.categoryID) ?? "工具", launchCount: item.launchCount) } }
        let favorites = registry.tools(for: favoriteIDs).map { DashboardCardContent.ToolItem(id: $0.id, title: $0.title, systemImage: $0.systemImage, subtitle: registry.categoryTitle(for: $0.categoryID) ?? "工具") }
        let trend = store.activityDays.map(\.launchCount)
        let categories = registry.categoryGroups().compactMap { group -> DashboardCardContent.CategoryItem? in let ids = Set(group.tools.map(\.id)); let count = store.preferences.activity.filter { ids.contains($0.toolID) }.reduce(0) { $0 + $1.count }; guard count > 0 else { return nil }; return .init(id: group.category.id.rawValue, title: group.category.title, systemImage: group.category.systemImage, count: count) }.sorted { $0.count > $1.count }
        let mapped = store.cards.map { layout -> DashboardCardContent in let kind = layout.kind; let size: DashboardCardContent.Size = layout.span == .small ? .small : (layout.span == .large ? .large : .medium); switch kind { case .continueWork: return .init(id: kind.rawValue, title: "继续工作", subtitle: recent.first?.title ?? "还没有最近使用记录", systemImage: recent.first?.systemImage ?? "arrow.right.circle", value: recent.isEmpty ? nil : "继续打开", size: size, detail: recent.first.map { "\($0.subtitle) · 工具切换 \($0.launchCount) 次" }, tools: Array(recent.prefix(1)), action: recent.first.map { .openTool($0.id) } ?? .openCommandPalette); case .activityOverview: let today = store.activityDays.last; return .init(id: kind.rawValue, title: "今日概览", subtitle: "本地日历 · 最近 90 天", systemImage: "chart.bar.doc.horizontal", value: "\(today?.launchCount ?? 0)", size: size, detail: "工具切换 · 活跃 \(today?.activeToolCount ?? 0) 个工具"); case .sevenDayTrend: return .init(id: kind.rawValue, title: "七日趋势", subtitle: "最近 7 天工具切换", systemImage: "chart.bar.doc.horizontal", value: "\(trend.reduce(0, +))", size: size, trend: trend); case .favorites: return .init(id: kind.rawValue, title: "收藏工具", subtitle: favorites.isEmpty ? "收藏常用工具，快速回来" : "\(favorites.count) 个工具", systemImage: "star.fill", size: size, tools: favorites, action: favorites.first.map { .openTool($0.id) }); case .recent: return .init(id: kind.rawValue, title: "最近使用", subtitle: recent.first?.title ?? "暂无记录", systemImage: "arrow.clockwise", size: size, tools: Array(recent.prefix(4)), action: recent.first.map { .openTool($0.id) }); case .quickActions: return .init(id: kind.rawValue, title: "快捷动作", subtitle: "搜索全部工具和动作", systemImage: "lightbulb", size: size, action: .openCommandPalette); case .categoryHighlights: return .init(id: kind.rawValue, title: "分类脉冲", subtitle: categories.isEmpty ? "开始使用工具后显示" : "按工具切换次数排序", systemImage: "square.grid.3x3", size: size, categories: Array(categories.prefix(4))) } }
        self.init(cards: mapped, onOpenCard: { id in if id == DashboardCardKind.quickActions.rawValue { onOpenCommandPalette(); return }; let target = id == DashboardCardKind.favorites.rawValue ? favorites.first?.id : (id == DashboardCardKind.continueWork.rawValue || id == DashboardCardKind.recent.rawValue ? recent.first?.id : nil); if let target { onSelectTool(target) } }, onSelectTool: onSelectTool, onOpenCommandPalette: onOpenCommandPalette, onEditLayout: onEditLayout, layoutStore: store, registry: registry, autoResumeLastTool: autoResumeLastTool, onSetAutoResumeLastTool: onSetAutoResumeLastTool)
    }
}

@MainActor private struct DashboardLayoutEditor: View {
    @ObservedObject var store: DashboardStore; let autoResumeLastTool: Bool; let onSetAutoResumeLastTool: @MainActor @Sendable (Bool) -> Void
    @Environment(\.dismiss) private var dismiss; @State private var query = ""
    private var visibleCards: [DashboardCardLayout] { store.preferences.cards.sorted { $0.sortOrder < $1.sortOrder } }
    private var filteredKinds: [DashboardCardKind] { DashboardCardKind.allCases.filter { title(for: $0).localizedCaseInsensitiveContains(query) } }
    var body: some View {
        VStack(alignment: .leading, spacing: ToolMetrics.Spacing.lg) {
            header
            Label("布局和活动统计仅保存在本机", systemImage: "lock.shield")
                .font(ToolTypography.caption)
                .foregroundStyle(ToolTheme.textTertiary)
            IndexSwitch(title: "启动时继续上次使用的工具", isOn: Binding(get: { autoResumeLastTool }, set: onSetAutoResumeLastTool))
            searchField
            ScrollView {
                VStack(alignment: .leading, spacing: ToolMetrics.Spacing.lg) {
                    sectionLabel("当前布局")
                    VStack(spacing: ToolMetrics.Spacing.xs) {
                        ForEach(visibleCards) { card in cardRow(card) }
                    }
                    if !query.isEmpty {
                        let hidden = filteredKinds.filter { kind in !visibleCards.contains(where: { $0.kind == kind && $0.isVisible }) }
                        if !hidden.isEmpty {
                            sectionLabel("添加卡片")
                            VStack(spacing: ToolMetrics.Spacing.xs) {
                                ForEach(hidden) { kind in
                                    Button {
                                        store.updateCard(kind: kind, isVisible: true)
                                        query = ""
                                    } label: {
                                        Label(title(for: kind), systemImage: icon(for: kind))
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .buttonStyle(IndexSmallButtonStyle())
                                }
                            }
                        }
                    }
                }
            }
            .scrollIndicators(.automatic)
            .indexSurface(.card, fill: ToolTheme.editorBackground, border: ToolTheme.border)
        }
        .padding(ToolMetrics.Spacing.xl)
        .frame(width: 650, height: 520)
        .background(ToolTheme.workspaceBackground)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: ToolMetrics.Spacing.md) {
            VStack(alignment: .leading, spacing: 3) {
                Text("编辑工作台").font(ToolTypography.sectionHeader).foregroundStyle(ToolTheme.textPrimary)
                Text("排序、尺寸和显隐会即时保存在本机").font(ToolTypography.compactBody).foregroundStyle(ToolTheme.textSecondary)
            }
            Spacer()
            Button("恢复默认") { store.resetLayout() }
                .buttonStyle(IndexSmallButtonStyle())
            Button("完成") { dismiss() }
                .buttonStyle(IndexButtonStyle(primary: true))
                .keyboardShortcut(.defaultAction)
        }
    }

    private var searchField: some View {
        HStack(spacing: ToolMetrics.Spacing.sm) {
            Image(systemName: "magnifyingglass").foregroundStyle(ToolTheme.textTertiary)
            TextField("搜索并添加隐藏卡片", text: $query)
                .textFieldStyle(.plain)
                .font(ToolTypography.bodyPlain)
            if !query.isEmpty {
                Button { query = "" } label: { Image(systemName: IndexActionSymbol.searchClear) }
                    .buttonStyle(IndexBareButtonStyle())
                    .foregroundStyle(ToolTheme.textTertiary)
            }
        }
        .padding(.horizontal, ToolMetrics.Spacing.md)
        .frame(height: 34)
        .indexSurface(.field, fill: ToolTheme.panelBackground, border: ToolTheme.border)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased()).font(ToolTypography.tagMicro).foregroundStyle(ToolTheme.textTertiary)
    }

    private func cardRow(_ card: DashboardCardLayout) -> some View {
        HStack(spacing: ToolMetrics.Spacing.md) {
            Image(systemName: icon(for: card.kind)).frame(width: 20).foregroundStyle(ToolTheme.accent)
            IndexSwitch(title: title(for: card.kind), isOn: Binding(get: { card.isVisible }, set: { value in
                if visibleCards.filter(\.isVisible).count > 1 || value { store.updateCard(kind: card.kind, isVisible: value) }
            }))
            Spacer(minLength: ToolMetrics.Spacing.sm)
            IndexSegmentedControl(items: [(DashboardCardSpan.small.rawValue, "小"), (DashboardCardSpan.medium.rawValue, "中"), (DashboardCardSpan.large.rawValue, "大")], selection: Binding(get: { card.span.rawValue }, set: { value in guard let span = DashboardCardSpan(rawValue: value) else { return }; store.updateCard(kind: card.kind, span: span) }), density: .compact)
            Button { move(card, offset: -1) } label: { Image(systemName: "chevron.up") }
                .buttonStyle(IndexBareButtonStyle()).disabled(card == visibleCards.first)
                .accessibilityLabel("上移 \(title(for: card.kind))")
            Button { move(card, offset: 1) } label: { Image(systemName: "chevron.down") }
                .buttonStyle(IndexBareButtonStyle()).disabled(card == visibleCards.last)
                .accessibilityLabel("下移 \(title(for: card.kind))")
        }
        .padding(.horizontal, ToolMetrics.Spacing.md)
        .frame(minHeight: 44)
        .background(ToolTheme.panelBackground, in: RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.control, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.control, style: .continuous).strokeBorder(ToolTheme.border, lineWidth: 0.5) }
    }
    private func move(_ card: DashboardCardLayout, offset: Int) { var items = visibleCards; guard let index = items.firstIndex(where: { $0.kind == card.kind }), items.indices.contains(index + offset) else { return }; items.swapAt(index, index + offset); store.setCards(items) }
    private func title(for kind: DashboardCardKind) -> String { [.continueWork:"继续工作", .activityOverview:"今日概览", .sevenDayTrend:"七日趋势", .favorites:"收藏工具", .recent:"最近使用", .quickActions:"快捷动作", .categoryHighlights:"分类脉冲"][kind] ?? kind.rawValue }
    private func icon(for kind: DashboardCardKind) -> String { [.continueWork:"arrow.right.circle", .activityOverview:"chart.bar.doc.horizontal", .sevenDayTrend:"chart.bar.doc.horizontal", .favorites:"star", .recent:"arrow.clockwise", .quickActions:"lightbulb", .categoryHighlights:"square.grid.3x3"][kind] ?? "square" }
}

private struct DashboardCardView: View {
    let card: DashboardCardContent; let onOpenCard: () -> Void; let onOpenTool: (ToolID) -> Void; let onOpenCommandPalette: () -> Void
    var body: some View { VStack(alignment: .leading, spacing: ToolMetrics.Spacing.md) { titleRow; if card.id == DashboardCardKind.continueWork.rawValue { continueContent } else if card.id == DashboardCardKind.activityOverview.rawValue { overviewContent } else if !card.trend.isEmpty { TrendBars(values: card.trend, tint: card.tint).frame(height: 80); metricFooter } else if !card.tools.isEmpty { toolList } else if !card.categories.isEmpty { categoryList } else { Text(card.subtitle).font(ToolTypography.bodyPlain).foregroundStyle(ToolTheme.textSecondary); if let detail = card.detail { Text(detail).font(ToolTypography.caption).foregroundStyle(ToolTheme.textTertiary) } } }.padding(card.id == DashboardCardKind.continueWork.rawValue ? ToolMetrics.Spacing.xl : ToolMetrics.Spacing.lg).frame(maxWidth: .infinity, minHeight: card.size == .small ? 112 : (card.id == DashboardCardKind.continueWork.rawValue ? 176 : 148), alignment: .topLeading).indexSurface(.card, fill: card.id == DashboardCardKind.continueWork.rawValue ? ToolTheme.selectionFill : ToolTheme.panelBackground, border: card.id == DashboardCardKind.continueWork.rawValue ? ToolTheme.accentBorder : ToolTheme.border) }
    @ViewBuilder private var titleRow: some View { if let action = card.action { IndexSelectableRow(action: { perform(action) }) { titleLabel }.accessibilityLabel("打开 \(card.title)") } else { titleLabel.accessibilityAddTraits(.isHeader) } }
    private var titleLabel: some View { HStack(spacing: ToolMetrics.Spacing.sm) { Image(systemName: card.systemImage).foregroundStyle(card.tint); Text(card.title).font(ToolTypography.panelTitleProminent).foregroundStyle(ToolTheme.textPrimary); Spacer(); if card.action != nil { Image(systemName: "chevron.right").font(ToolTypography.caption).foregroundStyle(ToolTheme.textTertiary) } } }
    private func perform(_ action: DashboardCardContent.Action) { switch action { case .openCard: onOpenCard(); case .openTool(let id): onOpenTool(id); case .openCommandPalette: onOpenCommandPalette() } }
    @ViewBuilder private var continueContent: some View { HStack(spacing: 13) { ZStack { Circle().fill(ToolTheme.accent); Image(systemName: card.tools.first?.systemImage ?? card.systemImage).font(.system(size: ToolMetrics.IconSize.display, weight: .medium)).foregroundStyle(ToolTheme.onAccent) }.frame(width: 48, height: 48); VStack(alignment: .leading, spacing: 4) { Text(card.tools.first?.subtitle ?? "准备探索工具").font(ToolTypography.caption).foregroundStyle(ToolTheme.textSecondary); Text(card.subtitle).font(ToolTypography.sectionHeader).foregroundStyle(ToolTheme.textPrimary); Text(card.detail ?? "搜索一个工具开始").font(ToolTypography.compactBody).foregroundStyle(ToolTheme.textSecondary) }; Spacer(minLength: 8); if let item = card.tools.first { Button(card.value ?? "继续打开") { onOpenTool(item.id) }.buttonStyle(IndexButtonStyle(primary: true)).toolInteractionFeedback() } else { Button("开始搜索", action: onOpenCommandPalette).buttonStyle(IndexButtonStyle(primary: true)).toolInteractionFeedback() } } }
    @ViewBuilder private var overviewContent: some View { HStack(alignment: .lastTextBaseline, spacing: 9) { Text(card.value ?? "0").font(ToolTypography.heroValue(design: .rounded)).foregroundStyle(ToolTheme.textPrimary); Text(card.detail ?? "").font(ToolTypography.caption).foregroundStyle(ToolTheme.textSecondary) }; Text(card.subtitle).font(ToolTypography.caption).foregroundStyle(ToolTheme.textTertiary) }
    @ViewBuilder private var metricFooter: some View { HStack { Text(card.subtitle).font(ToolTypography.caption).foregroundStyle(ToolTheme.textSecondary); Spacer(); Text(card.value ?? "0").font(ToolTypography.monoValueMedium).foregroundStyle(ToolTheme.textPrimary) } }
    @ViewBuilder private var toolList: some View { VStack(spacing: ToolMetrics.Spacing.xs) { ForEach(card.tools.prefix(card.size == .small ? 2 : 4)) { item in IndexSelectableRow(action: { onOpenTool(item.id) }) { HStack(spacing: 9) { Image(systemName: item.systemImage).frame(width: 18).foregroundStyle(ToolTheme.accent); VStack(alignment: .leading, spacing: 2) { Text(item.title).lineLimit(1); if !item.subtitle.isEmpty { Text(item.subtitle).font(ToolTypography.caption).foregroundStyle(ToolTheme.textTertiary) } }; Spacer(); if item.launchCount > 0 { Text("\(item.launchCount)").font(ToolTypography.tagMicro).foregroundStyle(ToolTheme.textTertiary) }; Image(systemName: "chevron.right").font(ToolTypography.caption).foregroundStyle(ToolTheme.textTertiary) } }.font(ToolTypography.bodyPlain).foregroundStyle(ToolTheme.textPrimary).accessibilityLabel("打开 \(item.title)" ) } } }
    @ViewBuilder private var categoryList: some View { VStack(spacing: 5) { ForEach(card.categories) { item in HStack(spacing: 9) { Image(systemName: item.systemImage).frame(width: 18).foregroundStyle(card.tint); Text(item.title).font(ToolTypography.bodyPlain).foregroundStyle(ToolTheme.textPrimary); Spacer(); Text("\(item.count)").font(ToolTypography.monoValueSmall).foregroundStyle(ToolTheme.textSecondary) } } } }
}

private struct TrendBars: View { let values: [Int]; let tint: Color; var body: some View { GeometryReader { proxy in let maxValue = max(values.max() ?? 1, 1); HStack(alignment: .bottom, spacing: 7) { ForEach(Array(values.enumerated()), id: \.offset) { index, value in VStack(spacing: 4) { Spacer(minLength: 0); Capsule().fill(index == values.count - 1 ? tint : tint.opacity(0.42)).frame(height: max(4, proxy.size.height * CGFloat(value) / CGFloat(maxValue))); Text(index == values.count - 1 ? "今" : "\(index + 1)").font(ToolTypography.micro).foregroundStyle(ToolTheme.textTertiary) } } } }.accessibilityLabel("最近七日趋势：\(values.map(String.init).joined(separator: "、"))") } }
