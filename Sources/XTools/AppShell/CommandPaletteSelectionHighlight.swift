import SwiftUI

/// Command-palette selection highlight, matched to mature launchers
/// (Raycast / Spotlight): the active row carries one neutral floating fill
/// that repositions INSTANTLY — keyboard navigation reads as smooth through
/// deterministic, zero-latency feedback; interpolation only ever lags the
/// selection behind the keys. Rebuilds (query reset, new session), pointer
/// moves, and ↑↓ moves all snap identically.
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

    var body: some View {
        GeometryReader { proxy in
            CommandPaletteSelectionHighlightLayer(
                activeFrame: CommandPaletteSelectionHighlightLayer.resolvedActiveFrame(
                    activeItemID,
                    anchors: anchors,
                    proxy: proxy
                )
            )
        }
    }
}

/// Floating selection fill behind the list rows. Every active-row change
/// repositions it instantly (no interpolation): under ↑↓ key repeat an
/// animated highlight trails the keys by rows, which reads as lag.
struct CommandPaletteSelectionHighlightLayer: View {
    let activeFrame: CGRect?

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
    }
}
