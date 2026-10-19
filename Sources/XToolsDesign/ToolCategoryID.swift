import Foundation

/// Category identity used by design accents and registry metadata.
public struct ToolCategoryID: RawRepresentable, Hashable, Identifiable, Codable, Sendable {
    public let rawValue: String

    public var id: String {
        rawValue
    }

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

public extension ToolCategoryID {
    public static let crypto = ToolCategoryID(rawValue: "crypto")
    public static let converter = ToolCategoryID(rawValue: "converter")
    public static let development = ToolCategoryID(rawValue: "development")
    public static let web = ToolCategoryID(rawValue: "web")
    public static let image = ToolCategoryID(rawValue: "image")
    public static let time = ToolCategoryID(rawValue: "time")
    public static let utility = ToolCategoryID(rawValue: "utility")
}
