import AppKit

/// Keep the complete native document, but let TextKit estimate unvisited
/// paragraphs. Explicit selection/find/navigation may lay out their target.
@MainActor
enum IndexNativeViewportLayout {
    static func configure(_ textView: NSTextView, allowsNonContiguousLayout: Bool = true) {
        textView.layoutManager?.allowsNonContiguousLayout = allowsNonContiguousLayout
        // Do not follow a cheap first frame with unsolicited whole-document
        // work on the main thread. Visiting a region requests its layout.
        textView.layoutManager?.backgroundLayoutEnabled = false
    }

    static func documentHeight(for textView: NSTextView, allowsNonContiguousLayout: Bool = true) -> CGFloat {
        guard let manager = textView.layoutManager,
              let container = textView.textContainer else { return 0 }
        configure(textView, allowsNonContiguousLayout: allowsNonContiguousLayout)
        let font = textView.font ?? .monospacedSystemFont(ofSize: 12.5, weight: .regular)
        let lineHeight = manager.defaultLineHeight(for: font)
        let origin = textView.textContainerOrigin
        let visible = textView.visibleRect
        // An unmounted inner Diff scroll view can temporarily fill its entire
        // document. Its provisional layout request must still be bounded.
        let height = min(2_048, max(lineHeight, visible.height))
        if container.containerSize.width > 1 {
            manager.ensureLayout(
                forBoundingRect: NSRect(x: 0, y: max(0, visible.minY - origin.y),
                                       width: container.containerSize.width, height: height),
                in: container
            )
        }
        let usedHeight = manager.usedRect(for: container).maxY
        return ceil(max(lineHeight, usedHeight) + textView.textContainerInset.height * 2)
    }
}
