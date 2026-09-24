import AppKit
import SwiftUI
import XToolsCore

/// A toolbar/keyboard request to jump to the previous or next difference.
struct DiffDifferenceNavigationRequest: Equatable {
    let id: Int
    let forward: Bool
}

struct DiffDifferenceNavigationProgress: Equatable, Sendable {
    let current: Int?
    let total: Int
}

struct IndexEditableDiffWorkspace<LeadingControl: View>: View {
    var inputTitle: String = "原始文本"
    var outputTitle: String = "对比文本"
    let leftPlaceholder: String
    let rightPlaceholder: String
    var leftDisplayText: String?
    var rightDisplayText: String?
    @Binding var left: String
    @Binding var right: String
    let rows: [DiffAlignedRow]
    var resultState: DiffExecutionResultState = .current
    var syntax: IndexDiffSyntax = .plain
    /// Enables the view-mode fold projection over unchanged regions. The
    /// binding keeps full canonical text; collapsed regions render as
    /// click-to-expand placeholder rows and panes turn read-only while any
    /// region stays collapsed.
    var foldUnchanged: Bool = false
    var error: String?
    var warning: String?
    var onClear: (() -> Void)? = nil
    var clearDisabled = false
    var leadingControl: () -> LeadingControl

    @State private var navigationRequest: DiffDifferenceNavigationRequest?
    @State private var navigationProgress = DiffDifferenceNavigationProgress(current: nil, total: 0)

    init(
        inputTitle: String = "原始文本",
        outputTitle: String = "对比文本",
        leftPlaceholder: String,
        rightPlaceholder: String,
        leftDisplayText: String? = nil,
        rightDisplayText: String? = nil,
        left: Binding<String>,
        right: Binding<String>,
        rows: [DiffAlignedRow],
        resultState: DiffExecutionResultState = .current,
        syntax: IndexDiffSyntax = .plain,
        foldUnchanged: Bool = false,
        error: String? = nil,
        warning: String? = nil,
        onClear: (() -> Void)? = nil,
        clearDisabled: Bool = false,
        @ViewBuilder leadingControl: @escaping () -> LeadingControl
    ) {
        self.inputTitle = inputTitle
        self.outputTitle = outputTitle
        self.leftPlaceholder = leftPlaceholder
        self.rightPlaceholder = rightPlaceholder
        self.leftDisplayText = leftDisplayText
        self.rightDisplayText = rightDisplayText
        self._left = left
        self._right = right
        self.rows = rows
        self.resultState = resultState
        self.syntax = syntax
        self.foldUnchanged = foldUnchanged
        self.error = error
        self.warning = warning
        self.onClear = onClear
        self.clearDisabled = clearDisabled
        self.leadingControl = leadingControl
    }

    /// 一次共享的全文裁剪：body 里诊断文案、语气与差异导航都会读取这两个
    /// 结论，合并计算避免对大文本重复全量 trim。
    private var diffSummary: (isIdentical: Bool, differenceBlockCount: Int) {
        let leftNonEmpty = !left.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let rightNonEmpty = !right.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        var identical = false
        if resultState == .current,
           error == nil,
           leftNonEmpty,
           rightNonEmpty {
            if syntax == .json && rows.isEmpty {
                identical = true
            } else if !rows.isEmpty {
                identical = rows.allSatisfy { !$0.kind.isDifference }
            }
        }

        let inputsPresent = resultState == .current
            && error == nil
            && (leftNonEmpty || rightNonEmpty)
        let blocks = inputsPresent ? Self.differenceBlockCount(in: rows) : 0

        return (identical, blocks)
    }

    private var canNavigateDifferences: Bool {
        Self.navigationEnabled(resultState: resultState, diffCount: diffSummary.differenceBlockCount)
    }

    static func navigationEnabled(
        resultState: DiffExecutionResultState,
        diffCount: Int
    ) -> Bool {
        resultState == .current && diffCount > 0
    }

    /// A consecutive replacement, insertion, or removal is one navigation
    /// destination. Inline segments remain a rendering detail of that block.
    static func differenceBlockCount(in rows: [DiffAlignedRow]) -> Int {
        var previousWasDifference = false
        var count = 0
        for row in rows {
            if row.kind.isDifference, !previousWasDifference {
                count += 1
            }
            previousWasDifference = row.kind.isDifference
        }
        return count
    }

    private var diagnosticText: String? {
        // Running/stale notes only make sense once there is something to
        // compare; toggling options on empty panes must stay visually quiet.
        let hasInput = !left.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !right.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if resultState == .running {
            return hasInput ? "正在对比…" : nil
        }
        if resultState == .stale {
            return hasInput ? "正在更新对比结果…" : nil
        }
        guard resultState == .current else {
            return nil
        }
        if let error, !error.isEmpty {
            return error
        }
        if let warning, !warning.isEmpty {
            return warning
        }
        let summary = diffSummary
        if summary.isIdentical {
            return syntax == .json ? "两段 JSON 完全一致" : "两段文本完全一致"
        }
        if summary.differenceBlockCount > 0 {
            return "共 \(summary.differenceBlockCount) 个差异块"
        }
        return nil
    }

    private var diagnosticTone: ToolFeedbackTone {
        guard resultState == .current else {
            return .info
        }
        if let error, !error.isEmpty {
            return .error
        }
        if let warning, !warning.isEmpty {
            return .warning
        }
        if diffSummary.isIdentical {
            return .success
        }
        return .info
    }

    private var showsErrorState: Bool {
        diagnosticText != nil && diagnosticTone == .error
    }

    private var hasDiagnostic: Bool {
        diagnosticText != nil && (diagnosticTone == .error || diagnosticTone == .warning)
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            if hasDiagnostic {
                IndexDiagnosticBanner(
                    diagnostic: nil,
                    message: diagnosticText!,
                    tone: diagnosticTone
                )
                .transition(.asymmetric(
                    insertion: .move(edge: .top).combined(with: .opacity),
                    removal: .opacity.combined(with: .move(edge: .top))
                ))
            }
            IndexEditableDiffMergeView(
                left: $left,
                right: $right,
                leftPlaceholder: leftPlaceholder,
                rightPlaceholder: rightPlaceholder,
                leftAccessibilityLabel: inputTitle,
                rightAccessibilityLabel: outputTitle,
                leftDisplayText: resultState == .current ? leftDisplayText : nil,
                rightDisplayText: resultState == .current ? rightDisplayText : nil,
                rows: resultState == .current ? rows : [],
                syntax: syntax,
                foldUnchanged: foldUnchanged,
                differenceNavigationRequest: navigationRequest,
                onDifferenceNavigationChange: { progress in
                    // This callback can be invoked while AppKit is handling a
                    // representable update initiated by a toolbar action.
                    // Publish after that update has completed so SwiftUI does
                    // not discard the current/total indicator as a state
                    // mutation during view reconciliation.
                    DispatchQueue.main.async {
                        if navigationProgress != progress {
                            navigationProgress = progress
                        }
                    }
                }
            )
            .padding(.horizontal, ToolMetrics.Spacing.md)
            .padding(.bottom, ToolMetrics.Spacing.md)
            .padding(.top, ToolMetrics.Spacing.sm)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.84), value: hasDiagnostic)
        .clipShape(RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.panel, style: .continuous))
        .background(
            ToolTheme.panelBackground,
            in: RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.panel, style: .continuous)
        )
        .overlay {
            if showsErrorState {
                RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.panel, style: .continuous)
                    .strokeBorder(ToolTheme.error.opacity(0.55), lineWidth: 1)
            }
        }
        .toolShadow(ToolTheme.Shadow.panel)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var toolbar: some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                IndexBadge("STDIN", tone: .accent, isCapsule: true)
                    .fixedSize(horizontal: true, vertical: false)
                    .layoutPriority(10)
                Text(inputTitle)
                    .font(ToolTypography.panelTitle)
                    .foregroundStyle(ToolTheme.textSecondary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .layoutPriority(9)

                leadingControl()

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 6) {
                IndexBadge("STDOUT", tone: .accent, isCapsule: true)
                    .fixedSize(horizontal: true, vertical: false)
                    .layoutPriority(10)
                Text(outputTitle)
                    .font(ToolTypography.panelTitle)
                    .foregroundStyle(ToolTheme.textSecondary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .layoutPriority(9)

                inlineDiagnostic

                Spacer(minLength: 0)

                HStack(spacing: 6) {
                    if let current = navigationProgress.current,
                       navigationProgress.total == diffSummary.differenceBlockCount {
                        IndexBadge(
                            "\(current) / \(navigationProgress.total)",
                            tone: .accent,
                            isCapsule: true
                        )
                        .fixedSize(horizontal: true, vertical: false)
                        .help("当前差异块 \(current) / \(navigationProgress.total)")
                        .accessibilityLabel("当前差异块 \(current)，共 \(navigationProgress.total) 个")
                    }
                    IndexIconButton(
                        systemImage: "chevron.up",
                        help: "上一处差异（⌥⌘↑）"
                    ) {
                        navigateDifference(false)
                    }
                    .fixedSize(horizontal: true, vertical: false)
                    .disabled(!canNavigateDifferences)
                    IndexIconButton(
                        systemImage: "chevron.down",
                        help: "下一处差异（⌥⌘↓）"
                    ) {
                        navigateDifference(true)
                    }
                    .fixedSize(horizontal: true, vertical: false)
                    .disabled(!canNavigateDifferences)
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
                .layoutPriority(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: 44)
        .padding(.horizontal, 12)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(ToolTheme.border)
                .frame(height: 0.5)
        }
        .accessibilityElement(children: .contain)
    }

    private func navigateDifference(_ forward: Bool) {
        guard canNavigateDifferences else { return }
        navigationRequest = DiffDifferenceNavigationRequest(
            id: (navigationRequest?.id ?? 0) + 1,
            forward: forward
        )
    }

    @ViewBuilder
    private var inlineDiagnostic: some View {
        if let diagnosticText, !hasDiagnostic {
            HStack(spacing: 4) {
                Image(systemName: diagnosticTone.systemImage)
                    .font(.system(size: ToolMetrics.IconSize.small, weight: .semibold))
                Text(diagnosticText)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .font(ToolTypography.caption)
            .foregroundStyle(diagnosticTone.tint)
            .frame(maxWidth: 320, alignment: .leading)
            .layoutPriority(1)
            .help(diagnosticText)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(diagnosticTone.accessibilityPrefix)：\(diagnosticText)")
        }
    }
}

extension IndexEditableDiffWorkspace where LeadingControl == EmptyView {
    init(
        inputTitle: String = "原始文本",
        outputTitle: String = "对比文本",
        leftPlaceholder: String,
        rightPlaceholder: String,
        leftDisplayText: String? = nil,
        rightDisplayText: String? = nil,
        left: Binding<String>,
        right: Binding<String>,
        rows: [DiffAlignedRow],
        resultState: DiffExecutionResultState = .current,
        syntax: IndexDiffSyntax = .plain,
        foldUnchanged: Bool = false,
        error: String? = nil,
        warning: String? = nil,
        onClear: (() -> Void)? = nil,
        clearDisabled: Bool = false
    ) {
        self.init(
            inputTitle: inputTitle,
            outputTitle: outputTitle,
            leftPlaceholder: leftPlaceholder,
            rightPlaceholder: rightPlaceholder,
            leftDisplayText: leftDisplayText,
            rightDisplayText: rightDisplayText,
            left: left,
            right: right,
            rows: rows,
            resultState: resultState,
            syntax: syntax,
            foldUnchanged: foldUnchanged,
            error: error,
            warning: warning,
            onClear: onClear,
            clearDisabled: clearDisabled,
            leadingControl: { EmptyView() }
        )
    }
}

private enum IndexDiffEditorMetrics {
    static let rulerWidth: CGFloat = 44
    static let textInset = NSSize(width: rulerWidth + 13, height: 14)
    static let paneGap: CGFloat = 8
    static let dividerThickness: CGFloat = paneGap
    static let stageInset: CGFloat = 0
    static let frameCornerRadius: CGFloat = 0
    static let frameBorderWidth: CGFloat = 0
    static let paneCornerRadius: CGFloat = ToolMetrics.CornerRadius.field
    static let trailingReadingGuard: CGFloat = 16
    static let placeholderTrailing: CGFloat = trailingReadingGuard
    static let placeholderTopInset: CGFloat = textInset.height + 1
    static let lineNumberLeadingPadding: CGFloat = 6
    static let lineNumberTrailingPadding: CGFloat = 10
    static let gutterAccentWidth: CGFloat = 2
    static let gutterAccentLeadingPadding: CGFloat = 4
}

struct IndexEditableDiffMergeView: NSViewRepresentable {
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
    var onDifferenceNavigationChange: ((DiffDifferenceNavigationProgress) -> Void)? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(left: $left, right: $right)
    }

    func makeNSView(context: Context) -> NSView {
        let hostView = IndexEditableDiffScrollHostView()
        hostView.onNavigateDifference = { [weak coordinator = context.coordinator] forward in
            coordinator?.navigateDifference(forward: forward)
        }
        let splitView = IndexEditableDiffSplitView()
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.delegate = context.coordinator
        hostView.splitView = splitView
        context.coordinator.hostView = hostView
        context.coordinator.outerScrollView = hostView.outerScrollView
        context.coordinator.onDifferenceNavigationChange = onDifferenceNavigationChange
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
            syntax: syntax,
            foldUnchanged: foldUnchanged
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
        context.coordinator.onDifferenceNavigationChange = onDifferenceNavigationChange
        context.coordinator.updateAccessibilityLabels(
            left: leftAccessibilityLabel,
            right: rightAccessibilityLabel
        )
        let splitView = hostView.splitView
        context.coordinator.applyStoredDividerRatio(in: splitView)
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
    final class Coordinator: NSObject, NSTextViewDelegate, NSSplitViewDelegate {
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

        /// Consecutive changed rows form one navigation unit. Keeping every
        /// visual line for each side lets a deletion move to the side that
        /// actually has source text instead of selecting an unrelated line
        /// with the same display number in the other editor.
        private struct DifferenceHunk: Equatable {
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
            textView.onCompositionChange = { [weak self] _ in
                self?.refreshPlaceholders()
            }
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
            refreshEditorLayout()
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
        }

        private func updateDifferenceHunks(resetNavigation: Bool) {
            var planned: [DifferenceHunk] = []
            var active: DifferenceHunk?

            func flushActive() {
                guard let current = active else { return }
                planned.append(current)
                active = nil
            }

            for row in currentRows {
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
            let lineRanges = IndexDiffSourceText.lineRanges(in: textView.string)
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
            (leftTextView as? IndexDiffTextView)?.lineDecorations = [:]
            (rightTextView as? IndexDiffTextView)?.lineDecorations = [:]
            clearTemporaryDecorations(in: leftTextView)
            clearTemporaryDecorations(in: rightTextView)
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
            guard line.utf16.count <= 10_000 else { return }
            let tokens = JSONHighlighting.tokens(in: line)
            guard !tokens.isEmpty else { return }

            // tokens 按扫描顺序 start 单调递增：单次游标同时累积字符偏移与
            // UTF-16 偏移，避免每个 token 重复 O(start) 的前缀换算（长单行
            // JSON 高亮原为 O(n²)）。
            var characterCursor = line.startIndex
            var characterOffset = 0
            var utf16Prefix = 0

            func advance(to target: Int) -> Bool {
                while characterOffset < target {
                    guard characterCursor < line.endIndex else { return false }
                    utf16Prefix += line[characterCursor].utf16.count
                    characterCursor = line.index(after: characterCursor)
                    characterOffset += 1
                }
                return characterOffset == target
            }

            for token in tokens {
                guard token.length > 0, advance(to: token.start) else {
                    continue
                }

                var tokenUTF16Length = 0
                var endCursor = characterCursor
                var consumed = 0
                while consumed < token.length, endCursor < line.endIndex {
                    tokenUTF16Length += line[endCursor].utf16.count
                    endCursor = line.index(after: endCursor)
                    consumed += 1
                }
                guard consumed == token.length, tokenUTF16Length > 0 else {
                    continue
                }

                layoutManager.addTemporaryAttribute(
                    .foregroundColor,
                    value: nsColor(for: token.kind),
                    forCharacterRange: NSRange(location: lineRange.location + utf16Prefix, length: tokenUTF16Length)
                )
            }
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
    var onNavigateDifference: ((Bool) -> Void)?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.type == .keyDown,
           event.modifierFlags.intersection(.deviceIndependentFlagsMask) == [.option, .command] {
            if event.charactersIgnoringModifiers == String(NSDownArrowFunctionKey) {
                onNavigateDifference?(true)
                return true
            }
            if event.charactersIgnoringModifiers == String(NSUpArrowFunctionKey) {
                onNavigateDifference?(false)
                return true
            }
        }
        return super.performKeyEquivalent(with: event)
    }

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
        layer?.backgroundColor = NSColor.clear.cgColor
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
    private var isSynchronizing = false

    override func tile() {
        super.tile()
        synchronizeGeometryIfNeeded()
    }

    override func layout() {
        super.layout()
        synchronizeTextGeometry()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        synchronizeGeometryIfNeeded()
    }

    private func synchronizeGeometryIfNeeded() {
        guard !isSynchronizing else { return }
        isSynchronizing = true
        defer { isSynchronizing = false }
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

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        if let tv = documentView as? IndexDiffTextView, tv.onFileDrop != nil, IndexCaretTextView.hasDroppableFile(sender) {
            return .copy
        }
        return super.draggingEntered(sender)
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        if let tv = documentView as? IndexDiffTextView, tv.onFileDrop != nil, IndexCaretTextView.hasDroppableFile(sender) {
            return .copy
        }
        return super.draggingUpdated(sender)
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        if let tv = documentView as? IndexDiffTextView, let onFileDrop = tv.onFileDrop, let content = IndexCaretTextView.extractDroppedContent(sender) {
            onFileDrop(content)
            return true
        }
        return super.performDragOperation(sender)
    }
}

private final class IndexEditableDiffSplitView: NSSplitView {
    override var dividerThickness: CGFloat {
        IndexDiffEditorMetrics.dividerThickness
    }

    override func drawDivider(in rect: NSRect) {
        NSColor.clear.setFill()
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
        layer?.borderColor = NSColor(ToolTheme.border).cgColor
        layer?.borderWidth = 0.5
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
    var onFileDrop: ((String) -> Void)?

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        if onFileDrop != nil && IndexCaretTextView.hasDroppableFile(sender) {
            return .copy
        }
        return super.draggingEntered(sender)
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        if onFileDrop != nil && IndexCaretTextView.hasDroppableFile(sender) {
            return .copy
        }
        return super.draggingUpdated(sender)
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        if let onFileDrop, let content = IndexCaretTextView.extractDroppedContent(sender) {
            onFileDrop(content)
            return true
        }
        return super.performDragOperation(sender)
    }

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
    var customLineNumbers: [Int: Int?] = [:] {
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

        let hairline = NSRect(x: bounds.width - 0.5, y: 0, width: 0.5, height: bounds.height)
        NSColor(ToolTheme.border).setFill()
        NSBezierPath(rect: hairline).fill()

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

        let nsText = textView.string as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
            .foregroundColor: lineNumberColor(for: .unchanged),
            .paragraphStyle: paragraphStyle
        ]

        if nsText.length == 0 {
            let y = textView.textContainerOrigin.y - visibleRect.minY
            let label = "1" as NSString
            label.draw(
                in: NSRect(x: labelX, y: y + 3, width: labelWidth, height: min(bounds.height, labelHeight)),
                withAttributes: attributes
            )
            return
        }

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
            let lineAttributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
                .foregroundColor: lineNumberColor(for: status),
                .paragraphStyle: paragraphStyle
            ]
            let lineText: NSString?
            if let custom = customLineNumbers[lineNumber] {
                if let actual = custom {
                    lineText = "\(actual)" as NSString
                } else {
                    lineText = nil
                }
            } else {
                lineText = "\(lineNumber)" as NSString
            }

            guard let lineText else { continue }
            lineText.draw(
                in: NSRect(x: labelX, y: y, width: labelWidth, height: min(height, labelHeight)),
                withAttributes: lineAttributes
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
    // 语义色一律取自 ToolTheme 单一真相源
    static let textPrimary = NSColor(ToolTheme.textPrimary)
    static let lineNumber = NSColor(ToolTheme.textTertiary)
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
