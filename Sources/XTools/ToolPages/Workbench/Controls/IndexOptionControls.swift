import AppKit
import SwiftUI

// MARK: - IndexSwitch

/// Shared native-toggle wrapper: the Toggle role, state announcement, and
/// fixed-size wrapping both switch names route through.
private struct IndexToggleSurface<Style: ToggleStyle>: View {
    let title: String
    @Binding var isOn: Bool
    let style: Style

    var body: some View {
        Toggle(isOn: $isOn) {
            Text(title)
        }
        .toggleStyle(style)
        .accessibilityValue(isOn ? "已开启" : "已关闭")
        .fixedSize(horizontal: true, vertical: false)
    }
}

private struct IndexSwitchTrack: View {
    let isOn: Bool
    let offBackground: Color
    let offBorder: Color
    let offThumb: Color

    var body: some View {
        ZStack(alignment: isOn ? .trailing : .leading) {
            Capsule(style: .continuous)
                .fill(isOn ? ToolTheme.accentSoft : offBackground)
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(isOn ? ToolTheme.accentBorder : offBorder, lineWidth: 1)
                }

            Circle()
                .fill(isOn ? ToolTheme.accent : offThumb)
                .frame(width: 14, height: 14)
                .padding(3)
        }
        .frame(width: 34, height: 20)
        .toolAnimation(ToolMotion.Preset.controlFeedback, value: isOn)
        .accessibilityHidden(true)
    }
}

// MARK: - IndexOptionGroup

struct IndexOptionLabel: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(ToolTypography.bodyPlain)
            .foregroundStyle(ToolTheme.textSecondary)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
    }
}

struct IndexOptionGroup<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        HStack(spacing: 10) {
            content
        }
        .fixedSize(horizontal: true, vertical: false)
        .padding(.horizontal, 8)
        .frame(height: 36)
        .background(ToolTheme.utilityBackground, in: RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.field, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.field, style: .continuous)
                .strokeBorder(ToolTheme.strongBorder, lineWidth: 1)
        }
        .fixedSize(horizontal: true, vertical: false)
    }
}

struct IndexOptionDivider: View {
    var body: some View {
        Rectangle()
            .fill(ToolTheme.strongBorder)
            .frame(width: 0.5, height: 20)
    }
}

struct IndexOptionSwitch: View {
    enum Style: Sendable, Equatable {
        /// The standalone spine switch look (former IndexSwitch): plain
        /// button, editor-background track, secondary label.
        case standalone
        case switchToggle
        case embeddedSwitch
        case button
    }

    let title: String
    var style: Style = .switchToggle
    @Binding var isOn: Bool

    init(title: String, style: Style = .switchToggle, isOn: Binding<Bool>) {
        self.title = title
        self.style = style
        self._isOn = isOn
    }

    var body: some View {
        IndexToggleSurface(title: title, isOn: $isOn, style: IndexOptionSwitchToggleStyle(style: style))
    }
}

private struct IndexOptionSwitchToggleStyle: ToggleStyle {
    var style: IndexOptionSwitch.Style = .switchToggle

    func makeBody(configuration: Configuration) -> some View {
        Group {
            if style == .standalone {
                toggleLabel(configuration)
                    .buttonStyle(.plain)
            } else {
                toggleLabel(configuration)
                    .buttonStyle(IndexOptionPressableButtonStyle())
            }
        }
    }

    @ViewBuilder
    private func toggleLabel(_ configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            switch style {
            case .standalone:
                HStack(spacing: 9) {
                    IndexSwitchTrack(
                        isOn: configuration.isOn,
                        offBackground: ToolTheme.editorBackground,
                        offBorder: ToolTheme.border,
                        offThumb: ToolTheme.textSecondary
                    )

                    configuration.label
                        .font(ToolTypography.bodyPlain)
                        .foregroundStyle(ToolTheme.textSecondary)
                }
                .contentShape(Rectangle())

            case .switchToggle:
                HStack(spacing: 6) {
                    IndexSwitchTrack(
                        isOn: configuration.isOn,
                        offBackground: ToolTheme.panelBackground,
                        offBorder: ToolTheme.strongBorder,
                        offThumb: ToolTheme.textSecondary
                    )

                    configuration.label
                        .font(ToolTypography.bodyMedium)
                        .foregroundStyle(ToolTheme.textPrimary)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
                .padding(.horizontal, 4)
                .frame(height: 28)
                .background(
                    configuration.isOn ? ToolTheme.selectionFill : Color.clear,
                    in: RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.control, style: .continuous)
                )
                .contentShape(RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.control, style: .continuous))

            case .embeddedSwitch:
                IndexEmbeddedSwitchLabel(configuration: configuration)

            case .button:
                IndexOptionButtonLabel(configuration: configuration)
            }
        }
    }
}

/// Press feedback for option toggles: the same 0.98 settle the button and
/// icon families use, so every pressable control in the spine shares one
/// physical vocabulary (Reduce Motion collapses to identity).
private struct IndexOptionPressableButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? ToolMotion.Scale.pressed : 1)
            .animation(
                ToolMotion.animation(ToolMotion.Preset.controlFeedback, reduceMotion: reduceMotion),
                value: configuration.isPressed
            )
    }
}

private struct IndexEmbeddedSwitchLabel: View {
    let configuration: ToggleStyle.Configuration
    @State private var isHovering = false
    @Environment(\.isEnabled) private var isEnabled

    private let thumbSize: CGFloat = 20
    private let trackPadding: CGFloat = 3
    private let textSpacing: CGFloat = 6
    private let textOuterPadding: CGFloat = 9

    private var isOn: Bool { configuration.isOn }
    private var hovering: Bool { isHovering && isEnabled }

    private var trackBackground: Color {
        if !isEnabled { return ToolTheme.editorBackground }
        if isOn {
            return hovering ? ToolTheme.accentHover : ToolTheme.accent
        }
        return hovering ? ToolTheme.hoverFill : ToolTheme.utilityBackground
    }

    private var trackBorder: Color {
        if !isEnabled { return ToolTheme.border }
        if isOn {
            return hovering ? ToolTheme.accentHover : ToolTheme.accent
        }
        return hovering ? ToolTheme.strongBorder : ToolTheme.strongBorder.opacity(0.85)
    }

    private var textForeground: Color {
        if !isEnabled { return ToolTheme.textTertiary }
        if isOn { return ToolTheme.onAccent }
        return hovering ? ToolTheme.textPrimary : ToolTheme.textSecondary
    }

    var body: some View {
        ZStack(alignment: isOn ? .trailing : .leading) {
            configuration.label
                .font(ToolTypography.label)
                .foregroundStyle(textForeground)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.leading, isOn ? textOuterPadding : (trackPadding + thumbSize + textSpacing))
                .padding(.trailing, isOn ? (trackPadding + thumbSize + textSpacing) : textOuterPadding)

            Circle()
                .fill(isOn ? ToolTheme.onAccent : ToolTheme.textSecondary)
                .frame(width: thumbSize, height: thumbSize)
                .toolShadow(ToolTheme.Shadow.panel)
                .overlay {
                    Circle()
                        .strokeBorder(ToolTheme.border, lineWidth: 0.5)
                }
                .padding(.horizontal, trackPadding)
        }
        .frame(height: 26)
        .background(
            trackBackground,
            in: Capsule(style: .continuous)
        )
        .overlay {
            Capsule(style: .continuous)
                .strokeBorder(trackBorder, lineWidth: 1)
        }
        .contentShape(Capsule(style: .continuous))
        .onHover { isHovering = $0 }
        .toolAnimation(ToolMotion.Preset.controlFeedback, value: isOn)
        .toolAnimation(ToolMotion.Preset.controlFeedback, value: hovering)
    }
}

private struct IndexOptionButtonLabel: View {
    let configuration: ToggleStyle.Configuration
    @State private var isHovering = false
    @Environment(\.isEnabled) private var isEnabled

    private var isOn: Bool { configuration.isOn }
    private var hovering: Bool { isHovering && isEnabled }

    private var background: Color {
        if isOn {
            return hovering ? ToolTheme.accentSoft.opacity(0.85) : ToolTheme.accentSoft
        }
        return hovering ? ToolTheme.hoverFill : ToolTheme.editorBackground
    }

    private var border: Color {
        if isOn {
            return ToolTheme.accentBorder
        }
        return hovering ? ToolTheme.strongBorder : ToolTheme.border
    }

    private var foreground: Color {
        if !isEnabled { return ToolTheme.textTertiary }
        if isOn { return ToolTheme.accent }
        return hovering ? ToolTheme.textPrimary : ToolTheme.textSecondary
    }

    var body: some View {
        configuration.label
            .font(ToolTypography.label)
            .foregroundStyle(foreground)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 8)
            .frame(height: 26)
            .background(
                background,
                in: RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.field, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.field, style: .continuous)
                    .strokeBorder(border, lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.field, style: .continuous))
            .onHover { isHovering = $0 }
            .toolAnimation(ToolMotion.Preset.controlFeedback, value: [hovering, isOn])
    }
}

struct IndexOptionMenu: View {
    let items: [(String, String)]
    @Binding var selection: String
    var title = "选项"
    var tone: ToolFeedbackTone? = nil

    private var selectedLabel: String {
        items.first { $0.0 == selection }?.1 ?? title
    }

    var body: some View {
        Picker(title, selection: $selection) {
            ForEach(items, id: \.0) { item in
                Text(item.1)
                    .tag(item.0)
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .font(ToolTypography.controlLabel(weight: .semibold))
        .buttonStyle(.plain)
        .tint(tone?.tint ?? ToolTheme.accentHover)
        .padding(.leading, 7)
        .padding(.trailing, 24)
        .frame(minWidth: 116)
        .frame(height: 38)
        .background(ToolTheme.editorBackground, in: RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.field, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.field, style: .continuous)
                .strokeBorder(tone?.tint.opacity(0.7) ?? ToolTheme.border, lineWidth: 1)
        }
        .overlay(alignment: .trailing) {
            Image(systemName: "chevron.down")
                .font(.system(size: ToolMetrics.IconSize.micro, weight: .semibold))
                .foregroundStyle(ToolTheme.textSecondary)
                .padding(.trailing, 9)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .contentShape(RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.field, style: .continuous))
        .accessibilityLabel("\(title)：\(selectedLabel)")
        .fixedSize(horizontal: true, vertical: false)
    }
}

