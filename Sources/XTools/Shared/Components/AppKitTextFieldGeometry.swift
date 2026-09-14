import AppKit

struct IndexTextFieldContentInsets: Equatable, Sendable {
    var leading: CGFloat
    var trailing: CGFloat

    static let zero = IndexTextFieldContentInsets(leading: 0, trailing: 0)
}

enum IndexTextFieldContentGeometry {
    static func contentBounds(
        in bounds: NSRect,
        insets: IndexTextFieldContentInsets
    ) -> NSRect {
        let leading = max(0, insets.leading)
        let trailing = max(0, insets.trailing)
        let width = bounds.width - leading - trailing

        guard width > 0 else {
            return NSRect(x: bounds.midX, y: bounds.minY, width: 0, height: bounds.height)
        }

        return NSRect(
            x: bounds.minX + leading,
            y: bounds.minY,
            width: width,
            height: bounds.height
        )
    }

    static func textFrame(
        in bounds: NSRect,
        insets: IndexTextFieldContentInsets,
        lineHeight: CGFloat
    ) -> NSRect {
        let contentBounds = contentBounds(in: bounds, insets: insets)
        let height = min(contentBounds.height, max(0, lineHeight))

        return NSRect(
            x: contentBounds.minX,
            y: contentBounds.midY - (height / 2),
            width: contentBounds.width,
            height: height
        )
    }
}

@MainActor
protocol IndexTextFieldContentInsetConfiguring: AnyObject {
    var contentInsets: IndexTextFieldContentInsets { get set }
}

/// Owns a private undo stack so plain fields never resolve ⌘Z to the shared
/// window undo manager — the use-after-free crash path (ADR-0022).
final class IndexUndoIsolatedFieldEditor: NSTextView {
    private let boundedUndoManager = UndoManager()
    override var undoManager: UndoManager? { boundedUndoManager }
}

class IndexPaddedTextFieldCell: NSTextFieldCell, IndexTextFieldContentInsetConfiguring {
    var contentInsets = IndexTextFieldContentInsets.zero {
        didSet {
            controlView?.needsDisplay = true
        }
    }

    private var isolatedFieldEditor: IndexUndoIsolatedFieldEditor?

    override func fieldEditor(for controlView: NSView) -> NSTextView? {
        if let isolatedFieldEditor { return isolatedFieldEditor }
        let editor = IndexUndoIsolatedFieldEditor(frame: .zero)
        editor.isFieldEditor = true
        // A field editor has undo registration off by default. Without this ⌘Z
        // does nothing in the plain search fields, and the undo action falls
        // through the responder chain to the shared window manager (the crash
        // path). Enabling it keeps undo working and scoped to the private stack.
        editor.allowsUndo = true
        isolatedFieldEditor = editor
        return editor
    }

    func textFrame(forBounds bounds: NSRect) -> NSRect {
        let contentBounds = IndexTextFieldContentGeometry.contentBounds(in: bounds, insets: contentInsets)
        // NSTextFieldCell.titleRect consults drawingRect internally. Keep
        // drawingRect inherited; routing it back here would recurse forever.
        let baseRect = super.titleRect(forBounds: contentBounds)
        let lineHeight = min(baseRect.height, super.cellSize(forBounds: contentBounds).height)
        return IndexTextFieldContentGeometry.textFrame(
            in: bounds,
            insets: contentInsets,
            lineHeight: lineHeight
        )
    }

    override func titleRect(forBounds rect: NSRect) -> NSRect {
        textFrame(forBounds: rect)
    }

    override func drawInterior(withFrame cellFrame: NSRect, in controlView: NSView) {
        super.drawInterior(withFrame: textFrame(forBounds: cellFrame), in: controlView)
    }

    override func edit(
        withFrame aRect: NSRect,
        in controlView: NSView,
        editor textObj: NSText,
        delegate anObject: Any?,
        event: NSEvent?
    ) {
        super.edit(
            withFrame: textFrame(forBounds: aRect),
            in: controlView,
            editor: textObj,
            delegate: anObject,
            event: event
        )
    }

    override func select(
        withFrame aRect: NSRect,
        in controlView: NSView,
        editor textObj: NSText,
        delegate anObject: Any?,
        start selStart: Int,
        length selLength: Int
    ) {
        super.select(
            withFrame: textFrame(forBounds: aRect),
            in: controlView,
            editor: textObj,
            delegate: anObject,
            start: selStart,
            length: selLength
        )
    }
}

final class IndexPaddedSecureTextFieldCell: NSSecureTextFieldCell, IndexTextFieldContentInsetConfiguring {
    var contentInsets = IndexTextFieldContentInsets.zero {
        didSet {
            controlView?.needsDisplay = true
        }
    }

    func textFrame(forBounds bounds: NSRect) -> NSRect {
        let contentBounds = IndexTextFieldContentGeometry.contentBounds(in: bounds, insets: contentInsets)
        // See the plain cell above: drawingRect must remain inherited because
        // AppKit's titleRect implementation calls it internally.
        let baseRect = super.titleRect(forBounds: contentBounds)
        let lineHeight = min(baseRect.height, super.cellSize(forBounds: contentBounds).height)
        return IndexTextFieldContentGeometry.textFrame(
            in: bounds,
            insets: contentInsets,
            lineHeight: lineHeight
        )
    }

    override func titleRect(forBounds rect: NSRect) -> NSRect {
        textFrame(forBounds: rect)
    }

    override func drawInterior(withFrame cellFrame: NSRect, in controlView: NSView) {
        super.drawInterior(withFrame: textFrame(forBounds: cellFrame), in: controlView)
    }

    override func edit(
        withFrame aRect: NSRect,
        in controlView: NSView,
        editor textObj: NSText,
        delegate anObject: Any?,
        event: NSEvent?
    ) {
        super.edit(
            withFrame: textFrame(forBounds: aRect),
            in: controlView,
            editor: textObj,
            delegate: anObject,
            event: event
        )
    }

    override func select(
        withFrame aRect: NSRect,
        in controlView: NSView,
        editor textObj: NSText,
        delegate anObject: Any?,
        start selStart: Int,
        length selLength: Int
    ) {
        super.select(
            withFrame: textFrame(forBounds: aRect),
            in: controlView,
            editor: textObj,
            delegate: anObject,
            start: selStart,
            length: selLength
        )
    }
}

class IndexPaddedTextField: NSTextField {
    override class var cellClass: AnyClass? {
        get { IndexPaddedTextFieldCell.self }
        set {}
    }

    var contentInsets: IndexTextFieldContentInsets {
        get { indexContentInsets }
        set { indexContentInsets = newValue }
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .iBeam)
    }
}

final class IndexPaddedSecureTextField: NSSecureTextField {
    /// Secure text fields use AppKit's shared `NSSecureTextView` field editor.
    /// Keep the undo history with this field instance instead of allowing the
    /// editor to resolve through the window responder chain. The field owns
    /// this manager for exactly as long as its binding/identity does.
    private let secureUndoManager = UndoManager()

    override class var cellClass: AnyClass? {
        get { IndexPaddedSecureTextFieldCell.self }
        set {}
    }

    /// AppKit asks the secure field (the system editor's delegate) for its
    /// undo manager. Keep the official NSTextViewDelegate hook so the secure
    /// editor remains the system implementation and all existing secure-field
    /// behavior stays intact.
    @objc(undoManagerForTextView:)
    func undoManager(for view: NSTextView) -> UndoManager? {
        secureUndoManager
    }

    /// Programmatic binding replacement is a new text baseline. Clearing both
    /// directions prevents an old secure editor action from targeting ranges
    /// in the previous value when this field is focused again.
    func setStringFromExternalBinding(_ newValue: String) {
        secureUndoManager.disableUndoRegistration()
        defer {
            secureUndoManager.enableUndoRegistration()
            secureUndoManager.removeAllActions()
        }
        stringValue = newValue
    }

    var contentInsets: IndexTextFieldContentInsets {
        get { indexContentInsets }
        set { indexContentInsets = newValue }
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .iBeam)
    }
}

extension NSTextField {
    var indexContentInsets: IndexTextFieldContentInsets {
        get {
            (cell as? any IndexTextFieldContentInsetConfiguring)?.contentInsets ?? .zero
        }
        set {
            (cell as? any IndexTextFieldContentInsetConfiguring)?.contentInsets = newValue
            needsDisplay = true
        }
    }
}
