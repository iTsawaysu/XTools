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

/// Native text, empty placeholders and status footers share one reading edge.
private enum IndexCodeViewerLayout {
    static let horizontalInset: CGFloat = 13

    static func leadingInset(lineNumbers: Bool) -> CGFloat {
        horizontalInset + (lineNumbers ? IndexEditorLineNumberGutter.width : 0)
    }
}

/// Reports the floating footer's fitted height so the native document can grow
/// an equally tall tail (scroll-end clearance) without a second layout system.
private struct IndexCodeViewerFooterHeightPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// Glass mask for the floating status footer: a square top edge (the hairline)
/// and bottom corners matching the field the band floats inside.
private struct IndexCodeViewerFooterGlassShape: Shape {
    let cornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        let radius = min(cornerRadius, rect.width / 2, rect.height)
        guard radius > 0 else { return Path(rect) }
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
        path.addArc(
            center: CGPoint(x: rect.maxX - radius, y: rect.maxY - radius),
            radius: radius,
            startAngle: .degrees(0),
            endAngle: .degrees(90),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
        path.addArc(
            center: CGPoint(x: rect.minX + radius, y: rect.maxY - radius),
            radius: radius,
            startAngle: .degrees(90),
            endAngle: .degrees(180),
            clockwise: false
        )
        path.closeSubpath()
        return path
    }
}

/// High-performance read-only code surface built on AppKit `NSTextView` and
/// `IndexEditorLineNumberGutterView`.
///
/// Provides:
/// - Viewport-lazy syntax highlighting with bounded line and pass budgets
/// - Complete native text selection/copy when expensive coloring is skipped
/// - Native First Responder support for `⌘A` (Select All) and `⌘C` (Copy)
/// - Native macOS Find Bar support (`⌘F`)
/// - Line spacing matching the input editor
struct IndexCodeViewerSurface: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var highlightingLimited = false
    @State private var fullTextSource: IndexCodeViewerText?
    @State private var previewSource: IndexCodeViewerText?
    @State private var previewCharacterCount: Int?
    /// Fitted height of the currently mounted glass footer; feeds the native
    /// document's scroll-end clearance (see `IndexCodeViewerFooterHeightPreferenceKey`).
    @State private var footerHeight: CGFloat = 0
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

    /// The footer overlays the viewport only while a notice exists; the scroll
    /// document's tail grows to match (prototype G1 glass band).
    private var footerOverlayHeight: CGFloat {
        let showsPreviewFooter = previewSource == text && previewCharacterCount != nil
        let showsDegradationFooter = highlightingLimited && !text.isEmpty
        return showsPreviewFooter || showsDegradationFooter ? footerHeight : 0
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            ZStack(alignment: .topLeading) {
                IndexCodeViewerTextView(
                    text: text,
                    lineNumbers: lineNumbers,
                    syntax: syntax,
                    lineBreakMode: lineBreakMode,
                    embedsFlat: embedsFlat,
                    permitsFullText: fullTextSource == text,
                    bottomInset: footerOverlayHeight,
                    onPreviewChange: { source, count in
                        Task { @MainActor in
                            previewSource = source
                            previewCharacterCount = count
                        }
                    },
                    onHighlightingDegradation: { limited in
                        Task { @MainActor in highlightingLimited = limited }
                    }
                )
                .opacity(text.isEmpty ? 0 : 1)
                .accessibilityHidden(text.isEmpty)

                if text.isEmpty {
                    placeholderView
                        // Wave 2 empty-arrival: the editor placeholder rises in
                        // softly when content empties (IndexEmptyState owns the
                        // staged beats for whole-panel empty states).
                        .transition(
                            .opacity.combined(with: .offset(y: ToolMotion.EmptyArrival.textRiseDistance))
                        )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            if previewSource == text, let previewCharacterCount {
                statusFooter {
                    VStack(alignment: .leading, spacing: ToolMetrics.Spacing.xs) {
                        noticeRow(
                            icon: "eye",
                            "预览前 \(previewCharacterCount) 个字符；选择与查找仅限预览"
                        )
                        HStack(spacing: ToolMetrics.Spacing.sm) {
                            IndexCopyButton(text: text.value, title: "复制全文", showsIcon: false, framed: true)
                            Button("载入全文") { fullTextSource = text }
                                .buttonStyle(IndexSmallButtonStyle(framed: true))
                                .help("全文排版可能需要较长时间")
                        }
                    }
                }
            } else if highlightingLimited, !text.isEmpty {
                statusFooter {
                    noticeRow(icon: "paintpalette", "部分内容已简化着色；仍可选择和复制全文")
                }
            }
        }
        .onPreferenceChange(IndexCodeViewerFooterHeightPreferenceKey.self) { footerHeight = $0 }
        .onChange(of: text) { _ in fullTextSource = nil }
        .animation(
            reduceMotion ? nil : ToolMotion.EmptyArrival.elementArrival,
            value: text.isEmpty
        )
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
        // Workbenches name the whole output surface. Keep that label on a
        // container so it cannot replace the preview notice/action labels.
        .accessibilityElement(children: .contain)
    }

    /// Icon + notice line. The glyph shares the notice's secondary ink so the
    /// monochrome viewport never gains a competing color accent. Icon and text
    /// form one static-text element whose frame keeps the code reading edge
    /// (the icon marks the column the text no longer starts at).
    private func noticeRow(icon systemImage: String, _ message: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: ToolMetrics.IconSize.small, weight: .medium))
                .foregroundStyle(ToolTheme.textSecondary)
                .padding(.top, 1.5)
                .accessibilityHidden(true)
            Text(verbatim: message)
                .font(ToolTypography.caption)
                .foregroundStyle(ToolTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isStaticText)
        .accessibilityLabel(message)
    }

    /// Frosted chrome band floating over the viewport's bottom edge (prototype
    /// G1): the notice and its actions ride the system material, so scrolling
    /// content passes under them blurred instead of reading as more output.
    private func statusFooter<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(ToolTheme.border)
                .frame(height: 0.5)
                .accessibilityHidden(true)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, IndexCodeViewerLayout.leadingInset(lineNumbers: lineNumbers))
                .padding(.trailing, IndexCodeViewerLayout.horizontalInset)
                .padding(.vertical, ToolMetrics.Spacing.sm)
        }
        .fixedSize(horizontal: false, vertical: true)
        .background {
            // ultraThin keeps the light frost translucent; the adaptive
            // editor tint restores enough body in dark mode that the notice
            // stays legible over busy content.
            IndexCodeViewerFooterGlassShape(cornerRadius: ToolMetrics.CornerRadius.field)
                .fill(.ultraThinMaterial)
                .overlay {
                    IndexCodeViewerFooterGlassShape(cornerRadius: ToolMetrics.CornerRadius.field)
                        .fill(ToolTheme.editorBackground.opacity(0.35))
                }
        }
        .background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: IndexCodeViewerFooterHeightPreferenceKey.self,
                    value: proxy.size.height
                )
            }
        }
        // The band is chrome over the selectable text surface, never a
        // typeable/selectable hover target itself.
        .arrowCursorOnHover()
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
                .padding(.leading, lineNumbers ? IndexCodeViewerLayout.horizontalInset : 0)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .padding(.vertical, 12)
        .padding(.trailing, IndexCodeViewerLayout.horizontalInset)
        .padding(.leading, lineNumbers ? 0 : IndexCodeViewerLayout.horizontalInset)
        // Fill the pane first so the gutter hairline spans the full height
        // like the native gutter instead of just the placeholder text block.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .overlay(alignment: .leading) {
            if lineNumbers {
                // 1pt at half opacity renders reliably where a 0.5pt frame
                // gets rounded away in this overlay hierarchy, and reads
                // identical to the native gutter hairline.
                Rectangle()
                    .fill(ToolTheme.border)
                    .frame(width: 1)
                    .opacity(0.5)
                    .padding(.leading, IndexEditorLineNumberGutter.width - 0.5)
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
    /// Tail space appended to the scroll document while the glass footer
    /// floats over the viewport, keeping the last line reachable above it.
    var bottomInset: CGFloat = 0
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
            minimumHeight: contentSize.height,
            bottomPadding: bottomInset,
            usesViewportLayout: true
        )
    }
}

private struct IndexCodeViewerTextView: NSViewRepresentable {
    let text: IndexCodeViewerText
    var lineNumbers: Bool
    var syntax: IndexSyntaxKind?
    var lineBreakMode: NSLineBreakMode
    var embedsFlat: Bool
    var permitsFullText: Bool
    var bottomInset: CGFloat
    var onPreviewChange: (IndexCodeViewerText, Int?) -> Void
    var onHighlightingDegradation: (Bool) -> Void

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
        scrollView.bottomInset = bottomInset

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

        let plan = IndexCodePreviewPlan.make(text: text.value, permitsFullText: permitsFullText)
        applyContent(plan.displayedText, to: textView)
        onPreviewChange(text, plan.previewCharacterCount)

        context.coordinator.highlighting.onDegradationChange = onHighlightingDegradation
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
        context.coordinator.highlighting.contentChanged(text: plan.displayedText, syntax: syntax)
        scrollView.synchronizeGeometryIfNeeded()
        context.coordinator.lastText = text
        context.coordinator.lastSyntax = syntax
        context.coordinator.lastPermitsFullText = permitsFullText
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let customScrollView = scrollView as? IndexCodeViewerScrollView,
              let textView = customScrollView.documentView as? IndexCodeViewerTextViewInternal else { return }
        configure(textView)
        context.coordinator.highlighting.onDegradationChange = onHighlightingDegradation

        if customScrollView.bottomInset != bottomInset {
            customScrollView.bottomInset = bottomInset
            customScrollView.synchronizeTextGeometry()
        }

        if context.coordinator.lastText != text || context.coordinator.lastSyntax != syntax
            || context.coordinator.lastPermitsFullText != permitsFullText {
            context.coordinator.lastText = text
            context.coordinator.lastSyntax = syntax
            context.coordinator.lastPermitsFullText = permitsFullText
            let plan = IndexCodePreviewPlan.make(text: text.value, permitsFullText: permitsFullText)
            let previousSelectedRanges = textView.selectedRanges
            applyContent(plan.displayedText, to: textView)
            onPreviewChange(text, plan.previewCharacterCount)
            let stringLength = (plan.displayedText as NSString).length
            let validRanges = previousSelectedRanges.filter { $0.rangeValue.upperBound <= stringLength }
            if !validRanges.isEmpty {
                textView.selectedRanges = validRanges
            }
            customScrollView.synchronizeTextGeometry()
            context.coordinator.highlighting.contentChanged(text: plan.displayedText, syntax: syntax)
            context.coordinator.lineNumberGutter?.refresh()
        } else {
            customScrollView.synchronizeTextGeometry()
            context.coordinator.highlighting.highlightVisibleIfNeeded()
        }
    }

    private func configure(_ textView: NSTextView) {
        IndexNativeViewportLayout.configure(textView)
        textView.isEditable = false
        textView.isSelectable = true
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        AppKitTextEditingConfiguration.configurePlainTextEditor(textView, allowsUndo: false)

        let font = NSFont.monospacedSystemFont(ofSize: 12.5, weight: .regular)
        if textView.font != font { textView.font = font }
        // The attributed document owns its colors. Setting textColor again
        // would erase token colors during an unrelated SwiftUI state update.
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 6
        if textView.defaultParagraphStyle != paragraphStyle {
            textView.defaultParagraphStyle = paragraphStyle
        }

        textView.textContainerInset = NSSize(
            width: IndexCodeViewerLayout.leadingInset(lineNumbers: lineNumbers),
            height: 12
        )

        if let textContainer = textView.textContainer {
            textContainer.widthTracksTextView = false
            textContainer.lineFragmentPadding = 0
            textContainer.lineBreakMode = lineBreakMode
        }
    }

    /// The explicit preview policy owns the displayed document. Toolbar copy
    /// and export continue to use the complete formatter result.
    private func applyContent(_ displayedText: String, to textView: NSTextView) {
        let attributed = NSAttributedString(string: displayedText, attributes: Self.baseAttributes(lineSpacing: 6))
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
        var lastPermitsFullText = false
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
    private var continuationScheduled = false
    private var unhighlightedLineCount = 0
    private var degradationReported = false
    var onDegradationChange: ((Bool) -> Void)?
    private(set) var lastPassUTF16Count = 0
    private(set) var lastPassTokenCount = 0
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
                (self?.scrollView as? IndexCodeViewerScrollView)?.synchronizeGeometryIfNeeded()
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
        highlightedLines = lineRanges.map { $0.length > IndexSyntaxHighlightBudget.maximumLineUTF16 }
        unhighlightedLineCount = highlightedLines.filter { !$0 }.count
        reportDegradation(syntax != nil && highlightedLines.contains(true))
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
        guard !isApplyingAttributes, unhighlightedLineCount > 0 else { return }
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
        lastPassUTF16Count = 0
        lastPassTokenCount = 0
        textStorage.beginEditing()
        defer {
            textStorage.endEditing()
            isApplyingAttributes = false
        }
        for lineIndex in span where !highlightedLines[lineIndex] {
            let fullRange = lineRanges[lineIndex]
            if lastPassUTF16Count + fullRange.length > IndexSyntaxHighlightBudget.maximumPassUTF16
                || lastPassTokenCount >= IndexSyntaxHighlightBudget.maximumPassTokens {
                scheduleContinuation()
                break
            }
            highlightedLines[lineIndex] = true
            unhighlightedLineCount -= 1
            let hasNewline = NSMaxRange(fullRange) > fullRange.location
                && nsText.character(at: NSMaxRange(fullRange) - 1) == unichar(10)
            let contentLength = max(0, fullRange.length - (hasNewline ? 1 : 0))
            guard contentLength > 0 else { continue }

            let contentRange = NSRange(location: fullRange.location, length: contentLength)
            lastPassUTF16Count += contentLength
            let line = nsText.substring(with: contentRange)
            let tokens = syntax.tokens(line: line)
            guard tokens.count <= IndexSyntaxHighlightBudget.maximumLineTokens else {
                reportDegradation(true)
                continue
            }
            if lastPassTokenCount + tokens.count > IndexSyntaxHighlightBudget.maximumPassTokens {
                highlightedLines[lineIndex] = false
                unhighlightedLineCount += 1
                scheduleContinuation()
                break
            }
            lastPassTokenCount += tokens.count
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

    private func reportDegradation(_ limited: Bool) {
        guard limited != degradationReported else { return }
        degradationReported = limited
        onDegradationChange?(limited)
    }

    private func scheduleContinuation() {
        guard !continuationScheduled else { return }
        continuationScheduled = true
        Task { @MainActor [weak self] in
            // Every continuation re-reads the current content/syntax/viewport;
            // it never applies a captured range to a newer text revision.
            await Task.yield()
            guard let self else { return }
            self.continuationScheduled = false
            self.highlightVisibleIfNeeded()
        }
    }

}
