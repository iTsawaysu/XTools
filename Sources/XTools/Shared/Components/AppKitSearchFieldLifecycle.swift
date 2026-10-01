import AppKit
import SwiftUI

struct AppKitSearchFieldConfiguration {
    let placeholder: String
    let font: NSFont
    let contentInsets: IndexTextFieldContentInsets

    init(
        placeholder: String,
        font: NSFont,
        contentInsets: IndexTextFieldContentInsets = .zero
    ) {
        self.placeholder = placeholder
        self.font = font
        self.contentInsets = contentInsets
    }
}

enum AppKitSearchFieldFocusAttemptSource: Equatable, Sendable {
    case immediate
    case delayed(TimeInterval)
}

struct AppKitSearchFieldFocusAttempt: Sendable {
    let source: AppKitSearchFieldFocusAttemptSource
    let isRequestValid: Bool
    let hasWindow: Bool
    let isKeyWindow: Bool
    let hasNonzeroFrame: Bool
    let makeFirstResponderResult: Bool?
    let makeFirstResponderMilliseconds: Double?
    let firstResponderIsFieldEditor: Bool
}

@MainActor
final class AppKitSearchFieldCoordinator: NSObject, NSTextFieldDelegate {
    typealias CommandHandler = (NSTextView, Selector) -> Bool
    typealias FocusRequestValidity = @MainActor @Sendable () -> Bool
    typealias FocusRequester = @MainActor @Sendable (
        NSTextField,
        [TimeInterval],
        @escaping FocusRequestValidity
    ) -> Void

    private var text: Binding<String>
    private var onFocusChange: ((Bool) -> Void)?
    private var commandHandler: CommandHandler?
    private var canRequestFocus: FocusRequestValidity = { true }
    private var focusedToken: Int?
    private var focusRequestGeneration = 0
    private var acceptsFocusRequests = true
    private let focusRetryDelays: [TimeInterval]
    private let focusRequester: FocusRequester

    init(
        text: Binding<String>,
        processedFocusToken: Int?,
        focusRetryDelays: [TimeInterval],
        requestFocus: @escaping FocusRequester = AppKitSearchFieldLifecycle.requestFocus
    ) {
        self.text = text
        self.focusedToken = processedFocusToken
        self.focusRetryDelays = focusRetryDelays
        self.focusRequester = requestFocus
    }

    func update(
        text: Binding<String>,
        onFocusChange: ((Bool) -> Void)?,
        commandHandler: CommandHandler?,
        canRequestFocus: @escaping FocusRequestValidity = { true }
    ) {
        self.text = text
        self.onFocusChange = onFocusChange
        self.commandHandler = commandHandler
        self.canRequestFocus = canRequestFocus
    }

    func focus(_ textField: NSTextField, focusToken: Int) {
        guard focusedToken != focusToken else { return }
        focusedToken = focusToken
        focusRequestGeneration &+= 1
        let generation = focusRequestGeneration
        focusRequester(textField, focusRetryDelays) { [weak self] in
            guard let self else { return false }
            return self.acceptsFocusRequests
                && self.focusRequestGeneration == generation
                && self.canRequestFocus()
        }
    }

    func invalidateFocusRequests() {
        acceptsFocusRequests = false
        focusRequestGeneration &+= 1
    }

    /// Live validity for a focus grab performed outside the token-scheduled
    /// chain — the search field's window attachment. There is no single
    /// captured request generation at that moment, so the grab must respect
    /// the same invalidate/rearm flag and live-presentation guard as a
    /// scheduled retry; that is what keeps a closed or replaced session from
    /// stealing first responder on a late view attachment.
    func canRequestFocusNow() -> Bool {
        acceptsFocusRequests && canRequestFocus()
    }

    /// Re-arms focus scheduling after `invalidateFocusRequests`. The command
    /// palette's search field persists across sessions, so a closed session's
    /// invalidation must not poison the next session's focus requests.
    func rearmFocusRequests() {
        acceptsFocusRequests = true
    }

    func controlTextDidBeginEditing(_ notification: Notification) {
        if let textField = notification.object as? NSTextField {
            AppKitTextEditingConfiguration.configureCurrentFieldEditor(for: textField)
        }
        onFocusChange?(true)
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        onFocusChange?(false)
    }

    func controlTextDidChange(_ notification: Notification) {
        guard let textField = notification.object as? NSTextField else { return }
        AppKitTextEditingConfiguration.configureCurrentFieldEditor(for: textField)
        if text.wrappedValue != textField.stringValue {
            text.wrappedValue = textField.stringValue
        }
    }

    func control(
        _ control: NSControl,
        textView: NSTextView,
        doCommandBy commandSelector: Selector
    ) -> Bool {
        commandHandler?(textView, commandSelector) ?? false
    }
}

@MainActor
enum AppKitSearchFieldLifecycle {
    typealias FocusAttemptObserver = @MainActor @Sendable (AppKitSearchFieldFocusAttempt) -> Void

    private final class FocusRequestState {
        var succeeded = false
    }

    static func makeTextField(
        configuration: AppKitSearchFieldConfiguration,
        text: Binding<String>,
        focusToken: Int,
        coordinator: AppKitSearchFieldCoordinator,
        onFocusChange: ((Bool) -> Void)? = nil,
        commandHandler: AppKitSearchFieldCoordinator.CommandHandler? = nil,
        canRequestFocus: @escaping AppKitSearchFieldCoordinator.FocusRequestValidity = { true }
    ) -> NSTextField {
        let textField = IndexPaddedTextField()
        attach(
            textField,
            configuration: configuration,
            text: text,
            focusToken: focusToken,
            coordinator: coordinator,
            onFocusChange: onFocusChange,
            commandHandler: commandHandler,
            canRequestFocus: canRequestFocus
        )
        return textField
    }

    /// Shared field wiring behind `makeTextField`: live coordinator state,
    /// geometry, editing delegate, and the session's first focus request.
    /// Callers own the field instance — the command palette passes its
    /// `CommandPaletteTextField` subclass so the lazily-mounted first-open
    /// field can grab focus the moment it gains a window.
    static func attach(
        _ textField: NSTextField,
        configuration: AppKitSearchFieldConfiguration,
        text: Binding<String>,
        focusToken: Int,
        coordinator: AppKitSearchFieldCoordinator,
        onFocusChange: ((Bool) -> Void)? = nil,
        commandHandler: AppKitSearchFieldCoordinator.CommandHandler? = nil,
        canRequestFocus: @escaping AppKitSearchFieldCoordinator.FocusRequestValidity = { true }
    ) {
        coordinator.update(
            text: text,
            onFocusChange: onFocusChange,
            commandHandler: commandHandler,
            canRequestFocus: canRequestFocus
        )
        configure(textField, with: configuration)
        textField.delegate = coordinator
        textField.stringValue = text.wrappedValue
        coordinator.focus(textField, focusToken: focusToken)
    }

    static func update(
        _ textField: NSTextField,
        configuration: AppKitSearchFieldConfiguration,
        text: Binding<String>,
        focusToken: Int,
        coordinator: AppKitSearchFieldCoordinator,
        onFocusChange: ((Bool) -> Void)? = nil,
        commandHandler: AppKitSearchFieldCoordinator.CommandHandler? = nil,
        canRequestFocus: @escaping AppKitSearchFieldCoordinator.FocusRequestValidity = { true }
    ) {
        coordinator.update(
            text: text,
            onFocusChange: onFocusChange,
            commandHandler: commandHandler,
            canRequestFocus: canRequestFocus
        )
        configure(textField, with: configuration)

        if textField.stringValue != text.wrappedValue {
            textField.stringValue = text.wrappedValue
        }

        coordinator.focus(textField, focusToken: focusToken)
    }

    static func requestFocus(
        _ textField: NSTextField,
        delayedRetries: [TimeInterval],
        isValid: @escaping AppKitSearchFieldCoordinator.FocusRequestValidity
    ) {
        requestFocus(
            textField,
            delayedRetries: delayedRetries,
            isValid: isValid,
            observer: nil
        )
    }

    static func requestFocus(
        _ textField: NSTextField,
        delayedRetries: [TimeInterval],
        isValid: @escaping AppKitSearchFieldCoordinator.FocusRequestValidity,
        observer: FocusAttemptObserver?
    ) {
        let state = FocusRequestState()
        DispatchQueue.main.async { [weak textField] in
            guard !state.succeeded else { return }
            state.succeeded = performFocusAttempt(
                textField,
                source: .immediate,
                isValid: isValid,
                observer: observer
            )
        }
        for delay in delayedRetries {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak textField] in
                guard !state.succeeded else { return }
                state.succeeded = performFocusAttempt(
                    textField,
                    source: .delayed(delay),
                    isValid: isValid,
                    observer: observer
                )
            }
        }
    }

    /// Synchronous focus grab at the moment the field gains a window
    /// (`viewDidMoveToWindow`): one guarded attempt with the same success
    /// semantics as a scheduled link — first responder taken and the field
    /// editor owned. A success makes the pending scheduled retries no-ops
    /// (the `succeeded` guard); a failure (extreme attach timing) falls
    /// through to them untouched.
    @discardableResult
    static func grabFocusOnWindowAttach(
        _ textField: NSTextField,
        isValid: AppKitSearchFieldCoordinator.FocusRequestValidity
    ) -> Bool {
        guard isValid(), textField.isEnabled, let window = textField.window,
              window.makeFirstResponder(textField),
              let editor = textField.currentEditor() else { return false }
        return window.firstResponder === editor
    }

    private static func performFocusAttempt(
        _ textField: NSTextField?,
        source: AppKitSearchFieldFocusAttemptSource,
        isValid: AppKitSearchFieldCoordinator.FocusRequestValidity,
        observer: FocusAttemptObserver?
    ) -> Bool {
        guard let observer else {
            guard isValid(), let textField, let window = textField.window,
                  window.makeFirstResponder(textField),
                  let editor = textField.currentEditor() else { return false }
            return window.firstResponder === editor
        }

        let isRequestValid = isValid()
        guard let textField else {
            observer(
                AppKitSearchFieldFocusAttempt(
                    source: source,
                    isRequestValid: isRequestValid,
                    hasWindow: false,
                    isKeyWindow: false,
                    hasNonzeroFrame: false,
                    makeFirstResponderResult: nil,
                    makeFirstResponderMilliseconds: nil,
                    firstResponderIsFieldEditor: false
                )
            )
            return false
        }

        let window = textField.window
        let isKeyWindow = window?.isKeyWindow ?? false
        let hasNonzeroFrame = textField.frame.width > 0 && textField.frame.height > 0
        let makeFirstResponderStartedAt = isRequestValid && window != nil
            ? ContinuousClock.now
            : nil
        let makeFirstResponderResult = isRequestValid
            ? window?.makeFirstResponder(textField)
            : nil
        let makeFirstResponderMilliseconds = makeFirstResponderStartedAt.map {
            $0.duration(to: .now).milliseconds
        }
        let firstResponderIsFieldEditor: Bool
        if let window, let editor = textField.currentEditor() {
            firstResponderIsFieldEditor = window.firstResponder === editor
        } else {
            firstResponderIsFieldEditor = false
        }

        observer(
            AppKitSearchFieldFocusAttempt(
                source: source,
                isRequestValid: isRequestValid,
                hasWindow: window != nil,
                isKeyWindow: isKeyWindow,
                hasNonzeroFrame: hasNonzeroFrame,
                makeFirstResponderResult: makeFirstResponderResult,
                makeFirstResponderMilliseconds: makeFirstResponderMilliseconds,
                firstResponderIsFieldEditor: firstResponderIsFieldEditor
            )
        )
        return makeFirstResponderResult == true && firstResponderIsFieldEditor
    }

    /// Accept the complete proposed height for hit testing instead of the
    /// NSTextField intrinsic 15pt line height.
    static func sizeThatFits(
        _ proposal: ProposedViewSize,
        textField: NSTextField
    ) -> CGSize? {
        guard let height = proposal.height else { return nil }
        return CGSize(width: proposal.width ?? textField.fittingSize.width, height: height)
    }

    private static func configure(
        _ textField: NSTextField,
        with configuration: AppKitSearchFieldConfiguration
    ) {
        textField.placeholderString = configuration.placeholder
        textField.font = configuration.font
        textField.textColor = .labelColor
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
        textField.indexContentInsets = configuration.contentInsets
        textField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        textField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }
}

extension Duration {
    /// Duration → 毫秒（浮点）。App 内统一的耗时换算，避免各处重复 components 数学。
    var milliseconds: Double {
        let value = components
        return Double(value.seconds) * 1_000
            + Double(value.attoseconds) / 1_000_000_000_000_000
    }
}
