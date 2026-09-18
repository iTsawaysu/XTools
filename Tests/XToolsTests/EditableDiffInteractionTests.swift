import AppKit
import SwiftUI
import Testing
@testable import XTools
@testable import XToolsCore

@MainActor
struct EditableDiffInteractionTests {
    @Test func endingRightEditingAppliesCanonicalJSONAndCurrentDiffDecorationsTogether() throws {
        let leftSource = #"{"name":"Ada","active":true}"#
        let rightSource = #"{"name":"Grace","active":false,"port":5432}"#
        let leftDisplay = try #require(JSONStructuralDiff.displayTextForDiff(leftSource))
        let rightDisplay = try #require(JSONStructuralDiff.displayTextForDiff(rightSource))
        let rows = try comparableRows(left: leftSource, right: rightSource)
        let leftValue = MutableStringValue(leftSource)
        let rightValue = MutableStringValue(rightSource)
        let coordinator = IndexEditableDiffMergeView.Coordinator(
            left: binding(to: leftValue),
            right: binding(to: rightValue)
        )
        let leftEditor = coordinator.makeEditor(side: .left, placeholder: "JSON A")
        let rightEditor = coordinator.makeEditor(side: .right, placeholder: "JSON B")
        let leftTextView = try #require(textView(in: leftEditor))
        let rightTextView = try #require(textView(in: rightEditor))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 560),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let contentView = try #require(window.contentView)
        contentView.addSubview(leftEditor)
        contentView.addSubview(rightEditor)
        leftTextView.string = leftSource
        rightTextView.string = rightSource
        #expect(window.makeFirstResponder(rightTextView))

        coordinator.update(
            left: leftDisplay,
            right: rightDisplay,
            rows: rows,
            syntax: .json,
            foldUnchanged: false
        )

        // Fresh JSON computation: canonical text and decorations appear
        // immediately on both sides — including the active right editor —
        // without requiring the user to click away.
        #expect(leftTextView.string == leftDisplay)
        #expect(rightTextView.string == rightDisplay)
        #expect(hasTemporaryBackground(in: leftTextView))
        #expect(hasTemporaryBackground(in: rightTextView))
    }

    @Test func endingRightEditingFallbackStillReconciles() throws {
        let leftSource = #"{"name":"Ada","active":true}"#
        let rightSource = #"{"name":"Grace","active":false,"port":5432}"#
        let leftDisplay = try #require(JSONStructuralDiff.displayTextForDiff(leftSource))
        let rightDisplay = try #require(JSONStructuralDiff.displayTextForDiff(rightSource))
        let rows = try comparableRows(left: leftSource, right: rightSource)
        let leftValue = MutableStringValue(leftSource)
        let rightValue = MutableStringValue(rightSource)
        let coordinator = IndexEditableDiffMergeView.Coordinator(
            left: binding(to: leftValue),
            right: binding(to: rightValue)
        )
        let leftEditor = coordinator.makeEditor(side: .left, placeholder: "JSON A")
        let rightEditor = coordinator.makeEditor(side: .right, placeholder: "JSON B")
        let leftTextView = try #require(textView(in: leftEditor))
        let rightTextView = try #require(textView(in: rightEditor))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 560),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let contentView = try #require(window.contentView)
        contentView.addSubview(leftEditor)
        contentView.addSubview(rightEditor)
        leftTextView.string = leftSource
        rightTextView.string = rightSource
        #expect(window.makeFirstResponder(rightTextView))

        // First call establishes the latest display text.
        coordinator.update(
            left: leftDisplay,
            right: rightDisplay,
            rows: rows,
            syntax: .json,
            foldUnchanged: false
        )

        // Simulate the user editing the right side, reverting to raw source.
        rightTextView.string = rightSource

        // Second update with SAME display text is NOT fresh, so the active
        // editor keeps the user's raw draft.
        coordinator.update(
            left: leftDisplay,
            right: rightDisplay,
            rows: rows,
            syntax: .json,
            foldUnchanged: false
        )
        #expect(rightTextView.string == rightSource)

        // textDidEndEditing fallback still reconciles the active editor.
        coordinator.textDidEndEditing(Notification(name: NSText.didEndEditingNotification, object: rightTextView))
        #expect(rightTextView.string == rightDisplay)
        #expect(hasTemporaryBackground(in: leftTextView))
        #expect(hasTemporaryBackground(in: rightTextView))
    }

    @Test func endingEditingDoesNotDecorateRowsThatDoNotMatchTheOtherVisibleSide() throws {
        let leftSource = #"{"name":"Ada"}"#
        let rightSource = #"{"name":"Grace"}"#
        let leftDisplay = try #require(JSONStructuralDiff.displayTextForDiff(leftSource))
        let rightDisplay = try #require(JSONStructuralDiff.displayTextForDiff(rightSource))
        let rows = try comparableRows(left: leftSource, right: rightSource)
        let leftValue = MutableStringValue(leftSource)
        let rightValue = MutableStringValue(rightSource)
        let coordinator = IndexEditableDiffMergeView.Coordinator(
            left: binding(to: leftValue),
            right: binding(to: rightValue)
        )
        let leftEditor = coordinator.makeEditor(side: .left, placeholder: "JSON A")
        let rightEditor = coordinator.makeEditor(side: .right, placeholder: "JSON B")
        let leftTextView = try #require(textView(in: leftEditor))
        let rightTextView = try #require(textView(in: rightEditor))
        leftTextView.string = #"{"name":"Changed after rows were produced"}"#
        rightTextView.string = rightSource

        coordinator.update(
            left: leftDisplay,
            right: rightDisplay,
            rows: rows,
            syntax: .json,
            foldUnchanged: false
        )
        leftTextView.string = #"{"name":"Still stale"}"#
        coordinator.textDidEndEditing(Notification(name: NSText.didEndEditingNotification, object: rightTextView))

        #expect(rightTextView.string == rightDisplay)
        #expect(!hasTemporaryBackground(in: leftTextView))
        #expect(!hasTemporaryBackground(in: rightTextView))
    }

    private func comparableRows(left: String, right: String) throws -> [DiffAlignedRow] {
        let decision = JSONStructuralDiff.alignedDiff(
            left: left,
            right: right,
            labels: JSONDiffValidation.SideLabels(left: "JSON A", right: "JSON B")
        )
        guard case .comparable(let rows) = decision else {
            Issue.record("Expected comparable JSON diff, got \(decision)")
            return []
        }
        return rows
    }

    private func binding(to value: MutableStringValue) -> Binding<String> {
        Binding(
            get: { value.value },
            set: { value.value = $0 }
        )
    }

    private func textView(in view: NSView) -> NSTextView? {
        if let scrollView = view as? NSScrollView,
           let textView = scrollView.documentView as? NSTextView {
            return textView
        }
        for subview in view.subviews {
            if let textView = textView(in: subview) {
                return textView
            }
        }
        return nil
    }

    private func hasTemporaryBackground(in textView: NSTextView) -> Bool {
        guard let layoutManager = textView.layoutManager else {
            return false
        }
        let length = (textView.string as NSString).length
        return (0..<length).contains { index in
            layoutManager.temporaryAttribute(.backgroundColor, atCharacterIndex: index, effectiveRange: nil) != nil
        }
    }
}

@MainActor
private final class MutableStringValue {
    var value: String

    init(_ value: String) {
        self.value = value
    }
}
