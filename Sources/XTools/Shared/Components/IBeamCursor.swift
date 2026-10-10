import AppKit
import SwiftUI

/// AppKit cursor-rect is unreliable inside a SwiftUI host, so the I-beam is
/// driven from SwiftUI hover instead of the field's own cursor rects. `onHover`
/// fires once per enter/exit (no per-move wakeups); the AppKit arrow-rect
/// layers below remain the authoritative fallback for chrome zones.
private struct IBeamCursorModifier: ViewModifier {
    /// Chrome column (the line-number gutter) kept out of the I-beam hover
    /// target so the arrow owns it while text keeps the beam.
    var excludingLeading: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .contentShape(LeadingExcludedHoverShape(excludedLeading: excludingLeading))
            .onHover { isHovering in
                if isHovering {
                    NSCursor.iBeam.set()
                } else {
                    NSCursor.arrow.set()
                }
            }
    }
}

private struct LeadingExcludedHoverShape: Shape {
    var excludedLeading: CGFloat

    func path(in rect: CGRect) -> Path {
        guard excludedLeading > 0, rect.width > excludedLeading else { return Path(rect) }
        return Path(
            CGRect(x: excludedLeading, y: 0, width: rect.width - excludedLeading, height: rect.height)
        )
    }
}

extension View {
    /// Apply to the outermost container so the cursor covers the padded region,
    /// not just the inner AppKit field bounds.
    func iBeamCursorOnHover(excludingLeading: CGFloat = 0) -> some View {
        modifier(IBeamCursorModifier(excludingLeading: excludingLeading))
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
