import Foundation

public struct HTMLToMarkdownURLPipeline: Sendable {
    public typealias ProgressHandler = @Sendable (HTMLToMarkdownURLPipelineStage) async -> Void

    private let fetchService: HTMLToMarkdownURLFetchService
    private let extractor: any HTMLReadableArticleExtracting

    public init(
        fetchService: HTMLToMarkdownURLFetchService = HTMLToMarkdownURLFetchService(),
        extractor: any HTMLReadableArticleExtracting
    ) {
        self.fetchService = fetchService
        self.extractor = extractor
    }

    public func convert(
        urlText: String,
        progress: @escaping ProgressHandler = { _ in }
    ) async throws -> HTMLToMarkdownURLResult {
        try Task.checkCancellation()
        await progress(.fetching)
        let fetched = try await fetchService.fetchHTML(from: urlText)

        try Task.checkCancellation()
        await progress(.extracting)
        let article = try await extractor.extractArticle(
            from: fetched.html,
            baseURL: fetched.responseURL
        )

        try Task.checkCancellation()
        await progress(.converting)
        let cleaned = try HTMLReadableArticleCleaner.clean(
            article,
            baseURL: fetched.responseURL,
            policy: .readableArticleParity
        )
        let converted = try HTMLToMarkdownConverter.convert(
            cleaned.contentHTML,
            options: HTMLToMarkdownOptions(
                baseURL: fetched.responseURL,
                liveConversionByteLimit: .max
            ),
            shouldCancel: { Task.isCancelled }
        )

        try Task.checkCancellation()
        return HTMLToMarkdownURLResult(
            finalURL: fetched.responseURL,
            title: cleaned.title,
            cleanedHTML: cleaned.contentHTML,
            markdown: converted.markdown,
            warnings: converted.warnings
        )
    }
}
