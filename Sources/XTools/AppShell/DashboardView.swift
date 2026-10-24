import SwiftUI
import XToolsDesign

/// 工作台首页（Cmd+0）。Raycast Home 式卡片流：继续工作 / 收藏 / 最近打开 /
/// 分类 / 全部工具。所有区块复用共享组件与 `ToolMotion` 动效。
///
/// 动效原则：工作台是"一眼可扫、立即点"的入口页，**不做逐卡入场动画**——
/// 每次从工具页切回都会重新挂载，逐卡淡入会读成"闪烁"。hover 只做表面色
/// 平滑过渡，不做位移/缩放。
@MainActor
struct DashboardView: View {
    /// `store` 用 let 而非 @ObservedObject：最近打开/frecency 数据只在进入
    /// 工作台时刷新一次即可，不需要订阅每次 recordLaunch（切换工具）的变化。
    /// 否则停靠中的工作台会在每次切工具时跟着重估，拖慢切页热路径。
    /// `favorites` 必须 @ObservedObject：工作台内点击收藏星要实时增删。
    let store: DashboardStore
    @ObservedObject var favorites: FavoritesStore
    let registry: ToolRegistry
    /// Smart Detection「为你建议」（D2）：与 ⌘K 落地页同源的一条，紧随
    /// 「继续工作」卡。nil = 无建议（不占位）。
    let clipboardSuggestion: ClipboardSuggestionModel.Suggestion?
    let routing: any DetailActionRouting

    /// 进入工作台时自增，强制 body 重估一次读最新 store 数据（最近打开/
    /// frecency）。store 用 let 不订阅，靠这个 token 在 onAppear 刷新。
    @State private var refreshToken = 0

    /// 最近打开展示上限（不含"继续工作"那张卡）。
    private let recentLimit = 5
    /// 快捷工具（frecency 动态）展示上限。
    private let shortcutLimit = 5

    var body: some View {
        // refreshToken 参与 body 依赖：onAppear 自增时重估读最新 store。
        let _ = refreshToken
        // 一次计算全部派生数据，body 内多处引用不再各自重算。
        // knownToolIDs 也只算一次。
        let snapshot = computeSnapshot()

        ScrollView {
            VStack(alignment: .leading, spacing: ToolMetrics.Spacing.lg) {
                pageHeader

                if let resume = snapshot.continueTool {
                    resumeCard(resume)
                }

                // 「为你建议」（D2）：剪贴板类型判定命中时的同源一条。
                if let suggestion = clipboardSuggestion {
                    clipboardSuggestionCard(suggestion)
                }

                // 收藏 / 快捷 / 最近：一张卡内的三个 section，瓷砖两列布局，
                // 同屏可见条目数是单列行的两倍以上。
                if !snapshot.favoriteTools.isEmpty || !snapshot.shortcutTools.isEmpty || !snapshot.recentTools.isEmpty {
                    DashboardCard(title: "工具", detail: "收藏 · 常用 · 最近") {
                        VStack(alignment: .leading, spacing: ToolMetrics.Spacing.md) {
                            if !snapshot.favoriteTools.isEmpty {
                                tileSection(title: "收藏", tools: snapshot.favoriteTools, detail: { _ in nil })
                            }
                            if !snapshot.shortcutTools.isEmpty {
                                tileSection(title: "常用", tools: snapshot.shortcutTools, detail: { _ in nil })
                            }
                            if !snapshot.recentTools.isEmpty {
                                tileSection(title: "最近", tools: snapshot.recentTools.map(\.tool), detail: { id in
                                    snapshot.recentTools.first { $0.tool.id == id }.map { "上次使用 \($0.lastOpenedAt.relativeText())" }
                                })
                            }
                        }
                    }
                }

                DashboardCard(title: "分类", detail: "\(registry.categoryGroups().count) 个分类") {
                    categoryGrid
                }

                DashboardCard(title: nil, detail: nil) {
                    allToolsRow
                }
            }
            .frame(maxWidth: ToolMetrics.Workbench.mainMaxWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .top)
            .padding(.horizontal, ToolMetrics.Workbench.horizontalInset)
            .padding(.top, ToolMetrics.Spacing.lg)
            .padding(.bottom, ToolMetrics.Spacing.xxxl)
        }
        .background(ToolTheme.Workbench.canvas)
        .onAppear {
            // 回访工作台时读一次最新 store（最近打开/frecency 随切换更新）。
            refreshToken += 1
        }
    }

    /// 一个瓷砖 section：小节标题 + 两列瓷砖网格。
    private func tileSection(
        title: String,
        tools: [RegisteredTool],
        detail: @escaping (ToolID) -> String?
    ) -> some View {
        VStack(alignment: .leading, spacing: ToolMetrics.Spacing.sm) {
            Text(title)
                .font(ToolTypography.Workbench.caption)
                .foregroundStyle(ToolTheme.Workbench.textFaint)
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: ToolMetrics.Spacing.sm), GridItem(.flexible(), spacing: ToolMetrics.Spacing.sm)],
                alignment: .leading,
                spacing: ToolMetrics.Spacing.sm
            ) {
                ForEach(tools) { tool in
                    DashboardTile(
                        tool: tool,
                        detail: detail(tool.id),
                        isFavorite: isFavorite(tool.id)
                    ) {
                        routing.selectTool(tool.id)
                    } onToggleFavorite: {
                        _ = routing.toggleFavorite(tool.id)
                    }
                }
            }
        }
    }

    // MARK: - 继续工作大卡片

    private func resumeCard(_ item: RecentItem) -> some View {
        Button {
            routing.selectTool(item.tool.id)
        } label: {
            HStack(spacing: ToolMetrics.Spacing.md) {
                Image(systemName: item.tool.systemImage)
                    .font(ToolTypography.icon(ToolMetrics.IconSize.display, .medium))
                    .foregroundStyle(ToolTheme.accent)
                    .frame(width: 40, height: 40)
                    .background(
                        ToolTheme.selectionFill,
                        in: RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.control, style: .continuous)
                    )

                VStack(alignment: .leading, spacing: ToolMetrics.Spacing.xxs) {
                    Text("继续工作")
                        .font(ToolTypography.Workbench.caption)
                        .foregroundStyle(ToolTheme.Workbench.textFaint)
                    Text(item.tool.title)
                        .font(ToolTypography.Workbench.title)
                        .foregroundStyle(ToolTheme.Workbench.textPrimary)
                        .lineLimit(1)
                    Text("上次使用 \(relativeTime(for: item.lastOpenedAt))")
                        .font(ToolTypography.Workbench.caption)
                        .foregroundStyle(ToolTheme.Workbench.textSecondary)
                }

                Spacer(minLength: 0)

                // 「继续」强调件与 IndexButtonStyle(primary) 同配方
                //（design-foundation C6：bodyMedium 字号、md 水平内距、
                // Control.regular 高、field 圆角、onAccent 前景）。整卡是
                // 唯一命中钮（嵌套 Button 的命中/无障碍行为有歧义，见
                // SidebarToolRow 先例），故此处复刻配方而非嵌套按钮。
                HStack(spacing: ToolMetrics.Spacing.sm) {
                    Text("继续")
                        .font(ToolTypography.bodyMedium)
                        .foregroundStyle(ToolTheme.onAccent)
                    Image(systemName: "arrow.right")
                        .font(ToolTypography.icon(ToolMetrics.IconSize.medium, .medium))
                        .foregroundStyle(ToolTheme.onAccent)
                }
                .labelStyle(.titleAndIcon)
                .padding(.horizontal, ToolMetrics.Spacing.md)
                .frame(height: ToolMetrics.Control.regular)
                .background(ToolTheme.accent, in: RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.field, style: .continuous))
            }
            .padding(ToolMetrics.Spacing.md)
            .contentShape(Rectangle())
        }
        .buttonStyle(IndexQuietChromeStyle(look: .bare))
        .indexRowHoverBackground(
            true,
            color: ToolTheme.Workbench.surface,
            cornerRadius: ToolMetrics.Workbench.groupCorner
        )
        .overlay {
            RoundedRectangle(cornerRadius: ToolMetrics.Workbench.groupCorner, style: .continuous)
                .strokeBorder(ToolTheme.Workbench.border, lineWidth: 1)
        }
        .accessibilityLabel("继续使用\(item.tool.title)")
        .accessibilityIdentifier("dashboard.resume.\(item.tool.id.rawValue)")
    }

    // MARK: - Smart Detection 建议卡（D2）

    /// 「为你建议」单条：剪贴板类型判定 → 对应工具 + 类型文案；点击 =
    /// 打开工具并经 SmartPaste 通道预填。样式对齐 resumeCard 配方
    /// （quiet chrome + hover 面 + 1pt 描边），尺寸收敛为单行条。
    private func clipboardSuggestionCard(
        _ suggestion: ClipboardSuggestionModel.Suggestion
    ) -> some View {
        Button {
            routing.openClipboardSuggestion(suggestion)
        } label: {
            HStack(spacing: ToolMetrics.Spacing.md) {
                Image(systemName: "lightbulb")
                    .font(ToolTypography.icon(ToolMetrics.IconSize.display, .medium))
                    .foregroundStyle(ToolTheme.accent)
                    .frame(width: 40, height: 40)
                    .background(
                        ToolTheme.selectionFill,
                        in: RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.control, style: .continuous)
                    )

                VStack(alignment: .leading, spacing: ToolMetrics.Spacing.xxs) {
                    Text("为你建议")
                        .font(ToolTypography.Workbench.caption)
                        .foregroundStyle(ToolTheme.Workbench.textFaint)
                    Text(suggestion.message)
                        .font(ToolTypography.Workbench.title)
                        .foregroundStyle(ToolTheme.Workbench.textPrimary)
                        .lineLimit(1)
                    Text("打开\(suggestion.toolTitle)处理")
                        .font(ToolTypography.Workbench.caption)
                        .foregroundStyle(ToolTheme.Workbench.textSecondary)
                }

                Spacer(minLength: 0)

                HStack(spacing: ToolMetrics.Spacing.sm) {
                    Text("打开")
                        .font(ToolTypography.bodyMedium)
                        .foregroundStyle(ToolTheme.onAccent)
                    Image(systemName: "arrow.right")
                        .font(ToolTypography.icon(ToolMetrics.IconSize.medium, .medium))
                        .foregroundStyle(ToolTheme.onAccent)
                }
                .labelStyle(.titleAndIcon)
                .padding(.horizontal, ToolMetrics.Spacing.md)
                .frame(height: ToolMetrics.Control.regular)
                .background(ToolTheme.accent, in: RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.field, style: .continuous))
            }
            .padding(ToolMetrics.Spacing.md)
            .contentShape(Rectangle())
        }
        .buttonStyle(IndexQuietChromeStyle(look: .bare))
        .indexRowHoverBackground(
            true,
            color: ToolTheme.Workbench.surface,
            cornerRadius: ToolMetrics.Workbench.groupCorner
        )
        .overlay {
            RoundedRectangle(cornerRadius: ToolMetrics.Workbench.groupCorner, style: .continuous)
                .strokeBorder(ToolTheme.Workbench.border, lineWidth: 1)
        }
        .accessibilityLabel("\(suggestion.message)，可以打开\(suggestion.toolTitle)")
        .accessibilityIdentifier("dashboard.clipboardSuggestion.\(suggestion.kind.rawValue)")
    }

    // MARK: - 页头

    private var pageHeader: some View {
        HStack(alignment: .top, spacing: ToolMetrics.Spacing.xxxl) {
            VStack(alignment: .leading, spacing: ToolMetrics.Spacing.fine) {
                Text("工作台")
                    .font(ToolTypography.Workbench.title)
                    .foregroundStyle(ToolTheme.Workbench.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Text("\(greetingText) · 打开常用工具，或按 ⌘K 搜索全部工具。")
                    .font(ToolTypography.Workbench.subtitle)
                    .foregroundStyle(ToolTheme.Workbench.textSecondary)
            }

            Spacer(minLength: 12)

            // 日期用 TimelineView 每 60s 重估，避免取一次后过时。
            TimelineView(.periodic(from: Date(), by: 60)) { context in
                Text(Self.headerDateFormatter.string(from: context.date))
                    .font(ToolTypography.Workbench.caption)
                    .foregroundStyle(ToolTheme.Workbench.textFaint)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
        .padding(.bottom, ToolMetrics.Spacing.lg)
    }

    private var greetingText: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<11: return "早安，开发者"
        case 11..<13: return "午安，开发者"
        case 13..<18: return "下午好，开发者"
        case 18..<24: return "晚上好，开发者"
        default: return "夜深了，开发者"
        }
    }

    // MARK: - 分类网格

    private var categoryGrid: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 160), spacing: ToolMetrics.Spacing.sm)],
            alignment: .leading,
            spacing: ToolMetrics.Spacing.sm
        ) {
            ForEach(registry.categoryGroups(), id: \.category.id) { group in
                Button {
                    if let firstTool = group.tools.first {
                        routing.selectTool(firstTool.id)
                    }
                } label: {
                    HStack(spacing: ToolMetrics.Spacing.sm) {
                        Image(systemName: group.category.systemImage)
                            .font(ToolTypography.Workbench.icon)
                            .foregroundStyle(ToolTheme.Workbench.textSecondary)
                            .frame(width: 22)
                        Text(group.category.title)
                            .font(ToolTypography.Workbench.body.weight(.medium))
                            .foregroundStyle(ToolTheme.Workbench.textPrimary)
                        Spacer(minLength: 0)
                        Text("\(group.tools.count)")
                            .font(ToolTypography.Workbench.caption)
                            .foregroundStyle(ToolTheme.Workbench.textFaint)
                    }
                    .padding(.horizontal, ToolMetrics.Spacing.md)
                    .frame(height: ToolMetrics.Control.row)
                    .contentShape(Rectangle())
                }
                .buttonStyle(IndexQuietChromeStyle(look: .bare))
                .background(ToolTheme.panelBackground, in: RoundedRectangle(cornerRadius: ToolMetrics.Workbench.compactCorner, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: ToolMetrics.Workbench.compactCorner, style: .continuous)
                        .strokeBorder(ToolTheme.Workbench.border, lineWidth: 1)
                }
                .toolInteractionFeedback()
                .accessibilityLabel("打开\(group.category.title)分类")
            }
        }
    }

    // MARK: - 全部工具

    private var allToolsRow: some View {
        Button {
            routing.openCommandPalette()
        } label: {
            HStack(spacing: ToolMetrics.Spacing.sm) {
                Image(systemName: "magnifyingglass")
                    .font(ToolTypography.Workbench.icon)
                    .foregroundStyle(ToolTheme.Workbench.textSecondary)
                Text("全部工具")
                    .font(ToolTypography.Workbench.body.weight(.medium))
                    .foregroundStyle(ToolTheme.Workbench.textPrimary)
                Spacer(minLength: 0)
                IndexKeycap(label: "⌘K")
            }
            .padding(.horizontal, ToolMetrics.Spacing.md)
            .frame(height: ToolMetrics.Control.row)
            .contentShape(Rectangle())
        }
        .buttonStyle(IndexQuietChromeStyle(look: .bare))
        .background(ToolTheme.panelBackground, in: RoundedRectangle(cornerRadius: ToolMetrics.Workbench.compactCorner, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: ToolMetrics.Workbench.compactCorner, style: .continuous)
                .strokeBorder(ToolTheme.Workbench.border, lineWidth: 1)
        }
        .toolInteractionFeedback()
        .accessibilityLabel("打开全部工具")
        .accessibilityHint("打开命令面板，快捷键 Command-K")
    }

    // MARK: - 数据投影

    private struct DashboardSnapshot {
        var continueTool: RecentItem?
        var favoriteTools: [RegisteredTool] = []
        var shortcutTools: [RegisteredTool] = []
        var recentTools: [RecentItem] = []
    }

    private struct RecentItem: Identifiable {
        let tool: RegisteredTool
        let lastOpenedAt: Date
        var id: ToolID { tool.id }
    }

    /// 一次性派生全部工作台数据：knownToolIDs 算一次，recent/frecency/favorite
    /// 各算一次。body 只读这个快照，避免每次 body 重估时多算 6+ 次。
    ///
    /// 收藏语义：收藏星只做标记，**不迁移工具位置**。工具停留在"最近/常用"
    /// 原区，星标变实心/空心；收藏区独立展示全部收藏。这样点击收藏星不会
    /// 让工具在区块间跳飞，避免布局跳动（成熟 app 的 pinned/recent 是独立
    /// 维度，允许同一工具同时出现）。
    private func computeSnapshot() -> DashboardSnapshot {
        let knownToolIDs = Set(registry.categoryGroups().flatMap { $0.tools.map(\.id) })

        let favoriteTools = favorites.favoriteIDs.compactMap { registry.tool(for: $0) }

        let allRecent = store.recentTools(knownToolIDs: knownToolIDs)
            .prefix(recentLimit + 1)
            .compactMap { recent in
                registry.tool(for: recent.toolID).map {
                    RecentItem(tool: $0, lastOpenedAt: recent.lastOpenedAt)
                }
            }

        let continueTool = allRecent.first
        // 只排除"继续工作"已展示的第一个，不排除收藏（收藏留在原区）。
        let recentTools = allRecent.dropFirst()

        let shortcutTools = store.frecencyRankedToolIDs(
            knownToolIDs: knownToolIDs,
            limit: shortcutLimit + (continueTool.map { _ in 1 } ?? 0)
        )
        .compactMap { registry.tool(for: $0) }
        .filter { $0.id != continueTool?.tool.id }
        .prefix(shortcutLimit)
        .map { $0 }

        return DashboardSnapshot(
            continueTool: continueTool,
            favoriteTools: favoriteTools,
            shortcutTools: Array(shortcutTools),
            recentTools: Array(recentTools)
        )
    }

    private func isFavorite(_ toolID: ToolID) -> Bool {
        favorites.isFavorite(toolID)
    }

    private func relativeTime(for date: Date) -> String {
        WorkbenchRelativeTime.text(for: date)
    }

    @MainActor private static let headerDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "MMM d EEE"
        return formatter
    }()
}

// MARK: - 卡片壳

/// 工作台首页统一卡片：44pt 纸头 + hairline + 14pt 内边距 + panel 表面。
/// 所有区块共用同一壳，卡片有清晰视觉边界（区别于裸 VStack）。
private struct DashboardCard<Content: View>: View {
    let title: String?
    let detail: String?
    private let content: Content

    init(
        title: String?,
        detail: String?,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.detail = detail
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let title {
                HStack(alignment: .firstTextBaseline) {
                    Text(title)
                        .font(ToolTypography.Workbench.sectionTitle)
                        .foregroundStyle(ToolTheme.Workbench.textPrimary)
                    Spacer()
                    if let detail {
                        Text(detail)
                            .font(ToolTypography.Workbench.caption)
                            .foregroundStyle(ToolTheme.Workbench.textFaint)
                    }
                }
                .padding(.horizontal, ToolMetrics.Spacing.panelInset)
                .padding(.vertical, ToolMetrics.Spacing.sm)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(ToolTheme.Workbench.border)
                        .frame(height: ToolMetrics.Spacing.hairline)
                }
            }

            content
                .padding(.horizontal, ToolMetrics.Spacing.panelInset)
                .padding(.vertical, ToolMetrics.Spacing.sm)
        }
        .background(
            ToolTheme.Workbench.surface,
            in: RoundedRectangle(cornerRadius: ToolMetrics.Workbench.groupCorner, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: ToolMetrics.Workbench.groupCorner, style: .continuous)
                .strokeBorder(ToolTheme.Workbench.border, lineWidth: 1)
        }
    }
}

// MARK: - 工具瓷砖

/// 工作台工具瓷砖（Raycast Home 式双列网格单元）：图标 + 标题(+副行)，
/// 收藏星右上角独立命中。整块是单一 Button，hover 状态挂整块外层，
/// `withToolAnimation` 包状态 + opacity 插值背景——无嵌套抖动、无颜色硬切。
private struct DashboardTile: View {
    let tool: RegisteredTool
    let detail: String?
    let isFavorite: Bool
    let onOpen: () -> Void
    let onToggleFavorite: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: ToolMetrics.Spacing.sm) {
                Image(systemName: tool.systemImage)
                    .font(ToolTypography.Workbench.icon)
                    .foregroundStyle(ToolTheme.accent)
                    .frame(width: 28, height: 28)
                    .background(
                        ToolTheme.selectionFill,
                        in: RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.nestedControl, style: .continuous)
                    )

                VStack(alignment: .leading, spacing: ToolMetrics.Spacing.hair) {
                    Text(tool.title)
                        .font(ToolTypography.Workbench.body.weight(.semibold))
                        .foregroundStyle(ToolTheme.Workbench.textPrimary)
                        .lineLimit(1)
                    if let detail {
                        Text(detail)
                            .font(ToolTypography.Workbench.caption)
                            .foregroundStyle(ToolTheme.Workbench.textSecondary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.leading, ToolMetrics.Spacing.md)
            .padding(.trailing, ToolMetrics.Spacing.xxxl) // 给右上收藏星留独立命中区
            .frame(height: ToolMetrics.Control.thumb)
            .contentShape(Rectangle())
        }
        .buttonStyle(IndexQuietChromeStyle(look: .bare))
        .accessibilityLabel("打开\(tool.title)")
        .overlay(alignment: .topTrailing) {
            IndexFavoriteButton(isFavorite: isFavorite, density: .compact) {
                onToggleFavorite()
            }
            .padding(.top, ToolMetrics.Spacing.fine)
            .padding(.trailing, ToolMetrics.Spacing.fine)
        }
        .indexRowHoverBackground(
            isHovering,
            color: ToolTheme.hoverFill,
            cornerRadius: ToolMetrics.Workbench.compactCorner
        )
        .onHover { hovering in
            withToolAnimation(ToolMotion.Preset.controlFeedback) {
                isHovering = hovering
            }
        }
        .accessibilityIdentifier("dashboard.tile.\(tool.id.rawValue)")
    }
}

// MARK: - 相对时间

private enum WorkbenchRelativeTime {
    @MainActor private static let formatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.dateTimeStyle = .named
        formatter.unitsStyle = .full
        return formatter
    }()

    @MainActor static func text(for date: Date) -> String {
        formatter.localizedString(for: date, relativeTo: Date())
    }
}

@MainActor
private extension Date {
    func relativeText() -> String {
        WorkbenchRelativeTime.text(for: self)
    }
}
