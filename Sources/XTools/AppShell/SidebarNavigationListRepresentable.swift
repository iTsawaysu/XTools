import AppKit
import SwiftUI

struct SidebarNavigationList: NSViewRepresentable {
    let configuration: SidebarNavigationListConfiguration
    @Environment(\.isEnabled) private var isEnabled

    func makeCoordinator() -> SidebarNavigationListCoordinator {
        SidebarNavigationListCoordinator()
    }

    func makeNSView(context: Context) -> NSScrollView {
        context.coordinator.documentView.isKeyboardNavigationEnabled = isEnabled
        return context.coordinator.makeScrollView()
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.documentView.isKeyboardNavigationEnabled = isEnabled
        context.coordinator.update(
            scrollView: scrollView,
            configuration: configuration
        )
    }
}
