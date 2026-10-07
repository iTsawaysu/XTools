import SwiftUI

// MARK: - ToolSurfaceMaterial
//
// 系统材质适配层（Clay Warmth × Liquid Glass 时代）。
//
// 策略：
// - macOS 26+ 仅侧栏改用系统材质，让工作区与侧栏保持温和层级差；再叠一层
//   低透明度 Clay 底色保温。
// - macOS 13–25 与所有「内容面板」及浮层（命令面板 / Toast / SmartPaste
//   横幅走 .indexSurface(.modal) 不透明底）保持 ToolTheme 填充——信息密度
//   最高的表面永远以可读性优先。
// - 所有落点必须通过 `toolSurface` 进入，不允许各处自行搭建材质。

enum ToolSurfaceRole {
    /// 侧栏：细材质，让工作区与侧栏保持温和的层级差。
    case sidebar
}

private enum ToolSurfaceMaterial {
    static let usesSystemMaterial: Bool = {
        if #available(macOS 26, *) {
            return true
        }
        return false
    }()

    static func material(for role: ToolSurfaceRole) -> Material {
        .thin
    }

    /// 材质之上的 Clay 保温层透明度：太透会冷灰，太实会失去玻璃感。
    static func tintOpacity(for role: ToolSurfaceRole) -> Double {
        0.42
    }
}

extension View {
    /// 系统材质 + Clay 保温底的表面处理；材质不可用时回退为纯色填充。
    @ViewBuilder
    func toolSurface(
        _ role: ToolSurfaceRole,
        fallback: Color,
        in shape: some Shape
    ) -> some View {
        if ToolSurfaceMaterial.usesSystemMaterial {
            self
                .background {
                    shape
                        .fill(fallback.opacity(ToolSurfaceMaterial.tintOpacity(for: role)))
                        .background(
                            ToolSurfaceMaterial.material(for: role),
                            in: shape
                        )
                }
        } else {
            self.background(fallback, in: shape)
        }
    }
}
