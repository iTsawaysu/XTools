import AppKit
import Testing
@testable import XTools

@MainActor
@Suite(.serialized)
struct RenderingBudgetRegressionTests {
    @Test func diffGeometryWorkIsBoundedByViewportAtBothDocumentEnds() throws {
        let text = (0..<10_000).map { "line \($0)" }.joined(separator: "\n")
        let view = editor(text)
        let all = IndexDiffTextLayoutGeometry.lineBlockRects(for: view)
        for line in [1, 5_000, 9_990] {
            let target = try #require(all[line])
            let viewport = NSRect(x: 0, y: target.minY, width: 500, height: 140)
            let rects = IndexDiffTextLayoutGeometry.lineBlockRects(for: view, visibleRect: viewport)
            #expect(rects.count <= 16, "Gutter work must include visible lines and small overscan only")
            #expect(rects[line]?.intersects(viewport) == true)
        }
    }

    @Test func diffGeometryMapsGlyphsBackToUTF16ForEmojiAndCombiningText() throws {
        let text = (0..<150).map { "👩🏽‍💻 e\u{301} ffi line \($0)" }.joined(separator: "\n")
        let view = editor(text)
        let all = IndexDiffTextLayoutGeometry.lineBlockRects(for: view)
        let target = try #require(all[100])
        let viewport = NSRect(x: 0, y: target.minY, width: 500, height: 55)
        let visible = IndexDiffTextLayoutGeometry.lineBlockRects(for: view, visibleRect: viewport)
        let actual = Set(all.filter { $0.value.intersects(viewport) }.keys)
        #expect(actual.isSubset(of: Set(visible.keys)))
        #expect(visible.count <= actual.count + 4, "Glyph offsets are not UTF-16 offsets")
    }

    @Test func giantLogicalLineKeepsExactSelectableTextWithoutUnboundedTokenApplication() throws {
        let text = "{" + Array(repeating: #""key":1"#, count: 16_384).joined(separator: ",") + "}"
        let view = editor(text)
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 500, height: 160))
        scroll.documentView = view
        let base = NSColor.labelColor
        let highlighter = IndexViewportHighlighting()
        var reports: [Bool] = []
        highlighter.onDegradationChange = { reports.append($0) }
        highlighter.install(scrollView: scroll, textView: view, syntax: .json, baseAttributes: [.foregroundColor: base])
        view.setSelectedRange(NSRange(location: 2, length: 3))
        highlighter.contentChanged(text: text, syntax: .json)
        let storage = try #require(view.textStorage)
        #expect(storage.attribute(.foregroundColor, at: 2, effectiveRange: nil) as? NSColor == base,
                "An over-budget logical line must stay plain instead of applying every token")
        #expect(view.string.utf8.elementsEqual(text.utf8))
        #expect(view.selectedRange() == NSRange(location: 2, length: 3))
        view.selectAll(nil)
        #expect(view.selectedRange().length == (text as NSString).length)
        #expect(highlighter.lastPassTokenCount == 0)
        #expect(highlighter.lastPassUTF16Count == 0)
        #expect(reports == [true])
        view.string = #"{"small":1}"#
        highlighter.contentChanged(text: view.string, syntax: .json)
        #expect(reports == [true, false])
        #expect(storage.attribute(.foregroundColor, at: 2, effectiveRange: nil) as? NSColor == IndexSyntaxToken.Kind.key.nsColor)
    }

    @Test func diffSourceIndexRebuildsOnlyForCharacterEdits() throws {
        let view = editor("a\nb\n")
        let storage = try #require(view.textStorage)
        let index = IndexDiffTextIndex(storage: storage)
        #expect(index.ranges.count == 3)
        let revision = index.revision
        storage.addAttribute(.foregroundColor, value: NSColor.red, range: NSRange(location: 0, length: 1))
        for _ in 0..<20 { #expect(index.ranges.count == 3) }
        #expect(index.rebuildCount == 1)
        #expect(index.revision == revision)
        storage.replaceCharacters(in: NSRange(location: 0, length: 1), with: "👩🏽‍💻\n")
        #expect(index.ranges.count == 4)
        #expect(index.rebuildCount == 2)
        #expect(index.revision > revision)
        #expect(index.ranges[2].location == ("👩🏽‍💻\n\n" as NSString).length)
    }

    @Test func denseTokenLineAndPerPassApplicationStayWithinBudgets() throws {
        let text = String(repeating: "[", count: IndexSyntaxHighlightBudget.maximumLineUTF16)
        let view = editor(text)
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 500, height: 160))
        scroll.documentView = view
        let highlighter = IndexViewportHighlighting()
        highlighter.install(scrollView: scroll, textView: view, syntax: .json, baseAttributes: [.foregroundColor: NSColor.labelColor])
        var limited = false
        highlighter.onDegradationChange = { limited = $0 }
        highlighter.contentChanged(text: text, syntax: .json)
        #expect(limited)
        #expect(highlighter.lastPassUTF16Count <= IndexSyntaxHighlightBudget.maximumPassUTF16)
        #expect(highlighter.lastPassTokenCount == 0)
        #expect(view.string == text)
    }

    private func editor(_ text: String) -> NSTextView {
        let view = NSTextView(frame: NSRect(x: 0, y: 0, width: 500, height: 300))
        view.font = .monospacedSystemFont(ofSize: 12.5, weight: .regular)
        view.textContainerInset = NSSize(width: 10, height: 10)
        view.textContainer?.containerSize = NSSize(width: 480, height: CGFloat.greatestFiniteMagnitude)
        view.textContainer?.widthTracksTextView = false
        view.string = text
        return view
    }
}
