import AppKit
import SwiftUI

@MainActor
enum AppKitUndoCommandRouter {
    enum Action {
        case undo
        case redo

        var managerSelector: Selector {
            switch self {
            case .undo:
                return #selector(UndoManager.undo)
            case .redo:
                return #selector(UndoManager.redo)
            }
        }

        var responderSelector: Selector {
            switch self {
            case .undo:
                return Selector(("undo:"))
            case .redo:
                return Selector(("redo:"))
            }
        }
    }

    @discardableResult
    static func perform(
        _ action: Action,
        in window: NSWindow? = nil,
        application: NSApplication = .shared
    ) -> Bool {
        let activeWindow = window ?? application.keyWindow ?? application.mainWindow
        if let manager = activeTextEditor(in: activeWindow)?.undoManager {
            return application.sendAction(action.managerSelector, to: manager, from: nil)
        }

        return application.sendAction(action.responderSelector, to: nil, from: nil)
    }

    private static func activeTextEditor(in window: NSWindow?) -> NSTextView? {
        if let textView = window?.firstResponder as? NSTextView {
            return textView
        }
        if let textField = window?.firstResponder as? NSTextField {
            return textField.currentEditor() as? NSTextView
        }
        return nil
    }
}

@main
struct XToolsApp: App {
    init() {
        // Provide a snappy 400ms tooltip delay (default 1.5s is too slow).
        // This avoids instant-hover misfire while feeling much faster.
        UserDefaults.standard.register(defaults: ["NSInitialToolTipDelay": 400])

        // One-shot domain migration must run before RootView / stores read
        // UserDefaults.standard under the new bundle id.
        LegacyPreferencesMigrator.migrateFromLegacyDomainIfNeeded()
    }

    var body: some Scene {
        Window("Tools", id: "main") {
            RootView()
                .frame(minWidth: 960, minHeight: 640)
        }
        .windowStyle(HiddenTitleBarWindowStyle())
        // Compact unified chrome keeps the page identity and workspace close
        // to the native titlebar instead of reserving a tall empty band.
        .windowToolbarStyle(.unifiedCompact(showsTitle: false))
        .defaultSize(width: 1200, height: 800)
        .windowResizability(.contentMinSize)
        .commands {
            SidebarMenuCommands()
            CommandPaletteMenuCommands()
            FindMenuCommands()

            CommandGroup(replacing: .undoRedo) {
                Button("撤销") {
                    AppKitUndoCommandRouter.perform(.undo)
                }
                .keyboardShortcut("z", modifiers: .command)

                Button("重做") {
                    AppKitUndoCommandRouter.perform(.redo)
                }
                .keyboardShortcut("z", modifiers: [.command, .shift])
            }
        }
    }
}
