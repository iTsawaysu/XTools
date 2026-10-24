import AppKit
import SwiftUI
import XToolsCore
import XToolsDesign

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
            // WindowGroup（D4）下的等价复活：优先唤起已有 "Tools" 窗口；
            // 完全无窗口时经 openWindow(id:"main") 新建（新窗口默认仪表盘，
            // 由 ShellSharedStores 的窗口认领序决定）。
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
    // 多窗口共享单例束（阶段③ D4，design.md §9）：App 级构造一份，每个
    // 窗口的 RootView 经 init 注入同一组 store（收藏/使用频率/偏好/侧栏
    // 折叠/工作台仓库跨窗口一致）；选中/搜索/面板状态每窗口独立。
    @State private var sharedStores = ShellSharedStores()

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
        // WindowGroup（D4）：系统 File > New Window（⌘N）免费获得；reopen
        // 复活逻辑（XToolsAppDelegate.applicationShouldHandleReopen）按窗口
        // title "Tools" 匹配已有窗口，无可见窗口时 openWindow(id:"main")
        // 经本组新建（新窗口默认仪表盘）。选中/搜索/面板状态每窗口独立。
        WindowGroup("Tools", id: "main") {
            RootView(shared: sharedStores)
                // min 尺寸单源：与 RootView 内容层 frame 共用 ToolMetrics.Window
                // 常量（阶段③ 治理速赢，原两处 960×640 字面量收敛）。
                .frame(minWidth: ToolMetrics.Window.minimumWidth, minHeight: ToolMetrics.Window.minimumHeight)
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
