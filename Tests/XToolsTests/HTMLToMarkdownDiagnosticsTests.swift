import XToolsCore
import Testing

struct HTMLToMarkdownDiagnosticsTests {
    @Test func emptyWarningsYieldNil() {
        #expect(HTMLToMarkdownDiagnostics.conversionWarningMessage(for: []) == nil)
    }

    @Test func singleUnsupportedElementWarning() {
        let message = HTMLToMarkdownDiagnostics.conversionWarningMessage(
            for: [.unsupportedElement("canvas")]
        )
        #expect(message == "部分 HTML 内容无法完整转换。")
        ToolDiagnosticContract.expectFactual(message ?? "")
    }

    @Test func allWarningCasesMatchGoldenChinese() {
        #expect(
            HTMLToMarkdownDiagnostics.warningText(for: .unsupportedElement("svg"))
                == "部分 HTML 内容无法完整转换。"
        )
        #expect(
            HTMLToMarkdownDiagnostics.warningText(for: .flattenedTableSpan)
                == "复杂表格无法完整转换。"
        )
        #expect(
            HTMLToMarkdownDiagnostics.warningText(for: .droppedUnsafeElement("script"))
                == "部分 HTML 内容无法完整转换。"
        )
        #expect(
            HTMLToMarkdownDiagnostics.warningText(for: .emptyVisibleContent)
                == "未检测到可见内容。"
        )
        #expect(
            HTMLToMarkdownDiagnostics.warningText(for: .completedInputExceedsThreshold(512_000))
                == "输入超过 500 KB，本次已完成转换。"
        )
    }

    @Test func emptyVisibleContentRemainsThePrimaryWarning() {
        let message = HTMLToMarkdownDiagnostics.conversionWarningMessage(
            for: [.emptyVisibleContent, .flattenedTableSpan]
        )
        #expect(message == "未检测到可见内容。")
        ToolDiagnosticContract.expectFactual(message ?? "")
    }

    @Test func allURLFetchErrorsMatchGoldenChinese() {
        #expect(HTMLToMarkdownDiagnostics.urlFetchErrorMessage(for: .emptyURL)
            == "URL 为空。")
        #expect(HTMLToMarkdownDiagnostics.urlFetchErrorMessage(for: .invalidURL)
            == "URL 格式无效；仅支持 http 或 https 地址。")
        #expect(HTMLToMarkdownDiagnostics.urlFetchErrorMessage(for: .unsupportedScheme("ftp"))
            == "`ftp` 协议不支持；仅支持 http 或 https。")
        #expect(HTMLToMarkdownDiagnostics.urlFetchErrorMessage(for: .requestFailed)
            == "无法获取 URL，网络请求失败或连接中断。")
        #expect(HTMLToMarkdownDiagnostics.urlFetchErrorMessage(for: .nonHTTPResponse)
            == "URL 没有返回 HTTP 响应。")
        #expect(HTMLToMarkdownDiagnostics.urlFetchErrorMessage(for: .unacceptableStatusCode(404))
            == "URL 返回 HTTP 404，无法转换。")
        #expect(HTMLToMarkdownDiagnostics.urlFetchErrorMessage(for: .unsupportedContentType)
            == "URL 返回的不是 HTML 页面。")
        #expect(HTMLToMarkdownDiagnostics.urlFetchErrorMessage(for: .responseTooLarge(2_000_000))
            == "页面超过 \(ByteSizeFormatter.format(bytes: 2_000_000)) 上限，已停止获取。")
        #expect(HTMLToMarkdownDiagnostics.urlFetchErrorMessage(for: .emptyResponse)
            == "URL 返回空内容。")
        #expect(HTMLToMarkdownDiagnostics.urlFetchErrorMessage(for: .undecodableText)
            == "无法识别页面文本编码。")
    }

    @Test func allArticleExtractionErrorsMatchGoldenChinese() {
        #expect(HTMLToMarkdownDiagnostics.articleExtractionErrorMessage(for: .readabilityUnavailable)
            == "未能识别网页正文。")
        #expect(HTMLToMarkdownDiagnostics.articleExtractionErrorMessage(for: .readabilityTimedOut)
            == "网页正文解析超时。")
        #expect(HTMLToMarkdownDiagnostics.articleExtractionErrorMessage(for: .readabilityMalformedResult)
            == "网页正文解析结果无效。")
        #expect(HTMLToMarkdownDiagnostics.articleExtractionErrorMessage(for: .articleNotFound)
            == "未能识别网页正文。")
        #expect(HTMLToMarkdownDiagnostics.articleExtractionErrorMessage(for: .articleBecameEmptyAfterCleaning)
            == "网页正文清理后没有可转换内容。")
    }

    @Test func warningNamesAndSchemesDoNotEchoUnboundedInput() {
        let longElement = "private-secret-" + String(repeating: "x", count: 120)
        let warning = HTMLToMarkdownDiagnostics.conversionWarningMessage(
            for: [
                .unsupportedElement(longElement),
                .droppedUnsafeElement("bad element private-secret")
            ]
        )

        #expect(warning?.contains("private-secret") == false)
        #expect(warning == "部分 HTML 内容无法完整转换。")
        ToolDiagnosticContract.expectFactual(
            warning ?? "",
            sensitiveInputs: [longElement, "bad element private-secret"]
        )

        let scheme = "private-secret-" + String(repeating: "x", count: 80)
        let schemeMessage = HTMLToMarkdownDiagnostics.urlFetchErrorMessage(
            for: .unsupportedScheme(scheme)
        )
        #expect(schemeMessage == "`未知` 协议不支持；仅支持 http 或 https。")
        ToolDiagnosticContract.expectFactual(
            schemeMessage,
            sensitiveInputs: [scheme]
        )
    }

    @Test func converterFacadeStillExistsAndConverts() {
        // Deletion guard: Converter is a real contract, not a pass-through to delete.
        let result = HTMLToMarkdownConverter.convert("<p>hi</p>")
        #expect(result == "hi" || result.contains("hi"))
        #expect(HTMLToMarkdownInputBudget.manual.completedResultThreshold == 512_000)
    }

    @Test func repeatedElementWarningsCollapseToOnePrimarySummary() {
        let message = HTMLToMarkdownDiagnostics.conversionWarningMessage(
            for: [
                .unsupportedElement("canvas"),
                .unsupportedElement("video"),
                .unsupportedElement("canvas"),
                .droppedUnsafeElement("script"),
                .droppedUnsafeElement("style")
            ]
        )

        #expect(message == "部分 HTML 内容无法完整转换。")
    }

    @Test func userMixedElementSampleKeepsStructuredWarningsAndUsesPrimarySummary() {
        let html = """
        <h1>Visible</h1>
        <script>alert('xss')</script>
        <style>body{display:none}</style>
        <template><p>template-only</p></template>
        <iframe src="https://example.com/embed"></iframe>
        <video src="movie.mp4">Video fallback</video>
        <audio src="sound.mp3">Audio fallback</audio>
        <svg><text>Vector label</text></svg>
        <p>Still visible</p>
        """

        let result = HTMLToMarkdownConverter.convert(html, options: HTMLToMarkdownOptions())

        #expect(result.markdown == "# Visible\n\n    [https\\://example.com/embed](https://example.com/embed) [movie.mp4](movie.mp4) [sound.mp3](sound.mp3) Vector label \n\nStill visible")
        #expect(result.warnings.contains(.droppedUnsafeElement("script")))
        #expect(result.warnings.contains(.droppedUnsafeElement("style")))
        #expect(result.warnings.contains(.droppedUnsafeElement("template")))
        #expect(result.warnings.contains(.unsupportedElement("video")))
        #expect(HTMLToMarkdownDiagnostics.conversionWarningMessage(for: result.warnings) == "部分 HTML 内容无法完整转换。")
    }

    @Test func userComplexTableSampleKeepsTableWarningAndUsesPrimarySummary() {
        let html = """
        <table>
          <tr><th rowspan="2">Name</th><th colspan="2">Scores</th></tr>
          <tr><th>Math</th><th>English</th></tr>
          <tr><td>Alice</td><td>95</td><td>88</td></tr>
        </table>
        """

        let result = HTMLToMarkdownConverter.convert(html, options: HTMLToMarkdownOptions())

        #expect(result.markdown == "| Name | Scores |  |\n| --- | --- | --- |\n| Math | English |  |\n| Alice | 95 | 88 |")
        #expect(result.warnings.contains(.flattenedTableSpan))
        #expect(HTMLToMarkdownDiagnostics.conversionWarningMessage(for: result.warnings) == "复杂表格无法完整转换。")
    }
}
