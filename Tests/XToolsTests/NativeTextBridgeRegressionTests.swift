import AppKit
import SwiftUI
import Testing
@testable import XTools
import XToolsCore

@MainActor
@Suite(.serialized)
struct NativeTextBridgeRegressionTests {
    @Test func singleLineBridgePreservesCanonicalEquivalentBytesInBothDirections() async throws {
        var text = "é"
        let binding = Binding(get: { text }, set: { text = $0 })
        let host = NSHostingView(rootView: IndexTextInput(placeholder: "", text: binding))
        let window = makeWindow(host)
        defer { window.close() }
        await settle(host)
        let field = try #require(descendant(NSTextField.self, in: host))
        text = "e\u{301}"
        host.rootView = IndexTextInput(placeholder: "", text: binding)
        await settle(host)
        #expect(descendant(NSTextField.self, in: host) === field)
        #expect(field.stringValue.utf8.elementsEqual(text.utf8))

        field.stringValue = "é"
        field.delegate?.controlTextDidChange?(Notification(name: NSControl.textDidChangeNotification, object: field))
        #expect(text.utf8.elementsEqual("é".utf8))
    }

    @Test func workspaceScrollRequestReachesNativeViewportWithoutChangingSelection() async throws {
        let text = (0..<250).map { "line \($0)" }.joined(separator: "\n")
        let host = NSHostingView(rootView: IndexWorkspaceTextArea(
            placeholder: "", text: .constant(text), minHeight: 180,
            inputRenderingMode: .measuredContent
        ))
        let window = makeWindow(host)
        defer { window.close() }
        await settle(host)
        let editor = try #require(descendant(NSTextView.self, in: host))
        let scrollView = try #require(editor.enclosingScrollView)
        editor.setSelectedRange(NSRange(location: 0, length: 0))
        scrollView.contentView.scroll(to: .zero)
        let before = scrollView.contentView.bounds.origin.y
        host.rootView = IndexWorkspaceTextArea(
            placeholder: "", text: .constant(text), minHeight: 180,
            scrollRequest: IndexTextAreaScrollRequest(token: 1, utf16Range: NSRange(location: (text as NSString).length - 8, length: 8)),
            inputRenderingMode: .measuredContent
        )
        await settle(host)
        #expect(scrollView.contentView.bounds.origin.y > before + 100)
        #expect(editor.selectedRange() == NSRange(location: 0, length: 0))
        #expect(editor.string.utf8.elementsEqual(text.utf8))
    }

    @Test func singleLineAutoFocusPlacesCaretAtUTF16End() async throws {
        let text = "👩🏽‍💻e\u{301}"
        let host = NSHostingView(rootView: IndexTextInput(placeholder: "", text: .constant(text), autoFocus: true)
            .environment(\.toolPageEntryGeneration, 1))
        let window = makeWindow(host)
        defer { window.close() }
        await settle(host)
        let field = try #require(descendant(NSTextField.self, in: host))
        let editor = try #require(field.currentEditor())
        #expect(editor.selectedRange == NSRange(location: (text as NSString).length, length: 0))
    }

    @Test func manuallyFocusedDateInputReleasesEditorWhenParked() async throws {
        var input = ControlledDateInput(components: DateOnlyComponents(year: 2026, month: 10, day: 11))
        let binding = Binding(get: { input }, set: { input = $0 })
        func root(_ generation: Int) -> some View {
            IndexControlledDateInput(input: binding, placeholder: "", onCommit: { _ in }, onInvalidPaste: {})
                .environment(\.toolPageEntryGeneration, generation)
        }
        let host = NSHostingView(rootView: root(1))
        let window = makeWindow(host)
        defer { window.close() }
        await settle(host)
        let field = try #require(descendant(IndexControlledSegmentNSTextField.self, in: host))
        try #require(window.makeFirstResponder(field))
        try #require(field.currentEditor() != nil)
        host.rootView = root(0)
        await settle(host)
        #expect(field.currentEditor() == nil)
        #expect(input.components == DateOnlyComponents(year: 2026, month: 10, day: 11))
    }

    @Test func dateInputPasteRequiresAnActivePageAndItsOwnFocusedEditor() async throws {
        var input = ControlledDateInput(components: DateOnlyComponents(year: 2026, month: 10, day: 11))
        var otherText = "other editor"
        var committedDates: [Date] = []
        let binding = Binding(get: { input }, set: { input = $0 })
        let otherBinding = Binding(get: { otherText }, set: { otherText = $0 })
        func root(_ generation: Int) -> some View {
            VStack {
                IndexControlledDateInput(input: binding, placeholder: "", onCommit: { committedDates.append($0) }, onInvalidPaste: {})
                    .environment(\.toolPageEntryGeneration, generation)
                IndexTextInput(placeholder: "", text: otherBinding)
            }
        }
        let host = NSHostingView(rootView: root(1))
        let window = makeWindow(host)
        defer { window.close() }
        await settle(host)
        let field = try #require(descendant(IndexControlledSegmentNSTextField.self, in: host))
        let otherField = try #require(descendants(NSTextField.self, in: host).first { !($0 is IndexControlledSegmentNSTextField) })
        try #require(window.makeFirstResponder(field))
        let previousEditor = try #require(field.currentEditor() as? IndexControlledSegmentFieldEditor)
        let pasteboard = NSPasteboard.general
        let originalItems = pasteboard.pasteboardItems?.map { item in
            item.types.compactMap { type in item.data(forType: type).map { (type, $0) } }
        } ?? []
        defer {
            pasteboard.clearContents()
            let items = originalItems.map { values in
                let item = NSPasteboardItem()
                for (type, data) in values { item.setData(data, forType: type) }
                return item
            }
            pasteboard.writeObjects(items)
        }
        let commandV = try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: .command,
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
            context: nil, characters: "v", charactersIgnoringModifiers: "v", isARepeat: false, keyCode: 9
        ))
        pasteboard.clearContents()
        pasteboard.setString("2025/09/08", forType: .string)
        #expect(field.performKeyEquivalent(with: commandV))
        #expect(input.components == DateOnlyComponents(year: 2025, month: 9, day: 8))
        let acceptedCommitCount = committedDates.count
        #expect(acceptedCommitCount > 0)

        try #require(window.makeFirstResponder(otherField))
        let otherEditor = try #require(otherField.currentEditor())
        pasteboard.clearContents()
        pasteboard.setString("2024/01/02", forType: .string)
        // An active but unfocused field must also decline the window's shortcut traversal.
        #expect(!field.performKeyEquivalent(with: commandV))
        field.paste(nil)
        #expect(!previousEditor.performKeyEquivalent(with: commandV))
        previousEditor.paste(nil)
        #expect(input.components == DateOnlyComponents(year: 2025, month: 9, day: 8))

        host.rootView = root(0)
        await settle(host)
        #expect(descendant(IndexControlledSegmentNSTextField.self, in: host) === field)
        #expect(window.firstResponder === otherEditor)
        let commitsBeforeHiddenPaste = committedDates.count
        #expect(!field.performKeyEquivalent(with: commandV))
        field.paste(nil)
        #expect(!previousEditor.performKeyEquivalent(with: commandV))
        previousEditor.paste(nil)
        #expect(input.components == DateOnlyComponents(year: 2025, month: 9, day: 8))
        #expect(committedDates.count == commitsBeforeHiddenPaste)
        #expect(window.firstResponder === otherEditor)
        #expect(otherText == "other editor")
    }

    private func makeWindow<V: View>(_ host: NSHostingView<V>) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 220), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        return window
    }

    private func settle(_ view: NSView) async {
        for _ in 0..<5 {
            view.layoutSubtreeIfNeeded()
            try? await Task.sleep(for: .milliseconds(20))
        }
    }

    private func descendant<T: NSView>(_ type: T.Type, in view: NSView) -> T? {
        if let match = view as? T { return match }
        return view.subviews.lazy.compactMap { descendant(type, in: $0) }.first
    }

    private func descendants<T: NSView>(_ type: T.Type, in view: NSView) -> [T] {
        (view as? T).map { [$0] } ?? view.subviews.flatMap { descendants(type, in: $0) }
    }
}
