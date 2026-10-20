import AppKit
import QuartzCore
import SwiftUI

/// Shared motion vocabulary for the macOS tool UI.
///
/// Motion stays intentionally lightweight: tokens describe state feedback,
/// panel reveal, modal reveal, and icon/text swaps without changing workspace
/// ownership, scroll behavior, or split/focus semantics.
public enum ToolMotion {
    public enum Duration {
        public static let micro: TimeInterval = 0.12
        public static let quick: TimeInterval = 0.15
        public static let arrival: TimeInterval = 0.24
        public static let fast: TimeInterval = 0.25
        public static let medium: TimeInterval = 0.35
        /// 01 景深沉降 (PAGE-TRANSITIONS t-1): incoming page settles over
        /// 300ms on smoothOut.
        public static let pageSinkEnter: TimeInterval = 0.30
        /// 01 景深沉降: outgoing page leaves over 220ms on productiveExit —
        /// faster than the arrival so the exit never lags the new page.
        public static let pageSinkExit: TimeInterval = 0.22
        public static let pageSharedAxisEnter: TimeInterval = 0.32
        public static let pageSharedAxisExit: TimeInterval = 0.26
        public static let pageBloomEnter: TimeInterval = 0.42
        public static let pageBloomExit: TimeInterval = 0.20
        /// Page-header letter arrival: one character's rise arc on smoothOut
        /// (prototype .lt 480ms); delay comes from `letterStagger`.
        public static let letter: TimeInterval = 0.48
        /// Page-header letter arrival: delay added per title character.
        public static let letterStagger: TimeInterval = 0.032
        /// Subtitle follow-up beat after the letter choreography starts.
        public static let headerFollowDelay: TimeInterval = 0.16
        /// Indeterminate hairline sweep: one back-and-forth traversal of the
        /// rail. Loops sit outside the one-shot feedback envelope because the
        /// steady rhythm itself is the liveness cue — a shorter sweep reads
        /// as flicker. (Dropped by the logic-branch merge; restored.)
        public static let progressLoop: TimeInterval = 1.4
        /// Wave 2 output breath: the arc starts 80ms after the run so the
        /// text swap lands first (prototype MOTION d.breathDelay).
        public static let outputBreathDelay: TimeInterval = 0.08
        /// Half-arc of the single 640ms breath envelope (320 up + 320 down).
        public static let outputBreathHalfArc: TimeInterval = 0.32
        /// Wave 2 card-lift pane hover: enter 180ms, leave 240ms (prototype
        /// MOTION d.hoverIn / d.hoverOut).
        public static let hoverIn: TimeInterval = 0.18
        public static let hoverOut: TimeInterval = 0.24
        /// Warning tint fade-in / fade-out.
        public static let errorTintIn: TimeInterval = 0.24
        public static let errorTintOut: TimeInterval = 0.2
        public static let errorTintDelay: TimeInterval = 0.08
        /// Wave 2 theme crossfade: 320ms single envelope (prototype d.themeXfade).
        public static let themeCrossfade: TimeInterval = 0.32
        /// Wave 2 segmented-control active-label cross-fade (prototype
        /// MOTION d.labelXfade).
        public static let labelXfade: TimeInterval = 0.12
    }

    public enum Distance {
        public static let micro: CGFloat = 3
        public static let small: CGFloat = 6
        public static let base: CGFloat = 8
        public static let medium: CGFloat = 12
        public static let large: CGFloat = 18
        /// Page-header arrival rise (≈0.6em of the 18pt page title)
        /// and the subtitle follow-up offset.
        public static let letterRise: CGFloat = 11
        public static let headerFollow: CGFloat = 4
        /// 01 景深沉降: incoming page rises 10pt while settling (prototype
        /// translateY(10px)).
        public static let pageSinkRise: CGFloat = 10
        public static let pageSharedAxisRise: CGFloat = 18
        public static let pageSharedAxisDrop: CGFloat = 12
        public static let pageBloomDrop: CGFloat = 6
    }

    public enum Scale {
        public static let modal: CGFloat = 0.98
        public static let pressed: CGFloat = 0.98
        public static let iconInserted: CGFloat = 0.98
        public static let iconRemoved: CGFloat = 1.02
        /// Page-arrival depth: incoming tool pages settle from 99.5% scale.
        public static let pageArrivalSink: CGFloat = 0.995
        /// 01 景深沉降: outgoing pages sink to 99.2% while fading — depth on
        /// the exit without a readable zoom.
        public static let pageDepartureSink: CGFloat = 0.992
        public static let pageSharedAxisArrival: CGFloat = 1.04
        public static let pageSharedAxisDeparture: CGFloat = 0.96
        public static let pageBloomArrival: CGFloat = 0.94
    }

    public enum ResultPresence {
        public static let appearanceDuration = Duration.medium
        public static let exitDuration = Duration.fast
    }

    public enum OrderedDirection {
        case backward
        case forward

        public var insertionOffsetX: CGFloat {
            switch self {
            case .backward: -Distance.small
            case .forward: Distance.small
            }
        }
    }

    public enum Curve {
        public static let smoothOutControlPoints = (
            x1: 0.22,
            y1: 1.0,
            x2: 0.36,
            y2: 1.0
        )

        /// Productive exit easing accelerates content that is leaving the view.
        /// Source: https://carbondesignsystem.com/elements/motion/overview/#easing
        public static let productiveExitControlPoints = (
            x1: 0.2,
            y1: 0.0,
            x2: 1.0,
            y2: 0.9
        )

        public static func smoothOut(duration: TimeInterval) -> Animation {
            .timingCurve(
                smoothOutControlPoints.x1,
                smoothOutControlPoints.y1,
                smoothOutControlPoints.x2,
                smoothOutControlPoints.y2,
                duration: duration
            )
        }

        public static func productiveExit(duration: TimeInterval) -> Animation {
            .timingCurve(
                productiveExitControlPoints.x1,
                productiveExitControlPoints.y1,
                productiveExitControlPoints.x2,
                productiveExitControlPoints.y2,
                duration: duration
            )
        }

        public static func inOut(duration: TimeInterval) -> Animation {
            .easeInOut(duration: duration)
        }

        /// Symmetric exit arc (prototype easeExit 0.45/0/0.55/1): keeps leaving
        /// content readable mid-flight. Serves Wave 2 breath-fall and palette
        /// close half-arcs; declared discrete exception to the smoothOut family.
        public static let exitControlPoints = (
            x1: 0.45,
            y1: 0.0,
            x2: 0.55,
            y2: 1.0
        )

        public static func exit(duration: TimeInterval) -> Animation {
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
        public static func gentleSpring() -> Animation {
            .spring(response: 0.3, dampingFraction: 0.85, blendDuration: 0)
        }

        /// Slight-overshoot spring reserved for delight moments (copy success,
        /// generated-result arrival, favorite star). Never for containers.
        public static func playfulSpring() -> Animation {
            .spring(response: 0.35, dampingFraction: 0.7, blendDuration: 0)
        }
    }

    public enum Preset {
        public static let controlFeedback = Curve.inOut(duration: Duration.micro)
        public static let textSwap = Curve.inOut(duration: Duration.quick)
        public static let iconSwap = Curve.inOut(duration: Duration.quick)
        public static let orderedContent = Curve.smoothOut(duration: Duration.fast)
        public static let tabs = Curve.smoothOut(duration: Duration.fast)
        public static let accordion = Curve.smoothOut(duration: Duration.medium)
        public static let shellResize = Curve.smoothOut(duration: Duration.fast)
        public static let modal = Animation.spring(response: 0.25, dampingFraction: 0.86, blendDuration: 0)
        public static let panelReveal = Curve.smoothOut(duration: Duration.medium)
        /// v3: tool-switch page arrival (host-owned whitelist; see
        /// `MotionSourceContractTests`). 01 景深沉降: 300ms smoothOut — the
        /// incoming page sinks from y+10/99.5% while the outgoing layer runs
        /// its own 220ms productiveExit (`pageDeparture`). Timing is driven by
        /// `ToolPageStage`'s two explicit transactions, one per direction.
        public static let pageArrival = Curve.smoothOut(duration: Duration.pageSinkEnter)
        /// 01 景深沉降: outgoing page exit timing — 220ms productiveExit so
        /// leaving content accelerates away while the arrival still settles.
        public static let pageDeparture = Curve.productiveExit(duration: Duration.pageSinkExit)
        public static let pageSharedAxisArrival = Curve.smoothOut(duration: Duration.pageSharedAxisEnter)
        public static let pageSharedAxisDeparture = Curve.smoothOut(duration: Duration.pageSharedAxisExit)
        public static let pageBloomArrival = Curve.smoothOut(duration: Duration.pageBloomEnter)
        public static let pageBloomDeparture = Curve.productiveExit(duration: Duration.pageBloomExit)
        /// Page-header letter choreography: each title character rises on the
        /// shared 480ms smoothOut arc (prototype .lt), one stagger step apart.
        /// Consumed by `IndexPageHeader` only; tool pages never apply it
        /// themselves.
        public static func letterArrival(index: Int) -> Animation {
            Curve.smoothOut(duration: Duration.letter).delay(letterArrivalDelay(index: index))
        }

        public static func letterArrivalDelay(index: Int) -> TimeInterval {
            Double(index) * Duration.letterStagger
        }
        /// Subtitle follow-up beat after the letter choreography starts.
        public static let headerFollow = Curve.smoothOut(duration: Duration.arrival)
        public static let resultPresenceAppearance = Curve.smoothOut(duration: ResultPresence.appearanceDuration)
        public static let resultPresenceExit = Curve.productiveExit(duration: ResultPresence.exitDuration)
        public static let diagnostic = Curve.inOut(duration: Duration.quick)
        /// Wave 2 theme crossfade (prototype MOTION d.themeXfade): the whole
        /// SwiftUI colorScheme dissolves through one 320ms envelope; AppKit
        /// chrome (WindowAppearanceOwner) still flips natively.
        public static let themeCrossfade = Curve.inOut(duration: Duration.themeCrossfade)
        /// Output breath: one-shot accent pulse when an explicit run lands
        /// (output pane chrome). Terminal envelope lives in `OutputBreath`.
        /// Container settle: no-overshoot spring for selection pills and reveals.
        public static let settle = Curve.gentleSpring()
        /// Delight: slight-overshoot spring for success/result-arrival moments only.
        public static let delight = Curve.playfulSpring()
        /// Indeterminate hairline progress: continuous back-and-forth sweep for
        /// `IndexProgressHairline`. Loops must not reuse one-shot state-feedback
        /// durations.
        public static let hairlineSweep = Animation.easeInOut(duration: Duration.progressLoop).repeatForever(autoreverses: true)
    }

    /// Wave 2 terminal values for the output success breath (prototype
    /// MOTION d.breath*): delayed single 640ms arc — border-led with a faint
    /// wash, rise on smoothOut / fall on the exit arc. Border/wash opacity
    /// only; no glow, no re-trigger stacking.
    public enum OutputBreath {
        public static let delay = Duration.outputBreathDelay
        public static let rise = Curve.smoothOut(duration: Duration.outputBreathHalfArc)
        public static let fall = Curve.exit(duration: Duration.outputBreathHalfArc)
        /// Border-layer peak opacity over the arc.
        public static let borderPeak: Double = 0.28
        /// Wash fill peak: accent at 1.5% over the pane background.
        public static let washPeak: Double = 0.015
    }

    /// Wave 2 card-lift pane hover (prototype MOTION d.hoverIn/hoverOut):
    /// the pane reads as a card lifting off the surface through neutral
    /// shadow depth (recipes live in `ToolTheme.Shadow.paneHover*`) plus a
    /// border deepen and a faint white background lift. Zero
    /// translate/scale by discipline; this namespace owns timing only.
    public enum PaneHover {
        public static let inCurve = Curve.smoothOut(duration: Duration.hoverIn)
        public static let outCurve = Curve.smoothOut(duration: Duration.hoverOut)
        /// White overlay peak: ≈1% restrained background lift in both themes.
        public static let washPeak: Double = 0.01
    }

    /// Wave 2 error feedback terminal values (prototype MOTION d.errTint*):
    /// state-held warning tint. No-flash rule: the tint is a *state*, not a
    /// pulse — it fades in delayed, holds while the error persists, and fades
    /// out on resolve; border width never changes.
    public enum ErrorFeedback {
        public static let tintDelay = Duration.errorTintDelay
        public static let tintPeak: Double = 0.55
        public static let tintIn = Curve.smoothOut(duration: Duration.errorTintIn)
        public static let tintOut = Curve.smoothOut(duration: Duration.errorTintOut)
    }

    /// Wave 2 empty-state arrival (prototype MOTION d/x.empty*): the icon
    /// rises on a slight-overshoot spring, then the caption and message
    /// follow one beat apart (fade-dominant). Reduce Motion shows directly.
    public enum EmptyArrival {
        public static let iconRise = Animation.spring(response: 0.3, dampingFraction: 0.71)
        public static let textFollow = Curve.smoothOut(duration: 0.3).delay(0.06)
        public static let messageFollow = Curve.smoothOut(duration: 0.3).delay(0.12)
        public static let iconRiseDistance: CGFloat = 6
        public static let textRiseDistance: CGFloat = 4
        /// Single-element variant (editor placeholder swap): no beat delay.
        public static let elementArrival = Curve.smoothOut(duration: 0.3)
    }

    /// Wave 2 command-palette choreography (prototype MOTION d/x/s.cmdk*):
    /// open = ~150ms near-critical spring rise (8pt) + fade; close rides a
    /// ~140ms critically damped spring. Open and close share ONE continuous
    /// rise/sink distance and opacity mapping driven by the single panel
    /// progress (the scrim dims through the same progress at a 0.30 ceiling),
    /// so rapid reversals never hard-switch the presentation geometry
    /// (contract: `CommandPaletteVisibilityGeometry`). Deliberately no scale
    /// channel: scaling the panel would resample its retained native-view
    /// subtree (~45 NSViews) on every interpolated frame. Rows mount visible
    /// with no per-row stagger; the keyboard selection highlight snaps on the
    /// 0.2/1.0 fast spring with no stretch.
    public enum PaletteMotion {
        /// Panel open: quiet ~130ms fade — the palette is the densest
        /// reading surface, so restraint (no movement) is the smooth feel.
        public static let open = Animation.easeOut(duration: 0.13)
        /// Panel close: a slightly faster ~120ms fade.
        public static let close = Animation.easeOut(duration: 0.12)
        /// Fade-only presentation: no positional travel. The mapping keeps
        /// the offset channel at zero so reversal geometry stays trivially
        /// continuous.
        public static let riseDistance: CGFloat = 0
    }

    /// Wave 2 copy-confirmation tick (prototype MOTION d.copyOut / d.copyDraw /
    /// d.copyBox / d.copyBack / d.copyHold + s.copyBoxFrom): the shared copy
    /// button keeps its label and width constant (zero deformation); the copy
    /// glyph fades out while a checkmark stroke-draws in, the icon box settles
    /// 0.94→1 once, dwells 1200ms (matching the pinned copied-state lifecycle), then both glyphs cross-fade back
    /// symmetrically. Reduce Motion collapses to the plain symbol cut.
    public enum CopyTick {
        /// Copy glyph fade-out on enter (d.copyOut).
        public static let out: TimeInterval = 0.12
        /// Checkmark stroke draw (d.copyDraw, prototype --ease).
        public static let draw: TimeInterval = 0.22
        /// Icon-box settle arc, 0.94→1 one-shot (d.copyBox).
        public static let box: TimeInterval = 0.18
        /// Symmetric fade-back after the dwell (d.copyBack).
        public static let back: TimeInterval = 0.12
        /// Dwell before the fade-back (d.copyHold).
        public static let hold: TimeInterval = 1.2
        /// Icon-box settle start scale (s.copyBoxFrom).
        public static let boxFrom: CGFloat = 0.94
        /// Glyph cross-fade in (copyOut on the shared smoothOut family).
        public static let fade = Curve.smoothOut(duration: out)
        /// Glyph cross-fade out after the dwell (copyBack, symmetric).
        public static let fadeBack = Curve.smoothOut(duration: back)
        /// Checkmark draw curve (prototype --ease).
        public static let drawCurve = Curve.smoothOut(duration: draw)
        /// Icon-box settle: the one declared easeSettle curve exception
        /// (0.25, 1.2, 0.45, 1 — ≤2% overshoot), one-shot like the prototype
        /// keyframe; no retargeting surface, so the exact curve is safe here.
        public static let boxSettle = Animation.timingCurve(0.25, 1.2, 0.45, 1.0, duration: box)
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
    public enum SegmentedCursor {
        /// Cursor flight spring — the 0.22 fast variant of the shared
        /// 0.3/0.85 selection-slide family (springFast ≈ 220ms).
        public static let slide = Animation.spring(
            response: 0.22,
            dampingFraction: 0.85,
            blendDuration: 0
        )
        /// Horizontal stretch peak sampled mid-flight (s.segCursorStretch).
        public static let stretchPeak: CGFloat = 1.10
        /// Active-label color/state cross-fade (d.labelXfade, smoothOut).
        public static let labelXfade = Curve.smoothOut(duration: Duration.labelXfade)
    }

    /// Wave 2 difference-block locating wash (prototype MOTION d.diffPulse /
    /// d.diffWashPeak): when a difference jump lands, the target block's
    /// background sweeps one soft accent wash — opacity 0 → 10% → 0 across a
    /// single 360ms arc (rise on smoothOut to a 40% peak, fall on the exit
    /// arc) — while the pane's line-number slot marker deepens on the same
    /// arc (2pt accent → 3pt accentHover → 2pt). One layer, one animated
    /// property, one arc: outline and enclose treatments were explicitly
    /// rejected. Reduce Motion skips the wash entirely; the jump still
    /// scrolls and selects.
    public enum LocatingWash {
        /// Total wash arc, redone to the GitHub line-fade profile: quick
        /// attack then a long readable decay (was 360ms, which read as a
        /// flash slab).
        public static let duration: TimeInterval = 0.9
        /// Peak wash opacity — accent at 6%, restrained (was 10%).
        public static let washPeak: Double = 0.06
        /// Peak position across the arc: ≈120ms attack, ≈780ms decay.
        public static let peakFraction: Double = 0.13
        /// Wash corner radius.
        public static let washCornerRadius: CGFloat = 2

        /// The single-arc opacity keyframe for AppKit-hosted wash surfaces
        /// (control points come from the shared curve tokens; callers pass
        /// their peak, the wash passes `washPeak`).
        public static func opacityKeyframe(peak: Double) -> CAKeyframeAnimation {
            let smooth = Curve.smoothOutControlPoints
            let exit = Curve.exitControlPoints
            let arc = CAKeyframeAnimation(keyPath: "opacity")
            arc.values = [0.0, peak, 0.0]
            arc.keyTimes = [0.0, NSNumber(value: peakFraction), 1.0]
            arc.duration = duration
            arc.timingFunctions = [
                CAMediaTimingFunction(
                    controlPoints: Float(smooth.x1),
                    Float(smooth.y1),
                    Float(smooth.x2),
                    Float(smooth.y2)
                ),
                CAMediaTimingFunction(
                    controlPoints: Float(exit.x1),
                    Float(exit.y1),
                    Float(exit.x2),
                    Float(exit.y2)
                )
            ]
            arc.isRemovedOnCompletion = true
            return arc
        }
    }

    public struct AppKitMotion {
        public let duration: TimeInterval
        public let timingFunction: CAMediaTimingFunction
    }

    public enum AppKitPreset {
        public static var accordion: AppKitMotion {
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

        /// Sliding spring for the sidebar selection chrome. Replicates the
        /// prototype's hand-integrated rail spring exactly (transition-lab
        /// PHYS.spring { s: 170, d: 22 }, mass 1): ωn ≈ 13.0 rad/s, ζ ≈ 0.84 —
        /// slow, soft, and inertial, which is the "settles like liquid" feel
        /// the prototype's rail has. Deliberately NOT the 0.3/0.85
        /// `gentleSpring` family: that one reads snappy here, not silky.
        /// CoreAnimation integrates the spring off the main thread, which beats
        /// the prototype's rAF loop on frame budget; the one trade is that an
        /// interrupted slide restarts from its presentation position with zero
        /// velocity (CASpringAnimation cannot inject the in-flight velocity the
        /// prototype carried over on retarget).
        public static func selectionSlide() -> CASpringAnimation {
            let spring = CASpringAnimation(keyPath: "position.y")
            spring.mass = 1
            spring.stiffness = 170
            spring.damping = 22
            // settlingDuration self-reports short: at that timestamp the spring
            // can still be a few pixels from rest on long jumps, and CASpring
            // hard-cuts to the model value when the animation ends — the
            // "slams to a stop" feel. The +0.12s tail lets the arc settle to
            // sub-pixel residual before the cut, restoring the prototype's
            // liquid landing (its rAF loop ran until |Δ| < 0.05px).
            spring.duration = spring.settlingDuration + 0.12
            return spring
        }
    }

    public enum Transition {
        public static var scrim: AnyTransition {
            .opacity
        }

        /// 01 景深沉降 (PAGE-TRANSITIONS t-1): incoming page fades in while
        /// rising 10pt and settling from 99.5% scale; the outgoing page sinks
        /// to 99.2% while fading. Insertion and removal intentionally ride
        /// different timings (300ms smoothOut in / 220ms productiveExit out),
        /// which one implicit `.animation` cannot split — `ToolPageStage` drives
        /// each direction through its own explicit transaction. Host-owned;
        /// Reduce Motion collapses to identity through the shared transition
        /// helper.
        public static var pageArrival: AnyTransition {
            AnyTransition.asymmetric(
                insertion: .opacity
                    .combined(with: .offset(y: Distance.pageSinkRise))
                    .combined(with: .scale(scale: Scale.pageArrivalSink)),
                removal: .opacity
                    .combined(with: .scale(scale: Scale.pageDepartureSink))
            )
        }

        public static var modal: AnyTransition {
            AnyTransition.opacity
                .combined(with: .scale(scale: Scale.modal))
        }

        public static var toastPanel: AnyTransition {
            AnyTransition.asymmetric(
                insertion: .opacity.combined(with: .offset(y: -Distance.base)),
                removal: .opacity.combined(with: .offset(y: -Distance.small))
            )
        }

        /// Toolbar-anchored dropdown (IndexOptionsMenu): the panel fades in
        /// slightly small and settles down from the trigger edge; removal
        /// reverses the settle. Top-anchored so the panel reads as unfolding
        /// from below its trigger rather than zooming from its center.
        public static var anchoredDropdown: AnyTransition {
            AnyTransition.asymmetric(
                insertion: .opacity
                    .combined(with: .scale(scale: Scale.modal, anchor: .top))
                    .combined(with: .offset(y: -Distance.micro)),
                removal: .opacity
                    .combined(with: .scale(scale: Scale.modal, anchor: .top))
            )
        }

        public static var modeContent: AnyTransition {
            AnyTransition.asymmetric(
                insertion: .opacity.combined(with: .offset(y: Distance.micro)),
                removal: .opacity
            )
        }

        public static var topRowInsertion: AnyTransition {
            AnyTransition.asymmetric(
                insertion: .opacity.combined(with: .offset(y: -Distance.small)),
                removal: .identity
            )
        }

        public static var diagnostic: AnyTransition {
            AnyTransition.asymmetric(
                insertion: .opacity.combined(with: .offset(y: -Distance.small)),
                removal: .opacity
            )
        }

        public static var iconSwap: AnyTransition {
            AnyTransition.asymmetric(
                insertion: .opacity.combined(with: .scale(scale: Scale.iconInserted)),
                removal: .opacity.combined(with: .scale(scale: Scale.iconRemoved))
            )
        }

        public static var textSwap: AnyTransition {
            AnyTransition.opacity
        }

        /// Inline count/status label swap (IndexOptionsMenu): a one-token
        /// leading nudge, no scale. Keeps the trigger label snug.
        public static var labelCountSwap: AnyTransition {
            AnyTransition.opacity.combined(with: .offset(x: -Distance.micro))
        }

        /// Short copy that rises into an empty editor slot
        /// (IndexCodeViewerSurface placeholder).
        public static var emptyArrivalText: AnyTransition {
            AnyTransition.opacity.combined(with: .offset(y: EmptyArrival.textRiseDistance))
        }

        public static func orderedContent(_ direction: OrderedDirection) -> AnyTransition {
            AnyTransition.asymmetric(
                insertion: .opacity.combined(with: .offset(x: direction.insertionOffsetX)),
                removal: .opacity
            )
        }
    }

    public static var systemReduceMotionEnabled: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    public static func animation(_ animation: Animation, reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : animation
    }

    public static func transition(_ transition: AnyTransition, reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .identity : transition
    }

    public static var disabledTransaction: Transaction {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        return transaction
    }
}

@MainActor
public func withToolAnimation(
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
public func applyToolMotion(_ body: () -> Void) {
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

public extension View {
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
