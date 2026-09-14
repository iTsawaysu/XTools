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
}
