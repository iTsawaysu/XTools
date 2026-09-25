import Foundation

public struct HTMLToMarkdownConversionResult: Equatable, Sendable {
    public let markdown: String
    public let warnings: [HTMLToMarkdownWarning]
    public let error: HTMLToMarkdownConversionError?

    public init(
        markdown: String,
        warnings: [HTMLToMarkdownWarning] = [],
        error: HTMLToMarkdownConversionError? = nil
    ) {
        self.markdown = markdown
        self.warnings = warnings
        self.error = error
    }
}

public struct HTMLToMarkdownOptions: Equatable, Sendable {
    public var baseURL: URL?
    public var inputBudget: HTMLToMarkdownInputBudget

    public init(
        baseURL: URL? = nil,
        inputBudget: HTMLToMarkdownInputBudget = .manual
    ) {
        self.baseURL = baseURL
        self.inputBudget = inputBudget
    }

    public static var manual: Self { .init(inputBudget: .manual) }
}

public struct HTMLToMarkdownInputBudget: Equatable, Sendable {
    public static let defaultCompletedResultThreshold = 512_000
    public static let defaultPreParseByteLimit = 5 * 1_024 * 1_024

    public static let manual = Self(
        preParseByteLimit: defaultPreParseByteLimit,
        completedResultThreshold: defaultCompletedResultThreshold
    )

    public static let urlFetchedDocument = Self(
        preParseByteLimit: defaultPreParseByteLimit,
        completedResultThreshold: nil
    )

    public var preParseByteLimit: Int
    public var completedResultThreshold: Int?

    public init(preParseByteLimit: Int, completedResultThreshold: Int?) {
        self.preParseByteLimit = preParseByteLimit
        self.completedResultThreshold = completedResultThreshold
    }
}

public enum HTMLToMarkdownConversionError: Error, Equatable, Sendable {
    case inputExceedsPreParseByteLimit(Int)
    case domDepthExceeded(Int)
}

public enum HTMLToMarkdownWarning: Equatable, Sendable {
    case unsupportedElement(String)
    case flattenedTableSpan
    case droppedUnsafeElement(String)
    case emptyVisibleContent
    case completedInputExceedsThreshold(Int)
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
        } catch let conversionError as HTMLToMarkdownConversionError {
            return HTMLToMarkdownConversionResult(
                markdown: "",
                error: conversionError
            )
        } catch {
            preconditionFailure("Non-cancellable HTML conversion produced an unexpected error: \(error)")
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
