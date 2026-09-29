import AppKit
import SwiftUI
import Testing
@testable import XTools
@testable import XToolsCore

struct FormatterReliabilityRegressionTests {
    @Test func sqlErrorsReferToOriginalWhitespaceAndUnicode() throws {
        for prefix in ["\n\n", "\r\n\r\n", " \t\n\n"] {
            let input = prefix + "SELECT '👩‍💻e\u{301}', (1"
            let diagnostic = try #require(failure(input) { try SQLFormatting.format($0) })
            #expect(diagnostic.line == 3)
            #expect(diagnostic.column == 14)
        }
    }

    @Test func xmlErrorsReferToOriginalLinesAfterTrimAndEncodingNormalization() throws {
        for prefix in ["\n\n", "\r\n\r\n", " \t\n\n"] {
            let input = prefix + "<?xml version=\"1.0\" encoding=\"UTF-16\"?>\n<root><item></root>"
            let diagnostic = try #require(failure(input) { try XMLFormatting.format($0) })
            #expect(diagnostic.line == 4)
        }
    }

    @Test func unclosedJSONDoesNotExposeDynamicKeysInPrimaryDiagnostic() throws {
        let sentinel = "SENSITIVE_SENTINEL_123"
        let input = "{\"\(sentinel)\": {"
        let diagnostic = try #require(failure(input) { try JSONFormatting.minify($0) })
        #expect(!diagnostic.message.contains(sentinel))
        #expect(!diagnostic.workspaceMessage.contains(sentinel))
        #expect(!(diagnostic.suggestion ?? "").contains(sentinel))
        #expect(diagnostic.line == 1)
    }

    private func failure(_ input: String, operation: (String) throws -> String) -> FormatDiagnostic? {
        if case .failed(let diagnostic) = FormatRunner.run(input, produce: operation) { return diagnostic }
        Issue.record("Expected invalid source to produce a diagnostic")
        return nil
    }
}

@MainActor
struct FormatterExactInputRegressionTests {
    @Test func allFormatterModelsInvalidateResultsForCanonicalEquivalentEdits() {
        let defaults = UserDefaults(suiteName: "FormatterExactInputRegressionTests.\(UUID())")!
        let repository = ToolWorkspaceRepository(defaults: defaults)
        let json = repository.model(for: JSONFormatterToolWorkspaceModel.key)
        let xml = repository.model(for: XMLFormatterToolWorkspaceModel.key)
        let sql = repository.model(for: SQLPrettifyToolWorkspaceModel.key)
        let yaml = repository.model(for: YAMLPrettifyToolWorkspaceModel.key)
        let pairs: [(IndexFormatExecutionSession, (String) -> Void)] = [
            (json.execution, { json.input = $0 }), (xml.execution, { xml.input = $0 }),
            (sql.execution, { sql.input = $0 }), (yaml.execution, { yaml.input = $0 })
        ]
        for (session, setInput) in pairs {
            for (before, after) in [("café", "cafe\u{301}"), ("cafe\u{301}", "café")] {
                setInput(before)
                session.invalidate(resetTo: FormatBinding(output: before))
                setInput(after)
                #expect(!session.isOutputFresh)
                #expect(session.hasStaleResult)
            }
        }
    }

    @Test func nativeEditsPublishExactUnicodeAndInvalidateFormatterOutput() {
        let repository = ToolWorkspaceRepository(defaults: UserDefaults(suiteName: "ExactNative.\(UUID())")!)
        let model = repository.model(for: JSONFormatterToolWorkspaceModel.key)
        let coordinator = IndexUndoableTextView.Coordinator(
            text: Binding(get: { model.input }, set: { model.input = $0 }),
            measuredHeight: .constant(0), growsWithContent: false, inputPolicy: nil
        )
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 500, height: 250))
        for (before, after) in [("café", "cafe\u{301}"), ("cafe\u{301}", "café")] {
            model.input = before
            model.execution.invalidate(resetTo: FormatBinding(output: before))
            textView.string = after
            coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: textView))
            #expect(model.input.utf8.elementsEqual(after.utf8))
            #expect(!model.execution.isOutputFresh)
        }
    }

    @Test func externalUnicodeUpdatesReuseNativeEditorAndDeliverExactBytes() async throws {
        let model = ExactInputProbeModel()
        let hosting = NSHostingView(rootView: ExactInputProbe(model: model))
        hosting.frame = NSRect(x: 0, y: 0, width: 640, height: 260)
        hosting.layoutSubtreeIfNeeded()
        let native = try #require(findEditor(hosting))
        for text in ["cafe\u{301}", "café"] {
            model.text = text
            for _ in 0..<40 {
                hosting.layoutSubtreeIfNeeded()
                if native.string.utf8.elementsEqual(text.utf8) { break }
                try await Task.sleep(for: .milliseconds(10))
            }
            #expect(native.string.utf8.elementsEqual(text.utf8))
            #expect(findEditor(hosting) === native)
        }
    }

    private func findEditor(_ view: NSView) -> NSTextView? {
        if let editor = view as? NSTextView { return editor }
        return view.subviews.lazy.compactMap { findEditor($0) }.first
    }
}

@MainActor private final class ExactInputProbeModel: ObservableObject {
    @Published var text = "café"
}

private struct ExactInputProbe: View {
    @ObservedObject var model: ExactInputProbeModel
    var body: some View {
        IndexWorkspaceTextArea(placeholder: "", text: $model.text, fillsHeight: true,
                               workspaceSemantic: .structuredEditorTransform)
    }
}
