import SwiftUI

// MARK: - ToolSurfaceMaterial
//
// 系统材质适配层（Clay Warmth × Liquid Glass 时代）。
//
// 策略（见 docs/ui-unification-v2-master-plan.md 与 v1 方案 §七）：
// - macOS 26+ 的浮层（命令面板 / Toast / SmartPaste 横幅）与侧栏改用系统
//   材质，让窗口内容与系统玻璃语言一致；再叠一层低透明度 Clay 底色保温。
// - macOS 13–25 与所有「内容面板」保持 ToolTheme 不透明填充——信息密度
//   最高的表面永远以可读性优先。
// - 所有落点必须通过 `toolSurface` 进入，不允许各处自行搭建材质。

enum ToolSurfaceRole {
    /// 侧栏：细材质，让工作区与侧栏保持温和的层级差。
    case sidebar
    /// 浮层（面板之上）：常规材质，真实磨砂底下层内容。
    case floating
}

enum ToolSurfaceMaterial {
    static let usesSystemMaterial: Bool = {
        if #available(macOS 26, *) {
            return true
        }
        return false
    }()

    static func material(for role: ToolSurfaceRole) -> Material {
        switch role {
        case .sidebar: return .thin
        case .floating: return .regular
        }
    }

    /// 材质之上的 Clay 保温层透明度：太透会冷灰，太实会失去玻璃感。
    static func tintOpacity(for role: ToolSurfaceRole) -> Double {
        switch role {
        case .sidebar: return 0.42
        case .floating: return 0.16
        }
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
