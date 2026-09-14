import XToolsCore
import Testing

@Suite("HTMLToMarkdownSessionProjection")
struct HTMLToMarkdownSessionProjectionTests {
    @Test
    func urlProcessingPhases() {
        #expect(HTMLToMarkdownSessionProjection.isURLProcessing(.fetching))
        #expect(HTMLToMarkdownSessionProjection.isURLProcessing(.extracting))
        #expect(HTMLToMarkdownSessionProjection.isURLProcessing(.converting(.url)))
        #expect(!HTMLToMarkdownSessionProjection.isURLProcessing(.converting(.manual)))
        #expect(!HTMLToMarkdownSessionProjection.isURLProcessing(.ready))
    }

    @Test
    func processingTextMatchesProductCopy() {
        #expect(HTMLToMarkdownSessionProjection.processingText(.fetching) == "正在获取网页…")
        #expect(HTMLToMarkdownSessionProjection.processingText(.extracting) == "正在提取正文…")
        #expect(HTMLToMarkdownSessionProjection.processingText(.converting(.manual)) == "正在转换 Markdown…")
        #expect(HTMLToMarkdownSessionProjection.processingText(.waitingForManualConversion) == "等待输入完成…")
        #expect(HTMLToMarkdownSessionProjection.processingText(.ready) == nil)
    }
}
