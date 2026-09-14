import Foundation

public struct HTMLReadableArticle: Equatable, Sendable {
    public let title: String
    public let contentHTML: String
    public let excerpt: String?
    public let byline: String?
    public let siteName: String?
    public let language: String?

    public init(
        title: String,
        contentHTML: String,
        excerpt: String? = nil,
        byline: String? = nil,
        siteName: String? = nil,
        language: String? = nil
    ) {
        self.title = title
        self.contentHTML = contentHTML
        self.excerpt = excerpt
        self.byline = byline
        self.siteName = siteName
        self.language = language
    }
}

public enum HTMLReadableArticleCleaningPolicy: Equatable, Sendable {
    case sourceFidelity
    case readableArticleParity
}

public enum HTMLReadableArticleExtractionError: Error, Equatable, Sendable {
    case readabilityUnavailable
    case readabilityTimedOut
    case readabilityMalformedResult
    case articleNotFound
    case articleBecameEmptyAfterCleaning
}

public protocol HTMLReadableArticleExtracting: Sendable {
    func extractArticle(from html: String, baseURL: URL) async throws -> HTMLReadableArticle
}

public struct HTMLToMarkdownURLResult: Equatable, Sendable {
    public let finalURL: URL
    public let title: String
    public let cleanedHTML: String
    public let markdown: String
    public let warnings: [HTMLToMarkdownWarning]

    public init(
        finalURL: URL,
        title: String,
        cleanedHTML: String,
        markdown: String,
        warnings: [HTMLToMarkdownWarning]
    ) {
        self.finalURL = finalURL
        self.title = title
        self.cleanedHTML = cleanedHTML
        self.markdown = markdown
        self.warnings = warnings
    }
}

public enum HTMLToMarkdownURLPipelineStage: Equatable, Sendable {
    case fetching
    case extracting
    case converting
}
