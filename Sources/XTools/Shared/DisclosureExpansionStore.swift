import Foundation

@MainActor
class PersistentDisclosureExpansionStore: ObservableObject {
    @Published private(set) var collapsedGroupIDs: Set<String>

    private let storageKey: String
    private let defaults: UserDefaults

    init(storageKey: String, defaults: UserDefaults = .standard) {
        self.storageKey = storageKey
        self.defaults = defaults
        let raw = defaults.array(forKey: storageKey) as? [String] ?? []
        self.collapsedGroupIDs = Set(raw)
    }

    func isExpanded(_ groupID: String) -> Bool {
        !collapsedGroupIDs.contains(groupID)
    }

    func toggle(_ groupID: String) {
        if collapsedGroupIDs.contains(groupID) {
            collapsedGroupIDs.remove(groupID)
        } else {
            collapsedGroupIDs.insert(groupID)
        }
        persist()
    }

    func expand(_ groupID: String) {
        guard collapsedGroupIDs.remove(groupID) != nil else { return }
        persist()
    }

    func toggleSolo(_ groupID: String, allGroupIDs: [String]) {
        let otherGroupIDs = allGroupIDs.filter { $0 != groupID }
        let isOnlyExpanded = isExpanded(groupID) && otherGroupIDs.allSatisfy { !isExpanded($0) }

        if isOnlyExpanded {
            collapsedGroupIDs.removeAll()
        } else {
            collapsedGroupIDs.remove(groupID)
            for otherID in otherGroupIDs {
                collapsedGroupIDs.insert(otherID)
            }
        }
        persist()
    }

    private func persist() {
        defaults.set(collapsedGroupIDs.sorted(), forKey: storageKey)
    }
}
