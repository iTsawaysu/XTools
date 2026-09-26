import AppKit
import SwiftUI

/// SwiftUI diffing must distinguish canonically equivalent formatter output
/// when its Unicode bytes differ, so the native viewer can copy exact output.
private struct IndexCodeViewerText: Equatable {
    let value: String

    var isEmpty: Bool { value.isEmpty }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.value.utf8.elementsEqual(rhs.value.utf8)
    }
}

/// High-performance read-only code surface built on AppKit `NSTextView` and
/// `IndexEditorLineNumberGutterView`.
///
/// Provides:
/// - True viewport virtualization (instant rendering & 120 FPS scrolling on 100k+ lines)
/// - Viewport-lazy syntax highlighting: only logical lines around the visible
///   rect are colorized, so arbitrarily large outputs highlight without a
///   per-page character budget
/// - Native First Responder support for `⌘A` (Select All) and `⌘C` (Copy)
/// - Native macOS Find Bar support (`⌘F`)
/// - Line spacing matching the input editor
struct IndexCodeViewerSurface: View {
    private let text: IndexCodeViewerText
    var placeholder: String = IndexEmptyStateCopy.outputWillShowHere
    var lineNumbers: Bool = true
    var syntax: IndexSyntaxKind? = nil
    var fillsHeight: Bool = true
    var minHeight: CGFloat = 220
    var lineBreakMode: NSLineBreakMode = .byCharWrapping
    var embedsFlat: Bool = false

    init(
        text: String,
        placeholder: String = IndexEmptyStateCopy.outputWillShowHere,
        lineNumbers: Bool = true,
        syntax: IndexSyntaxKind? = nil,
        fillsHeight: Bool = true,
        minHeight: CGFloat = 220,
        lineBreakMode: NSLineBreakMode = .byCharWrapping,
        embedsFlat: Bool = false
    ) {
        self.text = IndexCodeViewerText(value: text)
        self.placeholder = placeholder
        self.lineNumbers = lineNumbers
        self.syntax = syntax
        self.fillsHeight = fillsHeight
        self.minHeight = minHeight
        self.lineBreakMode = lineBreakMode
        self.embedsFlat = embedsFlat
    }

    private var effectiveMinHeight: CGFloat { fillsHeight ? 60 : minHeight }

    var body: some View {
        ZStack(alignment: .topLeading) {
            IndexCodeViewerTextView(
                text: text,
                lineNumbers: lineNumbers,
                syntax: syntax,
                lineBreakMode: lineBreakMode,
                embedsFlat: embedsFlat
            )
            .opacity(text.isEmpty ? 0 : 1)
            .accessibilityHidden(text.isEmpty)

            if text.isEmpty {
                placeholderView
            }
        }
        .frame(
            maxWidth: .infinity,
            minHeight: effectiveMinHeight,
            maxHeight: fillsHeight ? .infinity : nil,
            alignment: .topLeading
        )
        .background(
            embedsFlat ? Color.clear : ToolTheme.editorBackground,
            in: RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.field, style: .continuous)
        )
        .overlay {
            if !embedsFlat {
                RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.field, style: .continuous)
                    .strokeBorder(ToolTheme.border, lineWidth: 0.5)
            }
        }
    }

    private var placeholderView: some View {
        HStack(alignment: .top, spacing: 0) {
            if lineNumbers {
                Text("1")
                    .font(ToolTypography.monoCaption)
                    .monospacedDigit()
                    .foregroundStyle(ToolTheme.textTertiary)
                    .frame(width: 34, alignment: .trailing)
                    .padding(.trailing, 10)
            }
            Text(placeholder)
                .font(ToolTypography.codeBody)
                .foregroundStyle(ToolTheme.textTertiary)
                .lineLimit(nil)
                .multilineTextAlignment(.leading)
                .lineSpacing(6)
                .padding(.leading, lineNumbers ? 13 : 0)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .padding(.vertical, 12)
        .padding(.trailing, 13)
        .padding(.leading, lineNumbers ? 0 : 13)
        .overlay(alignment: .leading) {
            if lineNumbers {
                Rectangle()
                    .fill(ToolTheme.border)
                    .frame(width: 0.5)
                    .padding(.leading, IndexEditorLineNumberGutter.width)
            }
        }
    }
}

private final class IndexCodeViewerTextViewInternal: NSTextView, IndexAsymmetricTextContainerSurface {
    var leadingTextContainerInset: CGFloat {
        textContainerInset.width
    }

    var onEffectiveAppearanceChange: (() -> Void)?

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        onEffectiveAppearanceChange?()
    }
}

private final class IndexCodeViewerScrollView: NSScrollView {
    weak var lineNumberGutter: IndexEditorLineNumberGutterView?
    var onViewportSizeChange: (() -> Void)?
    private var isSynchronizing = false
    private var lastViewportSize: NSSize = .zero

    override func tile() {
        super.tile()
        synchronizeGeometryIfNeeded()
    }

    override func layout() {
        super.layout()
        synchronizeGeometryIfNeeded()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        synchronizeGeometryIfNeeded()
    }

    func synchronizeGeometryIfNeeded() {
        guard !isSynchronizing else { return }
        isSynchronizing = true
        defer { isSynchronizing = false }
        synchronizeTextGeometry()
        if let gutter = lineNumberGutter, abs(gutter.frame.height - bounds.height) > 0.5 {
            gutter.frame = NSRect(x: 0, y: 0, width: IndexEditorLineNumberGutter.width, height: bounds.height)
        }
        lineNumberGutter?.setNeedsDisplay(lineNumberGutter?.bounds ?? .zero)
        let viewportSize = contentView.bounds.size
        if viewportSize.width > 0, viewportSize.height > 0,
           viewportSize != lastViewportSize,
           let onViewportSizeChange {
            lastViewportSize = viewportSize
            onViewportSizeChange()
        }
    }

    func synchronizeTextGeometry() {
        guard let textView = documentView as? NSTextView else { return }
        IndexTextKitGeometry.synchronizeTextGeometry(
            for: textView,
            visibleWidth: contentSize.width,
            minimumHeight: contentSize.height
        )
    }
}

private struct IndexCodeViewerTextView: NSViewRepresentable {
    let text: IndexCodeViewerText
    var lineNumbers: Bool
    var syntax: IndexSyntaxKind?
    var lineBreakMode: NSLineBreakMode
    var embedsFlat: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = IndexCodeViewerTextViewInternal(frame: .zero)
        let scrollView = IndexCodeViewerScrollView(frame: .zero)
        scrollView.contentView = IndexLeadingLockedClipView(frame: .zero)
        scrollView.documentView = textView
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true

        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.isRichText = false
        textView.importsGraphics = false
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.backgroundColor = .clear

        configure(textView)
        textView.onEffectiveAppearanceChange = { [weak coordinator = context.coordinator] in
            coordinator?.highlighting.resetAppliedTokens()
        }

        if lineNumbers {
            let gutter = IndexEditorLineNumberGutterView(scrollView: scrollView, textView: textView)
            gutter.autoresizingMask = [.height]
            scrollView.addSubview(gutter)
            scrollView.lineNumberGutter = gutter
            context.coordinator.lineNumberGutter = gutter
        }

        applyContent(to: textView)

        context.coordinator.highlighting.install(
            scrollView: scrollView,
            textView: textView,
            syntax: syntax,
            baseAttributes: Self.baseAttributes(lineSpacing: 6)
        )
        scrollView.onViewportSizeChange = { [weak coordinator = context.coordinator] in
            Task { @MainActor in
                coordinator?.highlighting.highlightVisibleIfNeeded()
            }
        }
        context.coordinator.highlighting.contentChanged(text: text.value, syntax: syntax)
        scrollView.synchronizeGeometryIfNeeded()
        context.coordinator.lastText = text
        context.coordinator.lastSyntax = syntax
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let customScrollView = scrollView as? IndexCodeViewerScrollView,
              let textView = customScrollView.documentView as? IndexCodeViewerTextViewInternal else { return }
        configure(textView)

        if context.coordinator.lastText != text || context.coordinator.lastSyntax != syntax {
            context.coordinator.lastText = text
            context.coordinator.lastSyntax = syntax
            let previousSelectedRanges = textView.selectedRanges
            applyContent(to: textView)
            let stringLength = (text.value as NSString).length
            let validRanges = previousSelectedRanges.filter { $0.rangeValue.upperBound <= stringLength }
            if !validRanges.isEmpty {
                textView.selectedRanges = validRanges
            }
            customScrollView.synchronizeTextGeometry()
            context.coordinator.highlighting.contentChanged(text: text.value, syntax: syntax)
            context.coordinator.lineNumberGutter?.refresh()
        } else {
            customScrollView.synchronizeTextGeometry()
            context.coordinator.highlighting.highlightVisibleIfNeeded()
        }
    }

    private func configure(_ textView: NSTextView) {
        textView.isEditable = false
        textView.isSelectable = true
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        AppKitTextEditingConfiguration.configurePlainTextEditor(textView, allowsUndo: false)

        textView.font = .monospacedSystemFont(ofSize: 12.5, weight: .regular)
        textView.textColor = NSColor(ToolTheme.textSecondary)

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 6
        textView.defaultParagraphStyle = paragraphStyle

        textView.textContainerInset = NSSize(
            width: lineNumbers ? IndexEditorLineNumberGutter.width + 13 : 13,
            height: 12
        )

        if let textContainer = textView.textContainer {
            textContainer.widthTracksTextView = false
            textContainer.lineFragmentPadding = 0
            textContainer.lineBreakMode = lineBreakMode
        }
    }

    /// Plain base attributes only; syntax colors are applied lazily by the
    /// viewport highlighter, which keeps first paint O(visible) regardless of
    /// document size.
    private func applyContent(to textView: NSTextView) {
        let attributed = NSAttributedString(string: text.value, attributes: Self.baseAttributes(lineSpacing: 6))
        textView.textStorage?.setAttributedString(attributed)
    }

    private static func baseAttributes(lineSpacing: CGFloat) -> [NSAttributedString.Key: Any] {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = lineSpacing
        return [
            .font: NSFont.monospacedSystemFont(ofSize: 12.5, weight: .regular),
            .paragraphStyle: paragraphStyle,
            .foregroundColor: NSColor(ToolTheme.textSecondary)
        ]
    }

    @MainActor
    final class Coordinator: NSObject {
        var lastText: IndexCodeViewerText?
        var lastSyntax: IndexSyntaxKind?
        weak var lineNumberGutter: IndexEditorLineNumberGutterView?
        let highlighting = IndexViewportHighlighting()
    }
}

/// Colors only the logical lines inside (and near) the current scroll
/// viewport. Per-line tokenizing is stateless, so a partially highlighted
/// document is always visually consistent; lines outside the viewport keep
/// the plain base color until they scroll into view.
@MainActor
final class IndexViewportHighlighting {
    /// Extra fully-colored lines kept above and below the viewport so fast
    /// scrolls reveal pre-highlighted content instead of plain flashes.
    private static let viewportLineMargin = 12

    private weak var scrollView: NSScrollView?
    private weak var textView: NSTextView?
    private var syntax: IndexSyntaxKind?
    private var baseAttributes: [NSAttributedString.Key: Any] = [:]

    /// UTF-16 ranges of each logical line including its trailing newline.
    private var lineRanges: [NSRange] = []
    private var highlightedLines: [Bool] = []
    private var isApplyingAttributes = false
    private nonisolated(unsafe) var boundsObserver: (any NSObjectProtocol)?

    func install(
        scrollView: NSScrollView,
        textView: NSTextView,
        syntax: IndexSyntaxKind?,
        baseAttributes: [NSAttributedString.Key: Any]
    ) {
        self.scrollView = scrollView
        self.textView = textView
        self.baseAttributes = baseAttributes

        let contentView = scrollView.contentView
        contentView.postsBoundsChangedNotifications = true
        boundsObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: contentView,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.highlightVisibleIfNeeded()
            }
        }
    }

    deinit {
        if let boundsObserver {
            NotificationCenter.default.removeObserver(boundsObserver)
        }
    }

    func contentChanged(text: String, syntax: IndexSyntaxKind?) {
        self.syntax = syntax
        rebuildLineRanges(for: text)
        resetAppliedTokens()
    }

    /// Wipes token colors (appearance flip, syntax change) and re-colors the
    /// visible window from the plain base attributes.
    func resetAppliedTokens() {
        guard let textView else { return }
        let fullRange = NSRange(location: 0, length: (textView.string as NSString).length)
        textView.textStorage?.setAttributes(baseAttributes, range: fullRange)
        highlightedLines = Array(repeating: false, count: lineRanges.count)
        highlightVisibleIfNeeded()
    }

    private func rebuildLineRanges(for text: String) {
        let nsText = text as NSString
        var ranges: [NSRange] = []
        ranges.reserveCapacity(nsText.length / 32 + 1)

        var searchRange = NSRange(location: 0, length: nsText.length)
        var lineStart = 0
        while searchRange.location < nsText.length {
            let newline = nsText.range(of: "\n", options: [], range: searchRange)
            guard newline.location != NSNotFound else { break }
            ranges.append(NSRange(location: lineStart, length: newline.location - lineStart + 1))
            lineStart = newline.location + 1
            searchRange = NSRange(location: lineStart, length: nsText.length - lineStart)
        }
        if lineStart <= nsText.length, nsText.length > 0 {
            ranges.append(NSRange(location: lineStart, length: nsText.length - lineStart))
        }
        lineRanges = ranges
    }

    func highlightVisibleIfNeeded() {
        guard !isApplyingAttributes else { return }
        guard let scrollView, let textView, let syntax,
              !lineRanges.isEmpty,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer,
              let textStorage = textView.textStorage else {
            return
        }

        let visibleRect = scrollView.contentView.bounds
        guard visibleRect.height > 0 else { return }
        let origin = textView.textContainerOrigin
        let containerRect = NSRect(
            x: visibleRect.minX - origin.x,
            y: visibleRect.minY - origin.y,
            width: visibleRect.width,
            height: visibleRect.height
        )
        let glyphRange = layoutManager.glyphRange(forBoundingRect: containerRect, in: textContainer)
        let characterRange = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
        guard characterRange.length > 0 || characterRange.location == 0 else { return }

        let span = IndexViewportHighlightMath.lineSpan(
            covering: characterRange,
            lineRanges: lineRanges,
            margin: Self.viewportLineMargin
        )
        guard !span.isEmpty else { return }
        guard span.contains(where: { !highlightedLines[$0] }) else { return }

        let nsText = textView.string as NSString
        // Geometry is resolved above. TextKit coalesces the token edits and
        // notifies observers after every line has been marked as highlighted.
        isApplyingAttributes = true
        textStorage.beginEditing()
        defer {
            textStorage.endEditing()
            isApplyingAttributes = false
        }
        for lineIndex in span where !highlightedLines[lineIndex] {
            highlightedLines[lineIndex] = true
            let fullRange = lineRanges[lineIndex]
            let hasNewline = NSMaxRange(fullRange) > fullRange.location
                && nsText.character(at: NSMaxRange(fullRange) - 1) == unichar(10)
            let contentLength = max(0, fullRange.length - (hasNewline ? 1 : 0))
            guard contentLength > 0 else { continue }

            let contentRange = NSRange(location: fullRange.location, length: contentLength)
            let line = nsText.substring(with: contentRange)
            let tokens = syntax.tokens(line: line)
            guard !tokens.isEmpty else { continue }
            let utf16Ranges = IndexSyntaxUTF16RangeMap(line: line)
            for token in tokens {
                guard let tokenRange = utf16Ranges.range(for: token, in: contentRange) else {
                    continue
                }
                textStorage.addAttribute(
                    .foregroundColor,
                    value: token.kind.nsColor,
                    range: tokenRange
                )
            }
        }
    }
}
