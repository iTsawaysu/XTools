import Foundation

/// Persists the expanded/collapsed state of top-level sidebar sections.
/// Stores collapsed ids so newly registered sections stay visible by default.
@MainActor
final class SidebarSectionExpansionStore: PersistentDisclosureExpansionStore {
    static let storageKey = "tools.sidebar.collapsedSections.v1"

    init(defaults: UserDefaults = .standard) {
        super.init(storageKey: Self.storageKey, defaults: defaults)
    }
}
