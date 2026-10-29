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
    private var monitor: Any?

    func install(viewModel: RootViewModel) {
        self.viewModel = viewModel
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let action = self.action(for: event) else { return event }
            action()
            return nil
        }
    }

    func uninstall() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
    }

    private func action(for event: NSEvent) -> (() -> Void)? {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags == .command,
              let characters = event.charactersIgnoringModifiers?.lowercased(),
              let window = NSApp.keyWindow,
              window.title == "Tools",
              window.attachedSheet == nil,
              NSApp.modalWindow == nil else { return nil }

        switch characters {
        case "k":
            return { [weak self] in
                withToolAnimation(ToolMotion.Preset.modal) {
                    self?.viewModel?.toggleCommandPalette()
                }
            }
        case "f":
            // An editor with its native find bar keeps ⌘F for incremental
            // search; the Edit menu routes it there.
            if let textView = window.firstResponder as? NSTextView, textView.usesFindBar {
                return nil
            }
            return { [weak self] in
                guard let self, let viewModel = self.viewModel else { return }
                if viewModel.sidebarVisibility == .hidden {
                    viewModel.sidebarVisibility = .visible
                }
                // 先装首字缓冲再要焦点：SwiftUI 的 focusToken 更新落下一拍，
                // 用户紧随 ⌘F 敲下的第一个字符会先于字段就绪到达。
                AppKitSearchFieldCoordinator.armSidebarSearchKeystrokeHandoff()
                viewModel.focusSearch()
            }
        default:
            return nil
        }
    }
}
