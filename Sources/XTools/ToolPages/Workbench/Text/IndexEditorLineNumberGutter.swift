import AppKit
import SwiftUI
import XToolsCore

// MARK: - Editor line-number gutter

enum IndexEditorLineNumberGutter {
    /// Number column (34, right-aligned) plus the gap before the separator.
    static let width: CGFloat = 44
}

@MainActor
/// Shared chrome for line-number columns: flipped coordinates, hit-test
/// transparency, the arrow cursor, the trailing hairline, and right-aligned
/// monospaced label attributes. Subclasses own their line enumeration
/// (TextKit 1 fragments vs TextKit 2 line blocks) and status coloring — the
/// bounded TextKit 2 viewport must never reach a legacy layout manager, so
/// enumeration never lives here.
class IndexLineNumberColumnView: NSView {
    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    /// The number column is chrome, not selectable content: keep the arrow
    /// cursor over it even though the column stays hit-test transparent.
    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .arrow)
    }

    /// Trailing hairline separating the number column from the text viewport.
    func drawTrailingHairline() {
        let hairline = NSRect(x: bounds.width - 0.5, y: 0, width: 0.5, height: bounds.height)
        NSColor(ToolTheme.border).setFill()
        NSBezierPath(rect: hairline).fill()
    }

    /// Right-aligned monospaced attributes shared by line-number labels.
    static func labelAttributes(color: NSColor) -> [NSAttributedString.Key: Any] {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .right
        return [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
            .foregroundColor: color,
            .paragraphStyle: paragraphStyle
        ]
    }
}

/// Draws logical line numbers for a measured-content editor as an overlay
/// pinned to the owning scroll view (prototype v3 code-editor gutter).
///
/// Only visible line fragments are projected, and each logical line draws its
/// number once at its first visual fragment, so wrapped lines stay aligned
/// with the editor. The overlay is presentation-only: hit-test transparent,
/// decorative for accessibility, and never touches text storage.
final class IndexEditorLineNumberGutterView: IndexLineNumberColumnView {
    static let numberColumnWidth: CGFloat = 34

    weak var scrollView: NSScrollView?
    weak var textView: NSTextView?
    var diagnosticLine: Int? { didSet { if oldValue != diagnosticLine { needsDisplay = true } } }
    private var newlineOffsetsDirty = true
    private var newlineOffsets: [Int] = []
    private nonisolated(unsafe) var boundsObserver: NSObjectProtocol?

    init(scrollView: NSScrollView, textView: NSTextView) {
        self.scrollView = scrollView
        self.textView = textView
        super.init(frame: .zero)
        setNeedsDisplay(self.bounds)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        if let boundsObserver {
            NotificationCenter.default.removeObserver(boundsObserver)
            self.boundsObserver = nil
        }
        guard window != nil, let scrollView else { return }
        let contentView = scrollView.contentView

        // The scroll view is frame-managed and does not autoresize foreign
        // subviews up from a zero frame; sync once the window has laid out so
        // the first display pass has real geometry.
        DispatchQueue.main.async { [weak self] in
            self?.syncFrameWithScrollView()
        }

        contentView.postsBoundsChangedNotifications = true
        boundsObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: contentView,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.needsDisplay = true
            }
        }
        // Bounds notifications pause during live scrolling; the live-scroll
        // notification keeps the gutter tracking while dragging the scroller.
        // Selector observers deregister at dealloc, so install only once.
        if !didInstallLiveScrollObserver {
            didInstallLiveScrollObserver = true
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(scrollViewDidLiveScroll),
                name: NSScrollView.didLiveScrollNotification,
                object: scrollView
            )
        }
    }

    private nonisolated(unsafe) var didInstallLiveScrollObserver = false

    @objc private func scrollViewDidLiveScroll() {
        needsDisplay = true
    }

    deinit {
        if let boundsObserver {
            NotificationCenter.default.removeObserver(boundsObserver)
        }
    }

    /// Marks cached layout metadata stale after any text-buffer replacement.
    func refresh() {
        newlineOffsetsDirty = true
        needsDisplay = true
    }

    /// The scroll view is frame-managed (no Auto Layout), so the gutter keeps
    /// its own frame in sync at draw time; autoresizing covers live resizes
    /// between draws.
    private func syncFrameWithScrollView() {
        guard let scrollView, scrollView.bounds.height > 0 else { return }
        let target = NSRect(
            x: 0,
            y: 0,
            width: IndexEditorLineNumberGutter.width,
            height: scrollView.bounds.height
        )
        if frame != target {
            frame = target
            needsDisplay = true
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        syncFrameWithScrollView()
        guard let textView, let scrollView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else {
            return
        }

        drawTrailingHairline()

        let nsText = textView.string as NSString
        if newlineOffsetsDirty {
            rebuildNewlineOffsets(for: nsText)
        }

        let visibleRect = scrollView.contentView.bounds
        let origin = textView.textContainerOrigin
        let containerRect = NSRect(
            x: visibleRect.minX - origin.x,
            y: visibleRect.minY - origin.y,
            width: visibleRect.width,
            height: visibleRect.height
        )
        let glyphRange = layoutManager.glyphRange(forBoundingRect: containerRect, in: textContainer)
        let terminal = terminalLineNumberFragment()
        guard glyphRange.length > 0 || nsText.length == 0 || terminal != nil else { return }

        let attributes = IndexLineNumberColumnView.labelAttributes(color: NSColor(ToolTheme.textTertiary))

        if nsText.length == 0 {
            let defaultLineHeight = layoutManager.defaultLineHeight(for: textView.font ?? .monospacedSystemFont(ofSize: 12.5, weight: .regular))
            let y = origin.y - visibleRect.minY
            let label = "1" as NSString
            label.draw(
                in: NSRect(
                    x: 6,
                    y: y + 3,
                    width: Self.numberColumnWidth - 6,
                    height: max(1, defaultLineHeight)
                ),
                withAttributes: attributes
            )
            return
        }

        layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) { [weak self] fragmentRect, _, _, fragmentGlyphRange, _ in
            guard let self else { return }
            let characterIndex = layoutManager.characterIndexForGlyph(at: fragmentGlyphRange.location)
            guard self.isLogicalLineStart(at: characterIndex, in: nsText) else { return }

            let y = fragmentRect.minY + origin.y - visibleRect.minY
            let height = max(1, fragmentRect.height)
            guard y + height >= 0, y <= bounds.height else { return }

            self.drawLineNumber(self.lineNumber(at: characterIndex), y: y, height: height, attributes: attributes)
        }
        if let terminal {
            let y = terminal.rect.minY - visibleRect.minY
            if y + terminal.rect.height >= 0, y <= bounds.height {
                drawLineNumber(terminal.line, y: y, height: terminal.rect.height, attributes: attributes)
            }
        }
    }

    private func drawLineNumber(_ line: Int, y: CGFloat, height: CGFloat,
                                attributes: [NSAttributedString.Key: Any]) {
        var attributes = attributes
        if line == diagnosticLine {
            attributes[.foregroundColor] = NSColor(ToolTheme.error)
            NSColor(ToolTheme.error).setFill()
            NSBezierPath(ovalIn: NSRect(x: 1, y: y + 7, width: 4, height: 4)).fill()
        }
        ("\(line)" as NSString).draw(
            in: NSRect(x: 6, y: y + 3, width: Self.numberColumnWidth - 6, height: max(1, height)),
            withAttributes: attributes
        )
    }

    /// TextKit's terminal empty line has no glyphs to enumerate. Its native
    /// extra fragment also owns the diagnostic at EOF after a newline.
    func terminalLineNumberFragment() -> (line: Int, rect: NSRect)? {
        guard let textView, let manager = textView.layoutManager,
              let container = textView.textContainer,
              manager.extraLineFragmentTextContainer === container else { return nil }
        let text = textView.string as NSString
        if newlineOffsetsDirty { rebuildNewlineOffsets(for: text) }
        guard text.length > 0, newlineOffsets.last == text.length - 1,
              manager.extraLineFragmentRect.height > 0 else { return nil }
        let origin = textView.textContainerOrigin
        return (newlineOffsets.count + 1, manager.extraLineFragmentRect.offsetBy(dx: origin.x, dy: origin.y))
    }

    private func rebuildNewlineOffsets(for nsText: NSString) {
        var offsets: [Int] = []
        offsets.reserveCapacity(nsText.length / 32 + 1)
        var start = 0
        while start < nsText.length {
            var end = 0, contentsEnd = 0
            nsText.getLineStart(nil, end: &end, contentsEnd: &contentsEnd,
                                for: NSRange(location: start, length: 0))
            guard end > start else { break }
            if end > contentsEnd { offsets.append(end - 1) }
            start = end
        }
        newlineOffsets = offsets
        newlineOffsetsDirty = false
    }

    private func isLogicalLineStart(at characterIndex: Int, in nsText: NSString) -> Bool {
        guard characterIndex > 0 else { return true }
        guard characterIndex <= nsText.length else { return false }
        let line = lineNumber(at: characterIndex)
        return line > 1 && newlineOffsets[line - 2] == characterIndex - 1
    }

    private func lineNumber(at characterIndex: Int) -> Int {
        var low = 0
        var high = newlineOffsets.count
        while low < high {
            let mid = (low + high) / 2
            if newlineOffsets[mid] < characterIndex {
                low = mid + 1
            } else {
                high = mid
            }
        }
        return low + 1
    }
}

