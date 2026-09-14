import SwiftUI

public enum IndexHeroStatTone: Sendable {
    case accent
    case primary
    
    var valueColor: Color {
        switch self {
        case .accent: return ToolTheme.accentHover
        case .primary: return ToolTheme.textPrimary
        }
    }
}

public struct IndexHeroStat: View {
    public let caption: String?
    public let value: String
    public let tone: IndexHeroStatTone
    public let copyable: Bool
    public let design: Font.Design
    
    public init(
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

    public var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
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
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 26)
    }
}
