import AppKit
import SwiftUI
@testable import XTools
import Testing

struct AppKitSearchFieldLifecycleTests {
    @Test @MainActor func createsAndUpdatesAPlainNativeSearchField() {
        let state = TestState(text: "initial")
        let coordinator = AppKitSearchFieldCoordinator(
            text: state.binding,
            processedFocusToken: 0,
            focusRetryDelays: [0.05],
            requestFocus: { _, delays, isValid in
                state.focusRequests.append(delays)
                state.focusRequestValidities.append(isValid)
            }
        )
        let configuration = AppKitSearchFieldConfiguration(
            placeholder: "Search",
            font: .systemFont(ofSize: 12.5),
            contentInsets: IndexTextFieldContentInsets(leading: 30, trailing: 31)
        )

        let textField = AppKitSearchFieldLifecycle.makeTextField(
            configuration: configuration,
            text: state.binding,
            focusToken: 0,
            coordinator: coordinator,
            onFocusChange: { state.focusEvents.append($0) }
        )

        #expect(textField.stringValue == "initial")
        #expect(textField.placeholderString == "Search")
        #expect(textField.font?.pointSize == 12.5)
        #expect(textField.isEditable)
        #expect(textField.isSelectable)
        #expect(textField.isBordered == false)
        #expect(textField.isBezeled == false)
        #expect(textField.drawsBackground == false)
        #expect(textField.focusRingType == .none)
        #expect(textField.usesSingleLineMode)
        #expect(textField.delegate === coordinator)
        #expect(textField is IndexPaddedTextField)
        #expect(!(textField is NSSearchField))
        #expect(textField.indexContentInsets == IndexTextFieldContentInsets(leading: 30, trailing: 31))
        #expect(state.focusRequests.isEmpty)

        textField.frame = NSRect(x: 0, y: 0, width: 196, height: 32)
        for point in [
            NSPoint(x: 0.5, y: 0.5),
            NSPoint(x: 195.5, y: 0.5),
            NSPoint(x: 0.5, y: 31.5),
            NSPoint(x: 195.5, y: 31.5),
        ] {
            #expect(textField.hitTest(point) === textField)
        }

        state.text = "external"
        let updatedConfiguration = AppKitSearchFieldConfiguration(
            placeholder: "Find",
            font: .systemFont(ofSize: 15),
            contentInsets: IndexTextFieldContentInsets(leading: 0, trailing: 0)
        )
        AppKitSearchFieldLifecycle.update(
            textField,
            configuration: updatedConfiguration,
            text: state.binding,
            focusToken: 1,
            coordinator: coordinator,
            onFocusChange: { state.focusEvents.append($0) }
        )

        #expect(textField.stringValue == "external")
        #expect(textField.placeholderString == "Find")
        #expect(textField.indexContentInsets == .zero)
        #expect(state.focusRequests == [[0.05]])
        #expect(state.focusRequestValidities.last?() == true)

        AppKitSearchFieldLifecycle.update(
            textField,
            configuration: updatedConfiguration,
            text: state.binding,
            focusToken: 1,
            coordinator: coordinator,
            onFocusChange: { state.focusEvents.append($0) }
        )
        #expect(state.focusRequests.count == 1)
    }

    @Test @MainActor func nativeEditingSyncsBindingAndFocusCallbacks() {
        let state = TestState(text: "before")
        let coordinator = AppKitSearchFieldCoordinator(
            text: state.binding,
            processedFocusToken: 0,
            focusRetryDelays: [],
            requestFocus: { _, _, _ in }
        )
        coordinator.update(
            text: state.binding,
            onFocusChange: { state.focusEvents.append($0) },
            commandHandler: nil
        )
        let textField = NSTextField()
        textField.stringValue = "after"

        coordinator.controlTextDidBeginEditing(Notification(name: NSControl.textDidBeginEditingNotification, object: textField))
        coordinator.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: textField))
        coordinator.controlTextDidEndEditing(Notification(name: NSControl.textDidEndEditingNotification, object: textField))

        #expect(state.text == "after")
        #expect(state.focusEvents == [true, false])
    }

    @Test @MainActor func initialProcessedTokenAndRetrySchedulePreserveAdapterPolicies() {
        let sidebarState = TestState(text: "")
        let sidebar = AppKitSearchFieldCoordinator(
            text: sidebarState.binding,
            processedFocusToken: 0,
            focusRetryDelays: [0.05],
            requestFocus: { _, delays, isValid in
                sidebarState.focusRequests.append(delays)
                sidebarState.focusRequestValidities.append(isValid)
            }
        )
        let textField = NSTextField()

        sidebar.focus(textField, focusToken: 0)
        sidebar.focus(textField, focusToken: 1)
        sidebar.focus(textField, focusToken: 1)
        #expect(sidebarState.focusRequests == [[0.05]])

        let paletteState = TestState(text: "")
        let palette = AppKitSearchFieldCoordinator(
            text: paletteState.binding,
            processedFocusToken: nil,
            focusRetryDelays: [0.05, 0.15],
            requestFocus: { _, delays, isValid in
                paletteState.focusRequests.append(delays)
                paletteState.focusRequestValidities.append(isValid)
            }
        )
        palette.focus(textField, focusToken: 0)
        #expect(paletteState.focusRequests == [[0.05, 0.15]])
    }

    @Test @MainActor func focusRequestsExpireAcrossTokensPresentationSessionsAndDismantle() throws {
        let state = TestState(text: "")
        state.presentationSession = 1
        let expectedSession = state.presentationSession
        let coordinator = AppKitSearchFieldCoordinator(
            text: state.binding,
            processedFocusToken: nil,
            focusRetryDelays: [0.05, 0.15],
            requestFocus: { _, delays, isValid in
                state.focusRequests.append(delays)
                state.focusRequestValidities.append(isValid)
            }
        )
        coordinator.update(
            text: state.binding,
            onFocusChange: nil,
            commandHandler: nil,
            canRequestFocus: {
                state.isPresented && state.presentationSession == expectedSession
            }
        )
        let textField = IndexPaddedTextField()

        coordinator.focus(textField, focusToken: 0)
        let firstRequest = try #require(state.focusRequestValidities.last)
        #expect(firstRequest())

        coordinator.focus(textField, focusToken: 1)
        let secondRequest = try #require(state.focusRequestValidities.last)
        #expect(!firstRequest())
        #expect(secondRequest())

        state.isPresented = false
        state.presentationSession = 2
        #expect(!secondRequest())

        state.isPresented = true
        state.presentationSession = 3
        #expect(!secondRequest())

        coordinator.invalidateFocusRequests()
        #expect(!secondRequest())
    }

    @Test @MainActor func focusAttemptObserverReportsInvalidRequestWithoutMakingFirstResponderRequest() async throws {
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 196, height: 32))
        let window = FocusRequestTrackingWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 120),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = field
        var attempts: [AppKitSearchFieldFocusAttempt] = []

        AppKitSearchFieldLifecycle.requestFocus(
            field,
            delayedRetries: [],
            isValid: { false },
            observer: { attempts.append($0) }
        )

        let deadline = Date(timeIntervalSinceNow: 1)
        while attempts.isEmpty, Date() < deadline {
            try await Task.sleep(for: .milliseconds(1))
        }
        let attempt = try #require(attempts.first)

        #expect(attempt.source == .immediate)
        #expect(!attempt.isRequestValid)
        #expect(attempt.hasWindow)
        #expect(attempt.hasNonzeroFrame)
        #expect(attempt.makeFirstResponderResult == nil)
        #expect(attempt.makeFirstResponderMilliseconds == nil)
        #expect(!attempt.firstResponderIsFieldEditor)
        #expect(window.makeFirstResponderRequestCount == 0)
    }

    @Test(arguments: [false, true])
    @MainActor func successfulFieldEditorFocusDoesNotReclaimFocusAfterUserHandoff(observed: Bool) async throws {
        let window = FocusRequestTrackingWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 120),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 120))
        let search = NSTextField(frame: NSRect(x: 20, y: 70, width: 260, height: 28))
        let other = NSTextField(frame: NSRect(x: 20, y: 20, width: 260, height: 28))
        content.addSubview(search)
        content.addSubview(other)
        window.contentView = content
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }
        var attempts: [AppKitSearchFieldFocusAttempt] = []
        let requestsBeforeFocus = window.makeFirstResponderRequestCount

        if observed {
            AppKitSearchFieldLifecycle.requestFocus(
                search, delayedRetries: [0.05, 0.15], isValid: { true },
                observer: { attempts.append($0) }
            )
        } else {
            AppKitSearchFieldLifecycle.requestFocus(
                search, delayedRetries: [0.05, 0.15], isValid: { true }
            )
        }
        let deadline = Date(timeIntervalSinceNow: 1)
        while Date() < deadline {
            if window.makeFirstResponderRequestCount > requestsBeforeFocus,
               let editor = search.currentEditor(), window.firstResponder === editor { break }
            try await Task.sleep(for: .milliseconds(1))
        }

        let searchEditor = try #require(search.currentEditor())
        #expect(window.makeFirstResponderRequestCount > requestsBeforeFocus)
        #expect(window.firstResponder === searchEditor)
        if observed {
            let immediate = try #require(attempts.first)
            #expect(immediate.source == .immediate)
            #expect(immediate.makeFirstResponderResult == true)
            #expect(immediate.firstResponderIsFieldEditor)
        }

        #expect(window.makeFirstResponder(other))
        let otherEditor = try #require(other.currentEditor())
        #expect(search.currentEditor() == nil)
        #expect(window.firstResponder === otherEditor)
        let requestsAfterHandoff = window.makeFirstResponderRequestCount
        await withCheckedContinuation { continuation in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                continuation.resume()
            }
        }

        #expect(search.currentEditor() == nil)
        let currentOtherEditor = try #require(other.currentEditor())
        #expect(window.firstResponder === currentOtherEditor)
        #expect(window.makeFirstResponderRequestCount == requestsAfterHandoff)
        if observed {
            #expect(attempts.map(\.source) == [.immediate])
        }
    }

    @Test @MainActor func detachedFieldRetriesAfterWindowAttachment() async throws {
        let field = NSTextField(frame: NSRect(x: 20, y: 40, width: 260, height: 28))
        let window = FocusRequestTrackingWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 120),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 120))
        window.contentView = content
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }
        var attempts: [AppKitSearchFieldFocusAttempt] = []

        AppKitSearchFieldLifecycle.requestFocus(
            field, delayedRetries: [0.05], isValid: { true },
            observer: { attempts.append($0) }
        )
        let immediateDeadline = Date(timeIntervalSinceNow: 1)
        while attempts.isEmpty, Date() < immediateDeadline {
            try await Task.sleep(for: .milliseconds(1))
        }
        let immediate = try #require(attempts.first)
        #expect(immediate.source == .immediate)
        #expect(!immediate.hasWindow)
        #expect(!immediate.firstResponderIsFieldEditor)

        content.addSubview(field)
        #expect(field.currentEditor() == nil)
        let retryDeadline = Date(timeIntervalSinceNow: 1)
        while attempts.count < 2, Date() < retryDeadline {
            try await Task.sleep(for: .milliseconds(1))
        }
        let retry = try #require(attempts.last)
        let editor = try #require(field.currentEditor())
        #expect(attempts.count == 2)
        #expect(retry.source == .delayed(0.05))
        #expect(retry.hasWindow)
        #expect(retry.makeFirstResponderResult == true)
        #expect(retry.firstResponderIsFieldEditor)
        #expect(window.firstResponder === editor)
    }

    @Test @MainActor func successfulResponderReturnWithoutFieldEditorStillRetries() async throws {
        let field = NSTextField(frame: NSRect(x: 20, y: 40, width: 260, height: 28))
        field.isEditable = false
        let window = FocusRequestTrackingWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 120),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        window.contentView = field
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }
        var attempts: [AppKitSearchFieldFocusAttempt] = []

        AppKitSearchFieldLifecycle.requestFocus(
            field, delayedRetries: [0.05], isValid: { true },
            observer: { attempts.append($0) }
        )
        let deadline = Date(timeIntervalSinceNow: 1)
        while attempts.count < 2, Date() < deadline {
            try await Task.sleep(for: .milliseconds(1))
        }

        #expect(attempts.map(\.source) == [.immediate, .delayed(0.05)])
        #expect(attempts.first?.makeFirstResponderResult == true)
        #expect(attempts.allSatisfy { !$0.firstResponderIsFieldEditor })
        #expect(window.makeFirstResponderRequestCount >= 2)
    }

    @Test @MainActor func optionalCommandHandlerOwnsPaletteSpecificCommands() {
        let state = TestState(text: "")
        let coordinator = AppKitSearchFieldCoordinator(
            text: state.binding,
            processedFocusToken: nil,
            focusRetryDelays: [],
            requestFocus: { _, _, _ in }
        )
        coordinator.update(
            text: state.binding,
            onFocusChange: nil,
            commandHandler: { _, selector in
                state.commandSelectors.append(selector)
                return selector == #selector(NSResponder.moveDown(_:))
            }
        )

        let handled = coordinator.control(
            NSTextField(),
            textView: NSTextView(),
            doCommandBy: #selector(NSResponder.moveDown(_:))
        )

        #expect(handled)
        #expect(state.commandSelectors == [#selector(NSResponder.moveDown(_:))])
    }
}

@MainActor
private final class FocusRequestTrackingWindow: NSWindow {
    private(set) var makeFirstResponderRequestCount = 0

    override func makeFirstResponder(_ responder: NSResponder?) -> Bool {
        makeFirstResponderRequestCount += 1
        return super.makeFirstResponder(responder)
    }
}

@MainActor
private final class TestState {
    var text: String
    var focusEvents: [Bool] = []
    var focusRequests: [[TimeInterval]] = []
    var focusRequestValidities: [AppKitSearchFieldCoordinator.FocusRequestValidity] = []
    var commandSelectors: [Selector] = []
    var isPresented = true
    var presentationSession = 0

    init(text: String) {
        self.text = text
    }

    var binding: Binding<String> {
        Binding(
            get: { self.text },
            set: { self.text = $0 }
        )
    }
}
