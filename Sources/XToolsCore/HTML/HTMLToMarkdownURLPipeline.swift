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
        extractArticleOnly: Bool = true,
        progress: @escaping ProgressHandler = { _ in }
    ) async throws -> HTMLToMarkdownURLResult {
        try Task.checkCancellation()
        await progress(.fetching)
        let fetched = try await fetchService.fetchHTML(from: urlText)

        let cleanedHTML: String
        let title: String
        if extractArticleOnly {
            try Task.checkCancellation()
            await progress(.extracting)
            let article = try await extractor.extractArticle(
                from: fetched.html,
                baseURL: fetched.responseURL
            )

            try Task.checkCancellation()
            let cleaned = try HTMLReadableArticleCleaner.clean(
                article,
                baseURL: fetched.responseURL,
                policy: .readableArticleParity
            )
            cleanedHTML = cleaned.contentHTML
            title = cleaned.title
        } else {
            cleanedHTML = fetched.html
            title = ""
        }

        try Task.checkCancellation()
        await progress(.converting)
        let converted = try HTMLToMarkdownConverter.convert(
            cleanedHTML,
            options: HTMLToMarkdownOptions(
                baseURL: fetched.responseURL,
                liveConversionByteLimit: .max
            ),
            shouldCancel: { Task.isCancelled }
        )

        try Task.checkCancellation()
        return HTMLToMarkdownURLResult(
            finalURL: fetched.responseURL,
            title: title,
            cleanedHTML: cleanedHTML,
            markdown: converted.markdown,
            warnings: converted.warnings
        )
    }
}
