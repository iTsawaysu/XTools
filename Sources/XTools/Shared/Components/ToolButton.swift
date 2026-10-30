import SwiftUI

/// v9 shared button. Pages declare role, size, width and state; the style owns
/// color, hover, press, focus, disabled and busy behavior.
struct ToolButton: View {
    enum Role: Equatable {
        case primary
        case secondary
        case quiet
        case icon
        case chip
    }

    enum Size: Equatable {
        case icon24
        case compact28
        case cta32
        case field38
        case bar44

        var height: CGFloat {
            switch self {
            case .icon24: return ToolMetrics.ControlHeight.icon24
            case .compact28: return ToolMetrics.ControlHeight.compact28
            case .cta32: return ToolMetrics.ControlHeight.cta32
            case .field38: return ToolMetrics.ControlHeight.field38
            case .bar44: return ToolMetrics.ControlHeight.bar44
            }
        }
    }

    enum Width: Equatable {
        case hug
        case fill
    }

    enum State: Equatable {
        case idle
        case active
        case done
        case busy
    }

    let title: String?
    let systemImage: String?
    let role: Role
    let size: Size
    let width: Width
    let state: State
    let isEnabled: Bool
    let help: String?
    let keycap: String?
    let accessibilityLabel: String?
    let action: () -> Void

    @FocusState private var isFocused: Bool

    init(
        _ title: String? = nil,
        systemImage: String? = nil,
        role: Role,
        size: Size? = nil,
        width: Width = .hug,
        state: State = .idle,
        isEnabled: Bool = true,
        help: String? = nil,
        keycap: String? = nil,
        accessibilityLabel: String? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.role = role
        self.size = size ?? role.defaultSize
        self.width = width
        self.state = state
        self.isEnabled = isEnabled
        self.help = help
        self.keycap = keycap
        self.accessibilityLabel = accessibilityLabel
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            label
        }
        .buttonStyle(ToolButtonStyle(role: role, size: size, width: width, state: state))
        .disabled(!isEnabled || state == .busy)
        .focused($isFocused)
        .overlay {
            if isFocused {
                RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.control, style: .continuous)
                    .strokeBorder(ToolTheme.focusRing, lineWidth: ToolMetrics.BorderWidth.focus)
                    .allowsHitTesting(false)
            }
        }
        .help(help ?? title ?? "")
        .accessibilityLabel(accessibilityLabel ?? title ?? help ?? "")
        .accessibilityHint(help ?? "")
    }

    @ViewBuilder
    private var label: some View {
        HStack(spacing: 6) {
            if state == .busy {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.72)
                    .frame(width: 14, height: 14)
            } else if state == .done {
                Image(systemName: "checkmark")
                    .font(.system(size: ToolMetrics.IconSize.small, weight: .semibold))
                    .frame(width: 14, height: 14)
            } else if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: role.iconSize, weight: .medium))
                    .frame(width: 14, height: 14)
            }

            if let title, !title.isEmpty {
                Text(title)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }

            if let keycap, !keycap.isEmpty {
                IndexKeycap(label: keycap)
            }
        }
    }
}

private extension ToolButton.Role {
    var defaultSize: ToolButton.Size {
        switch self {
        case .primary: return .cta32
        case .secondary, .quiet, .chip: return .compact28
        case .icon: return .icon24
        }
    }

    var iconSize: CGFloat {
        switch self {
        case .icon: return ToolMetrics.IconSize.large
        case .primary: return ToolMetrics.IconSize.medium
        default: return ToolMetrics.IconSize.small
        }
    }
}

private struct ToolButtonStyle: ButtonStyle {
    let role: ToolButton.Role
    let size: ToolButton.Size
    let width: ToolButton.Width
    let state: ToolButton.State

    func makeBody(configuration: Configuration) -> some View {
        StyleBody(
            configuration: configuration,
            role: role,
            size: size,
            width: width,
            state: state
        )
    }

    private struct StyleBody: View {
        let configuration: Configuration
        let role: ToolButton.Role
        let size: ToolButton.Size
        let width: ToolButton.Width
        let state: ToolButton.State

        @State private var isHovering = false
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        private var hovering: Bool { isHovering && isEnabled && state != .busy }
        private var pressed: Bool { configuration.isPressed && isEnabled && state != .busy }

        private var background: Color {
            if state == .done { return ToolTheme.successSoft }
            if state == .active { return ToolTheme.selectionFill }
            switch role {
            case .primary:
                return (pressed || hovering) ? ToolTheme.accentHover : ToolTheme.accent
            case .secondary:
                if pressed { return ToolTheme.activeFill }
                if hovering { return ToolTheme.hoverFill }
                return ToolTheme.utilityBackground
            case .quiet, .icon:
                if pressed { return ToolTheme.activeFill }
                if hovering { return ToolTheme.hoverFill }
                return Color.clear
            case .chip:
                if pressed { return ToolTheme.activeFill }
                if hovering { return ToolTheme.hoverFill }
                return ToolTheme.panelBackground
            }
        }

        private var border: Color {
            if state == .active { return ToolTheme.selectionStroke }
            if state == .done { return ToolTheme.successSoft }
            if role == .secondary || role == .chip { return hovering ? ToolTheme.strongBorder : ToolTheme.border }
            if role == .primary { return ToolTheme.accent }
            return Color.clear
        }

        private var foreground: Color {
            if state == .done { return ToolTheme.success }
            if state == .active { return ToolTheme.accent }
            switch role {
            case .primary: return ToolTheme.onAccent
            case .secondary, .quiet: return ToolTheme.textSecondary
            case .icon: return ToolTheme.textSecondary
            case .chip: return ToolTheme.textPrimary
            }
        }

        private var horizontalPadding: CGFloat {
            switch size {
            case .icon24: return 0
            case .compact28: return 9
            case .cta32, .field38: return 12
            case .bar44: return 14
            }
        }

        private var font: Font {
            switch size {
            case .icon24, .compact28: return ToolTypography.buttonSmall
            case .cta32, .field38: return ToolTypography.bodyMedium
            case .bar44: return ToolTypography.body
            }
        }

        var body: some View {
            configuration.label
                .font(font)
                .foregroundStyle(foreground)
                .padding(.horizontal, horizontalPadding)
                .frame(height: size.height)
                .frame(maxWidth: width == .fill ? .infinity : nil)
                .background(background, in: RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.control, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.control, style: .continuous)
                        .strokeBorder(border, lineWidth: border == .clear ? 0 : ToolMetrics.BorderWidth.hairline)
                }
                .contentShape(RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.control, style: .continuous))
                .opacity(isEnabled ? 1 : (role == .icon ? 0.4 : 0.45))
                .scaleEffect(!reduceMotion && pressed ? ToolMotion.Scale.pressed : 1)
                .onHover { isHovering = $0 }
                .toolAnimation(hovering ? ToolMotion.Preset.hoverIn : ToolMotion.Preset.hoverOut, reduceMotion: reduceMotion, value: hovering)
                .toolAnimation(ToolMotion.Preset.press, value: pressed)
        }
    }
}
