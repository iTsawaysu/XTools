import AppKit
import QuartzCore
import SwiftUI

/// Shared motion vocabulary for the macOS tool UI.
///
/// Motion stays intentionally lightweight: tokens describe state feedback,
/// panel reveal, modal reveal, and icon/text swaps without changing workspace
/// ownership, scroll behavior, or split/focus semantics.
enum ToolMotion {
    enum Duration {
        static let stagger: TimeInterval = 0.04
        static let micro: TimeInterval = 0.12
        static let quick: TimeInterval = 0.15
        static let arrival: TimeInterval = 0.24
        static let fast: TimeInterval = 0.25
        static let medium: TimeInterval = 0.35
        /// Page-header letter arrival: delay added per title character.
        static let letterStagger: TimeInterval = 0.032
        /// Subtitle follow-up beat after the letter choreography starts.
        static let headerFollowDelay: TimeInterval = 0.16
        /// Wave 2 output breath: the arc starts 80ms after the run so the
        /// text swap lands first (prototype MOTION d.breathDelay).
        static let outputBreathDelay: TimeInterval = 0.08
        /// Half-arc of the single 640ms breath envelope (320 up + 320 down).
        static let outputBreathHalfArc: TimeInterval = 0.32
        /// Wave 2 card-lift pane hover: enter 180ms, leave 240ms (prototype
        /// MOTION d.hoverIn / d.hoverOut).
        static let hoverIn: TimeInterval = 0.18
        static let hoverOut: TimeInterval = 0.24
        /// Wave 2 error feedback: damped-sine shake total (prototype
        /// MOTION d.shake).
        static let shake: TimeInterval = 0.3
        /// Warning tint fade-in (delayed off the shake start) / fade-out.
        static let errorTintIn: TimeInterval = 0.24
        static let errorTintOut: TimeInterval = 0.2
        static let errorTintDelay: TimeInterval = 0.08
        /// Wave 2 theme crossfade: 320ms single envelope (prototype d.themeXfade).
        static let themeCrossfade: TimeInterval = 0.32
        /// Wave 2 segmented-control active-label cross-fade (prototype
        /// MOTION d.labelXfade).
        static let labelXfade: TimeInterval = 0.12
    }

    enum Distance {
        static let micro: CGFloat = 3
        static let small: CGFloat = 6
        static let base: CGFloat = 8
        static let medium: CGFloat = 12
        static let large: CGFloat = 18
        /// Page-header arrival: per-letter rise (≈0.6em of the 18pt page title)
        /// and the subtitle follow-up offset.
        static let letterRise: CGFloat = 11
        static let headerFollow: CGFloat = 4
    }

    enum Scale {
        static let modal: CGFloat = 0.98
        static let pressed: CGFloat = 0.98
        static let iconInserted: CGFloat = 0.98
        static let iconRemoved: CGFloat = 1.02
        /// Wave 2 sidebar selection pill stretch (prototype MOTION s.pillStretch*):
        /// vertical stretch per row of travel, capped, with horizontal volume
        /// compensation; only jumps beyond `pillStretchMinRows` rows stretch.
        static let pillStretchPerRow: CGFloat = 0.06
        static let pillStretchMax: CGFloat = 0.15
        static let pillStretchMinRows: CGFloat = 1.5
        /// Page-arrival depth: incoming tool pages settle from 99.5% scale.
        static let pageArrivalSink: CGFloat = 0.995
    }

    enum ResultPresence {
        static let appearanceDuration = Duration.medium
        static let exitDuration = Duration.fast
    }

    enum OrderedDirection {
        case backward
        case forward

        var insertionOffsetX: CGFloat {
            switch self {
            case .backward: -Distance.small
            case .forward: Distance.small
            }
        }
    }

    enum Curve {
        static let smoothOutControlPoints = (
            x1: 0.22,
            y1: 1.0,
            x2: 0.36,
            y2: 1.0
        )

        /// Productive exit easing accelerates content that is leaving the view.
        /// Source: https://carbondesignsystem.com/elements/motion/overview/#easing
        static let productiveExitControlPoints = (
            x1: 0.2,
            y1: 0.0,
            x2: 1.0,
            y2: 0.9
        )

        static func smoothOut(duration: TimeInterval) -> Animation {
            .timingCurve(
                smoothOutControlPoints.x1,
                smoothOutControlPoints.y1,
                smoothOutControlPoints.x2,
                smoothOutControlPoints.y2,
                duration: duration
            )
        }

        static func productiveExit(duration: TimeInterval) -> Animation {
            .timingCurve(
                productiveExitControlPoints.x1,
                productiveExitControlPoints.y1,
                productiveExitControlPoints.x2,
                productiveExitControlPoints.y2,
                duration: duration
            )
        }

        static func inOut(duration: TimeInterval) -> Animation {
            .easeInOut(duration: duration)
        }

        /// Symmetric exit arc (prototype easeExit 0.45/0/0.55/1): keeps leaving
        /// content readable mid-flight. Serves Wave 2 breath-fall and palette
        /// close half-arcs; declared discrete exception to the smoothOut family.
        static let exitControlPoints = (
            x1: 0.45,
            y1: 0.0,
            x2: 0.55,
            y2: 1.0
        )

        static func exit(duration: TimeInterval) -> Animation {
            .timingCurve(
                exitControlPoints.x1,
                exitControlPoints.y1,
                exitControlPoints.x2,
                exitControlPoints.y2,
                duration: duration
            )
        }

        // MARK: - Spring family (Clay Warmth feel)
        //
        // Springs derive their timing from `response` (both stay inside the
        // HIG 100–500ms envelope). Reduce Motion still gates them through
        // `ToolMotion.animation(_:reduceMotion:)`.

        /// Container-grade spring: settles without visible overshoot. Use for
        /// selection pills, container reveal, sidebar-like geometry.
        static func gentleSpring() -> Animation {
            .spring(response: 0.3, dampingFraction: 0.85, blendDuration: 0)
        }

        /// Slight-overshoot spring reserved for delight moments (copy success,
        /// generated-result arrival, favorite star). Never for containers.
        static func playfulSpring() -> Animation {
            .spring(response: 0.35, dampingFraction: 0.7, blendDuration: 0)
        }
    }

    enum Preset {
        static let controlFeedback = Curve.inOut(duration: Duration.micro)
        static let textSwap = Curve.inOut(duration: Duration.quick)
        static let iconSwap = Curve.inOut(duration: Duration.quick)
        static let orderedContent = Curve.smoothOut(duration: Duration.fast)
        static let tabs = Curve.smoothOut(duration: Duration.fast)
        static let accordion = Curve.smoothOut(duration: Duration.medium)
        /// Favorite-order / disclosure family timing. AppKit sidebar owns reorder
        /// presentation; do not bind this preset to SwiftUI `searchText` or Root.
        static let navigationReorder = accordion
        static let shellResize = Curve.smoothOut(duration: Duration.fast)
        static let modal = Animation.spring(response: 0.25, dampingFraction: 0.86, blendDuration: 0)
        static let panelReveal = Curve.smoothOut(duration: Duration.medium)
        /// v3: tool-switch page arrival (host-owned whitelist; see
        /// `MotionSourceContractTests`). Light crossfade that keeps the entry
        /// hot path responsive — pages never apply this preset themselves.
        static let pageArrival = Curve.smoothOut(duration: Duration.arrival)
        /// Page-header letter choreography: each title character rises with
        /// the shared container spring, one stagger step apart. Consumed by
        /// `IndexPageHeader` only; tool pages never apply it themselves.
        static func letterArrival(index: Int) -> Animation {
            Curve.gentleSpring().delay(letterArrivalDelay(index: index))
        }

        static func letterArrivalDelay(index: Int) -> TimeInterval {
            Double(index) * Duration.letterStagger
        }
        /// Subtitle follow-up beat after the letter choreography starts.
        static let headerFollow = Curve.smoothOut(duration: Duration.arrival)
        static let resultPresenceAppearance = Curve.smoothOut(duration: ResultPresence.appearanceDuration)
        static let resultPresenceExit = Curve.productiveExit(duration: ResultPresence.exitDuration)
        static let diagnostic = Curve.inOut(duration: Duration.quick)
        /// Wave 2 theme crossfade (prototype MOTION d.themeXfade): the whole
        /// SwiftUI colorScheme dissolves through one 320ms envelope; AppKit
        /// chrome (WindowAppearanceOwner) still flips natively.
        static let themeCrossfade = Curve.inOut(duration: Duration.themeCrossfade)
        /// Output breath: one-shot accent pulse when an explicit run lands
        /// (output pane chrome). Terminal envelope lives in `OutputBreath`.
        /// Container settle: no-overshoot spring for selection pills and reveals.
        static let settle = Curve.gentleSpring()
        /// Delight: slight-overshoot spring for success/result-arrival moments only.
        static let delight = Curve.playfulSpring()
    }

    /// Wave 2 terminal values for the output success breath (prototype
    /// MOTION d.breath*): delayed single 640ms arc — border-led with a faint
    /// wash, rise on smoothOut / fall on the exit arc. Border/wash opacity
    /// only; no glow, no re-trigger stacking.
    enum OutputBreath {
        static let delay = Duration.outputBreathDelay
        static let rise = Curve.smoothOut(duration: Duration.outputBreathHalfArc)
        static let fall = Curve.exit(duration: Duration.outputBreathHalfArc)
        /// Border-layer peak opacity over the arc.
        static let borderPeak: Double = 0.28
        /// Wash fill peak: accent at 1.5% over the pane background.
        static let washPeak: Double = 0.015
    }

    /// Wave 2 card-lift pane hover (prototype MOTION d.hoverIn/hoverOut):
    /// the pane reads as a card lifting off the surface through neutral
    /// shadow depth (recipes live in `ToolTheme.Shadow.paneHover*`) plus a
    /// border deepen and a faint white background lift. Zero
    /// translate/scale by discipline; this namespace owns timing only.
    enum PaneHover {
        static let inCurve = Curve.smoothOut(duration: Duration.hoverIn)
        static let outCurve = Curve.smoothOut(duration: Duration.hoverOut)
        /// White overlay peak: ≈1.5% background lift in both themes.
        static let washPeak: Double = 0.015
    }

    /// Wave 2 error feedback terminal values (prototype MOTION d.shake /
    /// d.errTint* / x.shake*): one damped-sine horizontal jolt plus a
    /// state-held warning tint. No-flash rule: the tint is a *state*, not a
    /// pulse — it fades in delayed after the shake starts, holds while the
    /// error persists, and fades out on resolve; border width never changes.
    enum ErrorFeedback {
        static let shakeCurve = Curve.inOut(duration: Duration.shake)
        static let shakeAmplitude: CGFloat = 4
        static let shakeDecay: Double = 0.68
        static let shakeOscillations: Double = 3
        static let tintDelay = Duration.errorTintDelay
        static let tintPeak: Double = 0.55
        static let tintIn = Curve.smoothOut(duration: Duration.errorTintIn)
        static let tintOut = Curve.smoothOut(duration: Duration.errorTintOut)
    }

    /// Wave 2 sidebar search-result arrival (prototype MOTION d/x.search*):
    /// first filter → fade-dominant staggered rise (12ms/row capped at 7,
    /// 4pt rise, 140ms per row); refinement while filtered → 100ms row
    /// crossfade with persistent rows untouched; leaving search is instant.
    enum SearchArrival {
        static let stagger: TimeInterval = 0.012
        static let rowCap = 7
        static let rowIn: TimeInterval = 0.14
        static let rowCrossfade: TimeInterval = 0.1
        static let rise: CGFloat = 4
    }

    /// Wave 2 empty-state arrival (prototype MOTION d/x.empty*): the icon
    /// rises on a slight-overshoot spring, then the caption and message
    /// follow one beat apart (fade-dominant). Reduce Motion shows directly.
    enum EmptyArrival {
        static let iconRise = Animation.spring(response: 0.3, dampingFraction: 0.71)
        static let textFollow = Curve.smoothOut(duration: 0.3).delay(0.06)
        static let messageFollow = Curve.smoothOut(duration: 0.3).delay(0.12)
        static let iconRiseDistance: CGFloat = 6
        static let textRiseDistance: CGFloat = 4
    }

    /// Wave 2 command-palette choreography (prototype MOTION d/x/s.cmdk*):
    /// open = 240ms smoothOut rise (8pt) + fade while the scrim dims on its
    /// own independent 200ms arc; close = 200ms exit-arc fade settling toward
    /// the 0.985 scale. Open and close share ONE continuous rise/sink
    /// distance and scale mapping so rapid reversals never hard-switch the
    /// presentation geometry (contract: `CommandPaletteVisibilityGeometry`).
    /// Rows stagger in 20ms/row starting 60ms after the panel launch; the
    /// keyboard selection highlight slides on the shared gentle spring
    /// (0.3/0.85, same family as the sidebar pill) and stretches ≈1.08
    /// vertically across jumps of two rows or more.
    enum PaletteMotion {
        /// Panel open: 8pt rise + fade on the spring family (cmdkIn 240ms,
        /// prototype --ease ≈ smoothOut feel). A near-critical spring keeps
        /// the arc overshoot-free while staying retargetable mid-flight.
        static let open = Animation.spring(
            response: 0.24,
            dampingFraction: 0.95,
            blendDuration: 0
        )
        /// Panel close: fade + sink settling in ~200ms (cmdkOut). A
        /// critically damped spring approximates the prototype's easeExit
        /// arc monotonically — timing-curve variants stall real-window
        /// retargets (see `CommandPaletteMotionTests` rapid reversals).
        static let close = Animation.spring(
            response: 0.2,
            dampingFraction: 1.0,
            blendDuration: 0
        )
        /// Scrim dims in / out on its own 200ms arc, independent of the
        /// panel's 240ms open choreography (cmdkMask). Critically damped so
        /// opacity never overshoots.
        static let scrimIn = Animation.spring(
            response: 0.2,
            dampingFraction: 1.0,
            blendDuration: 0
        )
        static let scrimOut = Animation.spring(
            response: 0.2,
            dampingFraction: 1.0,
            blendDuration: 0
        )
        /// Unified rise/sink travel: open rises from 8pt below the resting
        /// position, close sinks the same 8pt while fading. The prototype
        /// splits this 8 in / 6 out; one distance keeps reversal geometry
        /// continuous (cmdkRise / cmdkSink).
        static let riseDistance: CGFloat = 8
        /// Panel settle scale at the closed end of the interpolation; the
        /// open arc passes through the same settling scale (cmdkOut 0.985).
        static let settleScale: CGFloat = 0.985
        /// Row entrance starts 60ms after the panel launch (cmdkRowsDelay).
        static let rowsDelay: TimeInterval = 0.06
        /// Per-row entrance stagger: the shared list cadence (MOTION
        /// d.listStagger, 20ms; the sidebar search keeps its faster 12ms
        /// `SearchArrival.stagger`).
        static let rowStagger: TimeInterval = 0.02
        /// Each row's entrance arc (prototype rowIn .15s).
        static let rowIn: TimeInterval = 0.15
        /// Row entrance rise (prototype rowIn translateY 4px).
        static let rowRise: CGFloat = 4
        /// Selection highlight flight spring — the shared 0.3/0.85 container
        /// spring, same family as the sidebar selection pill.
        static let highlightSlide = Curve.gentleSpring()
        /// Highlight vertical stretch peak across ≥2-row jumps (cmdkHlStretch).
        static let highlightStretchPeak: CGFloat = 1.08

        /// Per-row entrance animation: 150ms smoothOut rise + fade, delayed
        /// by the 60ms panel-launch lead plus the row's 20ms stagger step.
        static func rowArrival(index: Int) -> Animation {
            Curve.smoothOut(duration: rowIn)
                .delay(rowsDelay + TimeInterval(index) * rowStagger)
        }
    }

    /// Wave 2 copy-confirmation tick (prototype MOTION d.copyOut / d.copyDraw /
    /// d.copyBox / d.copyBack / d.copyHold + s.copyBoxFrom): the shared copy
    /// button keeps its label and width constant (zero deformation); the copy
    /// glyph fades out while a checkmark stroke-draws in, the icon box settles
    /// 0.94→1 once, dwells 1200ms (matching the pinned copied-state lifecycle), then both glyphs cross-fade back
    /// symmetrically. Reduce Motion collapses to the plain symbol cut.
    enum CopyTick {
        /// Copy glyph fade-out on enter (d.copyOut).
        static let out: TimeInterval = 0.12
        /// Checkmark stroke draw (d.copyDraw, prototype --ease).
        static let draw: TimeInterval = 0.22
        /// Icon-box settle arc, 0.94→1 one-shot (d.copyBox).
        static let box: TimeInterval = 0.18
        /// Symmetric fade-back after the dwell (d.copyBack).
        static let back: TimeInterval = 0.12
        /// Dwell before the fade-back (d.copyHold).
        static let hold: TimeInterval = 1.2
        /// Icon-box settle start scale (s.copyBoxFrom).
        static let boxFrom: CGFloat = 0.94
        /// Glyph cross-fade in (copyOut on the shared smoothOut family).
        static let fade = Curve.smoothOut(duration: out)
        /// Glyph cross-fade out after the dwell (copyBack, symmetric).
        static let fadeBack = Curve.smoothOut(duration: back)
        /// Checkmark draw curve (prototype --ease).
        static let drawCurve = Curve.smoothOut(duration: draw)
        /// Icon-box settle: the one declared easeSettle curve exception
        /// (0.25, 1.2, 0.45, 1 — ≤2% overshoot), one-shot like the prototype
        /// keyframe; no retargeting surface, so the exact curve is safe here.
        static let boxSettle = Animation.timingCurve(0.25, 1.2, 0.45, 1.0, duration: box)
    }

    /// Wave 2 segmented-control sliding cursor (prototype MOTION d.segCursor /
    /// d.labelXfade + s.segCursorStretch + MOTION.springFast): the selected
    /// fill detaches from the segments into one shared cursor that springs to
    /// the newly selected segment on the fast variant of the selection-slide
    /// spring family (0.3/0.85 sidebar pill and palette highlight → 0.22
    /// here, ≈220ms), stretching ≈1.10 horizontally mid-flight and settling
    /// on arrival. The active label cross-fades its color over 120ms on the
    /// smoothOut family. Reduce Motion drops the cursor onto the new segment
    /// and cuts the label directly.
    enum SegmentedCursor {
        /// Cursor flight spring — the 0.22 fast variant of the shared
        /// 0.3/0.85 selection-slide family (springFast ≈ 220ms).
        static let slide = Animation.spring(
            response: 0.22,
            dampingFraction: 0.85,
            blendDuration: 0
        )
        /// Horizontal stretch peak sampled mid-flight (s.segCursorStretch).
        static let stretchPeak: CGFloat = 1.10
        /// Active-label color/state cross-fade (d.labelXfade, smoothOut).
        static let labelXfade = Curve.smoothOut(duration: Duration.labelXfade)
    }

    struct AppKitMotion {
        let duration: TimeInterval
        let timingFunction: CAMediaTimingFunction
    }

    enum AppKitPreset {
        static var accordion: AppKitMotion {
            let points = Curve.smoothOutControlPoints
            return AppKitMotion(
                duration: Duration.medium,
                timingFunction: CAMediaTimingFunction(
                    controlPoints: Float(points.x1),
                    Float(points.y1),
                    Float(points.x2),
                    Float(points.y2)
                )
            )
        }

        /// Spring-matched slide for the sidebar selection indicator. Mirrors
        /// `Curve.gentleSpring()` (response 0.3 / damping 0.85) through the
        /// standard SwiftUI→CASpringAnimation parameter mapping, so AppKit
        /// layer motion and SwiftUI containers stay in one spring family.
        /// Duration self-reports from `settlingDuration`; consumers retarget
        /// mid-flight by reading the presentation layer.
        static func selectionSlide() -> CASpringAnimation {
            let response = 0.3
            let dampingFraction = 0.85
            let spring = CASpringAnimation(keyPath: "position.y")
            spring.mass = 1
            spring.stiffness = pow(2 * .pi / response, 2)
            spring.damping = 4 * .pi * dampingFraction / response
            spring.duration = max(spring.settlingDuration, Duration.quick)
            return spring
        }
    }

    enum Transition {
        static var scrim: AnyTransition {
            .opacity
        }

        /// v3: tool-switch arrival — outgoing page fades, incoming page sinks
        /// by one base step while settling from 99.5% scale (depth without a
        /// visible zoom). Host-owned; Reduce Motion collapses to identity
        /// through the shared transition helper.
        static var pageArrival: AnyTransition {
            AnyTransition.asymmetric(
                insertion: .opacity
                    .combined(with: .offset(y: Distance.base))
                    .combined(with: .scale(scale: Scale.pageArrivalSink)),
                removal: .opacity
            )
        }

        /// v3: command palette panel — prototype-matched scale-and-settle:
        /// the panel fades in slightly small, settling downward; removal
        /// reverses the settle. The scrim stays on `scrim` (opacity-only).
        static var commandPalette: AnyTransition {
            AnyTransition.asymmetric(
                insertion: .opacity
                    .combined(with: .scale(scale: Scale.modal))
                    .combined(with: .offset(y: -Distance.small)),
                removal: .opacity
                    .combined(with: .scale(scale: Scale.modal))
            )
        }

        static var modal: AnyTransition {
            AnyTransition.opacity
                .combined(with: .scale(scale: Scale.modal))
        }

        static var toastPanel: AnyTransition {
            AnyTransition.asymmetric(
                insertion: .opacity.combined(with: .offset(y: -Distance.base)),
                removal: .opacity.combined(with: .offset(y: -Distance.small))
            )
        }

        static var modeContent: AnyTransition {
            AnyTransition.asymmetric(
                insertion: .opacity.combined(with: .offset(y: Distance.micro)),
                removal: .opacity
            )
        }

        static var topRowInsertion: AnyTransition {
            AnyTransition.asymmetric(
                insertion: .opacity.combined(with: .offset(y: -Distance.small)),
                removal: .identity
            )
        }

        static var diagnostic: AnyTransition {
            AnyTransition.asymmetric(
                insertion: .opacity.combined(with: .offset(y: -Distance.small)),
                removal: .opacity
            )
        }

        static var iconSwap: AnyTransition {
            AnyTransition.asymmetric(
                insertion: .opacity.combined(with: .scale(scale: Scale.iconInserted)),
                removal: .opacity.combined(with: .scale(scale: Scale.iconRemoved))
            )
        }

        static var textSwap: AnyTransition {
            AnyTransition.opacity
        }

        static func orderedContent(_ direction: OrderedDirection) -> AnyTransition {
            AnyTransition.asymmetric(
                insertion: .opacity.combined(with: .offset(x: direction.insertionOffsetX)),
                removal: .opacity
            )
        }
    }

    static var systemReduceMotionEnabled: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    static func animation(_ animation: Animation, reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : animation
    }

    static func transition(_ transition: AnyTransition, reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .identity : transition
    }

    static var disabledTransaction: Transaction {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        return transaction
    }
}

@MainActor
func withToolAnimation(
    _ animation: Animation = ToolMotion.Preset.controlFeedback,
    reduceMotion: Bool? = nil,
    _ body: () -> Void
) {
    if reduceMotion ?? ToolMotion.systemReduceMotionEnabled {
        body()
    } else {
        withAnimation(animation, body)
    }
}

/// Compatibility wrapper for non-View feedback owners such as the toast center.
@MainActor
func applyToolMotion(_ body: () -> Void) {
    withToolAnimation(ToolMotion.Preset.panelReveal, body)
}

private struct ToolMotionAnimationModifier<Value: Equatable>: ViewModifier {
    let animation: Animation
    let value: Value

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.animation(
            ToolMotion.animation(animation, reduceMotion: reduceMotion),
            value: value
        )
    }
}

private struct ToolMotionIdentityTransitionModifier<ID: Hashable>: ViewModifier {
    let id: ID
    let transition: AnyTransition
    let animation: Animation

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .id(id)
            .transition(ToolMotion.transition(transition, reduceMotion: reduceMotion))
            .animation(ToolMotion.animation(animation, reduceMotion: reduceMotion), value: id)
    }
}

/// Numeric readout tween: digit roll on value change (macOS 14+
/// `numericText`). Older systems and Reduce Motion render the final value
/// directly — the motion is presentation-only chrome for instrument reads.
private struct ToolNumericTransitionModifier<Value: Equatable>: ViewModifier {
    let value: Value

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if #available(macOS 14.0, *) {
            content
                .contentTransition(.numericText())
                .animation(
                    ToolMotion.animation(ToolMotion.Preset.textSwap, reduceMotion: reduceMotion),
                    value: value
                )
        } else {
            content
        }
    }
}

extension View {
    func toolAnimation<Value: Equatable>(
        _ animation: Animation,
        value: Value
    ) -> some View {
        modifier(ToolMotionAnimationModifier(animation: animation, value: value))
    }

    func toolTransition(
        _ transition: AnyTransition,
        reduceMotion: Bool
    ) -> some View {
        self.transition(ToolMotion.transition(transition, reduceMotion: reduceMotion))
    }

    /// v3: tool-switch page arrival. Identity-driven so the outgoing page fades
    /// while the incoming page rises; the shared modifier owns Reduce Motion.
    func toolPageArrival<ID: Hashable>(id: ID) -> some View {
        modifier(
            ToolMotionIdentityTransitionModifier(
                id: id,
                transition: ToolMotion.Transition.pageArrival,
                animation: ToolMotion.Preset.pageArrival
            )
        )
    }

    func toolMotionIconSwap<ID: Hashable>(id: ID) -> some View {
        modifier(
            ToolMotionIdentityTransitionModifier(
                id: id,
                transition: ToolMotion.Transition.iconSwap,
                animation: ToolMotion.Preset.iconSwap
            )
        )
    }

    /// Delight variant for success moments only (copy/save checkmark reveal).
    func toolMotionSuccessSwap<ID: Hashable>(id: ID) -> some View {
        modifier(
            ToolMotionIdentityTransitionModifier(
                id: id,
                transition: ToolMotion.Transition.iconSwap,
                animation: ToolMotion.Preset.delight
            )
        )
    }

    func toolMotionTextSwap<ID: Hashable>(id: ID) -> some View {
        modifier(
            ToolMotionIdentityTransitionModifier(
                id: id,
                transition: ToolMotion.Transition.textSwap,
                animation: ToolMotion.Preset.textSwap
            )
        )
    }

    /// Digit-roll tween for monospaced count readouts (see
    /// `ToolNumericTransitionModifier`).
    func toolNumericTransition<Value: Equatable>(value: Value) -> some View {
        modifier(ToolNumericTransitionModifier(value: value))
    }
}
