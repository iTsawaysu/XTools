import SwiftUI
import XToolsDesign

// MARK: - IndexKeycap
//
// 全 App 统一键帽（实心色片，ADR-0024）：一块比所在表面深一档（浅色）/
// 亮一档（深色）的实心圆角片，字形用 textPrimary；无渐变、无边线、无投影。
// 所有快捷键提示——顶栏 ⌘K、命令面板提示条、侧栏 ⌘0、页内主按钮 hint——
// 必须走本组件，禁止各处自建键帽底盒。

struct IndexKeycap: View {
    enum Variant {
        /// 中性表面（顶栏 / 命令面板 / 侧栏）。
        case standard
        /// 实心 accent 主按钮内：onAccent 同色系键帽。
        case onAccent
    }

    let label: String
    var variant: Variant = .standard

    private var surface: Color {
        variant == .standard
            ? ToolTheme.Keycap.surface
            : ToolTheme.Keycap.onAccentSurface
    }

    private var foreground: Color {
        variant == .standard
            ? ToolTheme.textPrimary
            : ToolTheme.Keycap.onAccentForeground
    }

    var body: some View {
        Text(label)
            .font(ToolTypography.keycap)
            .tracking(0.6)
            .foregroundStyle(foreground)
            .padding(.horizontal, ToolMetrics.Spacing.sm)
            .padding(.vertical, ToolMetrics.Spacing.xxs)
            .background(
                RoundedRectangle(
                    cornerRadius: ToolMetrics.CornerRadius.keycap,
                    style: .continuous
                )
                .fill(surface)
            )
    }
}
