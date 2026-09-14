import AppKit
import SwiftUI

struct SidebarNavigationList: NSViewRepresentable {
    let configuration: SidebarNavigationListConfiguration

    func makeCoordinator() -> SidebarNavigationListCoordinator {
        SidebarNavigationListCoordinator()
    }

    func makeNSView(context: Context) -> NSScrollView {
        context.coordinator.makeScrollView()
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.update(
            scrollView: scrollView,
            configuration: configuration
        )
    }
}
