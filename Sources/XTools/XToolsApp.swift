import AppKit
import SwiftUI
import XToolsCore

extension Notification.Name {
    static let openXToolsPreferences = Notification.Name("XTools.openXToolsPreferences")
    static let presentXToolsPreferences = Notification.Name("XTools.presentXToolsPreferences")
}

/// 关闭窗口后从菜单打开设置时，AppDelegate 会先创建主窗口；若 RootView
/// 尚未安装，通知会丢失。RootView 首次出现时消费这个标记并打开设置。
@MainActor
enum PendingPreferencesPresentation {
    static var isPending = false
}

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
    /// Test seam for the Dock-reopen path; production uses `openWindowAction`.
    var openWindowFallback: (() -> Void)?
    /// Test seam for window discovery; production uses `NSApp.windows`.
    var windowProvider: (() -> [NSWindow])?

    private func windows() -> [NSWindow] {
        windowProvider?() ?? NSApp.windows
    }

    private func requestMainWindow() {
        openWindowFallback?() ?? openWindowAction?(id: "main")
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleOpenPreferences),
            name: .openXToolsPreferences,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            if !showMainWindow() {
                requestMainWindow()
            }
            sender.activate()
        }
        return true
    }

    @objc private func handleOpenPreferences(_ notification: Notification) {
        presentPreferences()
    }

    /// 设置菜单在窗口关闭后仍然可用：先恢复主窗口，再让 RootView 呈现 sheet。
    private func presentPreferences() {
        if showMainWindow() {
            PendingPreferencesPresentation.isPending = false
            NotificationCenter.default.post(name: .presentXToolsPreferences, object: nil)
            return
        }

        PendingPreferencesPresentation.isPending = true
        requestMainWindow()
        NSApp.activate(ignoringOtherApps: true)
    }

    private func showMainWindow() -> Bool {
        let availableWindows = windows()
        let candidate = availableWindows.first(where: { !($0 is NSPanel) && $0.title == "Tools" })
            ?? availableWindows.first(where: { !($0 is NSPanel) })
        guard let window = candidate else { return false }
        if window.isMiniaturized {
            window.deminiaturize(nil)
        } else {
            window.makeKeyAndOrderFront(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
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

            CommandGroup(replacing: .appSettings) {
                Button("设置…") {
                    NotificationCenter.default.post(name: .openXToolsPreferences, object: nil)
                }
                .keyboardShortcut(",", modifiers: .command)
            }

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
