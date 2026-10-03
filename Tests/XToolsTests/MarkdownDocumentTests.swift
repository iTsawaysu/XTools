import Foundation
import SwiftUI
import Testing
@testable import XTools
@testable import XToolsCore

/// MarkdownDocument（swift-cmark 解析 + 自有渲染出口）的行为测试：
/// HTMLToMarkdownConverterTests 用本模块做 GFM oracle，这里补齐解析结构、
/// 原始 HTML 处理、行内渲染与检测器 AST 遍历的覆盖面。
struct MarkdownDocumentTests {
    // MARK: - 解析结构

    @Test func parseCapturesGFMStructure() throws {
        let blocks = MarkdownDocument.parse(
            """
            ### Head

            | Left | Right |
            | :--- | ---: |
            | a | b |

            3. third

            - [x] done
            - [ ] open

            Some ~~struck~~ text with an ![img](https://example.com/i.png).
            """
        )

        let heading = try #require(blocks.first)
        #expect(heading == .heading(level: 3, content: [.text("Head")]))

        let table = try #require(blocks.first { if case .table = $0 { return true } else { return false } })
        guard case .table(let alignments, let rows) = table else {
            Issue.record("expected table")
            return
        }
        #expect(alignments == [.left, .right])
        #expect(rows.count == 2)

        let ordered = try #require(blocks.first { if case .numberedList = $0 { return true } else { return false } })
        guard case .numberedList(_, let start, _) = ordered else {
            Issue.record("expected ordered list")
            return
        }
        #expect(start == 3)

        guard case .taskList(_, let tasks) = try #require(blocks.first(where: { if case .taskList = $0 { return true } else { return false } })) else {
            Issue.record("expected task list")
            return
        }
        #expect(tasks.map(\.isCompleted) == [true, false])

        let paragraph = try #require(blocks.last)
        guard case .paragraph(let inlines) = paragraph else {
            Issue.record("expected paragraph")
            return
        }
        #expect(inlines.contains { if case .strikethrough = $0 { return true } else { return false } })
        #expect(inlines.contains { if case .image(let source, _) = $0 { return source == "https://example.com/i.png" } else { return false } })
    }

    @Test func emptyInputParsesToNoBlocks() {
        #expect(MarkdownDocument.parse("").isEmpty)
    }

    // MARK: - 渲染出口（oracle 行为）

    @Test func renderHTMLEmitsGFMTableAndTaskCheckbox() throws {
        let html = MarkdownDocument.parse(
            """
            | A | B |
            | --- | ---: |
            | 1 | 2 |

            - [x] done
            """
        ).renderHTML()

        #expect(html.contains("<table"))
        #expect(html.contains("<th>"))
        #expect(html.contains("<td>"))
        #expect(html.contains("checkbox"))
        #expect(html.contains("checked"))
    }

    @Test func renderHTMLOmitsRawHTMLLikeVendoredOracle() {
        // cmark 非 UNSAFE 模式把原始 HTML 输出为注释（vendored renderHTML 同行为）；
        // 预览里原始 HTML 由视图层按纯文本渲染，两者互不影响。
        let html = MarkdownDocument.parse("<div class=\"x\">raw</div>\n\nafter").renderHTML()
        #expect(html.contains("<!-- raw HTML omitted -->"))
        #expect(html.contains("<p>after</p>"))
    }

    @Test func renderPlainTextSkipsRawHTMLAndKeepsPlainLines() {
        // renderPlainText 走 cmark_render_plaintext：软换行输出为换行，原始 HTML 不输出。
        let text = MarkdownDocument.parse("line one\nline two\n\n<div>noise</div>").renderPlainText()
        #expect(text == "line one\nline two")
    }

    // MARK: - 行内渲染

    @Test func inlineRendererHidesHTMLCommentsAndRendersBRAndLiteralHTML() throws {
        let styleSet = MarkdownInlineStyleSet.plain
        let paragraph = try #require(MarkdownDocument.parse("a<!-- hidden -->b\n<br>c<i>d</i>").first)
        guard case .paragraph(let inlines) = paragraph else {
            Issue.record("expected paragraph")
            return
        }
        let attributed = inlines.reduce(into: AttributedString()) { $0 += $1.renderAttributedString(styleSet: styleSet) }

        // 注释不可见 → "ab"；软换行折叠为空格，<br> 输出换行（空格在换行前，
        // 与上游 softBreak→space + br→lineBreak 的顺序一致）；其余行内 HTML 按字面渲染。
        #expect(String(attributed.characters) == "ab \nc<i>d</i>")
        #expect(attributed.runs.allSatisfy { $0.link == nil })
    }

    @Test func firstTextBlockAttributedStringShowsLiteralEmailWithoutLink() throws {
        let attributed = try #require(
            MarkdownDocument.parse("user@<!-- -->example.com").renderFirstTextBlockAttributedString()
        )
        #expect(String(attributed.characters) == "user@example.com")
        #expect(attributed.runs.allSatisfy { $0.link == nil })
    }

    @Test func firstTextBlockAttributedStringCarriesLinkDestination() throws {
        let attributed = try #require(
            MarkdownDocument.parse("[label](https://example.com/x)").renderFirstTextBlockAttributedString()
        )
        let linkRuns = attributed.runs.compactMap(\.link)
        #expect(linkRuns == [URL(string: "https://example.com/x")!])
    }

    @Test func nestedStylesComposeInsteadOfOverwriting() throws {
        let attributed = try #require(
            MarkdownDocument.parse("***both***").renderFirstTextBlockAttributedString()
        )
        #expect(String(attributed.characters) == "both")
        // 粗斜体必须同时具备 italic 与 semibold：字段级组合不能让 semibold 冲掉 italic。
        let expectedFont = Font.system(size: 13, weight: .semibold, design: .default).italic()
        let fonts = attributed.runs.compactMap { $0.font }
        #expect(fonts == [expectedFont])
    }

    // MARK: - 远程图片检测（AST 直查）

    @Test func detectorFindsImagesInNestedContainers() {
        let detected = [
            "> ![quoted](https://example.com/quoted.png)",
            "| [linked ![cell](https://example.com/cell.png)](https://example.com/) | x |\n| --- | --- |\n| a | b |",
            "- ![in list](https://example.com/list.png)",
            "1. ![in ordered](https://example.com/ordered.png)",
            "- [ ] ![in task](https://example.com/task.png)",
            "[![wrapped](https://example.com/wrapped.png)](https://example.com/)",
        ]
        for markdown in detected {
            #expect(MarkdownRemoteImageDetector.containsRemoteImage(in: markdown), "must detect: \(markdown)")
        }
    }

    @Test func detectorBoundedBySourceByteLimitBeforeParsing() {
        let oversized = String(
            repeating: "x",
            count: MarkdownRemoteImageDetector.maximumSourceByteCount + 1
        ) + "![late](https://example.com/late.png)"
        #expect(!MarkdownRemoteImageDetector.containsRemoteImage(in: oversized))
    }
}
