import SwiftUI

/// Wave 2 command-palette selection highlight, redone to match mature
/// launchers (Raycast / Linear command menu): the active row carries one
/// neutral floating fill that slides to the next row with a fast
/// critically-damped spring — glued to the row, retargetable under key
/// repeat, never stretched. List rebuilds (query reset, new session)
/// reposition it instantly.
///
/// This file owns the geometry plumbing (row anchor preference, list-space
/// resolution) so the palette view itself stays free of continuous geometry
/// measurement (see `MotionSourceContractTests`).

/// Bounds of the palette's selectable rows, published once per row and
/// resolved by the highlight host in list coordinates. Section titles and
/// the empty state publish nothing.
struct CommandPaletteRowAnchorsKey: PreferenceKey {
    static let defaultValue: [String: Anchor<CGRect>] = [:]

    static func reduce(
        value: inout [String: Anchor<CGRect>],
        nextValue: () -> [String: Anchor<CGRect>]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

/// Resolves the collected row anchors against the list's bounds and hosts
/// the floating highlight layer behind the rows.
struct CommandPaletteSelectionHighlightHost: View {
    let activeItemID: String?
    let anchors: [String: Anchor<CGRect>]
    let animates: Bool
    let reduceMotion: Bool

    var body: some View {
        GeometryReader { proxy in
            CommandPaletteSelectionHighlightLayer(
                activeFrame: CommandPaletteSelectionHighlightLayer.resolvedActiveFrame(
                    activeItemID,
                    anchors: anchors,
                    proxy: proxy
                ),
                animates: animates,
                reduceMotion: reduceMotion
            )
        }
    }
}

/// Floating selection fill behind the list rows. Keyboard moves slide the
/// whole frame (position *and* size) on the shared fast snap spring; a
/// spring keeps mid-flight retargeting continuous when ↑↓ repeats outpace
/// the settle. Non-animated changes drop it instantly. Reduce Motion
/// removes the spring entirely — the highlight follows the active row
/// without interpolation.
struct CommandPaletteSelectionHighlightLayer: View {
    let activeFrame: CGRect?
    let animates: Bool
    let reduceMotion: Bool

    /// Resolves the active row's anchor in list space.
    static func resolvedActiveFrame(
        _ activeItemID: String?,
        anchors: [String: Anchor<CGRect>],
        proxy: GeometryProxy
    ) -> CGRect? {
        guard let activeItemID, let anchor = anchors[activeItemID] else {
            return nil
        }
        return proxy[anchor]
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let activeFrame {
                RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.field, style: .continuous)
                    .fill(ToolTheme.selectionFill)
                    .overlay {
                        RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.field, style: .continuous)
                            .strokeBorder(ToolTheme.selectionStroke, lineWidth: 1)
                    }
                    .frame(width: activeFrame.width, height: activeFrame.height)
                    .offset(x: activeFrame.minX, y: activeFrame.minY)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .animation(
            animates && !reduceMotion
                ? ToolMotion.PaletteMotion.highlightSlide
                : nil,
            value: activeFrame
        )
    }
}
