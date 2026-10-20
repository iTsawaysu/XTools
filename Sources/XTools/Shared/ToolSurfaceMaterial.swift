import SwiftUI
import XToolsDesign

// MARK: - ToolSurfaceMaterial
//
// v5：应用内不再使用系统材质。侧栏与所有内容表面一样，用不透明的暖中性
// 填充 + 0.5pt 发丝线分层；材质感来自表面阶梯与暖色偏移，而不是透光/模糊。
// 保留 `toolSurface` 入口，避免调用点各自搭建填充逻辑。

enum ToolSurfaceRole {
    /// 侧栏：与工作区共用暖中性阶梯，靠一档明度差和右侧发丝线分层。
    case sidebar
}

extension View {
    /// 不透明表面填充；`role` 保留为语义锚点，后续若要区分表面族在此收口。
    func toolSurface(
        _ role: ToolSurfaceRole,
        fallback: Color,
        in shape: some Shape
    ) -> some View {
        self.background(fallback, in: shape)
    }
}
