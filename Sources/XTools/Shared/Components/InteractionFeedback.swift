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

    func body(content: Content) -> some View {
        content
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        isHovered ? ToolTheme.strongBorder : .clear,
                        lineWidth: 1
                    )
                    .allowsHitTesting(false)
            }
            .animation(ToolMotion.Preset.controlFeedback, value: isHovered)
            .onHover { isHovered = $0 }
    }
}

/// One-shot breath for output panes: a 1pt accent border fades in
/// and out over half a second when an explicit run lands. Keyed by a caller
/// supplied generation so each run pulses exactly once; Reduce Motion and
/// non-positive generations render nothing.
struct ToolOutputBreathModifier: ViewModifier {
    let generation: Int
    let cornerRadius: CGFloat
    @State private var isBreathing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(ToolTheme.accentBorder, lineWidth: 1)
                    .opacity(isBreathing ? 1 : 0)
                    .allowsHitTesting(false)
                    .animation(
                        ToolMotion.animation(ToolMotion.Preset.outputBreath, reduceMotion: reduceMotion),
                        value: isBreathing
                    )
            }
            .onChange(of: generation) { _ in
                guard generation > 0, !reduceMotion else { return }
                isBreathing = true
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(500))
                    isBreathing = false
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
