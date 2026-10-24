@testable import XTools
import Foundation
import SwiftUI
import Testing
import XToolsDesign

struct ToolNavigationActionsTests {
    @MainActor
    @Test func selectingToolExpandsOwningSectionAndCanDismissCommandPalette() {
        let fixture = Self.fixture()
        fixture.favorites.toggle(.jwt)
        fixture.sidebarSections.toggle(ToolNavigationSection.favorites.groupID)
        fixture.viewModel.openCommandPalette()

        let didSelect = fixture.actions.selectTool(.jwt, dismissCommandPalette: true)

        #expect(didSelect)
        #expect(fixture.viewModel.selectedToolID == .jwt)
        #expect(fixture.sidebarSections.isExpanded(ToolNavigationSection.favorites.groupID))
        #expect(!fixture.viewModel.showsCommandPalette)
    }

    @MainActor
    @Test func selectingCategoryToolExpandsItsCategorySection() {
        let fixture = Self.fixture()
        let development = ToolNavigationSection.category(.development)
        fixture.sidebarSections.toggle(development.groupID)

        let didSelect = fixture.actions.selectTool(.json)

        #expect(didSelect)
        #expect(fixture.viewModel.selectedToolID == .json)
        #expect(fixture.sidebarSections.isExpanded(development.groupID))
    }

    @MainActor
    @Test func favoriteToggleExpandsTheSectionThatNowOwnsTheSelectedTool() {
        let fixture = Self.fixture()
        fixture.viewModel.selectedToolID = .json
        let favorites = ToolNavigationSection.favorites
        let development = ToolNavigationSection.category(.development)
        fixture.sidebarSections.toggle(favorites.groupID)

        let becameFavorite = fixture.actions.toggleFavorite(.json)

        #expect(becameFavorite == true)
        #expect(fixture.favorites.isFavorite(.json))
        #expect(fixture.sidebarSections.isExpanded(favorites.groupID))

        fixture.sidebarSections.toggle(development.groupID)
        let stoppedBeingFavorite = fixture.actions.toggleFavorite(.json)

        #expect(stoppedBeingFavorite == false)
        #expect(!fixture.favorites.isFavorite(.json))
        #expect(fixture.sidebarSections.isExpanded(development.groupID))
    }

    @MainActor
    @Test func selectCategoryOpensFirstToolOfNthCategory() {
        let fixture = Self.fixture()

        let development = fixture.actions.selectCategory(at: 0)
        #expect(development)
        #expect(fixture.viewModel.selectedToolID == .json)
        #expect(fixture.sidebarSections.isExpanded(ToolNavigationSection.category(.development).groupID))

        let web = fixture.actions.selectCategory(at: 1)
        #expect(web)
        #expect(fixture.viewModel.selectedToolID == .jwt)
        #expect(fixture.sidebarSections.isExpanded(ToolNavigationSection.category(.web).groupID))

        #expect(!fixture.actions.selectCategory(at: 2))
        #expect(fixture.viewModel.selectedToolID == .jwt)
    }

    @MainActor
    @Test func unknownToolIDDoesNotMutateNavigationState() {
        let fixture = Self.fixture()
        fixture.viewModel.selectedToolID = .json
        fixture.viewModel.openCommandPalette()
        fixture.sidebarSections.toggle(ToolNavigationSection.category(.web).groupID)

        let didSelect = fixture.actions.selectTool(.missing, dismissCommandPalette: true)
        let favoriteResult = fixture.actions.toggleFavorite(.missing)

        #expect(!didSelect)
        #expect(favoriteResult == nil)
        #expect(fixture.viewModel.selectedToolID == .json)
        #expect(fixture.viewModel.showsCommandPalette)
        #expect(!fixture.sidebarSections.isExpanded(ToolNavigationSection.category(.web).groupID))
    }

    @MainActor
    @Test func defaultSelectionKeepsDashboardWhenAutoResumeIsDisabled() {
        let fixture = Self.fixture()
        fixture.viewModel.selectedToolID = .json
        fixture.viewModel.autoResumeLastTool = false

        fixture.actions.selectDefaultToolIfNeeded(.json)

        #expect(fixture.viewModel.selectedToolID == nil)
    }

    @MainActor
    @Test func favoritesLoadWithoutDuplicatesOrUnknownIDs() {
        let defaults = Self.defaults()
        defaults.set(["jwt", "missing", "jwt", "json"], forKey: "tools.favorites.v1")

        let favorites = FavoritesStore(
            defaults: defaults,
            validToolIDs: [.jwt, .json]
        )

        #expect(favorites.favoriteIDs == [.jwt, .json])
        #expect(favorites.isFavorite(.jwt))
        #expect(!favorites.isFavorite(.missing))
    }

    @MainActor
    @Test func favoritesToggleKeepsOrderAndSetMembershipInSync() {
        let favorites = FavoritesStore(
            defaults: Self.defaults(),
            validToolIDs: [.json, .jwt]
        )

        #expect(favorites.toggle(.json))
        #expect(favorites.toggle(.jwt))
        #expect(favorites.favoriteIDs == [.json, .jwt])
        #expect(favorites.isFavorite(.json))

        #expect(!favorites.toggle(.json))
        #expect(favorites.favoriteIDs == [.jwt])
        #expect(!favorites.isFavorite(.json))
        #expect(favorites.isFavorite(.jwt))
    }

    @MainActor
    @Test func favoritesMoveReordersInPlaceAndPersistsArrayOrder() {
        // 收藏区拖拽排序（原生 List .onMove）：数组序即 tools.favorites.v1
        // 持久化序，成员集合不变。
        let defaults = Self.defaults()
        let favorites = FavoritesStore(
            defaults: defaults,
            validToolIDs: [.json, .regex, .jwt]
        )
        favorites.toggle(.json)
        favorites.toggle(.regex)
        favorites.toggle(.jwt)
        #expect(favorites.favoriteIDs == [.json, .regex, .jwt])

        favorites.move(fromOffsets: IndexSet(integer: 2), toOffset: 0)
        #expect(favorites.favoriteIDs == [.jwt, .json, .regex])
        #expect(favorites.isFavorite(.regex))

        let reloaded = FavoritesStore(defaults: defaults)
        #expect(reloaded.favoriteIDs == [.jwt, .json, .regex])
    }

    @MainActor
    @Test func favoritesMoveIgnoresNoOpReordersAndClampsOutOfRangeTargets() {
        let defaults = Self.defaults()
        defaults.set(["jwt", "json"], forKey: "tools.favorites.v1")
        let favorites = FavoritesStore(defaults: defaults, validToolIDs: [.json, .jwt])

        favorites.move(fromOffsets: IndexSet(integer: 0), toOffset: 1)
        #expect(favorites.favoriteIDs == [.jwt, .json])

        favorites.move(fromOffsets: IndexSet(integer: 0), toOffset: 99)
        #expect(favorites.favoriteIDs == [.json, .jwt])

        favorites.move(fromOffsets: IndexSet(), toOffset: 0)
        #expect(favorites.favoriteIDs == [.json, .jwt])
        #expect(favorites.isFavorite(.json))
        #expect(favorites.isFavorite(.jwt))
    }

    @MainActor
    @Test func defaultSelectionPrefersFirstFavoriteBeforeProjectedRegistryDefault() {
        // 收藏优先默认落点在动作层（投影自阶段③ B 起不读收藏）。
        let fixture = Self.fixture()
        fixture.viewModel.autoResumeLastTool = true
        fixture.favorites.toggle(.jwt)

        fixture.actions.selectDefaultToolIfNeeded(.json)
        #expect(fixture.viewModel.selectedToolID == .jwt)

        // 已有合法选择不被默认落点覆盖。
        fixture.actions.selectDefaultToolIfNeeded(.json)
        #expect(fixture.viewModel.selectedToolID == .jwt)

        // 无收藏时回落注册表序默认。
        fixture.actions.toggleFavorite(.jwt)
        fixture.viewModel.selectedToolID = nil
        fixture.actions.selectDefaultToolIfNeeded(.json)
        #expect(fixture.viewModel.selectedToolID == .json)
    }

    @MainActor
    private static func fixture() -> Fixture {
        let registry = ToolRegistry(
            categories: [
                ToolCategory(id: .development, title: "Development", systemImage: "hammer"),
                ToolCategory(id: .web, title: "Web", systemImage: "globe")
            ],
            tools: [
                tool(.json, title: "JSON Formatter", categoryID: .development),
                tool(.regex, title: "Regex Tester", categoryID: .development),
                tool(.jwt, title: "Token Inspector", categoryID: .web)
            ]
        )
        let viewModel = ShellNavigationModel()
        let favorites = FavoritesStore(defaults: defaults())
        let sidebarSections = SidebarSectionExpansionStore(defaults: defaults())
        return Fixture(
            registry: registry,
            viewModel: viewModel,
            favorites: favorites,
            sidebarSections: sidebarSections,
            actions: ToolNavigationActions(
                registry: registry,
                navigation: viewModel,
                favorites: favorites,
                sidebarSections: sidebarSections
            )
        )
    }

    private static func tool(
        _ id: ToolID,
        title: String,
        categoryID: ToolCategoryID
    ) -> RegisteredTool {
        RegisteredTool(
            id: id,
            title: title,
            categoryID: categoryID,
            systemImage: "gear",
            keywords: []
        ) {
            EmptyView()
        }
    }

    private static func defaults() -> UserDefaults {
        let suiteName = "ToolNavigationActionsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    @MainActor
    private struct Fixture {
        let registry: ToolRegistry
        let viewModel: ShellNavigationModel
        let favorites: FavoritesStore
        let sidebarSections: SidebarSectionExpansionStore
        let actions: ToolNavigationActions
    }
}

private extension ToolID {
    static let json = ToolID(rawValue: "json")
    static let regex = ToolID(rawValue: "regex")
    static let jwt = ToolID(rawValue: "jwt")
    static let missing = ToolID(rawValue: "missing")
}
