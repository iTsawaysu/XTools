@testable import XTools
import Foundation
import Testing

struct SidebarSectionExpansionStoreTests {
    @MainActor
    @Test func defaultsToExpandedAndPersistsCollapsedGroups() {
        let defaults = Self.defaults()
        let store = SidebarSectionExpansionStore(defaults: defaults)

        #expect(store.isExpanded("category.development"))

        store.toggle("category.development")

        #expect(!store.isExpanded("category.development"))
        #expect(defaults.array(forKey: SidebarSectionExpansionStore.storageKey) as? [String] == ["category.development"])

        let reloaded = SidebarSectionExpansionStore(defaults: defaults)
        #expect(!reloaded.isExpanded("category.development"))
    }

    @MainActor
    @Test func expandRemovesOnlyTheRequestedCollapsedGroup() {
        let defaults = Self.defaults()
        let store = SidebarSectionExpansionStore(defaults: defaults)

        store.toggle("category.web")
        store.toggle("category.development")

        #expect(defaults.array(forKey: SidebarSectionExpansionStore.storageKey) as? [String] == [
            "category.development",
            "category.web"
        ])

        store.expand("category.development")

        #expect(store.isExpanded("category.development"))
        #expect(!store.isExpanded("category.web"))
        #expect(defaults.array(forKey: SidebarSectionExpansionStore.storageKey) as? [String] == ["category.web"])
    }

    @MainActor
    @Test func toggleSoloCollapsesOthersThenExpandsAllOnSecondSoloToggle() {
        let defaults = Self.defaults()
        let store = SidebarSectionExpansionStore(defaults: defaults)
        let allGroups = ["category.development", "category.web", "category.graphic"]

        #expect(store.isExpanded("category.development"))
        #expect(store.isExpanded("category.web"))
        #expect(store.isExpanded("category.graphic"))

        store.toggleSolo("category.development", allGroupIDs: allGroups)
        #expect(store.isExpanded("category.development"))
        #expect(!store.isExpanded("category.web"))
        #expect(!store.isExpanded("category.graphic"))

        store.toggleSolo("category.development", allGroupIDs: allGroups)
        #expect(store.isExpanded("category.development"))
        #expect(store.isExpanded("category.web"))
        #expect(store.isExpanded("category.graphic"))
    }

    private static func defaults() -> UserDefaults {
        let suiteName = "SidebarSectionExpansionStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
