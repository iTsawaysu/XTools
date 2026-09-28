import AppKit
import QuartzCore
import SwiftUI

/// Shared press acknowledgement for controls across the shell.
///
/// Hover remains a color cue, while press gets a short scale response so a
/// click is acknowledged even when the control's selection state does not
/// change immediately. The animation is disabled for Reduce Motion.
struct ToolInteractionFeedbackStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(
                ToolMotion.animation(ToolMotion.Preset.controlFeedback, reduceMotion: reduceMotion),
                value: configuration.isPressed
            )
    }
}

extension View {
    /// Applies the shared press/focus treatment without replacing a view's
    /// existing surface or hover colors.
    func toolInteractionFeedback() -> some View {
        buttonStyle(ToolInteractionFeedbackStyle())
    }

    /// Pane-level hover chrome: deepens the pane border to `strongBorder`
    /// while the pointer is inside, so the editing surface answers the cursor
    /// before any control does. Border-color transition only — no movement,
    /// no shadow; Reduce Motion keeps it (it is a state color, not motion).
    func toolPaneHoverChrome(cornerRadius: CGFloat = ToolMetrics.CornerRadius.field) -> some View {
        modifier(ToolPaneHoverChromeModifier(cornerRadius: cornerRadius))
    }
}

private struct ToolPaneHoverChromeModifier: ViewModifier {
    let cornerRadius: CGFloat
    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let recipe = isHovered
            ? ToolTheme.Shadow.paneHoverLifted
            : ToolTheme.Shadow.paneHoverResting
        content
            .toolShadowBehind(recipe, cornerRadius: cornerRadius)
            .overlay {
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(Color.white)
                        .opacity(isHovered ? ToolMotion.PaneHover.washPeak : 0)
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(
                            isHovered ? ToolTheme.strongBorder : .clear,
                            lineWidth: 1
                        )
                }
                .allowsHitTesting(false)
            }
            .onHover { hovering in
                guard hovering != isHovered else { return }
                if reduceMotion {
                    isHovered = hovering
                } else {
                    withAnimation(hovering ? ToolMotion.PaneHover.inCurve : ToolMotion.PaneHover.outCurve) {
                        isHovered = hovering
                    }
                }
            }
    }
}

/// One-shot breath for output panes (Wave 2 terminal envelope, see
/// `ToolMotion.OutputBreath`): 80ms after an explicit run lands — so the text
/// swap settles first — a single 640ms arc fades an accent border and a faint
/// wash in and out. Rise and fall are separate transactions (smoothOut in,
/// exit arc out). Keyed by a caller-supplied generation; re-triggering while
/// active restarts the arc instead of stacking. Reduce Motion and
/// non-positive generations render nothing.
struct ToolOutputBreathModifier: ViewModifier {
    let generation: Int
    let cornerRadius: CGFloat
    @State private var isBreathing = false
    @State private var breathTask: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay {
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(ToolTheme.accent)
                        .opacity(isBreathing ? ToolMotion.OutputBreath.washPeak : 0)
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(ToolTheme.accentBorder, lineWidth: 1)
                        .opacity(isBreathing ? ToolMotion.OutputBreath.borderPeak : 0)
                }
                .allowsHitTesting(false)
            }
            .onChange(of: generation) { _ in
                guard generation > 0, !reduceMotion else { return }
                breathTask?.cancel()
                breathTask = Task { @MainActor in
                    let ms = { (seconds: TimeInterval) in
                        UInt64(seconds * 1000)
                    }
                    let halfArc = ms(ToolMotion.Duration.outputBreathHalfArc)
                    try? await Task.sleep(nanoseconds: ms(ToolMotion.OutputBreath.delay))
                    guard !Task.isCancelled else { return }
                    withAnimation(ToolMotion.OutputBreath.rise) { isBreathing = true }
                    try? await Task.sleep(nanoseconds: halfArc)
                    guard !Task.isCancelled else { return }
                    withAnimation(ToolMotion.OutputBreath.fall) { isBreathing = false }
                }
            }
    }
}

extension View {
    /// Output-pane success breath (see `ToolOutputBreathModifier`).
    func toolOutputBreath(generation: Int, cornerRadius: CGFloat = ToolMetrics.CornerRadius.field) -> some View {
        modifier(ToolOutputBreathModifier(generation: generation, cornerRadius: cornerRadius))
    }
}

// MARK: - Error feedback (Wave 2)

/// Damped-sine horizontal jolt for failed explicit runs: amplitude decays
/// geometrically across the oscillations while the phase animates 0→1, so a
/// repeated identical failure (attempt bump) replays the same envelope.
@MainActor
struct ToolShakeEffect: GeometryEffect {
    var phase: CGFloat

    var animatableData: CGFloat {
        get { phase }
        set { phase = newValue }
    }

    nonisolated func effectValue(size: CGSize) -> ProjectionTransform {
        guard phase > 0 else { return ProjectionTransform(CGAffineTransform.identity) }
        let oscillations = ToolMotion.ErrorFeedback.shakeOscillations
        let envelope = pow(ToolMotion.ErrorFeedback.shakeDecay, Double(phase) * oscillations)
        let offset = ToolMotion.ErrorFeedback.shakeAmplitude
            * envelope
            * sin(Double(phase) * .pi * 2 * oscillations)
        return ProjectionTransform(CGAffineTransform(translationX: offset, y: 0))
    }
}

/// Shakes once per failed attempt (see `ToolShakeEffect`). Keyed by a caller
/// bump counter so repeated identical failures re-trigger; Reduce Motion
/// renders no offset.
struct ToolErrorShakeModifier: ViewModifier {
    let attempt: Int
    let isActive: Bool
    @State private var shakePhase: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .modifier(ToolShakeEffect(phase: shakePhase))
            .onChange(of: attempt) { _ in
                guard isActive, !reduceMotion else { return }
                shakePhase = 0
                withAnimation(ToolMotion.ErrorFeedback.shakeCurve) { shakePhase = 1 }
            }
    }
}

/// State-held warning tint for error chrome: the border is always laid out
/// at constant width and only its opacity moves — delayed fade-in after the
/// shake onset (`ToolMotion.ErrorFeedback.tintDelay`), hold while the error
/// persists, fade out on resolve. Never pulses; Reduce Motion jumps between
/// states without interpolation.
struct ToolErrorTintModifier: ViewModifier {
    let active: Bool
    let cornerRadius: CGFloat
    @State private var tintOn = false
    @State private var tintTask: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(ToolTheme.error, lineWidth: 1)
                    .opacity(tintOn ? ToolMotion.ErrorFeedback.tintPeak : 0)
                    .allowsHitTesting(false)
            }
            .onChange(of: active) { nowActive in
                tintTask?.cancel()
                guard !reduceMotion else {
                    tintOn = nowActive
                    return
                }
                if nowActive {
                    tintTask = Task { @MainActor in
                        try? await Task.sleep(
                            nanoseconds: UInt64(ToolMotion.ErrorFeedback.tintDelay * 1_000_000_000)
                        )
                        guard !Task.isCancelled else { return }
                        withAnimation(ToolMotion.ErrorFeedback.tintIn) { tintOn = true }
                    }
                } else {
                    withAnimation(ToolMotion.ErrorFeedback.tintOut) { tintOn = false }
                }
            }
    }
}

extension View {
    /// Error shake for explicit-run failures (see `ToolErrorShakeModifier`).
    func toolErrorShake(attempt: Int, isActive: Bool) -> some View {
        modifier(ToolErrorShakeModifier(attempt: attempt, isActive: isActive))
    }

    /// State-held warning border tint (see `ToolErrorTintModifier`).
    func toolErrorTint(active: Bool, cornerRadius: CGFloat) -> some View {
        modifier(ToolErrorTintModifier(active: active, cornerRadius: cornerRadius))
    }
}

// MARK: - Locating wash (Wave 2)

/// One-shot locating wash for difference-block jumps (Wave 2, see
/// `ToolMotion.LocatingWash`): when a jump lands on a difference block, one
/// layer over the target block sweeps its opacity 0 → peak → 0 across a
/// single 360ms arc while the pane's line-number slot marker deepens on the
/// same arc. One layer, one animated property, one arc — outline and enclose
/// treatments were explicitly rejected. Hosted on the AppKit side because
/// block geometry lives inside the TextKit diff editors; SwiftUI hosts keep
/// `toolOutputBreath` for pane-level feedback.
///
/// Two styles share one arc: `.blockWash` (accent fill peaking at
/// `washPeak`) and `.gutterDeepen` (an accentHover mark at full opacity that
/// widens the resting 2pt slot mark to 3pt mid-arc). Keyed by a
/// caller-supplied generation so repeated identical triggers and re-renders
/// never replay the arc. Reduce Motion plays nothing — the jump itself still
/// scrolls and selects.
@MainActor
final class ToolLocatingWashView: NSView {
    enum Style {
        /// Block background wash: accent fill peaking at `washPeak` opacity.
        case blockWash
        /// Line-number slot mark deepening: accentHover fill at full opacity
        /// over the resting slot mark, same 360ms arc.
        case gutterDeepen
    }

    private let style: Style
    private var playedGeneration = 0
    private static let arcKey = "toolLocatingWashArc"

    init(style: Style) {
        self.style = style
        super.init(frame: .zero)
        wantsLayer = true
        updateLayer()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        super.updateLayer()
        switch style {
        case .blockWash:
            layer?.backgroundColor = NSColor(ToolTheme.accent).cgColor
            layer?.cornerRadius = ToolMotion.LocatingWash.washCornerRadius
        case .gutterDeepen:
            layer?.backgroundColor = NSColor(ToolTheme.accentHover).cgColor
            layer?.cornerRadius = ToolMotion.LocatingWash.gutterDeepCornerRadius
        }
        layer?.opacity = 0
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateLayer()
    }

    /// Repositions the wash to cover `rect` (host-view coordinates) without
    /// an implicit layer animation, then plays the one-shot arc once per
    /// generation change. Reduce Motion keeps the repositioning silent — the
    /// jump's scroll/selection behavior is owned by the caller and untouched.
    func play(generation: Int, frame: NSRect) {
        guard generation != playedGeneration else { return }
        playedGeneration = generation

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        self.frame = frame
        CATransaction.commit()

        guard !ToolMotion.systemReduceMotionEnabled else { return }
        let peak: Double
        switch style {
        case .blockWash:
            peak = ToolMotion.LocatingWash.washPeak
        case .gutterDeepen:
            peak = ToolMotion.LocatingWash.gutterDeepPeak
        }
        layer?.removeAnimation(forKey: Self.arcKey)
        layer?.add(ToolMotion.LocatingWash.opacityKeyframe(peak: peak), forKey: Self.arcKey)
    }
}
