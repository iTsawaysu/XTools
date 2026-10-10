import AppKit

@MainActor
enum AppKitTextEditingConfiguration {
    static func configurePlainTextEditor(_ textView: NSTextView, allowsUndo: Bool = true) {
        textView.allowsUndo = allowsUndo
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
    }

    static func configureCurrentFieldEditor(for textField: NSTextField, allowsUndo: Bool = true) {
        guard let fieldEditor = textField.currentEditor() as? NSTextView else { return }
        if !textField.drawsBackground {
            fieldEditor.drawsBackground = false
            fieldEditor.backgroundColor = NSColor.clear
        }
        configurePlainTextEditor(fieldEditor, allowsUndo: allowsUndo)
    }

    /// Borderless single-line body text field style shared by the controlled
    /// segment input and the undoable text input. Only `alignment` differs
    /// between call sites, so it stays a parameter.
    static func applyBorderlessBodyStyle(
        _ textField: NSTextField,
        placeholder: String,
        alignment: NSTextAlignment,
        contentInsets: IndexTextFieldContentInsets
    ) {
        textField.placeholderString = placeholder
        textField.font = .monospacedSystemFont(ofSize: 12.5, weight: .regular)
        textField.textColor = .labelColor
        textField.alignment = alignment
        textField.isEditable = true
        textField.isSelectable = true
        textField.isBordered = false
        textField.isBezeled = false
        textField.drawsBackground = false
        textField.focusRingType = .none
        textField.usesSingleLineMode = true
        textField.lineBreakMode = .byTruncatingTail
        textField.cell?.isScrollable = true
        textField.cell?.wraps = false
        textField.indexContentInsets = contentInsets
        textField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        textField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }
}
