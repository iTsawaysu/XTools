import SwiftUI

/// Tracks hover state for chrome controls that change appearance on pointer
/// hover. Shared by the titlebar's sidebar toggle and the command palette rows.
@MainActor
final class HoverState: ObservableObject {
    @Published var isHovered = false
}

/// Quiet square button for the sidebar toggle: transparent at rest, filled on
/// hover/press.
struct SidebarChromeButtonStyle: ButtonStyle {
    let isHovered: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isHovered || configuration.isPressed ? ToolTheme.textPrimary : ToolTheme.textSecondary)
            .background(
                backgroundFill(isPressed: configuration.isPressed),
                in: RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.control, style: .continuous)
            )
            .contentShape(RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.control, style: .continuous))
            .toolAnimation(ToolMotion.Preset.controlFeedback, value: [isHovered, configuration.isPressed])
    }

    private func backgroundFill(isPressed: Bool) -> Color {
        if isPressed {
            return ToolTheme.activeFill
        }

        if isHovered {
            return ToolTheme.hoverFill
        }

        return .clear
    }
}

/// Borderless titlebar button (e.g. the favorite toggle): tints on press only.
struct QuietTitlebarButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(configuration.isPressed ? ToolTheme.accent : ToolTheme.textSecondary)
            .background(
                configuration.isPressed ? ToolTheme.activeFill : Color.clear,
                in: RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.control, style: .continuous)
            )
            .contentShape(RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.control, style: .continuous))
            .toolAnimation(ToolMotion.Preset.controlFeedback, value: configuration.isPressed)
    }
}

/// Bordered field-like button for the command-palette trigger in the titlebar.
struct CommandTriggerButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(configuration.isPressed ? ToolTheme.textPrimary : ToolTheme.textSecondary)
            .background(
                configuration.isPressed ? ToolTheme.activeFill : ToolTheme.editorBackground,
                in: RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.field, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.field, style: .continuous)
                    .strokeBorder(ToolTheme.border, lineWidth: 0.5)
            }
            .contentShape(RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.field, style: .continuous))
            .toolAnimation(ToolMotion.Preset.controlFeedback, value: configuration.isPressed)
    }
}
