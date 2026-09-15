import Foundation

enum ToolNavigationSection: Equatable, Hashable {
    case favorites
    case category(ToolCategoryID)

    var groupID: String {
        switch self {
        case .favorites:
            return "favorites"
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
    let isFavorite: Bool
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
}

/// Palette-only projection. It intentionally skips favorite grouping,
/// selection lookup, sidebar sections, and default-tool calculation.
struct ToolNavigationCommandProjection: Equatable {
    let entries: [ToolNavigationCommandEntry]

    init(registry: ToolRegistry, query: String) {
        entries = registry.matchingTools(query: query).map { tool in
            ToolNavigationCommandEntry(
                toolID: tool.id,
                title: tool.title,
                categoryTitle: registry.categoryTitle(for: tool.categoryID),
                systemImage: tool.systemImage
            )
        }
    }
}

struct ToolNavigationProjection {
    let selectedTool: ToolNavigationItem?
    let selectedSection: ToolNavigationSection?
    let sidebarGroups: [ToolNavigationGroup]
    let commandPaletteEntries: [ToolNavigationCommandEntry]
    let defaultToolID: ToolID?

    init(
        registry: ToolRegistry,
        favoriteIDs: [ToolID],
        selectedToolID: ToolID?,
        query: String
    ) {
        let favoriteSet = Set(favoriteIDs)
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let favoriteTools = registry.tools(for: favoriteIDs)
        let matchingTools = registry.matchingTools(query: normalizedQuery)
        let matchingToolIDs: Set<ToolID>? = normalizedQuery.isEmpty
            ? nil
            : Set(matchingTools.map(\.id))

        func matches(_ tool: RegisteredTool) -> Bool {
            matchingToolIDs?.contains(tool.id) ?? true
        }

        let visibleFavoriteItems = favoriteTools
            .filter(matches)
            .map { Self.item(for: $0, isFavorite: true, section: .favorites) }

        var groups: [ToolNavigationGroup] = []
        if !visibleFavoriteItems.isEmpty {
            groups.append(ToolNavigationGroup(
                title: "收藏",
                systemImage: "star.fill",
                section: .favorites,
                items: visibleFavoriteItems
            ))
        }

        for group in registry.categoryGroups() {
            let category = group.category
            let items = group.tools
                .filter { !favoriteSet.contains($0.id) }
                .filter(matches)
                .map {
                    Self.item(
                        for: $0,
                        isFavorite: false,
                        section: .category(category.id)
                    )
                }

            if !items.isEmpty {
                groups.append(ToolNavigationGroup(
                    title: category.title,
                    systemImage: category.systemImage,
                    section: .category(category.id),
                    items: items
                ))
            }
        }

        self.sidebarGroups = groups

        if let selectedToolID,
           let selectedTool = registry.tool(for: selectedToolID) {
            let section: ToolNavigationSection = favoriteSet.contains(selectedToolID)
                ? .favorites
                : .category(selectedTool.categoryID)
            self.selectedSection = section
            self.selectedTool = Self.item(
                for: selectedTool,
                isFavorite: favoriteSet.contains(selectedToolID),
                section: section
            )
        } else {
            self.selectedSection = nil
            self.selectedTool = nil
        }

        self.commandPaletteEntries = matchingTools
            .map {
                ToolNavigationCommandEntry(
                    toolID: $0.id,
                    title: $0.title,
                    categoryTitle: registry.categoryTitle(for: $0.categoryID),
                    systemImage: $0.systemImage
                )
            }

        self.defaultToolID = favoriteTools.first?.id ?? registry.firstToolIDInCategoryOrder()
    }

    private static func item(
        for tool: RegisteredTool,
        isFavorite: Bool,
        section: ToolNavigationSection
    ) -> ToolNavigationItem {
        ToolNavigationItem(
            id: tool.id,
            title: tool.title,
            categoryID: tool.categoryID,
            systemImage: tool.systemImage,
            isFavorite: isFavorite,
            section: section
        )
    }
}
