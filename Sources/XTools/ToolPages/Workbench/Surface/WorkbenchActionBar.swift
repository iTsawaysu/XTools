import SwiftUI
import XToolsDesign

// MARK: - 声明式结果操作（design.md §5）

/// 结果操作条的动作模型：copy / save / useAsInput / swap / clear 五种
/// （design.md §5）。按工具能力声明式启用，渲染归 `WorkbenchActionBar`。
///
/// 契约：
/// - 第一个 `.copy` 动作即「主输出复制」，挂全局 ⇧⌘C（页面级、
///   `toolPageEntryGeneration` 门控：停靠失活自动注销，design.md §5-6）；
/// - `.save` 平移 AppKit 异步保存器（`IndexSaveTextButton` 能力，含
///   取消静默/失败一次性 error toast）；
/// - `.useAsInput` 执行宿主写回闭包后由操作条统一播报成功 toast
///   （「已作为输入」）；写回与聚焦输入由宿主闭包完成；
/// - `.swap` 只翻转方向并触发重算，不播报 toast（方向变化自身可见）。
/// Sendable 说明：动作闭包均为页面侧 MainActor UI 回调，结构体仅在主线程
/// 构造与消费（preference 传递也在主线程视图树内）；`@unchecked` 限于该边界。
struct WorkbenchActionBarAction: @unchecked Sendable {
    /// 动作种类（存储用；调用侧用静态工厂构造）。
    enum Kind {
        case copy(text: String, title: String, successToast: String?, help: String?, enabled: Bool)
        case save(payload: String, fileName: String)
        case useAsInput(onPerform: () -> Void)
        case swap(onPerform: () -> Void, directionLabel: String)
        case clear(title: String, enabled: Bool, onPerform: () -> Void)
    }

    let kind: Kind

    /// 复制主输出（第一个 copy 动作挂 ⇧⌘C）。`title` 为按钮文案（默认
    /// 「复制」，批量动作传「全部复制」保持旧页文案等价）；`successToast`
    /// 覆盖标准「已复制」回执（批量复制传 `copiedAll(noun:)`）；`enabled`
    /// 由宿主给出门控（page-rollout Batch B：格式化族沿用旧页
    /// `.disabled(!isOutputFresh)`——陈旧结果在重新格式化前不可复制），
    /// 默认 true，既有调用点零影响。
    static func copy(
        text: String,
        title: String = "复制",
        successToast: String? = nil,
        help: String? = nil,
        enabled: Bool = true
    ) -> WorkbenchActionBarAction {
        WorkbenchActionBarAction(kind: .copy(text: text, title: title, successToast: successToast, help: help, enabled: enabled))
    }

    /// 异步保存输出到文件（AppKit 异步保存器）。
    static func save(payload: String, fileName: String) -> WorkbenchActionBarAction {
        WorkbenchActionBarAction(kind: .save(payload: payload, fileName: fileName))
    }

    /// 把输出写回输入并聚焦（写回逻辑由宿主闭包持有）。
    static func useAsInput(onPerform: @escaping () -> Void) -> WorkbenchActionBarAction {
        WorkbenchActionBarAction(kind: .useAsInput(onPerform: onPerform))
    }

    /// 编解码/加解密方向互换（图标 + 方向标签；闭包翻转方向状态并重算）。
    static func swap(
        onPerform: @escaping () -> Void,
        directionLabel: String
    ) -> WorkbenchActionBarAction {
        WorkbenchActionBarAction(kind: .swap(onPerform: onPerform, directionLabel: directionLabel))
    }

    /// 清空工作区（enabled 由宿主按完整工作区状态给出；`title` 默认
    /// 「清空」，全工作区清空传旧页文案「全部清空」）。
    static func clear(
        title: String = "清空",
        enabled: Bool = true,
        onPerform: @escaping () -> Void
    ) -> WorkbenchActionBarAction {
        WorkbenchActionBarAction(kind: .clear(title: title, enabled: enabled, onPerform: onPerform))
    }
}

/// 页面级快捷键代理钮的动作载体（壳与 IOPair 的 `pageLevelShortcuts` 使用）：
/// 钮的真实文字，EmptyView 标签不产生平台视图）+ 键位 + 闭包。⇧⌘C 的执行
/// 语义与可见复制钮一致（写剪贴板 + toast 回执），由壳侧调用
/// `performCopyViaToastCenter` 桥接。
struct WorkbenchPageShortcut {
    let title: String
    let key: KeyEquivalent
    let modifiers: EventModifiers
    let perform: () -> Void
}

extension WorkbenchActionBarAction {
    /// 可见 copy 钮的标题（壳层代理钮复用同文案）。
    var copyTitle: String {
        if case let .copy(_, title, _, _, _) = kind { return title }
        return "复制"
    }

    /// copy 门控（Batch B 格式化族 isOutputFresh 等价迁移）：壳层/IOPair 的
    /// ⇧⌘C 代理与可见钮同门控——旧页禁用按钮的快捷键不触发，代理同样注销。
    var copyEnabled: Bool {
        if case let .copy(_, _, _, _, enabled) = kind { return enabled }
        return false
    }

    /// 供壳层 ⇧⌘C 代理钮复用：执行 copy 语义（IndexCopyButton 同路径：
    /// IndexPasteboard 写剪贴板 + toastCenter 播报成功回执）。
    @MainActor
    func performCopyViaToastCenter(_ toastCenter: ToolToastCenter?) {
        guard case let .copy(text, _, successToast, _, _) = kind, !text.isEmpty else { return }
        IndexPasteboard.copyString(text)
        let message = successToast ?? ToolFeedbackCopy.copied
        toastCenter?.show(message, tone: .success)
    }
}

/// 新能力「用作输入」的规范回执文案（ToolFeedbackCopy 的同族规范；随
/// 本操作条首发，阶段④铺开时如需集中可平移进共享文案表）。
enum WorkbenchActionBarCopy {
    static let usedAsInput = "已作为输入"
    static let useAsInputTitle = "用作输入"
    static let useAsInputHelp = "把输出写回输入并聚焦"
    static func swapHelp(directionLabel: String) -> String {
        "切换方向（\(directionLabel)）"
    }
}

/// 声明式结果操作条：右对齐 quiet 钮一排，按动作模型渲染。
///
/// 挂载位置（design.md §5）：
/// - 对等双栏：输出 pane 尾部（`WorkbenchIOPair` 的 trailing 动作槽）；
/// - 单结果/生成器形态：`WorkbenchSurface` 内容区底部；
/// - 画布形态：宿主自行嵌入。
///
/// 全部走阶段① 组件：复制 `IndexCopyButton`、保存 `IndexSaveTextButton`
/// （AppKit 异步保存器）、清空 `IndexClearButton`、自绘钮用
/// `IndexQuietChromeStyle(look: .framed)`；剪贴板唯一入口 `IndexPasteboard`
/// 经由 IndexCopyButton 间接复用。
struct WorkbenchActionBar: View {
    let actions: [WorkbenchActionBarAction]

    @Environment(\.toolPageEntryGeneration) private var entryGeneration
    @Environment(\.toolToastCenter) private var toastCenter

    /// 首个 copy 动作的下标（主输出 ⇧⌘C 的唯一持有者）。
    private var primaryCopyIndex: Int? {
        actions.firstIndex {
            if case .copy = $0.kind { return true }
            return false
        }
    }

    var body: some View {
        HStack(spacing: ToolMetrics.Spacing.sm) {
            ForEach(actions.indices, id: \.self) { index in
                button(for: actions[index], isPrimaryCopy: primaryCopyIndex == index)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
        .frame(maxWidth: .infinity, alignment: .trailing)
        .accessibilityElement(children: .contain)
    }

    // MARK: - 渲染

    @ViewBuilder
    private func button(for action: WorkbenchActionBarAction, isPrimaryCopy: Bool) -> some View {
        switch action.kind {
        case let .copy(text, title, successToast, help, enabled):
            IndexCopyButton(
                text: text,
                title: title,
                showsIcon: false,
                framed: true,
                successToast: successToast,
                help: help
            )
            .disabled(!enabled)
            // 页面级 ⇧⌘C 已上移至壳层 pageLevelShortcuts 统一挂载（真窗口
            // 排查结论：pane 深嵌位置的事件分发不稳定；此处不再挂快捷键，
            // 仅保留可见按钮的点击路径）。

        case let .save(payload, fileName):
            IndexSaveTextButton(
                text: payload,
                fileName: fileName,
                showsIcon: false,
                framed: true
            )

        case let .useAsInput(onPerform):
            quietButton(
                title: WorkbenchActionBarCopy.useAsInputTitle,
                systemImage: "tray.and.arrow.down",
                help: WorkbenchActionBarCopy.useAsInputHelp
            ) {
                onPerform()
                toastCenter?.show(WorkbenchActionBarCopy.usedAsInput, tone: .success)
            }

        case let .swap(onPerform, directionLabel):
            quietButton(
                title: directionLabel,
                systemImage: "arrow.left.arrow.right",
                help: WorkbenchActionBarCopy.swapHelp(directionLabel: directionLabel)
            ) {
                onPerform()
            }

        case let .clear(title, enabled, onPerform):
            IndexClearButton(
                isDisabled: !enabled,
                title: title,
                showsIcon: false,
                framed: true,
                action: onPerform
            )
        }
    }

    /// 自绘 quiet 动作钮：`IndexQuietChromeStyle(look: .framed)` 负责
    /// chrome 反馈（静止 utility 底 + hairline、hover/press 上色），label
    /// 自带字体/内边距/高度（与 IndexButtonStyle(compact) 同密度）。
    private func quietButton(
        title: String,
        systemImage: String,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: ToolMetrics.Spacing.fine) {
                Image(systemName: systemImage)
                Text(title)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .font(ToolTypography.buttonSmall)
            .padding(.horizontal, ToolMetrics.Spacing.sm)
            .frame(height: ToolMetrics.Control.small)
        }
        .buttonStyle(IndexQuietChromeStyle(look: .framed, ink: .quiet))
        .help(help)
        .accessibilityLabel(help)
    }
}
