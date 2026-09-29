import AppKit
import XToolsCore

/// Prepared once for a completed request, never inferred from a parser's
/// unspecified column unit. The source snapshot guards native edits and IME.
struct IndexTextAreaDiagnosticMarker: Equatable, Sendable {
    let id = UUID()
    let sourceText: String
    let line: Int
    let selectionRange: NSRange
    let decorationRange: NSRange?

    init?(diagnostic: FormatDiagnostic, sourceText: String) {
        guard let line = diagnostic.line, line > 0 else { return nil }
        let source = sourceText as NSString
        self.sourceText = sourceText
        self.line = line
        if let range = diagnostic.sourceUTF16Range {
            guard range.location != NSNotFound, range.location >= 0,
                  range.location <= source.length, range.length >= 0,
                  range.length <= source.length - range.location,
                  Range(range, in: sourceText) != nil else { return nil }
            selectionRange = range
            decorationRange = range.length > 0 ? range : nil
        } else {
            var offset = 0
            var currentLine = 1
            while currentLine < line, offset < source.length {
                var end = 0
                var contentsEnd = 0
                source.getLineStart(nil, end: &end, contentsEnd: &contentsEnd,
                                    for: NSRange(location: offset, length: 0))
                guard end > contentsEnd else { return nil }
                offset = end
                currentLine += 1
            }
            guard currentLine == line else { return nil }
            selectionRange = NSRange(location: offset, length: 0)
            decorationRange = nil
        }
    }

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
}

/// Temporary attributes leave the document, typing attributes and undo history
/// untouched. Only an explicit navigation request changes selection or focus.
@MainActor
final class IndexTextAreaDiagnosticController {
    private var appliedID: UUID?
    private var decorationRange: NSRange?
    private var navigationToken = 0

    func clear(in textView: NSTextView, gutter: IndexEditorLineNumberGutterView?) {
        if let range = decorationRange, range.upperBound <= (textView.string as NSString).length {
            textView.layoutManager?.removeTemporaryAttribute(.underlineStyle, forCharacterRange: range)
            textView.layoutManager?.removeTemporaryAttribute(.underlineColor, forCharacterRange: range)
        }
        decorationRange = nil
        appliedID = nil
        gutter?.diagnosticLine = nil
    }

    func update(
        _ marker: IndexTextAreaDiagnosticMarker?,
        requestToken: Int,
        in textView: NSTextView,
        gutter: IndexEditorLineNumberGutterView?
    ) {
        // A rejected click is consumed, never deferred onto a later source or
        // post-IME result. Parsing a fresh diagnostic must not steal focus.
        let shouldNavigate = requestToken > 0 && requestToken != navigationToken
        navigationToken = requestToken
        guard let marker, !textView.hasMarkedText(),
              JSONExactTextIdentity.isExactlyEqual(marker.sourceText, textView.string) else {
            clear(in: textView, gutter: gutter)
            return
        }
        if appliedID != marker.id {
            clear(in: textView, gutter: gutter)
            if let range = marker.decorationRange {
                textView.layoutManager?.addTemporaryAttributes([
                    .underlineStyle: NSUnderlineStyle.single.rawValue,
                    .underlineColor: NSColor(ToolTheme.error)
                ], forCharacterRange: range)
                decorationRange = range
            }
            gutter?.diagnosticLine = marker.line
            appliedID = marker.id
        }
        guard shouldNavigate else { return }
        textView.window?.makeFirstResponder(textView)
        textView.setSelectedRange(marker.selectionRange)
        textView.scrollRangeToVisible(marker.selectionRange)
    }
}
