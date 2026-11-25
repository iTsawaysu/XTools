import AppKit
import SwiftUI

@MainActor
protocol CommandPalettePresentationLifecycle: AnyObject {
    func commandPaletteDidOpen(session: Int)
    func commandPaletteDidClose(session: Int)
}

/// Lightweight presentation state observed only by the palette overlay host.
/// RootViewModel deliberately does not forward this object's notifications, so
/// opening or focusing the palette does not invalidate the full app shell.
@MainActor
final class CommandPalettePresentationModel: ObservableObject {
    private struct State {
        var shows = false
        var focusToken = 0
        var session = 0
        var hasPresented = false
    }

    @Published private var state = State()
    private weak var lifecycle: (any CommandPalettePresentationLifecycle)?

    var shows: Bool { state.shows }
    var focusToken: Int { state.focusToken }
    var session: Int { state.session }
    var hasPresented: Bool { state.hasPresented }

    func installLifecycle(_ lifecycle: any CommandPalettePresentationLifecycle) {
        self.lifecycle = lifecycle
    }

    func removeLifecycle(_ lifecycle: any CommandPalettePresentationLifecycle) {
        guard self.lifecycle === lifecycle else { return }
        self.lifecycle = nil
    }

    func focus() {
        var next = state
        next.focusToken += 1
        state = next
    }

    func open() {
        if state.shows {
            focus()
            return
        }

        let nextSession = state.session + 1
        CommandPaletteTrace.requestStarted(session: nextSession)
        var next = state
        next.shows = true
        next.focusToken += 1
        next.session = nextSession
        next.hasPresented = true
        CommandPaletteTrace.opened(session: nextSession)
        lifecycle?.commandPaletteDidOpen(session: nextSession)
        state = next
    }

    func toggle() {
        if state.shows {
            close()
        } else {
            open()
        }
    }

    func close() {
        guard state.shows else { return }
        let closingSession = state.session
        var next = state
        next.shows = false
        next.session += 1
        state = next
        // MainActor serialization makes the new invalid session visible before
        // native callbacks are synchronously suspended.
        lifecycle?.commandPaletteDidClose(session: closingSession)
    }
}
