@testable import XTools
import SwiftUI
import Testing

struct ToolNavigationProjectionTests {
    @Test func favoriteToolsMoveOutOfTheirOriginalCategoryAndDriveSelectedSection() {
        let registry = Self.registry()
        let projection = ToolNavigationProjection(
            registry: registry,
            favoriteIDs: [.json],
            selectedToolID: .json,
            query: ""
        )

        #expect(projection.selectedSection == .favorites)
        #expect(projection.sidebarGroups.map(\.title) == ["收藏", "Development", "Web"])
        #expect(projection.sidebarGroups.map(\.systemImage) == ["star.fill", "hammer", "globe"])
        #expect(projection.sidebarGroups[0].items.map(\.id) == [.json])
        #expect(projection.sidebarGroups[1].items.map(\.id) == [.regex])
    }

    @Test func defaultSelectionUsesFavoritesBeforeFirstRegisteredCategoryTool() {
        let registry = Self.registry()
        let withFavorite = ToolNavigationProjection(
            registry: registry,
            favoriteIDs: [.jwt],
            selectedToolID: nil,
            query: ""
        )
        let withoutFavorite = ToolNavigationProjection(
            registry: registry,
            favoriteIDs: [],
            selectedToolID: nil,
            query: ""
        )

        #expect(withFavorite.defaultToolID == .jwt)
        #expect(withoutFavorite.defaultToolID == .json)
    }

    @Test func commandPaletteEntriesUseRankedSearchAndCarryCategoryTitles() {
        let registry = Self.registry()
        let projection = ToolNavigationProjection(
            registry: registry,
            favoriteIDs: [],
            selectedToolID: nil,
            query: "token"
        )

        #expect(projection.commandPaletteEntries.map(\.toolID) == [.jwt, .json])
        #expect(projection.commandPaletteEntries.map(\.categoryTitle) == ["Web", "Development"])
    }

    @Test func sidebarSearchUsesSameDiacriticInsensitiveMatchingButKeepsGroups() {
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
            favoriteIDs: [],
            selectedToolID: nil,
            query: "café"
        )

        #expect(projection.sidebarGroups.count == 1)
        #expect(projection.sidebarGroups[0].items.map(\.id) == [.cafe])
    }

    @Test func sectionGroupIDsAreStableForSidebarExpansionPersistence() {
        #expect(ToolNavigationSection.favorites.groupID == "favorites")
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
