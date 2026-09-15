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
}
