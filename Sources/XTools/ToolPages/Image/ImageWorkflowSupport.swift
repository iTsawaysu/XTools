import SwiftUI
import XToolsCore

/// 单图工作流页面的共享上传装配。
///
/// 图片五页（格式转换/压缩/灰度/水印/Favicon）的上传交互逐字同形：选择/
/// 更换/清除动作行、源准备进度与图片空态分支、页面持有的源发布 panelReveal
/// 事务、多文件拖放整批拒绝。各页保留各自的会话调用与文案，这里只收敛
/// 骨架；按钮词表、无障碍名、动画预设与拖放修饰符与收敛前完全一致。
struct ImageSelectionActionRow: View {
    /// 已有源图时显示「更换 + 清除」，否则只显示「选择」。
    let hasSource: Bool
    let selectAccessibilityLabel: String
    let replaceAccessibilityLabel: String
    let clearAccessibilityLabel: String
    let onSelect: () -> Void
    /// 清除动作由页面自带 panelReveal 事务包装（各页清除语义不同：批量页
    /// 清空全部、水印页先取消防抖）。
    let onClear: () -> Void
    var selectTitle = "选择图片"
    var changeTitle = "更换图片"
    var clearTitle = "清除图片"

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onSelect) {
                Label(hasSource ? changeTitle : selectTitle, systemImage: "photo")
                    .font(ToolTypography.buttonSmall)
            }
            .buttonStyle(IndexSmallButtonStyle())
            .accessibilityLabel(hasSource ? replaceAccessibilityLabel : selectAccessibilityLabel)

            if hasSource {
                Button(action: onClear) {
                    Label(clearTitle, systemImage: IndexActionSymbol.removeResource)
                        .font(ToolTypography.buttonSmall)
                }
                .buttonStyle(IndexSmallButtonStyle())
                .accessibilityLabel(clearAccessibilityLabel)
            }
        }
    }
}

/// 源准备占位：读取中显示进度标签，否则显示共享图片空态。
/// `fillsHeight` 仅供铺满整个输入区的页面（批量转换）让空态垂直居中。
struct ImageUploadPendingState: View {
    let isProcessing: Bool
    let title: String
    var fillsHeight = false

    var body: some View {
        if isProcessing {
            IndexProgressLabel(message: "正在读取图片…")
                .foregroundStyle(ToolTheme.textSecondary)
                .accessibilityLabel("正在读取图片")
        } else {
            IndexEmptyState(
                title: title,
                systemImage: "photo.on.rectangle.angled",
                message: IndexEmptyStateCopy.autoGenerate("图片"),
                density: .list
            )
            .frame(maxWidth: .infinity, minHeight: 128, maxHeight: fillsHeight ? .infinity : nil)
        }
    }
}

/// 单输出页（压缩/灰度）的「上传图片」空态面板：动作行 + 源准备占位，
/// 面板内容即共享单文件拖放区（多文件整批拒绝）。
struct ImageUploadEmptyPanel<Actions: View>: View {
    @Binding var isDropTargeted: Bool
    let isProcessing: Bool
    let diagnostic: String?
    let emptyStateTitle: String
    private let actions: Actions
    private let onDropFile: (URL) -> Void
    private let onDropMultipleFiles: () -> Void

    init(
        isDropTargeted: Binding<Bool>,
        isProcessing: Bool,
        diagnostic: String?,
        emptyStateTitle: String,
        actions: Actions,
        onDropFile: @escaping (URL) -> Void,
        onDropMultipleFiles: @escaping () -> Void
    ) {
        self._isDropTargeted = isDropTargeted
        self.isProcessing = isProcessing
        self.diagnostic = diagnostic
        self.emptyStateTitle = emptyStateTitle
        self.actions = actions
        self.onDropFile = onDropFile
        self.onDropMultipleFiles = onDropMultipleFiles
    }

    var body: some View {
        IndexPanel("上传图片") {
            VStack(alignment: .leading, spacing: ToolMetrics.Spacing.md) {
                actions
                ImageUploadPendingState(isProcessing: isProcessing, title: emptyStateTitle)
            }
            .indexWorkspaceDiagnostic(diagnostic)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, ToolMetrics.Spacing.sm)
            .indexDropZone(
                isTargeted: $isDropTargeted,
                onFile: onDropFile,
                onMultipleFiles: onDropMultipleFiles
            )
        }
        .verticallyFilling()
    }
}

/// 单图页共享的页面持有交互事务：接受的选图与多文件拖放拒绝都在
/// panelReveal 事务内落位（会话源赋值不逃出事务）。
struct ImageUploadInteractions {
    let reduceMotion: Bool

    @MainActor
    func publishSelection(_ selection: ImageInputSelection, _ publish: () -> Void) {
        withToolAnimation(ToolMotion.Preset.panelReveal, reduceMotion: reduceMotion) {
            publish()
        }
    }

    @MainActor
    func rejectMultipleDrop(_ reject: () -> Void) {
        withToolAnimation(ToolMotion.Preset.panelReveal, reduceMotion: reduceMotion) {
            reject()
        }
    }
}

/// 单输出保存结果的共享 toast 映射：成功只在确认保存后提示；写盘失败报
/// error；取消/阻止静默；单输出页对不可能出现的部分结果同样静默（部分
/// 成熟的批量语义由 Favicon 与批量转换页自行映射 warning）。
@MainActor
enum ImageSaveOutcomeToasts {
    static func presentSingleOutput(_ outcome: ImageSaveOutcome, toastCenter: ToolToastCenter?) {
        switch outcome {
        case .saved:
            toastCenter?.show(ToolFeedbackCopy.savedFile, tone: .success)
        case let .failed(message):
            toastCenter?.show(message, tone: .error)
        case .cancelled, .blocked, .partiallySaved:
            break
        }
    }
}
