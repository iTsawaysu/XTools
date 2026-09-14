import Foundation

/// Persists the favorites order as raw ToolID strings in UserDefaults, decoupled
/// from the registry.
@MainActor
final class FavoritesStore: ObservableObject {
    private static let storageKey = "tools.favorites.v1"

    @Published private(set) var favoriteIDs: [ToolID]

    private let defaults: UserDefaults
    private var favoriteSet: Set<ToolID>

    init(defaults: UserDefaults = .standard, validToolIDs: Set<ToolID>? = nil) {
        self.defaults = defaults
        let raw = defaults.array(forKey: Self.storageKey) as? [String] ?? []
        var seen = Set<ToolID>()
        let loaded = raw.compactMap { value -> ToolID? in
            let id = ToolID(rawValue: value)
            guard validToolIDs?.contains(id) ?? true, seen.insert(id).inserted else {
                return nil
            }
            return id
        }
        self.favoriteIDs = loaded
        self.favoriteSet = Set(loaded)
    }

    func isFavorite(_ id: ToolID) -> Bool {
        favoriteSet.contains(id)
    }

    @discardableResult
    func toggle(_ id: ToolID) -> Bool {
        if let index = favoriteIDs.firstIndex(of: id) {
            favoriteIDs.remove(at: index)
            favoriteSet.remove(id)
            persist()
            return false
        }

        favoriteIDs.append(id)
        favoriteSet.insert(id)
        persist()
        return true
    }

    private func persist() {
        defaults.set(favoriteIDs.map(\.rawValue), forKey: Self.storageKey)
    }
}
