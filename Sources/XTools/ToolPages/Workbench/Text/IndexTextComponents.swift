import AppKit
import SwiftUI
import XToolsCore

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
    /// Drops the field box so an owning container (e.g. the format workbench's
    /// input header) supplies the shared surface edge.
    var embedsFlat = false
    var onSubmit: (() -> Void)? = nil
    var onEscape: (() -> Void)? = nil
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
            onEscape: onEscape,
            onFocusChange: { focused in
                isFocused = focused
                onFocusChange?(focused)
            }
        )
        .id(secure)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .frame(height: height)
        .background(
            embedsFlat ? Color.clear : ToolTheme.editorBackground,
            in: RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.field, style: .continuous)
        )
        .overlay {
            if !embedsFlat {
                RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.field, style: .continuous)
                    .strokeBorder(isFocused ? ToolTheme.focusRing : ToolTheme.border, lineWidth: isFocused ? 1.5 : 0.5)
            }
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
                .arrowCursorOnHover()
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
    let onEscape: (() -> Void)?
    let onFocusChange: ((Bool) -> Void)?
    // 停靠保活后回访不再重建视图；进入聚焦以代际驱动保持「每次进入聚焦」语义。
    @Environment(\.toolPageEntryGeneration) private var entryGeneration: Int

    func makeCoordinator() -> Coordinator {
        Coordinator(
            text: $text,
            allowsCopy: allowsCopy,
            selectAllOnFocus: selectAllOnFocus,
            onSubmit: onSubmit,
            onEscape: onEscape,
            onFocusChange: onFocusChange
        )
    }

    func makeNSView(context: Context) -> NSTextField {
        let textField: NSTextField = secure ? IndexPaddedSecureTextField() : IndexCaretTextField()
        configure(textField)
        textField.delegate = context.coordinator
        textField.stringValue = text
        if autoFocus {
            context.coordinator.focus(
                textField,
                entryGeneration: entryGeneration,
                entryTraceContext: entryTraceContext,
                placeholder: placeholder
            )
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
        context.coordinator.onEscape = onEscape
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
            context.coordinator.focus(
                textField,
                entryGeneration: entryGeneration,
                entryTraceContext: entryTraceContext,
                placeholder: placeholder
            )
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
        AppKitTextEditingConfiguration.applyBorderlessBodyStyle(
            textField,
            placeholder: placeholder,
            alignment: nsAlignment,
            contentInsets: contentInsets
        )
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
        var onEscape: (() -> Void)?
        var onFocusChange: ((Bool) -> Void)?

        private var processedFocusRequestToken: Int?
        private var shouldPlaceCursorAtEndAfterFocus = false

        init(
            text: Binding<String>,
            allowsCopy: Bool,
            selectAllOnFocus: Bool,
            onSubmit: (() -> Void)?,
            onEscape: (() -> Void)?,
            onFocusChange: ((Bool) -> Void)?
        ) {
            self.text = text
            self.allowsCopy = allowsCopy
            self.selectAllOnFocus = selectAllOnFocus
            self.onSubmit = onSubmit
            self.onEscape = onEscape
            self.onFocusChange = onFocusChange
        }

        private var focusedEntryGeneration: Int?

        func focus(
            _ textField: NSTextField,
            entryGeneration: Int,
            entryTraceContext: ToolPageEntryTraceContext?,
            placeholder: String
        ) {
            // generation > 0 表示本页当前显示中；停靠（0）不聚焦。同一代际
            // 只聚焦一次——等价于整页重建时代「每视图实例一次」的守卫。
            guard entryGeneration > 0, focusedEntryGeneration != entryGeneration else { return }
            focusedEntryGeneration = entryGeneration
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
            if commandSelector == #selector(NSResponder.cancelOperation(_:)),
               let onEscape {
                onEscape()
                return true
            }

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

/// 临时高亮的分层样式：匹配底色、选中匹配、捕获组分色。
enum IndexTextAreaHighlightStyle: Equatable, Sendable {
    case match
    case activeMatch
    /// 组序号（0 起），用于在调色板中循环取色。
    case capture(Int)
}

struct IndexTextAreaStyledRange: Equatable, Sendable {
    let range: NSRange
    let style: IndexTextAreaHighlightStyle
}

/// 捕获组配色。文本高亮（底色）与匹配列表（前景）共用同一映射，
/// 保证「列表里的第 N 组」和「正文里的第 N 组」颜色一致。
enum IndexTextAreaHighlightPalette {
    private static let backgrounds: [Color] = [
        ToolTheme.successSoft,
        ToolTheme.warningSoft,
        ToolTheme.errorSoft
    ]

    private static let foregrounds: [Color] = [
        ToolTheme.success,
        ToolTheme.warning,
        ToolTheme.error
    ]

    static func captureBackground(_ index: Int) -> Color {
        backgrounds[abs(index) % backgrounds.count]
    }

    static func captureForeground(_ index: Int) -> Color {
        foregrounds[abs(index) % foregrounds.count]
    }
}

struct IndexTextAreaTemporaryHighlights: Equatable {
    let sourceText: String
    var styledRanges: [IndexTextAreaStyledRange]

    init(sourceText: String, styledRanges: [IndexTextAreaStyledRange]) {
        self.sourceText = sourceText
        self.styledRanges = styledRanges
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.styledRanges == rhs.styledRanges && JSONExactTextIdentity.isExactlyEqual(lhs.sourceText, rhs.sourceText)
    }
}

/// 一次性滚动定位请求：token 变化时把目标 UTF-16 范围滚入可视区。
struct IndexTextAreaScrollRequest: Equatable {
    let token: Int
    let utf16Range: NSRange
}

@MainActor
enum IndexTextAreaTemporaryHighlightRenderer {
    /// 重涂临时背景高亮。返回值表示是否已到达目标状态（nil = 已清空；
    /// 非 nil = 已按 range 着色）。输入法 marked-text 或文本漂移时返回 false，
    /// 调用方应保持"未达成"状态以便下次 updateNSView 重试。
    @discardableResult
    static func apply(_ highlights: IndexTextAreaTemporaryHighlights?, to textView: NSTextView) -> Bool {
        clear(in: textView)
        guard let highlights,
              JSONExactTextIdentity.isExactlyEqual(textView.string, highlights.sourceText),
              !textView.hasMarkedText(),
              let layoutManager = textView.layoutManager else {
            return highlights == nil
        }

        let textLength = (textView.string as NSString).length
        for styled in highlights.styledRanges where styled.range.length > 0 {
            guard styled.range.location >= 0, styled.range.upperBound <= textLength else { continue }
            layoutManager.addTemporaryAttribute(
                .backgroundColor,
                value: backgroundColor(for: styled.style),
                forCharacterRange: styled.range
            )
            if styled.style == .activeMatch {
                layoutManager.addTemporaryAttribute(
                    .underlineColor,
                    value: NSColor(ToolTheme.accent),
                    forCharacterRange: styled.range
                )
                layoutManager.addTemporaryAttribute(
                    .underlineStyle,
                    value: NSUnderlineStyle.single.rawValue,
                    forCharacterRange: styled.range
                )
            }
        }
        return true
    }

    private static func backgroundColor(for style: IndexTextAreaHighlightStyle) -> NSColor {
        switch style {
        case .match:
            return NSColor(ToolTheme.accentSoft)
        case .activeMatch:
            return NSColor(ToolTheme.accentHover).withAlphaComponent(0.30)
        case .capture(let index):
            return NSColor(IndexTextAreaHighlightPalette.captureBackground(index))
        }
    }

    static func clear(in textView: NSTextView) {
        guard let layoutManager = textView.layoutManager else { return }
        let fullRange = NSRange(location: 0, length: (textView.string as NSString).length)
        layoutManager.removeTemporaryAttribute(.backgroundColor, forCharacterRange: fullRange)
        layoutManager.removeTemporaryAttribute(.underlineColor, forCharacterRange: fullRange)
        layoutManager.removeTemporaryAttribute(.underlineStyle, forCharacterRange: fullRange)
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
    var fillsHeight = false
    var expandsWithContent = false
    var renderingMode: IndexTextAreaRenderingMode = .measuredContent
    var lineBreakMode: NSLineBreakMode = .byCharWrapping
    var autoFocus = false
    var caretPlacementRequestToken: Int? = nil
    var temporaryHighlights: IndexTextAreaTemporaryHighlights? = nil
    var scrollRequest: IndexTextAreaScrollRequest? = nil
    var diagnosticMarker: IndexTextAreaDiagnosticMarker? = nil
    var diagnosticNavigationToken = 0
    var inputPolicy: IndexTextAreaInputPolicy? = nil
    /// Prototype v3 embedded-code presentation: drop the editor's own field
    /// box so the owning workbench panel supplies the surface edge to edge.
    var embedsFlat = false
    /// AppKit line-number gutter drawn inside the scroll view. Supported only
    /// by the measured-content path (same boundary as temporary highlights);
    /// the TextKit 2 viewport path ignores it.
    var lineNumbers = false
    var onFileDrop: ((String) -> Void)? = nil
    var droppedFile: IndexDroppedTextFile? = nil

    @State private var isComposing = false
    @State private var measuredTextHeight: CGFloat = 0

    private let exactTextIdentity: JSONExactTextIdentity

    init(
        placeholder: String,
        text: Binding<String>,
        minHeight: CGFloat = 220,
        fillsHeight: Bool = false,
        expandsWithContent: Bool = false,
        renderingMode: IndexTextAreaRenderingMode = .measuredContent,
        lineBreakMode: NSLineBreakMode = .byCharWrapping,
        autoFocus: Bool = false,
        caretPlacementRequestToken: Int? = nil,
        temporaryHighlights: IndexTextAreaTemporaryHighlights? = nil,
        scrollRequest: IndexTextAreaScrollRequest? = nil,
        diagnosticMarker: IndexTextAreaDiagnosticMarker? = nil,
        diagnosticNavigationToken: Int = 0,
        inputPolicy: IndexTextAreaInputPolicy? = nil,
        embedsFlat: Bool = false,
        lineNumbers: Bool = false,
        onFileDrop: ((String) -> Void)? = nil,
        droppedFile: IndexDroppedTextFile? = nil
    ) {
        self.placeholder = placeholder
        self._text = text
        self.minHeight = minHeight
        self.fillsHeight = fillsHeight
        self.expandsWithContent = expandsWithContent
        self.renderingMode = renderingMode
        self.lineBreakMode = lineBreakMode
        self.autoFocus = autoFocus
        self.caretPlacementRequestToken = caretPlacementRequestToken
        self.temporaryHighlights = temporaryHighlights
        self.diagnosticMarker = diagnosticMarker
        self.diagnosticNavigationToken = diagnosticNavigationToken
        self.inputPolicy = inputPolicy
        self.embedsFlat = embedsFlat
        self.lineNumbers = lineNumbers
        self.onFileDrop = onFileDrop
        self.droppedFile = droppedFile
        self.exactTextIdentity = JSONExactTextIdentity(text.wrappedValue)
    }

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
                        exactTextIdentity: exactTextIdentity,
                        lineBreakMode: lineBreakMode,
                        autoFocus: autoFocus,
                        caretPlacementRequestToken: caretPlacementRequestToken,
                        inputPolicy: inputPolicy,
                        onCompositionChange: { isComposing = $0 },
                        onFileDrop: onFileDrop,
                        droppedFile: droppedFile
                    )
                } else {
                    IndexUndoableTextView(
                        text: $text,
                        exactTextIdentity: exactTextIdentity,
                        growsWithContent: growsWithContent,
                        lineBreakMode: lineBreakMode,
                        measuredHeight: $measuredTextHeight,
                        autoFocus: autoFocus,
                        caretPlacementRequestToken: caretPlacementRequestToken,
                        temporaryHighlights: temporaryHighlights,
                        scrollRequest: scrollRequest,
                        diagnosticMarker: diagnosticMarker,
                        diagnosticNavigationToken: diagnosticNavigationToken,
                        inputPolicy: inputPolicy,
                        embedsFlat: embedsFlat,
                        lineNumbers: lineNumbers,
                        onCompositionChange: { isComposing = $0 },
                        onFileDrop: onFileDrop,
                        droppedFile: droppedFile
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
            maxHeight: fillsHeight ? .infinity : (resolvedHeight ?? minHeight),
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
        .iBeamCursorOnHover(excludingLeading: lineNumbers ? IndexEditorLineNumberGutter.width : 0)
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
    // 停靠保活后回访不再重建视图；进入聚焦以代际驱动保持「每次进入聚焦」语义。
    @Environment(\.toolPageEntryGeneration) private var entryGeneration: Int

    @Binding var text: String
    var exactTextIdentity: JSONExactTextIdentity? = nil
    var lineBreakMode: NSLineBreakMode
    var autoFocus = false
    var caretPlacementRequestToken: Int? = nil
    var inputPolicy: IndexTextAreaInputPolicy? = nil
    var onCompositionChange: ((Bool) -> Void)? = nil
    var onFileDrop: ((String) -> Void)? = nil
    var droppedFile: IndexDroppedTextFile? = nil

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
        textView.onFileDrop = onFileDrop
        textView.sharedDroppedFile = droppedFile

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
            IndexTextAreaScrollPositioning.revealInsertionPoint(in: textView, growsWithContent: false)
        }
        if autoFocus {
            context.coordinator.focus(textView, entryGeneration: entryGeneration)
        }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }

        context.coordinator.text = $text
        context.coordinator.inputPolicy = inputPolicy
        configure(textView)
        (textView as? IndexCaretTextView)?.onCompositionChange = onCompositionChange
        (textView as? IndexCaretTextView)?.onFileDrop = onFileDrop
        (textView as? IndexCaretTextView)?.sharedDroppedFile = droppedFile

        // Do not rewrite marked text during Chinese IME composition. The
        if !JSONExactTextIdentity.isExactlyEqual(textView.string, text) && !textView.hasMarkedText() {
            (textView as? IndexCaretTextView)?.invalidateDroppedFile()
            let selectedRanges = textView.selectedRanges
            textView.setStringWithoutUndoRegistration(text)
            let stringLength = (text as NSString).length
            let validRanges = selectedRanges.filter { $0.rangeValue.upperBound <= stringLength }
            textView.selectedRanges = validRanges.isEmpty
                ? [NSValue(range: NSRange(location: stringLength, length: 0))]
                : validRanges
            IndexTextAreaScrollPositioning.revealInsertionPoint(in: textView, growsWithContent: false)
        }
        if context.coordinator.placeCaretAtEndIfRequested(caretPlacementRequestToken, in: textView) {
            IndexTextAreaScrollPositioning.revealInsertionPoint(in: textView, growsWithContent: false)
        }
        if autoFocus {
            context.coordinator.focus(textView, entryGeneration: entryGeneration)
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
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
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

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        var inputPolicy: IndexTextAreaInputPolicy? {
            didSet {
                configureUndoManager()
            }
        }
        private var focusedEntryGeneration: Int?
        private var caretPlacementState = IndexTextAreaCaretPlacementState(processedRequestToken: nil)
        private let privateUndo = IndexPrivateUndoStack()

        init(text: Binding<String>, inputPolicy: IndexTextAreaInputPolicy?) {
            self.text = text
            self.inputPolicy = inputPolicy
            super.init()
            configureUndoManager()
        }

        func focus(_ textView: NSTextView, entryGeneration: Int) {
            // generation > 0 表示本页显示中；停靠（0）不聚焦。同代际只聚焦
            // 一次，等价整页重建时代「每实例一次」的守卫。
            guard entryGeneration > 0, focusedEntryGeneration != entryGeneration else { return }
            focusedEntryGeneration = entryGeneration
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
            if !JSONExactTextIdentity.isExactlyEqual(text.wrappedValue, textView.string) {
                text.wrappedValue = textView.string
            }
            textView.scrollRangeToVisible(clampedSelectedRange(for: textView))
        }

        private func configureUndoManager() {
            privateUndo.configureLevels(inputPolicy?.undoLevels)
        }
    }
}

private final class IndexTextKit2ViewportScrollView: IndexTextViewportScrollView {
    override func synchronizeDocumentGeometry() {
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
    // 停靠保活后回访不再重建视图；进入聚焦以代际驱动保持「每次进入聚焦」语义。
    @Environment(\.toolPageEntryGeneration) private var entryGeneration: Int

    @Binding var text: String
    var exactTextIdentity: JSONExactTextIdentity? = nil
    var growsWithContent: Bool
    var lineBreakMode: NSLineBreakMode
    @Binding var measuredHeight: CGFloat
    var autoFocus = false
    var caretPlacementRequestToken: Int? = nil
    var temporaryHighlights: IndexTextAreaTemporaryHighlights? = nil
    var scrollRequest: IndexTextAreaScrollRequest? = nil
    var diagnosticMarker: IndexTextAreaDiagnosticMarker? = nil
    var diagnosticNavigationToken = 0
    var inputPolicy: IndexTextAreaInputPolicy? = nil
    var embedsFlat = false
    var lineNumbers = false
    var onCompositionChange: ((Bool) -> Void)? = nil
    var onFileDrop: ((String) -> Void)? = nil
    var droppedFile: IndexDroppedTextFile? = nil

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
        textView.onFileDrop = onFileDrop
        textView.sharedDroppedFile = droppedFile
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
        context.coordinator.diagnosticController.update(diagnosticMarker, requestToken: diagnosticNavigationToken, in: textView, gutter: context.coordinator.lineNumberGutter)
        scrollView.synchronizeTextGeometry()
        context.coordinator.measure(textView)
        if context.coordinator.placeCaretAtEndIfRequested(caretPlacementRequestToken, in: textView) {
            IndexTextAreaScrollPositioning.revealInsertionPoint(in: textView, growsWithContent: growsWithContent)
        }
        if autoFocus {
            context.coordinator.focus(textView, entryGeneration: entryGeneration)
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
        (textView as? IndexCaretTextView)?.onFileDrop = onFileDrop
        (textView as? IndexCaretTextView)?.sharedDroppedFile = droppedFile
        scrollView.hasVerticalScroller = !growsWithContent
        scrollView.autohidesScrollers = !growsWithContent
        scrollView.verticalScrollElasticity = growsWithContent ? .none : .automatic
        keepContentGrowingScrollOriginStable(in: scrollView)

        // `textView.string` already contains the marked (组字) text but `text`
        // back would wipe the marked text and abort the composition (Chinese
        if !JSONExactTextIdentity.isExactlyEqual(textView.string, text) && !textView.hasMarkedText() {
            (textView as? IndexCaretTextView)?.invalidateDroppedFile()
            let selectedRanges = textView.selectedRanges
            context.coordinator.diagnosticController.clear(in: textView, gutter: context.coordinator.lineNumberGutter)
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
        context.coordinator.refreshTemporaryHighlights(temporaryHighlights, in: textView)
        context.coordinator.scrollToVisibleIfRequested(scrollRequest, in: textView)
        context.coordinator.diagnosticController.update(diagnosticMarker, requestToken: diagnosticNavigationToken, in: textView, gutter: context.coordinator.lineNumberGutter)
        context.coordinator.measure(textView)
        keepContentGrowingScrollOriginStable(in: scrollView)
        if autoFocus {
            context.coordinator.focus(textView, entryGeneration: entryGeneration)
        }
    }

    private func installLineNumberGutter(
        in scrollView: NSScrollView,
        for textView: NSTextView,
        coordinator: Coordinator
    ) {
        let gutter = IndexEditorLineNumberGutterView(scrollView: scrollView, textView: textView)
        gutter.autoresizingMask = [.height]
        scrollView.addSubview(gutter)
        (scrollView as? IndexTextAreaScrollView)?.lineNumberGutter = gutter
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
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
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
        let diagnosticController = IndexTextAreaDiagnosticController()
        private var focusedEntryGeneration: Int?
        private var caretPlacementState = IndexTextAreaCaretPlacementState(processedRequestToken: nil)
        private let privateUndo = IndexPrivateUndoStack()
        private var lastAppliedTemporaryHighlights: IndexTextAreaTemporaryHighlights?
        private var lastTemporaryHighlightApplyReachedTarget = false
        private var processedScrollToken: Int?

        /// token 变化时把目标范围滚入可视区；异步补一次，规避刚布局完
        /// 时 scrollRangeToVisible 早退的情况（与 caret 揭示同一手法）。
        func scrollToVisibleIfRequested(_ request: IndexTextAreaScrollRequest?, in textView: NSTextView) {
            guard let request, request.token != processedScrollToken else { return }
            processedScrollToken = request.token
            let length = (textView.string as NSString).length
            guard request.utf16Range.location >= 0, request.utf16Range.upperBound <= length else { return }
            textView.scrollRangeToVisible(request.utf16Range)
            DispatchQueue.main.async { [weak textView] in
                textView?.scrollRangeToVisible(request.utf16Range)
            }
        }

        func refreshLineNumberGutter() {
            lineNumberGutter?.refresh()
        }

        /// updateNSView 会在焦点/滚动/测量等无关更新时反复触发；高亮未变化
        /// 且文本未漂移时跳过全量清除+重涂，避免 TextKit 临时属性抖动。
        func refreshTemporaryHighlights(_ highlights: IndexTextAreaTemporaryHighlights?, in textView: NSTextView) {
            if lastTemporaryHighlightApplyReachedTarget,
               highlights == lastAppliedTemporaryHighlights {
                if let highlights {
                    if JSONExactTextIdentity.isExactlyEqual(textView.string, highlights.sourceText) { return }
                } else {
                    return
                }
            }
            lastTemporaryHighlightApplyReachedTarget = IndexTextAreaTemporaryHighlightRenderer.apply(
                highlights,
                to: textView
            )
            lastAppliedTemporaryHighlights = highlights
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

        func focus(_ textView: NSTextView, entryGeneration: Int) {
            // generation > 0 表示本页显示中；停靠（0）不聚焦。同代际只聚焦
            // 一次，等价整页重建时代「每实例一次」的守卫。
            guard entryGeneration > 0, focusedEntryGeneration != entryGeneration else { return }
            focusedEntryGeneration = entryGeneration
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
            guard let maxUTF8Bytes = inputPolicy?.maxUTF8Bytes else {
                diagnosticController.clear(in: textView, gutter: lineNumberGutter)
                return true
            }
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
            diagnosticController.clear(in: textView, gutter: lineNumberGutter)
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
            diagnosticController.clear(in: textView, gutter: lineNumberGutter)
            refreshLineNumberGutter()
            if !JSONExactTextIdentity.isExactlyEqual(text.wrappedValue, textView.string) {
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


private final class IndexTextAreaScrollView: IndexTextViewportScrollView {
    weak var lineNumberGutter: IndexEditorLineNumberGutterView?
    var growsWithContent = false

    override func synchronizeDocumentGeometry() {
        synchronizeTextGeometry()
        if let gutter = lineNumberGutter, abs(gutter.frame.height - bounds.height) > 0.5 {
            gutter.frame = NSRect(x: 0, y: 0, width: IndexEditorLineNumberGutter.width, height: bounds.height)
        }
        lineNumberGutter?.setNeedsDisplay(lineNumberGutter?.bounds ?? .zero)
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

