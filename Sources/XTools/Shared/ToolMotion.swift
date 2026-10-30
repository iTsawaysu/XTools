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
        /// v9 canonical vocabulary. `instant` means an explicit no-animation
        /// transaction, not a zero-length curve.
        static let instant: TimeInterval = 0
        static let micro: TimeInterval = 0.100
        static let quick: TimeInterval = 0.140
        static let base: TimeInterval = 0.200
        static let enter: TimeInterval = 0.260
        static let exit: TimeInterval = 0.160
        static let loop: TimeInterval = 1.200
        static let arrival: TimeInterval = enter
        static let fast: TimeInterval = base
        static let medium: TimeInterval = base
        /// 01 景深沉降 (PAGE-TRANSITIONS t-1): incoming page settles over
        /// 300ms on smoothOut.
        static let pageSinkEnter: TimeInterval = enter
        /// Outgoing page leaves on the v9 exit beat.
        static let pageSinkExit: TimeInterval = exit
        /// Indeterminate hairline sweep: one back-and-forth traversal of the
        /// rail. Loops sit outside the one-shot feedback envelope because the
        /// steady rhythm itself is the liveness cue — a shorter sweep reads
        /// as flicker. (Dropped by the logic-branch merge; restored.)
        static let progressLoop: TimeInterval = loop
        /// Wave 2 output breath: the arc starts 80ms after the run so the
        /// text swap lands first (prototype MOTION d.breathDelay).
        static let outputBreathDelay: TimeInterval = 0.08
        /// Half-arc of the single 640ms breath envelope (320 up + 320 down).
        static let outputBreathHalfArc: TimeInterval = base
        /// Wave 2 card-lift pane hover: enter 180ms, leave 240ms (prototype
        /// MOTION d.hoverIn / d.hoverOut).
        static let hoverIn: TimeInterval = quick
        static let hoverOut: TimeInterval = base
        /// Warning tint fade-in / fade-out.
        static let errorTintIn: TimeInterval = base
        static let errorTintOut: TimeInterval = micro
        static let errorTintDelay: TimeInterval = 0.08
        /// Wave 2 theme crossfade: 320ms single envelope (prototype d.themeXfade).
        static let themeCrossfade: TimeInterval = base
        /// Wave 2 segmented-control active-label cross-fade (prototype
        /// MOTION d.labelXfade).
        static let labelXfade: TimeInterval = quick
    }

    enum Distance {
        /// Hero readout hand-off clears the glyph height: at display sizes a
        /// 3pt shift still lets old/new strings sit on top of each other.
        static let valueSwapRise: CGFloat = 8
        static let micro: CGFloat = 3
        static let small: CGFloat = 6
        static let base: CGFloat = 8
        static let medium: CGFloat = 12
        static let large: CGFloat = 18
        /// Page-header arrival rise: one whole-header fade/4pt move.
        static let headerRise: CGFloat = 4
        /// 01 景深沉降: incoming page rises 10pt while settling (prototype
        /// translateY(10px)).
        static let pageSinkRise: CGFloat = 10
        /// v9 page arrival: one whole-page fade with a 4pt rise; no scale.
        static let pageRise: CGFloat = 4
    }

    enum Scale {
        static let modal: CGFloat = 0.98
        static let pressed: CGFloat = 0.98
        static let iconInserted: CGFloat = 0.98
        static let iconRemoved: CGFloat = 1.02
        /// Page-arrival depth: incoming tool pages settle from 99.5% scale.
        static let pageArrivalSink: CGFloat = 0.995
        /// 01 景深沉降: outgoing pages sink to 99.2% while fading — depth on
        /// the exit without a readable zoom.
        static let pageDepartureSink: CGFloat = 0.992
        /// Image-result reveal: incoming frames settle from 98.5% — a barely
        /// readable depth cue, not a zoom.
        static let imageReveal: CGFloat = 0.99
    }

    enum ResultPresence {
        static let appearanceDuration = Duration.base
        static let exitDuration = Duration.exit
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
        /// v9 exit curve: content leaves quickly and accelerates away.
        static let exitControlPoints = (
            x1: 0.4,
            y1: 0.0,
            x2: 1.0,
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

        /// v9 standard curve: the only state/color/position/reorder curve.
        static let standardControlPoints = (
            x1: 0.2,
            y1: 0.0,
            x2: 0.0,
            y2: 1.0
        )

        static func standard(duration: TimeInterval) -> Animation {
            .timingCurve(
                standardControlPoints.x1,
                standardControlPoints.y1,
                standardControlPoints.x2,
                standardControlPoints.y2,
                duration: duration
            )
        }

        /// v9 enter curve: arrivals only.
        static let enterControlPoints = (
            x1: 0.16,
            y1: 1.0,
            x2: 0.3,
            y2: 1.0
        )

        static func enter(duration: TimeInterval) -> Animation {
            .timingCurve(
                enterControlPoints.x1,
                enterControlPoints.y1,
                enterControlPoints.x2,
                enterControlPoints.y2,
                duration: duration
            )
        }

        /// v9 selection spring: container-level, no visible overshoot.
        static func selection() -> Animation {
            .spring(response: 0.26, dampingFraction: 0.90, blendDuration: 0)
        }

        /// v9 delight spring: single success glyph only.
        static func delight() -> Animation {
            .spring(response: 0.34, dampingFraction: 0.72, blendDuration: 0)
        }

    }

    enum Preset {
        /// v9 component-state presets. Existing pages keep the legacy
        /// `controlFeedback` until their page family migrates in P4.
        static let hoverIn = Curve.standard(duration: Duration.quick)
        static let hoverOut = Curve.standard(duration: Duration.base)
        static let press = Curve.standard(duration: Duration.micro)
        static let pageEnter = Curve.enter(duration: Duration.enter)
        static let pageExit = Curve.exit(duration: Duration.exit)
        static let toastEnter = Curve.enter(duration: Duration.base)
        static let toastExit = Curve.exit(duration: Duration.exit)
        /// Reduce Motion keeps a 100ms opacity/color fade where the state must
        /// remain legible; movement/scale callers still use the hard-cut gate.
        static let reducedMotionFade = Curve.standard(duration: Duration.micro)
        static let controlFeedback = Curve.standard(duration: Duration.micro)
        static let textSwap = Curve.standard(duration: Duration.quick)
        /// Prominent readout and structural content hand-off: the outgoing
        /// layer leaves on the fast beat, the incoming layer rises after a
        /// short beat. Staggering keeps differently sized content from
        /// blanking the pane (flicker) or blending into a jumble.
        static let valueSwapExit = Curve.standard(duration: Duration.micro)
        static let valueSwapEnter = Curve.enter(duration: Duration.quick).delay(0.06)
        static let iconSwap = Curve.standard(duration: Duration.quick)
        static let orderedContent = Curve.standard(duration: Duration.base)
        /// Atomic structural swap settle (Hub segments, output presentation,
        /// image state surfaces): the new branch mounts immediately; only a
        /// 94%→100% opacity settle remains so dense toolbars never blank,
        /// ghost, or mix old/new labels.
        static let contentSettle = Curve.standard(duration: Duration.micro)
        static let tabs = Curve.standard(duration: Duration.base)
        static let accordion = Curve.standard(duration: Duration.base)
        static let shellResize = Curve.standard(duration: Duration.base)
        static let modal = Curve.enter(duration: Duration.enter)
        static let panelReveal = Curve.enter(duration: Duration.base)
        /// Image-result reveal: same 350ms smoothOut beat as the panel reveal,
        /// so a new grayscale/compressed/watermarked frame settles instead of
        /// snapping. The transition owns the fade/scale shape.
        static let imageReveal = Curve.enter(duration: Duration.base)
        /// v3: tool-switch page arrival (host-owned whitelist; see
        /// `MotionSourceContractTests`). 01 景深沉降: 300ms smoothOut — the
        /// incoming page sinks from y+10/99.5% while the outgoing layer runs
        /// its own 220ms productiveExit (`pageDeparture`). Timing is driven by
        /// `ToolPageStage`'s two explicit transactions, one per direction.
        static let pageArrival = Curve.enter(duration: Duration.pageSinkEnter)
        /// 01 景深沉降: outgoing page exit timing — 220ms productiveExit so
        /// leaving content accelerates away while the arrival still settles.
        static let pageDeparture = Curve.exit(duration: Duration.pageSinkExit)
        /// Page-header arrival: one whole-header fade + 4pt rise on the shared
        /// 240ms smoothOut arc. Consumed by `IndexPageHeader` only; no
        /// per-character stagger.
        static let pageHeader = Curve.enter(duration: Duration.enter)
        static let resultPresenceAppearance = Curve.enter(duration: ResultPresence.appearanceDuration)
        static let resultPresenceExit = Curve.exit(duration: ResultPresence.exitDuration)
        static let diagnostic = Curve.standard(duration: Duration.quick)
        /// Wave 2 theme crossfade (prototype MOTION d.themeXfade): the whole
        /// SwiftUI colorScheme dissolves through one 320ms envelope; AppKit
        /// chrome (WindowAppearanceOwner) still flips natively.
        static let themeCrossfade = Curve.standard(duration: Duration.themeCrossfade)
        /// Output breath: one-shot accent pulse when an explicit run lands
        /// (output pane chrome). Terminal envelope lives in `OutputBreath`.
        /// Container settle: no-overshoot spring for selection pills and reveals.
        static let settle = Curve.selection()
        /// Delight: slight-overshoot spring for success/result-arrival and the
        /// favorite star only.
        static let delight = Curve.delight()
        /// Indeterminate hairline progress: continuous back-and-forth sweep for
        /// `IndexProgressHairline`. Loops must not reuse one-shot state-feedback
        /// durations.
        static let hairlineSweep = Animation.easeInOut(duration: Duration.progressLoop).repeatForever(autoreverses: true)
    }

    /// Wave 2 terminal values for the output success breath (prototype
    /// MOTION d.breath*): delayed single 640ms arc — border-led with a faint
    /// wash, rise on smoothOut / fall on the exit arc. Border/wash opacity
    /// only; no glow, no re-trigger stacking.
    enum OutputBreath {
        static let delay = Duration.outputBreathDelay
        static let rise = Curve.standard(duration: Duration.outputBreathHalfArc)
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
        static let inCurve = Curve.standard(duration: Duration.hoverIn)
        static let outCurve = Curve.standard(duration: Duration.hoverOut)
        /// White overlay peak: ≈1% restrained background lift in both themes.
        static let washPeak: Double = 0.01
    }

    /// Wave 2 error feedback terminal values (prototype MOTION d.errTint*):
    /// state-held warning tint. No-flash rule: the tint is a *state*, not a
    /// pulse — it fades in delayed, holds while the error persists, and fades
    /// out on resolve; border width never changes.
    enum ErrorFeedback {
        static let tintDelay = Duration.errorTintDelay
        static let tintPeak: Double = 0.55
        static let tintIn = Curve.standard(duration: Duration.errorTintIn)
        static let tintOut = Curve.standard(duration: Duration.errorTintOut)
    }

    /// Empty-state arrival (P3 single beat): the whole group fades in with one
    /// 4pt rise; icon, title, and message never stage separately. Reduce
    /// Motion shows the final layout directly.
    enum EmptyArrival {
        static let arrive = Curve.enter(duration: Duration.enter)
        static let riseDistance: CGFloat = 4
        /// Single-element variant (editor placeholder swap): same timeline,
        /// no beat delay.
        static let elementArrival = arrive
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
    enum PaletteMotion {
        /// Panel open: quiet ~130ms fade — the palette is the densest
        /// reading surface, so restraint (no movement) is the smooth feel.
        static let open = Curve.standard(duration: Duration.quick)
        /// Panel close: a slightly faster ~120ms fade.
        static let close = Curve.standard(duration: Duration.exit)
        /// Fade-only presentation: no positional travel. The mapping keeps
        /// the offset channel at zero so reversal geometry stays trivially
        /// continuous.
        static let riseDistance: CGFloat = 0
    }

    /// Wave 2 copy-confirmation tick (prototype MOTION d.copyOut / d.copyDraw /
    /// d.copyBox / d.copyBack / d.copyHold + s.copyBoxFrom): the shared copy
    /// button keeps its label and width constant (zero deformation); the copy
    /// glyph fades out while a checkmark stroke-draws in, the icon box settles
    /// 0.94→1 once, dwells 1200ms (matching the pinned copied-state lifecycle), then both glyphs cross-fade back
    /// symmetrically. Reduce Motion collapses to the plain symbol cut.
    enum CopyTick {
        /// v9: copy glyph cross-fade and check draw share the base beat; the
        /// old 0.94 box bounce is removed (zero deformation on the icon box).
        static let out: TimeInterval = 0.200
        /// Checkmark stroke draw, same base beat as the glyph exchange.
        static let draw: TimeInterval = 0.200
        /// Fade-back after the dwell.
        static let back: TimeInterval = 0.140
        /// Dwell before the fade-back.
        static let hold: TimeInterval = 1.2
        /// Glyph cross-fade in.
        static let fade = Curve.standard(duration: out)
        /// Glyph cross-fade out after the dwell.
        static let fadeBack = Curve.standard(duration: back)
        /// Checkmark draw curve.
        static let drawCurve = Curve.standard(duration: draw)
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
        static let slide = Curve.standard(duration: Duration.base)
        /// Horizontal stretch peak sampled mid-flight (s.segCursorStretch).
        static let stretchPeak: CGFloat = 1.10
        /// Active-label color/state cross-fade (d.labelXfade, smoothOut).
        static let labelXfade = Curve.standard(duration: Duration.labelXfade)
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
    enum LocatingWash {
        /// Total wash arc, redone to the GitHub line-fade profile: quick
        /// attack then a long readable decay (was 360ms, which read as a
        /// flash slab).
        static let duration: TimeInterval = 0.9
        /// Peak wash opacity — accent at 6%, restrained (was 10%).
        static let washPeak: Double = 0.06
        /// Peak position across the arc: ≈120ms attack, ≈780ms decay.
        static let peakFraction: Double = 0.13
        /// Wash corner radius.
        static let washCornerRadius: CGFloat = 2

        /// The single-arc opacity keyframe for AppKit-hosted wash surfaces
        /// (control points come from the shared curve tokens; callers pass
        /// their peak, the wash passes `washPeak`).
        static func opacityKeyframe(peak: Double) -> CAKeyframeAnimation {
            let smooth = Curve.standardControlPoints
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

    struct AppKitMotion {
        let duration: TimeInterval
        let timingFunction: CAMediaTimingFunction
    }

    enum AppKitPreset {
        static var accordion: AppKitMotion {
            let points = Curve.standardControlPoints
            return AppKitMotion(
                duration: Duration.base,
                timingFunction: CAMediaTimingFunction(
                    controlPoints: Float(points.x1),
                    Float(points.y1),
                    Float(points.x2),
                    Float(points.y2)
                )
            )
        }

        /// Favorite reorder: 320ms shared arc for adjacent favorite moves.
        /// CASpringAnimation cannot drive NSView frame animations through an
        /// NSAnimationContext, so the row and the selection chrome share this
        /// damping-0.90-like curve instead of two competing timelines.
        static var favoriteReorder: AppKitMotion {
            let points = Curve.standardControlPoints
            return AppKitMotion(
                duration: Duration.base,
                timingFunction: CAMediaTimingFunction(
                    controlPoints: Float(points.x1),
                    Float(points.y1),
                    Float(points.x2),
                    Float(points.y2)
                )
            )
        }

        /// Reduce Motion structural favorite change: alpha-only, never a
        /// frame animation. 130ms stays inside the 120–150ms contract.
        static var favoriteReducedMotion: AppKitMotion {
            let points = Curve.standardControlPoints
            return AppKitMotion(
                duration: Duration.micro,
                timingFunction: CAMediaTimingFunction(
                    controlPoints: Float(points.x1),
                    Float(points.y1),
                    Float(points.x2),
                    Float(points.y2)
                )
            )
        }

        /// Cross-section favorite toggle: short fade/reflow, never a flight
        /// across groups.
        static var favoriteToggle: AppKitMotion {
            let points = Curve.standardControlPoints
            return AppKitMotion(
                duration: Duration.base,
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
        static func selectionSlide() -> CASpringAnimation {
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

    enum Transition {
        static var scrim: AnyTransition {
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
        static var pageArrival: AnyTransition {
            AnyTransition.asymmetric(
                insertion: .opacity
                    .combined(with: .offset(y: Distance.pageRise)),
                removal: .opacity
            )
        }

        static var modal: AnyTransition {
            AnyTransition.opacity
                .combined(with: .scale(scale: Scale.modal))
        }

        static var toastPanel: AnyTransition {
            AnyTransition.asymmetric(
                insertion: .opacity.combined(with: .offset(y: Distance.base)),
                removal: .opacity.combined(with: .offset(y: Distance.small))
            )
        }

        /// Toolbar-anchored dropdown (IndexOptionsMenu): the panel fades in
        /// slightly small and settles down from the trigger edge; removal
        /// reverses the settle. Top-anchored so the panel reads as unfolding
        /// from below its trigger rather than zooming from its center.
        static var anchoredDropdown: AnyTransition {
            AnyTransition.asymmetric(
                insertion: .opacity
                    .combined(with: .scale(scale: Scale.modal, anchor: .top))
                    .combined(with: .offset(y: -Distance.micro)),
                removal: .opacity
                    .combined(with: .scale(scale: Scale.modal, anchor: .top))
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

        /// Shared image-result reveal: the incoming frame fades in from a
        /// barely readable scale while the outgoing frame fades out. Used by
        /// the image preview stage and comparison panes so grayscale,
        /// compression, conversion, watermark and favicon results all swap on
        /// the same beat.
        static var imageReveal: AnyTransition {
            AnyTransition.asymmetric(
                insertion: .opacity.combined(with: .scale(scale: Scale.imageReveal, anchor: .center)),
                removal: .opacity
            )
        }

        /// Floating processing chip: small fade + scale, never a hard pop.
        static var statusChip: AnyTransition {
            AnyTransition.opacity.combined(with: .scale(scale: 0.96, anchor: .center))
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
    reduceMotion: Bool,
    _ body: () -> Void
) {
    if reduceMotion {
        body()
    } else {
        withAnimation(animation, body)
    }
}

/// Compatibility wrapper for non-View feedback owners such as the toast center.
@MainActor
func applyToolMotion(_ body: () -> Void) {
    withToolAnimation(
        ToolMotion.Preset.panelReveal,
        reduceMotion: ToolMotion.systemReduceMotionEnabled,
        body
    )
}

private struct ToolMotionOptionalAnimationModifier<Value: Equatable>: ViewModifier {
    let animation: Animation?
    let reduceMotion: Bool
    let value: Value

    func body(content: Content) -> some View {
        let resolved: Animation? = {
            guard reduceMotion else { return animation }
            return animation == nil ? nil : ToolMotion.Preset.reducedMotionFade
        }()
        return content.animation(resolved, value: value)
    }
}

private struct ToolMotionExplicitReduceMotionModifier<Value: Equatable>: ViewModifier {
    let animation: Animation
    let reduceMotion: Bool
    let value: Value

    func body(content: Content) -> some View {
        content.animation(
            reduceMotion ? ToolMotion.Preset.reducedMotionFade : animation,
            value: value
        )
    }
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
/// `numericText`). Reduce Motion renders the final value directly.
private struct ToolNumericTransitionModifier<Value: Equatable>: ViewModifier {
    let value: Value

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .contentTransition(.numericText())
            .toolAnimation(ToolMotion.Preset.textSwap, reduceMotion: reduceMotion, value: value)
    }
}

extension View {
    func toolAnimation<Value: Equatable>(
        _ animation: Animation,
        value: Value
    ) -> some View {
        modifier(ToolMotionAnimationModifier(animation: animation, value: value))
    }

    /// Optional-animation variant for call sites whose animation depends on a
    /// transient condition (e.g. segmented cursor settle). The Reduce Motion
    /// fade still applies when an animation is present.
    func toolAnimation<Value: Equatable>(
        _ animation: Animation?,
        reduceMotion: Bool,
        value: Value
    ) -> some View {
        modifier(
            ToolMotionOptionalAnimationModifier(
                animation: animation,
                reduceMotion: reduceMotion,
                value: value
            )
        )
    }

    /// Explicit Reduce Motion fade for state feedback that must stay readable.
    /// Movement/scale callers keep the hard-cut `toolAnimation(_:value:)`.
    func toolAnimation<Value: Equatable>(
        _ animation: Animation,
        reduceMotion: Bool,
        value: Value
    ) -> some View {
        modifier(
            ToolMotionExplicitReduceMotionModifier(
                animation: animation,
                reduceMotion: reduceMotion,
                value: value
            )
        )
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
    /// Favorite star: the single permitted delight spring. Only the glyph
    /// swaps; the row/group reorder stays on its AppKit timeline.
    func toolMotionFavoriteSwap<ID: Hashable>(id: ID) -> some View {
        modifier(
            ToolMotionIdentityTransitionModifier(
                id: id,
                transition: ToolMotion.Transition.iconSwap,
                animation: ToolMotion.Preset.delight
            )
        )
    }

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
