import AppKit
import SwiftUI
import Testing
@testable import XTools
@testable import XToolsCore

@MainActor
@Suite(.serialized)
struct EditableDiffInteractionTests {
    /// Mirrors the canonical display form the production diff pipeline renders
    /// (sorted keys, 2-space indent), built from public formatting API.
    private func canonicalDisplayText(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return try? JSONFormatting.format(trimmed, sortKeys: true, sortArrays: false, indentWidth: 2)
    }

    @Test func absentDiagnosticLeavesNoReservedStatusRowAboveThePanes() async throws {
        let model = DiffDiagnosticProbeModel()
        let hosting = NSHostingView(rootView: DiffDiagnosticProbe(model: model))
        hosting.frame = NSRect(x: 0, y: 0, width: 1000, height: 500)
        hosting.layoutSubtreeIfNeeded()
        let editor = try #require(textView(in: hosting))
        let viewport = try #require(editor.enclosingScrollView)
        let originalFrame = viewport.convert(viewport.bounds, to: hosting)

        // The toolbar is 44pt; only the normal 8pt pane inset may follow it.
        let topInset = hosting.isFlipped ? originalFrame.minY : hosting.bounds.maxY - originalFrame.maxY
        #expect(abs(topInset - 52) < 0.5, "No diff diagnostic must leave no reserved status row")

        model.error = "对比输入有误"
        try await Task.sleep(for: .milliseconds(60))
        hosting.layoutSubtreeIfNeeded()
        let diagnosticFrame = viewport.convert(viewport.bounds, to: hosting)
        #expect(abs(diagnosticFrame.height - (originalFrame.height - 36)) < 0.5,
                "A visible diff diagnostic must occupy exactly its own 36pt status row")
        #expect(diagnosticFrame.minX == originalFrame.minX && diagnosticFrame.width == originalFrame.width)

        model.error = nil
        try await Task.sleep(for: .milliseconds(60))
        hosting.layoutSubtreeIfNeeded()
        #expect(viewport.convert(viewport.bounds, to: hosting) == originalFrame,
                "Clearing the diff diagnostic must reclaim the status row")
    }

    @Test func rejectedNativeFileDropShowsThroughSharedSlotAndDismisses() async throws {
        let model = DiffDiagnosticProbeModel()
        // Swift Testing has no assistive-technology client; enable the SwiftUI
        // semantic tree for this fixture so the dismiss control is pressable
        // through real accessibility actions (never a fake closure call).
        let hosting = NSHostingView(
            rootView: DiffDiagnosticProbe(model: model).environment(\.accessibilityEnabled, true)
        )
        hosting.frame = NSRect(x: 0, y: 0, width: 1000, height: 500)
        let window = NSWindow(
            contentRect: hosting.frame,
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        window.makeKeyAndOrderFront(nil)
        defer {
            window.orderOut(nil)
            window.contentView = nil
        }
        hosting.layoutSubtreeIfNeeded()
        let editor = try #require(textView(in: hosting))
        let viewport = try #require(editor.enclosingScrollView)
        let originalFrame = viewport.convert(viewport.bounds, to: hosting)
        #expect(findDismissAction(in: window) == nil, "No rejection must show no dismiss control")

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("XToolsDiffRejection-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let malformed = directory.appendingPathComponent("invalid-utf8.txt")
        try Data([0xC3]).write(to: malformed)

        let native = try #require(editor as? IndexDiffTextView)
        native.loadDroppedFile(from: malformed)
        try await waitUntilLayout(window, hosting, "rejection row and dismiss control") {
            findDismissAction(in: window) != nil
        }
        let rejectionFrame = viewport.convert(viewport.bounds, to: hosting)
        #expect(abs(rejectionFrame.height - (originalFrame.height - 36)) < 0.5,
                "The rejection must occupy exactly its own 36pt status row")

        #expect(try #require(findDismissAction(in: window)).press())
        try await waitUntilLayout(window, hosting, "dismiss reclaims the status row") {
            findDismissAction(in: window) == nil
                && viewport.convert(viewport.bounds, to: hosting) == originalFrame
        }
        #expect(native.string == model.left, "Dismissing the rejection must preserve the user draft")
    }

    @Test func rejectedNativeFileDropReportsDiagnosticAndKeepsBothDrafts() async throws {
        let left = MutableStringValue("existing left")
        let right = MutableStringValue("existing right")
        let coordinator = IndexEditableDiffMergeView.Coordinator(left: binding(to: left), right: binding(to: right))
        let pane = coordinator.makeEditor(side: .left, placeholder: "Left")
        let native = try #require(textView(in: pane) as? IndexDiffTextView)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 300),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView?.addSubview(pane)
        coordinator.update(left: left.value, right: right.value, rows: [], syntax: .plain, foldUnchanged: false)
        var diagnostic: String?
        coordinator.onFileDropDiagnostic = { diagnostic = $0 }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("XToolsDiffDrop-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let malformed = directory.appendingPathComponent("invalid-utf8.txt")
        try Data([0xC3]).write(to: malformed)
        native.loadDroppedFile(from: malformed)
        for _ in 0..<200 {
            if diagnostic != nil { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(diagnostic == IndexDroppedTextRejection.invalidEncoding.message)
        #expect(native.string == "existing left")
        #expect(left.value == "existing left")
        #expect(right.value == "existing right")
        native.didChangeText()
        #expect(diagnostic == nil)
        #expect(native.window === window)
    }

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

    @Test func planDifferenceHunksMergesConsecutiveDifferenceRowsPerSideLineNumbers() {
        typealias MergeView = IndexEditableDiffMergeView
        let rows = [
            DiffAlignedRow(kind: .removed, left: DiffAlignedCell(lineNumber: 1, text: "old 1", indent: 0), right: nil),
            DiffAlignedRow(kind: .added, left: nil, right: DiffAlignedCell(lineNumber: 1, text: "new 1", indent: 0)),
            DiffAlignedRow(kind: .changed, left: DiffAlignedCell(lineNumber: 2, text: "old 2", indent: 0), right: DiffAlignedCell(lineNumber: 2, text: "new 2", indent: 0)),
            DiffAlignedRow(kind: .unchanged, left: DiffAlignedCell(lineNumber: 3, text: "same", indent: 0), right: DiffAlignedCell(lineNumber: 3, text: "same", indent: 0)),
            DiffAlignedRow(kind: .changed, left: DiffAlignedCell(lineNumber: 4, text: "old 3", indent: 0), right: DiffAlignedCell(lineNumber: 4, text: "new 3", indent: 0))
        ]

        let hunks = MergeView.planDifferenceHunks(in: rows)

        #expect(hunks.count == 2)
        #expect(hunks[0].leftLines == [1, 2])
        #expect(hunks[0].rightLines == [1, 2])
        #expect(hunks[1].leftLines == [4])
        #expect(hunks[1].rightLines == [4])
        #expect(hunks[0].contains(2, on: .left))
        #expect(!hunks[0].contains(3, on: .left))
        #expect(hunks[0].firstLine(for: .right) == 1)
        #expect(hunks[1].firstLine(for: .left) == 4)
    }

    @Test func planDifferenceHunksReturnsEmptyForUnchangedOrMissingInput() {
        typealias MergeView = IndexEditableDiffMergeView

        #expect(MergeView.planDifferenceHunks(in: []).isEmpty)

        let unchanged = [
            DiffAlignedRow(kind: .unchanged, left: DiffAlignedCell(lineNumber: 1, text: "same", indent: 0), right: DiffAlignedCell(lineNumber: 1, text: "same", indent: 0))
        ]
        #expect(MergeView.planDifferenceHunks(in: unchanged).isEmpty)
    }

    @Test func computeDiffSummaryFollowsStateErrorAndSyntaxMatrix() {
        typealias Workspace = IndexEditableDiffWorkspace<EmptyView>
        let unchangedRows = [
            DiffAlignedRow(kind: .unchanged, left: DiffAlignedCell(lineNumber: 1, text: "same", indent: 0), right: DiffAlignedCell(lineNumber: 1, text: "same", indent: 0))
        ]
        let differingRows = [
            DiffAlignedRow(kind: .removed, left: DiffAlignedCell(lineNumber: 1, text: "old", indent: 0), right: nil),
            DiffAlignedRow(kind: .added, left: nil, right: DiffAlignedCell(lineNumber: 1, text: "new", indent: 0))
        ]

        let empty = Workspace.computeDiffSummary(left: "", right: "", rows: [], resultState: .current, syntax: .plain, error: nil)
        #expect(!empty.leftNonEmpty && !empty.rightNonEmpty)
        #expect(!empty.isIdentical && empty.differenceBlockCount == 0)

        let identical = Workspace.computeDiffSummary(left: "a", right: "a", rows: unchangedRows, resultState: .current, syntax: .plain, error: nil)
        #expect(identical.leftNonEmpty && identical.rightNonEmpty)
        #expect(identical.isIdentical && identical.differenceBlockCount == 0)

        let differing = Workspace.computeDiffSummary(left: "a", right: "b", rows: differingRows, resultState: .current, syntax: .plain, error: nil)
        #expect(!differing.isIdentical && differing.differenceBlockCount == 1)

        let stale = Workspace.computeDiffSummary(left: "a", right: "b", rows: differingRows, resultState: .stale, syntax: .plain, error: nil)
        #expect(!stale.isIdentical && stale.differenceBlockCount == 0)

        let errored = Workspace.computeDiffSummary(left: "a", right: "b", rows: differingRows, resultState: .current, syntax: .plain, error: "对比输入有误")
        #expect(!errored.isIdentical && errored.differenceBlockCount == 0)

        let jsonIdentical = Workspace.computeDiffSummary(left: "{}", right: "{}", rows: [], resultState: .current, syntax: .json, error: nil)
        #expect(jsonIdentical.isIdentical)

        let plainWithEmptyRows = Workspace.computeDiffSummary(left: "{}", right: "{}", rows: [], resultState: .current, syntax: .plain, error: nil)
        #expect(!plainWithEmptyRows.isIdentical)
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
        let leftDisplay = try #require(canonicalDisplayText(left))
        let rightDisplay = try #require(canonicalDisplayText(right))
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
        let leftDisplay = try #require(canonicalDisplayText(leftSource))
        let rightDisplay = try #require(canonicalDisplayText(rightSource))
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

    @Test func unmountedEditorsReceiveBoundedInitialDiffDecorations() throws {
        let left = (0..<128).map { "old value \($0)" }.joined(separator: "\n")
        let right = (0..<128).map { "new value \($0)" }.joined(separator: "\n")
        let rows = try LineDiffer.safeAlignedDiff(left: left, right: right)
        let leftValue = MutableStringValue(left)
        let rightValue = MutableStringValue(right)
        let coordinator = IndexEditableDiffMergeView.Coordinator(
            left: binding(to: leftValue), right: binding(to: rightValue)
        )
        let leftEditor = coordinator.makeEditor(side: .left, placeholder: "Left")
        let rightEditor = coordinator.makeEditor(side: .right, placeholder: "Right")
        let leftView = try #require(textView(in: leftEditor))
        let rightView = try #require(textView(in: rightEditor))
        coordinator.update(left: left, right: right, rows: rows, syntax: .plain, foldUnchanged: false)
        for view in [leftView, rightView] {
            let manager = try #require(view.layoutManager)
            #expect(manager.temporaryAttribute(.backgroundColor, atCharacterIndex: 0, effectiveRange: nil) != nil)
            let distant = (view.string as NSString).range(of: "value 100").location - 4
            #expect(manager.temporaryAttribute(.backgroundColor, atCharacterIndex: distant, effectiveRange: nil) == nil,
                    "An unmounted editor must not fall back to decorating the full document")
        }
    }

    @Test func endingRightEditingFallbackStillReconciles() throws {
        let leftSource = #"{"name":"Ada","active":true}"#
        let rightSource = #"{"name":"Grace","active":false,"port":5432}"#
        let leftDisplay = try #require(canonicalDisplayText(leftSource))
        let rightDisplay = try #require(canonicalDisplayText(rightSource))
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
        let leftDisplay = try #require(canonicalDisplayText(leftSource))
        let rightDisplay = try #require(canonicalDisplayText(rightSource))
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

    private func waitUntilLayout(
        _ window: NSWindow, _ hosting: NSView, _ stage: String, _ condition: () -> Bool
    ) async throws {
        let deadline = ContinuousClock.now + .seconds(10)
        repeat {
            hosting.layoutSubtreeIfNeeded()
            hosting.displayIfNeeded()
            window.displayIfNeeded()
            CATransaction.flush()
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        } while ContinuousClock.now < deadline
        Issue.record("Timed out waiting for diff workspace state: \(stage)")
    }

    private func findDismissAction(in window: NSWindow) -> DiffAccessibilityProbeElement? {
        DiffAccessibilityProbeElement.elements(in: window).first {
            $0.role == NSAccessibility.Role.button.rawValue && $0.label == "关闭导入提示"
        }
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

@MainActor
private final class DiffDiagnosticProbeModel: ObservableObject {
    @Published var left = "draft"
    @Published var right = ""
    @Published var error: String?
}

/// Minimal in-process accessibility probe mirroring the established
/// WorkbenchAccessibilityTests element walk: SwiftUI's virtual nodes implement
/// accessibility selectors without declaring NSAccessibilityProtocol, and
/// Objective-C optional dispatch reaches them without unchecked casts.
@MainActor
private struct DiffAccessibilityProbeElement {
    let object: NSObject
    // Objective-C optional protocol dispatch requires an untyped receiver.
    private var dynamic: AnyObject { object }

    var role: String? { dynamic.accessibilityRole?()?.rawValue }
    var label: String? { dynamic.accessibilityLabel?() }
    var children: [DiffAccessibilityProbeElement] {
        (dynamic.accessibilityChildren?() ?? []).compactMap { ($0 as? NSObject).map(Self.init) }
    }

    func press() -> Bool {
        dynamic.accessibilityPerformPress?() ?? false
    }

    static func elements(in window: NSWindow) -> [DiffAccessibilityProbeElement] {
        var pending = [DiffAccessibilityProbeElement(object: window)]
        var result: [DiffAccessibilityProbeElement] = []
        var visited = Set<ObjectIdentifier>()
        while let element = pending.popLast(), result.count < 2000 {
            guard visited.insert(ObjectIdentifier(element.object)).inserted else { continue }
            result.append(element)
            pending.append(contentsOf: element.children)
        }
        return result
    }
}

private struct DiffDiagnosticProbe: View {
    @ObservedObject var model: DiffDiagnosticProbeModel
    var body: some View {
        IndexEditableDiffWorkspace(
            leftPlaceholder: "原始文本…",
            rightPlaceholder: "对比文本…",
            left: $model.left,
            right: $model.right,
            rows: [],
            resultState: .current,
            error: model.error,
            onClear: {},
            leadingControl: {}
        )
        .transaction { $0.disablesAnimations = true }
    }
}
