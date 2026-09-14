import AppKit
import SwiftUI

/// Installs window-scoped focus and mouse behavior that cannot be expressed by
/// a page-local SwiftUI gesture. Native toolbar presentation belongs to the
/// scene and is intentionally not configured here.
/// Installed once via `.background(WindowChromeConfigurator())` on the root.
struct WindowChromeConfigurator: NSViewRepresentable {
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        Task { @MainActor in
            configure(window: view.window, coordinator: context.coordinator)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        Task { @MainActor in
            configure(window: nsView.window, coordinator: context.coordinator)
        }
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.removeMouseMonitor()
    }

    private func configure(window: NSWindow?, coordinator: Coordinator) {
        guard let window else { return }

        coordinator.installMouseMonitor(for: window)

        // 启动时清掉初始 key focus（P1）。AppKit 默认把窗口里第一个可聚焦控件
        // （恰为侧边栏搜索框）设为 first responder，造成「打开 app 焦点就在搜索框」。
        // 只在首次清一次：之后用户按 ⌘F 主动聚焦后不能再被抢走，所以 updateNSView
        // 反复调用时不重复清。延后到下一拍，确保在 AppKit 赋初始焦点之后执行。
        if !coordinator.didClearInitialFocus {
            coordinator.didClearInitialFocus = true
            Task { @MainActor in
                window.makeFirstResponder(nil)
            }
        }
    }

    @MainActor
    final class Coordinator {
        var didClearInitialFocus = false
        private weak var monitoredWindow: NSWindow?
        private var mouseMonitor: Any?

        func installMouseMonitor(for window: NSWindow) {
            guard monitoredWindow !== window else { return }
            removeMouseMonitor()
            monitoredWindow = window

            mouseMonitor = NSEvent.addLocalMonitorForEvents(
                matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
            ) { [weak window] event in
                guard let window, event.window === window else { return event }

                let clickedView = window.contentView.flatMap { contentView in
                    let location = contentView.convert(event.locationInWindow, from: nil)
                    return contentView.hitTest(location)
                }
                guard WindowTextEditingFocusPolicy.shouldDismissEditing(
                    firstResponder: window.firstResponder,
                    clickedView: clickedView
                ) else {
                    return event
                }

                window.makeFirstResponder(nil)
                return event
            }
        }

        func removeMouseMonitor() {
            if let mouseMonitor {
                NSEvent.removeMonitor(mouseMonitor)
                self.mouseMonitor = nil
            }
            monitoredWindow = nil
        }
    }
}

// Ends an active AppKit text-editing session when the next click is not another
// editable text target. The original mouse event is still delivered.
@MainActor
enum WindowTextEditingFocusPolicy {
    static func shouldDismissEditing(
        firstResponder: NSResponder?,
        clickedView: NSView?
    ) -> Bool {
        guard isEditableTextResponder(firstResponder) else { return false }
        return !isEditingTarget(clickedView)
    }

    private static func isEditableTextResponder(_ responder: NSResponder?) -> Bool {
        if let textView = responder as? NSTextView {
            return textView.isEditable
        }
        if let textField = responder as? NSTextField {
            return textField.isEditable && textField.isEnabled
        }
        return false
    }

    private static func isEditingTarget(_ clickedView: NSView?) -> Bool {
        var candidate = clickedView
        while let view = candidate {
            if let textView = view as? NSTextView, textView.isEditable {
                return true
            }
            if let textField = view as? NSTextField,
               textField.isEditable,
               textField.isEnabled {
                return true
            }
            candidate = view.superview
        }
        return false
    }
}
