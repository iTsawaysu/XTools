import SwiftUI

struct ToolBadge: View {
    enum Tone: Equatable {
        case neutral
        case success
        case warning
        case error
        case accent

        var tint: Color {
            switch self {
            case .neutral: return ToolTheme.textSecondary
            case .success: return ToolTheme.success
            case .warning: return ToolTheme.warning
            case .error: return ToolTheme.error
            case .accent: return ToolTheme.accentHover
            }
        }

        var fill: Color {
            switch self {
            case .neutral: return ToolTheme.editorBackground
            case .success: return ToolTheme.successSoft
            case .warning: return ToolTheme.warningSoft
            case .error: return ToolTheme.errorSoft
            case .accent: return ToolTheme.accentSoft
            }
        }
    }

    let title: String
    var systemImage: String? = nil
    var tone: Tone = .neutral

    var body: some View {
        HStack(spacing: 5) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: ToolMetrics.IconSize.micro, weight: .semibold))
            }
            Text(title)
                .lineLimit(1)
        }
        .font(ToolTypography.monoValueSmall)
        .foregroundStyle(tone.tint)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(tone.fill, in: RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.control, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.control, style: .continuous)
                .strokeBorder(tone == .neutral ? ToolTheme.border : tone.tint.opacity(0.26), lineWidth: ToolMetrics.BorderWidth.hairline)
        }
        .accessibilityElement(children: .combine)
    }
}

struct ToolChip: View {
    let title: String
    var isSelected: Bool = false
    var isEnabled: Bool = true
    var help: String? = nil
    let action: () -> Void

    var body: some View {
        ToolButton(
            title,
            role: .chip,
            size: .compact28,
            state: isSelected ? .active : .idle,
            isEnabled: isEnabled,
            help: help,
            action: action
        )
    }
}
