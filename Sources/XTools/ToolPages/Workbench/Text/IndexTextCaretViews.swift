import AppKit
import SwiftUI
import XToolsCore

// MARK: - Caret

/// Shared 2pt caret widening for native text surfaces: the hairline 1pt
/// insertion point is nearly invisible, so every custom text view widens
/// both the caret draw rect and its invalidation rect by the same amount.
///
/// Also hosts the shared drag-and-drop / IME skeleton for editable text
/// surfaces: subclasses keep their own differences (hover highlight, drop
/// diagnostics, shared drop gates) through the three small hooks, while the
/// drag session overrides, composition callbacks, and pasteboard helpers
/// stay in one place.
class IndexCaretWideningTextView: NSTextView {
    let caretWidth: CGFloat = 2

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

    // MARK: IME composition feedback

    /// Fired whenever IME composition (marked text) starts or ends. Lets a
    /// host keep workspace state (e.g. undo baselines) aligned with composition.
    var onCompositionChange: ((Bool) -> Void)?

    override func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        super.setMarkedText(string, selectedRange: selectedRange, replacementRange: replacementRange)
        onCompositionChange?(hasMarkedText())
    }

    override func unmarkText() {
        super.unmarkText()
        onCompositionChange?(false)
    }

    // MARK: Text file drop skeleton

    var onFileDrop: ((String) -> Void)?

    /// A drop session was accepted (entered/updated over droppable content).
    /// Subclasses add their own feedback here; the base keeps none.
    func acceptDropSession() {}

    /// A drop session ended or the pending file finished loading. Subclasses
    /// clear their own feedback here.
    func endDropSession() {}

    /// A local text change happened: subclasses invalidate their pending drop
    /// gate and any transient diagnostics tied to it.
    func invalidateDropState() {}

    /// The view detached from its window: pending drop reads become obsolete,
    /// but surfaces without drop diagnostics only invalidate the gate.
    func invalidatePendingDropRead() {}

    /// Load the accepted drop URL; subclasses own their gate and diagnostics
    /// wiring around the shared `IndexDroppedTextFile` reader.
    func loadDroppedFile(from url: URL) {}

    override func didChangeText() {
        invalidateDropState()
        super.didChangeText()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { invalidatePendingDropRead() }
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        if onFileDrop != nil && Self.hasDroppableFile(sender) {
            acceptDropSession()
            return .copy
        }
        return super.draggingEntered(sender)
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        if onFileDrop != nil && Self.hasDroppableFile(sender) {
            acceptDropSession()
            return .copy
        }
        return super.draggingUpdated(sender)
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        guard onFileDrop != nil, let url = Self.droppedFileURL(sender) else {
            return super.performDragOperation(sender)
        }
        endDropSession()
        loadDroppedFile(from: url)
        return true
    }

    static func hasDroppableFile(_ sender: any NSDraggingInfo) -> Bool {
        guard let types = sender.draggingPasteboard.types else { return false }
        return types.contains(.fileURL)
            || types.contains(NSPasteboard.PasteboardType("public.file-url"))
            || types.contains(NSPasteboard.PasteboardType("NSFilenamesPboardType"))
    }

    static func droppedFileURL(_ sender: any NSDraggingInfo) -> URL? {
        if let fileURLs = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
           let first = fileURLs.first {
            return first
        } else if let filenames = sender.draggingPasteboard.propertyList(forType: NSPasteboard.PasteboardType("NSFilenamesPboardType")) as? [String],
                  let first = filenames.first {
            return URL(fileURLWithPath: first)
        }
        return nil
    }
}

final class IndexCaretTextView: IndexCaretWideningTextView, IndexAsymmetricTextContainerSurface {
    private var droppedFile: IndexDroppedTextFile?
    var sharedDroppedFile: IndexDroppedTextFile? {
        didSet {
            if oldValue !== sharedDroppedFile { oldValue?.invalidate(ownedBy: self) }
            sharedDroppedFile?.attach(to: self)
        }
    }

    private var activeDroppedFile: IndexDroppedTextFile? { sharedDroppedFile ?? droppedFile }
    var leadingTextContainerInset: CGFloat {
        textContainerInset.width
    }

    /// Private undo stack used only when this view acts as a single-line field
    private let fieldEditorUndo = IndexPrivateUndoStack()

    override var undoManager: UndoManager? {
        isFieldEditor ? fieldEditorUndo.manager : super.undoManager
    }

    // Drop-session feedback: this surface paints a targeted highlight while a
    // droppable session hovers, and invalidates through the shared/own gate.

    override func acceptDropSession() {
        activeDroppedFile?.setDropTargeted(true)
    }

    override func endDropSession() {
        activeDroppedFile?.setDropTargeted(false)
    }

    override func invalidateDropState() {
        activeDroppedFile?.invalidate(ownedBy: self)
    }

    override func invalidatePendingDropRead() {
        activeDroppedFile?.invalidate(ownedBy: self)
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        activeDroppedFile?.setDropTargeted(false)
        super.draggingExited(sender)
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        activeDroppedFile?.setDropTargeted(false)
        super.draggingEnded(sender)
    }

    override func loadDroppedFile(from url: URL) {
        if activeDroppedFile == nil { droppedFile = IndexDroppedTextFile(view: self) }
        activeDroppedFile?.start(url: url) { [weak self] content in
            self?.onFileDrop?(content)
        }
    }

    func invalidateDroppedFile() {
        activeDroppedFile?.invalidate(ownedBy: self)
    }

    nonisolated static func readDroppedContent(from url: URL) -> String? {
        if case .loaded(let content) = readDroppedOutcome(from: url) { return content }
        return nil
    }

    nonisolated static func readDroppedOutcome(from url: URL) -> IndexDroppedTextOutcome {
        guard url.isFileURL else { return .rejected(.unreadable) }
        let scopedOriginal = url.startAccessingSecurityScopedResource()
        let resolvedURL = url.resolvingSymlinksInPath()
        let scopedResolved = resolvedURL != url
            ? resolvedURL.startAccessingSecurityScopedResource()
            : false
        defer {
            if scopedResolved { resolvedURL.stopAccessingSecurityScopedResource() }
            if scopedOriginal { url.stopAccessingSecurityScopedResource() }
        }
        let values: URLResourceValues
        do {
            values = try resolvedURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        } catch {
            return .rejected(.unreadable)
        }
        guard values.isRegularFile == true else {
            return .rejected(.notRegularFile)
        }
        if let fileSize = values.fileSize, fileSize > IndexDroppedTextRejection.maximumBytes {
            return .rejected(.tooLarge)
        }
        do {
            let data = try BoundedFileReader.read(from: resolvedURL, maxBytes: IndexDroppedTextRejection.maximumBytes)
            guard let content = decodeDroppedContent(data) else { return .rejected(.invalidEncoding) }
            return .loaded(content)
        } catch is CancellationError {
            return .cancelled
        } catch BoundedFileReader.ReadError.tooLarge {
            return .rejected(.tooLarge)
        } catch {
            return .rejected(.unreadable)
        }
    }

    nonisolated static func decodeDroppedContent(_ data: Data) -> String? {
        if let utf8 = String(data: data, encoding: .utf8) { return utf8 }
        // Foundation's UTF-16 decoder silently ignores a trailing odd byte.
        // Reject a partial code unit instead of importing truncated source.
        guard data.count.isMultiple(of: 2) else { return nil }
        return String(data: data, encoding: .utf16)
    }
}

enum IndexDroppedTextRejection: Equatable, Sendable {
    static let maximumBytes = 15_000_000
    case notRegularFile, tooLarge, invalidEncoding, unreadable

    var message: String {
        switch self {
        case .notRegularFile: return "只能导入普通文本文件，原输入已保留。"
        case .tooLarge: return "文件超过 15 MB 导入上限，原输入已保留。"
        case .invalidEncoding: return "文件不是有效的 UTF-8 或 UTF-16 文本，原输入已保留。"
        case .unreadable: return "无法读取文件，原输入已保留。"
        }
    }
}

enum IndexDroppedTextOutcome: Sendable {
    case loaded(String)
    case rejected(IndexDroppedTextRejection)
    case cancelled
}

@MainActor
final class IndexDroppedTextFile: ObservableObject {
    @Published private(set) var rejection: IndexDroppedTextRejection?
    /// 文件拖拽悬停态：由真正认领拖拽会话的 NSTextView 回调驱动
    /// （draggingEntered/Updated 置 true，exited/ended/perform 置 false），
    /// 供工作台在输入面上画 targeted 反馈——SwiftUI 外层 onDrop 收不到回调。
    @Published private(set) var isDropTargeted = false

    func setDropTargeted(_ targeted: Bool) {
        isDropTargeted = targeted
    }
    private weak var view: NSTextView?
    private let gate = AsyncWorkGate()
    private let reader: @Sendable (URL) async -> IndexDroppedTextOutcome

    init(
        view: NSTextView? = nil,
        outcomeReader: @escaping @Sendable (URL) async -> IndexDroppedTextOutcome = { IndexCaretTextView.readDroppedOutcome(from: $0) }
    ) {
        self.view = view
        self.reader = outcomeReader
    }

    convenience init(view: NSTextView? = nil, reader: @escaping @Sendable (URL) async -> String?) {
        self.init(view: view, outcomeReader: { url in
            if let text = await reader(url) { return .loaded(text) }
            return .rejected(.unreadable)
        })
    }

    func dismissRejection() {
        rejection = nil
    }

    func rejectUnreadableDrop() {
        rejection = .unreadable
    }

    func attach(to view: NSTextView) {
        if self.view !== view {
            gate.invalidate()
            self.view = view
        }
    }

    @discardableResult
    func invalidate() -> Int { gate.invalidate() }

    func invalidate(ownedBy view: NSTextView) {
        if self.view === view { gate.invalidate() }
    }

    func isCurrent(_ token: Int) -> Bool { gate.isCurrent(token) }

    func start(
        url: URL,
        onRejected: (@MainActor (IndexDroppedTextRejection) -> Void)? = nil,
        publish: @escaping @MainActor (String) -> Void
    ) {
        guard let view, view.window != nil else { return }
        rejection = nil
        gate.invalidate()
        let reader = reader
        gate.runDetached {
            await reader(url)
        } publish: { [weak self, weak view] outcome in
            guard let self, let view, view.window != nil else { return }
            switch outcome {
            case .loaded(let content): publish(content)
            case .rejected(let rejection):
                self.rejection = rejection
                onRejected?(rejection)
            case .cancelled: break
            }
        }
    }
}

private final class IndexCaretTextFieldCell: IndexPaddedTextFieldCell {
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
    /// external binding must not push onto the undo stack, or the programmatic
    /// write would swallow the user's most recent manual undo.
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

