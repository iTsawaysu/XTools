import AppKit
import SwiftUI
import XToolsCore

enum IndexDiffEditorMetrics {
    static let rulerWidth: CGFloat = 44
    static let textInset = NSSize(width: rulerWidth + 13, height: 14)
    /// 两块独立编辑器之间的固定负空间宽度（不是可拖动分隔线）。
    static let paneGap: CGFloat = 8
    static let paneCornerRadius: CGFloat = ToolMetrics.CornerRadius.field
    static let trailingReadingGuard: CGFloat = 16
    static let placeholderTrailing: CGFloat = trailingReadingGuard
    static let placeholderTopInset: CGFloat = textInset.height + 1
    static let lineNumberLeadingPadding: CGFloat = 6
    static let lineNumberTrailingPadding: CGFloat = 10
    static let gutterAccentWidth: CGFloat = 2
    static let gutterAccentLeadingPadding: CGFloat = 4
    static let gutterAccentVerticalInset: CGFloat = 3
    static let gutterAccentMinHeight: CGFloat = 8
}

final class IndexEditableDiffScrollHostView: NSView {
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

    var splitView = IndexEditableDiffPanePairView() {
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
        let height = max(viewportSize.height, contentHeight)
        documentView.frame = NSRect(origin: .zero, size: NSSize(width: viewportSize.width, height: height))
        splitView.frame = documentView.bounds
        onLayout?()
    }

    private func configure() {
        wantsLayer = true
        layer?.masksToBounds = true

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

    private func installSplitView() {
        splitView.autoresizingMask = [.width, .height]
        documentView.addSubview(splitView)
    }
}

final class IndexDiffScrollDocumentView: NSView {
    override var isFlipped: Bool { true }
}

final class IndexDiffEditorScrollView: IndexTextViewportScrollView {
    weak var forwardingScrollView: NSScrollView?
    var trailingReadingGuard = IndexDiffEditorMetrics.trailingReadingGuard
    var minimumDocumentHeight: CGFloat = 0

    /// Diff text geometry must run from the layout callback even while a
    /// gated synchronization is already in flight.
    override func layoutSynchronizeStep() {
        synchronizeTextGeometry()
    }

    override func synchronizeDocumentGeometry() {
        synchronizeTextGeometry()
    }

    override func scrollWheel(with event: NSEvent) {
        forwardingScrollView?.scrollWheel(with: event)
    }

    private func synchronizeTextGeometry() {
        guard let textView = documentView as? NSTextView else {
            return
        }

        IndexDiffTextLayoutGeometry.synchronizeTextGeometry(
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
        if let tv = documentView as? IndexDiffTextView, tv.onFileDrop != nil,
           let url = IndexCaretTextView.droppedFileURL(sender) {
            tv.loadDroppedFile(from: url)
            return true
        }
        return super.performDragOperation(sender)
    }
}

/// 等比例双栏容器：左右编辑器宽度恒相等，中缝是 paneGap 宽的固定负空间。
/// 参考布局是稳定对比分栏——没有可拖动分隔线，因此不吞点击、不注册
/// 调整光标，也不需要夹持分栏位置。
final class IndexEditableDiffPanePairView: NSView {
    func installPanes(_ left: NSView, _ right: NSView) {
        addSubview(left)
        addSubview(right)
        NSLayoutConstraint.activate([
            left.leadingAnchor.constraint(equalTo: leadingAnchor),
            left.topAnchor.constraint(equalTo: topAnchor),
            left.bottomAnchor.constraint(equalTo: bottomAnchor),
            right.trailingAnchor.constraint(equalTo: trailingAnchor),
            right.topAnchor.constraint(equalTo: topAnchor),
            right.bottomAnchor.constraint(equalTo: bottomAnchor),
            left.widthAnchor.constraint(equalTo: right.widthAnchor),
            right.leadingAnchor.constraint(equalTo: left.trailingAnchor, constant: IndexDiffEditorMetrics.paneGap)
        ])
    }
}

final class IndexDiffEditorPaneView: NSView {
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
