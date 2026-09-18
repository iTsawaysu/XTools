import XToolsCore
import Foundation
@_spi(XToolsTesting) import MarkdownUI
import Testing

struct HTMLToMarkdownConverterTests {
    // MARK: - Headings

    @Test func convertsHeadings() {
        #expect(HTMLToMarkdownConverter.convert("<h1>Title</h1>") == "# Title")
        #expect(HTMLToMarkdownConverter.convert("<h3>Sub</h3>") == "### Sub")
        #expect(HTMLToMarkdownConverter.convert("<h6>Deep</h6>") == "###### Deep")
    }

    @Test func convertsCommonTagsWithAttributes() {
        #expect(HTMLToMarkdownConverter.convert(#"<h1 class="hero">Title</h1>"#) == "# Title")
        #expect(HTMLToMarkdownConverter.convert(#"<p class="lead"><strong data-x="1">Bold</strong></p>"#) == "**Bold**")
        #expect(HTMLToMarkdownConverter.convert(#"<code class="language-swift">let x = 1</code>"#) == "`let x = 1`")
        #expect(HTMLToMarkdownConverter.convert(#"<hr class="sep">"#) == "---")
    }

    // MARK: - Inline emphasis

    @Test func convertsBoldItalicStrikethrough() {
        #expect(HTMLToMarkdownConverter.convert("<strong>x</strong>") == "**x**")
        #expect(HTMLToMarkdownConverter.convert("<b>x</b>") == "**x**")
        #expect(HTMLToMarkdownConverter.convert("<em>x</em>") == "*x*")
        #expect(HTMLToMarkdownConverter.convert("<i>x</i>") == "*x*")
        #expect(HTMLToMarkdownConverter.convert("<del>x</del>") == "~~x~~")
        #expect(HTMLToMarkdownConverter.convert("<strike>x</strike>") == "~~x~~")
    }

    @Test func isCaseInsensitiveOnTags() {
        #expect(HTMLToMarkdownConverter.convert("<STRONG>x</STRONG>") == "**x**")
    }

    // MARK: - Links & images

    @Test func convertsLinks() {
        #expect(HTMLToMarkdownConverter.convert("<a href=\"https://example.com\">link</a>") == "[link](https://example.com)")
    }

    @Test func decodesBasicHTMLEntities() {
        #expect(HTMLToMarkdownConverter.convert("<p>Tom &amp; Jerry&nbsp;&#x1F600;</p>") == "Tom & Jerry 😀")
        #expect(HTMLToMarkdownConverter.convert("<code>&lt;tag&gt;</code>") == "`<tag>`")
    }

    @Test func preservesLiteralMarkdownTextWithoutChangingItsParsedMeaning() {
        let html = """
        <p># literal heading</p><p>- literal list</p><p>1. literal ordered list</p>
        <p>&gt; literal quote</p><p>**literal strong** and *literal emphasis*</p>
        <p>[literal link](https://example.com) and ---</p>
        """

        let markdown = HTMLToMarkdownConverter.convert(html)

        #expect(markdown == """
        \\# literal heading

        \\- literal list

        1\\. literal ordered list

        \\> literal quote

        \\*\\*literal strong\\*\\* and \\*literal emphasis\\*

        \\[literal link\\](https\\://example.com) and ---
        """)

        let parsedHTML = MarkdownContent(markdown).renderHTML()
        #expect(!parsedHTML.contains("<h1>"))
        #expect(!parsedHTML.contains("<ul>"))
        #expect(!parsedHTML.contains("<ol>"))
        #expect(!parsedHTML.contains("<blockquote>"))
        #expect(!parsedHTML.contains("<strong>"))
        #expect(!parsedHTML.contains("<em>"))
        #expect(!parsedHTML.contains("<a "))
        #expect(!parsedHTML.contains("<hr"))
    }

    @Test func preservesBlockMarkerTextSplitAcrossInlineDOMNodes() {
        let html = """
        <p><span>#</span> literal heading</p>
        <p><span>-</span> literal list</p>
        <p><span>1</span>. literal ordered list</p>
        <p><span>&gt;</span> literal quote</p>
        """

        let markdown = HTMLToMarkdownConverter.convert(html)
        let parsedHTML = MarkdownContent(markdown).renderHTML()

        #expect(parsedHTML.components(separatedBy: "<p>").count - 1 == 4)
        #expect(!parsedHTML.contains("<h1>"))
        #expect(!parsedHTML.contains("<ul>"))
        #expect(!parsedHTML.contains("<ol>"))
        #expect(!parsedHTML.contains("<blockquote>"))
    }

    @Test func preservesOrdinaryGFMUrlAndEmailTextWithoutCreatingLinks() {
        let expected = "https://example.com www.example.com user@example.com"
        let markdown = HTMLToMarkdownConverter.convert(
            "<p>\(expected)</p>"
        )
        let parsed = MarkdownContent(markdown)

        #expect(markdown.contains("user@<!-- -->example.com"))
        #expect(!parsed.renderHTML().contains("<a "))
        #expect(parsed.renderPlainText() == expected)
        #expect(!markdown.contains("\u{200B}"))
    }

    @Test func markdownUIParserDoesNotCreateMailtoForCommentSeparatedEmail() {
        let markdown = HTMLToMarkdownConverter.convert("<p>user@example.com</p>")
        let vendorRenderedHTML = MarkdownContent(markdown).renderHTML()

        #expect(markdown == "user@<!-- -->example.com")
        #expect(!vendorRenderedHTML.contains("mailto:"))
        #expect(!vendorRenderedHTML.contains("<a "))
    }

    @Test func markdownUIAttributedRendererShowsLiteralEmailWithoutCommentOrLink() throws {
        let markdown = HTMLToMarkdownConverter.convert("<p>user@example.com</p>")
        let attributed = try #require(
            MarkdownContent(markdown).renderFirstTextBlockAttributedString()
        )

        #expect(String(attributed.characters) == "user@example.com")
        #expect(attributed.runs.allSatisfy { $0.link == nil })
    }

    @Test func preservesBackticksAnglesAndMarkersAsOrdinaryPlainText() {
        let samples = [
            ("<p>`literal` and ``two``</p>", "`literal` and ``two``"),
            ("<p>&lt;tag&gt; and 1 &lt; 2 &gt; 0</p>", "<tag> and 1 < 2 > 0"),
            ("<p># heading marker</p>", "# heading marker"),
            ("<p>- list marker</p>", "- list marker"),
            ("<p>1. ordered marker</p>", "1. ordered marker"),
            ("<p>&gt; quote marker</p>", "> quote marker")
        ]

        for (html, expected) in samples {
            let markdown = HTMLToMarkdownConverter.convert(html)
            let parsed = MarkdownContent(markdown)

            #expect(parsed.renderPlainText() == expected)
            #expect(!parsed.renderHTML().contains("<code>"))
            #expect(!parsed.renderHTML().contains("<blockquote>"))
        }
    }

    @Test func preservesBlockMarkerTextSplitAcrossRootInlineNodes() {
        let markdown = HTMLToMarkdownConverter.convert("<span>-</span> literal root text")

        #expect(MarkdownContent(markdown).renderHTML() == "<p>- literal root text</p>\n")
    }

    @Test func convertsImagesInBothAttributeOrders() {
        #expect(HTMLToMarkdownConverter.convert("<img src=\"a.png\" alt=\"cap\">") == "![cap](a.png)")
        // alt-before-src order is handled by a second pattern
        #expect(HTMLToMarkdownConverter.convert("<img alt=\"cap\" src=\"a.png\">") == "![cap](a.png)")
        // src only, no alt
        #expect(HTMLToMarkdownConverter.convert("<img src=\"a.png\">") == "![](a.png)")
    }

    // MARK: - Unsafe and unsupported HTML

    @Test func ignoresScriptAndStyleContentWhileKeepingVisibleBody() {
        let html = """
        <style>
          body { color: red; }
        </style>
        <script>
          alert("xss");
        </script>
        <h1>Visible Title</h1>
        <p>Visible paragraph.</p>
        """

        let markdown = HTMLToMarkdownConverter.convert(html)

        #expect(markdown.contains("# Visible Title"))
        #expect(markdown.contains("Visible paragraph."))
        #expect(!markdown.contains("alert"))
        #expect(!markdown.contains("color: red"))
        #expect(!markdown.localizedCaseInsensitiveContains("<script"))
        #expect(!markdown.localizedCaseInsensitiveContains("<style"))
    }

    @Test func degradesBrokenHTMLToReadableText() {
        let html = "<div><h1>Broken HTML<p>Paragraph <strong>bold <em>italic</strong></p></div>"
        let markdown = HTMLToMarkdownConverter.convert(html)

        #expect(!markdown.isEmpty)
        #expect(markdown.contains("Broken HTML"))
        #expect(markdown.contains("Paragraph"))
        #expect(markdown.contains("bold"))
        #expect(markdown.contains("italic"))
        #expect(!markdown.contains("<"))
        #expect(!markdown.contains(">"))
    }

    @Test func degradesFormsAndDetailsToReadableText() {
        let html = """
        <form action="/search" method="get">
          <label>Keyword <input name="q" value="json"></label>
          <button type="submit">Search</button>
        </form>
        <details open>
          <summary>More</summary>
          <p>Hidden by default in HTML, but should be visible in Markdown if converted.</p>
        </details>
        """

        let markdown = HTMLToMarkdownConverter.convert(html)

        #expect(markdown.contains("Keyword"))
        #expect(markdown.contains("json"))
        #expect(markdown.contains("Search"))
        #expect(markdown.contains("More"))
        #expect(markdown.contains("Hidden by default in HTML"))
        #expect(!markdown.localizedCaseInsensitiveContains("<form"))
        #expect(!markdown.localizedCaseInsensitiveContains("<input"))
        #expect(!markdown.localizedCaseInsensitiveContains("<button"))
        #expect(!markdown.localizedCaseInsensitiveContains("<details"))
        #expect(!markdown.localizedCaseInsensitiveContains("<summary"))
    }

    // MARK: - Code

    @Test func convertsInlineAndBlockCode() {
        #expect(HTMLToMarkdownConverter.convert("<code>x</code>") == "`x`")
        #expect(HTMLToMarkdownConverter.convert("<pre><code>let x = 1</code></pre>") == "```\nlet x = 1\n```")
    }

    @Test func codeContentKeepsMarkdownCharactersVerbatim() {
        let inline = HTMLToMarkdownConverter.convert("<code>*[]#|\\\\</code>")
        let block = HTMLToMarkdownConverter.convert("<pre><code>*[]#|\\\\</code></pre>")

        #expect(inline == "`*[]#|\\\\`")
        #expect(block == "```\n*[]#|\\\\\n```")
    }

    @Test func preservesFenceLanguageHints() {
        let html = #"<pre><code class="language-swift">let x = 1</code></pre>"#
        #expect(HTMLToMarkdownConverter.convert(html) == "```swift\nlet x = 1\n```")
    }

    // MARK: - Lists

    @Test func convertsUnorderedList() {
        let html = "<ul><li>a</li><li>b</li></ul>"
        #expect(HTMLToMarkdownConverter.convert(html) == "+ a\n+ b")
    }

    @Test func convertsOrderedListWithIncrementingNumbers() {
        let html = "<ol><li>a</li><li>b</li><li>c</li></ol>"
        #expect(HTMLToMarkdownConverter.convert(html) == "1. a\n2. b\n3. c")
    }

    @Test func convertsNestedListsAndTaskItems() {
        let html = """
        <ul>
          <li><input type="checkbox" checked> done</li>
          <li><input type="checkbox"> todo
            <ul><li>child</li></ul>
          </li>
        </ul>
        """

        let markdown = HTMLToMarkdownConverter.convert(html)

        #expect(markdown.contains("+ [x] done"))
        #expect(markdown.contains("+ [ ] todo"))
        #expect(markdown.contains("  + child"))
    }

    // MARK: - Blockquotes

    @Test func convertsBlockquote() {
        #expect(HTMLToMarkdownConverter.convert("<blockquote>quoted</blockquote>") == "> quoted")
    }

    // MARK: - Horizontal rule & line break

    @Test func convertsHorizontalRule() {
        #expect(HTMLToMarkdownConverter.convert("<hr>") == "---")
    }

    // MARK: - Tables

    @Test func convertsTableWithHeaderSeparator() {
        let html = "<table><tr><th>A</th><th>B</th></tr><tr><td>1</td><td>2</td></tr></table>"
        #expect(HTMLToMarkdownConverter.convert(html) == "| A | B |\n| --- | --- |\n| 1 | 2 |")
    }

    @Test func convertsTableWithoutHeaderTreatsFirstRowAsHeader() {
        let html = "<table><tr><td>1</td><td>2</td></tr><tr><td>3</td><td>4</td></tr></table>"
        #expect(HTMLToMarkdownConverter.convert(html) == "| 1 | 2 |\n| --- | --- |\n| 3 | 4 |")
    }

    @Test func recursivelyConvertsInlineTagsInTableCells() {
        let html = "<table><tr><td><strong>bold</strong></td></tr></table>"
        #expect(HTMLToMarkdownConverter.convert(html) == "| **bold** |\n| --- |")
    }

    @Test func escapesPipesInsideTableCells() {
        let html = "<table><tr><th>Name</th><th>Value</th></tr><tr><td>A | B</td><td>1</td></tr></table>"
        #expect(HTMLToMarkdownConverter.convert(html) == "| Name | Value |\n| --- | --- |\n| A \\| B | 1 |")
    }

    @Test func escapesLiteralMarkdownInsideLinkLabelsAndTableCells() {
        let link = HTMLToMarkdownConverter.convert("<a href=\"https://example.com\">[literal] *label*</a>")
        let table = HTMLToMarkdownConverter.convert("<table><tr><td>**literal** | [cell]</td></tr></table>")

        #expect(link == "[\\[literal\\] \\*label\\*](https://example.com)")
        #expect(table == "| \\*\\*literal\\*\\* \\| \\[cell\\] |\n| --- |")
    }

    @Test func escapesCodePipesAtTheTableSerializationBoundary() {
        let html = "<table><tr><th>Value</th><th>Other</th></tr><tr><td><code>a|b</code></td><td>x</td></tr></table>"
        let markdown = HTMLToMarkdownConverter.convert(html)

        #expect(markdown == "| Value | Other |\n| --- | --- |\n| `a\\|b` | x |")
        #expect(MarkdownContent(markdown).renderHTML().contains("<code>a|b</code>"))
    }

    @Test func completedLargeManualInputKeepsResultAndEmitsCompletedWarning() {
        let input = "<p>" + String(repeating: "x", count: 512_001) + "</p>"
        let result = HTMLToMarkdownConverter.convert(input, options: .manual)

        #expect(!result.markdown.isEmpty)
        #expect(result.warnings.contains(.completedInputExceedsThreshold(HTMLToMarkdownInputBudget.manual.completedResultThreshold!)))
    }

    @Test func inputAbovePreParseLimitFailsBeforeRendering() {
        let input = "<p>" + String(repeating: "x", count: HTMLToMarkdownInputBudget.manual.preParseByteLimit + 1) + "</p>"
        let counter = HTMLConverterCancelCounter()

        #expect {
            _ = try HTMLToMarkdownConverter.convert(input, options: .manual, shouldCancel: {
                _ = counter.incrementAndRead()
                return false
            })
        } throws: { error in
            error as? HTMLToMarkdownConversionError == .inputExceedsPreParseByteLimit(
                HTMLToMarkdownInputBudget.manual.preParseByteLimit
            )
        }
        #expect(counter.value == 1, "超限输入必须在 parser/traversal 前拒绝")
    }

    @Test func nonThrowingConvenienceReportsOversizedInputWithoutCrashing() {
        let input = "<p>" + String(
            repeating: "x",
            count: HTMLToMarkdownInputBudget.manual.preParseByteLimit + 1
        ) + "</p>"

        let result = HTMLToMarkdownConverter.convert(input, options: .manual)

        #expect(result.markdown.isEmpty)
        #expect(result.warnings.isEmpty)
        #expect(
            result.error == .inputExceedsPreParseByteLimit(
                HTMLToMarkdownInputBudget.manual.preParseByteLimit
            )
        )
        #expect(HTMLToMarkdownConverter.convert(input).isEmpty)
    }

    @Test func oversizedWhitespaceInputStillFailsThePreParseBudget() {
        let input = String(
            repeating: " ",
            count: HTMLToMarkdownInputBudget.manual.preParseByteLimit + 1
        )

        let result = HTMLToMarkdownConverter.convert(input, options: .manual)

        #expect(result.markdown.isEmpty)
        #expect(result.warnings.isEmpty)
        #expect(
            result.error == .inputExceedsPreParseByteLimit(
                HTMLToMarkdownInputBudget.manual.preParseByteLimit
            )
        )
    }

    @Test func returnsWarningsForDroppedAndFlattenedHTML() {
        let result = HTMLToMarkdownConverter.convert(
            "<script>alert(1)</script><table><tr><th colspan=\"2\">A</th></tr></table>",
            options: HTMLToMarkdownOptions()
        )

        #expect(result.warnings.contains(.droppedUnsafeElement("script")))
        #expect(result.warnings.contains(.flattenedTableSpan))
    }

    @Test func resolvesRelativeLinksAndImagesAgainstBaseURL() throws {
        let baseURL = try #require(URL(string: "https://example.com/docs/page.html"))
        let markdown = HTMLToMarkdownConverter.convert(
            #"<a href="../guide">Guide</a><img src="/assets/a.png" alt="A">"#,
            options: HTMLToMarkdownOptions(baseURL: baseURL)
        ).markdown

        #expect(markdown.contains("[Guide](https://example.com/guide)"))
        #expect(markdown.contains("![A](https://example.com/assets/a.png)"))
    }

    // MARK: - Whitespace cleanup

    @Test func collapsesExcessBlankLinesAndTrims() {
        // three paragraphs would produce many blank lines; cleanup collapses runs to \n\n
        let html = "<p>a</p><p>b</p>"
        #expect(HTMLToMarkdownConverter.convert(html) == "a\n\nb")
    }

    // MARK: - Cooperative cancellation

    @Test func cancellableConvertThrowsWhenShouldCancelFlips() {
        let nestedItems = (0..<80).map { index in
            "<li><p>Item \(index)</p><ul><li>Nested \(index)a</li><li>Nested \(index)b</li></ul></li>"
        }.joined()
        let html = "<div><h1>Cancel me</h1><ul>\(nestedItems)</ul><table><tr><th>A</th><th>B</th></tr><tr><td>1</td><td>2</td></tr></table></div>"

        let counter = HTMLConverterCancelCounter()
        #expect(throws: CancellationError.self) {
            try HTMLToMarkdownConverter.convert(html, shouldCancel: {
                counter.incrementAndRead() > 12
            })
        }
        #expect(counter.value > 12)
    }

    @Test func cancellableConvertMatchesNonCancellableWhenNeverCancelled() throws {
        let html = "<h1>Title</h1><p><strong>Bold</strong> and <em>italic</em></p><ul><li>a</li><li>b</li></ul>"
        let baseline = HTMLToMarkdownConverter.convert(html, options: HTMLToMarkdownOptions())
        let cancellable = try HTMLToMarkdownConverter.convert(
            html,
            options: HTMLToMarkdownOptions(),
            shouldCancel: { false }
        )
        #expect(cancellable == baseline)
    }

    // MARK: - Source contracts

    @Test func converterUsesDOMRendererAndKeepsCompatibilityAPI() throws {
        let converter = try readSource("Sources/XToolsCore/HTML/HTMLToMarkdownConverter.swift")
        let renderer = try readSource("Sources/XToolsCore/HTML/HTMLToMarkdownDOMRenderer.swift")

        contains(converter, "public static func convert(_ html: String) -> String", "HTML-to-Markdown must keep the existing string-only compatibility API")
        contains(converter, "options: HTMLToMarkdownOptions = HTMLToMarkdownOptions()", "HTML-to-Markdown must expose the richer result/warning API")
        contains(converter, "shouldCancel: @escaping @Sendable () -> Bool", "HTML-to-Markdown must expose a cancellable convert entry")
        contains(converter, "HTMLToMarkdownDOMRenderer(options: options, shouldCancel: shouldCancel).convert(html)", "The public converter must delegate to the DOM renderer")
        doesNotContain(converter, "legacyRegexConvert", "The old regex conversion path must not remain as a dormant fallback")
        doesNotContain(converter, "HTMLToMarkdownRegexCatalog", "The public converter file must not keep the retired regex catalog")
        contains(renderer, "import SwiftSoup", "The renderer must use SwiftSoup instead of treating HTML as regex-only text")
        contains(renderer, "SwiftSoup.parseHTML", "The renderer must parse HTML into a DOM before conversion")
        contains(renderer, "renderNode", "The renderer must own rule-based node traversal")
        contains(renderer, "cancellation.check()", "The renderer must check cooperative cancellation during traversal")
    }
}

private final class HTMLConverterCancelCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue = 0

    var value: Int {
        lock.withLock { storedValue }
    }

    func incrementAndRead() -> Int {
        lock.withLock {
            storedValue += 1
            return storedValue
        }
    }
}

struct HTMLToMarkdownURLFetchServiceTests {
    @Test func networkFailuresDoNotRetainSystemErrorText() async {
        let service = HTMLToMarkdownURLFetchService(
            client: FailingHTMLToMarkdownURLFetchClient()
        )

        await #expect {
            _ = try await service.fetchHTML(from: "https://example.com/private")
        } throws: { error in
            guard case HTMLToMarkdownURLFetchError.requestFailed = error else { return false }
            let message = HTMLToMarkdownDiagnostics.urlFetchErrorMessage(for: .requestFailed)
            ToolDiagnosticContract.expectFactual(
                message,
                sensitiveInputs: ["NSURLErrorDomain /tmp/private timeout"]
            )
            return true
        }
    }

    @Test func normalizesBareDomainsToHTTPS() throws {
        #expect(try HTMLToMarkdownURLFetchService.normalizedURL(from: "example.com").absoluteString == "https://example.com")
        #expect {
            _ = try HTMLToMarkdownURLFetchService.normalizedURL(from: "file:///tmp/a.html")
        } throws: { error in
            guard case HTMLToMarkdownURLFetchError.unsupportedScheme("file") = error else {
                return false
            }
            return true
        }
    }

    @Test func rejectsInvalidURLsAndRandomInput() {
        let invalidInputs = [
            "123",
            "99999",
            "abc",
            "123.456",
            "-example.com",
            "example-.com",
            "foo..bar.com",
            ".example.com",
            "example.com.",
            "http://",
            "https://",
            "ftp://example.com",
            "javascript:alert(1)",
            "example.c", // single letter TLD
            "http://127.0.0.1",
            "http://localhost",
            "http://192.168.1.1"
        ]

        for input in invalidInputs {
            #expect(!HTMLToMarkdownURLFetchService.isValidURL(input), "Expected \(input) to be invalid")
            #expect(throws: (any Error).self) {
                _ = try HTMLToMarkdownURLFetchService.normalizedURL(from: input)
            }
        }
    }

    @Test func allowsValidDomainsAndPublicIPs() throws {
        let validInputs = [
            "example.com",
            "https://example.com",
            "http://example.com",
            "sub.domain.example.com",
            "https://sub.domain.example.com/path?q=1#ref",
            "8.8.8.8",
            "https://8.8.8.8/index.html",
            "github.com/trending"
        ]

        for input in validInputs {
            #expect(HTMLToMarkdownURLFetchService.isValidURL(input), "Expected \(input) to be valid")
            #expect(throws: Never.self) {
                _ = try HTMLToMarkdownURLFetchService.normalizedURL(from: input)
            }
        }
    }

    @Test func fetchesAndDecodesHTMLWithCharset() async throws {
        let url = try #require(URL(string: "https://example.com/page"))
        let response = try #require(HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "text/html; charset=iso-8859-1"]
        ))
        let service = HTMLToMarkdownURLFetchService(
            client: FakeHTMLToMarkdownURLFetchClient(
                data: Data([0x63, 0x61, 0x66, 0xE9]),
                response: response
            )
        )

        let fetched = try await service.fetchHTML(from: "https://example.com/page")

        #expect(fetched.html == "café")
        #expect(fetched.responseURL == url)
    }

    @Test func fetchRejectsOversizedResponses() async throws {
        let url = try #require(URL(string: "https://example.com/page"))
        let response = try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil))
        let service = HTMLToMarkdownURLFetchService(
            client: FakeHTMLToMarkdownURLFetchClient(
                data: Data("abcdef".utf8),
                response: response
            )
        )

        await #expect {
            _ = try await service.fetchHTML(
                from: "https://example.com/page",
                options: HTMLToMarkdownURLFetchOptions(responseBodyByteLimit: 3)
            )
        } throws: { error in
            guard case HTMLToMarkdownURLFetchError.responseTooLarge(3) = error else {
                return false
            }
            return true
        }
    }

    @Test func defaultURLResponseBudgetRemainsFiveMiB() {
        #expect(HTMLToMarkdownURLFetchOptions.defaultResponseBodyByteLimit == 5 * 1024 * 1024)
        #expect(HTMLToMarkdownURLFetchOptions().responseBodyByteLimit == 5 * 1024 * 1024)
    }

    @Test func fetchRejectsHTTPFailures() async throws {
        let url = try #require(URL(string: "https://example.com/missing"))
        let response = try #require(HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil))
        let service = HTMLToMarkdownURLFetchService(
            client: FakeHTMLToMarkdownURLFetchClient(
                data: Data("missing".utf8),
                response: response
            )
        )

        await #expect {
            _ = try await service.fetchHTML(from: "https://example.com/missing")
        } throws: { error in
            guard case HTMLToMarkdownURLFetchError.unacceptableStatusCode(404) = error else {
                return false
            }
            return true
        }
    }
}

private struct FailingHTMLToMarkdownURLFetchClient: HTMLToMarkdownURLFetchClient {
    func fetchData(
        for request: URLRequest,
        byteLimit: Int
    ) async throws -> (Data, URLResponse) {
        throw NSError(
            domain: "NSURLErrorDomain",
            code: -1001,
            userInfo: [NSLocalizedDescriptionKey: "NSURLErrorDomain /tmp/private timeout"]
        )
    }
}

private struct FakeHTMLToMarkdownURLFetchClient: HTMLToMarkdownURLFetchClient {
    var data: Data
    var response: URLResponse

    func fetchData(
        for request: URLRequest,
        byteLimit: Int
    ) async throws -> (Data, URLResponse) {
        (data, response)
    }
}
