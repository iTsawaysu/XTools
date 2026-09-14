import Foundation

public struct HTMLToMarkdownConversionResult: Equatable, Sendable {
    public let markdown: String
    public let warnings: [HTMLToMarkdownWarning]

    public init(markdown: String, warnings: [HTMLToMarkdownWarning] = []) {
        self.markdown = markdown
        self.warnings = warnings
    }
}

public struct HTMLToMarkdownOptions: Equatable, Sendable {
    public static let defaultLiveConversionByteLimit = 512_000

    public var baseURL: URL?
    public var liveConversionByteLimit: Int

    public init(baseURL: URL? = nil, liveConversionByteLimit: Int = Self.defaultLiveConversionByteLimit) {
        self.baseURL = baseURL
        self.liveConversionByteLimit = liveConversionByteLimit
    }
}

public enum HTMLToMarkdownWarning: Equatable, Sendable {
    case unsupportedElement(String)
    case flattenedTableSpan
    case droppedUnsafeElement(String)
    case emptyVisibleContent
    case inputTooLarge(Int)
}

public enum HTMLToMarkdownConverter {
    public static func convert(_ html: String) -> String {
        convert(html, options: HTMLToMarkdownOptions()).markdown
    }

    public static func convert(
        _ html: String,
        options: HTMLToMarkdownOptions = HTMLToMarkdownOptions()
    ) -> HTMLToMarkdownConversionResult {
        do {
            return try convert(html, options: options, shouldCancel: { false })
        } catch {
            preconditionFailure("Non-cancellable HTML conversion path unexpectedly cancelled")
        }
    }

    public static func convert(
        _ html: String,
        options: HTMLToMarkdownOptions = HTMLToMarkdownOptions(),
        shouldCancel: @escaping @Sendable () -> Bool
    ) throws -> HTMLToMarkdownConversionResult {
        try HTMLToMarkdownDOMRenderer(options: options, shouldCancel: shouldCancel).convert(html)
    }
}
