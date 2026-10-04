import SwiftUI

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
/// 顶栏 ⌘K 触发按钮。按钮住在原生工具栏（AppKit chrome 层），⌘K 的内容
/// 遮罩盖不住它——面板打开时把按钮自身压暗淡化，视觉上与"被蒙层罩住"
/// 一致。压暗状态由 `CommandTriggerLabel` 自行观察
/// `CommandPalettePresentationModel`（工具栏内容不随面板开关重估，见
/// TitlebarView），本样式只负责把按压态传进 label 并驱动按压动画。
struct CommandTriggerButtonStyle: ButtonStyle {
    var presentation: CommandPalettePresentationModel

    func makeBody(configuration: Configuration) -> some View {
        CommandTriggerLabel(
            presentation: presentation,
            isPressed: configuration.isPressed
        )
        .toolAnimation(ToolMotion.Preset.controlFeedback, value: configuration.isPressed)
    }
}
