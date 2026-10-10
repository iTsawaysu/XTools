import Foundation
import AppKit
import XToolsCore
@testable import XTools
import Testing

/// Editable diff workspace contracts.
///
/// Retained anchors: single outer scroll owner, equal fixed split, line
/// numbers as in-editor overlays (no native rulers), decoration freshness
/// and spacer bans, legacy reader unavailability, and session-owned
/// execution. Multi-line indentation-sensitive needles, metric literals,
/// and swap/save copy bans were retired.
struct EditableDiffSourceContractTests {
    @Test @MainActor func textKitGeometryHonorsPaneSpecificTrailingReadingGuard() {
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 200, height: 120))
        textView.textContainerInset = NSSize(width: 12, height: 8)
        textView.textContainer?.lineFragmentPadding = 0

        let wrappingWidth = IndexTextKitGeometry.wrappingContainerWidth(
            for: textView,
            visibleWidth: 200,
            trailingReadingGuard: 32
        )

        #expect(wrappingWidth == 144, "Wrapping width should subtract both horizontal insets and the caller's trailing reading guard")

        IndexTextKitGeometry.synchronizeTextGeometry(
            for: textView,
            visibleWidth: 200,
            minimumHeight: 120,
            trailingReadingGuard: 32
        )

        #expect(textView.textContainer?.containerSize.width == 144, "Synchronized TextKit geometry should apply the caller-specific trailing guard")
        #expect(textView.frame.width == 200, "The document view should still fill the clip width while the text container wraps inside it")
    }

    @Test @MainActor func textKitGeometrySupportsAsymmetricLeadingInsetSurfaces() {
        final class AsymmetricTestTextView: NSTextView, IndexAsymmetricTextContainerSurface {
            var leadingTextContainerInset: CGFloat { 34 }
        }

        let textView = AsymmetricTestTextView(frame: NSRect(x: 0, y: 0, width: 350, height: 200))
        textView.textContainerInset = NSSize(width: 34, height: 14)
        textView.textContainer?.lineFragmentPadding = 0

        let wrappingWidth = IndexTextKitGeometry.wrappingContainerWidth(
            for: textView,
            visibleWidth: 350,
            trailingReadingGuard: 16
        )

        #expect(wrappingWidth == 300, "Asymmetric surfaces must subtract leading inset once and trailing reading guard once, eliminating the 34pt dead zone")

        IndexTextKitGeometry.synchronizeTextGeometry(
            for: textView,
            visibleWidth: 350,
            minimumHeight: 200,
            trailingReadingGuard: 16
        )

        #expect(textView.textContainer?.containerSize.width == 300)
        let rightMargin = textView.bounds.width - (textView.textContainerOrigin.x + (textView.textContainer?.containerSize.width ?? 0))
        #expect(rightMargin == 16, "Right margin should be exactly the 16pt trailing reading guard without any 50pt dead zone")
    }

    @Test @MainActor func leadingLockedClipViewRejectsHiddenHorizontalScrolling() {
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 120, height: 80))
        scrollView.contentView = IndexLeadingLockedClipView(frame: scrollView.bounds)
        let documentView = NSView(frame: NSRect(x: 0, y: 0, width: 360, height: 300))
        scrollView.documentView = documentView

        scrollView.contentView.scroll(to: NSPoint(x: 90, y: 44))
        scrollView.reflectScrolledClipView(scrollView.contentView)

        #expect(scrollView.contentView.bounds.origin.x == 0, "Hidden horizontal autoscroll must not move wrapped editors away from the leading edge")
        #expect(scrollView.contentView.bounds.origin.y == 44, "Locking horizontal offset must preserve vertical scrolling")

        documentView.scrollToVisible(NSRect(x: 240, y: 120, width: 12, height: 20))

        #expect(scrollView.contentView.bounds.origin.x == 0, "scrollToVisible must also be unable to push the diff workspace sideways")
        #expect(scrollView.contentView.bounds.origin.y > 44, "scrollToVisible should still be allowed to move vertically")
    }

    @Test func absentDiffDiagnosticDoesNotReserveABlankStatusRow() throws {
        let source = try readSource("Sources/XTools/ToolPages/Workbench/Diff/IndexEditableDiffWorkspace.swift")
        let diagnosticViews = try readSource("Sources/XTools/ToolPages/Workbench/Diagnostics/IndexFormatDiagnosticViews.swift")
        contains(source, "IndexDiagnosticStatusSlot(isActive: hasDiagnostic)", "The diff status row must go through the shared slot that owns conditional presence")
        contains(diagnosticViews, "struct IndexDiagnosticStatusSlot", "Diagnostic status rows must share one sanctioned container")
        doesNotContain(source, "frame(height: 36)", "Row geometry must live in the shared slot, not per workbench")
    }

    @Test func editableDiffAppliesLatestCanonicalTextWhenEitherEditorEndsEditing() throws {
        let source = try readSource("Sources/XTools/ToolPages/Workbench/Diff/IndexEditableDiffMergeView.swift")
        contains(source, "private var latestLeftDisplayText", "The left editor must retain the newest canonical display while its draft is active")
        contains(source, "private var latestRightDisplayText", "The right editor must retain the newest canonical display while its draft is active")
        contains(source, "func textDidEndEditing(_ notification: Notification)", "Both editors must reconcile their display when editing ends")
        contains(source, "applyLatestDisplay(to: textView)", "End-editing reconciliation must use the same guarded programmatic text path")
        contains(source, "if textView === leftTextView", "Canonical reconciliation must distinguish the left editor")
        contains(source, "else if textView === rightTextView", "Canonical reconciliation must distinguish the right editor")
        contains(source, "JSONExactTextIdentity.isExactlyEqual(textView.string, source)", "Active editors must preserve only byte-identical user drafts while typing")
    }

    @Test func editableDiffWorkspaceUsesSingleOuterScrollAndWrapping() throws {
        let workspaceSource = try readSource("Sources/XTools/ToolPages/Workbench/Diff/IndexEditableDiffWorkspace.swift")
        let mergeViewSource = try readSource("Sources/XTools/ToolPages/Workbench/Diff/IndexEditableDiffMergeView.swift")
        let appKitViewsSource = try readSource("Sources/XTools/ToolPages/Workbench/Diff/IndexEditableDiffAppKitViews.swift")
        let textSurfacesSource = try readSource("Sources/XTools/ToolPages/Workbench/Diff/IndexEditableDiffTextSurfaces.swift")
        // The editable diff implementation was split out of the original
        // workspace file; the union of the four files preserves the
        // pre-split assertion scope over the same implementation.
        let source = [workspaceSource, mergeViewSource, appKitViewsSource, textSurfacesSource].joined(separator: "\n")
        let geometrySource = try readSource("Sources/XTools/ToolPages/Workbench/Diff/IndexEditableDiffGeometry.swift")
        let decorationsSource = try readSource("Sources/XTools/ToolPages/Workbench/Diff/IndexEditableDiffDecorations.swift")
        let coreDecorationsSource = try readSource("Sources/XToolsCore/Diff/DiffEditorDecorations.swift")
        let editableDiffImplementation = [source, geometrySource, decorationsSource].joined(separator: "\n")
        let textDiff = try readSource("Sources/XTools/ToolPages/Development/TextDiffPage.swift")
        let jsonDiff = try readSource("Sources/XTools/ToolPages/Development/JSONDiffPage.swift")
        let execution = try readSource("Sources/XTools/ToolPages/Development/DiffExecutionSession.swift")
        let projection = try readSource("Sources/XToolsCore/Diff/DiffExecutionProjection.swift")

        contains(textDiff, "IndexEditableDiffWorkspace(", "Text diff must keep the editable diff workspace")
        contains(jsonDiff, "IndexEditableDiffWorkspace(", "JSON diff must keep the editable diff workspace")
        doesNotContain(source, "let leftTitle: String", "Diff workspace interface must not retain the inert left pane-title fact")
        doesNotContain(source, "var onClearLeft:", "Diff workspace interface must not retain the unreachable left clear callback")
        doesNotContain(source, "var onFormatLeft:", "Diff workspace interface must not retain the unreachable left format callback")
        doesNotContain(jsonDiff, "private enum JSONSide", "JSON diff must not keep the unreachable format-side implementation")
        for (name, page) in [("Text diff", textDiff), ("JSON diff", jsonDiff)] {
            contains(page, "@ObservedObject var execution: DiffExecutionSession", "\(name) must observe the retained execution session")
            doesNotContain(page, "onSwap:", "\(name) must keep the low-density Diff header free of a swap action")
            doesNotContain(page, "IndexDebouncer", "\(name) must not own a page-local debounce")
            doesNotContain(page, "private func run()", "\(name) must not run synchronous diff work from the View")
            doesNotContain(page, "onDisappear", "Ordinary diff navigation must not cancel retained work")
            doesNotContain(page, "leftFileName:", "\(name) must not expose pane-local source save buttons")
        }
        contains(jsonDiff, "DiffExecutionKind", "Diff workspace must capture the execution kind in its model")
        contains(textDiff, "error: execution.binding.error", "Text diff must route session diagnostics into the existing workspace diagnostic anchor")
        contains(jsonDiff, "leftDisplayText: execution.binding.leftDisplayText", "JSON diff must render the session's normalized left display")
        contains(jsonDiff, "rightDisplayText: execution.binding.rightDisplayText", "JSON diff must render the session's normalized right display")
        contains(jsonDiff, "rows: execution.binding.rows", "JSON diff must render the session's complete rows binding")
        contains(execution, "DiffExecution.project", "Diff session must delegate request→binding projection to Core")
        contains(projection, "LineDiffer.safeAlignedDiff", "Diff execution must use the budgeted text diff path")
        contains(projection, "JSONStructuralDiff.cancellablePreparedDiff", "Diff execution must use the single-parse cancellable JSON preparation path")

        // Diagnostics stay inline in the unified toolbar, never a body row.
        contains(source, "private var diagnosticText: String?", "Diff diagnostics must project error-first state into one shared text projection")
        contains(source, "IndexBadge(\"STDIN\"", "Diff workspace toolbar must show standard STDIN badge")
        contains(source, "IndexBadge(\"STDOUT\"", "Diff workspace toolbar must show standard STDOUT badge")
        contains(source, "inlineDiagnostic", "Diff workspace must render inline diagnostic in the unified toolbar")
        doesNotContain(source, "IndexWorkspaceDiagnostic(text: error, tone: .error)", "Diff errors must not insert a diagnostic row above the editable merge body")

        // Structured diff tools may pass normalized display text.
        contains(source, "var leftDisplayText: String?", "Diff workspace must accept optional normalized display text for structured diff tools")
        contains(source, "var rightDisplayText: String?", "Diff workspace must accept optional normalized display text for structured diff tools")
        contains(source, "left: leftDisplayText ?? left", "Diff workspace must render normalized left text when JSON diff provides it")
        contains(source, "right: rightDisplayText ?? right", "Diff workspace must render normalized right text when JSON diff provides it")
        contains(source, "source: self.left.wrappedValue", "Diff workspace must compare display updates against the editable source binding before replacing visible text")
        contains(source, "let overrideFoldProjection = hasCollapsedRegion", "A read-only fold projection must override the focused editor on both sides")
        contains(source, "textView.setStringWithoutUndoRegistration(text)", "Diff workspace programmatic replacements must establish a safe undo baseline through the shared helper")

        // One outer scroll owner; editors wrap and never scroll on their own.
        contains(source, "IndexEditableDiffScrollHostView", "Editable diff body must have one outer scroll host")
        contains(source, "let outerScrollView = NSScrollView(frame: .zero)", "Diff body must use one outer scroll view")
        contains(source, "outerScrollView.hasVerticalScroller = true", "The single outer diff scroll view must own vertical scrolling")
        contains(source, "outerScrollView.hasHorizontalScroller = false", "The single outer diff scroll view must not allow horizontal scrolling")
        contains(source, "outerScrollView.contentView = IndexLeadingLockedClipView(frame: .zero)", "The outer diff scroll owner must also lock horizontal clip movement from scrollToVisible")
        contains(source, "scrollView.hasVerticalScroller = false", "Left/right diff editors must not expose their own vertical scrollers")
        contains(source, "scrollView.hasHorizontalScroller = false", "Left/right diff editors must not expose horizontal scrollers")
        contains(source, "textView.isHorizontallyResizable = false", "Diff text views must wrap within their pane instead of growing horizontally")
        contains(source, "textContainer.widthTracksTextView = false", "Diff text containers must not track the full text-view bounds when insets are present")
        contains(source, "IndexTextKitGeometry.wrappingContainerWidth", "Diff text containers must share the inset-aware wrapping width with normal text inputs")
        contains(source, "IndexDiffTextLayoutGeometry.synchronizeTextGeometry(", "Diff text editors must reuse revision/width-cached document geometry after layout")
        contains(source, "textContainer.lineBreakMode = .byCharWrapping", "Diff text containers must break extremely long tokens inside the pane")
        contains(source, "scrollSelectionIntoOuterView(textView)", "Large paste/edit operations must reveal the insertion point through the outer scroll view")
        doesNotContain(source, "scrollViewDidScroll", "Diff editors must not keep the old side-by-side internal scroll synchronization")

        // Line numbers are in-editor overlays; native rulers stay out.
        contains(source, "let lineNumberView = IndexDiffLineNumberOverlayView(scrollView: scrollView, textView: textView)", "Diff line numbers must be drawn as an overlay inside the editor surface")
        contains(source, "final class IndexDiffLineNumberOverlayView: IndexLineNumberColumnView", "Diff line numbers must not use a native ruler view that creates a separate gutter column")
        doesNotContain(source, "hasVerticalRuler = true", "Diff editors must not use AppKit vertical rulers for the reference-matched line-number UI")
        doesNotContain(source, "rulersVisible = true", "Diff editors must not reveal AppKit ruler chrome")
        doesNotContain(source, "IndexDiffRulerLockedClipView", "Diff editors must not use a negative-origin ruler clip view after moving line numbers into the editor surface")
        let lineNumberChrome = try readSource("Sources/XTools/ToolPages/Workbench/Text/IndexEditorLineNumberGutter.swift")
        contains(lineNumberChrome, "paragraphStyle.alignment = .right", "Diff line numbers must be right-aligned like mature editor gutters")

        // Fixed equal split; no divider ceremony or persisted ratios.
        contains(source, "left.widthAnchor.constraint(equalTo: right.widthAnchor)", "Diff panes must stay at a fixed equal split")
        contains(source, "final class IndexEditableDiffPanePairView: NSView", "The fixed split must be a plain equal pair view, not a divider-capable control")
        doesNotContain(source, "NSSplitView", "The fixed diff split must not carry draggable-divider ceremony")
        doesNotContain(source, "captureDividerRatio", "Diff panes must not persist a user-dragged split ratio in the reference layout")

        // Difference navigation anchors on the focused editor and the caret.
        contains(source, ".disabled(!canNavigateDifferences)", "Difference navigation controls must disable outside a current non-empty result")
        contains(source, "return editorTextView(for: lastFocusedSide)", "Toolbar navigation must return to the pane that last owned editor focus")
        contains(source, "targetTextView.window?.makeFirstResponder(targetTextView)", "Difference navigation must restore keyboard focus to the target editor")
        contains(source, "targetTextView.scrollRangeToVisible(targetRange)", "Difference navigation must use the native editor reveal path before revealing through the shared outer scroll owner")
        contains(source, "firstDifferenceUTF16Offset(in cell: DiffAlignedCell)", "Difference navigation must place the caret at the first changed UTF-16 character rather than only the line start")

        // Execution stays session-owned and cooperative-cancellable.
        let worker = try readSource("Sources/XToolsCore/Utility/SupersedingDetachedWorker.swift")
        contains(execution, "SupersedingExecutionSession(", "Diff execution must use the shared superseding detached worker")
        contains(execution, "cancelInFlight: true", "Diff must keep cooperative cancellation of in-flight LCS work")
        contains(worker, "Task.detached(priority: .userInitiated)", "Diff work must execute off the MainActor")
        contains(worker, "activeTask?.cancel()", "Newer Diff requests must cancel the active cooperative operation")
        doesNotContain(source, "withAnimation", "Diff workspace chrome must not add structural layout animation")

        // Shared metrics and pane chrome; no forked shells or nested frames.
        contains(source, "enum IndexDiffEditorMetrics", "Diff editor spacing and ruler geometry must be owned by one shared metric set")
        doesNotContain(source, "IndexDiffEditorMetrics.stageInset", "The diff editor bay must remove the stage inset tray")
        doesNotContain(source, "IndexDiffEditorMetrics.frameCornerRadius", "The diff editor bay must not read as another nested rounded frame")
        doesNotContain(source, "IndexDiffEditorMetrics.frameBorderWidth", "The diff editor bay must not draw a second outer editor border")
        contains(source, "final class IndexDiffEditorPaneView: NSView", "Diff editors still need pane containers for overlays and placeholder layout")
        contains(source, "appearance.performAsCurrentDrawingAppearance", "Diff AppKit surfaces must resolve the shared SwiftUI editor background under the owning view appearance")
        contains(source, "resolvedColor(ToolTheme.editorBackground, for: appearance)", "Diff panes must consume the shared SwiftUI editor background token")
        doesNotContain(source, "static let editorBayBackground", "Diff must not duplicate the shared editor background token")
        doesNotContain(source, "static let editorPaneBackground", "Diff panes must not keep a separate white surface token")

        // Row status stays in the gutter accent; text bodies stay clean.
        contains(source, "static let gutterAccentWidth: CGFloat = 2", "Diff gutter status must stay as a thin line-number-slot marker")
        doesNotContain(source, "rowAccent", "Diff rows must not draw a second status rail in the editable text body")
        doesNotContain(source, "lineBackgroundColor", "Diff rows must not draw whole-line difference backgrounds")
        doesNotContain(source, "successLine", "Diff rows must not keep added-line background palette tokens")
        doesNotContain(source, "errorLine", "Diff rows must not keep removed-line background palette tokens")
        doesNotContain(source, "gutterBackground", "Diff line numbers must not carry a separate gutter background after moving into the editor surface")
        doesNotContain(source, "static let centerDivider", "Diff split gap must not keep the old draggable center-divider color")

        // Row alignment stays decoration-only: no real TextKit spacers.
        doesNotContain(editableDiffImplementation, "lineSpacingAfterGlyphAt", "Editable diff must not align rows by adding real TextKit after-line spacing")
        doesNotContain(editableDiffImplementation, "DiffLineSpacerMap", "Editable diff must not keep display-only spacer state in the real text layout")
        doesNotContain(editableDiffImplementation, "applyRowAlignmentSpacers", "Editable diff row alignment must stay decoration-only until a source/display mapping exists")
        doesNotContain(editableDiffImplementation, "lineSpacers", "Editable diff rulers and text views must not carry spacer maps that can move real source rows")
        doesNotContain(editableDiffImplementation, "paragraphSpacingBeforeGlyphAt", "Diff TextKit spacers must not add before-first spacing that moves an empty pane cursor down")
        doesNotContain(editableDiffImplementation, "CGFloat(lineNumber - 1) * lineHeight", "Diff line painting must not return to fixed logical-line-height positioning")

        // Decorations project through the Core seam and stay fresh.
        contains(geometrySource, "enum IndexDiffTextLayoutGeometry", "TextKit visual-line geometry must live behind its own internal seam")
        contains(geometrySource, "layoutManager.enumerateLineFragments", "The geometry seam must derive visual blocks from TextKit line fragments")
        contains(geometrySource, "enum IndexDiffSourceText", "Editable diff source line parsing must live behind a named internal seam")
        contains(coreDecorationsSource, "public struct DiffEditorDecorations", "Diff row projection must live in Core behind a pure seam")
        contains(coreDecorationsSource, "public enum DiffDecorationSide", "Decoration projection should keep left/right side knowledge in Core")
        contains(decorationsSource, "typealias DiffEditorDecorations", "Mac target must keep a compatibility alias for DiffEditorDecorations")
        contains(source, "guard rowsMatchVisibleText() else", "Diff workspace must reject stale debounced rows before applying decorations or spacers")
        contains(source, "clearDecorations()", "Stale diff rows must clear old decorations instead of leaving highlights on freshly pasted text")
        contains(source, "clearTemporaryDecorations(in: leftTextView, entireDocument: true)", "Stale diff rows must also clear inline attributes shifted by native edits in the left editor")
        contains(source, "DiffDecorationFreshness.rowsMatchVisibleText(", "Diff row freshness must delegate visible-text matching to Core")

        // Save/export actions stay removed.
        doesNotContain(textDiff, "diffReportFileName:", "Text diff must not expose a generated diff report save button")
        doesNotContain(source, "IndexDiffToolbarSaveButton", "Diff toolbar must not include save/download buttons")
        doesNotContain(source, "UnifiedDiffReport.make(", "Diff workspace must not generate export reports after save/export removal")
        doesNotContain(source, "NSSavePanel()", "Diff workspace must not construct save panels directly")
    }

    @Test func diffDecorationFreshnessRequiresExactVisibleLines() {
        let rows = [
            DiffAlignedRow(
                kind: .removed,
                left: DiffAlignedCell(lineNumber: 1, text: "old", indent: 0),
                right: nil
            ),
            DiffAlignedRow(
                kind: .added,
                left: nil,
                right: DiffAlignedCell(lineNumber: 1, text: "new", indent: 0)
            )
        ]

        #expect(
            DiffDecorationFreshness.rowsMatchVisibleText(
                rows: rows,
                side: .left,
                text: "old"
            )
        )
        #expect(
            !DiffDecorationFreshness.rowsMatchVisibleText(
                rows: rows,
                side: .left,
                text: "stale"
            )
        )

        let composed = "caf\u{00E9}"
        let decomposed = "cafe\u{0301}"
        let unicodeRows = [
            DiffAlignedRow(
                kind: .unchanged,
                left: DiffAlignedCell(lineNumber: 1, text: composed, indent: 0),
                right: DiffAlignedCell(lineNumber: 1, text: decomposed, indent: 0)
            )
        ]
        #expect(!DiffDecorationFreshness.rowsMatchVisibleText(
            rows: unicodeRows,
            side: .left,
            text: decomposed
        ))
        #expect(DiffSourceText.sourceLines(in: "a\nb") == ["a", "b"])
    }

    @Test func diffEditorDecorationsProjectRowsBySide() {
        let removed = DiffAlignedRow(
            kind: .removed,
            left: DiffAlignedCell(lineNumber: 1, text: "old", indent: 0),
            right: nil
        )
        let added = DiffAlignedRow(
            kind: .added,
            left: nil,
            right: DiffAlignedCell(lineNumber: 1, text: "new", indent: 0)
        )
        let changed = DiffAlignedRow(
            kind: .changed,
            left: DiffAlignedCell(lineNumber: 2, text: "before", indent: 0),
            right: DiffAlignedCell(lineNumber: 2, text: "after", indent: 0)
        )

        let decorations = DiffEditorDecorations(rows: [removed, added, changed])

        #expect(decorations.left[1]?.status == .removed)
        #expect(decorations.right[1]?.status == .added)
        #expect(decorations.left[2]?.status == .changedLeft)
        #expect(decorations.right[2]?.status == .changedRight)
    }

    @Test func legacyDiffReadersAreUnavailableAndDoNotCarryHorizontalReaderBehavior() throws {
        let singleColumnReader = try readSource("Sources/XTools/ToolPages/Workbench/Diff/IndexDiffResultReader.swift")
        let sideBySideReader = try readSource("Sources/XTools/ToolPages/Workbench/Diff/IndexSideBySideDiffReader.swift")
        let jsonResultView = try readSource("Sources/XTools/ToolPages/Development/JSONDiffResultView.swift")

        contains(singleColumnReader, "@available(*, unavailable", "Legacy single-column diff reader must be unavailable to ordinary pages")
        contains(sideBySideReader, "@available(*, unavailable", "Legacy side-by-side diff reader must be unavailable to ordinary pages")
        contains(jsonResultView, "@available(*, unavailable", "Legacy JSON diff result view must be unavailable to ordinary pages")
        contains(sideBySideReader, "enum IndexDiffSyntax", "Diff syntax remains a shared value used by the editable workspace")

        doesNotContain(singleColumnReader, "struct IndexDiffResultReader: View", "Legacy single-column reader must not remain a SwiftUI page component")
        doesNotContain(sideBySideReader, "struct IndexSideBySideDiffReader: View", "Legacy side-by-side reader must not remain a SwiftUI page component")
        doesNotContain(jsonResultView, "struct JSONDiffResultView: View", "Legacy JSON result view must not remain a SwiftUI page component")
        doesNotContain(jsonResultView, "IndexSideBySideDiffReader(", "Legacy JSON result view must not route back into the old reader")

        for source in [singleColumnReader, sideBySideReader, jsonResultView] {
            doesNotContain(source, "ScrollView(.horizontal", "Legacy diff readers must not carry horizontal scrolling code")
            doesNotContain(source, ".lineLimit(1)", "Legacy diff readers must not carry single-line content limits")
            doesNotContain(source, ".fixedSize(horizontal: true, vertical: false)", "Legacy diff readers must not carry single-line fixed-size content")
            doesNotContain(source, "scrollViewDidScroll", "Legacy diff readers must not carry independent side-scroll synchronization")
            doesNotContain(source, "columnWidth(for:", "Legacy side-by-side reader must not compute content-driven column widths")
        }
    }

    @Test func jsonHighlightingAdaptersUseCoreRanges() throws {
        let swiftUIAdapter = try readSource("Sources/XTools/Shared/JSONSyntaxHighlighter.swift")
        let appKitAdapter = try readSource("Sources/XTools/ToolPages/Workbench/Diff/IndexEditableDiffMergeView.swift")

        contains(swiftUIAdapter, "JSONHighlighting.tokens(in: line)", "SwiftUI JSON highlighting must use the shared Core JSON 着色标记 scanner")
        contains(appKitAdapter, "JSONSyntaxHighlighter.tokens(line: line)", "Editable diff JSON highlighting must reuse the shared Core JSON 着色标记 scanner adapter")
        contains(appKitAdapter, "IndexSyntaxUTF16RangeMap(line: line)", "Editable diff JSON highlighting must convert character offsets into UTF-16 NSRange lengths via the shared map")
    }
}
