import AppKit
import SwiftUI
import XToolsCore

struct IndexEditableDiffMergeView: NSViewRepresentable {
    /// 左右编辑器的角色标识，供 `DifferenceHunk` 的侧别查询与协调器的
    /// UI 标签共用。
    enum Side {
        case left
        case right

        var defaultAccessibilityLabel: String {
            switch self {
            case .left:
                return "原始文本"
            case .right:
                return "对比文本"
            }
        }
    }

    /// Consecutive changed rows form one navigation unit. Keeping every
    /// visual line for each side lets a deletion move to the side that
    /// actually has source text instead of selecting an unrelated line
    /// with the same display number in the other editor.
    struct DifferenceHunk: Equatable {
        var leftLines: [Int] = []
        var rightLines: [Int] = []

        func firstLine(for side: Side) -> Int? {
            switch side {
            case .left: return leftLines.first
            case .right: return rightLines.first
            }
        }

        func contains(_ line: Int, on side: Side) -> Bool {
            switch side {
            case .left: return leftLines.contains(line)
            case .right: return rightLines.contains(line)
            }
        }
    }

    /// 对齐行 → 连续差异块的纯规划：不读编辑器状态，可直接行为测试，
    /// 与 `IndexEditableDiffWorkspace.differenceBlockCount` 语义同源。
    static func planDifferenceHunks(in rows: [DiffAlignedRow]) -> [DifferenceHunk] {
        var planned: [DifferenceHunk] = []
        var active: DifferenceHunk?

        func flushActive() {
            guard let current = active else { return }
            planned.append(current)
            active = nil
        }

        for row in rows {
            guard row.kind.isDifference else {
                flushActive()
                continue
            }
            if active == nil {
                active = DifferenceHunk()
            }
            if let line = row.left?.lineNumber {
                active?.leftLines.append(line)
            }
            if let line = row.right?.lineNumber {
                active?.rightLines.append(line)
            }
        }
        flushActive()
        return planned
    }

    @Binding var left: String
    @Binding var right: String
    let leftPlaceholder: String
    let rightPlaceholder: String
    let leftAccessibilityLabel: String
    let rightAccessibilityLabel: String
    let leftDisplayText: String?
    let rightDisplayText: String?
    let rows: [DiffAlignedRow]
    let syntax: IndexDiffSyntax
    let foldUnchanged: Bool
    var differenceNavigationRequest: DiffDifferenceNavigationRequest? = nil
    var onFileDropDiagnostic: ((String?) -> Void)? = nil
    var onDifferenceNavigationChange: ((DiffDifferenceNavigationProgress) -> Void)? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(left: $left, right: $right)
    }

    func makeNSView(context: Context) -> NSView {
        let hostView = IndexEditableDiffScrollHostView()
        hostView.onNavigateDifference = { [weak coordinator = context.coordinator] forward in
            coordinator?.navigateDifference(forward: forward)
        }
        let splitView = IndexEditableDiffPanePairView()
        hostView.splitView = splitView
        context.coordinator.hostView = hostView
        context.coordinator.outerScrollView = hostView.outerScrollView
        context.coordinator.onDifferenceNavigationChange = onDifferenceNavigationChange
        context.coordinator.onFileDropDiagnostic = onFileDropDiagnostic
        hostView.onLayout = { [weak coordinator = context.coordinator] in
            coordinator?.refreshEditorLayout()
        }
        let leftEditor = context.coordinator.makeEditor(
            side: .left,
            placeholder: leftPlaceholder,
            accessibilityLabel: leftAccessibilityLabel
        )
        let rightEditor = context.coordinator.makeEditor(
            side: .right,
            placeholder: rightPlaceholder,
            accessibilityLabel: rightAccessibilityLabel
        )

        splitView.installPanes(leftEditor, rightEditor)

        context.coordinator.update(
            left: leftDisplayText ?? left,
            right: rightDisplayText ?? right,
            rows: rows,
            syntax: syntax,
            foldUnchanged: foldUnchanged
        )
        return hostView
    }

    func updateNSView(_ view: NSView, context: Context) {
        guard let hostView = view as? IndexEditableDiffScrollHostView else {
            return
        }
        context.coordinator.left = $left
        context.coordinator.right = $right
        context.coordinator.hostView = hostView
        context.coordinator.outerScrollView = hostView.outerScrollView
        context.coordinator.onDifferenceNavigationChange = onDifferenceNavigationChange
        context.coordinator.onFileDropDiagnostic = onFileDropDiagnostic
        context.coordinator.updateAccessibilityLabels(
            left: leftAccessibilityLabel,
            right: rightAccessibilityLabel
        )
        context.coordinator.update(
            left: leftDisplayText ?? left,
            right: rightDisplayText ?? right,
            rows: rows,
            syntax: syntax,
            foldUnchanged: foldUnchanged
        )

        if let request = differenceNavigationRequest,
           request.id != context.coordinator.lastNavigationRequestID {
            context.coordinator.lastNavigationRequestID = request.id
            context.coordinator.navigateDifference(forward: request.forward)
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var left: Binding<String>
        var right: Binding<String>
        var onFileDropDiagnostic: ((String?) -> Void)?

        private weak var leftTextView: NSTextView?
        private weak var rightTextView: NSTextView?
        private weak var leftScrollView: NSScrollView?
        private weak var rightScrollView: NSScrollView?
        fileprivate weak var hostView: IndexEditableDiffScrollHostView?
        weak var outerScrollView: NSScrollView? {
            didSet {
                if let oldValue {
                    NotificationCenter.default.removeObserver(self, name: NSView.boundsDidChangeNotification, object: oldValue.contentView)
                }
                if let outerScrollView {
                    outerScrollView.contentView.postsBoundsChangedNotifications = true
                    NotificationCenter.default.addObserver(self, selector: #selector(viewportDidChange(_:)), name: NSView.boundsDidChangeNotification, object: outerScrollView.contentView)
                }
            }
        }
        private var isRefreshingLayout = false
        private var isApplyingViewportDecorations = false
        private var decorationGeneration = 0
        private var decorationsAreCurrent = false
        private weak var leftPlaceholderLabel: NSTextField?
        private weak var rightPlaceholderLabel: NSTextField?
        private weak var leftLineNumberView: IndexDiffLineNumberOverlayView?
        private weak var rightLineNumberView: IndexDiffLineNumberOverlayView?
        private var isApplyingProgrammaticText = false
        private var currentRows: [DiffAlignedRow] = []
        /// 派生数据缓存的 rows 身份：仅在 rows 值真正变化时递增（值相等
        /// 的数组替换不递增——decoration 只由 row 值派生，无需失效）。
        private var currentRowsGeneration = 0
        private var currentSyntax: IndexDiffSyntax = .plain
        private var latestLeftDisplayText = ""
        private var latestRightDisplayText = ""

        // Fold projection state: full canonical rows arrive from the binding;
        // the coordinator owns the per-region expansion set so an expand click
        // re-projects locally without re-running the diff.
        private var fullRows: [DiffAlignedRow] = []
        private var foldEnabled = false
        private var expandedFoldRegions: Set<Int> = []
        private var leftFoldPlaceholders: [Int: DiffFoldRegion] = [:]
        private var rightFoldPlaceholders: [Int: DiffFoldRegion] = [:]
        private var differenceHunks: [DifferenceHunk] = []
        private var navigationSelection: NavigationSelection?
        private var lastFocusedSide: Side = .left
        private var isApplyingNavigationSelection = false
        var onDifferenceNavigationChange: ((DiffDifferenceNavigationProgress) -> Void)?
        var lastNavigationRequestID = 0

        // Wave 2 locating wash: one block wash plus one slot-mark deepening
        // per pane. Bumping the generation per successful jump keeps each
        // wash a single arc; Reduce Motion leaves these silent (the jump
        // still scrolls and selects).
        private var blockWashes: [Side: ToolLocatingWashView] = [:]
        private var locatingWashGeneration = 0

        private struct NavigationSelection {
            let hunkIndex: Int
            let side: Side
            let location: Int
        }

        // Each editor pane resolves undo to its own private manager rather than
        // the shared window manager. NSTextView has no built-in per-view undo
        // isolation here (the panes share this one delegate), so ⌘Z would
        // otherwise pop actions off the window stack whose target text object was
        // already torn down — a use-after-free crash. See ADR-0022.
        private let leftUndo = IndexPrivateUndoStack()
        private let rightUndo = IndexPrivateUndoStack()

        init(left: Binding<String>, right: Binding<String>) {
            self.left = left
            self.right = right
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }

        func undoManager(for view: NSTextView) -> UndoManager? {
            if view === rightTextView { return rightUndo.manager }
            return leftUndo.manager
        }

        func makeEditor(
            side: Side,
            placeholder: String,
            accessibilityLabel: String? = nil
        ) -> NSView {
            let textView = IndexDiffTextView(frame: .zero)
            textView.onCompositionChange = { [weak self] marked in
                self?.refreshPlaceholders()
                if marked { self?.clearDecorations() }
            }
            textView.onAppearanceChange = { [weak self] in
                self?.decorationGeneration &+= 1
                self?.refreshViewportDecorations()
            }
            _ = textView.diffTextIndex
            configure(textView)
            textView.setAccessibilityLabel(accessibilityLabel ?? side.defaultAccessibilityLabel)

            let dropHandler: (String) -> Void = { [weak self] content in
                guard let self else { return }
                switch side {
                case .left:
                    self.left.wrappedValue = content
                    self.setText(content, source: content, in: self.leftTextView, allowActiveEditorOverride: true)
                case .right:
                    self.right.wrappedValue = content
                    self.setText(content, source: content, in: self.rightTextView, allowActiveEditorOverride: true)
                }
                self.refreshPlaceholders()
                self.refreshEditorLayout()
            }
            textView.onFileDrop = dropHandler
            textView.onFileDropDiagnostic = { [weak self] message in
                self?.onFileDropDiagnostic?(message)
            }
            textView.registerForDraggedTypes([.fileURL, .string])

            let scrollView = IndexDiffEditorScrollView(frame: .zero)
            scrollView.registerForDraggedTypes([.fileURL])
            scrollView.contentView = IndexLeadingLockedClipView(frame: .zero)
            scrollView.forwardingScrollView = outerScrollView
            scrollView.trailingReadingGuard = IndexDiffEditorMetrics.trailingReadingGuard
            scrollView.translatesAutoresizingMaskIntoConstraints = false
            scrollView.borderType = .noBorder
            scrollView.drawsBackground = false
            scrollView.hasVerticalScroller = false
            scrollView.hasHorizontalScroller = false
            scrollView.autohidesScrollers = true
            scrollView.verticalScrollElasticity = .none
            scrollView.horizontalScrollElasticity = .none
            scrollView.documentView = textView

            let lineNumberView = IndexDiffLineNumberOverlayView(scrollView: scrollView, textView: textView)
            lineNumberView.translatesAutoresizingMaskIntoConstraints = false

            let placeholderLabel = NSTextField(labelWithString: placeholder)
            placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
            placeholderLabel.font = .monospacedSystemFont(ofSize: 12.5, weight: .regular)
            placeholderLabel.textColor = IndexDiffNSPalette.textTertiary
            placeholderLabel.lineBreakMode = .byTruncatingTail
            placeholderLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

            let container = IndexDiffEditorPaneView(frame: .zero)
            container.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(scrollView)
            container.addSubview(lineNumberView)
            container.addSubview(placeholderLabel)
            NSLayoutConstraint.activate([
                scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                scrollView.topAnchor.constraint(equalTo: container.topAnchor),
                scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
                lineNumberView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                lineNumberView.topAnchor.constraint(equalTo: container.topAnchor),
                lineNumberView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
                lineNumberView.widthAnchor.constraint(equalToConstant: IndexDiffEditorMetrics.rulerWidth),
                placeholderLabel.leadingAnchor.constraint(
                    equalTo: container.leadingAnchor,
                    constant: IndexDiffEditorMetrics.textInset.width
                ),
                placeholderLabel.trailingAnchor.constraint(
                    lessThanOrEqualTo: container.trailingAnchor,
                    constant: -IndexDiffEditorMetrics.placeholderTrailing
                ),
                placeholderLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: IndexDiffEditorMetrics.placeholderTopInset)
            ])

            switch side {
            case .left:
                leftTextView = textView
                leftScrollView = scrollView
                leftPlaceholderLabel = placeholderLabel
                leftLineNumberView = lineNumberView
            case .right:
                rightTextView = textView
                rightScrollView = scrollView
                rightPlaceholderLabel = placeholderLabel
                rightLineNumberView = lineNumberView
            }

            // Wave 2 locating wash surfaces: the block wash rides above the
            // editor pane; the slot-mark deepening rides above the gutter
            // overlay. Both stay non-interactive and animate opacity only.
            let blockWash = ToolLocatingWashView()
            container.addSubview(blockWash)
            blockWashes[side] = blockWash

            // Set the delegate only after the side references are wired, so the
            // first `undoManager(for:)` query can resolve this view to its own
            // side's private manager (never fall through to the wrong side).
            textView.delegate = self

            return container
        }

        func updateAccessibilityLabels(left: String, right: String) {
            leftTextView?.setAccessibilityLabel(left)
            rightTextView?.setAccessibilityLabel(right)
        }

        func update(left: String, right: String, rows: [DiffAlignedRow], syntax: IndexDiffSyntax, foldUnchanged: Bool) {
            fullRows = rows
            if foldUnchanged {
                expandedFoldRegions.formIntersection(Set(DiffFoldProjection.regions(in: rows).map(\.id)))
            }
            foldEnabled = foldUnchanged
            currentSyntax = syntax
            latestLeftDisplayText = left
            latestRightDisplayText = right
            render()
        }

        /// Re-projects the full rows through the fold planner (honoring the
        /// expansion set) and pushes the composed text into both editors.
        private func render() {
            let composition: (rows: [DiffAlignedRow], leftText: String, rightText: String)
            if foldEnabled, fullRows.contains(where: { $0.kind.isDifference }) {
                let applied = DiffFoldProjection.apply(rows: fullRows, expandedRegionIDs: expandedFoldRegions)
                composition = (applied.rows, applied.leftText, applied.rightText)
            } else {
                composition = (fullRows, latestLeftDisplayText, latestRightDisplayText)
            }

            let projectionChanged = composition.rows != currentRows
            currentRows = composition.rows
            if projectionChanged {
                currentRowsGeneration &+= 1
            }
            updateDifferenceHunks(resetNavigation: projectionChanged)
            leftFoldPlaceholders = Dictionary(
                composition.rows.compactMap { row in
                    guard let region = row.foldRegion, let visual = row.left?.lineNumber else { return nil }
                    return (visual, region)
                },
                uniquingKeysWith: { first, _ in first }
            )
            rightFoldPlaceholders = Dictionary(
                composition.rows.compactMap { row in
                    guard let region = row.foldRegion, let visual = row.right?.lineNumber else { return nil }
                    return (visual, region)
                },
                uniquingKeysWith: { first, _ in first }
            )

            // Editing stays blocked only while some region is collapsed; once
            // every region is expanded the editors accept keystrokes again.
            let hasCollapsedRegion = !leftFoldPlaceholders.isEmpty || !rightFoldPlaceholders.isEmpty
            leftTextView?.isEditable = !hasCollapsedRegion
            rightTextView?.isEditable = !hasCollapsedRegion

            let freshComposedLeft = !JSONExactTextIdentity.isExactlyEqual(composition.leftText, latestAppliedLeftText)
            let freshComposedRight = !JSONExactTextIdentity.isExactlyEqual(composition.rightText, latestAppliedRightText)
            let overrideFresh = currentSyntax == .json && (freshComposedLeft || freshComposedRight)
            // A collapsed projection is intentionally read-only and must
            // replace both native buffers, including the focused pane. The
            // active-editor guard remains for ordinary live results so a
            // debounced recomputation never overwrites an editable draft.
            let overrideFoldProjection = hasCollapsedRegion
            setText(
                composition.leftText,
                source: self.left.wrappedValue,
                in: leftTextView,
                allowActiveEditorOverride: (overrideFresh && freshComposedLeft) || overrideFoldProjection
            )
            setText(
                composition.rightText,
                source: self.right.wrappedValue,
                in: rightTextView,
                allowActiveEditorOverride: (overrideFresh && freshComposedRight) || overrideFoldProjection
            )
            updateFoldAccessibility(
                in: leftTextView,
                hasCollapsedRegion: hasCollapsedRegion
            )
            updateFoldAccessibility(
                in: rightTextView,
                hasCollapsedRegion: hasCollapsedRegion
            )
            latestAppliedLeftText = composition.leftText
            latestAppliedRightText = composition.rightText
            refreshEditorLayout()
            applyDecorations()
            refreshPlaceholders()
        }

        private var latestAppliedLeftText = ""
        private var latestAppliedRightText = ""

        private func toggleFoldRegion(_ regionID: Int) {
            if expandedFoldRegions.contains(regionID) {
                expandedFoldRegions.remove(regionID)
            } else {
                expandedFoldRegions.insert(regionID)
            }
            render()
        }

        func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            guard let raw = link as? String, let regionID = Int(raw) else {
                return false
            }
            toggleFoldRegion(regionID)
            return true
        }

        // MARK: Difference navigation

        func navigateDifference(forward: Bool) {
            guard let textView = navigationTextView(), !differenceHunks.isEmpty else {
                return
            }
            let preferredSide: Side = textView === rightTextView ? .right : .left
            let targetIndex = navigationTargetIndex(
                forward: forward,
                from: textView,
                preferredSide: preferredSide
            )
            let hunk = differenceHunks[targetIndex]
            let targetSide = hunk.firstLine(for: preferredSide) == nil
                ? opposite(of: preferredSide)
                : preferredSide
            guard let targetLine = hunk.firstLine(for: targetSide),
                  let targetTextView = editorTextView(for: targetSide),
                  let targetRange = navigationRange(
                      forVisualLine: targetLine,
                      side: targetSide,
                      in: targetTextView
                  ) else {
                return
            }

            navigationSelection = NavigationSelection(
                hunkIndex: targetIndex,
                side: targetSide,
                location: targetRange.location
            )
            isApplyingNavigationSelection = true
            targetTextView.window?.makeFirstResponder(targetTextView)
            targetTextView.setSelectedRange(targetRange)
            // A distant target can extend a lazily laid-out prefix. Grow the
            // shared document before native reveal so an inner clip cannot
            // acquire its own vertical scroll offset.
            targetTextView.layoutManager?.ensureLayout(forCharacterRange: targetRange)
            refreshEditorLayout()
            hostView?.layoutSubtreeIfNeeded()
            targetTextView.scrollRangeToVisible(targetRange)
            scrollSelectionIntoOuterView(targetTextView)
            isApplyingNavigationSelection = false
            lastFocusedSide = targetSide
            NSAccessibility.post(element: targetTextView, notification: .selectedTextChanged)
            NSAccessibility.post(
                element: targetTextView,
                notification: .announcementRequested,
                userInfo: [
                    .announcement: "差异块 \(targetIndex + 1) / \(differenceHunks.count)",
                    .priority: NSAccessibilityPriorityLevel.high
                ]
            )
            onDifferenceNavigationChange?(
                DiffDifferenceNavigationProgress(
                    current: targetIndex + 1,
                    total: differenceHunks.count
                )
            )

            // Wave 2 locating wash: one arc over the landed block (and its
            // gutter slot marks) per jump; Reduce Motion keeps positioning
            // only. The scroll/selection behavior above is untouched.
            locatingWashGeneration += 1
            playLocatingWash(for: hunk, generation: locatingWashGeneration)
        }

        /// Wave 2 locating wash (see `ToolMotion.LocatingWash`): after a jump
        /// lands, every pane that carries the hunk sweeps one soft accent
        /// wash across the block while its gutter slot mark deepens on the
        /// same 360ms arc. Single element per pane, single arc per jump.
        /// Reduce Motion skips the wash entirely — positioning is owned by
        /// `navigateDifference(forward:)` and never changes here.
        private func playLocatingWash(for hunk: DifferenceHunk, generation: Int) {
            guard !ToolMotion.systemReduceMotionEnabled else { return }
            for side in [Side.left, Side.right] {
                let lines = side == .left ? hunk.leftLines : hunk.rightLines
                guard !lines.isEmpty,
                      let textView = editorTextView(for: side),
                      let lineNumberView = side == .left ? leftLineNumberView : rightLineNumberView,
                      let container = lineNumberView.superview,
                      let blockWash = blockWashes[side] else {
                    continue
                }

                let lineRects = IndexDiffTextLayoutGeometry.lineBlockRects(for: textView, visibleRect: viewportRect(for: textView))
                var block = NSRect.null
                for line in lines {
                    guard let rect = lineRects[line] else { continue }
                    block = block.isNull ? rect : block.union(rect)
                }
                guard !block.isNull else { continue }

                // The wash spans the pane width so wrapped or horizontally
                // shifted rows stay covered; its height hugs the block.
                var washRect = textView.convert(block, to: container)
                washRect.origin.x = 0
                washRect.size.width = container.bounds.width
                blockWash.play(generation: generation, frame: washRect)


            }
        }

        private func updateDifferenceHunks(resetNavigation: Bool) {
            let planned = planDifferenceHunks(in: currentRows)

            let hunksChanged = resetNavigation || planned != differenceHunks
            let hadNavigationSelection = navigationSelection != nil
            if hunksChanged {
                navigationSelection = nil
            }
            differenceHunks = planned
            if hunksChanged, hadNavigationSelection {
                let progress = DiffDifferenceNavigationProgress(current: nil, total: planned.count)
                DispatchQueue.main.async { [weak self] in
                    self?.onDifferenceNavigationChange?(progress)
                }
            }
        }

        private func navigationTargetIndex(
            forward: Bool,
            from textView: NSTextView,
            preferredSide: Side
        ) -> Int {
            if let navigationSelection,
               navigationSelection.side == preferredSide,
               navigationSelection.hunkIndex < differenceHunks.count,
               textView.selectedRange().location == navigationSelection.location {
                return wrappedIndex(
                    from: navigationSelection.hunkIndex,
                    forward: forward,
                    count: differenceHunks.count
                )
            }

            let selection = textView.selectedRange()
            let anchor = Self.anchorVisualLine(in: textView)
            // A fresh editor starts at line one with an empty caret. In that
            // state the first request deliberately reaches the first block
            // (or the last for previous) instead of silently skipping a
            // change that begins on the first line.
            guard selection.location > 0 || selection.length > 0 else {
                return forward ? 0 : differenceHunks.count - 1
            }

            if let current = differenceHunks.firstIndex(where: { $0.contains(anchor, on: preferredSide) }) {
                return wrappedIndex(from: current, forward: forward, count: differenceHunks.count)
            }

            if forward {
                return differenceHunks.firstIndex {
                    ($0.firstLine(for: preferredSide) ?? Int.max) > anchor
                } ?? 0
            }
            return differenceHunks.lastIndex {
                ($0.firstLine(for: preferredSide) ?? Int.min) < anchor
            } ?? differenceHunks.count - 1
        }

        private func wrappedIndex(from index: Int, forward: Bool, count: Int) -> Int {
            forward ? (index + 1) % count : (index + count - 1) % count
        }

        private func opposite(of side: Side) -> Side {
            side == .left ? .right : .left
        }

        private func editorTextView(for side: Side) -> NSTextView? {
            side == .left ? leftTextView : rightTextView
        }

        private func navigationTextView() -> NSTextView? {
            if let rightTextView, rightTextView.window?.firstResponder === rightTextView {
                lastFocusedSide = .right
                return rightTextView
            }
            if let leftTextView, leftTextView.window?.firstResponder === leftTextView {
                lastFocusedSide = .left
                return leftTextView
            }
            return editorTextView(for: lastFocusedSide) ?? leftTextView ?? rightTextView
        }

        private static func anchorVisualLine(in textView: NSTextView) -> Int {
            let nsText = textView.string as NSString
            guard nsText.length > 0 else { return 1 }
            let selected = textView.selectedRange()
            let location = min(max(selected.location, 0), max(nsText.length - 1, 0))
            var line = 1
            var index = 0
            while index < location {
                if nsText.character(at: index) == unichar(10) {
                    line += 1
                }
                index += 1
            }
            return line
        }

        private func navigationRange(
            forVisualLine line: Int,
            side: Side,
            in textView: NSTextView
        ) -> NSRange? {
            let lineRanges = IndexDiffTextLayoutGeometry.lineRanges(for: textView)
            guard line >= 1, line <= lineRanges.count else { return nil }
            let lineRange = lineRanges[line - 1]
            let cell = currentRows.lazy.compactMap { row -> DiffAlignedCell? in
                guard row.kind.isDifference else { return nil }
                let candidate = side == .left ? row.left : row.right
                return candidate?.lineNumber == line ? candidate : nil
            }.first
            let inlineOffset = cell.map { firstDifferenceUTF16Offset(in: $0) } ?? 0
            return NSRange(
                location: lineRange.location + min(inlineOffset, lineRange.length),
                length: 0
            )
        }

        private func firstDifferenceUTF16Offset(in cell: DiffAlignedCell) -> Int {
            var offset = 0
            for segment in cell.segments {
                if segment.kind != .unchanged {
                    return offset
                }
                offset += (segment.text as NSString).length
            }
            return 0
        }

        func textDidBeginEditing(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            let focusedSide: Side
            if textView === leftTextView {
                focusedSide = .left
            } else if textView === rightTextView {
                focusedSide = .right
            } else {
                return
            }
            lastFocusedSide = focusedSide
            if !isApplyingNavigationSelection,
               let navigationSelection,
               navigationSelection.side != focusedSide {
                self.navigationSelection = nil
                onDifferenceNavigationChange?(
                    DiffDifferenceNavigationProgress(current: nil, total: differenceHunks.count)
                )
            }
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard !isApplyingNavigationSelection,
                  let textView = notification.object as? NSTextView else {
                return
            }
            if textView === leftTextView {
                lastFocusedSide = .left
            } else if textView === rightTextView {
                lastFocusedSide = .right
            } else {
                return
            }

            guard let navigationSelection,
                  textView.selectedRange().location != navigationSelection.location
                    || textView.selectedRange().length != 0 else {
                return
            }
            self.navigationSelection = nil
            onDifferenceNavigationChange?(
                DiffDifferenceNavigationProgress(current: nil, total: differenceHunks.count)
            )
        }

        func textDidChange(_ notification: Notification) {
            guard !isApplyingProgrammaticText, let textView = notification.object as? NSTextView else {
                return
            }

            clearDecorations()
            if textView === leftTextView {
                left.wrappedValue = textView.string
            } else if textView === rightTextView {
                right.wrappedValue = textView.string
            }
            refreshPlaceholders()
            refreshEditorLayout()
            scrollSelectionIntoOuterView(textView)
        }

        func textDidEndEditing(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else {
                return
            }

            applyLatestDisplay(to: textView)
            applyDecorations()
        }

        private func applyLatestDisplay(to textView: NSTextView) {
            if textView === leftTextView {
                setText(
                    latestLeftDisplayText,
                    source: left.wrappedValue,
                    in: textView,
                    allowActiveEditorOverride: true
                )
            } else if textView === rightTextView {
                setText(
                    latestRightDisplayText,
                    source: right.wrappedValue,
                    in: textView,
                    allowActiveEditorOverride: true
                )
            }
        }

        private func configure(_ textView: NSTextView) {
            IndexNativeViewportLayout.configure(textView, allowsNonContiguousLayout: false)
            textView.font = .monospacedSystemFont(ofSize: 12.5, weight: .regular)
            textView.textColor = IndexDiffNSPalette.textPrimary
            textView.insertionPointColor = IndexDiffNSPalette.textPrimary
            textView.drawsBackground = false
            textView.isEditable = true
            textView.isSelectable = true
            AppKitTextEditingConfiguration.configurePlainTextEditor(textView)
            textView.isRichText = false
            textView.importsGraphics = false
            textView.usesFindBar = true
            textView.isIncrementalSearchingEnabled = true
            textView.textContainerInset = IndexDiffEditorMetrics.textInset
            textView.minSize = NSSize(width: 0, height: 0)
            textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
            textView.isVerticallyResizable = true
            textView.isHorizontallyResizable = false
            textView.autoresizingMask = [.width]
            if let textContainer = textView.textContainer {
                textContainer.widthTracksTextView = false
                textContainer.lineBreakMode = .byCharWrapping
                textContainer.lineFragmentPadding = 0
                textContainer.containerSize = NSSize(
                    width: IndexTextKitGeometry.wrappingContainerWidth(
                        for: textView,
                        visibleWidth: textView.bounds.width,
                        trailingReadingGuard: IndexDiffEditorMetrics.trailingReadingGuard
                    ),
                    height: CGFloat.greatestFiniteMagnitude
                )
            }
        }

        private func updateFoldAccessibility(
            in textView: NSTextView?,
            hasCollapsedRegion: Bool
        ) {
            guard let textView else { return }
            textView.setAccessibilityHelp(
                hasCollapsedRegion
                    ? "未变更内容已折叠，编辑器当前为只读；展开折叠区域后可继续编辑。"
                    : nil
            )
        }

        private func setText(
            _ text: String,
            source: String,
            in textView: NSTextView?,
            allowActiveEditorOverride: Bool = false
        ) {
            guard let textView,
                  !JSONExactTextIdentity.isExactlyEqual(textView.string, text),
                  !textView.hasMarkedText() else {
                return
            }

            if !allowActiveEditorOverride,
               isActiveEditor(textView),
               JSONExactTextIdentity.isExactlyEqual(textView.string, source) {
                return
            }

            let selectedRanges = textView.selectedRanges
            isApplyingProgrammaticText = true
            defer { isApplyingProgrammaticText = false }
            (textView as? IndexDiffTextView)?.invalidateDroppedFile()
            textView.setStringWithoutUndoRegistration(text)

            let textLength = (text as NSString).length
            if !JSONExactTextIdentity.isExactlyEqual(text, source) {
                // Canonical replacement (e.g. JSON formatting/sorting): the
                // text structure has changed so old cursor offsets are
                // meaningless — dock to the end.
                textView.selectedRanges = [NSValue(range: NSRange(location: textLength, length: 0))]
            } else {
                let validRanges = selectedRanges.filter { $0.rangeValue.upperBound <= textLength }
                textView.selectedRanges = validRanges.isEmpty
                    ? [NSValue(range: NSRange(location: textLength, length: 0))]
                    : validRanges
            }
            refreshPlaceholders()
            refreshEditorLayout()
        }

        private func isActiveEditor(_ textView: NSTextView) -> Bool {
            textView.window?.firstResponder === textView
        }

        func refreshEditorLayout() {
            guard let hostView, !isRefreshingLayout else { return }
            isRefreshingLayout = true
            defer { isRefreshingLayout = false }

            updateEditorGeometry(leftTextView, in: leftScrollView)
            updateEditorGeometry(rightTextView, in: rightScrollView)

            let contentHeight = max(measuredHeight(for: leftTextView), measuredHeight(for: rightTextView))
            hostView.contentHeight = contentHeight
            updateEditorGeometry(leftTextView, in: leftScrollView)
            updateEditorGeometry(rightTextView, in: rightScrollView)
            leftLineNumberView?.needsDisplay = true
            rightLineNumberView?.needsDisplay = true
            refreshViewportDecorations()
        }

        private func updateEditorGeometry(_ textView: NSTextView?, in scrollView: NSScrollView?) {
            guard let textView, let scrollView else {
                return
            }

            let width = max(1, scrollView.contentSize.width)
            let height = max(hostView?.contentHeight ?? 0, scrollView.contentSize.height)
            (scrollView as? IndexDiffEditorScrollView)?.minimumDocumentHeight = height
            IndexDiffTextLayoutGeometry.synchronizeTextGeometry(
                for: textView,
                visibleWidth: width,
                minimumHeight: height,
                trailingReadingGuard: IndexDiffEditorMetrics.trailingReadingGuard
            )
        }

        private func measuredHeight(for textView: NSTextView?) -> CGFloat {
            guard let textView else {
                return 0
            }

            return IndexDiffTextLayoutGeometry.documentHeight(for: textView)
        }

        private func scrollSelectionIntoOuterView(_ textView: NSTextView) {
            guard let documentView = outerScrollView?.documentView,
                  let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer else {
                return
            }

            let selectedRange = textView.selectedRange()
            let characterLocation = min(selectedRange.location, (textView.string as NSString).length)
            let glyphRange = layoutManager.glyphRange(
                forCharacterRange: NSRange(location: characterLocation, length: 0),
                actualCharacterRange: nil
            )
            refreshEditorLayout()
            hostView?.layoutSubtreeIfNeeded()
            var caretRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
            caretRect.origin.x += textView.textContainerOrigin.x
            caretRect.origin.y += textView.textContainerOrigin.y
            caretRect.size.height = max(caretRect.height, layoutManager.defaultLineHeight(for: textView.font ?? .monospacedSystemFont(ofSize: 12.5, weight: .regular)))
            let documentRect = textView.convert(caretRect.insetBy(dx: 0, dy: -24), to: documentView)
            documentView.scrollToVisible(documentRect)
        }

        private func refreshPlaceholders() {
            leftPlaceholderLabel?.isHidden = !shouldShowPlaceholder(for: leftTextView)
            rightPlaceholderLabel?.isHidden = !shouldShowPlaceholder(for: rightTextView)
        }

        private func shouldShowPlaceholder(for textView: NSTextView?) -> Bool {
            guard let textView else {
                return false
            }

            return textView.string.isEmpty && !textView.hasMarkedText()
        }

        /// A1 缓存门：rows 身份与两侧 buffer revision 都未变时，freshness
        /// 结论与 decorations 是纯派生数据，直接复用——跳过 rowsMatchVisibleText
        /// 的全文拆行比对与 DiffEditorDecorations 重建（这两步原本在每次
        /// SwiftUI body 触发的 updateNSView → render 路径上都按 O(全文) 执行）。
        /// 失效条件覆盖：文本编辑（revision 变化）与 diff 行集替换（rows
        /// 身份变化）。窗口尺寸/可见范围不参与失效——视口裁剪由
        /// applyDecorations(to:) 的 span 门负责，这里不缓存任何视口相关
        /// 状态（符合 ADR-0009：无 display buffer）。
        private struct DecorationCache {
            var rowsGeneration: Int
            var leftRevision: Int
            var rightRevision: Int
            var syntax: IndexDiffSyntax
            var isFresh: Bool
            var decorations: DiffEditorDecorations?
        }
        private var decorationCache: DecorationCache?

        private func applyDecorations() {
            // revision 从 0 递增，-1 仅表示编辑器尚未创建。
            let leftRevision = (leftTextView as? IndexDiffTextView)?.diffTextIndex.revision ?? -1
            let rightRevision = (rightTextView as? IndexDiffTextView)?.diffTextIndex.revision ?? -1
            if let cache = decorationCache,
               cache.rowsGeneration == currentRowsGeneration,
               cache.leftRevision == leftRevision,
               cache.rightRevision == rightRevision,
               cache.syntax == currentSyntax {
                // 输入法组合期间缓冲文本是临时 marked text：无论缓存是否
                // 命中都保持清空状态，等提交后再重建（onCompositionChange
                // 已即时 clear，这里防止迟到路径把高亮挂回组合态）。
                if !cache.isFresh || leftTextView?.hasMarkedText() == true || rightTextView?.hasMarkedText() == true {
                    if decorationsAreCurrent {
                        clearDecorations()
                    }
                } else if let decorations = cache.decorations {
                    decorationsAreCurrent = true
                    applyDecorations(to: leftTextView, lineDecorations: decorations.left, syntax: currentSyntax, foldPlaceholders: leftFoldPlaceholders)
                    applyDecorations(to: rightTextView, lineDecorations: decorations.right, syntax: currentSyntax, foldPlaceholders: rightFoldPlaceholders)
                }
                return
            }

            guard rowsMatchVisibleText() else {
                decorationCache = DecorationCache(
                    rowsGeneration: currentRowsGeneration,
                    leftRevision: leftRevision,
                    rightRevision: rightRevision,
                    syntax: currentSyntax,
                    isFresh: false,
                    decorations: nil
                )
                clearDecorations()
                return
            }
            let decorations = DiffEditorDecorations(rows: currentRows)
            decorationCache = DecorationCache(
                rowsGeneration: currentRowsGeneration,
                leftRevision: leftRevision,
                rightRevision: rightRevision,
                syntax: currentSyntax,
                isFresh: true,
                decorations: decorations
            )
            publishDecorations(decorations)
        }

        private func publishDecorations(_ decorations: DiffEditorDecorations) {
            decorationGeneration &+= 1
            decorationsAreCurrent = true
            (leftTextView as? IndexDiffTextView)?.lineDecorations = decorations.left
            (rightTextView as? IndexDiffTextView)?.lineDecorations = decorations.right
            applyDecorations(to: leftTextView, lineDecorations: decorations.left, syntax: currentSyntax, foldPlaceholders: leftFoldPlaceholders)
            applyDecorations(to: rightTextView, lineDecorations: decorations.right, syntax: currentSyntax, foldPlaceholders: rightFoldPlaceholders)
            leftLineNumberView?.lineStatuses = decorations.left.mapValues(\.status)
            rightLineNumberView?.lineStatuses = decorations.right.mapValues(\.status)
            leftLineNumberView?.customLineNumbers = Dictionary(
                currentRows.compactMap { row in
                    guard let cell = row.left, let visualLine = cell.lineNumber else { return nil }
                    return (visualLine, cell.originalLineNumber)
                },
                uniquingKeysWith: { first, _ in first }
            )
            rightLineNumberView?.customLineNumbers = Dictionary(
                currentRows.compactMap { row in
                    guard let cell = row.right, let visualLine = cell.lineNumber else { return nil }
                    return (visualLine, cell.originalLineNumber)
                },
                uniquingKeysWith: { first, _ in first }
            )
        }

        private func clearDecorations() {
            decorationsAreCurrent = false
            (leftTextView as? IndexDiffTextView)?.lineDecorations = [:]
            (rightTextView as? IndexDiffTextView)?.lineDecorations = [:]
            clearTemporaryDecorations(in: leftTextView, entireDocument: true)
            clearTemporaryDecorations(in: rightTextView, entireDocument: true)
            leftLineNumberView?.lineStatuses = [:]
            rightLineNumberView?.lineStatuses = [:]
            leftLineNumberView?.customLineNumbers = [:]
            rightLineNumberView?.customLineNumbers = [:]
        }

        private func rowsMatchVisibleText() -> Bool {
            guard !currentRows.isEmpty else {
                return true
            }

            return rowsMatchVisibleText(side: .left, text: leftTextView?.string ?? "")
                && rowsMatchVisibleText(side: .right, text: rightTextView?.string ?? "")
        }

        private func rowsMatchVisibleText(side: Side, text: String) -> Bool {
            let decorationSide: DiffDecorationSide = side == .left ? .left : .right
            return DiffDecorationFreshness.rowsMatchVisibleText(
                rows: currentRows,
                side: decorationSide,
                text: text
            )
        }

        private func applyDecorations(
            to textView: NSTextView?,
            lineDecorations: [Int: DiffLineDecoration],
            syntax: IndexDiffSyntax,
            foldPlaceholders: [Int: DiffFoldRegion]
        ) {
            guard let textView,
                  let layoutManager = textView.layoutManager else { return }

            guard !textView.hasMarkedText() else { return }
            let indexed = textView as? IndexDiffTextView
            let lineRanges = IndexDiffTextLayoutGeometry.lineRanges(for: textView)
            let viewport = viewportRect(for: textView)
            let span = viewport.isEmpty ? 0..<min(32, lineRanges.count)
                : IndexDiffTextLayoutGeometry.visibleLineSpan(for: textView, ranges: lineRanges, visibleRect: viewport)
            let revision = indexed?.diffTextIndex.revision ?? 0
            if indexed?.lastDecorationSpan == span,
               indexed?.lastDecorationRevision == revision,
               indexed?.lastDecorationGeneration == decorationGeneration { return }
            clearTemporaryDecorations(in: textView)
            indexed?.lastDecorationSpan = span
            indexed?.lastDecorationRevision = revision
            indexed?.lastDecorationGeneration = decorationGeneration
            guard let first = span.first, let last = span.last else { return }
            indexed?.decoratedRange = NSRange(location: lineRanges[first].location,
                length: NSMaxRange(lineRanges[last]) - lineRanges[first].location)
            let nsText = textView.string as NSString
            for index in span {
                let range = lineRanges[index]
                let lineNumber = index + 1
                if let region = foldPlaceholders[lineNumber] {
                    layoutManager.addTemporaryAttribute(
                        .foregroundColor,
                        value: IndexDiffNSPalette.textTertiary,
                        forCharacterRange: range
                    )
                    // The placeholder line is the expand/collapse affordance;
                    // the link value carries the region identity back through
                    // textView(_:clickedOnLink:at:).
                    textView.textStorage?.addAttribute(
                        .link,
                        value: String(region.id),
                        range: range
                    )
                    continue
                }

                if syntax == .json, range.length <= 10_000 {
                    applyJSONSyntax(nsText.substring(with: range), lineRange: range, layoutManager: layoutManager)
                }

                guard let decoration = lineDecorations[lineNumber] else {
                    continue
                }

                var offset = 0
                for segment in decoration.segments {
                    let segmentLength = (segment.text as NSString).length
                    defer { offset += segmentLength }
                    guard segment.kind != .unchanged, segmentLength > 0 else {
                        continue
                    }

                    let segmentRange = NSRange(
                        location: min(range.location + offset, nsText.length),
                        length: min(segmentLength, max(0, NSMaxRange(range) - range.location - offset))
                    )
                    guard segmentRange.length > 0 else {
                        continue
                    }

                    layoutManager.addTemporaryAttribute(
                        .backgroundColor,
                        value: segment.kind == .added ? IndexDiffNSPalette.successFragment : IndexDiffNSPalette.errorFragment,
                        forCharacterRange: segmentRange
                    )
                    layoutManager.addTemporaryAttribute(
                        .underlineStyle,
                        value: NSUnderlineStyle.single.rawValue,
                        forCharacterRange: segmentRange
                    )
                    layoutManager.addTemporaryAttribute(
                        .underlineColor,
                        value: segment.kind == .added ? IndexDiffNSPalette.success : IndexDiffNSPalette.error,
                        forCharacterRange: segmentRange
                    )

                    layoutManager.addTemporaryAttribute(
                        .foregroundColor,
                        value: segment.kind == .added ? IndexDiffNSPalette.success : IndexDiffNSPalette.error,
                        forCharacterRange: segmentRange
                    )
                }
            }
        }

        private func clearTemporaryDecorations(in textView: NSTextView?, entireDocument: Bool = false) {
            guard let textView,
                  let layoutManager = textView.layoutManager else {
                return
            }

            let indexed = textView as? IndexDiffTextView
            let length = (textView.string as NSString).length
            // Native edits shift temporary ranges before the delegate callback.
            // Clear all sparse attributes on invalidation, but only the old
            // viewport during ordinary scrolling.
            let previous = entireDocument ? NSRange(location: 0, length: length)
                : indexed?.decoratedRange ?? NSRange(location: 0, length: 0)
            let fullRange = NSIntersectionRange(previous, NSRange(location: 0, length: length))
            indexed?.lastDecorationSpan = nil
            indexed?.decoratedRange = nil
            textView.textStorage?.removeAttribute(.link, range: fullRange)
            layoutManager.removeTemporaryAttribute(.foregroundColor, forCharacterRange: fullRange)
            layoutManager.removeTemporaryAttribute(.backgroundColor, forCharacterRange: fullRange)
            layoutManager.removeTemporaryAttribute(.underlineStyle, forCharacterRange: fullRange)
            layoutManager.removeTemporaryAttribute(.underlineColor, forCharacterRange: fullRange)
        }

        @objc private func viewportDidChange(_ notification: Notification) {
            refreshEditorLayout()
            refreshViewportDecorations()
            leftLineNumberView?.needsDisplay = true
            rightLineNumberView?.needsDisplay = true
        }

        private func viewportRect(for textView: NSTextView) -> NSRect {
            if let outerScrollView {
                return textView.convert(outerScrollView.contentView.bounds, from: outerScrollView.contentView).intersection(textView.bounds)
            }
            // Before the outer host is installed, AppKit may report a narrow
            // provisional frame that cannot lay out even one glyph. Use the
            // bounded initial decoration span until a real viewport exists.
            return .zero
        }

        private func refreshViewportDecorations() {
            guard decorationsAreCurrent, !isApplyingViewportDecorations else { return }
            isApplyingViewportDecorations = true
            defer { isApplyingViewportDecorations = false }
            applyDecorations(to: leftTextView, lineDecorations: (leftTextView as? IndexDiffTextView)?.lineDecorations ?? [:], syntax: currentSyntax, foldPlaceholders: leftFoldPlaceholders)
            applyDecorations(to: rightTextView, lineDecorations: (rightTextView as? IndexDiffTextView)?.lineDecorations ?? [:], syntax: currentSyntax, foldPlaceholders: rightFoldPlaceholders)
        }

        private func applyJSONSyntax(_ line: String, lineRange: NSRange, layoutManager: NSLayoutManager) {
            guard line.utf16.count <= 10_000 else { return }
            let tokens = JSONSyntaxHighlighter.tokens(line: line)
            guard !tokens.isEmpty else { return }

            // tokens 按扫描顺序 start 单调递增：共享映射单次游标构建字符
            // 偏移 → UTF-16 的换算表，逐 token 查表，避免每个 token 重复
            // O(start) 的前缀换算（长单行 JSON 高亮原为 O(n²)）。
            let utf16Ranges = IndexSyntaxUTF16RangeMap(line: line)

            for token in tokens {
                guard let range = utf16Ranges.range(for: token, in: lineRange) else {
                    continue
                }

                layoutManager.addTemporaryAttribute(
                    .foregroundColor,
                    value: nsColor(for: token.kind),
                    forCharacterRange: range
                )
            }
        }

        private func nsColor(for kind: IndexSyntaxToken.Kind) -> NSColor {
            switch kind {
            case .key:
                return IndexDiffNSPalette.syntaxKey
            case .string:
                return IndexDiffNSPalette.syntaxString
            case .number:
                return IndexDiffNSPalette.syntaxNumber
            case .literal:
                return IndexDiffNSPalette.syntaxBool
            case .punctuation:
                return IndexDiffNSPalette.syntaxPunctuation
            // JSON 扫描只产出上面五种 token；attribute/comment 仅为穷尽共享 Kind。
            case .attribute, .comment:
                return IndexDiffNSPalette.syntaxPunctuation
            }
        }

    }
}
