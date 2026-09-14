import Foundation
import Testing
@testable import XTools
@testable import XToolsCore

@MainActor
struct HTMLReadableArticleExtractorTests {
    @Test func extractsArticleWithoutReturningPageScripts() async throws {
        let baseURL = try #require(URL(string: "https://example.com/articles/test"))
        let longBody = String(repeating: "Readable article sentence with enough words for candidate scoring. ", count: 18)
        let html = """
        <!doctype html>
        <html>
          <head><title>Readable Test</title></head>
          <body>
            <nav>Navigation links that are not article content.</nav>
            <script>document.body.innerHTML = '<p>Script executed</p>';</script>
            <article>
              <h1>Readable Test</h1>
              <p>\(longBody)</p>
            </article>
            <footer>Footer template.</footer>
          </body>
        </html>
        """
        let extractor = WebKitHTMLReadableArticleExtractor(timeout: 20)

        let article = try await extractor.extractArticle(from: html, baseURL: baseURL)

        #expect(article.title.contains("Readable Test"))
        #expect(article.contentHTML.contains("Readable article sentence"))
        #expect(!article.contentHTML.contains("Script executed"))
        #expect(!article.contentHTML.contains("Navigation links"))
        #expect(!article.contentHTML.contains("Footer template"))
    }

    @Test func livePdaiReferenceProbeWhenExplicitlyEnabled() async throws {
        guard ProcessInfo.processInfo.environment["HTML_MD_LIVE_REFERENCE"] == "1" else {
            return
        }

        let pipeline = HTMLToMarkdownURLPipeline(
            extractor: WebKitHTMLReadableArticleExtractor(timeout: 15)
        )
        let result = try await pipeline.convert(
            urlText: "https://www.pdai.tech/md/java/basic/java-basic-oop.html"
        )
        try result.cleanedHTML.write(
            to: URL(fileURLWithPath: "/tmp/tools-pdai-cleaned.html"),
            atomically: true,
            encoding: .utf8
        )
        try result.markdown.write(
            to: URL(fileURLWithPath: "/tmp/tools-pdai-parity.md"),
            atomically: true,
            encoding: .utf8
        )

        #expect(result.markdown.hasPrefix("## Java 基础 - 面向对象"))
        #expect(result.markdown.contains("## 三大特性"))
        #expect(result.markdown.contains("## 类图"))
        #expect(result.markdown.hasSuffix("## 参考资料"))
        #expect(!result.markdown.contains("Java 全栈知识体系"))
        #expect(!result.markdown.contains("站点图"))
    }

    @Test func cancellationDoesNotPublishAReadabilityFailure() async throws {
        let baseURL = try #require(URL(string: "https://example.com"))
        let extractor = WebKitHTMLReadableArticleExtractor(timeout: 20)
        let task = Task {
            try await extractor.extractArticle(
                from: "<html><body><article><p>\(String(repeating: "content ", count: 500))</p></article></body></html>",
                baseURL: baseURL
            )
        }

        task.cancel()

        await #expect {
            _ = try await task.value
        } throws: { error in
            error is CancellationError
        }
    }
}
