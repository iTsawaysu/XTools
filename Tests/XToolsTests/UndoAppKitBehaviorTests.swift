import AppKit
import SwiftUI
import Testing
@testable import XTools
@testable import XToolsCore

@MainActor
struct UndoAppKitBehaviorTests {
    @Test func applicationActionsExecuteCurrentManagerAndAreSafeAtStackEdges() throws {
        let text = MutableUndoTestValue("")
        let coordinator = IndexUndoableTextView.Coordinator(
            text: binding(to: text),
            measuredHeight: binding(to: MutableUndoTestHeight(0)),
            growsWithContent: false,
            inputPolicy: nil
        )
        let textView = IndexCaretTextView(frame: NSRect(x: 0, y: 0, width: 320, height: 120))
        textView.delegate = coordinator
        configureForUndo(textView)

        let window = makeWindow(containing: textView)
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }
        #expect(window.makeFirstResponder(textView))

        insertUserText("abcdef", in: textView)
        textView.deleteBackward(nil)
        textView.breakUndoCoalescing()
        #expect(textView.string == "abcde")

        let manager = try #require(textView.undoManager)
        #expect(window.firstResponder === textView)
        #expect(AppKitUndoCommandRouter.perform(.undo, in: window))
        #expect(textView.string != "abcde")

        // Repeated menu actions must remain harmless at the bottom/top of the
        // native stack, matching the user's continuous shortcut sequence.
        for _ in 0..<12 {
            _ = AppKitUndoCommandRouter.perform(.undo, in: window)
        }
        #expect(textView.string.isEmpty)

        #expect(textView.undoManager === manager)
        for _ in 0..<12 {
            _ = AppKitUndoCommandRouter.perform(.redo, in: window)
        }
        #expect(textView.string == "abcde")
    }

    @Test func currentMultilineManagerStaysIsolatedAfterOldEditorTeardown() throws {
        let window = makeWindow()
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }

        var oldManager: UndoManager?
        do {
            let state = MutableUndoTestValue("")
            var coordinator: IndexUndoableTextView.Coordinator? = IndexUndoableTextView.Coordinator(
                text: binding(to: state),
                measuredHeight: binding(to: MutableUndoTestHeight(0)),
                growsWithContent: false,
                inputPolicy: nil
            )
            var textView: IndexCaretTextView? = IndexCaretTextView(frame: NSRect(x: 0, y: 0, width: 320, height: 120))
            textView?.delegate = coordinator
            let activeTextView = try #require(textView)
            configureForUndo(activeTextView)
            window.contentView?.addSubview(activeTextView)
            #expect(window.makeFirstResponder(activeTextView))
            insertUserText("old editor", in: activeTextView)
            oldManager = activeTextView.undoManager
            #expect(oldManager?.canUndo == true)

            window.makeFirstResponder(nil)
            textView?.delegate = nil
            textView?.removeFromSuperview()
            textView = nil
            coordinator = nil
        }

        let currentState = MutableUndoTestValue("")
        let currentCoordinator = IndexUndoableTextView.Coordinator(
            text: binding(to: currentState),
            measuredHeight: binding(to: MutableUndoTestHeight(0)),
            growsWithContent: false,
            inputPolicy: nil
        )
        let currentTextView = IndexCaretTextView(frame: NSRect(x: 0, y: 0, width: 320, height: 120))
        currentTextView.delegate = currentCoordinator
        configureForUndo(currentTextView)
        window.contentView?.addSubview(currentTextView)
        #expect(window.makeFirstResponder(currentTextView))
        insertUserText("current", in: currentTextView)
        let currentManager = try #require(currentTextView.undoManager)
        #expect(currentManager !== oldManager)

        for _ in 0..<12 {
            _ = AppKitUndoCommandRouter.perform(.undo, in: window)
        }
        #expect(currentTextView.string.isEmpty)
        for _ in 0..<12 {
            _ = AppKitUndoCommandRouter.perform(.redo, in: window)
        }
        #expect(currentTextView.string == "current")
        #expect(oldManager?.canUndo == true)
    }

    @Test func currentSecureManagerStaysIsolatedAfterOldFieldTeardown() throws {
        let window = makeWindow()
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }

        var oldManager: UndoManager?
        do {
            var field: IndexPaddedSecureTextField? = IndexPaddedSecureTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 30))
            let activeField = try #require(field)
            window.contentView?.addSubview(activeField)
            #expect(window.makeFirstResponder(activeField))
            let editor = try #require(activeField.currentEditor() as? NSTextView)
            AppKitTextEditingConfiguration.configureCurrentFieldEditor(for: activeField)
            insertUserText("old secret", in: editor)
            oldManager = editor.undoManager
            #expect(oldManager?.canUndo == true)

            window.makeFirstResponder(nil)
            field?.removeFromSuperview()
            field = nil
        }

        let currentField = IndexPaddedSecureTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 30))
        window.contentView?.addSubview(currentField)
        #expect(window.makeFirstResponder(currentField))
        let currentEditor = try #require(currentField.currentEditor() as? NSTextView)
        AppKitTextEditingConfiguration.configureCurrentFieldEditor(for: currentField)
        insertUserText("current secret", in: currentEditor)
        let currentManager = try #require(currentEditor.undoManager)
        #expect(currentManager !== oldManager)

        for _ in 0..<12 {
            _ = AppKitUndoCommandRouter.perform(.undo, in: window)
        }
        #expect(currentField.stringValue.isEmpty)
        for _ in 0..<12 {
            _ = AppKitUndoCommandRouter.perform(.redo, in: window)
        }
        #expect(currentField.stringValue == "current secret")
        #expect(oldManager?.canUndo == true)
    }

    @Test func secureFieldsKeepIndependentUndoHistoriesAcrossSharedEditors() throws {
        let first = IndexPaddedSecureTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 30))
        let second = IndexPaddedSecureTextField(frame: NSRect(x: 0, y: 40, width: 240, height: 30))
        let window = makeWindow(containing: first, second)

        #expect(window.makeFirstResponder(first))
        let firstEditor = try #require(first.currentEditor() as? NSTextView)
        AppKitTextEditingConfiguration.configureCurrentFieldEditor(for: first)
        let firstManager = try #require(firstEditor.undoManager)
        insertUserText("abcdef", in: firstEditor)
        #expect(firstManager.canUndo)

        firstManager.undo()
        #expect(firstManager.canRedo)

        #expect(window.makeFirstResponder(second))
        let secondEditor = try #require(second.currentEditor() as? NSTextView)
        AppKitTextEditingConfiguration.configureCurrentFieldEditor(for: second)
        let secondManager = try #require(secondEditor.undoManager)
        #expect(firstManager !== secondManager)
        #expect(!secondManager.canUndo)

        // Simulate an external Binding update while field A is unfocused. Its
        // old action includes a redo range in the previous secure buffer.
        first.setStringFromExternalBinding("x")
        #expect(first.stringValue == "x")
        #expect(!firstManager.canUndo)
        #expect(!firstManager.canRedo)

        #expect(window.makeFirstResponder(first))
        let refocusedEditor = try #require(first.currentEditor() as? NSTextView)
        #expect(refocusedEditor.undoManager === firstManager)
        #expect(!refocusedEditor.undoManager!.canUndo)
        #expect(!refocusedEditor.undoManager!.canRedo)
    }

    @Test func plainFieldEditorsKeepUndoLocalToTheirOwner() throws {
        let first = IndexCaretTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 30))
        let second = IndexPaddedTextField(frame: NSRect(x: 0, y: 40, width: 240, height: 30))
        let window = makeWindow(containing: first, second)

        #expect(window.makeFirstResponder(first))
        let firstEditor = try #require(first.currentEditor() as? NSTextView)
        AppKitTextEditingConfiguration.configureCurrentFieldEditor(for: first)
        let firstManager = try #require(firstEditor.undoManager)
        insertUserText("first", in: firstEditor)
        #expect(firstManager.canUndo)

        #expect(window.makeFirstResponder(second))
        let secondEditor = try #require(second.currentEditor() as? NSTextView)
        AppKitTextEditingConfiguration.configureCurrentFieldEditor(for: second)
        let secondManager = try #require(secondEditor.undoManager)
        insertUserText("second", in: secondEditor)
        #expect(secondManager.canUndo)
        #expect(firstManager !== secondManager)

        secondManager.undo()
        #expect(secondEditor.string.isEmpty)
        #expect(first.stringValue == "first")
    }

    @Test func plainSearchFieldExternalReplacementReentersWithCleanHistory() throws {
        let searchField = IndexPaddedTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 30))
        let otherField = IndexPaddedTextField(frame: NSRect(x: 0, y: 40, width: 240, height: 30))
        let window = makeWindow(containing: searchField, otherField)

        #expect(window.makeFirstResponder(searchField))
        let editor = try #require(searchField.currentEditor() as? NSTextView)
        AppKitTextEditingConfiguration.configureCurrentFieldEditor(for: searchField)
        let manager = try #require(editor.undoManager)
        insertUserText("abcdef", in: editor)
        #expect(manager.canUndo)

        #expect(window.makeFirstResponder(otherField))
        searchField.stringValue = "x"
        #expect(window.makeFirstResponder(searchField))
        let refocusedEditor = try #require(searchField.currentEditor() as? NSTextView)

        #expect(refocusedEditor.undoManager === manager)
        #expect(searchField.stringValue == "x")
        #expect(!manager.canUndo)
        #expect(!manager.canRedo)
    }

    @Test func segmentFieldEditorResolvesAPrivateManager() throws {
        let segment = IndexControlledSegmentNSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 30))
        let window = makeWindow(containing: segment)

        #expect(window.makeFirstResponder(segment))
        let editor = try #require(segment.currentEditor() as? NSTextView)
        AppKitTextEditingConfiguration.configureCurrentFieldEditor(for: segment)
        let manager = try #require(editor.undoManager)
        insertUserText("segment", in: editor)

        #expect(manager.canUndo)
        #expect(editor.undoManager !== window.undoManager)
    }

    @Test func measuredTextViewTreatsProgrammaticReplacementAsNewUndoBaseline() throws {
        let text = MutableUndoTestValue("")
        let height = MutableUndoTestHeight(0)
        let coordinator = IndexUndoableTextView.Coordinator(
            text: binding(to: text),
            measuredHeight: binding(to: height),
            growsWithContent: false,
            inputPolicy: nil
        )
        let textView = IndexCaretTextView(frame: NSRect(x: 0, y: 0, width: 320, height: 120))
        textView.delegate = coordinator

        let window = makeWindow(containing: textView)
        try exerciseProgrammaticBaseline(in: textView, window: window)
    }

    @Test func textKit2ViewportTreatsProgrammaticReplacementAsNewUndoBaseline() throws {
        let text = MutableUndoTestValue("")
        let coordinator = IndexTextKit2ViewportTextView.Coordinator(
            text: binding(to: text),
            inputPolicy: nil
        )
        let textView = IndexTextKit2ViewportTextView.makeTextView()
        textView.frame = NSRect(x: 0, y: 0, width: 320, height: 120)
        textView.delegate = coordinator

        let window = makeWindow(containing: textView)
        try exerciseProgrammaticBaseline(in: textView, window: window)
    }

    @Test func textKit2ViewportPreservesBase64LargeInputUndoAndLimitPolicy() throws {
        let byteLimit = 1 * 1024 * 1024
        let baseText = String(repeating: "Undo-Base64-0123456789\n", count: 40_000)
        let text = MutableUndoTestValue(baseText)
        var rejection: IndexTextAreaInputRejection?
        let coordinator = IndexTextKit2ViewportTextView.Coordinator(
            text: binding(to: text),
            inputPolicy: .init(
                maxUTF8Bytes: byteLimit,
                undoLevels: 20,
                onRejectedInput: { rejection = $0 }
            )
        )
        let textView = IndexTextKit2ViewportTextView.makeTextView()
        textView.frame = NSRect(x: 0, y: 0, width: 320, height: 120)
        textView.delegate = coordinator
        configureForUndo(textView)
        textView.setStringWithoutUndoRegistration(baseText)
        textView.setSelectedRange(NSRange(location: (baseText as NSString).length, length: 0))

        let window = makeWindow(containing: textView)
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }
        #expect(window.makeFirstResponder(textView))
        let manager = try #require(textView.undoManager)
        #expect(manager.levelsOfUndo == 20)

        let overflow = String(repeating: "x", count: byteLimit - baseText.utf8.count + 1)
        insertUserText(overflow, in: textView)
        #expect(textView.string.utf8.count == 920_000)
        #expect(text.value.utf8.count == 920_000)
        #expect(rejection?.maxUTF8Bytes == byteLimit)
        #expect(rejection?.attemptedUTF8Bytes == byteLimit + 1)

        insertUserText("tail", in: textView)
        #expect(textView.string.utf8.count == 920_004)
        #expect(textView.string.hasSuffix("tail"))
        #expect(text.value.utf8.count == 920_004)
        #expect(text.value.hasSuffix("tail"))

        #expect(AppKitUndoCommandRouter.perform(.undo, in: window))
        drainAppKitNotifications()
        #expect(textView.string.utf8.count == 920_000)

        #expect(AppKitUndoCommandRouter.perform(.redo, in: window))
        drainAppKitNotifications()
        #expect(textView.string.utf8.count == 920_004)
        #expect(textView.string.hasSuffix("tail"))
    }

    @Test func diffProgrammaticReplacementClearsOnlyTheReplacedPaneHistory() throws {
        let left = MutableUndoTestValue("")
        let right = MutableUndoTestValue("")
        let coordinator = IndexEditableDiffMergeView.Coordinator(
            left: binding(to: left),
            right: binding(to: right)
        )
        let leftPane = coordinator.makeEditor(side: .left, placeholder: "Left")
        let rightPane = coordinator.makeEditor(side: .right, placeholder: "Right")
        let leftTextView = try #require(textView(in: leftPane))
        let rightTextView = try #require(textView(in: rightPane))
        let window = makeWindow(containing: leftPane, rightPane)

        #expect(window.makeFirstResponder(leftTextView))
        insertUserText("abcdef", in: leftTextView)
        let leftManager = try #require(leftTextView.undoManager)
        let rightManager = try #require(rightTextView.undoManager)
        #expect(leftManager !== rightManager)
        #expect(leftManager.canUndo)

        #expect(window.makeFirstResponder(nil))
        coordinator.update(left: "x", right: "", rows: [], syntax: .plain, foldUnchanged: false)

        #expect(leftTextView.string == "x")
        #expect(!leftManager.canUndo)
        #expect(!leftManager.canRedo)
        #expect(!rightManager.canUndo)
        #expect(!rightManager.canRedo)
    }

    private func exerciseProgrammaticBaseline(in textView: NSTextView, window: NSWindow) throws {
        configureForUndo(textView)
        #expect(window.makeFirstResponder(textView))

        insertUserText("abcdef", in: textView)
        let manager = try #require(textView.undoManager)
        #expect(manager.canUndo)

        manager.undo()
        #expect(textView.string.isEmpty)
        #expect(manager.canRedo)

        manager.redo()
        #expect(textView.string == "abcdef")
        #expect(manager.canUndo)

        textView.setStringWithoutUndoRegistration("x")

        #expect(textView.string == "x")
        #expect(!manager.canUndo)
        #expect(!manager.canRedo)
    }

    private func configureForUndo(_ textView: NSTextView) {
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
    }

    private func insertUserText(_ text: String, in textView: NSTextView) {
        configureForUndo(textView)
        textView.insertText(text, replacementRange: textView.selectedRange())
        textView.breakUndoCoalescing()
    }

    private func drainAppKitNotifications() {
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
    }

    private func makeWindow(containing views: NSView...) -> NSWindow {
        _ = NSApplication.shared
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 300),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        for view in views {
            window.contentView?.addSubview(view)
        }
        return window
    }

    private func textView(in view: NSView) -> NSTextView? {
        if let scrollView = view as? NSScrollView,
           let textView = scrollView.documentView as? NSTextView {
            return textView
        }
        for subview in view.subviews {
            if let textView = textView(in: subview) {
                return textView
            }
        }
        return nil
    }

    private func binding(to value: MutableUndoTestValue) -> Binding<String> {
        Binding(get: { value.value }, set: { value.value = $0 })
    }

    private func binding(to value: MutableUndoTestHeight) -> Binding<CGFloat> {
        Binding(get: { value.value }, set: { value.value = $0 })
    }
}

@MainActor
private final class MutableUndoTestValue {
    var value: String

    init(_ value: String) {
        self.value = value
    }
}

@MainActor
private final class MutableUndoTestHeight {
    var value: CGFloat

    init(_ value: CGFloat) {
        self.value = value
    }
}
