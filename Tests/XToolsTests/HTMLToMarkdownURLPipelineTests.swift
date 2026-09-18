import Foundation
import Testing
@testable import XTools
@testable import XToolsCore

struct HTMLReadableArticleCleanerTests {
    @Test func readableArticleParityRemovesTemplateNoiseAndBuildsReferenceStyleMarkdown() throws {
        let baseURL = try #require(URL(string: "https://example.com/docs/article.html"))
        let article = HTMLReadableArticle(
            title: "Article Title",
            contentHTML: """
            <div id="readability-page-1" class="page">
              <main class="theme-default-content">
                <nav><a href="/home">Site navigation</a></nav>
                <h1><a class="header-anchor" href="#article-title">#</a> Article Title</h1>
                <ul class="table-of-contents">
                  <li><a href="#section">Section</a></li>
                </ul>
                <h2 id="section"><a class="header-anchor" href="#section">#</a> Section</h2>
                <p>Main paragraph.</p>
                <ul><li>Reference URL mode omits this list.</li></ul>
                <pre><code class="language-swift">let hidden = true</code></pre>
                <p><img src="/images/diagram.png" alt="Diagram"></p>
                <h2>References</h2>
                <footer>Footer template</footer>
              </main>
            </div>
            """,
            excerpt: "Summary",
            byline: "Author",
            siteName: "Example",
            language: "en"
        )

        let cleaned = try HTMLReadableArticleCleaner.clean(
            article,
            baseURL: baseURL,
            policy: .readableArticleParity
        )
        let converted = HTMLToMarkdownConverter.convert(
            cleaned.contentHTML,
            options: HTMLToMarkdownOptions(baseURL: baseURL, inputBudget: .urlFetchedDocument)
        )

        #expect(cleaned.contentHTML.contains("readability-page-1"))
        #expect(cleaned.contentHTML.contains("https://example.com/images/diagram.png"))
        #expect(!cleaned.contentHTML.contains("Site navigation"))
        #expect(!cleaned.contentHTML.contains("table-of-contents"))
        #expect(!cleaned.contentHTML.contains("header-anchor"))
        #expect(!cleaned.contentHTML.contains("Reference URL mode omits this list."))
        #expect(!cleaned.contentHTML.contains("let hidden = true"))
        #expect(!cleaned.contentHTML.contains("Footer template"))
        #expect(converted.markdown == """
        ## Article Title

        ## Section

        Main paragraph.

        ![Diagram](https://example.com/images/diagram.png)

        ## References
        """)
    }

    @Test func sourceFidelityPolicyKeepsListsAndCodeBlocks() throws {
        let baseURL = try #require(URL(string: "https://example.com/docs/article.html"))
        let article = HTMLReadableArticle(
            title: "Article",
            contentHTML: """
            <article>
              <h1>Article</h1>
              <ul><li>Kept item</li></ul>
              <pre><code class="language-swift">let kept = true</code></pre>
            </article>
            """
        )

        let cleaned = try HTMLReadableArticleCleaner.clean(
            article,
            baseURL: baseURL,
            policy: .sourceFidelity
        )
        let markdown = HTMLToMarkdownConverter.convert(
            cleaned.contentHTML,
            options: HTMLToMarkdownOptions(baseURL: baseURL, inputBudget: .urlFetchedDocument)
        ).markdown

        #expect(markdown.contains("+ Kept item"))
        #expect(markdown.contains("```swift\nlet kept = true\n```"))
    }

    @Test func parityCleanerRejectsArticleThatBecomesEmpty() throws {
        let baseURL = try #require(URL(string: "https://example.com"))
        let article = HTMLReadableArticle(
            title: "Navigation only",
            contentHTML: "<nav><a href=\"/\">Home</a></nav><footer>Footer</footer>"
        )

        #expect {
            _ = try HTMLReadableArticleCleaner.clean(
                article,
                baseURL: baseURL,
                policy: .readableArticleParity
            )
        } throws: { error in
            error as? HTMLReadableArticleExtractionError == .articleBecameEmptyAfterCleaning
        }
    }
}

struct HTMLToMarkdownURLPipelineTests {
    @Test @MainActor func pipelineReturnsCleanedHTMLAndMarkdownFromInjectedExtractor() async throws {
        let url = try #require(URL(string: "https://example.com/article"))
        let response = try #require(HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "text/html; charset=utf-8"]
        ))
        let fetchService = HTMLToMarkdownURLFetchService(
            client: PipelineHTMLFetchClient(
                data: Data("<html><body><article>raw</article></body></html>".utf8),
                response: response
            )
        )
        let extractor = PipelineReadableArticleExtractor(
            result: HTMLReadableArticle(
                title: "Pipeline Article",
                contentHTML: "<article><h1>Pipeline Article</h1><p>Body.</p></article>"
            )
        )
        let pipeline = HTMLToMarkdownURLPipeline(
            fetchService: fetchService,
            extractor: extractor
        )

        let result = try await pipeline.convert(urlText: url.absoluteString)

        #expect(result.finalURL == url)
        #expect(result.title == "Pipeline Article")
        #expect(result.cleanedHTML.contains("<h2>Pipeline Article</h2>"))
        #expect(result.markdown == "## Pipeline Article\n\nBody.")
        #expect(extractor.receivedBaseURL == url)
        #expect(extractor.receivedHTML.contains("<article>raw</article>"))
    }
}

struct HTMLToMarkdownURLFetchValidationTests {
    @Test func rejectsClearlyNonHTMLContentTypes() async throws {
        let url = try #require(URL(string: "https://example.com/data.json"))
        let response = try #require(HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        ))
        let service = HTMLToMarkdownURLFetchService(
            client: PipelineHTMLFetchClient(
                data: Data(#"{"value":1}"#.utf8),
                response: response
            )
        )

        await #expect {
            _ = try await service.fetchHTML(from: url.absoluteString)
        } throws: { error in
            error as? HTMLToMarkdownURLFetchError == .unsupportedContentType
        }
    }

    @Test func decodesHTMLMetaCharsetBeforeLatin1Fallback() async throws {
        let url = try #require(URL(string: "https://example.com/cp1252"))
        let response = try #require(HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "text/html"]
        ))
        var data = Data(#"<html><head><meta charset="windows-1252"></head><body><p>Price: "#.utf8)
        data.append(0x80)
        data.append(contentsOf: Data("10</p></body></html>".utf8))
        let service = HTMLToMarkdownURLFetchService(
            client: PipelineHTMLFetchClient(data: data, response: response)
        )

        let fetched = try await service.fetchHTML(from: url.absoluteString)

        #expect(fetched.html.contains("Price: €10"))
    }
}

@MainActor
private final class PipelineReadableArticleExtractor: HTMLReadableArticleExtracting {
    let result: HTMLReadableArticle
    private(set) var receivedHTML = ""
    private(set) var receivedBaseURL: URL?

    init(result: HTMLReadableArticle) {
        self.result = result
    }

    func extractArticle(from html: String, baseURL: URL) async throws -> HTMLReadableArticle {
        receivedHTML = html
        receivedBaseURL = baseURL
        return result
    }
}

private struct PipelineHTMLFetchClient: HTMLToMarkdownURLFetchClient {
    let data: Data
    let response: URLResponse

    func fetchData(
        for request: URLRequest,
        byteLimit: Int
    ) async throws -> (Data, URLResponse) {
        (data, response)
    }
}
