import AppKit
import SwiftUI
import XToolsCore

/// Clamps the live selection into the current UTF-16 text length before
/// scroll-to-reveal: large programmatic replacements can leave a stale
/// selected range that would crash AppKit when scrolled raw.
func clampedSelectedRange(for textView: NSTextView) -> NSRange {
    let textLength = (textView.string as NSString).length
    let selectedRange = textView.selectedRange()
    let rawLocation = selectedRange.location == NSNotFound ? textLength : selectedRange.location
    let location = min(max(0, rawLocation), textLength)
    let upperBound = min(max(location, selectedRange.upperBound), textLength)
    return NSRange(location: location, length: upperBound - location)
}

@MainActor
protocol IndexAsymmetricTextContainerSurface {
    var leadingTextContainerInset: CGFloat { get }
}

@MainActor
enum IndexTextKitGeometry {
    static let trailingWrapGuard: CGFloat = 16

    static func wrappingContainerWidth(
        for textView: NSTextView,
        visibleWidth: CGFloat,
        trailingReadingGuard: CGFloat = trailingWrapGuard
    ) -> CGFloat {
        let safeVisibleWidth = max(1, visibleWidth.isFinite ? visibleWidth : textView.bounds.width)
        let linePadding = (textView.textContainer?.lineFragmentPadding ?? 0) * 2
        let horizontalInset: CGFloat
        if let asymmetric = textView as? IndexAsymmetricTextContainerSurface {
            horizontalInset = asymmetric.leadingTextContainerInset
        } else {
            horizontalInset = textView.textContainerInset.width * 2
        }
        return max(1, floor(safeVisibleWidth - horizontalInset - linePadding - trailingReadingGuard))
    }

    static func measuredTextHeight(for textView: NSTextView) -> CGFloat {
        guard let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else {
            return 0
        }

        layoutManager.ensureLayout(for: textContainer)
        let usedHeight = layoutManager.usedRect(for: textContainer).height
        let font = textView.font ?? .monospacedSystemFont(ofSize: 12.5, weight: .regular)
        let lineHeight = layoutManager.defaultLineHeight(for: font)
        return ceil(max(lineHeight, usedHeight) + textView.textContainerInset.height * 2)
    }

    static func synchronizeTextGeometry(
        for textView: NSTextView,
        visibleWidth: CGFloat,
        minimumHeight: CGFloat,
        trailingReadingGuard: CGFloat = trailingWrapGuard,
        bottomPadding: CGFloat = 0,
        usesViewportLayout: Bool = false
    ) {
        let width = max(1, floor(visibleWidth.isFinite ? visibleWidth : textView.bounds.width))

        if let textContainer = textView.textContainer {
            textContainer.widthTracksTextView = false
            let newContainerWidth = IndexTextKitGeometry.wrappingContainerWidth(
                for: textView,
                visibleWidth: width,
                trailingReadingGuard: trailingReadingGuard
            )
            if abs(textContainer.containerSize.width - newContainerWidth) > 0.5 {
                textContainer.containerSize = NSSize(
                    width: newContainerWidth,
                    height: CGFloat.greatestFiniteMagnitude
                )
                textView.needsDisplay = true
            }
        }

        let resolvedMinimumHeight = minimumHeight.isFinite ? minimumHeight : 0
        let documentHeight = usesViewportLayout
            ? IndexNativeViewportLayout.documentHeight(for: textView)
            : measuredTextHeight(for: textView)
        // bottomPadding grows the document's tail so a floating chrome band
        // (the code viewer's glass footer) can overlap the viewport while the
        // last line still rests fully above it at the end of the scroll range.
        let height = max(resolvedMinimumHeight, documentHeight + bottomPadding)
        let currentSize = textView.frame.size
        guard abs(currentSize.width - width) > 0.01 || abs(currentSize.height - height) > 0.01 else {
            return
        }
        textView.setFrameSize(NSSize(width: width, height: height))
        textView.needsDisplay = true
    }
}

final class IndexLeadingLockedClipView: NSClipView {
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var bounds = super.constrainBoundsRect(proposedBounds)
        bounds.origin.x = 0
        return bounds
    }

    override func setBoundsOrigin(_ newOrigin: NSPoint) {
        super.setBoundsOrigin(NSPoint(x: 0, y: newOrigin.y))
    }

    override func scroll(to newOrigin: NSPoint) {
        super.scroll(to: NSPoint(x: 0, y: newOrigin.y))
    }
}

/// NSScrollView base that funnels the tile()/layout()/setFrameSize() geometry
/// callbacks through one reentrancy-guarded synchronization hook, so text
/// viewports keep their document geometry in sync whenever AppKit re-tiles
/// them. Subclasses implement their per-surface geometry step.
class IndexTextViewportScrollView: NSScrollView {
    private var isSynchronizing = false

    final override func tile() {
        super.tile()
        synchronizeGeometryIfNeeded()
    }

    final override func layout() {
        super.layout()
        layoutSynchronizeStep()
    }

    final override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        synchronizeGeometryIfNeeded()
    }

    /// Layout callbacks may fire while a gated synchronization is already in
    /// flight; surfaces whose step must run there regardless override this.
    func layoutSynchronizeStep() {
        synchronizeGeometryIfNeeded()
    }

    func synchronizeGeometryIfNeeded() {
        guard !isSynchronizing else { return }
        isSynchronizing = true
        defer { isSynchronizing = false }
        synchronizeDocumentGeometry()
    }

    /// The per-surface document geometry step; subclasses override.
    func synchronizeDocumentGeometry() {}
}

@MainActor
enum IndexTextAreaScrollPositioning {
    static func revealInsertionPoint(in textView: NSTextView, growsWithContent: Bool) {
        guard !growsWithContent else { return }

        revealInsertionPointNow(in: textView, growsWithContent: growsWithContent)
        DispatchQueue.main.async { [weak textView] in
            guard let textView else { return }
            revealInsertionPointNow(in: textView, growsWithContent: growsWithContent)
        }
    }

    static func revealInsertionPointNow(in textView: NSTextView, growsWithContent: Bool) {
        guard !growsWithContent else { return }

        if let layoutManager = textView.layoutManager, let textContainer = textView.textContainer {
            layoutManager.ensureLayout(for: textContainer)
        }
        textView.scrollRangeToVisible(clampedSelectedRange(for: textView))
    }
}
