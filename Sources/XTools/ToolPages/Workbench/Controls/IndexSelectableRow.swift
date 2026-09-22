import SwiftUI

// MARK: - Focusable

extension View {
    /// Adds the shared keyboard-focus ring around any view.
    func indexFocusRing(active: Bool, cornerRadius: CGFloat = ToolMetrics.CornerRadius.control) -> some View {
        overlay {
            if active {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(ToolTheme.focusRing, lineWidth: 1.5)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
    }
}
