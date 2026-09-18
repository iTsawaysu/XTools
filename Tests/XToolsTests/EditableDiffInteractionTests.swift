import AppKit
import SwiftUI
import Testing
@testable import XTools
@testable import XToolsCore

@MainActor
@Suite(.serialized)
struct EditableDiffInteractionTests {
    @Test func navigationIsEnabledOnlyForCurrentResultsWithDifferences() {
        typealias Workspace = IndexEditableDiffWorkspace<EmptyView>

        #expect(!Workspace.navigationEnabled(resultState: .empty, diffCount: 1))
        #expect(!Workspace.navigationEnabled(resultState: .running, diffCount: 1))
        #expect(!Workspace.navigationEnabled(resultState: .stale, diffCount: 1))
        #expect(!Workspace.navigationEnabled(resultState: .current, diffCount: 0))
        #expect(Workspace.navigationEnabled(resultState: .current, diffCount: 1))
    }

    @Test func differenceBlockCountMergesConsecutiveRows() {
        typealias Workspace = IndexEditableDiffWorkspace<EmptyView>
        let rows = [
            DiffAlignedRow(kind: .removed, left: DiffAlignedCell(lineNumber: 1, text: "old 1", indent: 0), right: nil),
            DiffAlignedRow(kind: .added, left: nil, right: DiffAlignedCell(lineNumber: 1, text: "new 1", indent: 0)),
            DiffAlignedRow(kind: .changed, left: DiffAlignedCell(lineNumber: 2, text: "old 2", indent: 0), right: DiffAlignedCell(lineNumber: 2, text: "new 2", indent: 0)),
            DiffAlignedRow(kind: .unchanged, left: DiffAlignedCell(lineNumber: 3, text: "same", indent: 0), right: DiffAlignedCell(lineNumber: 3, text: "same", indent: 0)),
            DiffAlignedRow(kind: .changed, left: DiffAlignedCell(lineNumber: 4, text: "old 3", indent: 0), right: DiffAlignedCell(lineNumber: 4, text: "new 3", indent: 0))
        ]

        #expect(Workspace.differenceBlockCount(in: rows) == 2)
    }

    @Test func editorAccessibilityUsesPaneTitlesAndDescribesFoldedReadOnlyState() throws {
        let left = (1...10).map { "line \($0)" }.joined(separator: "\n")
        var rightLines = (1...10).map { "line \($0)" }
        rightLines[8] = "changed line 9"
        let right = rightLines.joined(separator: "\n")
        let rows = try LineDiffer.safeAlignedDiff(left: left, right: right)
        let leftValue = MutableStringValue(left)
        let rightValue = MutableStringValue(right)
        let coordinator = IndexEditableDiffMergeView.Coordinator(
            left: binding(to: leftValue),
            right: binding(to: rightValue)
        )
        let leftEditor = coordinator.makeEditor(
            side: .left,
            placeholder: "Left",
            accessibilityLabel: "原始 JSON"
        )
        let rightEditor = coordinator.makeEditor(
            side: .right,
            placeholder: "Right",
            accessibilityLabel: "对比 JSON"
        )
        let leftTextView = try #require(textView(in: leftEditor))
        let rightTextView = try #require(textView(in: rightEditor))

        coordinator.update(
            left: left,
            right: right,
            rows: rows,
            syntax: .json,
            foldUnchanged: true
        )

        #expect(leftTextView.accessibilityLabel() == "原始 JSON")
        #expect(rightTextView.accessibilityLabel() == "对比 JSON")
        #expect(!leftTextView.isEditable)
        #expect(!rightTextView.isEditable)
        #expect(leftTextView.accessibilityHelp()?.contains("当前为只读") == true)
        #expect(rightTextView.accessibilityHelp()?.contains("当前为只读") == true)
        #expect(leftTextView.accessibilityValue()?.contains("已折叠") == true)

        coordinator.update(
            left: left,
            right: right,
            rows: rows,
            syntax: .json,
            foldUnchanged: false
        )
        #expect(leftTextView.isEditable)
        #expect(leftTextView.accessibilityHelp() == nil)
    }

    @Test func foldProjectionReplacesBothPanesWhenRightEditorIsFocused() throws {
        let left = (1...30).map { line in
            (line == 5 || line == 26) ? "left change \(line)" : "shared \(line)"
        }.joined(separator: "\n")
        let right = (1...30).map { line in
            (line == 5 || line == 26) ? "right change \(line)" : "shared \(line)"
        }.joined(separator: "\n")
        let rows = try LineDiffer.safeAlignedDiff(left: left, right: right)
        let folded = DiffFoldProjection.apply(rows: rows, expandedRegionIDs: [])
        let region = try #require(DiffFoldProjection.regions(in: rows).first {
            $0.hiddenRowCount == 14
        })
        let leftValue = MutableStringValue(left)
        let rightValue = MutableStringValue(right)
        let coordinator = IndexEditableDiffMergeView.Coordinator(
            left: binding(to: leftValue),
            right: binding(to: rightValue)
        )
        let leftEditor = coordinator.makeEditor(side: .left, placeholder: "Left")
        let rightEditor = coordinator.makeEditor(side: .right, placeholder: "Right")
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

        coordinator.update(left: left, right: right, rows: rows, syntax: .plain, foldUnchanged: false)
        #expect(window.makeFirstResponder(rightTextView))

        coordinator.update(left: left, right: right, rows: rows, syntax: .plain, foldUnchanged: true)

        #expect(leftTextView.string == folded.leftText)
        #expect(rightTextView.string == folded.rightText)
        #expect(!leftTextView.isEditable)
        #expect(!rightTextView.isEditable)
        #expect(rightTextView.accessibilityValue()?.contains("已折叠 14 行") == true)

        #expect(coordinator.textView(rightTextView, clickedOnLink: String(region.id), at: 0))
        #expect(leftTextView.string == left)
        #expect(rightTextView.string == right)
        #expect(leftTextView.isEditable)
        #expect(rightTextView.isEditable)

        coordinator.update(left: left, right: right, rows: rows, syntax: .plain, foldUnchanged: false)
        #expect(leftTextView.string == left)
        #expect(rightTextView.string == right)
    }

    @Test func differenceNavigationUsesTheFocusedRightEditorAsItsAnchor() throws {
        let left = "same\nold one\nsame again\nold two"
        let right = "same\nnew one\nsame again\nnew two"
        let rows = try LineDiffer.safeAlignedDiff(left: left, right: right)
        let leftValue = MutableStringValue(left)
        let rightValue = MutableStringValue(right)
        let coordinator = IndexEditableDiffMergeView.Coordinator(
            left: binding(to: leftValue),
            right: binding(to: rightValue)
        )
        let leftEditor = coordinator.makeEditor(side: .left, placeholder: "Left")
        let rightEditor = coordinator.makeEditor(side: .right, placeholder: "Right")
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
        coordinator.update(
            left: left,
            right: right,
            rows: rows,
            syntax: .plain,
            foldUnchanged: false
        )
        leftTextView.setSelectedRange(NSRange(location: 0, length: 0))
        rightTextView.setSelectedRange((right as NSString).range(of: "new one"))
        #expect(window.makeFirstResponder(rightTextView))

        coordinator.navigateDifference(forward: true)

        #expect(leftTextView.selectedRange().location == 0)
        #expect(rightTextView.selectedRange().location == (right as NSString).range(of: "new two").location)
    }

    @Test func toolbarNavigationRestoresTheLastFocusedPaneAndReportsProgress() throws {
        let left = "stable\nprefix old suffix\nstable again\nprefix before suffix"
        let right = "stable\nprefix new suffix\nstable again\nprefix after suffix"
        let rows = try LineDiffer.safeAlignedDiff(left: left, right: right)
        let leftValue = MutableStringValue(left)
        let rightValue = MutableStringValue(right)
        let coordinator = IndexEditableDiffMergeView.Coordinator(
            left: binding(to: leftValue),
            right: binding(to: rightValue)
        )
        let leftEditor = coordinator.makeEditor(side: .left, placeholder: "Left")
        let rightEditor = coordinator.makeEditor(side: .right, placeholder: "Right")
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
        let toolbarField = NSTextField(string: "Toolbar control")
        contentView.addSubview(toolbarField)
        coordinator.update(left: left, right: right, rows: rows, syntax: .plain, foldUnchanged: false)
        rightTextView.setSelectedRange(NSRange(location: 0, length: 0))
        #expect(window.makeFirstResponder(rightTextView))
        coordinator.textDidBeginEditing(
            Notification(name: NSText.didBeginEditingNotification, object: rightTextView)
        )
        #expect(window.makeFirstResponder(toolbarField), "clicking a toolbar control moves first responder away from the editor")
        var reportedProgress: DiffDifferenceNavigationProgress?
        coordinator.onDifferenceNavigationChange = { reportedProgress = $0 }

        coordinator.navigateDifference(forward: true)

        #expect(window.firstResponder === rightTextView)
        #expect(rightTextView.selectedRange() == NSRange(
            location: (right as NSString).range(of: "new").location,
            length: 0
        ))
        #expect(reportedProgress == DiffDifferenceNavigationProgress(current: 1, total: 2))

        rightTextView.setSelectedRange(NSRange(location: (right as NSString).length, length: 0))
        coordinator.textViewDidChangeSelection(
            Notification(name: NSTextView.didChangeSelectionNotification, object: rightTextView)
        )
        #expect(reportedProgress == DiffDifferenceNavigationProgress(current: nil, total: 2))
    }

    @Test func optionCommandArrowShortcutUsesTheSameCaretNavigationPath() throws {
        let left = "stable\nprefix old suffix"
        let right = "stable\nprefix new suffix"
        let rows = try LineDiffer.safeAlignedDiff(left: left, right: right)
        let leftValue = MutableStringValue(left)
        let rightValue = MutableStringValue(right)
        let mergeView = IndexEditableDiffMergeView(
            left: binding(to: leftValue),
            right: binding(to: rightValue),
            leftPlaceholder: "Left",
            rightPlaceholder: "Right",
            leftAccessibilityLabel: "Shortcut Left",
            rightAccessibilityLabel: "Shortcut Right",
            leftDisplayText: nil,
            rightDisplayText: nil,
            rows: rows,
            syntax: .plain,
            foldUnchanged: false
        )
        let hostingView = NSHostingView(rootView: mergeView)
        hostingView.frame = NSRect(x: 0, y: 0, width: 900, height: 560)
        let window = NSWindow(
            contentRect: hostingView.frame,
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        hostingView.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        let leftTextView = try #require(textView(in: hostingView, accessibilityLabel: "Shortcut Left"))
        leftTextView.setSelectedRange(NSRange(location: 0, length: 0))
        #expect(window.makeFirstResponder(leftTextView))
        let downArrow = try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.option, .command],
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            characters: String(NSDownArrowFunctionKey),
            charactersIgnoringModifiers: String(NSDownArrowFunctionKey),
            isARepeat: false,
            keyCode: 125
        ))

        #expect(window.performKeyEquivalent(with: downArrow))
        #expect(window.firstResponder === leftTextView)
        #expect(leftTextView.selectedRange() == NSRange(
            location: (left as NSString).range(of: "old").location,
            length: 0
        ))
    }

    @Test func differenceNavigationStartsAtFirstBlockThenWrapsByBlock() throws {
        let left = "old one\nstable\nold two"
        let right = "new one\nstable\nnew two"
        let rows = try LineDiffer.safeAlignedDiff(left: left, right: right)
        let leftValue = MutableStringValue(left)
        let rightValue = MutableStringValue(right)
        let coordinator = IndexEditableDiffMergeView.Coordinator(
            left: binding(to: leftValue),
            right: binding(to: rightValue)
        )
        let leftEditor = coordinator.makeEditor(side: .left, placeholder: "Left")
        let rightEditor = coordinator.makeEditor(side: .right, placeholder: "Right")
        let leftTextView = try #require(textView(in: leftEditor))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 560),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let contentView = try #require(window.contentView)
        contentView.addSubview(leftEditor)
        contentView.addSubview(rightEditor)
        coordinator.update(left: left, right: right, rows: rows, syntax: .plain, foldUnchanged: false)
        leftTextView.setSelectedRange(NSRange(location: 0, length: 0))
        #expect(window.makeFirstResponder(leftTextView))

        coordinator.navigateDifference(forward: true)
        #expect(leftTextView.selectedRange().location == 0, "the first request reaches a first-line difference")

        coordinator.navigateDifference(forward: true)
        #expect(leftTextView.selectedRange().location == (left as NSString).range(of: "old two").location)

        coordinator.navigateDifference(forward: true)
        #expect(leftTextView.selectedRange().location == 0, "next wraps after the final block")

        coordinator.navigateDifference(forward: false)
        #expect(leftTextView.selectedRange().location == (left as NSString).range(of: "old two").location)
    }

    @Test func deletionNavigationMovesToThePaneContainingTheDifference() throws {
        let left = "removed\nshared\nold"
        let right = "shared\nnew"
        let rows = [
            DiffAlignedRow(kind: .removed, left: DiffAlignedCell(lineNumber: 1, text: "removed", indent: 0), right: nil),
            DiffAlignedRow(kind: .unchanged, left: DiffAlignedCell(lineNumber: 2, text: "shared", indent: 0), right: DiffAlignedCell(lineNumber: 1, text: "shared", indent: 0)),
            DiffAlignedRow(kind: .changed, left: DiffAlignedCell(lineNumber: 3, text: "old", indent: 0), right: DiffAlignedCell(lineNumber: 2, text: "new", indent: 0))
        ]
        let leftValue = MutableStringValue(left)
        let rightValue = MutableStringValue(right)
        let coordinator = IndexEditableDiffMergeView.Coordinator(
            left: binding(to: leftValue),
            right: binding(to: rightValue)
        )
        let leftEditor = coordinator.makeEditor(side: .left, placeholder: "Left")
        let rightEditor = coordinator.makeEditor(side: .right, placeholder: "Right")
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
        coordinator.update(left: left, right: right, rows: rows, syntax: .plain, foldUnchanged: false)
        rightTextView.setSelectedRange(NSRange(location: 0, length: 0))
        #expect(window.makeFirstResponder(rightTextView))

        coordinator.navigateDifference(forward: true)

        #expect(window.firstResponder === leftTextView)
        #expect(leftTextView.selectedRange().location == 0)
    }

    @Test func foldedNavigationUsesProjectedLinesAndWrapsAcrossHunks() throws {
        let left = (1...32).map { line in
            (line == 5 || line == 28) ? "prefix left \(line) suffix" : "shared \(line)"
        }.joined(separator: "\n")
        let right = (1...32).map { line in
            (line == 5 || line == 28) ? "prefix right \(line) suffix" : "shared \(line)"
        }.joined(separator: "\n")
        let rows = try LineDiffer.safeAlignedDiff(left: left, right: right)
        let folded = DiffFoldProjection.apply(rows: rows, expandedRegionIDs: [])
        let leftValue = MutableStringValue(left)
        let rightValue = MutableStringValue(right)
        let coordinator = IndexEditableDiffMergeView.Coordinator(
            left: binding(to: leftValue),
            right: binding(to: rightValue)
        )
        let leftEditor = coordinator.makeEditor(side: .left, placeholder: "Left")
        let rightEditor = coordinator.makeEditor(side: .right, placeholder: "Right")
        let leftTextView = try #require(textView(in: leftEditor))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 560),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let contentView = try #require(window.contentView)
        contentView.addSubview(leftEditor)
        contentView.addSubview(rightEditor)
        coordinator.update(left: left, right: right, rows: rows, syntax: .plain, foldUnchanged: true)
        leftTextView.setSelectedRange(NSRange(location: 0, length: 0))
        #expect(window.makeFirstResponder(leftTextView))

        coordinator.navigateDifference(forward: true)
        #expect(leftTextView.selectedRange().location == (folded.leftText as NSString).range(of: "left 5").location)

        coordinator.navigateDifference(forward: true)
        #expect(leftTextView.selectedRange().location == (folded.leftText as NSString).range(of: "left 28").location)

        coordinator.navigateDifference(forward: true)
        #expect(leftTextView.selectedRange().location == (folded.leftText as NSString).range(of: "left 5").location)
    }

    @Test func jsonNavigationMovesTheCaretInsideThePrettyPrintedChangedValue() throws {
        let left = #"{"id":7,"name":"Ada","active":true}"#
        let right = #"{"id":7,"name":"Grace","active":true}"#
        let leftDisplay = try #require(JSONStructuralDiff.displayTextForDiff(left))
        let rightDisplay = try #require(JSONStructuralDiff.displayTextForDiff(right))
        let rows = try comparableRows(left: left, right: right)
        let leftValue = MutableStringValue(left)
        let rightValue = MutableStringValue(right)
        let coordinator = IndexEditableDiffMergeView.Coordinator(
            left: binding(to: leftValue),
            right: binding(to: rightValue)
        )
        let leftEditor = coordinator.makeEditor(side: .left, placeholder: "JSON A")
        let rightEditor = coordinator.makeEditor(side: .right, placeholder: "JSON B")
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
        coordinator.update(
            left: leftDisplay,
            right: rightDisplay,
            rows: rows,
            syntax: .json,
            foldUnchanged: false
        )
        rightTextView.setSelectedRange(NSRange(location: 0, length: 0))
        #expect(window.makeFirstResponder(rightTextView))

        coordinator.navigateDifference(forward: true)

        #expect(window.firstResponder === rightTextView)
        #expect(rightTextView.selectedRange() == NSRange(
            location: (rightDisplay as NSString).range(of: "Grace").location,
            length: 0
        ))
    }

    @Test func navigationScrollsADistantDifferenceIntoTheOuterViewport() throws {
        let left = (1...120).map { $0 == 110 ? "prefix old suffix" : "shared \($0)" }.joined(separator: "\n")
        let right = (1...120).map { $0 == 110 ? "prefix new suffix" : "shared \($0)" }.joined(separator: "\n")
        let rows = try LineDiffer.safeAlignedDiff(left: left, right: right)
        let leftValue = MutableStringValue(left)
        let rightValue = MutableStringValue(right)
        let coordinator = IndexEditableDiffMergeView.Coordinator(
            left: binding(to: leftValue),
            right: binding(to: rightValue)
        )
        let leftEditor = coordinator.makeEditor(side: .left, placeholder: "Left")
        let rightEditor = coordinator.makeEditor(side: .right, placeholder: "Right")
        let leftTextView = try #require(textView(in: leftEditor))
        let outerScrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 700, height: 140))
        outerScrollView.hasVerticalScroller = true
        let documentView = NSView(frame: NSRect(x: 0, y: 0, width: 700, height: 2_800))
        documentView.addSubview(leftEditor)
        documentView.addSubview(rightEditor)
        leftEditor.translatesAutoresizingMaskIntoConstraints = true
        rightEditor.translatesAutoresizingMaskIntoConstraints = true
        leftEditor.frame = NSRect(x: 0, y: 0, width: 346, height: 2_800)
        rightEditor.frame = NSRect(x: 354, y: 0, width: 346, height: 2_800)
        outerScrollView.documentView = documentView
        coordinator.outerScrollView = outerScrollView
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 140),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = outerScrollView
        documentView.layoutSubtreeIfNeeded()
        leftEditor.layoutSubtreeIfNeeded()
        rightEditor.layoutSubtreeIfNeeded()
        coordinator.update(left: left, right: right, rows: rows, syntax: .plain, foldUnchanged: false)
        leftTextView.setSelectedRange(NSRange(location: 0, length: 0))
        #expect(window.makeFirstResponder(leftTextView))
        #expect(outerScrollView.contentView.bounds.origin.y == 0)

        coordinator.navigateDifference(forward: true)

        #expect(leftTextView.selectedRange().location == (left as NSString).range(of: "old").location)
        #expect(outerScrollView.contentView.bounds.origin.y > 0)
    }

    @Test func canonicalEquivalentJSONDisplayRefreshUsesExactTextIdentity() throws {
        let composed = "caf\u{00E9}"
        let decomposed = "cafe\u{0301}"
        let leftValue = MutableStringValue(composed)
        let rightValue = MutableStringValue("")
        let coordinator = IndexEditableDiffMergeView.Coordinator(
            left: binding(to: leftValue),
            right: binding(to: rightValue)
        )
        let leftEditor = coordinator.makeEditor(side: .left, placeholder: "Left")
        let leftTextView = try #require(textView(in: leftEditor))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 560),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let contentView = try #require(window.contentView)
        contentView.addSubview(leftEditor)

        coordinator.update(
            left: composed,
            right: "",
            rows: [],
            syntax: .json,
            foldUnchanged: false
        )
        #expect(window.makeFirstResponder(leftTextView))

        coordinator.update(
            left: decomposed,
            right: "",
            rows: [],
            syntax: .json,
            foldUnchanged: false
        )

        #expect(Array(leftTextView.string.utf8) == Array(decomposed.utf8))
    }

    @Test func equivalentRowsKeepSideLocalCopyEditAndUndoText() throws {
        let leftSource = "  SHARED   value"
        let rightSource = "shared value"
        let rows = try LineDiffer.safeAlignedDiff(
            left: leftSource,
            right: rightSource,
            options: TextDiffOptions(ignoreWhitespace: true, ignoreCase: true)
        )
        let leftValue = MutableStringValue(leftSource)
        let rightValue = MutableStringValue(rightSource)
        let coordinator = IndexEditableDiffMergeView.Coordinator(
            left: binding(to: leftValue),
            right: binding(to: rightValue)
        )
        let leftEditor = coordinator.makeEditor(side: .left, placeholder: "Left")
        let rightEditor = coordinator.makeEditor(side: .right, placeholder: "Right")
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

        coordinator.update(
            left: leftSource,
            right: rightSource,
            rows: rows,
            syntax: .plain,
            foldUnchanged: false
        )
        #expect(leftTextView.string == leftSource)
        #expect(rightTextView.string == rightSource)

        rightTextView.setSelectedRange(NSRange(location: 0, length: (rightSource as NSString).length))
        let selectedCopySource = (rightTextView.string as NSString).substring(with: rightTextView.selectedRange())
        #expect(selectedCopySource == rightSource)

        #expect(window.makeFirstResponder(rightTextView))
        rightTextView.setSelectedRange(NSRange(location: (rightSource as NSString).length, length: 0))
        rightTextView.insertText("!", replacementRange: rightTextView.selectedRange())
        rightTextView.breakUndoCoalescing()
        #expect(rightTextView.string == rightSource + "!")
        #expect(leftTextView.string == leftSource)

        let undoManager = try #require(rightTextView.undoManager)
        undoManager.undo()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
        #expect(rightTextView.string == rightSource)
        #expect(leftTextView.string == leftSource)
    }

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

    private func textView(in view: NSView, accessibilityLabel: String) -> NSTextView? {
        if let textView = view as? NSTextView,
           textView.accessibilityLabel() == accessibilityLabel {
            return textView
        }
        for subview in view.subviews {
            if let textView = textView(in: subview, accessibilityLabel: accessibilityLabel) {
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
