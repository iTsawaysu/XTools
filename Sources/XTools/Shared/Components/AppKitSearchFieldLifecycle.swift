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
    static func makeTextField(
        configuration: AppKitSearchFieldConfiguration,
        text: Binding<String>,
        focusToken: Int,
        coordinator: AppKitSearchFieldCoordinator,
        onFocusChange: ((Bool) -> Void)? = nil,
        commandHandler: AppKitSearchFieldCoordinator.CommandHandler? = nil,
        canRequestFocus: @escaping AppKitSearchFieldCoordinator.FocusRequestValidity = { true }
    ) -> NSTextField {
        coordinator.update(
            text: text,
            onFocusChange: onFocusChange,
            commandHandler: commandHandler,
            canRequestFocus: canRequestFocus
        )

        let textField = IndexPaddedTextField()
        configure(textField, with: configuration)
        textField.delegate = coordinator
        textField.stringValue = text.wrappedValue
        coordinator.focus(textField, focusToken: focusToken)
        return textField
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
        DispatchQueue.main.async { [weak textField] in
            guard isValid() else { return }
            textField?.window?.makeFirstResponder(textField)
        }
        for delay in delayedRetries {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak textField] in
                guard isValid() else { return }
                textField?.window?.makeFirstResponder(textField)
            }
        }
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
