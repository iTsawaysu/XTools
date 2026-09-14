@testable import XTools
import Foundation
import Testing

struct TimezoneViewerDisclosureExpansionStoreTests {
    @MainActor
    @Test func defaultsToExpandedAndPersistsCollapsedTimezoneSections() {
        let defaults = Self.defaults()
        let store = TimezoneViewerDisclosureExpansionStore(defaults: defaults)

        #expect(store.isExpanded("favorites"))
        #expect(store.isExpanded("region.亚洲"))

        store.toggle("favorites")
        store.toggle("region.亚洲")

        #expect(!store.isExpanded("favorites"))
        #expect(!store.isExpanded("region.亚洲"))
        #expect(defaults.array(forKey: TimezoneViewerDisclosureExpansionStore.storageKey) as? [String] == [
            "favorites",
            "region.亚洲"
        ])

        let reloaded = TimezoneViewerDisclosureExpansionStore(defaults: defaults)
        #expect(!reloaded.isExpanded("favorites"))
        #expect(!reloaded.isExpanded("region.亚洲"))
    }

    @MainActor
    @Test func expandRestoresOnlyFavoritesDisclosure() {
        let defaults = Self.defaults()
        let store = TimezoneViewerDisclosureExpansionStore(defaults: defaults)

        store.toggle("favorites")
        store.toggle("region.欧洲")

        store.expand("favorites")

        #expect(store.isExpanded("favorites"))
        #expect(!store.isExpanded("region.欧洲"))
        #expect(defaults.array(forKey: TimezoneViewerDisclosureExpansionStore.storageKey) as? [String] == ["region.欧洲"])
    }

    private static func defaults() -> UserDefaults {
        let suiteName = "TimezoneViewerDisclosureExpansionStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}

struct TimezoneViewerFavoriteStoreTests {
    @MainActor
    @Test func persistsFavoriteTimezoneKeysAcrossReloads() {
        let defaults = Self.defaults()
        let store = TimezoneViewerFavoriteStore(defaults: defaults)

        #expect(store.favoriteKeys.isEmpty)
        #expect(store.toggle(keys: ["Asia/Shanghai", "Asia/Hong_Kong"]))
        #expect(store.favoriteKeys == ["Asia/Shanghai", "Asia/Hong_Kong"])
        #expect(defaults.array(forKey: TimezoneViewerFavoriteStore.storageKey) as? [String] == [
            "Asia/Hong_Kong",
            "Asia/Shanghai"
        ])

        let reloaded = TimezoneViewerFavoriteStore(defaults: defaults)
        #expect(reloaded.favoriteKeys == ["Asia/Shanghai", "Asia/Hong_Kong"])
    }

    @MainActor
    @Test func toggleRemovesOnlyTheSelectedFavoriteGroup() {
        let defaults = Self.defaults()
        let store = TimezoneViewerFavoriteStore(defaults: defaults)

        #expect(store.toggle(keys: ["Asia/Shanghai", "Asia/Hong_Kong"]))
        #expect(store.toggle(keys: ["Europe/London"]))
        #expect(!store.toggle(keys: ["Asia/Shanghai", "Asia/Hong_Kong"]))

        #expect(store.favoriteKeys == ["Europe/London"])
        #expect(defaults.array(forKey: TimezoneViewerFavoriteStore.storageKey) as? [String] == ["Europe/London"])
    }

    private static func defaults() -> UserDefaults {
        let suiteName = "TimezoneViewerFavoriteStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
