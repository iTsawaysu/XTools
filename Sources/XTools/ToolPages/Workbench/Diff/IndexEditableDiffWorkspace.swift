import AppKit
import SwiftUI
import XToolsCore

struct IndexEditableDiffWorkspace: View {
    let leftPlaceholder: String
    let rightPlaceholder: String
    var leftDisplayText: String?
    var rightDisplayText: String?
    @Binding var left: String
    @Binding var right: String
    let rows: [DiffAlignedRow]
    var syntax: IndexDiffSyntax = .plain
    var error: String?
    var warning: String?
    var onClear: (() -> Void)? = nil
    var clearDisabled = false

    private var diagnosticText: String? {
        if let error, !error.isEmpty {
            return error
        }
        if let warning, !warning.isEmpty {
            return warning
        }
        return nil
    }

    private var diagnosticTone: ToolFeedbackTone {
        if let error, !error.isEmpty {
            return .error
        }
        return .warning
    }

    var body: some View {
        IndexPanel("对比") {
            IndexEditableDiffMergeView(
                left: $left,
                right: $right,
                leftPlaceholder: leftPlaceholder,
                rightPlaceholder: rightPlaceholder,
                leftDisplayText: leftDisplayText,
                rightDisplayText: rightDisplayText,
                rows: rows,
                syntax: syntax
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .indexWorkspaceDiagnostic(diagnosticText, tone: diagnosticTone)
        } accessory: {
            if let onClear {
                IndexClearButton(
                    isDisabled: clearDisabled,
                    title: "清空对比",
                    showsIcon: false,
                    framed: true,
                    action: onClear
                )
            }
        }
        .contentInsets(EdgeInsets(
            top: 0,
            leading: ToolMetrics.Spacing.xs,
            bottom: ToolMetrics.Spacing.xs,
            trailing: ToolMetrics.Spacing.xs
        ))
        .terminal("DIFF")
        .verticallyFilling()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private enum IndexDiffEditorMetrics {
    static let textInset = NSSize(width: 34, height: 14)
    static let rulerWidth: CGFloat = 30
    static let paneGap: CGFloat = 8
    static let dividerThickness: CGFloat = paneGap
    static let stageInset: CGFloat = 8
    static let frameCornerRadius: CGFloat = 0
    static let frameBorderWidth: CGFloat = 0
    static let paneCornerRadius: CGFloat = 7
    static let trailingReadingGuard: CGFloat = 16
    static let placeholderTrailing: CGFloat = trailingReadingGuard
    static let placeholderTopInset: CGFloat = textInset.height + 1
    static let lineNumberLeadingPadding: CGFloat = 3
    static let lineNumberTrailingPadding: CGFloat = 3
    static let gutterAccentWidth: CGFloat = 2
    static let gutterAccentLeadingPadding: CGFloat = 4
}

struct IndexEditableDiffMergeView: NSViewRepresentable {
    @Binding var left: String
    @Binding var right: String
    let leftPlaceholder: String
    let rightPlaceholder: String
    let leftDisplayText: String?
    let rightDisplayText: String?
    let rows: [DiffAlignedRow]
    let syntax: IndexDiffSyntax

    func makeCoordinator() -> Coordinator {
        Coordinator(left: $left, right: $right)
    }

    func makeNSView(context: Context) -> NSView {
        let hostView = IndexEditableDiffScrollHostView()
        let splitView = IndexEditableDiffSplitView()
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.delegate = context.coordinator
        hostView.splitView = splitView
        context.coordinator.hostView = hostView
        context.coordinator.outerScrollView = hostView.outerScrollView
        hostView.onLayout = { [weak coordinator = context.coordinator] in
            coordinator?.refreshEditorLayout()
        }
        let leftEditor = context.coordinator.makeEditor(side: .left, placeholder: leftPlaceholder)
        let rightEditor = context.coordinator.makeEditor(side: .right, placeholder: rightPlaceholder)

        splitView.addArrangedSubview(leftEditor)
        splitView.addArrangedSubview(rightEditor)
        splitView.setHoldingPriority(.defaultLow, forSubviewAt: 0)
        splitView.setHoldingPriority(.defaultLow, forSubviewAt: 1)
        leftEditor.widthAnchor.constraint(greaterThanOrEqualToConstant: 260).isActive = true
        rightEditor.widthAnchor.constraint(greaterThanOrEqualToConstant: 260).isActive = true

        context.coordinator.update(
            left: leftDisplayText ?? left,
            right: rightDisplayText ?? right,
            rows: rows,
            syntax: syntax
        )
        DispatchQueue.main.async {
            context.coordinator.applyStoredDividerRatio(in: splitView)
        }
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
        let splitView = hostView.splitView
        context.coordinator.applyStoredDividerRatio(in: splitView)
        context.coordinator.update(
            left: leftDisplayText ?? left,
            right: rightDisplayText ?? right,
            rows: rows,
            syntax: syntax
        )
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate, NSSplitViewDelegate {
        enum Side {
            case left
            case right
        }

        var left: Binding<String>
        var right: Binding<String>

        private weak var leftTextView: NSTextView?
        private weak var rightTextView: NSTextView?
        private weak var leftScrollView: NSScrollView?
        private weak var rightScrollView: NSScrollView?
        fileprivate weak var hostView: IndexEditableDiffScrollHostView?
        weak var outerScrollView: NSScrollView?
        private weak var leftPlaceholderLabel: NSTextField?
        private weak var rightPlaceholderLabel: NSTextField?
        private weak var leftLineNumberView: IndexDiffLineNumberOverlayView?
        private weak var rightLineNumberView: IndexDiffLineNumberOverlayView?
        private var isApplyingProgrammaticText = false
        private var isApplyingDividerRatio = false
        private let storedDividerRatio: CGFloat = 0.5
        private var currentRows: [DiffAlignedRow] = []
        private var currentSyntax: IndexDiffSyntax = .plain
        private var latestLeftDisplayText = ""
        private var latestRightDisplayText = ""

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

        func makeEditor(side: Side, placeholder: String) -> NSView {
            let textView = IndexDiffTextView(frame: .zero)
            textView.onCompositionChange = { [weak self] _ in
                self?.refreshPlaceholders()
            }
            configure(textView)

            let scrollView = IndexDiffEditorScrollView(frame: .zero)
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

            // Set the delegate only after the side references are wired, so the
            // first `undoManager(for:)` query can resolve this view to its own
            // side's private manager (never fall through to the wrong side).
            textView.delegate = self

            return container
        }

        func splitViewDidResizeSubviews(_ notification: Notification) {
            guard let splitView = notification.object as? NSSplitView else {
                return
            }

            if isApplyingDividerRatio {
                return
            }

            applyStoredDividerRatio(in: splitView)
        }

        func splitView(
            _ splitView: NSSplitView,
            constrainSplitPosition proposedPosition: CGFloat,
            ofSubviewAt dividerIndex: Int
        ) -> CGFloat {
            fixedDividerPosition(in: splitView) ?? proposedPosition
        }

        func applyStoredDividerRatio(in splitView: NSSplitView) {
            guard let desiredPosition = fixedDividerPosition(in: splitView) else { return }
            let currentPosition = splitView.arrangedSubviews[0].frame.width
            guard abs(currentPosition - desiredPosition) > 0.5 else {
                return
            }

            isApplyingDividerRatio = true
            splitView.setPosition(desiredPosition, ofDividerAt: 0)
            isApplyingDividerRatio = false
        }

        private func fixedDividerPosition(in splitView: NSSplitView) -> CGFloat? {
            guard splitView.arrangedSubviews.count == 2,
                  splitView.bounds.width > 0 else {
                return nil
            }

            let availableWidth = max(0, splitView.bounds.width - splitView.dividerThickness)
            guard availableWidth > 0 else {
                return nil
            }

            let minimumPaneWidth: CGFloat = 260
            let effectiveMinimum = min(minimumPaneWidth, availableWidth / 2)
            let minimumPosition = effectiveMinimum
            let maximumPosition = max(minimumPosition, availableWidth - effectiveMinimum)
            return min(max(availableWidth * storedDividerRatio, minimumPosition), maximumPosition)
        }

        func update(left: String, right: String, rows: [DiffAlignedRow], syntax: IndexDiffSyntax) {
            currentRows = rows
            currentSyntax = syntax
            latestLeftDisplayText = left
            latestRightDisplayText = right
            setText(left, source: self.left.wrappedValue, in: leftTextView)
            setText(right, source: self.right.wrappedValue, in: rightTextView)
            refreshEditorLayout()
            applyDecorations()
            refreshPlaceholders()
            refreshEditorLayout()
        }

        func textDidChange(_ notification: Notification) {
            guard !isApplyingProgrammaticText, let textView = notification.object as? NSTextView else {
                return
            }

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
            textView.font = .monospacedSystemFont(ofSize: 12.5, weight: .regular)
            textView.textColor = IndexDiffNSPalette.textPrimary
            textView.insertionPointColor = IndexDiffNSPalette.textPrimary
            textView.drawsBackground = false
            textView.isEditable = true
            textView.isSelectable = true
            AppKitTextEditingConfiguration.configurePlainTextEditor(textView)
            textView.isRichText = false
            textView.importsGraphics = false
            textView.usesFindPanel = true
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

        private func setText(
            _ text: String,
            source: String,
            in textView: NSTextView?,
            allowActiveEditorOverride: Bool = false
        ) {
            guard let textView, textView.string != text, !textView.hasMarkedText() else {
                return
            }

            if !allowActiveEditorOverride, isActiveEditor(textView), textView.string == source {
                return
            }

            let selectedRanges = textView.selectedRanges
            isApplyingProgrammaticText = true
            defer { isApplyingProgrammaticText = false }
            textView.setStringWithoutUndoRegistration(text)

            let textLength = (text as NSString).length
            let validRanges = selectedRanges.filter { $0.rangeValue.upperBound <= textLength }
            textView.selectedRanges = validRanges.isEmpty
                ? [NSValue(range: NSRange(location: textLength, length: 0))]
                : validRanges
            refreshPlaceholders()
            refreshEditorLayout()
        }

        private func isActiveEditor(_ textView: NSTextView) -> Bool {
            textView.window?.firstResponder === textView
        }

        func refreshEditorLayout() {
            guard let hostView else {
                return
            }

            updateEditorGeometry(leftTextView, in: leftScrollView)
            updateEditorGeometry(rightTextView, in: rightScrollView)

            let contentHeight = max(measuredHeight(for: leftTextView), measuredHeight(for: rightTextView))
            hostView.contentHeight = contentHeight
            updateEditorGeometry(leftTextView, in: leftScrollView)
            updateEditorGeometry(rightTextView, in: rightScrollView)
            leftLineNumberView?.needsDisplay = true
            rightLineNumberView?.needsDisplay = true
        }

        private func updateEditorGeometry(_ textView: NSTextView?, in scrollView: NSScrollView?) {
            guard let textView, let scrollView else {
                return
            }

            let width = max(1, scrollView.contentSize.width)
            let height = max(hostView?.contentHeight ?? 0, scrollView.contentSize.height)
            (scrollView as? IndexDiffEditorScrollView)?.minimumDocumentHeight = height
            IndexTextKitGeometry.synchronizeTextGeometry(
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

        private func applyDecorations() {
            guard rowsMatchVisibleText() else {
                clearDecorations()
                return
            }

            let decorations = DiffEditorDecorations(rows: currentRows)
            (leftTextView as? IndexDiffTextView)?.lineDecorations = decorations.left
            (rightTextView as? IndexDiffTextView)?.lineDecorations = decorations.right
            applyDecorations(to: leftTextView, lineDecorations: decorations.left, syntax: currentSyntax)
            applyDecorations(to: rightTextView, lineDecorations: decorations.right, syntax: currentSyntax)
            leftLineNumberView?.lineStatuses = decorations.left.mapValues(\.status)
            rightLineNumberView?.lineStatuses = decorations.right.mapValues(\.status)
        }

        private func clearDecorations() {
            (leftTextView as? IndexDiffTextView)?.lineDecorations = [:]
            (rightTextView as? IndexDiffTextView)?.lineDecorations = [:]
            clearTemporaryDecorations(in: leftTextView)
            clearTemporaryDecorations(in: rightTextView)
            leftLineNumberView?.lineStatuses = [:]
            rightLineNumberView?.lineStatuses = [:]
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
            syntax: IndexDiffSyntax
        ) {
            guard let textView,
                  let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer else {
                return
            }

            let text = textView.string
            let nsText = text as NSString
            layoutManager.ensureLayout(for: textContainer)
            clearTemporaryDecorations(in: textView)

            let lineRanges = IndexDiffSourceText.lineRanges(in: text)
            for (index, range) in lineRanges.enumerated() {
                let lineNumber = index + 1
                let line = nsText.substring(with: range)

                if syntax == .json {
                    applyJSONSyntax(line, lineRange: range, layoutManager: layoutManager)
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

        private func clearTemporaryDecorations(in textView: NSTextView?) {
            guard let textView,
                  let layoutManager = textView.layoutManager else {
                return
            }

            let fullRange = NSRange(location: 0, length: (textView.string as NSString).length)
            layoutManager.removeTemporaryAttribute(.foregroundColor, forCharacterRange: fullRange)
            layoutManager.removeTemporaryAttribute(.backgroundColor, forCharacterRange: fullRange)
            layoutManager.removeTemporaryAttribute(.underlineStyle, forCharacterRange: fullRange)
            layoutManager.removeTemporaryAttribute(.underlineColor, forCharacterRange: fullRange)
        }

        private func applyJSONSyntax(_ line: String, lineRange: NSRange, layoutManager: NSLayoutManager) {
            for token in JSONHighlighting.tokens(in: line) {
                guard let range = nsRange(for: token, in: line, lineRange: lineRange) else {
                    continue
                }

                layoutManager.addTemporaryAttribute(
                    .foregroundColor,
                    value: nsColor(for: token.kind),
                    forCharacterRange: range
                )
            }
        }

        private func nsRange(
            for token: JSONHighlightToken,
            in line: String,
            lineRange: NSRange
        ) -> NSRange? {
            guard token.length > 0,
                  let start = line.index(
                    line.startIndex,
                    offsetBy: token.start,
                    limitedBy: line.endIndex
                  ),
                  let end = line.index(
                    start,
                    offsetBy: token.length,
                    limitedBy: line.endIndex
                  ) else {
                return nil
            }

            let prefixLength = line[..<start].utf16.count
            let tokenLength = line[start..<end].utf16.count
            return NSRange(location: lineRange.location + prefixLength, length: tokenLength)
        }

        private func nsColor(for kind: JSONHighlightToken.Kind) -> NSColor {
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
            }
        }

    }
}

private final class IndexEditableDiffScrollHostView: NSView {
    let outerScrollView = NSScrollView(frame: .zero)
    let documentView = IndexDiffScrollDocumentView(frame: .zero)
    var onLayout: (() -> Void)?

    var splitView = IndexEditableDiffSplitView() {
        didSet {
            oldValue.removeFromSuperview()
            installSplitView()
        }
    }

    var contentHeight: CGFloat = 0 {
        didSet {
            guard abs(contentHeight - oldValue) > 0.5 else {
                return
            }

            needsLayout = true
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        outerScrollView.frame = bounds
        let viewportSize = outerScrollView.contentSize
        let stageInset = IndexDiffEditorMetrics.stageInset
        let height = max(viewportSize.height, contentHeight + stageInset * 2)
        documentView.frame = NSRect(origin: .zero, size: NSSize(width: viewportSize.width, height: height))
        splitView.frame = NSRect(
            x: stageInset,
            y: stageInset,
            width: max(0, documentView.bounds.width - stageInset * 2),
            height: max(0, documentView.bounds.height - stageInset * 2)
        )
        onLayout?()
    }

    private func configure() {
        wantsLayer = true
        layer?.masksToBounds = true
        updateLayer()

        outerScrollView.translatesAutoresizingMaskIntoConstraints = false
        outerScrollView.borderType = .noBorder
        outerScrollView.drawsBackground = false
        outerScrollView.contentView = IndexLeadingLockedClipView(frame: .zero)
        outerScrollView.hasVerticalScroller = true
        outerScrollView.hasHorizontalScroller = false
        outerScrollView.autohidesScrollers = true
        outerScrollView.horizontalScrollElasticity = .none
        outerScrollView.documentView = documentView

        addSubview(outerScrollView)
        installSplitView()

        NSLayoutConstraint.activate([
            outerScrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            outerScrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            outerScrollView.topAnchor.constraint(equalTo: topAnchor),
            outerScrollView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.cornerRadius = IndexDiffEditorMetrics.frameCornerRadius
        layer?.backgroundColor = IndexDiffNSPalette.panelBackground(for: effectiveAppearance).cgColor
        layer?.borderColor = NSColor.clear.cgColor
        layer?.borderWidth = IndexDiffEditorMetrics.frameBorderWidth
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateLayer()
    }

    private func installSplitView() {
        splitView.autoresizingMask = [.width, .height]
        documentView.addSubview(splitView)
    }
}

private final class IndexDiffScrollDocumentView: NSView {
    override var isFlipped: Bool { true }
}

private final class IndexDiffEditorScrollView: NSScrollView {
    weak var forwardingScrollView: NSScrollView?
    var trailingReadingGuard = IndexDiffEditorMetrics.trailingReadingGuard
    var minimumDocumentHeight: CGFloat = 0

    override func layout() {
        super.layout()
        synchronizeTextGeometry()
    }

    override func scrollWheel(with event: NSEvent) {
        forwardingScrollView?.scrollWheel(with: event)
    }

    private func synchronizeTextGeometry() {
        guard let textView = documentView as? NSTextView else {
            return
        }

        IndexTextKitGeometry.synchronizeTextGeometry(
            for: textView,
            visibleWidth: contentSize.width,
            minimumHeight: max(contentSize.height, minimumDocumentHeight),
            trailingReadingGuard: trailingReadingGuard
        )
    }
}

private final class IndexEditableDiffSplitView: NSSplitView {
    override var dividerThickness: CGFloat {
        IndexDiffEditorMetrics.dividerThickness
    }

    override func drawDivider(in rect: NSRect) {
        IndexDiffNSPalette.panelBackground(for: effectiveAppearance).setFill()
        NSBezierPath(rect: rect).fill()
    }

    override func resetCursorRects() {
        addCursorRect(dividerHitRect, cursor: .arrow)
    }

    override func cursorUpdate(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if dividerHitRect.contains(point) {
            NSCursor.arrow.set()
            return
        }

        super.cursorUpdate(with: event)
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let hitsDivider = dividerHitRect.contains(point)

        if hitsDivider {
            return
        }

        super.mouseDown(with: event)
    }

    private var dividerHitRect: NSRect {
        guard arrangedSubviews.count > 1 else {
            return .zero
        }

        let dividerX = arrangedSubviews[0].frame.maxX
        return NSRect(
            x: dividerX - 4,
            y: bounds.minY,
            width: dividerThickness + 8,
            height: bounds.height
        )
    }
}

private final class IndexDiffEditorPaneView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = true
        updateLayer()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.cornerRadius = IndexDiffEditorMetrics.paneCornerRadius
        layer?.backgroundColor = IndexDiffNSPalette.editorBackground(for: effectiveAppearance).cgColor
        layer?.borderColor = NSColor.clear.cgColor
        layer?.borderWidth = 0
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateLayer()
    }
}

private final class IndexDiffTextView: NSTextView, IndexAsymmetricTextContainerSurface {
    var leadingTextContainerInset: CGFloat {
        IndexDiffEditorMetrics.textInset.width
    }

    private let caretWidth: CGFloat = 2

    var lineDecorations: [Int: DiffLineDecoration] = [:] {
        didSet {
            needsDisplay = true
        }
    }

    var onCompositionChange: ((Bool) -> Void)?

    override func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        super.setMarkedText(string, selectedRange: selectedRange, replacementRange: replacementRange)
        onCompositionChange?(hasMarkedText())
    }

    override func unmarkText() {
        super.unmarkText()
        onCompositionChange?(false)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
    }

    override func drawInsertionPoint(in rect: NSRect, color: NSColor, turnedOn flag: Bool) {
        var widened = rect
        widened.size.width = caretWidth
        super.drawInsertionPoint(in: widened, color: color, turnedOn: flag)
    }

    override func setNeedsDisplay(_ invalidRect: NSRect, avoidAdditionalLayout flag: Bool) {
        var widened = invalidRect
        widened.size.width += caretWidth
        super.setNeedsDisplay(widened, avoidAdditionalLayout: flag)
    }
}

private extension DiffLineStatus {
    var rulerColor: NSColor {
        switch self {
        case .unchanged:
            return IndexDiffNSPalette.textTertiary
        case .added, .changedRight:
            return IndexDiffNSPalette.success
        case .removed, .changedLeft:
            return IndexDiffNSPalette.error
        }
    }
}

private final class IndexDiffLineNumberOverlayView: NSView {
    weak var scrollView: NSScrollView?
    weak var textView: NSTextView?
    var lineStatuses: [Int: DiffLineStatus] = [:] {
        didSet {
            needsDisplay = true
        }
    }

    override var isFlipped: Bool { true }

    init(scrollView: NSScrollView, textView: NSTextView) {
        self.scrollView = scrollView
        self.textView = textView
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let textView,
              let scrollView = scrollView else {
            return
        }

        let visibleRect = scrollView.contentView.bounds
        let lineRects = IndexDiffTextLayoutGeometry.lineBlockRects(for: textView)

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .right
        let labelX = IndexDiffEditorMetrics.lineNumberLeadingPadding
        let labelWidth = max(
            1,
            bounds.width - IndexDiffEditorMetrics.lineNumberLeadingPadding - IndexDiffEditorMetrics.lineNumberTrailingPadding
        )
        let labelHeight = IndexDiffTextLayoutGeometry.defaultLineHeight(for: textView)

        for lineNumber in lineRects.keys.sorted() {
            guard let lineRect = lineRects[lineNumber] else { continue }
            let status = lineStatuses[lineNumber] ?? .unchanged
            let y = lineRect.minY - visibleRect.minY
            let height = max(1, lineRect.height)

            if status != .unchanged, NSRect(x: 0, y: y, width: bounds.width, height: height).intersects(bounds) {
                status.rulerColor.setFill()
                NSBezierPath(
                    roundedRect: gutterAccentRect(y: y, height: height),
                    xRadius: 1,
                    yRadius: 1
                ).fill()
            }
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedSystemFont(ofSize: 10, weight: .regular),
                .foregroundColor: lineNumberColor(for: status),
                .paragraphStyle: paragraphStyle
            ]
            let lineText = "\(lineNumber)" as NSString
            lineText.draw(
                in: NSRect(x: labelX, y: y, width: labelWidth, height: min(height, labelHeight)),
                withAttributes: attributes
            )

        }
    }

    private func gutterAccentRect(y: CGFloat, height: CGFloat) -> NSRect {
        NSRect(
            x: IndexDiffEditorMetrics.gutterAccentLeadingPadding,
            y: y + 3,
            width: IndexDiffEditorMetrics.gutterAccentWidth,
            height: max(8, height - 6)
        )
    }

    private func lineNumberColor(for status: DiffLineStatus) -> NSColor {
        switch status {
        case .unchanged:
            return IndexDiffNSPalette.lineNumber
        case .added, .removed, .changedLeft, .changedRight:
            return status.rulerColor
        }
    }
}

private enum IndexDiffNSPalette {
    // 语义色一律取自 ToolTheme 单一真相源;只有 diff 专属度量(行号)保留本地定义。
    static let textPrimary = NSColor(ToolTheme.textPrimary)
    static let lineNumber = dynamicColor(light: 0x7A736A, dark: 0x777068, alpha: 0.62, darkAlpha: 0.66)
    static let textTertiary = NSColor(ToolTheme.textTertiary)
    static let success = NSColor(ToolTheme.success)
    static let error = NSColor(ToolTheme.error)
    static let successFragment = NSColor(ToolTheme.successFragment)
    static let errorFragment = NSColor(ToolTheme.errorFragment)
    static let syntaxKey = NSColor(ToolTheme.synKey)
    static let syntaxString = NSColor(ToolTheme.synString)
    static let syntaxNumber = NSColor(ToolTheme.synNumber)
    static let syntaxBool = NSColor(ToolTheme.synBool)
    static let syntaxPunctuation = NSColor(ToolTheme.synPunctuation)

    static func editorBackground(for appearance: NSAppearance) -> NSColor {
        resolvedColor(ToolTheme.editorBackground, for: appearance)
    }

    static func panelBackground(for appearance: NSAppearance) -> NSColor {
        resolvedColor(ToolTheme.panelBackground, for: appearance)
    }

    private static func resolvedColor(_ color: Color, for appearance: NSAppearance) -> NSColor {
        var resolved = NSColor.clear
        appearance.performAsCurrentDrawingAppearance {
            let sharedColor = NSColor(color)
            resolved = sharedColor.usingColorSpace(.deviceRGB) ?? sharedColor
        }
        return resolved
    }

    private static func dynamicColor(
        light: UInt32,
        dark: UInt32,
        alpha: CGFloat = 1,
        darkAlpha: CGFloat? = nil
    ) -> NSColor {
        NSColor(name: nil) { appearance in
            let color = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            let resolvedAlpha = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? (darkAlpha ?? alpha) : alpha
            return NSColor.indexDiffHex(color, alpha: resolvedAlpha)
        }
    }
}

private extension NSColor {
    static func indexDiffHex(_ hex: UInt32, alpha: CGFloat = 1) -> NSColor {
        NSColor(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}
