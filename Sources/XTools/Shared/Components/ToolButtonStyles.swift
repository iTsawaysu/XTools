import SwiftUI

// Shared small-button and icon-action styles used by ToolCopyButton and workbench actions.
// These live in Shared/Components so page-layer controls only depend on shared primitives.

// MARK: - ToolSmallButtonStyle

struct ToolSmallButtonStyle: ButtonStyle {
    var done = false
    /// Framed secondary treatment (prototype v3 workbench actions): the button
    /// rests on `utilityBackground` inside a hairline instead of staying quiet
    /// on the page surface until hover.
    var framed = false

    init(done: Bool = false, framed: Bool = false) {
        self.done = done
        self.framed = framed
    }

    func makeBody(configuration: Configuration) -> some View {
        StyleBody(configuration: configuration, done: done, framed: framed)
    }

    private struct StyleBody: View {
        let configuration: Configuration
        let done: Bool
        let framed: Bool

        @State private var isHovering = false
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        private var hovering: Bool { isHovering && isEnabled }

        private var background: Color {
            if done { return ToolTheme.successSoft }
            if configuration.isPressed { return ToolTheme.activeFill }
            if hovering { return framed ? ToolTheme.activeFill : ToolTheme.hoverFill }
            return framed ? ToolTheme.utilityBackground : Color.clear
        }

        private var border: Color {
            if done { return ToolTheme.successSoft }
            if hovering || configuration.isPressed { return ToolTheme.strongBorder }
            return framed ? ToolTheme.border : Color.clear
        }

        var body: some View {
            configuration.label
                .font(ToolTypography.buttonSmall)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .foregroundStyle(done ? ToolTheme.success : ToolTheme.textSecondary)
                .padding(.horizontal, 9)
                .frame(height: ToolMetrics.ControlHeight.compact28)
                .background(background, in: RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.control, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.control, style: .continuous)
                        .strokeBorder(border, lineWidth: 1)
                }
                .contentShape(RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.control, style: .continuous))
                .opacity(isEnabled ? 1 : 0.5)
                .scaleEffect(!reduceMotion && configuration.isPressed ? ToolMotion.Scale.pressed : 1)
                .onHover { isHovering = $0 }
                .toolAnimation(ToolMotion.Preset.controlFeedback, reduceMotion: reduceMotion, value: hovering)
                .toolAnimation(ToolMotion.Preset.controlFeedback, reduceMotion: reduceMotion, value: configuration.isPressed)
        }
    }
}

struct ToolIconActionButtonStyle: ButtonStyle {
    var isActive = false
    var activeTint: Color = ToolTheme.accent
    var tint: Color = ToolTheme.textSecondary
    var activeBackground: Color = ToolTheme.selectionFill

    func makeBody(configuration: Configuration) -> some View {
        StyleBody(
            configuration: configuration,
            isActive: isActive,
            activeTint: activeTint,
            tint: tint,
            activeBackground: activeBackground
        )
    }

    private struct StyleBody: View {
        let configuration: Configuration
        let isActive: Bool
        let activeTint: Color
        let tint: Color
        let activeBackground: Color

        @State private var isHovering = false
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        private var hovering: Bool { isHovering && isEnabled }

        private var foreground: Color {
            if isActive { return activeTint }
            return isEnabled ? tint : ToolTheme.textTertiary
        }

        private var background: Color {
            if configuration.isPressed && isEnabled { return ToolTheme.activeFill }
            if hovering { return ToolTheme.hoverFill }
            if isActive { return activeBackground }
            return Color.clear
        }

        var body: some View {
            configuration.label
                .font(ToolTypography.buttonSmall)
                .foregroundStyle(foreground)
                .frame(width: ToolMetrics.ControlHeight.compact, height: ToolMetrics.ControlHeight.compact)
                .background(background, in: RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.control, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.control, style: .continuous))
                .opacity(isEnabled ? 1 : 0.4)
                .scaleEffect(!reduceMotion && configuration.isPressed ? ToolMotion.Scale.pressed : 1)
                .onHover { isHovering = $0 }
                .toolAnimation(
                    ToolMotion.Preset.controlFeedback,
                    reduceMotion: reduceMotion,
                    value: [hovering, configuration.isPressed, isActive]
                )
                .transaction { transaction in
                    if reduceMotion { transaction.disablesAnimations = true }
                }
        }
    }
}


/// Compact snippet capsule used by input-assist rows. Hairline at rest,
/// hover fill, no accent emphasis.
struct ToolSnippetButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        SnippetStyleBody(configuration: configuration)
    }

    private struct SnippetStyleBody: View {
        let configuration: ButtonStyle.Configuration
        @State private var isHovering = false
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            configuration.label
                .background(
                    configuration.isPressed
                        ? ToolTheme.activeFill
                        : (isHovering ? ToolTheme.hoverFill : Color.clear),
                    in: RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.nestedControl, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.nestedControl, style: .continuous)
                        .strokeBorder(ToolTheme.border, lineWidth: 0.5)
                }
                .contentShape(RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.nestedControl, style: .continuous))
                .onHover { isHovering = $0 }
                .toolAnimation(ToolMotion.Preset.controlFeedback, reduceMotion: reduceMotion, value: isHovering)
                .toolAnimation(ToolMotion.Preset.controlFeedback, reduceMotion: reduceMotion, value: configuration.isPressed)
        }
    }
}


@available(*, deprecated, renamed: "ToolSmallButtonStyle")
typealias IndexSmallButtonStyle = ToolSmallButtonStyle

@available(*, deprecated, renamed: "ToolIconActionButtonStyle")
typealias IndexIconActionButtonStyle = ToolIconActionButtonStyle
