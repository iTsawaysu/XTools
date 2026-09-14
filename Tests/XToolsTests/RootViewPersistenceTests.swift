@testable import XTools
import Foundation
import SwiftUI
import Testing

struct RootViewPersistenceTests {
    @MainActor
    @Test func rootModelRestoresSelectedToolAndSidebarVisibilityWhenPreferencesAreInjected() {
        let defaults = Self.defaults()
        let preferences = ToolPreferenceStore(defaults: defaults)
        let model = RootViewModel(preferences: preferences)

        #expect(model.selectedToolID == nil)
        #expect(model.sidebarVisibility == .visible)

        model.selectedToolID = .persistedTool
        model.sidebarVisibility = .hidden

        let reloaded = RootViewModel(preferences: ToolPreferenceStore(defaults: defaults))
        #expect(reloaded.selectedToolID == .persistedTool)
        #expect(reloaded.sidebarVisibility == .hidden)
    }

    @MainActor
    @Test func invalidPersistedSelectionFallsBackThroughNavigationAndPersistsTheValidDefault() {
        let defaults = Self.defaults()
        let preferences = ToolPreferenceStore(defaults: defaults)
        preferences.set(true, for: AppShellPreferenceKeys.autoResumeLastTool)
        preferences.set("removed-tool", for: AppShellPreferenceKeys.selectedToolID)
        let fixture = Self.fixture(preferences: preferences, defaults: defaults)

        #expect(fixture.viewModel.selectedToolID == ToolID(rawValue: "removed-tool"))

        fixture.actions.selectDefaultToolIfNeeded(.persistedTool)

        #expect(fixture.viewModel.selectedToolID == .persistedTool)
        #expect(ToolPreferenceStore(defaults: defaults).value(for: AppShellPreferenceKeys.selectedToolID) == "persisted-tool")
    }

    @MainActor
    @Test func validPersistedSelectionIsNotOverwrittenByTheProjectedDefault() {
        let defaults = Self.defaults()
        let preferences = ToolPreferenceStore(defaults: defaults)
        preferences.set(true, for: AppShellPreferenceKeys.autoResumeLastTool)
        preferences.set("secondary-tool", for: AppShellPreferenceKeys.selectedToolID)
        let fixture = Self.fixture(preferences: preferences, defaults: defaults)

        fixture.actions.selectDefaultToolIfNeeded(.persistedTool)

        #expect(fixture.viewModel.selectedToolID == .secondaryTool)
    }

    @MainActor
    @Test func invalidSidebarPreferenceFallsBackToVisible() {
        let defaults = Self.defaults()
        defaults.set("future-case", forKey: AppShellPreferenceKeys.sidebarVisibility.rawKey)

        let model = RootViewModel(preferences: ToolPreferenceStore(defaults: defaults))

        #expect(model.sidebarVisibility == .visible)
    }

    @MainActor
    private static func fixture(
        preferences: ToolPreferenceStore,
        defaults: UserDefaults
    ) -> Fixture {
        let registry = ToolRegistry(
            categories: [
                ToolCategory(id: .persistenceCategory, title: "Persistence", systemImage: "externaldrive")
            ],
            tools: [
                tool(.persistedTool, title: "Persisted"),
                tool(.secondaryTool, title: "Secondary")
            ]
        )
        let viewModel = RootViewModel(preferences: preferences)
        let favorites = FavoritesStore(defaults: defaults)
        let sidebarSections = SidebarSectionExpansionStore(defaults: defaults)
        return Fixture(
            viewModel: viewModel,
            actions: ToolNavigationActions(
                registry: registry,
                viewModel: viewModel,
                favorites: favorites,
                sidebarSections: sidebarSections
            )
        )
    }

    private static func tool(_ id: ToolID, title: String) -> RegisteredTool {
        RegisteredTool(
            id: id,
            title: title,
            categoryID: .persistenceCategory,
            systemImage: "gear",
            keywords: []
        ) {
            EmptyView()
        }
    }

    private static func defaults() -> UserDefaults {
        let suiteName = "RootViewPersistenceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    @MainActor
    private struct Fixture {
        let viewModel: RootViewModel
        let actions: ToolNavigationActions
    }
}

private extension ToolID {
    static let persistedTool = ToolID(rawValue: "persisted-tool")
    static let secondaryTool = ToolID(rawValue: "secondary-tool")
}

private extension ToolCategoryID {
    static let persistenceCategory = ToolCategoryID(rawValue: "persistence-category")
}
