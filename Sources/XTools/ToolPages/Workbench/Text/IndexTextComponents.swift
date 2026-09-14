import AppKit
import SwiftUI

// MARK: - Caret

final class IndexCaretTextView: NSTextView {
    private let caretWidth: CGFloat = 2

    /// Private undo stack used only when this view acts as a single-line field
    private let fieldEditorUndo = IndexPrivateUndoStack()

    override var undoManager: UndoManager? {
        isFieldEditor ? fieldEditorUndo.manager : super.undoManager
    }

    /// Fired whenever IME composition (marked text) starts or ends. Lets a host
    var onCompositionChange: ((Bool) -> Void)?

    override func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        super.setMarkedText(string, selectedRange: selectedRange, replacementRange: replacementRange)
        onCompositionChange?(hasMarkedText())
    }

    override func unmarkText() {
        super.unmarkText()
        onCompositionChange?(false)
    }

    override func drawInsertionPoint(in rect: NSRect, color: NSColor, turnedOn flag: Bool) {
        var widened = rect
        widened.size.width = caretWidth
        super.drawInsertionPoint(in: widened, color: color, turnedOn: flag)
    }

    override func setNeedsDisplay(_ invalidRect: NSRect, avoidAdditionalLayout flag: Bool) {
        var widened = invalidRect
        widened.size.width += caretWidth
        super.setNeedsDisplay(widened, avoidAdditionalLayout: flag)
    }
}

final class IndexCaretTextFieldCell: IndexPaddedTextFieldCell {
    private var caretEditor: IndexCaretTextView?

    override func fieldEditor(for controlView: NSView) -> NSTextView? {
        if let caretEditor { return caretEditor }
        let editor = IndexCaretTextView(frame: .zero)
        editor.isFieldEditor = true
        caretEditor = editor
        return editor
    }
}

final class IndexCaretTextField: IndexPaddedTextField {
    override class var cellClass: AnyClass? {
        get { IndexCaretTextFieldCell.self }
        set {}
    }
}

extension NSTextView {
    /// Replace the buffer as a new undo baseline. Syncing the buffer to match an
    func setStringWithoutUndoRegistration(_ newValue: String) {
        let manager = undoManager
        manager?.disableUndoRegistration()
        defer {
            manager?.enableUndoRegistration()
            manager?.removeAllActions()
        }
        string = newValue
    }
}

// MARK: - IndexTextInput

struct IndexTextInput: View {
    let placeholder: String
    @Binding var text: String
    var height: CGFloat = 38
    var alignment: TextAlignment = .leading
    var secure = false
    var allowsCopy = true
    var trailingInset: CGFloat = 11
    var autoFocus = false
    var focusRequestToken: Int? = nil
    var selectAllOnFocus = false
    var onSubmit: (() -> Void)? = nil
    var onFocusChange: ((Bool) -> Void)? = nil

    @Environment(\.toolPageEntryTraceContext) private var toolPageEntryTraceContext
    @State private var isFocused = false

    var body: some View {
        IndexUndoableTextField(
            placeholder: placeholder,
            text: $text,
            alignment: alignment,
            secure: secure,
            contentInsets: IndexTextFieldContentInsets(leading: 11, trailing: trailingInset),
            allowsCopy: allowsCopy,
            autoFocus: autoFocus,
            focusRequestToken: focusRequestToken,
            entryTraceContext: toolPageEntryTraceContext,
            selectAllOnFocus: selectAllOnFocus,
            onSubmit: onSubmit,
            onFocusChange: { focused in
                isFocused = focused
                onFocusChange?(focused)
            }
        )
        .id(secure)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .frame(height: height)
        .background(ToolTheme.editorBackground, in: RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.field, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.field, style: .continuous)
                .strokeBorder(isFocused ? ToolTheme.focusRing : ToolTheme.border, lineWidth: isFocused ? 1.5 : 0.5)
        }
        .toolAnimation(ToolMotion.Preset.controlFeedback, value: isFocused)
    }
}

// MARK: - IndexSearchInput

struct IndexSearchInput: View {
    let placeholder: String
    @Binding var text: String
    var height: CGFloat = 38
    var autoFocus = false
    var clearTitle = "清空搜索"
    private let onClear: () -> Void

    @State private var focusRequestToken = 0

    init(
        placeholder: String,
        text: Binding<String>,
        height: CGFloat = 38,
        autoFocus: Bool = false,
        clearTitle: String = "清空搜索",
        onClear: (() -> Void)? = nil
    ) {
        self.placeholder = placeholder
        self._text = text
        self.height = height
        self.autoFocus = autoFocus
        self.clearTitle = clearTitle
        self.onClear = onClear ?? { text.wrappedValue = "" }
    }

    var body: some View {
        IndexTextInput(
            placeholder: placeholder,
            text: $text,
            height: height,
            trailingInset: 40,
            autoFocus: autoFocus,
            focusRequestToken: focusRequestToken == 0 ? nil : focusRequestToken
        )
        .overlay(alignment: .trailing) {
            if !text.isEmpty {
                IndexIconButton(
                    systemImage: IndexActionSymbol.searchClear,
                    help: clearTitle,
                    action: clear
                )
                .padding(.trailing, 4)
            }
        }
    }

    private func clear() {
        onClear()
        focusRequestToken &+= 1
    }
}

private struct IndexUndoableTextField: NSViewRepresentable {
    let placeholder: String
    @Binding var text: String
    let alignment: TextAlignment
    let secure: Bool
    let contentInsets: IndexTextFieldContentInsets
    let allowsCopy: Bool
    let autoFocus: Bool
    let focusRequestToken: Int?
    let entryTraceContext: ToolPageEntryTraceContext?
    let selectAllOnFocus: Bool
    let onSubmit: (() -> Void)?
    let onFocusChange: ((Bool) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, allowsCopy: allowsCopy, selectAllOnFocus: selectAllOnFocus, onSubmit: onSubmit, onFocusChange: onFocusChange)
    }

    func makeNSView(context: Context) -> NSTextField {
        let textField: NSTextField = secure ? IndexPaddedSecureTextField() : IndexCaretTextField()
        configure(textField)
        textField.delegate = context.coordinator
        textField.stringValue = text
        if autoFocus {
            context.coordinator.focus(textField, entryTraceContext: entryTraceContext, placeholder: placeholder)
        }
        if let focusRequestToken {
            context.coordinator.requestFocus(textField, token: focusRequestToken)
        }
        return textField
    }

    func updateNSView(_ textField: NSTextField, context: Context) {
        context.coordinator.text = $text
        context.coordinator.allowsCopy = allowsCopy
        context.coordinator.selectAllOnFocus = selectAllOnFocus
        context.coordinator.onSubmit = onSubmit
        context.coordinator.onFocusChange = onFocusChange
        configure(textField)

        if textField.stringValue != text {
            if let secureTextField = textField as? IndexPaddedSecureTextField {
                secureTextField.setStringFromExternalBinding(text)
            } else {
                textField.stringValue = text
            }
        }

        if autoFocus {
            context.coordinator.focus(textField, entryTraceContext: entryTraceContext, placeholder: placeholder)
        }
        if let focusRequestToken {
            context.coordinator.requestFocus(textField, token: focusRequestToken)
        }
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        nsView textField: NSTextField,
        context: Context
    ) -> CGSize? {
        guard let height = proposal.height else { return nil }
        return CGSize(width: proposal.width ?? textField.fittingSize.width, height: height)
    }

    private func configure(_ textField: NSTextField) {
        textField.placeholderString = placeholder
        textField.font = .monospacedSystemFont(ofSize: 12.5, weight: .regular)
        textField.textColor = .labelColor
        textField.alignment = nsAlignment
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

    private var nsAlignment: NSTextAlignment {
        switch alignment {
        case .center:
            return .center
        case .trailing:
            return .right
        default:
            return .left
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var text: Binding<String>
        var allowsCopy: Bool
        var selectAllOnFocus: Bool
        var onSubmit: (() -> Void)?
        var onFocusChange: ((Bool) -> Void)?

        private var didFocus = false
        private var processedFocusRequestToken: Int?
        private var shouldPlaceCursorAtEndAfterFocus = false

        init(text: Binding<String>, allowsCopy: Bool, selectAllOnFocus: Bool, onSubmit: (() -> Void)?, onFocusChange: ((Bool) -> Void)?) {
            self.text = text
            self.allowsCopy = allowsCopy
            self.selectAllOnFocus = selectAllOnFocus
            self.onSubmit = onSubmit
            self.onFocusChange = onFocusChange
        }

        func focus(_ textField: NSTextField, entryTraceContext: ToolPageEntryTraceContext?, placeholder: String) {
            guard !didFocus else { return }
            didFocus = true
            ToolPageEntryTrace.inputFocusRequested(entryTraceContext, placeholder: placeholder)
            DispatchQueue.main.async {
                self.shouldPlaceCursorAtEndAfterFocus = true
                textField.window?.makeFirstResponder(textField)
                ToolPageEntryTrace.inputFocusCompleted(entryTraceContext, placeholder: placeholder)
            }
        }

        func requestFocus(_ textField: NSTextField, token: Int) {
            guard processedFocusRequestToken != token else { return }
            processedFocusRequestToken = token
            DispatchQueue.main.async { [weak self, weak textField] in
                guard let self, let textField else { return }
                self.shouldPlaceCursorAtEndAfterFocus = true
                textField.window?.makeFirstResponder(textField)
            }
        }

        func controlTextDidBeginEditing(_ notification: Notification) {
            if let textField = notification.object as? NSTextField {
                enableUndo(in: textField)
                if selectAllOnFocus {
                    DispatchQueue.main.async {
                        textField.currentEditor()?.selectAll(nil)
                    }
                } else if shouldPlaceCursorAtEndAfterFocus {
                    DispatchQueue.main.async {
                        let end = textField.stringValue.count
                        textField.currentEditor()?.selectedRange = NSRange(location: end, length: 0)
                    }
                }
                shouldPlaceCursorAtEndAfterFocus = false
            }
            onFocusChange?(true)
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            onFocusChange?(false)
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let textField = notification.object as? NSTextField else { return }
            enableUndo(in: textField)
            if text.wrappedValue != textField.stringValue {
                text.wrappedValue = textField.stringValue
            }
        }

        func control(
            _ control: NSControl,
            textView: NSTextView,
            doCommandBy commandSelector: Selector
        ) -> Bool {
            guard commandSelector == #selector(NSResponder.insertNewline(_:)) else {
                if commandSelector == #selector(NSText.copy(_:)) && !allowsCopy {
                    return true
                }
                return false
            }

            onSubmit?()
            control.window?.makeFirstResponder(nil)
            return true
        }

        private func enableUndo(in textField: NSTextField) {
            AppKitTextEditingConfiguration.configureCurrentFieldEditor(for: textField)
        }
    }
}

// MARK: - IndexTextArea

enum IndexTextAreaRenderingMode: Equatable {
    case measuredContent
    /// Fixed internal viewport backed by TextKit 2. This is opt-in because
    /// changing the text system can affect selection, undo, and composition.
    case textKit2Viewport
}

struct IndexTextAreaCharacterRange: Equatable, Sendable {
    let start: Int
    let end: Int
}

enum IndexTextAreaCharacterRangeProjection {
    static func utf16Ranges(
        in text: String,
        characterRanges: [IndexTextAreaCharacterRange]
    ) -> [NSRange] {
        var result: [NSRange] = []
        var cursor = text.startIndex
        var cursorOffset = 0

        for range in characterRanges {
            guard range.start >= cursorOffset,
                  range.end >= range.start,
                  let lowerBound = text.index(
                    cursor,
                    offsetBy: range.start - cursorOffset,
                    limitedBy: text.endIndex
                  ),
                  let upperBound = text.index(
                    lowerBound,
                    offsetBy: range.end - range.start,
                    limitedBy: text.endIndex
                  ) else {
                continue
            }

            cursor = upperBound
            cursorOffset = range.end
            guard lowerBound < upperBound else { continue }
            result.append(NSRange(lowerBound..<upperBound, in: text))
        }

        return result
    }
}

struct IndexTextAreaTemporaryHighlights: Equatable {
    let sourceText: String
    let ranges: [NSRange]
}

@MainActor
enum IndexTextAreaTemporaryHighlightRenderer {
    static func apply(_ highlights: IndexTextAreaTemporaryHighlights?, to textView: NSTextView) {
        clear(in: textView)
        guard let highlights,
              textView.string == highlights.sourceText,
              !textView.hasMarkedText(),
              let layoutManager = textView.layoutManager else {
            return
        }

        let textLength = (textView.string as NSString).length
        let backgroundColor = NSColor(ToolTheme.accentSoft)
        for range in highlights.ranges where range.length > 0 {
            guard range.location >= 0, range.upperBound <= textLength else { continue }
            layoutManager.addTemporaryAttribute(
                .backgroundColor,
                value: backgroundColor,
                forCharacterRange: range
            )
        }
    }

    static func clear(in textView: NSTextView) {
        guard let layoutManager = textView.layoutManager else { return }
        layoutManager.removeTemporaryAttribute(
            .backgroundColor,
            forCharacterRange: NSRange(location: 0, length: (textView.string as NSString).length)
        )
    }
}

struct IndexTextAreaCaretPlacementState: Equatable {
    private(set) var processedRequestToken: Int? = nil

    @discardableResult
    mutating func selectionRange(
        requestToken: Int?,
        text: String,
        hasMarkedText: Bool
    ) -> NSRange? {
        guard let requestToken,
              requestToken != processedRequestToken,
              !hasMarkedText else {
            return nil
        }

        processedRequestToken = requestToken
        return NSRange(location: (text as NSString).length, length: 0)
    }
}

struct IndexTextArea: View {
    let placeholder: String
    @Binding var text: String
    var minHeight: CGFloat = 220
    var maxHeightRatio: CGFloat? = nil
    var fillsHeight = false
    var expandsWithContent = false
    var renderingMode: IndexTextAreaRenderingMode = .measuredContent
    var lineBreakMode: NSLineBreakMode = .byCharWrapping
    var autoFocus = false
    var caretPlacementRequestToken: Int? = nil
    var temporaryHighlights: IndexTextAreaTemporaryHighlights? = nil
    var inputPolicy: IndexTextAreaInputPolicy? = nil
    /// Prototype v3 embedded-code presentation: drop the editor's own field
    /// box so the owning workbench panel supplies the surface edge to edge.
    var embedsFlat = false
    /// AppKit line-number gutter drawn inside the scroll view. Supported only
    /// by the measured-content path (same boundary as temporary highlights);
    /// the TextKit 2 viewport path ignores it.
    var lineNumbers = false

    @Environment(\.pageAvailableHeight) private var pageAvailableHeight
    @State private var isComposing = false
    @State private var measuredTextHeight: CGFloat = 0

    var growsWithContent: Bool {
        expandsWithContent
    }

    private var resolvedHeight: CGFloat? {
        guard growsWithContent else { return nil }
        return max(minHeight, measuredTextHeight)
    }

    private var placeholderLeadingPadding: CGFloat {
        lineNumbers ? IndexEditorLineNumberGutter.width + 13 : 13
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty && !isComposing {
                Text(placeholder)
                    .font(lineNumbers ? ToolTypography.codeBody : ToolTypography.body)
                    .foregroundStyle(ToolTheme.textTertiary)
                    .padding(.leading, placeholderLeadingPadding)
                    .padding(.trailing, 13)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Group {
                if renderingMode == .textKit2Viewport {
                    IndexTextKit2ViewportTextView(
                        text: $text,
                        lineBreakMode: lineBreakMode,
                        autoFocus: autoFocus,
                        caretPlacementRequestToken: caretPlacementRequestToken,
                        inputPolicy: inputPolicy,
                        onCompositionChange: { isComposing = $0 }
                    )
                } else {
                    IndexUndoableTextView(
                        text: $text,
                        growsWithContent: growsWithContent,
                        lineBreakMode: lineBreakMode,
                        measuredHeight: $measuredTextHeight,
                        autoFocus: autoFocus,
                        caretPlacementRequestToken: caretPlacementRequestToken,
                        temporaryHighlights: temporaryHighlights,
                        inputPolicy: inputPolicy,
                        embedsFlat: embedsFlat,
                        lineNumbers: lineNumbers,
                        onCompositionChange: { isComposing = $0 }
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: fillsHeight ? .infinity : nil, alignment: .topLeading)
            .frame(height: renderingMode == .textKit2Viewport ? nil : (growsWithContent ? resolvedHeight : nil), alignment: .topLeading)
        }
        .frame(
            maxWidth: .infinity,
            minHeight: fillsHeight ? 60 : minHeight,
            idealHeight: resolvedHeight,
            maxHeight: fillsHeight ? .infinity : (resolvedHeight ?? maxHeightRatio.map { pageAvailableHeight * $0 } ?? minHeight),
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
        .iBeamCursorOnHover()
    }
}

struct IndexTextAreaInputPolicy {
    var maxUTF8Bytes: Int?
    var undoLevels: Int?
    var onRejectedInput: ((IndexTextAreaInputRejection) -> Void)?

    init(
        maxUTF8Bytes: Int? = nil,
        undoLevels: Int? = nil,
        onRejectedInput: ((IndexTextAreaInputRejection) -> Void)? = nil
    ) {
        self.maxUTF8Bytes = maxUTF8Bytes
        self.undoLevels = undoLevels
        self.onRejectedInput = onRejectedInput
    }
}

struct IndexTextAreaInputRejection {
    let maxUTF8Bytes: Int
    let attemptedUTF8Bytes: Int
}

// MARK: - IndexTextKit2ViewportTextView

/// layout manager opts the view into TextKit 1 compatibility mode and forces a
struct IndexTextKit2ViewportTextView: NSViewRepresentable {
    @Binding var text: String
    var lineBreakMode: NSLineBreakMode
    var autoFocus = false
    var caretPlacementRequestToken: Int? = nil
    var inputPolicy: IndexTextAreaInputPolicy? = nil
    var onCompositionChange: ((Bool) -> Void)? = nil

    static func makeTextView() -> IndexCaretTextView {
        let textView = IndexCaretTextView(usingTextLayoutManager: true)
        precondition(textView.textLayoutManager != nil)
        return textView
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, inputPolicy: inputPolicy)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = Self.makeTextView()
        textView.onCompositionChange = onCompositionChange

        let scrollView = IndexTextKit2ViewportScrollView(frame: .zero)
        scrollView.contentView = IndexLeadingLockedClipView(frame: .zero)
        scrollView.documentView = textView
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false

        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = false
        scrollView.verticalScrollElasticity = .automatic

        configure(textView)
        textView.delegate = context.coordinator
        textView.setStringWithoutUndoRegistration(text)
        if context.coordinator.placeCaretAtEndIfRequested(caretPlacementRequestToken, in: textView) {
            revealInsertionPoint(in: textView)
        }
        if autoFocus {
            context.coordinator.focus(textView)
        }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }

        context.coordinator.text = $text
        context.coordinator.inputPolicy = inputPolicy
        configure(textView)
        (textView as? IndexCaretTextView)?.onCompositionChange = onCompositionChange

        // Do not rewrite marked text during Chinese IME composition. The
        if textView.string != text && !textView.hasMarkedText() {
            let selectedRanges = textView.selectedRanges
            textView.setStringWithoutUndoRegistration(text)
            let stringLength = (text as NSString).length
            let validRanges = selectedRanges.filter { $0.rangeValue.upperBound <= stringLength }
            textView.selectedRanges = validRanges.isEmpty
                ? [NSValue(range: NSRange(location: stringLength, length: 0))]
                : validRanges
            revealInsertionPoint(in: textView)
        }
        if context.coordinator.placeCaretAtEndIfRequested(caretPlacementRequestToken, in: textView) {
            revealInsertionPoint(in: textView)
        }
    }

    private func configure(_ textView: NSTextView) {
        textView.font = .monospacedSystemFont(ofSize: 12.5, weight: .regular)
        textView.textColor = .labelColor
        textView.insertionPointColor = .labelColor
        textView.drawsBackground = false
        textView.isEditable = true
        textView.isSelectable = true
        AppKitTextEditingConfiguration.configurePlainTextEditor(textView)
        textView.isRichText = false
        textView.importsGraphics = false
        textView.usesFindPanel = true
        textView.textContainerInset = NSSize(width: 13, height: 12)

        if let textContainer = textView.textContainer {
            textContainer.widthTracksTextView = true
            textContainer.lineFragmentPadding = 0
            textContainer.lineBreakMode = lineBreakMode
            textContainer.containerSize = NSSize(
                width: max(1, textView.bounds.width),
                height: .greatestFiniteMagnitude
            )
        }
    }

    private func revealInsertionPoint(in textView: NSTextView) {
        textView.scrollRangeToVisible(clampedSelectedRange(for: textView))
        DispatchQueue.main.async { [weak textView] in
            guard let textView else { return }
            textView.scrollRangeToVisible(clampedSelectedRange(for: textView))
        }
    }

    private func clampedSelectedRange(for textView: NSTextView) -> NSRange {
        let textLength = (textView.string as NSString).length
        let selectedRange = textView.selectedRange()
        let rawLocation = selectedRange.location == NSNotFound ? textLength : selectedRange.location
        let location = min(max(0, rawLocation), textLength)
        let upperBound = min(max(location, selectedRange.upperBound), textLength)
        return NSRange(location: location, length: upperBound - location)
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        var inputPolicy: IndexTextAreaInputPolicy? {
            didSet {
                configureUndoManager()
            }
        }
        private var didFocus = false
        private var caretPlacementState = IndexTextAreaCaretPlacementState(processedRequestToken: nil)
        private let privateUndo = IndexPrivateUndoStack()

        init(text: Binding<String>, inputPolicy: IndexTextAreaInputPolicy?) {
            self.text = text
            self.inputPolicy = inputPolicy
            super.init()
            configureUndoManager()
        }

        func focus(_ textView: NSTextView) {
            guard !didFocus else { return }
            didFocus = true
            DispatchQueue.main.async {
                textView.window?.makeFirstResponder(textView)
            }
        }

        @discardableResult
        func placeCaretAtEndIfRequested(_ token: Int?, in textView: NSTextView) -> Bool {
            guard let selection = caretPlacementState.selectionRange(
                requestToken: token,
                text: textView.string,
                hasMarkedText: textView.hasMarkedText()
            ) else {
                return false
            }

            textView.setSelectedRange(selection)
            return true
        }

        func textView(
            _ textView: NSTextView,
            shouldChangeTextIn affectedCharRange: NSRange,
            replacementString: String?
        ) -> Bool {
            guard let maxUTF8Bytes = inputPolicy?.maxUTF8Bytes else { return true }
            let currentText = textView.string
            let currentNSString = currentText as NSString
            guard affectedCharRange.location >= 0,
                  affectedCharRange.upperBound <= currentNSString.length else {
                return false
            }

            let replacement = replacementString ?? ""
            let removedText = currentNSString.substring(with: affectedCharRange)
            let attemptedUTF8Bytes = currentText.utf8.count - removedText.utf8.count + replacement.utf8.count
            guard attemptedUTF8Bytes <= maxUTF8Bytes else {
                inputPolicy?.onRejectedInput?(
                    IndexTextAreaInputRejection(
                        maxUTF8Bytes: maxUTF8Bytes,
                        attemptedUTF8Bytes: attemptedUTF8Bytes
                    )
                )
                return false
            }
            return true
        }

        // resolves to the shared window undo manager. A per-instance stack dies
        // pop an action whose text target has already been freed (the crash).
        func undoManager(for view: NSTextView) -> UndoManager? {
            privateUndo.manager
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            if text.wrappedValue != textView.string {
                text.wrappedValue = textView.string
            }
            textView.scrollRangeToVisible(clampedSelectedRange(for: textView))
        }

        private func clampedSelectedRange(for textView: NSTextView) -> NSRange {
            let textLength = (textView.string as NSString).length
            let selectedRange = textView.selectedRange()
            let rawLocation = selectedRange.location == NSNotFound ? textLength : selectedRange.location
            let location = min(max(0, rawLocation), textLength)
            let upperBound = min(max(location, selectedRange.upperBound), textLength)
            return NSRange(location: location, length: upperBound - location)
        }

        private func configureUndoManager() {
            privateUndo.configureLevels(inputPolicy?.undoLevels)
        }
    }
}

private final class IndexTextKit2ViewportScrollView: NSScrollView {
    override func layout() {
        super.layout()
        guard let textView = documentView as? NSTextView else { return }

        let viewportSize = contentSize
        textView.minSize = NSSize(width: 0, height: viewportSize.height)
        if textView.frame.width <= 0
            || abs(textView.frame.width - viewportSize.width) > 0.5
            || textView.frame.height < viewportSize.height
        {
            textView.setFrameSize(NSSize(
                width: viewportSize.width,
                height: max(viewportSize.height, textView.frame.height)
            ))
        }
    }
}

// MARK: - Legacy measured text view

struct IndexUndoableTextView: NSViewRepresentable {
    @Binding var text: String
    var growsWithContent: Bool
    var lineBreakMode: NSLineBreakMode
    @Binding var measuredHeight: CGFloat
    var autoFocus = false
    var caretPlacementRequestToken: Int? = nil
    var temporaryHighlights: IndexTextAreaTemporaryHighlights? = nil
    var inputPolicy: IndexTextAreaInputPolicy? = nil
    var embedsFlat = false
    var lineNumbers = false
    var onCompositionChange: ((Bool) -> Void)? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(
            text: $text,
            measuredHeight: $measuredHeight,
            growsWithContent: growsWithContent,
            inputPolicy: inputPolicy
        )
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = IndexCaretTextView(frame: .zero)
        textView.onCompositionChange = onCompositionChange
        let scrollView = IndexTextAreaScrollView(frame: .zero)
        scrollView.contentView = IndexLeadingLockedClipView(frame: .zero)
        scrollView.growsWithContent = growsWithContent
        scrollView.documentView = textView
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false

        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = !growsWithContent
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = !growsWithContent
        scrollView.verticalScrollElasticity = growsWithContent ? .none : .automatic

        configure(textView)
        textView.delegate = context.coordinator
        textView.setStringWithoutUndoRegistration(text)
        if lineNumbers {
            installLineNumberGutter(in: scrollView, for: textView, coordinator: context.coordinator)
        }
        IndexTextAreaTemporaryHighlightRenderer.apply(temporaryHighlights, to: textView)
        scrollView.synchronizeTextGeometry()
        context.coordinator.measure(textView)
        if context.coordinator.placeCaretAtEndIfRequested(caretPlacementRequestToken, in: textView) {
            IndexTextAreaScrollPositioning.revealInsertionPoint(in: textView, growsWithContent: growsWithContent)
        }
        if autoFocus {
            context.coordinator.focus(textView)
        }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        context.coordinator.text = $text
        context.coordinator.measuredHeight = $measuredHeight
        context.coordinator.growsWithContent = growsWithContent
        context.coordinator.inputPolicy = inputPolicy
        configure(textView)
        if let scrollView = scrollView as? IndexTextAreaScrollView {
            scrollView.growsWithContent = growsWithContent
            scrollView.synchronizeTextGeometry()
        }
        (textView as? IndexCaretTextView)?.onCompositionChange = onCompositionChange
        scrollView.hasVerticalScroller = !growsWithContent
        scrollView.autohidesScrollers = !growsWithContent
        scrollView.verticalScrollElasticity = growsWithContent ? .none : .automatic
        keepContentGrowingScrollOriginStable(in: scrollView)

        // `textView.string` already contains the marked (组字) text but `text`
        // back would wipe the marked text and abort the composition (Chinese
        if textView.string != text && !textView.hasMarkedText() {
            let selectedRanges = textView.selectedRanges
            textView.setStringWithoutUndoRegistration(text)
            let stringLength = (text as NSString).length
            let validRanges = selectedRanges.filter { $0.rangeValue.upperBound <= stringLength }
            textView.selectedRanges = validRanges.isEmpty ? [NSValue(range: NSRange(location: stringLength, length: 0))] : validRanges
            IndexTextAreaScrollPositioning.revealInsertionPoint(in: textView, growsWithContent: growsWithContent)
            context.coordinator.refreshLineNumberGutter()
        }
        if context.coordinator.placeCaretAtEndIfRequested(caretPlacementRequestToken, in: textView) {
            IndexTextAreaScrollPositioning.revealInsertionPoint(in: textView, growsWithContent: growsWithContent)
        }
        IndexTextAreaTemporaryHighlightRenderer.apply(temporaryHighlights, to: textView)
        context.coordinator.measure(textView)
        keepContentGrowingScrollOriginStable(in: scrollView)
    }

    private func installLineNumberGutter(
        in scrollView: NSScrollView,
        for textView: NSTextView,
        coordinator: Coordinator
    ) {
        let gutter = IndexEditorLineNumberGutterView(scrollView: scrollView, textView: textView)
        gutter.autoresizingMask = [.height]
        scrollView.addSubview(gutter)
        coordinator.lineNumberGutter = gutter
    }

    private func configure(_ textView: NSTextView) {
        textView.font = .monospacedSystemFont(ofSize: 12.5, weight: .regular)
        textView.textColor = .labelColor
        textView.insertionPointColor = .labelColor
        textView.drawsBackground = false
        textView.isEditable = true
        textView.isSelectable = true
        AppKitTextEditingConfiguration.configurePlainTextEditor(textView)
        textView.isRichText = false
        textView.importsGraphics = false
        textView.usesFindPanel = true
        textView.textContainerInset = NSSize(
            width: lineNumbers ? IndexEditorLineNumberGutter.width + 13 : 13,
            height: 12
        )
        if embedsFlat || lineNumbers {
            // Keep the editor's visual line rhythm on the output surface's
            // 6pt line spacing so both workbench panes read consistently.
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.lineSpacing = 6
            textView.defaultParagraphStyle = paragraphStyle
        }

        if let textContainer = textView.textContainer {
            textContainer.widthTracksTextView = false
            textContainer.lineFragmentPadding = 0
            textContainer.lineBreakMode = lineBreakMode
            textContainer.containerSize = NSSize(
                width: IndexTextKitGeometry.wrappingContainerWidth(
                    for: textView,
                    visibleWidth: textView.bounds.width
                ),
                height: .greatestFiniteMagnitude
            )
        }
    }

    private func keepContentGrowingScrollOriginStable(in scrollView: NSScrollView) {
        guard growsWithContent else { return }

        let currentOrigin = scrollView.contentView.bounds.origin
        guard currentOrigin != .zero else { return }

        scrollView.contentView.scroll(to: .zero)
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        var measuredHeight: Binding<CGFloat>
        var growsWithContent: Bool
        var inputPolicy: IndexTextAreaInputPolicy? {
            didSet {
                configureUndoManager()
            }
        }
        weak var lineNumberGutter: IndexEditorLineNumberGutterView?
        private var didFocus = false
        private var caretPlacementState = IndexTextAreaCaretPlacementState(processedRequestToken: nil)
        private let privateUndo = IndexPrivateUndoStack()

        func refreshLineNumberGutter() {
            lineNumberGutter?.refresh()
        }

        init(
            text: Binding<String>,
            measuredHeight: Binding<CGFloat>,
            growsWithContent: Bool,
            inputPolicy: IndexTextAreaInputPolicy?
        ) {
            self.text = text
            self.measuredHeight = measuredHeight
            self.growsWithContent = growsWithContent
            self.inputPolicy = inputPolicy
            super.init()
            configureUndoManager()
        }

        func focus(_ textView: NSTextView) {
            guard !didFocus else { return }
            didFocus = true
            DispatchQueue.main.async {
                textView.window?.makeFirstResponder(textView)
            }
        }

        @discardableResult
        func placeCaretAtEndIfRequested(_ token: Int?, in textView: NSTextView) -> Bool {
            guard let selection = caretPlacementState.selectionRange(
                requestToken: token,
                text: textView.string,
                hasMarkedText: textView.hasMarkedText()
            ) else {
                return false
            }

            textView.setSelectedRange(selection)
            return true
        }

        func textView(
            _ textView: NSTextView,
            shouldChangeTextIn affectedCharRange: NSRange,
            replacementString: String?
        ) -> Bool {
            guard let maxUTF8Bytes = inputPolicy?.maxUTF8Bytes else { return true }
            let currentText = textView.string
            let currentNSString = currentText as NSString
            guard affectedCharRange.location >= 0,
                  affectedCharRange.upperBound <= currentNSString.length else {
                return false
            }

            let replacement = replacementString ?? ""
            let removedText = currentNSString.substring(with: affectedCharRange)
            let attemptedUTF8Bytes = currentText.utf8.count - removedText.utf8.count + replacement.utf8.count
            guard attemptedUTF8Bytes <= maxUTF8Bytes else {
                inputPolicy?.onRejectedInput?(
                    IndexTextAreaInputRejection(
                        maxUTF8Bytes: maxUTF8Bytes,
                        attemptedUTF8Bytes: attemptedUTF8Bytes
                    )
                )
                return false
            }
            return true
        }

        // Always vend this coordinator's private manager (see the TextKit2 path
        // above) so the view never falls back to the shared window undo manager.
        func undoManager(for view: NSTextView) -> UndoManager? {
            privateUndo.manager
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            IndexTextAreaTemporaryHighlightRenderer.clear(in: textView)
            refreshLineNumberGutter()
            if text.wrappedValue != textView.string {
                text.wrappedValue = textView.string
            }
            measure(textView)
            IndexTextAreaScrollPositioning.revealInsertionPoint(in: textView, growsWithContent: growsWithContent)
        }

        func measure(_ textView: NSTextView) {
            if let scrollView = textView.enclosingScrollView as? IndexTextAreaScrollView {
                scrollView.synchronizeTextGeometry()
            }
            // Fixed-height scroll editors never bind measuredHeight into frame;
            // skip the full-document ensureLayout path that only feeds height.
            guard growsWithContent else { return }

            let height = IndexTextKitGeometry.measuredTextHeight(for: textView)

            guard abs(measuredHeight.wrappedValue - height) > 0.5 else { return }
            DispatchQueue.main.async {
                self.measuredHeight.wrappedValue = height.rounded(.up)
            }
        }

        private func configureUndoManager() {
            privateUndo.configureLevels(inputPolicy?.undoLevels)
        }
    }
}

// MARK: - Editor line-number gutter

enum IndexEditorLineNumberGutter {
    /// Number column (34, right-aligned) plus the gap before the separator.
    static let width: CGFloat = 44
}

/// Draws logical line numbers for a measured-content editor as an overlay
/// pinned to the owning scroll view (prototype v3 code-editor gutter).
///
/// Only visible line fragments are projected, and each logical line draws its
/// number once at its first visual fragment, so wrapped lines stay aligned
/// with the editor. The overlay is presentation-only: hit-test transparent,
/// decorative for accessibility, and never touches text storage.
@MainActor
final class IndexEditorLineNumberGutterView: NSView {
    static let numberColumnWidth: CGFloat = 34

    weak var scrollView: NSScrollView?
    weak var textView: NSTextView?
    private var newlineOffsetsDirty = true
    private var newlineOffsets: [Int] = []
    private nonisolated(unsafe) var boundsObserver: NSObjectProtocol?

    override var isFlipped: Bool { true }

    init(scrollView: NSScrollView, textView: NSTextView) {
        self.scrollView = scrollView
        self.textView = textView
        super.init(frame: .zero)
        setNeedsDisplay(self.bounds)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        if let boundsObserver {
            NotificationCenter.default.removeObserver(boundsObserver)
            self.boundsObserver = nil
        }
        guard window != nil, let scrollView else { return }
        let contentView = scrollView.contentView

        // The scroll view is frame-managed and does not autoresize foreign
        // subviews up from a zero frame; sync once the window has laid out so
        // the first display pass has real geometry.
        DispatchQueue.main.async { [weak self] in
            self?.syncFrameWithScrollView()
        }

        contentView.postsBoundsChangedNotifications = true
        boundsObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: contentView,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.needsDisplay = true
            }
        }
        // Bounds notifications pause during live scrolling; the live-scroll
        // notification keeps the gutter tracking while dragging the scroller.
        // Selector observers deregister at dealloc, so install only once.
        if !didInstallLiveScrollObserver {
            didInstallLiveScrollObserver = true
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(scrollViewDidLiveScroll),
                name: NSScrollView.didLiveScrollNotification,
                object: scrollView
            )
        }
    }

    private nonisolated(unsafe) var didInstallLiveScrollObserver = false

    @objc private func scrollViewDidLiveScroll() {
        needsDisplay = true
    }

    deinit {
        if let boundsObserver {
            NotificationCenter.default.removeObserver(boundsObserver)
        }
    }

    /// Marks cached layout metadata stale after any text-buffer replacement.
    func refresh() {
        newlineOffsetsDirty = true
        needsDisplay = true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    /// The scroll view is frame-managed (no Auto Layout), so the gutter keeps
    /// its own frame in sync at draw time; autoresizing covers live resizes
    /// between draws.
    private func syncFrameWithScrollView() {
        guard let scrollView, scrollView.bounds.height > 0 else { return }
        let target = NSRect(
            x: 0,
            y: 0,
            width: IndexEditorLineNumberGutter.width,
            height: scrollView.bounds.height
        )
        if frame != target {
            frame = target
            needsDisplay = true
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        syncFrameWithScrollView()
        guard let textView, let scrollView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else {
            return
        }

        let hairline = NSRect(x: IndexEditorLineNumberGutter.width - 0.5, y: 0, width: 0.5, height: bounds.height)
        NSColor(ToolTheme.border).setFill()
        NSBezierPath(rect: hairline).fill()

        let nsText = textView.string as NSString
        if newlineOffsetsDirty {
            rebuildNewlineOffsets(for: nsText)
        }

        let visibleRect = scrollView.contentView.bounds
        let origin = textView.textContainerOrigin
        let containerRect = NSRect(
            x: visibleRect.minX - origin.x,
            y: visibleRect.minY - origin.y,
            width: visibleRect.width,
            height: visibleRect.height
        )
        let glyphRange = layoutManager.glyphRange(forBoundingRect: containerRect, in: textContainer)
        guard glyphRange.length > 0 || nsText.length == 0 else { return }

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .right
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
            .foregroundColor: NSColor(ToolTheme.textTertiary),
            .paragraphStyle: paragraphStyle
        ]

        if nsText.length == 0 {
            let defaultLineHeight = layoutManager.defaultLineHeight(for: textView.font ?? .monospacedSystemFont(ofSize: 12.5, weight: .regular))
            let y = origin.y - visibleRect.minY
            let label = "1" as NSString
            label.draw(
                in: NSRect(
                    x: 6,
                    y: y + 3,
                    width: Self.numberColumnWidth - 6,
                    height: max(1, defaultLineHeight)
                ),
                withAttributes: attributes
            )
            return
        }

        layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) { [weak self] fragmentRect, _, _, fragmentGlyphRange, _ in
            guard let self else { return }
            let characterIndex = layoutManager.characterIndexForGlyph(at: fragmentGlyphRange.location)
            guard self.isLogicalLineStart(at: characterIndex, in: nsText) else { return }

            let y = fragmentRect.minY + origin.y - visibleRect.minY
            let height = max(1, fragmentRect.height)
            guard y + height >= 0, y <= bounds.height else { return }

            let lineNumber = self.lineNumber(at: characterIndex)
            let label = "\(lineNumber)" as NSString
            label.draw(
                in: NSRect(
                    x: 6,
                    y: y + 3,
                    width: Self.numberColumnWidth - 6,
                    height: height
                ),
                withAttributes: attributes
            )
        }
    }

    private func rebuildNewlineOffsets(for nsText: NSString) {
        var offsets: [Int] = []
        offsets.reserveCapacity(nsText.length / 32 + 1)
        var searchRange = NSRange(location: 0, length: nsText.length)
        while searchRange.location < nsText.length {
            let found = nsText.range(of: "\n", options: [], range: searchRange)
            guard found.location != NSNotFound else { break }
            offsets.append(found.location)
            searchRange.location = found.location + 1
            searchRange.length = nsText.length - searchRange.location
        }
        newlineOffsets = offsets
        newlineOffsetsDirty = false
    }

    private func isLogicalLineStart(at characterIndex: Int, in nsText: NSString) -> Bool {
        guard characterIndex > 0 else { return true }
        guard characterIndex <= nsText.length else { return false }
        return nsText.character(at: characterIndex - 1) == unichar(10)
    }

    private func lineNumber(at characterIndex: Int) -> Int {
        var low = 0
        var high = newlineOffsets.count
        while low < high {
            let mid = (low + high) / 2
            if newlineOffsets[mid] < characterIndex {
                low = mid + 1
            } else {
                high = mid
            }
        }
        return low + 1
    }
}

@MainActor
enum IndexTextKitGeometry {
    static let trailingWrapGuard: CGFloat = 16

    static func wrappingContainerWidth(
        for textView: NSTextView,
        visibleWidth: CGFloat,
        trailingReadingGuard: CGFloat = trailingWrapGuard
    ) -> CGFloat {
        let safeVisibleWidth = max(1, visibleWidth.isFinite ? visibleWidth : textView.bounds.width)
        let linePadding = (textView.textContainer?.lineFragmentPadding ?? 0) * 2
        let horizontalInset = textView.textContainerInset.width * 2
        return max(1, floor(safeVisibleWidth - horizontalInset - linePadding - trailingReadingGuard))
    }

    static func measuredTextHeight(for textView: NSTextView) -> CGFloat {
        guard let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else {
            return 0
        }

        layoutManager.ensureLayout(for: textContainer)
        let usedHeight = layoutManager.usedRect(for: textContainer).height
        let font = textView.font ?? .monospacedSystemFont(ofSize: 12.5, weight: .regular)
        let lineHeight = layoutManager.defaultLineHeight(for: font)
        return ceil(max(lineHeight, usedHeight) + textView.textContainerInset.height * 2)
    }

    static func synchronizeTextGeometry(
        for textView: NSTextView,
        visibleWidth: CGFloat,
        minimumHeight: CGFloat,
        trailingReadingGuard: CGFloat = trailingWrapGuard
    ) {
        let width = max(1, floor(visibleWidth.isFinite ? visibleWidth : textView.bounds.width))

        if let textContainer = textView.textContainer {
            textContainer.widthTracksTextView = false
            textContainer.containerSize = NSSize(
                width: wrappingContainerWidth(
                    for: textView,
                    visibleWidth: width,
                    trailingReadingGuard: trailingReadingGuard
                ),
                height: CGFloat.greatestFiniteMagnitude
            )
        }

        let height = max(ceil(minimumHeight), measuredTextHeight(for: textView))
        let currentSize = textView.frame.size
        guard abs(currentSize.width - width) > 0.5 || abs(currentSize.height - height) > 0.5 else {
            return
        }
        textView.setFrameSize(NSSize(width: width, height: height))
    }
}

final class IndexLeadingLockedClipView: NSClipView {
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var bounds = super.constrainBoundsRect(proposedBounds)
        bounds.origin.x = 0
        return bounds
    }

    override func setBoundsOrigin(_ newOrigin: NSPoint) {
        super.setBoundsOrigin(NSPoint(x: 0, y: newOrigin.y))
    }

    override func scroll(to newOrigin: NSPoint) {
        super.scroll(to: NSPoint(x: 0, y: newOrigin.y))
    }
}

private final class IndexTextAreaScrollView: NSScrollView {
    var growsWithContent = false

    override func layout() {
        super.layout()
        synchronizeTextGeometry()
    }

    override func scrollWheel(with event: NSEvent) {
        guard growsWithContent else {
            super.scrollWheel(with: event)
            return
        }

        nextResponder?.scrollWheel(with: event)
    }

    func synchronizeTextGeometry() {
        guard let textView = documentView as? NSTextView else { return }

        IndexTextKitGeometry.synchronizeTextGeometry(
            for: textView,
            visibleWidth: contentSize.width,
            minimumHeight: contentSize.height
        )
    }
}

@MainActor
enum IndexTextAreaScrollPositioning {
    static func revealInsertionPoint(in textView: NSTextView, growsWithContent: Bool) {
        guard !growsWithContent else { return }

        revealInsertionPointNow(in: textView, growsWithContent: growsWithContent)
        DispatchQueue.main.async { [weak textView] in
            guard let textView else { return }
            revealInsertionPointNow(in: textView, growsWithContent: growsWithContent)
        }
    }

    static func revealInsertionPointNow(in textView: NSTextView, growsWithContent: Bool) {
        guard !growsWithContent else { return }

        if let layoutManager = textView.layoutManager, let textContainer = textView.textContainer {
            layoutManager.ensureLayout(for: textContainer)
        }
        textView.scrollRangeToVisible(clampedSelectedRange(for: textView))
    }

    private static func clampedSelectedRange(for textView: NSTextView) -> NSRange {
        let textLength = (textView.string as NSString).length
        let selectedRange = textView.selectedRange()
        let rawLocation = selectedRange.location == NSNotFound ? textLength : selectedRange.location
        let location = min(max(0, rawLocation), textLength)
        let upperBound = min(max(location, selectedRange.upperBound), textLength)
        return NSRange(location: location, length: upperBound - location)
    }
}

// MARK: - IndexOutputSurface

struct IndexOutputSurface: View {
    let text: String
    let placeholder: String
    var minHeight: CGFloat = 220
    var large = false
    var centered = false
    var fillsHeight = false
    var scrollsInternally = true
    var lineBreakMode: NSLineBreakMode = .byCharWrapping
    var lineNumbers = false
    var colorize: ((String) -> AttributedString)? = nil
    var embedsFlat = false

    private var showsGutter: Bool { lineNumbers && !large && !centered }
    private var effectiveMinHeight: CGFloat { fillsHeight ? 60 : minHeight }

    var body: some View {
        Group {
            if text.isEmpty {
                placeholderBody
            } else {
                if scrollsInternally {
                    ScrollView {
                        outputBody
                    }
                } else {
                    outputBody
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: fillsHeight ? .infinity : nil, alignment: .topLeading)
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
    }

    @ViewBuilder
    private var outputBody: some View {
        if showsGutter {
            gutteredBody
        } else if let colorize {
            colorizedBody(colorize)
        } else {
            plainBody
        }
    }

    private var placeholderBody: some View {
        HStack(alignment: .top, spacing: 0) {
            if showsGutter {
                Text("1")
                    .font(ToolTypography.monoCaption)
                    .monospacedDigit()
                    .foregroundStyle(ToolTheme.textTertiary)
                    .frame(width: 34, alignment: .trailing)
                    .padding(.trailing, 10)
            }
            Text(placeholder)
                .font(large ? ToolTypography.statValue : ToolTypography.body)
                .foregroundStyle(ToolTheme.textTertiary)
                .textSelection(.enabled)
                .lineLimit(nil)
                .multilineTextAlignment(.leading)
                .lineSpacing(6)
                .padding(.leading, showsGutter ? 13 : 0)
                .frame(
                    maxWidth: .infinity,
                    alignment: centered ? .center : .topLeading
                )
        }
        .frame(
            maxWidth: .infinity,
            minHeight: effectiveMinHeight,
            maxHeight: fillsHeight ? .infinity : nil,
            alignment: centered ? .center : .topLeading
        )
        .padding(.vertical, 12)
        .padding(.trailing, 13)
        .padding(.leading, showsGutter ? 0 : 13)
        .overlay(alignment: .leading) {
            if showsGutter {
                Rectangle()
                    .fill(ToolTheme.border)
                    .frame(width: 0.5)
                    .padding(.leading, 44)
            }
        }
    }

    private var plainBody: some View {
        Text(indexWrappingAttributedText(text, lineBreakMode: lineBreakMode))
            .font(large ? ToolTypography.statValue : ToolTypography.codeBody)
            .foregroundStyle(large ? ToolTheme.accentHover : ToolTheme.textSecondary)
            .textSelection(.enabled)
            .lineLimit(nil)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .lineSpacing(6)
            .frame(maxWidth: .infinity, minHeight: effectiveMinHeight, alignment: centered ? .center : .topLeading)
            .padding(12)
    }

    private func colorizedBody(_ colorize: @escaping (String) -> AttributedString) -> some View {
        let lines = text.components(separatedBy: "\n")
        var combined = AttributedString()
        for (index, line) in lines.enumerated() {
            if index > 0 {
                combined.append(AttributedString("\n"))
            }
            // Empty lines keep a space so layout height matches the prior per-line path.
            combined.append(line.isEmpty ? AttributedString(" ") : colorize(line))
        }

        return Text(indexWrappingAttributedText(combined, lineBreakMode: lineBreakMode))
            .font(ToolTypography.codeBody)
            .textSelection(.enabled)
            .lineLimit(nil)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .lineSpacing(6)
            .frame(maxWidth: .infinity, minHeight: effectiveMinHeight, alignment: .topLeading)
            .padding(12)
    }

    private var gutteredBody: some View {
        let lines = text.components(separatedBy: "\n")
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                HStack(alignment: .top, spacing: 0) {
                    Text("\(index + 1)")
                        .font(ToolTypography.monoCaption)
                        .monospacedDigit()
                        .foregroundStyle(ToolTheme.textTertiary)
                        .frame(width: 34, alignment: .trailing)
                        .padding(.trailing, 10)
                    lineText(line)
                        .font(ToolTypography.codeBody)
                        .textSelection(.enabled)
                        .lineLimit(nil)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, 13)
                }
                .lineSpacing(6)
            }
        }
        .frame(maxWidth: .infinity, minHeight: effectiveMinHeight, alignment: .topLeading)
        .padding(.vertical, 12)
        .padding(.trailing, 13)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(ToolTheme.border)
                .frame(width: 0.5)
                .padding(.leading, 44)
        }
    }

    @ViewBuilder
    private func lineText(_ line: String) -> some View {
        if let colorize {
            Text(indexWrappingAttributedText(line.isEmpty ? AttributedString(" ") : colorize(line), lineBreakMode: lineBreakMode))
        } else {
            Text(indexWrappingAttributedText(line.isEmpty ? " " : line, lineBreakMode: lineBreakMode))
                .foregroundStyle(ToolTheme.textSecondary)
        }
    }
}
