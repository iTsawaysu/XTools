import Foundation

struct ToolCategoryID: RawRepresentable, Hashable, Identifiable, Codable {
    let rawValue: String

    var id: String {
        rawValue
    }

    init(rawValue: String) {
        self.rawValue = rawValue
    }
}

struct ToolCategory: Identifiable, Hashable {
    let id: ToolCategoryID
    let title: String
    let systemImage: String
}

extension ToolCategoryID {
    static let crypto = ToolCategoryID(rawValue: "crypto")
    static let converter = ToolCategoryID(rawValue: "converter")
    static let development = ToolCategoryID(rawValue: "development")
    static let web = ToolCategoryID(rawValue: "web")
    static let text = ToolCategoryID(rawValue: "text")
    static let image = ToolCategoryID(rawValue: "image")
    static let time = ToolCategoryID(rawValue: "time")
    static let utility = ToolCategoryID(rawValue: "utility")
    static let other = ToolCategoryID(rawValue: "other")
}
