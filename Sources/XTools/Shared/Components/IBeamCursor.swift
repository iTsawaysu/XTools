import AppKit
import SwiftUI

/// AppKit cursor-rect is unreliable inside a SwiftUI host, so the I-beam is
/// driven from SwiftUI hover instead of the field's own cursor rects. `onHover`
/// fires once per enter/exit (no per-move wakeups); the AppKit arrow-rect
/// layers below remain the authoritative fallback for chrome zones.
private struct IBeamCursorModifier: ViewModifier {
    /// Chrome columns kept out of the I-beam hover target: the line-number
    /// gutter on the leading edge and the overlay scrollbar on the trailing
    /// edge. Both are chrome, so the arrow owns them.
    var excludingLeading: CGFloat = 0
    var excludingTrailing: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .contentShape(
                LeadingExcludedHoverShape(
                    excludedLeading: excludingLeading,
                    excludedTrailing: excludingTrailing
                )
            )
            .onHover { isHovering in
                if isHovering {
                    NSCursor.iBeam.set()
                } else {
                    NSCursor.arrow.set()
                }
            }
            // A page switch can remove the hovered editor without an exit
            // event; without this reset the I-beam would stick app-wide.
            .onDisappear {
                NSCursor.arrow.set()
            }
    }
}

private struct LeadingExcludedHoverShape: Shape {
    var excludedLeading: CGFloat
    var excludedTrailing: CGFloat

    func path(in rect: CGRect) -> Path {
        let leading = max(0, excludedLeading)
        let trailing = max(0, excludedTrailing)
        guard leading + trailing < rect.width else { return Path() }
        return Path(
            CGRect(
                x: rect.minX + leading,
                y: rect.minY,
                width: rect.width - leading - trailing,
                height: rect.height
            )
        )
    }
}

extension View {
    /// Apply to the outermost container so the cursor covers the padded region,
    /// not just the inner AppKit field bounds.
    func iBeamCursorOnHover(
        excludingLeading: CGFloat = 0,
        excludingTrailing: CGFloat = 0
    ) -> some View {
        modifier(
            IBeamCursorModifier(
                excludingLeading: excludingLeading,
                excludingTrailing: excludingTrailing
            )
        )
    }
}

// MARK: - Arrow cursor zones

/// Transparent AppKit layer that registers an arrow cursor rect over its
/// frame (hit-test transparent, clicks pass through). Native text surfaces
/// beneath install their own I-beam rect; a frontmost arrow rect removes the
/// source instead of racing it — the shared I-beam helper's inverse problem.
private struct ArrowCursorRectLayer: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        ArrowCursorRectView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class ArrowCursorRectView: NSView {
        override func resetCursorRects() {
            addCursorRect(bounds, cursor: .arrow)
        }

        override func hitTest(_ point: NSPoint) -> NSView? {
            nil
        }
    }
}

extension View {
    /// Chrome (glass footers, field accessory buttons, gutters) floating over
    /// an editable or selectable text surface: the hover point is not
    /// typeable or selectable content, so the cursor must stay an arrow.
    /// Registers the arrow rect up front and asserts it on hover enter —
    /// the menu panel's proven pattern generalized.
    func arrowCursorOnHover() -> some View {
        overlay {
            ArrowCursorRectLayer()
        }
        .onHover { isHovering in
            if isHovering {
                NSCursor.arrow.set()
            }
        }
    }
}
