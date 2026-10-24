@testable import XTools
import SwiftUI
import Testing
import XToolsDesign

struct ToolNavigationProjectionTests {
    @Test func categoryGroupsKeepFavoriteToolsAndCarryNoFavoritesSection() {
        // 阶段③ 决策 8：收藏不再移出分类组；投影不含收藏组（收藏区由
        // SidebarNativeList 用 FavoritesStore 装配，收藏切换不重估壳层）。
        let registry = Self.registry()
        let projection = ToolNavigationProjection(
            registry: registry,
            selectedToolID: .json,
            query: ""
        )

        #expect(projection.matchingToolIDs == nil)
        #expect(projection.selectedToolID == .json)
        #expect(projection.sidebarGroups.map(\.title) == ["Development", "Web"])
        #expect(projection.sidebarGroups.map(\.systemImage) == ["hammer", "globe"])
        #expect(projection.sidebarGroups[0].items.map(\.id) == [.json, .regex])
        #expect(projection.sidebarGroups[0].items[0].section == .category(.development))
    }

    @Test func defaultToolIsFirstToolInRegistryCategoryOrder() {
        // 收藏优先的默认落点已平移到 ToolNavigationActions 动作层；投影只
        // 回答注册表序首个工具。
        let projection = ToolNavigationProjection(
            registry: Self.registry(),
            selectedToolID: nil,
            query: ""
        )

        #expect(projection.defaultToolID == .json)
    }

    @Test func commandPaletteEntriesUseRankedSearchAndCarryCategoryTitles() {
        let projection = ToolNavigationCommandProjection(registry: Self.registry(), query: "token")

        #expect(projection.entries.map(\.toolID) == [.jwt, .json])
        #expect(projection.entries.map(\.categoryTitle) == ["Web", "Development"])
    }

    @Test func narrowCommandProjectionPreservesEmptyQueryRegistryOrder() {
        let projection = ToolNavigationCommandProjection(registry: Self.registry(), query: "  \n")

        #expect(projection.entries.map(\.toolID) == [.json, .regex, .jwt])
        #expect(projection.entries.map(\.categoryTitle) == ["Development", "Development", "Web"])
    }

    @Test func narrowCommandProjectionUsesUnicodeAndDiacriticInsensitiveMatching() {
        let registry = ToolRegistry(
            categories: [
                ToolCategory(id: .development, title: "Development", systemImage: "hammer")
            ],
            tools: [
                Self.tool(.cafe, title: "Cafe Menu", categoryID: .development, keywords: ["菜单"]),
                Self.tool(.json, title: "JSON Formatter", categoryID: .development, keywords: [])
            ]
        )

        #expect(ToolNavigationCommandProjection(registry: registry, query: "café").entries.map(\.toolID) == [.cafe])
        #expect(ToolNavigationCommandProjection(registry: registry, query: "菜单").entries.map(\.toolID) == [.cafe])
    }

    @Test func narrowCommandProjectionReturnsNoEntriesForNoMatch() {
        let projection = ToolNavigationCommandProjection(registry: Self.registry(), query: "definitely-missing")

        #expect(projection.entries.isEmpty)
    }

    @Test func sidebarSearchFiltersCategoryGroupsAndPublishesMatchingIDs() {
        let registry = ToolRegistry(
            categories: [
                ToolCategory(id: .development, title: "Development", systemImage: "hammer")
            ],
            tools: [
                Self.tool(.cafe, title: "Cafe Menu", categoryID: .development, keywords: [])
            ]
        )

        let projection = ToolNavigationProjection(
            registry: registry,
            selectedToolID: nil,
            query: "café"
        )

        #expect(projection.sidebarGroups.count == 1)
        #expect(projection.sidebarGroups[0].items.map(\.id) == [.cafe])
        #expect(projection.matchingToolIDs == [.cafe])
    }

    @Test func sidebarSearchMatchingIDsExcludeNonMatchesForFavoriteHoisting() {
        // 侧栏装配层用 matchingToolIDs 过滤收藏区并把命中收藏从分类组去重
        // 上浮（等价旧版搜索结果形态）。
        let projection = ToolNavigationProjection(
            registry: Self.registry(),
            selectedToolID: nil,
            query: "pretty"
        )

        #expect(projection.matchingToolIDs == [.json])
        #expect(projection.sidebarGroups.count == 1)
        #expect(projection.sidebarGroups[0].items.map(\.id) == [.json])
    }

    @Test func noMatchQueryYieldsEmptyGroupsButPublishesTheMatchSet() {
        let projection = ToolNavigationProjection(
            registry: Self.registry(),
            selectedToolID: nil,
            query: "definitely-missing"
        )

        #expect(projection.sidebarGroups.isEmpty)
        #expect(projection.matchingToolIDs == [])
    }

    @Test func sectionGroupIDsAreStableForSidebarExpansionPersistence() {
        #expect(ToolNavigationSection.favorites.groupID == "favorites")
        #expect(ToolNavigationSection.recents.groupID == "recents")
        #expect(ToolNavigationSection.category(.development).groupID == "category.development")
        #expect(ToolNavigationGroup(title: "Development", systemImage: "hammer", section: .category(.development), items: []).id == "category.development")
    }

    private static func registry() -> ToolRegistry {
        ToolRegistry(
            categories: [
                ToolCategory(id: .development, title: "Development", systemImage: "hammer"),
                ToolCategory(id: .web, title: "Web", systemImage: "globe")
            ],
            tools: [
                tool(.json, title: "JSON Formatter", categoryID: .development, keywords: ["pretty", "token"]),
                tool(.regex, title: "Regex Tester", categoryID: .development, keywords: ["pattern"]),
                tool(.jwt, title: "Token Inspector", categoryID: .web, keywords: ["jwt"])
            ]
        )
    }

    private static func tool(
        _ id: ToolID,
        title: String,
        categoryID: ToolCategoryID,
        keywords: [String]
    ) -> RegisteredTool {
        RegisteredTool(
            id: id,
            title: title,
            categoryID: categoryID,
            systemImage: "gear",
            keywords: keywords
        ) {
            EmptyView()
        }
    }
}

private extension ToolID {
    static let json = ToolID(rawValue: "json")
    static let regex = ToolID(rawValue: "regex")
    static let jwt = ToolID(rawValue: "jwt")
    static let cafe = ToolID(rawValue: "cafe")
}
