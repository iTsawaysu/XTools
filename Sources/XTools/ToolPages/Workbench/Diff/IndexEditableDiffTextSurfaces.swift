import AppKit
import SwiftUI
import XToolsCore

final class IndexDiffTextView: IndexCaretWideningTextView, IndexAsymmetricTextContainerSurface, IndexDiffIndexedTextSurface {
    lazy var diffTextIndex = IndexDiffTextIndex(storage: textStorage)
    var lastDecorationRevision = -1
    var lastDecorationGeneration = -1
    var lastDecorationSpan: Range<Int>?
    var decoratedRange: NSRange?
    var onAppearanceChange: (() -> Void)?

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        onAppearanceChange?()
    }
    private var droppedFile: IndexDroppedTextFile?
    var leadingTextContainerInset: CGFloat {
        IndexDiffEditorMetrics.textInset.width
    }

    var lineDecorations: [Int: DiffLineDecoration] = [:] {
        didSet {
            needsDisplay = true
        }
    }

    var onFileDropDiagnostic: ((String?) -> Void)?

    // Drop-state hooks: the shared base drives the drag session; this surface
    // additionally reports drop rejections through the workspace diagnostic.

    override func invalidateDropState() {
        droppedFile?.invalidate()
        onFileDropDiagnostic?(nil)
    }

    override func invalidatePendingDropRead() {
        droppedFile?.invalidate()
    }

    override func loadDroppedFile(from url: URL) {
        if droppedFile == nil { droppedFile = IndexDroppedTextFile(view: self) }
        onFileDropDiagnostic?(nil)
        droppedFile?.start(url: url, onRejected: { [weak self] rejection in
            self?.onFileDropDiagnostic?(rejection.message)
        }) { [weak self] content in
            self?.onFileDropDiagnostic?(nil)
            self?.onFileDrop?(content)
        }
    }

    func invalidateDroppedFile() {
        droppedFile?.invalidate()
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

final class IndexDiffLineNumberOverlayView: IndexLineNumberColumnView {
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

    init(scrollView: NSScrollView, textView: NSTextView) {
        self.scrollView = scrollView
        self.textView = textView
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let textView,
              let scrollView = scrollView else {
            return
        }

        drawTrailingHairline()

        let visibleRect = textView.visibleRect
        let lineRects = IndexDiffTextLayoutGeometry.lineBlockRects(for: textView, visibleRect: visibleRect)

        let labelX = IndexDiffEditorMetrics.lineNumberLeadingPadding
        let labelWidth = max(
            1,
            bounds.width - IndexDiffEditorMetrics.lineNumberLeadingPadding - IndexDiffEditorMetrics.lineNumberTrailingPadding
        )
        let labelHeight = IndexDiffTextLayoutGeometry.defaultLineHeight(for: textView)

        let nsText = textView.string as NSString
        let attributes = IndexLineNumberColumnView.labelAttributes(color: lineNumberColor(for: .unchanged))

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
            guard let lineRect = lineRects[lineNumber], lineRect.intersects(visibleRect) else { continue }
            let status = lineStatuses[lineNumber] ?? .unchanged
            let y = lineRect.minY - scrollView.contentView.bounds.minY
            let height = max(1, lineRect.height)

            if status != .unchanged, NSRect(x: 0, y: y, width: bounds.width, height: height).intersects(bounds) {
                status.rulerColor.setFill()
                NSBezierPath(
                    roundedRect: gutterAccentRect(y: y, height: height),
                    xRadius: 1,
                    yRadius: 1
                ).fill()
            }
            var lineAttributes = attributes
            lineAttributes[.foregroundColor] = lineNumberColor(for: status)
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
            y: y + IndexDiffEditorMetrics.gutterAccentVerticalInset,
            width: IndexDiffEditorMetrics.gutterAccentWidth,
            height: max(
                IndexDiffEditorMetrics.gutterAccentMinHeight,
                height - IndexDiffEditorMetrics.gutterAccentVerticalInset * 2
            )
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

enum IndexDiffNSPalette {
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

    private static func resolvedColor(_ color: Color, for appearance: NSAppearance) -> NSColor {
        var resolved = NSColor.clear
        appearance.performAsCurrentDrawingAppearance {
            let sharedColor = NSColor(color)
            resolved = sharedColor.usingColorSpace(.deviceRGB) ?? sharedColor
        }
        return resolved
    }
}
