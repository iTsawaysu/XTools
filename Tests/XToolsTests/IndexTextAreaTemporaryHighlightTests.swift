import AppKit
import SwiftUI
@testable import XTools
import Testing

struct IndexTextAreaTemporaryHighlightProjectionTests {
    @Test func characterOffsetsProjectToUTF16Ranges() {
        let cases: [(String, IndexTextAreaCharacterRange, NSRange)] = [
            ("a12b", .init(start: 1, end: 3), NSRange(location: 1, length: 2)),
            ("甲咖啡乙", .init(start: 1, end: 3), NSRange(location: 1, length: 2)),
            ("A👩‍💻B", .init(start: 1, end: 2), NSRange(location: 1, length: 5)),
            ("Ae\u{301}B", .init(start: 1, end: 2), NSRange(location: 1, length: 2))
        ]

        for (text, characterRange, expected) in cases {
            let ranges = IndexTextAreaCharacterRangeProjection.utf16Ranges(
                in: text,
                characterRanges: [characterRange]
            )
            #expect(ranges == [expected])
        }
    }

    @Test func zeroLengthInvalidAndOutOfOrderRangesAreNotPainted() {
        let ranges = IndexTextAreaCharacterRangeProjection.utf16Ranges(
            in: "abcdef",
            characterRanges: [
                .init(start: 1, end: 1),
                .init(start: -1, end: 2),
                .init(start: 1, end: 3),
                .init(start: 2, end: 4),
                .init(start: 8, end: 9),
                .init(start: 4, end: 6)
            ]
        )

        #expect(ranges == [
            NSRange(location: 1, length: 2),
            NSRange(location: 4, length: 2)
        ])
    }
}

@MainActor
struct IndexTextAreaTemporaryHighlightRendererTests {
    @Test func temporaryBackgroundPreservesTextSelectionAndUndoState() throws {
        let textView = HighlightTestTextView(frame: NSRect(x: 0, y: 0, width: 480, height: 160))
        textView.string = "A👩‍💻B"
        textView.setSelectedRange(NSRange(location: 6, length: 0))
        textView.testUndoManager.registerUndo(withTarget: textView) { _ in }
        let selection = textView.selectedRange()
        let canUndo = textView.testUndoManager.canUndo

        IndexTextAreaTemporaryHighlightRenderer.apply(
            IndexTextAreaTemporaryHighlights(
                sourceText: textView.string,
                ranges: [NSRange(location: 1, length: 5)]
            ),
            to: textView
        )

        #expect(textView.string == "A👩‍💻B")
        #expect(textView.selectedRange() == selection)
        #expect(textView.testUndoManager.canUndo == canUndo)
        #expect(hasTemporaryBackground(in: textView, range: NSRange(location: 1, length: 5)))
        #expect(!hasTemporaryBackground(in: textView, range: NSRange(location: 0, length: 1)))
    }

    @Test func staleSourceMarkedTextAndInvalidRangesClearOrSkipBackground() {
        let textView = HighlightTestTextView(frame: NSRect(x: 0, y: 0, width: 480, height: 160))
        textView.string = "abcdef"

        IndexTextAreaTemporaryHighlightRenderer.apply(
            .init(sourceText: textView.string, ranges: [NSRange(location: 1, length: 2)]),
            to: textView
        )
        #expect(hasTemporaryBackground(in: textView, range: NSRange(location: 1, length: 2)))

        IndexTextAreaTemporaryHighlightRenderer.apply(
            .init(sourceText: "stale", ranges: [NSRange(location: 1, length: 2)]),
            to: textView
        )
        #expect(!hasAnyTemporaryBackground(in: textView))

        textView.reportsMarkedText = true
        IndexTextAreaTemporaryHighlightRenderer.apply(
            .init(sourceText: textView.string, ranges: [NSRange(location: 1, length: 2)]),
            to: textView
        )
        #expect(!hasAnyTemporaryBackground(in: textView))

        textView.reportsMarkedText = false
        IndexTextAreaTemporaryHighlightRenderer.apply(
            .init(
                sourceText: textView.string,
                ranges: [
                    NSRange(location: 0, length: 0),
                    NSRange(location: 2, length: 2),
                    NSRange(location: 99, length: 1)
                ]
            ),
            to: textView
        )
        #expect(hasTemporaryBackground(in: textView, range: NSRange(location: 2, length: 2)))
        #expect(!hasTemporaryBackground(in: textView, range: NSRange(location: 0, length: 1)))
    }

    @Test func userEditClearsExistingTemporaryBackgroundBeforePublishingText() {
        let textValue = MutableHighlightTestValue("abc")
        let heightValue = MutableHighlightTestHeight(0)
        let coordinator = IndexUndoableTextView.Coordinator(
            text: binding(to: textValue),
            measuredHeight: binding(to: heightValue),
            growsWithContent: true,
            inputPolicy: nil
        )
        let textView = HighlightTestTextView(frame: NSRect(x: 0, y: 0, width: 480, height: 160))
        textView.string = "abcd"
        IndexTextAreaTemporaryHighlightRenderer.apply(
            .init(sourceText: textView.string, ranges: [NSRange(location: 0, length: 2)]),
            to: textView
        )
        #expect(hasAnyTemporaryBackground(in: textView))

        coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: textView))

        #expect(!hasAnyTemporaryBackground(in: textView))
        #expect(textValue.value == "abcd")
    }

    private func binding(to value: MutableHighlightTestValue) -> Binding<String> {
        Binding(get: { value.value }, set: { value.value = $0 })
    }

    private func binding(to value: MutableHighlightTestHeight) -> Binding<CGFloat> {
        Binding(get: { value.value }, set: { value.value = $0 })
    }

    private func hasAnyTemporaryBackground(in textView: NSTextView) -> Bool {
        let length = (textView.string as NSString).length
        guard length > 0 else { return false }
        return hasTemporaryBackground(in: textView, range: NSRange(location: 0, length: length))
    }

    private func hasTemporaryBackground(in textView: NSTextView, range: NSRange) -> Bool {
        guard let layoutManager = textView.layoutManager else { return false }
        return (range.location..<range.upperBound).contains { index in
            layoutManager.temporaryAttribute(.backgroundColor, atCharacterIndex: index, effectiveRange: nil) != nil
        }
    }
}

@MainActor
private final class MutableHighlightTestValue {
    var value: String

    init(_ value: String) {
        self.value = value
    }
}

@MainActor
private final class MutableHighlightTestHeight {
    var value: CGFloat

    init(_ value: CGFloat) {
        self.value = value
    }
}

@MainActor
private final class HighlightTestTextView: NSTextView {
    let testUndoManager = UndoManager()
    var reportsMarkedText = false

    override var undoManager: UndoManager? {
        testUndoManager
    }

    override func hasMarkedText() -> Bool {
        reportsMarkedText
    }
}
