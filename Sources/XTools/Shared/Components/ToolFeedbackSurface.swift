import SwiftUI

struct ToolFeedbackAction {
    let title: String
    var systemImage: String? = nil
    let action: () -> Void
}

struct ToolFeedbackSurface: View {
    enum Tone: Equatable {
        case info
        case success
        case warning
        case error

        var tint: Color {
            switch self {
            case .info: return ToolTheme.accent
            case .success: return ToolTheme.success
            case .warning: return ToolTheme.warning
            case .error: return ToolTheme.error
            }
        }

        var fill: Color {
            switch self {
            case .info: return ToolTheme.accentSoft
            case .success: return ToolTheme.successSoft
            case .warning: return ToolTheme.warningSoft
            case .error: return ToolTheme.errorSoft
            }
        }

        var icon: String {
            switch self {
            case .info: return "info.circle"
            case .success: return "checkmark.circle"
            case .warning: return "exclamationmark.triangle"
            case .error: return "xmark.octagon"
            }
        }
    }

    enum Presentation: Equatable {
        case inline
        case toast
        case statusSlot
    }

    let tone: Tone
    let message: String
    var action: ToolFeedbackAction? = nil
    var presentation: Presentation = .inline

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: tone.icon)
                .font(.system(size: ToolMetrics.IconSize.small, weight: .semibold))
                .foregroundStyle(tone.tint)
                .frame(width: 14, height: 14)

            Text(message)
                .font(ToolTypography.caption)
                .foregroundStyle(tone.tint)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 6)

            if let action {
                ToolButton(
                    action.title,
                    systemImage: action.systemImage,
                    role: .quiet,
                    size: .compact28,
                    action: action.action
                )
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, presentation == .statusSlot ? 6 : 7)
        .background(
            presentation == .toast ? ToolTheme.panelBackground : tone.fill,
            in: RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.control, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.control, style: .continuous)
                .strokeBorder(tone.tint.opacity(0.26), lineWidth: ToolMetrics.BorderWidth.hairline)
        }
        .modifier(ToolFeedbackElevation(presentation: presentation))
        .accessibilityElement(children: .combine)
    }
}

private struct ToolFeedbackElevation: ViewModifier {
    let presentation: ToolFeedbackSurface.Presentation

    func body(content: Content) -> some View {
        if presentation == .toast {
            content.toolShadow(ToolTheme.Shadow.floating)
        } else {
            content
        }
    }
}
