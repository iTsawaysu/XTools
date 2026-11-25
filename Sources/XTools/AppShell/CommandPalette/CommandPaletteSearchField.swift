import AppKit
import SwiftUI

/// The palette's AppKit-backed search field: reliable arrow/Return/Escape
/// handling that SwiftUI's TextField swallows, plus focus-token scheduling
/// delegated to the shared `AppKitSearchFieldLifecycle`.
///
/// The native field instance persists across palette sessions (it never
/// receives a per-session identity): rebuilding an NSTextField — first layout,
/// field editor creation, focus retries — inside the visible open arc is what
/// quantized the palette's fade-in into a brightness step on rapid ⌘K. Only
/// its live state resets: `isSessionActive` gates native interaction, and the
/// content lifecycle clears the text when a session opens.
struct CommandPaletteSearchField: NSViewRepresentable {
    let placeholder: String
    @Binding var text: String
    let focusToken: Int
    let isSessionActive: Bool
    /// Diagnostics-only session tag (focus/native-ready traces); it never
    /// drives field identity or attachment.
    let presentationSession: Int
    let canRequestFocus: AppKitSearchFieldCoordinator.FocusRequestValidity
    let contentLifecycle: CommandPaletteContentLifecycle
    let onSubmit: () -> Void
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onMoveToFirst: () -> Void
    let onMoveToLast: () -> Void
    let onPageUp: () -> Void
    let onPageDown: () -> Void
    let onCancel: () -> Void

    @MainActor
    final class Coordinator {
        let search: AppKitSearchFieldCoordinator
        weak var contentLifecycle: CommandPaletteContentLifecycle?

        init(
            search: AppKitSearchFieldCoordinator,
            contentLifecycle: CommandPaletteContentLifecycle
        ) {
            self.search = search
            self.contentLifecycle = contentLifecycle
        }
    }

    private var configuration: AppKitSearchFieldConfiguration {
        // Arc-style large prompt input — the palette's primary affordance.
        AppKitSearchFieldConfiguration(
            placeholder: placeholder,
            font: .systemFont(ofSize: 18)
        )
    }

    private var commandHandler: AppKitSearchFieldCoordinator.CommandHandler {
        { textView, commandSelector in
            if textView.hasMarkedText(), Self.markedTextShouldHandle(commandSelector) {
                return false
            }

            switch commandSelector {
            case #selector(NSResponder.moveUp(_:)):
                onMoveUp()
                return true
            case #selector(NSResponder.moveDown(_:)):
                onMoveDown()
                return true
            // Home/End also cover ⌘↑/⌘↓ (the text system routes both here).
            case #selector(NSResponder.moveToBeginningOfDocument(_:)):
                onMoveToFirst()
                return true
            case #selector(NSResponder.moveToEndOfDocument(_:)):
                onMoveToLast()
                return true
            // PageUp/PageDown arrive as either selector family depending on
            // the field editor's key binding resolution; claim both.
            case #selector(NSResponder.scrollPageUp(_:)),
                 #selector(NSResponder.pageUp(_:)):
                onPageUp()
                return true
            case #selector(NSResponder.scrollPageDown(_:)),
                 #selector(NSResponder.pageDown(_:)):
                onPageDown()
                return true
            case #selector(NSResponder.insertNewline(_:)):
                onSubmit()
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                onCancel()
                return true
            default:
                return false
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        let presentationSession = presentationSession
        return Coordinator(
            search: AppKitSearchFieldCoordinator(
                text: $text,
                processedFocusToken: nil,
                focusRetryDelays: [0.05, 0.15],
                requestFocus: { textField, delayedRetries, isValid in
                    AppKitSearchFieldLifecycle.requestFocus(
                        textField,
                        delayedRetries: delayedRetries,
                        isValid: isValid,
                        observer: CommandPaletteTrace.focusAttemptObserver(
                            session: presentationSession
                        )
                    )
                }
            ),
            contentLifecycle: contentLifecycle
        )
    }

    func makeNSView(context: Context) -> NSTextField {
        let coordinator = context.coordinator.search
        let textField = CommandPaletteTextField()
        AppKitSearchFieldLifecycle.attach(
            textField,
            configuration: configuration,
            text: $text,
            focusToken: focusToken,
            coordinator: coordinator,
            commandHandler: commandHandler,
            canRequestFocus: canRequestFocus
        )
        textField.setAccessibilityIdentifier("command-palette.search")
        textField.canGrabFocusOnWindowAttach = { [weak coordinator] in
            coordinator?.canRequestFocusNow() ?? false
        }
        contentLifecycle.attachSearchField(
            textField,
            coordinator: coordinator
        )
        CommandPaletteTrace.observeNativeReady(
            textField,
            session: presentationSession,
            isValid: canRequestFocus
        )
        return textField
    }

    func updateNSView(_ textField: NSTextField, context: Context) {
        textField.setAccessibilityIdentifier("command-palette.search")
        // The persistent field must follow live presentation readiness: a
        // closed or replaced session disables native interaction in the same
        // update that suspends the retained panel.
        textField.isEnabled = isSessionActive
        AppKitSearchFieldLifecycle.update(
            textField,
            configuration: configuration,
            text: $text,
            focusToken: focusToken,
            coordinator: context.coordinator.search,
            commandHandler: commandHandler,
            canRequestFocus: canRequestFocus
        )
        contentLifecycle.attachSearchField(
            textField,
            coordinator: context.coordinator.search
        )
        CommandPaletteTrace.observeNativeReady(
            textField,
            session: presentationSession,
            isValid: canRequestFocus
        )
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        nsView textField: NSTextField,
        context: Context
    ) -> CGSize? {
        guard let height = proposal.height else { return nil }
        return CGSize(width: proposal.width ?? textField.fittingSize.width, height: height)
    }

    static func dismantleNSView(
        _ textField: NSTextField,
        coordinator: Coordinator
    ) {
        coordinator.contentLifecycle?.detachSearchField(textField)
        coordinator.search.invalidateFocusRequests()
    }

    private static func markedTextShouldHandle(_ commandSelector: Selector) -> Bool {
        commandSelector == #selector(NSResponder.moveUp(_:))
            || commandSelector == #selector(NSResponder.moveDown(_:))
            || commandSelector == #selector(NSResponder.moveToBeginningOfDocument(_:))
            || commandSelector == #selector(NSResponder.moveToEndOfDocument(_:))
            || commandSelector == #selector(NSResponder.scrollPageUp(_:))
            || commandSelector == #selector(NSResponder.scrollPageDown(_:))
            || commandSelector == #selector(NSResponder.pageUp(_:))
            || commandSelector == #selector(NSResponder.pageDown(_:))
            || commandSelector == #selector(NSResponder.insertNewline(_:))
            || commandSelector == #selector(NSResponder.cancelOperation(_:))
    }
}

/// The palette's native search field. The retained palette subtree mounts
/// lazily on the first open, so the field previously met its window only
/// after the shared lifecycle's scheduled chain had already missed its
/// next-runloop attempt — the [0.05, 0.15] retries then left the first
/// ~50ms of the open arc without a cursor. Warm opens already focus
/// synchronously in `commandPaletteDidOpen`; grabbing focus the moment the
/// field gains a window gives the first open the same same-runloop
/// semantics.
final class CommandPaletteTextField: IndexPaddedTextField {
    /// Live-request validity sourced from the field's coordinator
    /// (`canRequestFocusNow`): the attach-time grab honors the same focus
    /// invalidation and live-presentation guards as a scheduled retry, so a
    /// closed or replaced session can never steal first responder on a late
    /// attachment.
    var canGrabFocusOnWindowAttach: AppKitSearchFieldCoordinator.FocusRequestValidity?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil, let isValid = canGrabFocusOnWindowAttach else { return }
        AppKitSearchFieldLifecycle.grabFocusOnWindowAttach(self, isValid: isValid)
    }
}
