import SwiftUI

// MARK: - IndexKeycap
//
// 全 App 统一键帽。配方（见 `ToolTheme.Keycap`）：一块实心色片 + 干净硬
// 边界，无渐变、无边线、无描边、无投影——质感只来自色片与表面的明度差
// （参考实测：浅色床 #E6E6E6 落在 #FCFCFC 上，约 8% 明度差）。所有快捷键
// 提示——顶栏 ⌘K、命令面板提示条、侧栏 ⌘0、页内主按钮 hint——必须走本
// 组件，禁止各处自建键帽底盒（源码契约
// `keycapsMustRenderThroughTheUnifiedComponent` 防回潮）。

struct IndexKeycap: View {
    enum Variant {
        /// 中性表面（顶栏 / 命令面板 / 侧栏）。
        case standard
        /// 实心 accent 主按钮内：onAccent 同色实底。
        case onAccent
    }

    let label: String
    var variant: Variant = .standard

    var body: some View {
        Text(label)
            .font(ToolTypography.keycap)
            .tracking(0.6)
            .foregroundStyle(variant == .standard ? ToolTheme.textPrimary : ToolTheme.onAccent.opacity(0.95))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                variant == .standard ? ToolTheme.Keycap.bed : ToolTheme.Keycap.onAccentBed,
                in: RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.keycap, style: .continuous)
            )
    }
}
