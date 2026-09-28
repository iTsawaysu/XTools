import SwiftUI

/// Wave 2 command-palette selection highlight (prototype MOTION s.cmdkHlStretch
/// + MOTION.spring): the active row's fill + stroke float in one capsule that
/// springs between rows on keyboard moves — same 0.3/0.85 family as the
/// sidebar pill — and stretches vertically on jumps of two rows or more.
/// List rebuilds (query reset, new session) reposition it instantly, matching
/// the prototype's silent reposition on rebuilds.
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

/// One keyboard-driven highlight flight: the envelope parameters snapshot
/// at the moment the active row changes. Jumps of two rows or more stretch
/// the highlight vertically (prototype MOTION s.cmdkHlStretch).
struct CommandPaletteHighlightFlight: Equatable {
    let fromY: CGFloat
    let toY: CGFloat
    let rowHeight: CGFloat

    /// ≥2 rows of travel stretches the capsule.
    var stretches: Bool {
        abs(toY - fromY) >= rowHeight * 2
    }

    /// Flight progress at a sampled highlight position, clamped to [0, 1].
    func progress(at y: CGFloat) -> CGFloat {
        let travel = toY - fromY
        guard travel != 0 else { return 1 }
        return min(max((y - fromY) / travel, 0), 1)
    }
}

/// Springs the highlight from its previous row to the target row: `y` is
/// the animatable channel (driven by the shared 0.3/0.85 gentle spring);
/// the 4p(1-p) envelope stretches the capsule about its center on
/// multi-row flights, mirroring the sidebar pill's velocity stretch.
@MainActor
struct CommandPaletteHighlightFlightEffect: GeometryEffect {
    let flight: CommandPaletteHighlightFlight?
    var y: CGFloat

    var animatableData: CGFloat {
        get { y }
        set { y = newValue }
    }

    nonisolated func effectValue(size: CGSize) -> ProjectionTransform {
        guard let flight else {
            return ProjectionTransform(CGAffineTransform(translationX: 0, y: y))
        }
        let progress = flight.progress(at: y)
        let stretch = flight.stretches
            ? (ToolMotion.PaletteMotion.highlightStretchPeak - 1) * 4 * progress * (1 - progress)
            : 0
        var transform = CGAffineTransform(translationX: 0, y: y)
        transform = transform.translatedBy(x: 0, y: size.height / 2)
        transform = transform.scaledBy(x: 1, y: 1 + stretch)
        transform = transform.translatedBy(x: 0, y: -size.height / 2)
        return ProjectionTransform(transform)
    }
}

/// Floating selection fill + stroke behind the list rows. Keyboard moves
/// spring the capsule between rows (with the ≥2-row vertical stretch);
/// non-animated changes drop it instantly. Reduce Motion removes the spring
/// entirely — the highlight follows the active row without interpolation.
struct CommandPaletteSelectionHighlightLayer: View {
    let activeFrame: CGRect?
    let animates: Bool
    let reduceMotion: Bool

    @State private var flight: CommandPaletteHighlightFlight?
    @State private var settledFrame: CGRect?

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
                    .modifier(CommandPaletteHighlightFlightEffect(
                        flight: flight,
                        y: activeFrame.minY
                    ))
                    .offset(x: activeFrame.minX)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .animation(
            animates && !reduceMotion
                ? ToolMotion.PaletteMotion.highlightSlide
                : nil,
            value: activeFrame?.minY
        )
        .onChange(of: activeFrame) { newFrame in
            if animates,
               !reduceMotion,
               let previousFrame = settledFrame,
               let newFrame,
               previousFrame.minY != newFrame.minY {
                flight = CommandPaletteHighlightFlight(
                    fromY: previousFrame.minY,
                    toY: newFrame.minY,
                    rowHeight: newFrame.height
                )
            } else {
                flight = nil
            }
            settledFrame = newFrame
        }
    }
}
