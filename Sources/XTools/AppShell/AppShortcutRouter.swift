import AppKit
import SwiftUI

/// Global keyboard shortcuts that must work even while a text field owns the
/// field editor. `NSTextView` consumes some command-key combinations (⌘K is
/// "delete to end of paragraph" in the standard key bindings), so a menu key
/// equivalent alone can silently lose the shortcut while the user is typing.
/// A local monitor sees the event before AppKit dispatches it and keeps the
/// editor's own find bar reachable for ⌘F.
@MainActor
final class AppShortcutRouter {
    private weak var viewModel: RootViewModel?
    private weak var window: NSWindow?
    private var monitor: Any?

    func install(viewModel: RootViewModel, window: NSWindow) {
        self.viewModel = viewModel
        self.window = window
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handle(event) == true ? nil : event
        }
    }

    func uninstall() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
        window = nil
    }

    func handle(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting(.capsLock)
        guard let viewModel,
              flags == .command || viewModel.commandPalettePresentation.isWaitingForOpeningKeys,
              let window,
              (event.window ?? NSApp.keyWindow) === window,
              window.attachedSheet == nil,
              NSApp.modalWindow == nil else { return false }
        guard flags == .command else {
            return viewModel.commandPalettePresentation.bufferOpeningKey(event)
        }
        guard let characters = event.charactersIgnoringModifiers?.lowercased() else { return false }

        switch characters {
        case "k":
            withToolAnimation(ToolMotion.Preset.modal, reduceMotion: ToolMotion.systemReduceMotionEnabled) {
                viewModel.toggleCommandPalette()
            }
        case "f":
            // An editor with its native find bar keeps ⌘F for incremental
            // search; the Edit menu routes it there.
            if !viewModel.showsCommandPalette,
               let textView = window.firstResponder as? NSTextView, textView.usesFindBar {
                return false
            }
            viewModel.focusSearch()
        default:
            return false
        }
        return true
    }
}
