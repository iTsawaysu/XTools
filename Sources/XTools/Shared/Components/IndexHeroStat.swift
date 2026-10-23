import SwiftUI
import XToolsDesign

enum IndexHeroStatTone: Sendable {
    case accent
    case primary
    
    var valueColor: Color {
        switch self {
        case .accent: return ToolTheme.accentHover
        case .primary: return ToolTheme.textPrimary
        }
    }
}

struct IndexHeroStat: View {
 let caption: String?
 let value: String
 let tone: IndexHeroStatTone
 let copyable: Bool
 let design: Font.Design
    
 init(
        caption: String? = nil,
        value: String,
        tone: IndexHeroStatTone = .accent,
        copyable: Bool = true,
        design: Font.Design = .monospaced
    ) {
        self.caption = caption
        self.value = value
        self.tone = tone
        self.copyable = copyable
        self.design = design
    }

 var body: some View {
        VStack(spacing: ToolMetrics.Spacing.sm) {
            HStack(spacing: ToolMetrics.Spacing.md) {
                Text(value)
                    .font(ToolTypography.heroValue(design: design))
                    .foregroundStyle(tone.valueColor)
                    .textSelection(.enabled)
                    .toolMotionTextSwap(id: value)
                
                if copyable && !value.isEmpty {
                    IndexCopyButton(text: value, iconOnly: true)
                }
            }
            if let caption {
                Text(caption)
                    .font(ToolTypography.monoCaption)
                    .foregroundStyle(ToolTheme.textSecondary)
                    .toolMotionTextSwap(id: caption)
            }
        }
        .padding(.horizontal, ToolMetrics.Spacing.xxxl)
        .padding(.vertical, ToolMetrics.Spacing.xxl)
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, ToolMetrics.Spacing.xxxl)
    }
}
