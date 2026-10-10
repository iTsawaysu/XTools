import SwiftUI

enum IndexBadgeTone: Sendable {
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

    var softFill: Color {
        switch self {
        case .neutral: return ToolTheme.editorBackground
        case .success: return ToolTheme.successSoft
        case .warning: return ToolTheme.warningSoft
        case .error: return ToolTheme.errorSoft
        case .accent: return ToolTheme.accentSoft
        }
    }
}

struct IndexBadge: View {
 let title: String
 let systemImage: String?
 let tone: IndexBadgeTone
 let isSelected: Bool
 let isCapsule: Bool
 let fixedWidth: CGFloat?
 let help: String?
 let action: (() -> Void)?

    @State private var isHovering = false

 init(
        _ title: String,
        systemImage: String? = nil,
        tone: IndexBadgeTone = .neutral,
        isSelected: Bool = false,
        isCapsule: Bool = false,
        fixedWidth: CGFloat? = nil,
        help: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.title = title
        self.systemImage = systemImage
        self.tone = tone
        self.isSelected = isSelected
        self.isCapsule = isCapsule
        self.fixedWidth = fixedWidth
        self.help = help
        self.action = action
    }

    private var isHighlighted: Bool {
        isSelected || isHovering
    }

    private var effectiveTone: IndexBadgeTone {
        if isHighlighted && tone == .neutral {
            return .accent
        }
        return tone
    }

    private var background: Color {
        if isSelected {
            return ToolTheme.selectionFill
        }
        if isHovering && action != nil {
            return ToolTheme.hoverFill
        }
        return effectiveTone.softFill
    }

    private var border: Color {
        if isSelected {
            return ToolTheme.selectionStroke
        }
        // 常态透色细描边：语义色同色低透明度（neutral 用中性发丝线），
        // 让 soft 底的语义在浅填充上也读得出轮廓；静态零光晕。
        if effectiveTone == .neutral {
            return ToolTheme.border
        }
        return effectiveTone.tint.opacity(0.26)
    }
    
    private var font: Font {
        isCapsule ? ToolTypography.tagMicro : ToolTypography.monoValueSmall
    }

 var body: some View {
        if let action {
            Button(action: action) {
                content
            }
            .buttonStyle(.plain)
            .onHover { isHovering = $0 }
                        .help(help ?? "")
        } else {
            content
        }
    }

    private var content: some View {
        HStack(spacing: 6) {
            if let systemImage {
                Image(systemName: systemImage)
            }
            Text(title)
                .tracking(isCapsule ? 0.8 : 0)
        }
        .font(font)
        .foregroundStyle(effectiveTone.tint)
        .padding(.horizontal, isCapsule ? 6 : 8)
        .padding(.vertical, isCapsule ? 2 : 3)
        .frame(width: fixedWidth, alignment: .center)
        .background(background, in: isCapsule ? AnyShape(Capsule(style: .continuous)) : AnyShape(RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.control, style: .continuous)))
        .overlay {
            if isCapsule {
                Capsule(style: .continuous).strokeBorder(border, lineWidth: 1)
            } else {
                RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.control, style: .continuous).strokeBorder(border, lineWidth: 1)
            }
        }
    }
}


