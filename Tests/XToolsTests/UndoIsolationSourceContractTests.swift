import Foundation
@testable import XTools
import Testing

/// Guards the ADR-0022 invariant: every editable text surface resolves undo to a
/// private, instance-scoped UndoManager and never falls back to the shared
/// window manager (the source of the ⌘Z use-after-free crash). These are source
/// contracts because the failure mode is a lifecycle/ownership shape that can't
/// be exercised through the non-instantiable AppKit view hierarchy in tests.
struct UndoIsolationSourceContractTests {
    @Test func multilineTextViewsAlwaysVendPrivateUndoManager() throws {
        let source = try readSource("Sources/XTools/ToolPages/Workbench/Text/IndexTextComponents.swift")

        // Both multi-line coordinators (TextKit2 + measured) must return the
        // private manager unconditionally — not only when a policy sets levels.
        contains(
            source,
            "func undoManager(for view: NSTextView) -> UndoManager? {\n            privateUndo.manager\n        }",
            "Multi-line coordinators must vend the private undo manager unconditionally, never returning nil (which resolves to the shared window manager)"
        )
        doesNotContain(
            source,
            "guard inputPolicy?.undoLevels != nil else { return nil }",
            "Multi-line undo resolution must not fall back to the shared window manager when no undo level policy is set"
        )

        // Unbounded-by-default, policy caps depth. levelsOfUndo == 0 means "no
        // limit" (undo stays fully functional), so the nil branch keeps undo on.
        contains(
            source,
            "privateUndo.configureLevels(inputPolicy?.undoLevels)",
            "Undo depth must stay unbounded by default and only be capped by an explicit policy"
        )
    }

    @Test func singleLineFieldEditorsOwnPrivateUndoManager() throws {
        let components = try readSource("Sources/XTools/ToolPages/Workbench/Text/IndexTextComponents.swift")
        let segment = try readSource("Sources/XTools/ToolPages/Workbench/Controls/IndexControlledSegmentInput.swift")
        let geometry = try readSource("Sources/XTools/Shared/Components/AppKitTextFieldGeometry.swift")

        // The caret field editor isolates undo only in its single-line field
        // editor role; as a multi-line document view the delegate takes over.
        contains(
            components,
            "override var undoManager: UndoManager? {\n        isFieldEditor ? fieldEditorUndo.manager : super.undoManager\n    }",
            "IndexCaretTextView must own a private undo stack when acting as a single-line field editor"
        )

        contains(
            segment,
            "override var undoManager: UndoManager? { boundedUndoManager }",
            "The segment field editor must own a private undo stack"
        )

        // Plain fields (sidebar / command-palette search) use the base cell,
        // which must vend an undo-isolated field editor.
        contains(
            geometry,
            "final class IndexUndoIsolatedFieldEditor: NSTextView",
            "The base padded field cell must have a private-undo field editor for plain search fields"
        )
        contains(
            geometry,
            "override var undoManager: UndoManager? { boundedUndoManager }",
            "The base field editor must resolve undo to its private manager"
        )
        contains(
            geometry,
            "override func fieldEditor(for controlView: NSView) -> NSTextView?",
            "The base padded field cell must vend the undo-isolated field editor"
        )

        contains(
            geometry,
            "private let secureUndoManager = UndoManager()",
            "Secure fields must own an undo manager whose lifetime matches the field instance"
        )
        contains(
            geometry,
            "@objc(undoManagerForTextView:)\n    func undoManager(for view: NSTextView) -> UndoManager?",
            "Secure fields must use AppKit's official delegate hook without replacing NSSecureTextView"
        )
        contains(
            geometry,
            "func setStringFromExternalBinding(_ newValue: String)",
            "Secure external binding replacement must have an explicit new-baseline path"
        )
    }

    @Test func diffWorkspaceVendsPerSidePrivateUndoManagers() throws {
        let source = try readSource("Sources/XTools/ToolPages/Workbench/Diff/IndexEditableDiffWorkspace.swift")

        contains(
            source,
            "func undoManager(for view: NSTextView) -> UndoManager? {",
            "The diff coordinator must vend a delegate-scoped undo manager for each pane"
        )
        contains(
            source,
            "if view === rightTextView { return rightUndo.manager }",
            "The diff coordinator must route each pane's undo to its own private manager"
        )
        // Diff keeps its own selection-preserving write path, but delegates the
        // undo baseline transition to the shared NSTextView helper.
        contains(
            source,
            "textView.setStringWithoutUndoRegistration(text)",
            "Diff programmatic text writes must reuse the shared undo-baseline helper"
        )
        contains(
            source,
            "defer { isApplyingProgrammaticText = false }",
            "Diff programmatic text writes must always restore the binding-suppression flag"
        )
    }

    @Test func programmaticTextResetsSkipUndoRegistration() throws {
        let source = try readSource("Sources/XTools/ToolPages/Workbench/Text/IndexTextComponents.swift")

        contains(
            source,
            "func setStringWithoutUndoRegistration(_ newValue: String)",
            "A shared helper must assign text without pushing onto the undo stack"
        )
        contains(
            source,
            "manager?.disableUndoRegistration()",
            "Programmatic text sync must disable undo registration around the assignment"
        )
        contains(
            source,
            "manager?.removeAllActions()",
            "Programmatic replacement must discard undo and redo actions that describe the previous text buffer"
        )
        contains(
            source,
            "secureTextField.setStringFromExternalBinding(text)",
            "Secure binding updates must clear the field-owned history after external replacement"
        )
        // No raw `textView.string = text` should remain on the editable paths —
        // every programmatic write goes through the undo-suppressing helper.
        doesNotContain(
            source,
            "textView.string = text\n",
            "Editable multi-line views must route programmatic writes through setStringWithoutUndoRegistration"
        )
    }
}
