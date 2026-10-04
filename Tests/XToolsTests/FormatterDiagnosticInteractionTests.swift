import AppKit
import SwiftUI
import Testing
@testable import XTools
@testable import XToolsCore

@MainActor
struct FormatterDiagnosticInteractionTests {
    @Test func markerProjectsUTF16AndFallsBackToLineWithoutGuessingColumns() throws {
        let input = "👩‍💻e\u{301}\r\nlast"
        let lineOnly = try #require(IndexTextAreaDiagnosticMarker(
            diagnostic: FormatDiagnostic(formatName: "XML", message: "invalid", line: 2, column: 99),
            sourceText: input
        ))
        #expect(lineOnly.selectionRange == NSRange(location: 9, length: 0))
        #expect(lineOnly.decorationRange == nil)
        #expect(IndexTextAreaDiagnosticMarker(
            diagnostic: FormatDiagnostic(formatName: "XML", message: "invalid", line: 3),
            sourceText: input
        ) == nil)
        let sql = "\r\nSELECT '👩‍💻e\u{301}', (1"
        let failure = FormatRunner.run(sql) { try SQLFormatting.format($0) }
        guard case .failed(let diagnostic) = failure else {
            Issue.record("Expected SQL error"); return
        }
        let marker = try #require(IndexTextAreaDiagnosticMarker(diagnostic: diagnostic, sourceText: sql))
        #expect(marker.selectionRange == (sql as NSString).range(of: "("))
        #expect(marker.line == 2)
    }

    @Test func decorationAndExplicitNavigationPreserveUndoAndNeverMutateText() throws {
        let (window, editor, gutter) = editorFixture()
        editor.string = "first\n👩‍💻 wrong"
        editor.setSelectedRange(NSRange(location: 0, length: 0))
        editor.testUndo.registerUndo(withTarget: editor) { _ in }
        let controller = IndexTextAreaDiagnosticController()
        let range = (editor.string as NSString).range(of: "wrong")
        let marker = try #require(IndexTextAreaDiagnosticMarker(
            diagnostic: FormatDiagnostic(formatName: "JSON", message: "invalid", line: 2, sourceUTF16Range: range),
            sourceText: editor.string
        ))
        let original = editor.string
        controller.update(marker, requestToken: 0, in: editor, gutter: gutter)
        #expect(editor.selectedRange() == NSRange(location: 0, length: 0))
        #expect(gutter.diagnosticLine == 2)
        #expect(editor.layoutManager?.temporaryAttribute(.underlineStyle, atCharacterIndex: range.location, effectiveRange: nil) != nil)
        #expect(editor.textStorage?.attribute(.underlineStyle, at: range.location, effectiveRange: nil) == nil)
        controller.update(marker, requestToken: 1, in: editor, gutter: gutter)
        #expect(editor.selectedRange() == range)
        #expect(window.firstResponder === editor)
        #expect(editor.testUndo.canUndo)
        #expect(editor.string.utf8.elementsEqual(original.utf8))
    }

    @Test func staleCanonicalEquivalentSourceAndIMECannotDecorateOrNavigate() throws {
        let (_, editor, gutter) = editorFixture()
        editor.string = "café"
        let controller = IndexTextAreaDiagnosticController()
        let marker = try #require(IndexTextAreaDiagnosticMarker(
            diagnostic: FormatDiagnostic(formatName: "JSON", message: "invalid", line: 1, sourceUTF16Range: NSRange(location: 0, length: 1)),
            sourceText: editor.string
        ))
        controller.update(marker, requestToken: 0, in: editor, gutter: gutter)
        editor.reportsMarkedText = true
        controller.update(marker, requestToken: 1, in: editor, gutter: gutter)
        #expect(gutter.diagnosticLine == nil)
        #expect(editor.layoutManager?.temporaryAttribute(.underlineStyle, atCharacterIndex: 0, effectiveRange: nil) == nil)
        editor.reportsMarkedText = false
        editor.string = "cafe\u{301}"
        editor.setSelectedRange(NSRange(location: 5, length: 0))
        controller.update(marker, requestToken: 1, in: editor, gutter: gutter)
        #expect(editor.selectedRange() == NSRange(location: 5, length: 0))
        #expect(gutter.diagnosticLine == nil)
    }

    @Test func terminalEmptyLineUsesNativeGeometryAndKeepsEOFNavigationExact() throws {
        for newline in ["\n", "\r\n", "\r"] {
            let (_, editor, gutter) = editorFixture()
            editor.string = "first" + newline + "👩‍💻" + newline
            editor.layoutManager?.ensureLayout(for: try #require(editor.textContainer))
            let terminal = try #require(gutter.terminalLineNumberFragment())
            #expect(terminal.line == 3)
            let manager = try #require(editor.layoutManager)
            #expect(terminal.rect.minY == manager.extraLineFragmentRect.minY + editor.textContainerOrigin.y)
            let marker = try #require(IndexTextAreaDiagnosticMarker(
                diagnostic: FormatDiagnostic(formatName: "JSON", message: "invalid", line: 3),
                sourceText: editor.string
            ))
            let original = editor.string
            let controller = IndexTextAreaDiagnosticController()
            controller.update(marker, requestToken: 1, in: editor, gutter: gutter)
            #expect(gutter.diagnosticLine == terminal.line)
            #expect(editor.selectedRange() == NSRange(location: (original as NSString).length, length: 0))
            #expect(editor.string.utf8.elementsEqual(original.utf8))
        }
    }

    @Test func rejectedNavigationIsNotDeferredOntoANewDiagnostic() throws {
        let (_, editor, gutter) = editorFixture()
        editor.string = "abc"
        let controller = IndexTextAreaDiagnosticController()
        let diagnostic = FormatDiagnostic(formatName: "JSON", message: "invalid", line: 1,
                                          sourceUTF16Range: NSRange(location: 0, length: 1))
        let marker = try #require(IndexTextAreaDiagnosticMarker(diagnostic: diagnostic, sourceText: editor.string))
        editor.setSelectedRange(NSRange(location: 3, length: 0))
        editor.reportsMarkedText = true
        controller.update(marker, requestToken: 1, in: editor, gutter: gutter)
        editor.reportsMarkedText = false
        let newer = try #require(IndexTextAreaDiagnosticMarker(diagnostic: diagnostic, sourceText: editor.string))
        controller.update(newer, requestToken: 1, in: editor, gutter: gutter)
        #expect(editor.selectedRange() == NSRange(location: 3, length: 0))
        controller.update(newer, requestToken: 2, in: editor, gutter: gutter)
        #expect(editor.selectedRange() == NSRange(location: 0, length: 1))
    }

    @Test func realCoordinatorEditClearsMarkerBeforePublishingNewInput() throws {
        let (_, editor, gutter) = editorFixture()
        editor.string = "abc"
        let coordinator = IndexUndoableTextView.Coordinator(
            text: Binding(get: { "abc" }, set: { _ in
                #expect(gutter.diagnosticLine == nil)
                #expect(editor.layoutManager?.temporaryAttribute(.underlineStyle, atCharacterIndex: 0, effectiveRange: nil) == nil)
            }), measuredHeight: .constant(0), growsWithContent: false, inputPolicy: nil
        )
        coordinator.lineNumberGutter = gutter
        let marker = try #require(IndexTextAreaDiagnosticMarker(
            diagnostic: FormatDiagnostic(formatName: "JSON", message: "invalid", line: 1, sourceUTF16Range: NSRange(location: 0, length: 1)), sourceText: editor.string
        ))
        coordinator.diagnosticController.update(marker, requestToken: 0, in: editor, gutter: gutter)
        #expect(gutter.diagnosticLine == 1)
        editor.string = "abcd"
        coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: editor))
        #expect(gutter.diagnosticLine == nil)
    }

    @Test func sourceRevisionClearsMarkerAndUnmappedDecodedJSONNeverGetsOne() async throws {
        let session = IndexFormatExecutionSession()
        session.schedule(snapshot: "{", sourceText: "{", delay: .zero) { input in
            FormatRunner.run(input) { try JSONFormatting.minify($0) }.binding(text: { $0 })
        }
        try await waitUntil { !session.isRunning }
        #expect(session.diagnosticMarker != nil)
        session.sourceDidChange()
        #expect(session.diagnosticMarker == nil)
        session.schedule(snapshot: "\n{", delay: .zero) { input in
            FormatRunner.run(input) { try JSONFormatting.minify($0) }.binding(text: { $0 })
        }
        try await waitUntil { !session.isRunning }
        #expect(session.diagnostic != nil)
        #expect(session.diagnosticMarker == nil)
    }

    @Test func safeDetailsAreBoundedCopyableAndExcludeSourceExcerpt() {
        let diagnostic = FormatDiagnostic(formatName: "JSON", message: "错误", line: 1,
            excerpt: "PRIVATE_SENTINEL", details: (0..<257).map { "安全提示\($0)" })
        let presentation = IndexDiagnosticPresentation(diagnostic: diagnostic, message: diagnostic.message)
        #expect(presentation.details.count == 257)
        #expect(presentation.copyPayload.contains("安全提示256"))
        #expect(!presentation.copyPayload.contains("PRIVATE_SENTINEL"))
        let overflowing = IndexDiagnosticPresentation(diagnostic: .init(formatName: "", message: "",
            details: Array(repeating: String(repeating: "x", count: 2_000), count: 300)), message: "warning")
        #expect(overflowing.details.count == 257)
        #expect(overflowing.details.allSatisfy { $0.count == 513 })
        #expect(overflowing.omittedCount == 43)
    }

    @Test func hostedWorkbenchCollapsesAbsentDiagnosticAndKeepsEditorIdentity() async throws {
        let model = DiagnosticLayoutProbeModel()
        let hosting = NSHostingView(rootView: DiagnosticLayoutProbe(model: model))
        hosting.frame = NSRect(x: 0, y: 0, width: 1000, height: 500)
        hosting.layoutSubtreeIfNeeded()
        let editor = try #require(findEditor(hosting))
        let viewport = try #require(editor.enclosingScrollView)
        let originalFrame = viewport.convert(viewport.bounds, to: hosting)
        let originalText = editor.string
        let originalUndoManager = editor.undoManager
        editor.setSelectedRange(NSRange(location: 1, length: 2))
        // The toolbar is 44pt; only the normal 8pt pane inset may follow it.
        let topInset = hosting.isFlipped ? originalFrame.minY : hosting.bounds.maxY - originalFrame.maxY
        #expect(abs(topInset - 52) < 0.5, "No diagnostic must leave no reserved status row")
        for message in ["输入有误", String(repeating: "很长的错误消息", count: 100), ""] {
            model.message = message
            try await Task.sleep(for: .milliseconds(60))
            hosting.layoutSubtreeIfNeeded()
            #expect(findEditor(hosting) === editor)
            let frame = viewport.convert(viewport.bounds, to: hosting)
            let expectedHeight = originalFrame.height - (message.isEmpty ? 0 : 36)
            #expect(abs(frame.height - expectedHeight) < 0.5)
            #expect(frame.minX == originalFrame.minX && frame.width == originalFrame.width)
            if message.isEmpty { #expect(frame == originalFrame) }
            #expect(editor.string == originalText)
            #expect(editor.selectedRange() == NSRange(location: 1, length: 2))
            #expect(editor.undoManager === originalUndoManager)
        }
    }

    private func editorFixture() -> (NSWindow, DiagnosticTestTextView, IndexEditorLineNumberGutterView) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 240), styleMask: [.titled], backing: .buffered, defer: false)
        let scroll = NSScrollView(frame: window.contentView!.bounds)
        let editor = DiagnosticTestTextView(frame: scroll.bounds)
        scroll.documentView = editor
        window.contentView = scroll
        return (window, editor, IndexEditorLineNumberGutterView(scrollView: scroll, textView: editor))
    }

    private func findEditor(_ view: NSView) -> NSTextView? {
        if let editor = view as? NSTextView, editor.isEditable { return editor }
        return view.subviews.lazy.compactMap { findEditor($0) }.first
    }
}

@MainActor private final class DiagnosticTestTextView: NSTextView {
    let testUndo = UndoManager()
    var reportsMarkedText = false
    override var undoManager: UndoManager? { testUndo }
    override func hasMarkedText() -> Bool { reportsMarkedText }
}

@MainActor private final class DiagnosticLayoutProbeModel: ObservableObject {
    @Published var input = "draft"
    @Published var message = ""
}

private struct DiagnosticLayoutProbe: View {
    @ObservedObject var model: DiagnosticLayoutProbeModel
    var body: some View {
        IndexFormatWorkbench(inputTitle: "输入", outputTitle: "输出", input: $model.input,
                             output: "result", diagnostic: model.message.isEmpty ? nil : model.message,
                             autoFocus: false, onClear: {})
            .transaction { $0.disablesAnimations = true }
    }
}
