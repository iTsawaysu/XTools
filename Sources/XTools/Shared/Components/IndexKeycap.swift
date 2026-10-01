import SwiftUI

// MARK: - IndexKeycap
//
// 全 App 统一键帽（brew.sh 式立体键帽）：白色顶面 + 底部露出的深一档侧壁
// 形成真实键帽的厚度，顶面一层极淡受光高光，配 1pt 落影。深色模式同构
// （亮灰顶面 + 近黑侧壁）。所有快捷键提示——顶栏 ⌘K、命令面板提示条、
// 侧栏 ⌘0、页内主按钮 hint——必须走本组件，禁止各处自建键帽底盒（源码
// 契约 `keycapsMustRenderThroughTheUnifiedComponent` 防回潮）。

struct IndexKeycap: View {
    enum Variant {
        /// 中性表面（顶栏 / 命令面板 / 侧栏）。
        case standard
        /// 实心 accent 主按钮内：onAccent 同色系键帽。
        case onAccent
    }

    /// 键帽厚度（底部露出的侧壁高度）。
    private static let wallThickness: CGFloat = 1.5

    let label: String
    var variant: Variant = .standard

    @Environment(\.colorScheme) private var colorScheme

    private var surface: Color {
        variant == .standard
            ? ToolTheme.Keycap.surface
            : ToolTheme.Keycap.onAccentSurface
    }

    private var wall: Color {
        variant == .standard
            ? ToolTheme.Keycap.wall
            : ToolTheme.Keycap.onAccentWall
    }

    /// 顶面受光高光强度：浅色明显、深色几乎不可见。
    private var sheenOpacity: Double {
        colorScheme == .light ? 0.5 : 0.08
    }

    var body: some View {
        Text(label)
            .font(ToolTypography.keycap)
            .tracking(0.6)
            .foregroundStyle(
                variant == .standard
                    ? ToolTheme.textPrimary
                    : ToolTheme.onAccent.opacity(0.95)
            )
            .padding(.horizontal, 7)
            .padding(.vertical, 2.5)
            .background(keycap)
            .toolShadow(ToolTheme.Shadow.keycap)
    }

    /// 立体键帽：侧壁全尺寸垫底，顶面短一截厚度、对齐顶部——底带即侧壁。
    private var keycap: some View {
        let shape = RoundedRectangle(
            cornerRadius: ToolMetrics.CornerRadius.keycap,
            style: .continuous
        )
        return ZStack(alignment: .top) {
            shape.fill(wall)
            shape
                .fill(surface)
                .overlay(alignment: .top) {
                    LinearGradient(
                        colors: [.white.opacity(sheenOpacity), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .clipShape(shape)
                }
                .padding(.bottom, Self.wallThickness)
        }
    }
}
