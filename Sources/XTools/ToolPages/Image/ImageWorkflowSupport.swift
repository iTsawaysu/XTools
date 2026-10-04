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
        HStack(spacing: ToolMetrics.Spacing.sm) {
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
///
/// 空态用 `.list` 密度（图标 + 标题 + 共享文案），按 `fillsHeight` 垂直
/// 居中于输入面板剩余空间，构成完整拖放区观感——图片各页共用同一空态
/// 范式；水印页把文字输入与占位编组后居中，占位本身保持自然高度。
/// `onSelect` 是空态主操作（32pt 标准按钮，quiet-until-hover，不用实心
/// accent 以免在空面板里过于突兀），nil 时只呈现文案。
struct ImageUploadPendingState: View {
    let isProcessing: Bool
    let title: String
    var fillsHeight = false
    var onSelect: (() -> Void)? = nil

    var body: some View {
        if isProcessing {
            IndexProgressLabel(message: "正在读取图片…", alignment: .center)
                .accessibilityLabel("正在读取图片")
                .uploadPendingFrame(fillsHeight: fillsHeight)
        } else {
            VStack(spacing: ToolMetrics.Spacing.md) {
                IndexEmptyState(
                    title: title,
                    systemImage: "photo.on.rectangle.angled",
                    message: IndexEmptyStateCopy.autoGenerate("图片"),
                    density: .list
                )

                if let onSelect {
                    Button(action: onSelect) {
                        Label("选择图片", systemImage: "photo")
                    }
                    .buttonStyle(IndexButtonStyle())
                }
            }
            .uploadPendingFrame(fillsHeight: fillsHeight)
        }
    }
}

/// fillsHeight 时居中填充面板剩余空间；否则保持自然高度并给足最小高度。
private extension View {
    func uploadPendingFrame(fillsHeight: Bool) -> some View {
        self.frame(
            maxWidth: .infinity,
            minHeight: fillsHeight ? nil : 128,
            maxHeight: fillsHeight ? .infinity : nil,
            alignment: .center
        )
    }
}

/// 单输出页（压缩/灰度）的「上传图片」空态面板：居中的空态/源准备占位，
/// 面板内容即共享单文件拖放区（多文件整批拒绝）。有源后的「更换/清除」
/// 动作行由各页的工作区面板自带，空态面板只呈现居中主操作。
struct ImageUploadEmptyPanel: View {
    @Binding var isDropTargeted: Bool
    let isProcessing: Bool
    let diagnostic: String?
    let emptyStateTitle: String
    let onSelect: () -> Void
    private let onDropFile: (URL) -> Void
    private let onDropMultipleFiles: () -> Void

    init(
        isDropTargeted: Binding<Bool>,
        isProcessing: Bool,
        diagnostic: String?,
        emptyStateTitle: String,
        onSelect: @escaping () -> Void,
        onDropFile: @escaping (URL) -> Void,
        onDropMultipleFiles: @escaping () -> Void
    ) {
        self._isDropTargeted = isDropTargeted
        self.isProcessing = isProcessing
        self.diagnostic = diagnostic
        self.emptyStateTitle = emptyStateTitle
        self.onSelect = onSelect
        self.onDropFile = onDropFile
        self.onDropMultipleFiles = onDropMultipleFiles
    }

    var body: some View {
        IndexPanel("上传图片") {
            ImageUploadPendingState(
                isProcessing: isProcessing,
                title: emptyStateTitle,
                fillsHeight: true,
                onSelect: onSelect
            )
            .indexWorkspaceDiagnostic(diagnostic)
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

/// 保存结果的共享 toast 映射：成功只在确认保存后提示；写盘失败报
/// error；取消/阻止静默；单输出页对不可能出现的部分结果同样静默（部分
/// 成功的批量语义由计数映射降级为 warning）。
@MainActor
enum ImageSaveOutcomeToasts {
    /// 单输出/具名文件保存映射：`fileName` 非 nil 时提示保存的文件名
    /// （Favicon 单个部署文件），nil 时用通用「文件已保存」。
    static func presentSingleOutput(
        _ outcome: ImageSaveOutcome,
        fileName: String? = nil,
        toastCenter: ToolToastCenter?
    ) {
        switch outcome {
        case .saved:
            if let fileName {
                toastCenter?.show(ToolFeedbackCopy.saved(fileName: fileName), tone: .success)
            } else {
                toastCenter?.show(ToolFeedbackCopy.savedFile, tone: .success)
            }
        case let .failed(message):
            toastCenter?.show(message, tone: .error)
        case .cancelled, .blocked, .partiallySaved:
            break
        }
    }

    /// 计数保存（批量转换 / Favicon 整包）的共享映射：多件成功走计数词表，
    /// 单件成功与单输出页同词表；部分成功降级 warning 并保留安全计数。
    /// `successNoun` 不含量词（计数词表内部补「个」）；`partialNoun` 含量词
    /// （部分保存模板为「已保存 x/y <名词>。」直接拼接，模板内无量词）。
    static func presentCountedOutput(
        _ outcome: ImageSaveOutcome,
        savedCount: Int,
        successNoun: String = "文件",
        partialNoun: String,
        toastCenter: ToolToastCenter?
    ) {
        switch outcome {
        case .saved:
            if savedCount > 1 {
                toastCenter?.show(ToolFeedbackCopy.saved(count: savedCount, noun: successNoun), tone: .success)
            } else {
                toastCenter?.show(ToolFeedbackCopy.savedFile, tone: .success)
            }
        case let .partiallySaved(partiallySavedCount, totalCount):
            toastCenter?.show("已保存 \(partiallySavedCount)/\(totalCount) \(partialNoun)。", tone: .warning)
        case let .failed(message):
            toastCenter?.show(message, tone: .error)
        case .cancelled, .blocked:
            break
        }
    }
}
