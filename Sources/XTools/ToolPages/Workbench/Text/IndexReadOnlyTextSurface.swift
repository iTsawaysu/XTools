import AppKit
import SwiftUI

struct IndexReadOnlyTextSurface: View {
    let text: String
    let placeholder: String
    var fillsHeight = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            IndexReadOnlyTextView(text: text)
                .opacity(text.isEmpty ? 0 : 1)
                .accessibilityHidden(text.isEmpty)

            if text.isEmpty {
                Text(placeholder)
                    .font(ToolTypography.body)
                    .foregroundStyle(ToolTheme.textTertiary)
                    .padding(12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .accessibilityLabel(placeholder)
            }
        }
        .frame(
            maxWidth: .infinity,
            minHeight: fillsHeight ? 60 : 220,
            maxHeight: fillsHeight ? .infinity : nil,
            alignment: .topLeading
        )
        .background(ToolTheme.editorBackground, in: RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.field, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.field, style: .continuous)
                .strokeBorder(ToolTheme.border, lineWidth: 0.5)
        }
    }
}

private final class IndexReadOnlyTextScrollView: NSScrollView {
    private var isSynchronizing = false

    override func tile() {
        super.tile()
        synchronizeDocumentGeometry()
    }

    override func layout() {
        super.layout()
        synchronizeDocumentGeometry()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        synchronizeDocumentGeometry()
    }

    private func synchronizeDocumentGeometry() {
        guard !isSynchronizing else { return }
        isSynchronizing = true
        defer { isSynchronizing = false }
        guard let textView = documentView as? NSTextView else { return }
        let viewportWidth = contentSize.width
        if viewportWidth > 0 && abs(textView.frame.width - viewportWidth) > 0.5 {
            textView.setFrameSize(NSSize(width: viewportWidth, height: textView.frame.height))
        }
    }
}

private struct IndexReadOnlyTextView: NSViewRepresentable {
    let text: String

    private static func makeTextView() -> NSTextView {
        let textView = NSTextView(usingTextLayoutManager: true)
        precondition(textView.textLayoutManager != nil)
        return textView
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = Self.makeTextView()
        let scrollView = IndexReadOnlyTextScrollView(frame: .zero)
        scrollView.contentView = IndexLeadingLockedClipView(frame: .zero)
        scrollView.documentView = textView
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true

        textView.autoresizingMask = [.width]
        textView.minSize = .zero
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: max(1, scrollView.contentSize.width),
            height: CGFloat.greatestFiniteMagnitude
        )
        configure(textView)
        textView.string = text
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        configure(textView)
        guard textView.string != text else { return }

        let selectedRange = textView.selectedRange()
        textView.string = text
        let textLength = (text as NSString).length
        if selectedRange.location != NSNotFound,
           selectedRange.upperBound <= textLength {
            textView.setSelectedRange(selectedRange)
        } else {
            textView.setSelectedRange(NSRange(location: 0, length: 0))
        }
        scrollView.contentView.scroll(to: .zero)
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    private func configure(_ textView: NSTextView) {
        textView.isEditable = false
        textView.isSelectable = true
        textView.usesFindPanel = true
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.font = .monospacedSystemFont(ofSize: 12.5, weight: .regular)
        textView.textColor = .secondaryLabelColor
        textView.textContainerInset = NSSize(width: 12, height: 12)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.lineBreakMode = .byCharWrapping
        textView.insertionPointColor = .controlAccentColor
        AppKitTextEditingConfiguration.configurePlainTextEditor(textView, allowsUndo: false)
    }
}
