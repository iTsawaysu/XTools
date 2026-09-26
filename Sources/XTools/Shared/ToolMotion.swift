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
        /// Container settle: no-overshoot spring for selection pills and reveals.
        static let settle = Curve.gentleSpring()
        /// Delight: slight-overshoot spring for success/result-arrival moments only.
        static let delight = Curve.playfulSpring()
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
}
