import Foundation

public enum HTMLReadabilityScriptResource {
    public static let version = "0.6.0"

    public enum ResourceError: Error, Equatable, Sendable {
        case missing
        case unreadable
    }

    public static func load() throws -> String {
        guard let url = Bundle.module.url(
            forResource: "Readability-0.6.0",
            withExtension: "js"
        ) else {
            throw ResourceError.missing
        }

        do {
            return try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw ResourceError.unreadable
        }
    }
}
