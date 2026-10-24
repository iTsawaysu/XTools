import SwiftUI
import XToolsCore
import XToolsDesign

// MARK: - 输入 pane 文本文件拖入支持（page-rollout Batch B）

/// 输入 pane 的文本文件拖入支持：格式化/转换族从旧 `IndexFormatWorkbench`
/// 迁入统一壳时随行的一组等价能力，收拢为单一 modifier 避免逐页复制
/// （旧壳「纸壳样板六连抄」教训）。配套 `IndexWorkspaceTextArea` 的
/// `droppedFile:` / `onFileDrop:` 参数使用——拖拽悬停与接收状态由认领拖拽
/// 会话的 NSTextView 经 `IndexDroppedTextFile` 发布，SwiftUI 外层 onDrop
/// 收不到回调（IndexCaretTextView 注释）。
///
/// modifier 负责两件事（接收写入仍由页面在 `onFileDrop` 闭包完成）：
/// 1. 悬停 wash：编辑器面不透明，选中底色 + accent 描边画在上层 overlay
///    （ToolOutputBreath 同法；旧壳 dropTargetHover 逐字平移）；
/// 2. 生命周期：输入变化即作废挂起的拖拽读取并撤下拒判提示；pane 消失
///    同样作废（旧壳 inputPane 的 onChange/onDisappear 等价平移）。
/// 拒判提示（超限/不可读文件）由页面经 `.indexWorkspaceDiagnostic` 发布
/// ——诊断单轨收编旧壳的拒绝横幅槽（显式关闭钮随单轨收敛退役；编辑输入
/// 自动消除的路径保留）。
struct WorkbenchInputDropSupport: ViewModifier {
    @Binding var text: String
    @ObservedObject var droppedFile: IndexDroppedTextFile

    func body(content: Content) -> some View {
        content
            .overlay { dropTargetHover }
            .onChange(of: JSONExactTextIdentity(text)) {
                droppedFile.invalidate()
                droppedFile.dismissRejection()
            }
            .onDisappear { droppedFile.invalidate() }
    }

    /// 文件拖拽悬停反馈：状态由认领拖拽会话的 `IndexCaretTextView` 经
    /// `droppedFile.isDropTargeted` 发布。编辑器面不透明，wash 与描边必须
    /// 画在上层 overlay。
    private var dropTargetHover: some View {
        let shape = RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.field, style: .continuous)
        return ZStack {
            shape.fill(ToolTheme.selectionFill)
            shape.strokeBorder(ToolTheme.accentBorder, lineWidth: 1)
        }
        .opacity(droppedFile.isDropTargeted ? 1 : 0)
        .allowsHitTesting(false)
        .toolAnimation(ToolMotion.Preset.controlFeedback, value: droppedFile.isDropTargeted)
    }
}

extension View {
    /// 把输入 pane 声明为文本文件拖入目标（配合 `IndexWorkspaceTextArea`
    /// 的 `onFileDrop:` / `droppedFile:` 参数）。
    func workbenchInputDropSupport(
        text: Binding<String>,
        droppedFile: IndexDroppedTextFile
    ) -> some View {
        modifier(WorkbenchInputDropSupport(text: text, droppedFile: droppedFile))
    }
}
