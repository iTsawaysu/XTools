import AppKit
import SwiftUI
import XToolsCore

struct IndexControlledDateInput<TrailingAccessory: View>: View {
    @Binding private var input: ControlledDateInput

    private let placeholder: String
    private let timeZone: TimeZone
    private let autoFocus: Bool
    private let trailingInset: CGFloat
    private let helpText: String
    private let onCommit: (Date) -> Void
    private let onInvalidPaste: () -> Void
    private let onFocusChange: (Bool) -> Void
    private let trailingAccessory: () -> TrailingAccessory

    init(
        input: Binding<ControlledDateInput>,
        placeholder: String,
        timeZone: TimeZone = .current,
        autoFocus: Bool = false,
        trailingInset: CGFloat = 11,
        help: String = "支持输入 yyyy-MM-dd 或粘贴 yyyy/MM/dd",
        onCommit: @escaping (Date) -> Void,
        onInvalidPaste: @escaping () -> Void,
        onFocusChange: @escaping (Bool) -> Void = { _ in },
        @ViewBuilder trailingAccessory: @escaping () -> TrailingAccessory
    ) {
        self._input = input
        self.placeholder = placeholder
        self.timeZone = timeZone
        self.autoFocus = autoFocus
        self.trailingInset = trailingInset
        self.helpText = help
        self.onCommit = onCommit
        self.onInvalidPaste = onInvalidPaste
        self.onFocusChange = onFocusChange
        self.trailingAccessory = trailingAccessory
    }

    var body: some View {
        IndexControlledSegmentInput(
            adapter: Self.adapter(input: $input),
            placeholder: placeholder,
            timeZone: timeZone,
            autoFocus: autoFocus,
            trailingInset: trailingInset,
            helpText: helpText,
            onCommit: onCommit,
            onInvalidPaste: onInvalidPaste,
            onFocusChange: onFocusChange,
            trailingAccessory: trailingAccessory
        )
    }

    @MainActor
    private static func adapter(input: Binding<ControlledDateInput>) -> IndexControlledSegmentInputAdapter {
        IndexControlledSegmentInputAdapter(
            displayText: { input.wrappedValue.displayText },
            displayRangeForActiveSegment: {
                input.wrappedValue.displayRange(for: input.wrappedValue.activeSegment)
            },
            selectSegmentContainingOffset: { offset in
                input.wrappedValue.select(input.wrappedValue.segment(containingDisplayOffset: offset))
            },
            inputCharacter: { character, timeZone in
                input.wrappedValue.inputCharacter(character, timeZone: timeZone)
            },
            deleteBackward: {
                input.wrappedValue.deleteBackward()
            },
            paste: { text, timeZone in
                switch input.wrappedValue.paste(text, timeZone: timeZone) {
                case .accepted(let date):
                    return .accepted(date)
                case .rejected:
                    return .rejected
                }
            },
            commitActiveSegment: { timeZone in
                input.wrappedValue.commitActiveSegment(timeZone: timeZone)
            },
            canMovePrevious: {
                !input.wrappedValue.isFirstSegment
            },
            canMoveNext: {
                !input.wrappedValue.isLastSegment
            },
            movePrevious: {
                input.wrappedValue.movePrevious()
            },
            moveNext: {
                input.wrappedValue.moveNext()
            }
        )
    }
}

extension IndexControlledDateInput where TrailingAccessory == EmptyView {
    init(
        input: Binding<ControlledDateInput>,
        placeholder: String,
        timeZone: TimeZone = .current,
        autoFocus: Bool = false,
        trailingInset: CGFloat = 11,
        help: String = "支持输入 yyyy-MM-dd 或粘贴 yyyy/MM/dd",
        onCommit: @escaping (Date) -> Void,
        onInvalidPaste: @escaping () -> Void,
        onFocusChange: @escaping (Bool) -> Void = { _ in }
    ) {
        self.init(
            input: input,
            placeholder: placeholder,
            timeZone: timeZone,
            autoFocus: autoFocus,
            trailingInset: trailingInset,
            help: help,
            onCommit: onCommit,
            onInvalidPaste: onInvalidPaste,
            onFocusChange: onFocusChange
        ) {
            EmptyView()
        }
    }
}

struct IndexControlledHumanTimeInput<TrailingAccessory: View>: View {
    @Binding private var input: ControlledHumanTimeInput

    private let placeholder: String
    private let timeZone: TimeZone
    private let autoFocus: Bool
    private let trailingInset: CGFloat
    private let helpText: String
    private let onCommit: (Date) -> Void
    private let onInvalidPaste: () -> Void
    private let onFocusChange: (Bool) -> Void
    private let trailingAccessory: () -> TrailingAccessory

    init(
        input: Binding<ControlledHumanTimeInput>,
        placeholder: String,
        timeZone: TimeZone = .current,
        autoFocus: Bool = false,
        trailingInset: CGFloat = 11,
        help: String = "支持粘贴 ISO 8601 或 yyyy-MM-dd HH:mm:ss",
        onCommit: @escaping (Date) -> Void,
        onInvalidPaste: @escaping () -> Void,
        onFocusChange: @escaping (Bool) -> Void = { _ in },
        @ViewBuilder trailingAccessory: @escaping () -> TrailingAccessory
    ) {
        self._input = input
        self.placeholder = placeholder
        self.timeZone = timeZone
        self.autoFocus = autoFocus
        self.trailingInset = trailingInset
        self.helpText = help
        self.onCommit = onCommit
        self.onInvalidPaste = onInvalidPaste
        self.onFocusChange = onFocusChange
        self.trailingAccessory = trailingAccessory
    }

    var body: some View {
        IndexControlledSegmentInput(
            adapter: Self.adapter(input: $input),
            placeholder: placeholder,
            timeZone: timeZone,
            autoFocus: autoFocus,
            trailingInset: trailingInset,
            helpText: helpText,
            onCommit: onCommit,
            onInvalidPaste: onInvalidPaste,
            onFocusChange: onFocusChange,
            trailingAccessory: trailingAccessory
        )
    }

    @MainActor
    private static func adapter(input: Binding<ControlledHumanTimeInput>) -> IndexControlledSegmentInputAdapter {
        IndexControlledSegmentInputAdapter(
            displayText: { input.wrappedValue.displayText },
            displayRangeForActiveSegment: {
                input.wrappedValue.displayRange(for: input.wrappedValue.activeSegment)
            },
            selectSegmentContainingOffset: { offset in
                input.wrappedValue.select(input.wrappedValue.segment(containingDisplayOffset: offset))
            },
            inputCharacter: { character, timeZone in
                input.wrappedValue.inputCharacter(character, timeZone: timeZone)
            },
            deleteBackward: {
                input.wrappedValue.deleteBackward()
            },
            paste: { text, timeZone in
                switch input.wrappedValue.paste(text, timeZone: timeZone) {
                case .accepted(let date):
                    return .accepted(date)
                case .rejected:
                    return .rejected
                }
            },
            commitActiveSegment: { timeZone in
                input.wrappedValue.commitActiveSegment(timeZone: timeZone)
            },
            canMovePrevious: {
                !input.wrappedValue.isFirstSegment
            },
            canMoveNext: {
                !input.wrappedValue.isLastSegment
            },
            movePrevious: {
                input.wrappedValue.movePrevious()
            },
            moveNext: {
                input.wrappedValue.moveNext()
            }
        )
    }
}

extension IndexControlledHumanTimeInput where TrailingAccessory == EmptyView {
    init(
        input: Binding<ControlledHumanTimeInput>,
        placeholder: String,
        timeZone: TimeZone = .current,
        autoFocus: Bool = false,
        trailingInset: CGFloat = 11,
        help: String = "支持粘贴 ISO 8601 或 yyyy-MM-dd HH:mm:ss",
        onCommit: @escaping (Date) -> Void,
        onInvalidPaste: @escaping () -> Void,
        onFocusChange: @escaping (Bool) -> Void = { _ in }
    ) {
        self.init(
            input: input,
            placeholder: placeholder,
            timeZone: timeZone,
            autoFocus: autoFocus,
            trailingInset: trailingInset,
            help: help,
            onCommit: onCommit,
            onInvalidPaste: onInvalidPaste,
            onFocusChange: onFocusChange
        ) {
            EmptyView()
        }
    }
}

private struct IndexControlledSegmentInput<TrailingAccessory: View>: View {
    let adapter: IndexControlledSegmentInputAdapter
    let placeholder: String
    let timeZone: TimeZone
    let autoFocus: Bool
    let trailingInset: CGFloat
    let helpText: String
    let onCommit: (Date) -> Void
    let onInvalidPaste: () -> Void
    let onFocusChange: (Bool) -> Void
    let trailingAccessory: () -> TrailingAccessory

    @State private var isFocused = false

    var body: some View {
        IndexControlledSegmentInputRepresentable(
            adapter: adapter,
            placeholder: placeholder,
            timeZone: timeZone,
            autoFocus: autoFocus,
            contentInsets: IndexTextFieldContentInsets(leading: 11, trailing: trailingInset),
            onCommit: onCommit,
            onInvalidPaste: onInvalidPaste,
            onFocusChange: { focused in
                isFocused = focused
                onFocusChange(focused)
            }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .frame(height: 38)
        .background(ToolTheme.editorBackground, in: RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.field, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.field, style: .continuous)
                .strokeBorder(isFocused ? ToolTheme.focusRing : ToolTheme.border, lineWidth: isFocused ? 1.5 : 0.5)
        }
        .overlay(alignment: .trailing) {
            trailingAccessory()
        }
        .help(helpText)
        .toolAnimation(ToolMotion.Preset.controlFeedback, value: isFocused)
    }
}

private enum IndexControlledSegmentPasteResult {
    case accepted(Date)
    case rejected
}

@MainActor
private struct IndexControlledSegmentInputAdapter {
    let displayText: () -> String
    let displayRangeForActiveSegment: () -> Range<Int>?
    let selectSegmentContainingOffset: (Int) -> Void
    let inputCharacter: (Character, TimeZone) -> Date?
    let deleteBackward: () -> Void
    let paste: (String, TimeZone) -> IndexControlledSegmentPasteResult
    let commitActiveSegment: (TimeZone) -> Date?
    let canMovePrevious: () -> Bool
    let canMoveNext: () -> Bool
    let movePrevious: () -> Void
    let moveNext: () -> Void
}

private struct IndexControlledSegmentInputRepresentable: NSViewRepresentable {
    let adapter: IndexControlledSegmentInputAdapter
    let placeholder: String
    let timeZone: TimeZone
    let autoFocus: Bool
    let contentInsets: IndexTextFieldContentInsets
    let onCommit: (Date) -> Void
    let onInvalidPaste: () -> Void
    let onFocusChange: (Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            adapter: adapter,
            timeZone: timeZone,
            onCommit: onCommit,
            onInvalidPaste: onInvalidPaste,
            onFocusChange: onFocusChange
        )
    }

    func makeNSView(context: Context) -> IndexControlledSegmentNSTextField {
        let textField = IndexControlledSegmentNSTextField()
        textField.segmentHandler = context.coordinator
        textField.delegate = context.coordinator
        configure(textField)
        textField.stringValue = adapter.displayText()
        if autoFocus {
            context.coordinator.focus(textField)
        }
        return textField
    }

    func updateNSView(_ textField: IndexControlledSegmentNSTextField, context: Context) {
        context.coordinator.adapter = adapter
        context.coordinator.timeZone = timeZone
        context.coordinator.onCommit = onCommit
        context.coordinator.onInvalidPaste = onInvalidPaste
        context.coordinator.onFocusChange = onFocusChange
        textField.segmentHandler = context.coordinator
        configure(textField)
        context.coordinator.syncTextField(textField)
        if autoFocus {
            context.coordinator.focus(textField)
        }
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        nsView textField: IndexControlledSegmentNSTextField,
        context: Context
    ) -> CGSize? {
        guard let height = proposal.height else { return nil }
        return CGSize(width: proposal.width ?? textField.fittingSize.width, height: height)
    }

    private func configure(_ textField: NSTextField) {
        textField.placeholderString = placeholder
        textField.font = .monospacedSystemFont(ofSize: 12.5, weight: .regular)
        textField.textColor = .labelColor
        textField.alignment = .left
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

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate, IndexControlledSegmentFieldHandling {
        var adapter: IndexControlledSegmentInputAdapter
        var timeZone: TimeZone
        var onCommit: (Date) -> Void
        var onInvalidPaste: () -> Void
        var onFocusChange: (Bool) -> Void

        private var didFocus = false

        init(
            adapter: IndexControlledSegmentInputAdapter,
            timeZone: TimeZone,
            onCommit: @escaping (Date) -> Void,
            onInvalidPaste: @escaping () -> Void,
            onFocusChange: @escaping (Bool) -> Void
        ) {
            self.adapter = adapter
            self.timeZone = timeZone
            self.onCommit = onCommit
            self.onInvalidPaste = onInvalidPaste
            self.onFocusChange = onFocusChange
        }

        func focus(_ textField: NSTextField) {
            guard !didFocus else { return }
            didFocus = true
            DispatchQueue.main.async {
                textField.window?.makeFirstResponder(textField)
            }
        }

        func controlTextDidBeginEditing(_ notification: Notification) {
            if let textField = notification.object as? NSTextField {
                enablePlainEditing(in: textField)
                syncTextField(textField)
            }
            onFocusChange(true)
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            if let date = adapter.commitActiveSegment(timeZone) {
                onCommit(date)
            }
            if let textField = notification.object as? NSTextField {
                syncTextField(textField)
            }
            onFocusChange(false)
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let textField = notification.object as? NSTextField else { return }
            syncTextField(textField)
        }

        func handleKeyDown(_ event: NSEvent, in textField: IndexControlledSegmentNSTextField) -> Bool {
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard !modifiers.contains(.command) else { return false }

            switch event.keyCode {
            case 48:
                return handleTab(from: textField, direction: modifiers.contains(.shift) ? .previous : .next)
            case 36, 76:
                commit(from: textField)
                textField.window?.makeFirstResponder(nil)
                return true
            case 51, 117:
                adapter.deleteBackward()
                syncTextField(textField)
                return true
            case 123:
                commitAndMove(from: textField, direction: .previous)
                return true
            case 124:
                commitAndMove(from: textField, direction: .next)
                return true
            default:
                break
            }

            guard !modifiers.contains(.control), !modifiers.contains(.option),
                  let character = event.charactersIgnoringModifiers?.first else {
                return true
            }

            if let date = adapter.inputCharacter(character, timeZone) {
                onCommit(date)
            }
            syncTextField(textField)
            return true
        }

        func handlePaste(in textField: IndexControlledSegmentNSTextField) -> Bool {
            let text = NSPasteboard.general.string(forType: .string) ?? ""
            switch adapter.paste(text, timeZone) {
            case .accepted(let date):
                onCommit(date)
            case .rejected:
                onInvalidPaste()
            }
            syncTextField(textField)
            return true
        }

        func handleClick(atDisplayOffset offset: Int, in textField: IndexControlledSegmentNSTextField) {
            if let date = adapter.commitActiveSegment(timeZone) {
                onCommit(date)
            }
            adapter.selectSegmentContainingOffset(offset)
            syncTextField(textField)
        }

        func syncTextField(_ textField: NSTextField) {
            let nextText = adapter.displayText()
            if textField.stringValue != nextText {
                textField.stringValue = nextText
            }
            selectActiveSegment(in: textField)
        }

        private enum SegmentMoveDirection {
            case previous
            case next
        }

        private func commit(from textField: NSTextField) {
            if let date = adapter.commitActiveSegment(timeZone) {
                onCommit(date)
            }
            syncTextField(textField)
        }

        private func handleTab(
            from textField: NSTextField,
            direction: SegmentMoveDirection
        ) -> Bool {
            if let date = adapter.commitActiveSegment(timeZone) {
                onCommit(date)
            }

            let canMove = direction == .next ? adapter.canMoveNext() : adapter.canMovePrevious()
            guard canMove else {
                syncTextField(textField)
                return false
            }

            move(direction)
            syncTextField(textField)
            return true
        }

        private func commitAndMove(from textField: NSTextField, direction: SegmentMoveDirection) {
            if let date = adapter.commitActiveSegment(timeZone) {
                onCommit(date)
            }
            if (direction == .next ? adapter.canMoveNext() : adapter.canMovePrevious()) {
                move(direction)
            }
            syncTextField(textField)
        }

        private func move(_ direction: SegmentMoveDirection) {
            switch direction {
            case .previous:
                adapter.movePrevious()
            case .next:
                adapter.moveNext()
            }
        }

        private func selectActiveSegment(in textField: NSTextField) {
            guard let editor = textField.currentEditor(),
                  !textField.stringValue.isEmpty,
                  let range = adapter.displayRangeForActiveSegment() else {
                return
            }

            editor.selectedRange = NSRange(location: range.lowerBound, length: range.count)
        }

        private func enablePlainEditing(in textField: NSTextField) {
            AppKitTextEditingConfiguration.configureCurrentFieldEditor(for: textField)
        }
    }
}

@MainActor
protocol IndexControlledSegmentFieldHandling: AnyObject {
    func handleKeyDown(_ event: NSEvent, in textField: IndexControlledSegmentNSTextField) -> Bool
    func handlePaste(in textField: IndexControlledSegmentNSTextField) -> Bool
    func handleClick(atDisplayOffset offset: Int, in textField: IndexControlledSegmentNSTextField)
}

final class IndexControlledSegmentNSTextField: IndexPaddedTextField {
    override class var cellClass: AnyClass? {
        get { IndexControlledSegmentTextFieldCell.self }
        set {}
    }

    weak var segmentHandler: (any IndexControlledSegmentFieldHandling)? {
        didSet {
            (cell as? IndexControlledSegmentTextFieldCell)?.segmentHandler = segmentHandler
        }
    }

    override func keyDown(with event: NSEvent) {
        if segmentHandler?.handleKeyDown(event, in: self) == true {
            return
        }
        super.keyDown(with: event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if modifiers.contains(.command),
           event.charactersIgnoringModifiers?.lowercased() == "v",
           segmentHandler?.handlePaste(in: self) == true {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    @objc func paste(_ sender: Any?) {
        if segmentHandler?.handlePaste(in: self) == true {
            return
        }
    }

    override func mouseDown(with event: NSEvent) {
        let wasEditing = currentEditor() != nil
        super.mouseDown(with: event)
        let offset = displayOffset(for: event)

        if wasEditing {
            // While editing, clicks inside the text frame go straight to the
            // custom field editor. Inset whitespace still lands on the text
            // field, so route that native selection synchronously instead of
            // dropping the click or scheduling a stale first-click callback.
            segmentHandler?.handleClick(atDisplayOffset: offset, in: self)
            return
        }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.segmentHandler?.handleClick(atDisplayOffset: offset, in: self)
        }
    }

    private func displayOffset(for event: NSEvent) -> Int {
        guard let editor = currentEditor() as? NSTextView else { return 0 }
        let editorPoint = editor.convert(event.locationInWindow, from: nil)
        let singleLinePoint = NSPoint(x: editorPoint.x, y: editor.bounds.midY)
        let nativeOffset = editor.characterIndexForInsertion(at: singleLinePoint)
        guard nativeOffset != NSNotFound else {
            return editor.selectedRange.location
        }
        return min(nativeOffset, stringValue.utf16.count)
    }
}

final class IndexControlledSegmentTextFieldCell: IndexPaddedTextFieldCell {
    weak var segmentHandler: (any IndexControlledSegmentFieldHandling)? {
        didSet {
            segmentEditor?.segmentHandler = segmentHandler
        }
    }

    private weak var textField: IndexControlledSegmentNSTextField?
    private var segmentEditor: IndexControlledSegmentFieldEditor?

    override func fieldEditor(for controlView: NSView) -> NSTextView? {
        if let textField = controlView as? IndexControlledSegmentNSTextField {
            self.textField = textField
            segmentHandler = textField.segmentHandler
        }

        if let segmentEditor {
            segmentEditor.textField = textField
            segmentEditor.segmentHandler = segmentHandler
            return segmentEditor
        }

        let editor = IndexControlledSegmentFieldEditor(frame: .zero)
        editor.isFieldEditor = true
        editor.textField = textField
        editor.segmentHandler = segmentHandler
        segmentEditor = editor
        return editor
    }
}

final class IndexControlledSegmentFieldEditor: NSTextView {
    private let caretWidth: CGFloat = 2

    weak var textField: IndexControlledSegmentNSTextField?
    weak var segmentHandler: (any IndexControlledSegmentFieldHandling)?

    // Private undo stack that lives and dies with this per-cell field editor, so
    // ⌘Z never resolves to the shared window undo manager and pops an action
    // whose target (a torn-down text object) has been freed. See ADR-0022.
    private let boundedUndoManager = UndoManager()
    override var undoManager: UndoManager? { boundedUndoManager }

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

    override func keyDown(with event: NSEvent) {
        if let textField, segmentHandler?.handleKeyDown(event, in: textField) == true {
            return
        }
        super.keyDown(with: event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if modifiers.contains(.command),
           event.charactersIgnoringModifiers?.lowercased() == "v",
           let textField,
           segmentHandler?.handlePaste(in: textField) == true {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    @objc override func paste(_ sender: Any?) {
        if let textField, segmentHandler?.handlePaste(in: textField) == true {
            return
        }
        super.paste(sender)
    }

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        routeClick()
    }

    func routeClick() {
        guard let textField else { return }
        let offset = selectedRange.location
        segmentHandler?.handleClick(atDisplayOffset: offset, in: textField)
    }
}
