import AppKit
import SwiftUI
import XToolsCore

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

@MainActor
final class XToolsAppDelegate: NSObject, NSApplicationDelegate {
    var openWindowAction: OpenWindowAction?

    func applicationDidFinishLaunching(_ notification: Notification) {
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            let candidate = sender.windows.first(where: { !($0 is NSPanel) && $0.title == "Tools" })
                ?? sender.windows.first(where: { !($0 is NSPanel) })
                ?? sender.windows.first
            if let window = candidate {
                if window.isMiniaturized {
                    window.deminiaturize(nil)
                } else {
                    window.makeKeyAndOrderFront(nil)
                }
            } else {
                openWindowAction?(id: "main")
            }
            if #available(macOS 14.0, *) {
                sender.activate()
            } else {
                sender.activate(ignoringOtherApps: true)
            }
        }
        return true
    }
}

@main
struct XToolsApp: App {
    @NSApplicationDelegateAdaptor(XToolsAppDelegate.self) private var appDelegate
    @Environment(\.openWindow) private var openWindow

    init() {
        // Provide a snappy 400ms tooltip delay (default 1.5s is too slow).
        // This avoids instant-hover misfire while feeling much faster.
        UserDefaults.standard.register(defaults: ["NSInitialToolTipDelay": 400])

        // One-shot domain migration must run before RootView / stores read
        // UserDefaults.standard under the new bundle id.
        LegacyPreferencesMigrator.migrateFromLegacyDomainIfNeeded()

        // Pinyin search needs the ICU Han→Latin engine; constructing it costs
        // ~45ms once per process, so warm it off the main thread instead of
        // paying inside the first palette/sidebar query.
        ToolSearchEngine.prewarmTransliterationEngine()

        // The emoji picker reads EmojiCatalog.groups inside its first render
        // pass; decoding the 384KB plist there put the whole catalog build on
        // the main thread at click time. Same treatment as the ICU prewarm.
        EmojiCatalog.prewarmCatalog()
    }

    var body: some Scene {
        Window("Tools", id: "main") {
            RootView()
                .frame(minWidth: 960, minHeight: 640)
                .onAppear {
                    appDelegate.openWindowAction = openWindow
                }
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
