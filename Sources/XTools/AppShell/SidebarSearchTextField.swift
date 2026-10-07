import AppKit
import SwiftUI

struct SidebarSearchTextField: NSViewRepresentable {
    let placeholder: String
    @Binding var text: String
    let focusToken: Int
    let contentInsets: IndexTextFieldContentInsets
    let onFocusChange: (Bool) -> Void

    private var configuration: AppKitSearchFieldConfiguration {
        AppKitSearchFieldConfiguration(
            placeholder: placeholder,
            font: .systemFont(ofSize: 12.5),
            contentInsets: contentInsets
        )
    }

    func makeCoordinator() -> AppKitSearchFieldCoordinator {
        AppKitSearchFieldCoordinator(
            text: $text,
            processedFocusToken: 0,
            focusRetryDelays: [0.05]
        )
    }

    func makeNSView(context: Context) -> NSTextField {
        let textField = AppKitSearchFieldLifecycle.makeTextField(
            configuration: configuration,
            text: $text,
            focusToken: focusToken,
            coordinator: context.coordinator,
            onFocusChange: onFocusChange
        )
        textField.setAccessibilityIdentifier("sidebar.search")
        return textField
    }

    func updateNSView(_ textField: NSTextField, context: Context) {
        textField.setAccessibilityIdentifier("sidebar.search")
        AppKitSearchFieldLifecycle.update(
            textField,
            configuration: configuration,
            text: $text,
            focusToken: focusToken,
            coordinator: context.coordinator,
            onFocusChange: onFocusChange
        )
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        nsView textField: NSTextField,
        context: Context
    ) -> CGSize? {
        guard let height = proposal.height else { return nil }
        return CGSize(width: proposal.width ?? textField.fittingSize.width, height: height)
    }

    static func dismantleNSView(
        _ textField: NSTextField,
        coordinator: AppKitSearchFieldCoordinator
    ) {
        coordinator.invalidateFocusRequests()
    }
}
