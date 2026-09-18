import AppKit
import SwiftUI

/// Routes menu find commands into the focused `NSTextView`'s native find bar
/// (the Safari/Xcode-style inline bar with incremental search). Text surfaces
/// opt in by setting `usesFindBar = true`; other responders never see these
/// actions, so the sidebar field editor can never grow a stray find bar.
@MainActor
enum AppKitFindCommandRouter {
    enum Action {
        case showFindInterface
        case nextMatch
        case previousMatch

        var finderAction: NSTextFinder.Action {
            switch self {
            case .showFindInterface:
                return .showFindInterface
            case .nextMatch:
                return .nextMatch
            case .previousMatch:
                return .previousMatch
            }
        }
    }

    /// Returns false when no find-bar text view owns keyboard focus, so the
    /// caller can keep its previous meaning for the shortcut.
    @discardableResult
    static func perform(_ action: Action) -> Bool {
        let window = NSApp.keyWindow ?? NSApp.mainWindow
        guard let textView = window?.firstResponder as? NSTextView,
              textView.usesFindBar else {
            return false
        }

        // performTextFinderAction reads the finder action off sender.tag.
        let item = NSMenuItem()
        item.tag = action.finderAction.rawValue
        textView.performTextFinderAction(item)
        return true
    }
}

struct FindMenuCommands: Commands {
    @FocusedObject private var viewModel: RootViewModel?

    var body: some Commands {
        CommandGroup(after: .textEditing) {
            // When a find-bar surface (editor, output viewer, diff pane) holds
            // focus the command targets it; otherwise ⌘F keeps its historical
            // meaning of jumping to the sidebar tool search.
            Button("查找…") {
                guard !AppKitFindCommandRouter.perform(.showFindInterface) else { return }
                guard let viewModel else { return }
                if viewModel.sidebarVisibility == .hidden {
                    viewModel.sidebarVisibility = .visible
                }
                viewModel.focusSearch()
            }
            .keyboardShortcut("f", modifiers: .command)

            // Next/previous stay enabled: Commands bodies do not re-evaluate on
            // focus changes, and a stale disabled state would swallow ⌘G. They
            // simply no-op until a find-bar surface owns focus.
            Button("查找下一个") {
                AppKitFindCommandRouter.perform(.nextMatch)
            }
            .keyboardShortcut("g", modifiers: .command)

            Button("查找上一个") {
                AppKitFindCommandRouter.perform(.previousMatch)
            }
            .keyboardShortcut("g", modifiers: [.command, .shift])
        }
    }
}
