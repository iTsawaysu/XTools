import Foundation
import AppKit
import XToolsCore
@testable import XTools
import Testing

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

    @Test func editableDiffAppliesLatestCanonicalTextWhenEitherEditorEndsEditing() throws {
        let source = try readSource("Sources/XTools/ToolPages/Workbench/Diff/IndexEditableDiffWorkspace.swift")
        contains(source, "private var latestLeftDisplayText", "The left editor must retain the newest canonical display while its draft is active")
        contains(source, "private var latestRightDisplayText", "The right editor must retain the newest canonical display while its draft is active")
        contains(source, "func textDidEndEditing(_ notification: Notification)", "Both editors must reconcile their display when editing ends")
        contains(source, "applyLatestDisplay(to: textView)", "End-editing reconciliation must use the same guarded programmatic text path")
        contains(source, "if textView === leftTextView", "Canonical reconciliation must distinguish the left editor")
        contains(source, "else if textView === rightTextView", "Canonical reconciliation must distinguish the right editor")
        contains(source, "if !allowActiveEditorOverride, isActiveEditor(textView), textView.string == source", "Active editors must continue preserving user drafts while typing")
    }

    @Test func editableDiffWorkspaceUsesSingleOuterScrollAndWrapping() throws {
        let source = try readSource("Sources/XTools/ToolPages/Workbench/Diff/IndexEditableDiffWorkspace.swift")
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
        doesNotContain(source, "let rightTitle: String", "Diff workspace interface must not retain the inert right pane-title fact")
        doesNotContain(source, "var onClearLeft:", "Diff workspace interface must not retain the unreachable left clear callback")
        doesNotContain(source, "var onClearRight:", "Diff workspace interface must not retain the unreachable right clear callback")
        doesNotContain(source, "var onFormatLeft:", "Diff workspace interface must not retain the unreachable left format callback")
        doesNotContain(source, "var onFormatRight:", "Diff workspace interface must not retain the unreachable right format callback")
        doesNotContain(textDiff, "onClearLeft:", "Text diff must not pass the unreachable clear callback")
        doesNotContain(jsonDiff, "onClearLeft:", "JSON diff must not pass the unreachable clear callback")
        doesNotContain(jsonDiff, "onFormatLeft:", "JSON diff must not pass the unreachable format callback")
        doesNotContain(jsonDiff, "private enum JSONSide", "JSON diff must not keep the unreachable format-side implementation")
        contains(textDiff, "@ObservedObject var execution: DiffExecutionSession", "Text diff must observe the retained execution session")
        contains(jsonDiff, "@ObservedObject var execution: DiffExecutionSession", "JSON diff must observe the retained execution session")
        contains(jsonDiff, "let execution: DiffExecutionSession", "Diff workspace must retain one execution session next to raw drafts")
        contains(jsonDiff, "DiffExecutionKind", "Diff workspace must capture the execution kind in its model")
        contains(textDiff, "error: execution.binding.error", "Text diff must route session diagnostics into the existing workspace diagnostic anchor")
        doesNotContain(textDiff, "onSwap:", "Text diff must keep the low-density Diff header free of a swap action")
        doesNotContain(jsonDiff, "onSwap:", "JSON diff must keep the low-density Diff header free of a swap action")
        doesNotContain(jsonDiff, "var canSwap", "The retained Diff model must not expose availability for a removed swap action")
        doesNotContain(jsonDiff, "func swap()", "The retained Diff model must not expose the removed side-swap behavior")
        contains(jsonDiff, "leftDisplayText: execution.binding.leftDisplayText", "JSON diff must render the session's normalized left display")
        contains(jsonDiff, "rightDisplayText: execution.binding.rightDisplayText", "JSON diff must render the session's normalized right display")
        contains(jsonDiff, "rows: execution.binding.rows", "JSON diff must render the session's complete rows binding")
        contains(jsonDiff, "warning: execution.binding.warning", "JSON diff warnings must route into the existing diagnostic anchor")
        contains(execution, "DiffExecution.project", "Diff session must delegate request→binding projection to Core")
        contains(projection, "LineDiffer.safeAlignedDiff", "Diff execution must use the budgeted text diff path")
        contains(projection, "JSONStructuralDiff.cancellableAlignedDiff", "Diff execution must use the cancellable JSON diff path")
        contains(projection, "JSONStructuralDiff.displayTextForDiff(request.left)", "JSON execution must preserve Core canonical left display")
        contains(projection, "JSONDiffValidation.comparisonWarning(", "JSON execution must preserve Core duplicate-key warning mapping")
        doesNotContain(textDiff, "IndexDebouncer", "Text diff must not own a page-local debounce")
        doesNotContain(jsonDiff, "IndexDebouncer", "JSON diff must not own a page-local debounce")
        doesNotContain(textDiff, "private func run()", "Text diff must not run synchronous diff work from the View")
        doesNotContain(jsonDiff, "private func run()", "JSON diff must not run synchronous diff work from the View")
        doesNotContain(textDiff, "onDisappear", "Ordinary diff navigation must not cancel retained work")
        doesNotContain(jsonDiff, "onDisappear", "Ordinary diff navigation must not cancel retained work")
        contains(source, "private var diagnosticText: String?", "Diff diagnostics must project error-first state into one shared text projection")
        contains(source, "IndexBadge(\"STDIN\"", "Diff workspace toolbar must show standard STDIN badge")
        contains(source, "IndexBadge(\"STDOUT\"", "Diff workspace toolbar must show standard STDOUT badge")
        contains(source, "inlineDiagnostic", "Diff workspace must render inline diagnostic in the unified toolbar")
        doesNotContain(source, "IndexWorkspaceDiagnostic(text: error, tone: .error)", "Diff errors must not insert a diagnostic row above the editable merge body")
        doesNotContain(source, ".padding(.top, error == nil ? 0 : 12)", "Diff errors must not shrink the editable merge body by adding error-dependent top padding")
        doesNotContain(source, "IndexPanel(\"对比工作区\")", "Diff workspace must not wrap the two editor panes in an extra inner panel shell")
        contains(source, "var leftDisplayText: String?", "Diff workspace must accept optional normalized display text for structured diff tools")
        contains(source, "var rightDisplayText: String?", "Diff workspace must accept optional normalized display text for structured diff tools")
        contains(source, "left: leftDisplayText ?? left", "Diff workspace must render normalized left text when JSON diff provides it")
        contains(source, "right: rightDisplayText ?? right", "Diff workspace must render normalized right text when JSON diff provides it")
        contains(source, "setText(left, source: self.left.wrappedValue", "Diff workspace must compare display updates against the editable source binding before replacing visible text")
        contains(source, "isActiveEditor(textView), textView.string == source", "Diff workspace must not overwrite the active editor with normalized display text during ordinary user edits")
        contains(source, "textView.setStringWithoutUndoRegistration(text)", "Diff workspace programmatic replacements must establish a safe undo baseline through the shared helper")
        contains(source, "IndexBadge(\"STDIN\"", "Diff workspace must show standard workbench badges")
        doesNotContain(source, "IndexTrafficLights()", "Diff workspace shell must not keep decorative traffic lights beside an active diagnostic")
        doesNotContain(source, "private struct IndexDiffWorkbenchPanel", "Diff workspace must not fork the panel shell away from the unified IndexPanel")
        doesNotContain(source, "Rectangle()\n                .fill(ToolTheme.border.opacity(0.75))", "Diff workspace must not spend vertical space on the old top rule")
        doesNotContain(source, "headingRow", "Diff workspace must not render the old Original/Compared pane-title row")
        doesNotContain(source, "private struct IndexDiffPaneHeading: View", "Diff workspace must not keep the old external pane heading component")
        doesNotContain(source, "IndexDiffToolbarIconButton", "Diff pane headings must not show local action icons when matching the reference layout")
        doesNotContain(source, "IndexDiffToolbarCopyButton", "Diff pane headings must not show copy icons when matching the reference layout")
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
        contains(source, "IndexTextKitGeometry.synchronizeTextGeometry(", "Diff text editors must synchronize text view and text container geometry after layout")
        contains(source, "scrollView.contentView = IndexLeadingLockedClipView(frame: .zero)", "Diff editors must lock hidden horizontal clip movement without using a separate native ruler column")
        contains(source, "let lineNumberView = IndexDiffLineNumberOverlayView(scrollView: scrollView, textView: textView)", "Diff line numbers must be drawn as an overlay inside the editor surface")
        contains(source, "private final class IndexDiffLineNumberOverlayView: NSView", "Diff line numbers must not use a native ruler view that creates a separate gutter column")
        contains(source, "override func hitTest(_ point: NSPoint) -> NSView? {\n        nil", "Diff line-number overlays must not intercept editor clicks")
        doesNotContain(source, "hasVerticalRuler = true", "Diff editors must not use AppKit vertical rulers for the reference-matched line-number UI")
        doesNotContain(source, "rulersVisible = true", "Diff editors must not reveal AppKit ruler chrome")
        doesNotContain(source, "IndexDiffRulerLockedClipView", "Diff editors must not use a negative-origin ruler clip view after moving line numbers into the editor surface")
        contains(source, "static let trailingReadingGuard: CGFloat = 16", "Diff panes must use the normal trailing wrap guard once line numbers are drawn inside the editor surface")
        contains(source, "scrollView.trailingReadingGuard = IndexDiffEditorMetrics.trailingReadingGuard", "Diff scroll views must receive the pane-specific trailing guard")
        contains(source, "override func layout() {\n        super.layout()\n        synchronizeTextGeometry()", "Diff scroll views must re-sync TextKit after their own clip size changes")
        contains(source, "textContainer.lineBreakMode = .byCharWrapping", "Diff text containers must break extremely long tokens inside the pane")
        contains(source, "private let storedDividerRatio: CGFloat = 0.5", "Diff panes must stay at a fixed equal split")
        contains(source, "applyStoredDividerRatio(in: splitView)", "Diff panes must keep the existing stable divider-ratio strategy")
        contains(source, "constrainSplitPosition proposedPosition", "Diff split position must stay fixed even if a divider drag event reaches NSSplitView")
        contains(source, "if hitsDivider {\n            return", "Diff split gap must not allow user dragging because the reference layout is fixed")
        contains(source, "override func resetCursorRects()", "Diff split gap must not register the default resize cursor")
        contains(source, "addCursorRect(dividerHitRect, cursor: .arrow)", "Diff split gap must keep the normal arrow cursor instead of implying it can be dragged")
        contains(source, "override func cursorUpdate(with event: NSEvent)", "Diff split gap must force the normal cursor when AppKit requests a cursor update")
        doesNotContain(source, "captureDividerRatio", "Diff panes must not persist a user-dragged split ratio in the reference layout")
        contains(source, "scrollSelectionIntoOuterView(textView)", "Large paste/edit operations must reveal the insertion point through the outer scroll view")
        doesNotContain(source, "var onSwap:", "The shared Diff header must not expose the removed swap callback")
        doesNotContain(source, "swapDisabled", "The shared Diff header must not retain disabled state for the removed swap action")
        doesNotContain(source, "Image(systemName: \"arrow.left.arrow.right\")", "The shared Diff header must not spend primary space on side swapping")
        doesNotContain(source, ".help(\"交换左右\")", "The shared Diff header must not retain swap-only help copy")
        doesNotContain(source, ".accessibilityLabel(\"交换左右\")", "The shared Diff header must not retain a hidden swap accessibility action")
        let worker = try readSource("Sources/XToolsCore/Utility/SupersedingDetachedWorker.swift")
        contains(execution, "SupersedingExecutionSession(", "Diff execution must use the shared superseding detached worker")
        contains(execution, "cancelInFlight: true", "Diff must keep cooperative cancellation of in-flight LCS work")
        contains(worker, "private var activeTask", "Diff execution must retain a cancellable active detached operation")
        contains(worker, "private var pending", "Diff execution must keep one replaceable latest pending request")
        contains(worker, "Task.detached(priority: .userInitiated)", "Diff work must execute off the MainActor")
        contains(worker, "activeTask?.cancel()", "Newer Diff requests must cancel the active cooperative operation")
        doesNotContain(source, "withAnimation", "Diff workspace chrome must not add structural layout animation")
        doesNotContain(source, "inlineStatus", "Diff pane headings must not reintroduce a center status label that can collide with the right pane title")
        doesNotContain(source, ".overlay(alignment: .center) {\n            inlineStatus", "Diff pane headings must not overlay a center status between the two editor titles")
        contains(source, "private enum IndexDiffEditorMetrics", "Diff editor spacing and ruler geometry must be owned by one shared metric set")
        doesNotContain(source, "topRuleToHeading", "Diff workspace must not reserve the old top-rule-to-heading gap")
        doesNotContain(source, "headingToEditorGap", "Diff workspace must not reserve the old title-to-editor gap")
        contains(source, "static let rulerWidth: CGFloat = 44", "Diff line numbers must use the unified 44-point editor gutter")
        contains(source, "static let textInset = NSSize(width: rulerWidth + 13, height: 14)", "Diff text must align with the unified gutter inset")
        contains(source, "static let lineNumberLeadingPadding: CGFloat = 6", "Unified line numbers must keep standard leading inset")
        contains(source, "static let lineNumberTrailingPadding: CGFloat = 10", "Unified line numbers must keep standard trailing separation")
        contains(source, ".monospacedSystemFont(ofSize: 11, weight: .regular)", "Unified line numbers must use 11-point monospaced font")
        contains(source, "static let paneGap: CGFloat = 1", "Plan C diff split gap must be a 1-point hairline divider")
        contains(source, "static let dividerThickness: CGFloat = paneGap", "The fixed split divider must match the hairline gap")
        contains(source, "static let stageInset: CGFloat = 0", "The diff editor bay must remove the stage inset tray")
        contains(source, "static let frameCornerRadius: CGFloat = ToolMetrics.CornerRadius.field", "The seamless diff workbench must own the standard field radius on the outer container")
        contains(source, "static let frameBorderWidth: CGFloat = 0.5", "The seamless diff workbench must own the 0.5pt border on the outer container")
        contains(source, "static let paneCornerRadius: CGFloat = 0", "Individual inner diff panes must not have their own corner radius in the seamless layout")
        contains(source, "private final class IndexDiffEditorPaneView: NSView", "Diff editors still need pane containers for overlays and placeholder layout")
        contains(source, "layer?.backgroundColor = IndexDiffNSPalette.editorBackground(for: effectiveAppearance).cgColor", "The outer diff container must use the shared editor background")
        contains(source, "layer?.borderColor = NSColor(ToolTheme.border).cgColor", "The outer diff host must own the unified container border")
        contains(source, "layer?.borderWidth = IndexDiffEditorMetrics.frameBorderWidth", "The outer diff host must own the 0.5pt border contract")
        contains(source, "appearance.performAsCurrentDrawingAppearance", "Diff AppKit surfaces must resolve the shared SwiftUI editor background under the owning view appearance")
        contains(source, "resolvedColor(ToolTheme.editorBackground, for: appearance)", "Diff panes must consume the shared SwiftUI editor background token")
        contains(source, "resolvedColor(ToolTheme.panelBackground, for: appearance)", "The stage and fixed gap must consume the shared panel background token")
        contains(source, "let sharedColor = NSColor(color)", "Diff AppKit surfaces must share one SwiftUI-to-AppKit color resolver")
        contains(source, "sharedColor.usingColorSpace(.deviceRGB)", "Diff AppKit surfaces must return a fixed color resolved under the owning appearance")
        doesNotContain(source, "static let editorBayBackground", "Diff must not duplicate the shared editor background token")
        doesNotContain(source, "static let editorPaneBackground", "Diff panes must not keep a separate white surface token")
        doesNotContain(source, "static let editorPaneBorder", "Borderless Diff panes must not retain the removed center-rail color token")
        contains(source, "layer?.borderColor = NSColor.clear.cgColor\n        layer?.borderWidth = 0", "Individual inner diff panes must be borderless in the seamless layout")
        contains(source, "override var dividerThickness: CGFloat {\n        IndexDiffEditorMetrics.dividerThickness", "Diff split divider must provide the fixed non-draggable gap")
        contains(source, "NSColor(ToolTheme.border).setFill()", "The seamless split divider must be filled with the border color")
        contains(source, "NSBezierPath(rect: rect).fill()", "The fixed split gap must be filled without implying a draggable divider")
        contains(source, "static let lineNumberTrailingPadding: CGFloat", "Diff line numbers must have an explicit trailing padding token")
        contains(source, "static let gutterAccentWidth: CGFloat = 2", "Diff gutter status must stay as a thin line-number-slot marker")
        contains(source, "static let gutterAccentLeadingPadding: CGFloat = 4", "Diff gutter status must remain near the compact pane edge")
        doesNotContain(source, "rowAccent", "Diff rows must not draw a second status rail in the editable text body")
        doesNotContain(source, "lineBackgroundColor", "Diff rows must not draw whole-line difference backgrounds")
        doesNotContain(source, "successLine", "Diff rows must not keep added-line background palette tokens")
        doesNotContain(source, "errorLine", "Diff rows must not keep removed-line background palette tokens")
        doesNotContain(source, "gutterBackground", "Diff line numbers must not carry a separate gutter background after moving into the editor surface")
        doesNotContain(source, "static let centerDivider", "Diff split gap must not keep the old draggable center-divider color")
        contains(source, "paragraphStyle.alignment = .right", "Diff line numbers must be right-aligned like mature editor gutters")
        contains(source, "lineText.draw(\n                in: NSRect(x: labelX", "Diff line numbers must draw inside the shared padded ruler label rect")
        contains(source, "lineNumberView.widthAnchor.constraint(equalToConstant: IndexDiffEditorMetrics.rulerWidth)", "Diff line-number overlay width must use the shared editor metrics")
        doesNotContain(source, "IndexDiffNSPalette.centerDivider.setFill()", "Diff editor panes must not draw the old center divider token")
        contains(source, "let hairline = NSRect(x: bounds.width - 0.5, y: 0, width: 0.5, height: bounds.height)", "Diff line-number gutters must draw the 0.5pt hairline divider matching unified gutter")
        doesNotContain(source, "status.lineBackgroundColor.setFill()\n                NSBezierPath(rect: NSRect(x: 0, y: y, width: bounds.width, height: height)).fill()", "Diff line-number gutters must not paint the whole gutter as a difference block")
        contains(source, "IndexDiffTextLayoutGeometry.lineBlockRects", "Wrapped diff row drawing must use TextKit line-fragment geometry")
        contains(geometrySource, "enum IndexDiffTextLayoutGeometry", "TextKit visual-line geometry must live behind its own internal seam")
        contains(geometrySource, "layoutManager.enumerateLineFragments", "The geometry seam must derive visual blocks from TextKit line fragments")
        contains(geometrySource, "enum IndexDiffSourceText", "Editable diff source line parsing must live behind a named internal seam")
        contains(coreDecorationsSource, "public struct DiffEditorDecorations", "Diff row projection must live in Core behind a pure seam")
        contains(decorationsSource, "typealias DiffEditorDecorations", "Mac target must keep a compatibility alias for DiffEditorDecorations")
        contains(coreDecorationsSource, "public enum DiffDecorationSide", "Decoration projection should keep left/right side knowledge in Core")
        contains(source, "guard rowsMatchVisibleText() else", "Diff workspace must reject stale debounced rows before applying decorations or spacers")
        contains(source, "clearDecorations()", "Stale diff rows must clear old decorations instead of leaving highlights on freshly pasted text")
        contains(source, "clearTemporaryDecorations(in: leftTextView)", "Stale diff rows must clear old inline TextKit temporary attributes from the left editor")
        contains(source, "clearTemporaryDecorations(in: rightTextView)", "Stale diff rows must clear old inline TextKit temporary attributes from the right editor")
        contains(source, "DiffDecorationFreshness.rowsMatchVisibleText(", "Diff row freshness must delegate visible-text matching to Core")
        contains(coreDecorationsSource, "matchedLines.count == lines.count", "Diff row freshness must require every visible source line on each side to be represented")
        contains(source, "layoutManager.addTemporaryAttribute(\n                        .foregroundColor,\n                        value: segment.kind == .added ? IndexDiffNSPalette.success : IndexDiffNSPalette.error", "JSON and text diff inline fragments must share the same red/green foreground emphasis")
        doesNotContain(editableDiffImplementation, "lineSpacingAfterGlyphAt", "Editable diff must not align rows by adding real TextKit after-line spacing")
        doesNotContain(editableDiffImplementation, "DiffLineSpacerMap", "Editable diff must not keep display-only spacer state in the real text layout")
        doesNotContain(editableDiffImplementation, "DiffLineSpacerBlock", "Editable diff must not draw artificial spacer rows as part of the editable text layout")
        doesNotContain(editableDiffImplementation, "applyRowAlignmentSpacers", "Editable diff row alignment must stay decoration-only until a source/display mapping exists")
        doesNotContain(editableDiffImplementation, "lineSpacers", "Editable diff rulers and text views must not carry spacer maps that can move real source rows")
        doesNotContain(textDiff, "diffReportFileName:", "Text diff must not expose a generated diff report save button")
        doesNotContain(textDiff, "leftFileName:", "Text diff must not expose pane-local source save buttons")
        doesNotContain(jsonDiff, "leftFileName:", "JSON diff must not expose pane-local source save buttons")
        doesNotContain(source, "IndexDiffToolbarSaveButton", "Diff toolbar must not include save/download buttons")
        doesNotContain(source, "saveClient: any IndexTextConversionTextSaving", "Diff workspace must not keep the text-saving seam when save actions are disabled")
        doesNotContain(source, "UnifiedDiffReport.make(", "Diff workspace must not generate export reports after save/export removal")
        doesNotContain(editableDiffImplementation, "paragraphSpacingBeforeGlyphAt", "Diff TextKit spacers must not add before-first spacing that moves an empty pane cursor down")
        doesNotContain(editableDiffImplementation, "beforeFirst", "Diff TextKit spacer maps must not carry before-first placeholder spacing")
        doesNotContain(editableDiffImplementation, "CGFloat(lineNumber - 1) * lineHeight", "Diff line painting must not return to fixed logical-line-height positioning")
        doesNotContain(source, "NSSavePanel()", "Diff workspace must not construct save panels directly")
        doesNotContain(source, "scrollViewDidScroll", "Diff editors must not keep the old side-by-side internal scroll synchronization")
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
            doesNotContain(source, ".frame(width: editorWidth", "Legacy side-by-side reader must not pin a horizontally scrolling editor width")
        }
    }

    @Test func jsonHighlightingAdaptersUseCoreRanges() throws {
        let swiftUIAdapter = try readSource("Sources/XTools/Shared/JSONSyntaxHighlighter.swift")
        let appKitAdapter = try readSource("Sources/XTools/ToolPages/Workbench/Diff/IndexEditableDiffWorkspace.swift")

        contains(swiftUIAdapter, "JSONHighlighting.tokens(in: line)", "SwiftUI JSON highlighting must use the shared Core JSON 着色标记 scanner")
        contains(appKitAdapter, "JSONHighlighting.tokens(in: line)", "Editable diff JSON highlighting must use the shared Core JSON 着色标记 scanner")
        contains(appKitAdapter, "line[start..<end].utf16.count", "Editable diff JSON highlighting must convert character offsets into UTF-16 NSRange lengths")
    }
}
