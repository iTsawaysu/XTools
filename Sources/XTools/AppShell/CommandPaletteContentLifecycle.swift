import AppKit
import SwiftUI

@MainActor
final class CommandPaletteContentLifecycle: ObservableObject, CommandPalettePresentationLifecycle {
    let revealRegistry = CommandPaletteRevealRegistry()
    let pointerMovementTracker = CommandPalettePointerMovementTracker()
    private(set) var sessionRevealRequest: CommandPaletteRevealRequest?

    private var liveSession: Int?
    private weak var sessionModel: CommandPaletteSessionModel?
    private var baseActions: [CommandActionEntry]
    private var revealRequestToken = 0
    private weak var searchField: NSTextField?
    private weak var searchCoordinator: AppKitSearchFieldCoordinator?

    init(
        session: Int,
        actions: [CommandActionEntry]
    ) {
        self.baseActions = actions
        resume(session: session)
    }

    func attachSessionModel(_ sessionModel: CommandPaletteSessionModel) {
        self.sessionModel = sessionModel
    }

    func updateActions(_ actions: [CommandActionEntry]) {
        baseActions = actions
    }

    func commandPaletteDidOpen(session: Int) {
        withTransaction(ToolMotion.disabledTransaction) {
            sessionModel?.beginSession(session, actions: baseActions)
            resume(session: session)
            // The persistent native field resets with the session while the
            // panel is still invisible: the text is cleared here (beginSession
            // already reset the model query) and focus scheduling is re-armed
            // after the previous session's close invalidation.
            searchField?.stringValue = ""
            searchCoordinator?.rearmFocusRequests()
            // Enable the persistent field ahead of the SwiftUI update pass and
            // attempt focus on this runloop turn — waiting for the scheduled
            // retry chain used to leave the first ~50ms of the open arc
            // without a cursor. A failed attempt (the first open has no
            // window yet) falls through to the [0.05, 0.15] retry chain; a
            // succeeded one makes those retries no-ops (already first
            // responder with the field editor owned).
            if let field = searchField {
                field.isEnabled = true
                field.window?.makeFirstResponder(field)
            }
            sessionRevealRequest = makeRevealRequest(
                source: .openReset,
                snapshot: sessionModel?.snapshot,
                session: session
            )
        }
    }

    func prepareSessionIfNeeded(session: Int) {
        guard sessionModel?.session != session else { return }
        commandPaletteDidOpen(session: session)
    }

    func makeRevealRequest(
        source: CommandPaletteActiveChangeSource,
        snapshot: CommandPaletteRowSnapshot?,
        session: Int
    ) -> CommandPaletteRevealRequest? {
        guard liveSession == session,
              let snapshot,
              let anchor = source.revealAnchor,
              let activeID = sessionModel?.navigationState.activeRowID(in: snapshot)
        else {
            return nil
        }

        revealRequestToken &+= 1
        revealRegistry.markRevealRequest(
            token: revealRequestToken,
            session: session
        )
        if case .keyboard = source {
            revealRegistry.markKeyboardRevealPending(
                itemID: activeID,
                token: revealRequestToken,
                session: session
            )
        }
        return CommandPaletteRevealRequest(
            id: activeID,
            anchor: anchor,
            token: revealRequestToken,
            session: session
        )
    }

    func resume(session: Int) {
        liveSession = session
        pointerMovementTracker.clear()
        revealRegistry.resume(session: session)
    }

    func attachSearchField(
        _ field: NSTextField,
        coordinator: AppKitSearchFieldCoordinator
    ) {
        searchField = field
        searchCoordinator = coordinator
    }

    func detachSearchField(_ field: NSTextField) {
        guard searchField === field else { return }
        searchField = nil
        searchCoordinator = nil
    }

    func commandPaletteDidClose(session: Int) {
        guard liveSession == session else { return }
        liveSession = nil
        revealRegistry.suspend(session: session)
        pointerMovementTracker.clear()

        // The persistent field stays in the retained tree after close, so the
        // close path owns dropping its field editor and disabling input —
        // exactly the editor teardown the per-session rebuild used to do.
        searchCoordinator?.invalidateFocusRequests()
        searchField?.isEnabled = false
        if let field = searchField,
           let window = field.window,
           let editor = field.currentEditor(),
           window.firstResponder === editor {
            window.makeFirstResponder(nil)
        }
    }

    func tearDown() {
        if let liveSession {
            commandPaletteDidClose(session: liveSession)
        }
    }
}
