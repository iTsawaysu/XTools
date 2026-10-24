import Foundation
import XToolsDesign

enum ToolNavigationSection: Equatable, Hashable {
    case favorites
    /// 「最近使用」区（阶段③ 原生侧栏新增）。旧持久化数据没有该键，
    /// 默认展开——兼容读取无需迁移。
    case recents
    case category(ToolCategoryID)

    var groupID: String {
        switch self {
        case .favorites:
            return "favorites"
        case .recents:
            return "recents"
        case .category(let categoryID):
            return "category.\(categoryID.rawValue)"
        }
    }
}

struct ToolNavigationItem: Identifiable, Hashable {
    let id: ToolID
    let title: String
    let categoryID: ToolCategoryID
    let systemImage: String
    let section: ToolNavigationSection
}

struct ToolNavigationGroup: Identifiable, Hashable {
    var id: String {
        section.groupID
    }

    let title: String
    let systemImage: String
    let section: ToolNavigationSection
    let items: [ToolNavigationItem]
}

struct ToolNavigationCommandEntry: Identifiable, Hashable {
    var id: String { "tool.\(toolID.rawValue)" }

    let toolID: ToolID
    let title: String
    let categoryTitle: String?
    let systemImage: String

    init(
        toolID: ToolID,
        title: String,
        categoryTitle: String?,
        systemImage: String
    ) {
        self.toolID = toolID
        self.title = title
        self.categoryTitle = categoryTitle
        self.systemImage = systemImage
    }

    /// Maps a registered tool into the palette's narrow entry shape.
    init(
        tool: RegisteredTool,
        categoryTitle: String?
    ) {
        self.init(
            toolID: tool.id,
            title: tool.title,
            categoryTitle: categoryTitle,
            systemImage: tool.systemImage
        )
    }
}

/// Palette-only projection. It intentionally skips favorite grouping,
/// selection lookup, sidebar sections, and default-tool calculation.
///
/// `matches` stays aligned with `entries` (index-for-index); each element is
/// nil only for the unfiltered empty-query list and otherwise carries the
/// engine match that ranked the entry, including title highlight ranges.
struct ToolNavigationCommandProjection: Equatable {
    let entries: [ToolNavigationCommandEntry]
    let matches: [ToolSearchEngine.Match?]

    init(entries: [ToolNavigationCommandEntry], matches: [ToolSearchEngine.Match?]) {
        self.entries = entries
        self.matches = matches
    }

    init(registry: ToolRegistry, query: String) {
        let ranked = registry.matchingToolMatches(query: query)
        self.init(
            entries: ranked.map { rankedMatch in
                ToolNavigationCommandEntry(
                    tool: rankedMatch.tool,
                    categoryTitle: registry.categoryTitle(for: rankedMatch.tool.categoryID)
                )
            },
            matches: ranked.map(\.match)
        )
    }
}

/// 侧栏导航投影（阶段③ 原生侧栏重构）。
///
/// 只承载「注册表 → 分类组/搜索匹配」的纯函数映射。收藏与最近使用是侧栏
/// 本地观察状态（`FavoritesStore` / `ToolUsageFrequencyStore`，由
/// `SidebarNativeList` 直接观察），不再进入投影——收藏切换因此只触发侧栏
/// 局部重估，RootView 不随失效（app-shell-performance rootBody=0 契约）。
///
/// 分类语义（PRD 决策 8）：**收藏工具保留在分类组中**，不再移出；收藏区
/// 上浮由侧栏装配层用 `FavoritesStore` 拼装。搜索态仍走全量引擎过滤
/// （`ToolSearchEngine` 拼音/fzf 语义不变）。
struct ToolNavigationProjection {
    let selectedToolID: ToolID?
    /// 仅分类组：空查询 = 该分类全部工具；搜索 = 命中查询的工具。
    let sidebarGroups: [ToolNavigationGroup]
    /// nil = 非搜索态；非 nil = 命中查询的工具 ID 集（侧栏用它过滤收藏区、
    /// 并把命中收藏从分类组上浮到收藏区以去重——等价旧版搜索结果形态）。
    let matchingToolIDs: Set<ToolID>?
    /// 注册表序首个工具（收藏优先的默认落点在 `ToolNavigationActions`
    /// 动作层叠加，投影不再读收藏）。
    let defaultToolID: ToolID?

    init(
        registry: ToolRegistry,
        selectedToolID: ToolID?,
        query: String
    ) {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let matchingTools = registry.matchingTools(query: normalizedQuery)
        let matchingToolIDs: Set<ToolID>? = normalizedQuery.isEmpty
            ? nil
            : Set(matchingTools.map(\.id))

        var groups: [ToolNavigationGroup] = []
        for group in registry.categoryGroups() {
            let items = group.tools
                .filter { matchingToolIDs?.contains($0.id) ?? true }
                .map { tool in
                    Self.item(for: tool, section: .category(group.category.id))
                }

            if !items.isEmpty {
                groups.append(ToolNavigationGroup(
                    title: group.category.title,
                    systemImage: group.category.systemImage,
                    section: .category(group.category.id),
                    items: items
                ))
            }
        }

        self.sidebarGroups = groups
        self.matchingToolIDs = matchingToolIDs
        self.selectedToolID = selectedToolID
        self.defaultToolID = registry.firstToolIDInCategoryOrder()
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
}
