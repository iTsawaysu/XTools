import Foundation

/// Stable tool identity for persistence and shell selection. The raw string
/// lives only at the registration point, so no second constant list can drift.
struct ToolID: RawRepresentable, Hashable, Identifiable, Codable, ExpressibleByStringLiteral {
    let rawValue: String

    var id: String {
        rawValue
    }

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    init(stringLiteral value: String) {
        self.rawValue = value
    }
}
