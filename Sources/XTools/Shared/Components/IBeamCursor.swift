import AppKit
import SwiftUI

/// AppKit cursor-rect is unreliable inside a SwiftUI host, so the I-beam is
/// driven from SwiftUI hover instead of the field's own cursor rects. Re-asserting
/// on every move prevents a missed exit event from leaving the cursor stuck.
private struct IBeamCursorModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active:
                    NSCursor.iBeam.set()
                case .ended:
                    NSCursor.arrow.set()
                }
            }
    }
}

extension View {
    /// Apply to the outermost container so the cursor covers the padded region,
    /// not just the inner AppKit field bounds.
    func iBeamCursorOnHover() -> some View {
        modifier(IBeamCursorModifier())
    }
}
