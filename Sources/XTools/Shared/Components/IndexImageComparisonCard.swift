import AppKit
import SwiftUI

struct IndexImageComparisonCard<Footer: View>: View {
 let title: String
 var badgeText: String? = nil
 var badgeTone: IndexBadgeTone = .neutral
 let image: NSImage?
 let accessibilityLabel: String
 let accessibilityValue: String
 let placeholder: String
 var isProcessing: Bool = false
 let footer: Footer

 init(
        title: String,
        badgeText: String? = nil,
        badgeTone: IndexBadgeTone = .neutral,
        image: NSImage?,
        accessibilityLabel: String,
        accessibilityValue: String,
        placeholder: String,
        isProcessing: Bool = false,
        @ViewBuilder footer: () -> Footer
    ) {
        self.title = title
        self.badgeText = badgeText
        self.badgeTone = badgeTone
        self.image = image
        self.accessibilityLabel = accessibilityLabel
        self.accessibilityValue = accessibilityValue
        self.placeholder = placeholder
        self.isProcessing = isProcessing
        self.footer = footer()
    }

 var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text(title)
                    .font(ToolTypography.label)
                    .foregroundStyle(ToolTheme.textPrimary)
                Spacer(minLength: 8)
                if let badgeText {
                    IndexBadge(badgeText, tone: badgeTone, isCapsule: true)
                }
            }
            .frame(minHeight: 34)
            .padding(.horizontal, 12)
            .background(ToolTheme.panelBackground)

            Rectangle()
                .fill(ToolTheme.border)
                .frame(height: 0.5)

            ZStack {
                IndexImagePreviewStage(
                    image: image,
                    accessibilityLabel: accessibilityLabel,
                    accessibilityValue: accessibilityValue,
                    placeholder: isProcessing ? "" : placeholder,
                    maxDisplayWidth: 560,
                    maxDisplayHeight: 320
                )
                if isProcessing {
                    IndexProgressLabel(message: "处理中…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 240, maxHeight: .infinity, alignment: .center)
            .background(ToolTheme.editorBackground)
            .clipShape(Rectangle())
            
            Rectangle()
                .fill(ToolTheme.border)
                .frame(height: 0.5)
            
            footer
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(ToolTheme.panelBackground)
        }
        .background(ToolTheme.editorBackground)
        .clipShape(RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.panel, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.panel, style: .continuous)
                .strokeBorder(ToolTheme.border, lineWidth: 0.5)
        }
    }
}
