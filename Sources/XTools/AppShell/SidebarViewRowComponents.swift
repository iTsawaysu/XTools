import SwiftUI
import XToolsDesign

// 侧栏壳行组件（阶段③ 原生侧栏后仅存品牌徽记与底部按钮；工具行/组头已由
// `SidebarNativeList` 的原生 List 行与 Section 头接管，自绘选中条/滚动条
// 同批退役）。

struct BrandMark: View {
    var body: some View {
        // Terminal prompt glyph. Solid accent, no glow (Ink Terminal Pro avoids
        // the Linear-style purple gradient + bloom — SPEC §7, anti-slop).
        Image(systemName: "chevron.right")
            .font(ToolTypography.icon(ToolMetrics.IconSize.small, .semibold))
            .foregroundStyle(ToolTheme.onAccent)
            .frame(width: 22, height: 22)
            .background(ToolTheme.accent, in: RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.nestedControl, style: .continuous))
    }
}

struct SidebarFooterButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    @StateObject private var hoverState = SidebarFooterHoverState()

    var body: some View {
        Button(action: action) {
            HStack(spacing: ToolMetrics.Spacing.sm) {
                Image(systemName: systemImage)
                    .font(ToolTypography.icon(ToolMetrics.IconSize.medium, .regular))
                    .frame(width: 15)

                Text(title)
                    .font(ToolTypography.label)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .foregroundStyle(hoverState.isHovered ? ToolTheme.textPrimary : ToolTheme.textSecondary)
            .frame(maxWidth: .infinity)
            .frame(height: 30)
            // hover 通道 opacity 插值（design-foundation D2 范式；圆角走
            // token 默认 control 档，原 SidebarMetrics.rowCornerRadius 已随
            // S14 退役）。
            .indexRowHoverBackground(hoverState.isHovered)
        }
        .buttonStyle(.plain)
        .toolInteractionFeedback()
        .onHover { hoverState.isHovered = $0 }
        .toolAnimation(ToolMotion.Preset.controlFeedback, value: hoverState.isHovered)
    }
}

@MainActor
private final class SidebarFooterHoverState: ObservableObject {
    @Published var isHovered = false
}
