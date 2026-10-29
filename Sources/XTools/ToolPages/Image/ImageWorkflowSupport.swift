import AppKit
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
    /// 面板头内的动作行用描边底：38pt 头部里安静文字按钮会失去可点暗示。
    var framed = false

    var body: some View {
        HStack(spacing: ToolMetrics.Spacing.sm) {
            Button(action: onSelect) {
                Label(hasSource ? changeTitle : selectTitle, systemImage: "photo")
                    .font(ToolTypography.buttonSmall)
            }
            .buttonStyle(IndexSmallButtonStyle(framed: framed))
            .accessibilityLabel(hasSource ? replaceAccessibilityLabel : selectAccessibilityLabel)

            if hasSource {
                Button(action: onClear) {
                    Label(clearTitle, systemImage: IndexActionSymbol.removeResource)
                        .font(ToolTypography.buttonSmall)
                }
                .buttonStyle(IndexSmallButtonStyle(framed: framed))
                .accessibilityLabel(clearAccessibilityLabel)
            }
        }
    }
}

/// 源准备占位：读取中显示进度标签，否则显示共享图片空态。
///
/// 空态用 `.list` 密度（图标 + 标题 + 共享文案），图片各页共用同一空态
/// 范式；主操作由调用方另行装配（空态只用 IndexEmptyState，不内嵌按钮）。
struct ImageUploadPendingState: View {
    let isProcessing: Bool
    let title: String
    var message: String = IndexEmptyStateCopy.autoGenerate("图片")

    var body: some View {
        if isProcessing {
            IndexProgressLabel(message: "正在读取图片…", alignment: .center)
                .accessibilityLabel("正在读取图片")
        } else {
            IndexEmptyState(
                title: title,
                systemImage: "photo.on.rectangle.angled",
                message: message,
                density: .list
            )
        }
    }
}

/// 单输出页（压缩/灰度）的「上传图片」空态：无面板头的拖放井，井内居中
/// 呈现共享空态与唯一的实心主操作。空态本身不参与分栏，纵向吃满视口。
struct ImageUploadEmptyPanel: View {
    @Binding var isDropTargeted: Bool
    let isProcessing: Bool
    let diagnostic: String?
    let emptyStateTitle: String
    var emptyStateMessage = "拖入图片，或点击下方按钮。"
    let onSelect: () -> Void
    private let onDropFile: (URL) -> Void
    private let onDropMultipleFiles: () -> Void

    init(
        isDropTargeted: Binding<Bool>,
        isProcessing: Bool,
        diagnostic: String?,
        emptyStateTitle: String,
        emptyStateMessage: String = "拖入图片，或点击下方按钮。",
        onSelect: @escaping () -> Void,
        onDropFile: @escaping (URL) -> Void,
        onDropMultipleFiles: @escaping () -> Void
    ) {
        self._isDropTargeted = isDropTargeted
        self.isProcessing = isProcessing
        self.diagnostic = diagnostic
        self.emptyStateTitle = emptyStateTitle
        self.emptyStateMessage = emptyStateMessage
        self.onSelect = onSelect
        self.onDropFile = onDropFile
        self.onDropMultipleFiles = onDropMultipleFiles
    }

    var body: some View {
        IndexPanel("上传图片") {
            VStack(spacing: ToolMetrics.Spacing.lg) {
                ImageUploadPendingState(
                    isProcessing: isProcessing,
                    title: emptyStateTitle,
                    message: emptyStateMessage
                )

                if !isProcessing {
                    IndexPrimaryActionButton(
                        title: "选择图片",
                        systemImage: "photo",
                        help: "选择图片",
                        action: onSelect
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .background(
                ToolTheme.editorBackground,
                in: RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.control, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.control, style: .continuous)
                    .strokeBorder(
                        ToolTheme.strongBorder,
                        style: StrokeStyle(lineWidth: 1, dash: [6, 5])
                    )
            }
            .indexWorkspaceDiagnostic(diagnostic)
            .indexDropZone(
                isTargeted: $isDropTargeted,
                onFile: onDropFile,
                onMultipleFiles: onDropMultipleFiles
            )
        }
        .withoutHeader()
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

// MARK: - 设置栏 + 固定动作区

/// 检查器里的只读事实行：左侧标签，右侧等宽数值。
struct ImageInspectorFactRow: View {
    let label: String
    let value: String
    var valueTone: Color = ToolTheme.textPrimary

    var body: some View {
        HStack(spacing: ToolMetrics.Spacing.sm) {
            Text(label)
                .font(ToolTypography.caption)
                .foregroundStyle(ToolTheme.textSecondary)
            Spacer(minLength: 8)
            Text(value)
                .font(ToolTypography.monoLabel)
                .foregroundStyle(valueTone)
        }
        .frame(height: 22)
        .accessibilityElement(children: .combine)
    }
}

/// 图片页右侧检查器的共享骨架：可选「源文件」区与「输出」摘要区，设置项居中，
/// 主 CTA 与状态行收在底部分隔线以下。
///
/// 图片页是整页滚动（`imagePreviewStage` → `.scroll`）。独立使用时保持自然
/// 高度；与预览舞台并排、需要底边对齐时传 `pinsActionToBottom`：源文件与设置
/// 留在顶部，输出摘要与动作区贴住面板底部，由外层分栏给出的高度决定中间留白。
struct ImageWorkflowSettingsPanel<Settings: View, Source: View, Output: View>: View {
    let primaryTitle: String
    var primaryIcon: String? = nil
    let primaryHelp: String
    let isPrimaryDisabled: Bool
    let statusText: String?
    var statusTone: Color = ToolTheme.textTertiary
    var pinsActionToBottom = false
    var sourceTitle = "源文件"
    var actionSummary: String? = nil
    let onPrimary: () -> Void
    private let showsSourceSection: Bool
    private let showsSettingsSection: Bool
    private let showsOutputSection: Bool
    private let source: Source
    private let settings: Settings
    private let output: Output

    private init(
        primaryTitle: String,
        primaryIcon: String?,
        primaryHelp: String,
        isPrimaryDisabled: Bool,
        statusText: String?,
        statusTone: Color,
        pinsActionToBottom: Bool,
        sourceTitle: String,
        actionSummary: String?,
        onPrimary: @escaping () -> Void,
        showsSourceSection: Bool,
        showsSettingsSection: Bool,
        showsOutputSection: Bool,
        source: Source,
        settings: Settings,
        output: Output
    ) {
        self.primaryTitle = primaryTitle
        self.primaryIcon = primaryIcon
        self.primaryHelp = primaryHelp
        self.isPrimaryDisabled = isPrimaryDisabled
        self.statusText = statusText
        self.statusTone = statusTone
        self.pinsActionToBottom = pinsActionToBottom
        self.sourceTitle = sourceTitle
        self.actionSummary = actionSummary
        self.onPrimary = onPrimary
        self.showsSourceSection = showsSourceSection
        self.showsSettingsSection = showsSettingsSection
        self.showsOutputSection = showsOutputSection
        self.source = source
        self.settings = settings
        self.output = output
    }

    /// 检查器版：源文件标识与操作、设置项、输出摘要三段。
    /// `showsOutput` 供批量页在「队列」区已承载聚合输出时关掉重复的
    /// 输出摘要段（空段会留下孤立的分隔线与标题）。
    init(
        primaryTitle: String,
        primaryIcon: String? = nil,
        primaryHelp: String,
        isPrimaryDisabled: Bool,
        statusText: String? = nil,
        statusTone: Color = ToolTheme.textTertiary,
        pinsActionToBottom: Bool = false,
        sourceTitle: String = "源文件",
        actionSummary: String? = nil,
        showsOutput: Bool = true,
        onPrimary: @escaping () -> Void,
        @ViewBuilder source: () -> Source,
        @ViewBuilder settings: () -> Settings,
        @ViewBuilder output: () -> Output
    ) {
        self.init(
            primaryTitle: primaryTitle,
            primaryIcon: primaryIcon,
            primaryHelp: primaryHelp,
            isPrimaryDisabled: isPrimaryDisabled,
            statusText: statusText,
            statusTone: statusTone,
            pinsActionToBottom: pinsActionToBottom,
            sourceTitle: sourceTitle,
            actionSummary: actionSummary,
            onPrimary: onPrimary,
            showsSourceSection: true,
            showsSettingsSection: true,
            showsOutputSection: showsOutput,
            source: source(),
            settings: settings(),
            output: output()
        )
    }

    var body: some View {
        Group {
            if pinsActionToBottom {
                // 检查器：内容放得下时按自然高度从顶部顺排、动作区紧跟
                // 输出收口，不会在设置与输出之间裂出一道断层；内容超出
                // 页面给出的高度上限时才退回「设置区滚动 + 输出/动作吸底」，
                // 保证主 CTA 在 960×678 也不会被推出首屏。
                ViewThatFits(in: .vertical) {
                    compactInspector
                    pinnedInspector
                }
                .frame(maxHeight: .infinity, alignment: .top)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    if showsSourceSection {
                        sourceSectionBody
                        sectionDivider
                    }
                    if showsSettingsSection {
                        settingsSectionBody
                    }
                    if showsOutputSection {
                        sectionDivider
                        outputSectionBody
                    }
                    sectionDivider
                    actionSectionBody
                }
            }
        }
        .frame(maxHeight: pinsActionToBottom ? .infinity : nil, alignment: .top)
    }

    /// 自然高度版本：源文件、设置、输出从顶部顺排，动作区紧跟输出收口；
    /// 面板按内容定高（上限由页面传入），不会在设置与输出之间裂出断层，
    /// 按钮也不会悬在面板中间。
    private var compactInspector: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showsSourceSection {
                sourceSectionBody
                sectionDivider
            }
            if showsSettingsSection {
                settingsSectionBody
            }
            if showsOutputSection {
                sectionDivider
                outputSectionBody
            }
            sectionDivider
            actionSectionBody
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 溢出回退版本：设置区独立滚动，输出摘要与动作区固定在底部。
    private var pinnedInspector: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if showsSourceSection {
                        sourceSectionBody
                        sectionDivider
                    }
                    if showsSettingsSection {
                        settingsSectionBody
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: .infinity)

            if showsOutputSection {
                sectionDivider
                outputSectionBody
            }

            sectionDivider
            actionSectionBody
        }
    }

    private var sourceSectionBody: some View {
        VStack(alignment: .leading, spacing: ToolMetrics.Spacing.sm) {
            IndexOptionLabel(sourceTitle)
            source
        }
        .padding(.top, ToolMetrics.Spacing.base)
        .padding(.bottom, ToolMetrics.Spacing.base)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var settingsSectionBody: some View {
        VStack(alignment: .leading, spacing: ToolMetrics.Spacing.md) {
            settings
        }
        // Horizontal gutter belongs to the hosting IndexPanel: adding a
        // second inset here misaligns fields with the panel title by 14pt.
        .padding(.top, ToolMetrics.Spacing.md)
        .padding(.bottom, ToolMetrics.Spacing.base)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var outputSectionBody: some View {
        VStack(alignment: .leading, spacing: ToolMetrics.Spacing.sm) {
            IndexOptionLabel("输出")
            output
        }
        .padding(.top, ToolMetrics.Spacing.md)
        .padding(.bottom, ToolMetrics.Spacing.base)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var actionSectionBody: some View {
        VStack(alignment: .leading, spacing: ToolMetrics.Spacing.sm) {
            if let actionSummary {
                Text(actionSummary)
                    .font(ToolTypography.caption)
                    .foregroundStyle(ToolTheme.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            IndexPrimaryActionButton(
                title: primaryTitle,
                systemImage: primaryIcon,
                hint: "⌘S",
                help: primaryHelp,
                fillsWidth: true,
                shortcut: "s",
                action: onPrimary
            )
            .disabled(isPrimaryDisabled)

            if let statusText {
                Text(statusText)
                    .font(ToolTypography.caption)
                    .foregroundStyle(statusTone)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(statusText)
            }
        }
        .padding(.top, ToolMetrics.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var sectionDivider: some View {
        Rectangle()
            .fill(ToolTheme.border)
            .frame(height: 0.5)
    }
}

extension ImageWorkflowSettingsPanel where Output == EmptyView {
    /// 源文件 + 设置两段（水印这类没有额外输出事实的页面）。
    init(
        primaryTitle: String,
        primaryIcon: String? = nil,
        primaryHelp: String,
        isPrimaryDisabled: Bool,
        statusText: String? = nil,
        statusTone: Color = ToolTheme.textTertiary,
        pinsActionToBottom: Bool = false,
        sourceTitle: String = "源文件",
        actionSummary: String? = nil,
        onPrimary: @escaping () -> Void,
        @ViewBuilder source: () -> Source,
        @ViewBuilder settings: () -> Settings
    ) {
        self.init(
            primaryTitle: primaryTitle,
            primaryIcon: primaryIcon,
            primaryHelp: primaryHelp,
            isPrimaryDisabled: isPrimaryDisabled,
            statusText: statusText,
            statusTone: statusTone,
            pinsActionToBottom: pinsActionToBottom,
            sourceTitle: sourceTitle,
            actionSummary: actionSummary,
            onPrimary: onPrimary,
            showsSourceSection: true,
            showsSettingsSection: true,
            showsOutputSection: false,
            source: source(),
            settings: settings(),
            output: EmptyView()
        )
    }
}

extension ImageWorkflowSettingsPanel where Settings == EmptyView {
    /// 源文件 + 输出两段（Favicon 这类没有可调参数的页面）。
    init(
        primaryTitle: String,
        primaryIcon: String? = nil,
        primaryHelp: String,
        isPrimaryDisabled: Bool,
        statusText: String? = nil,
        statusTone: Color = ToolTheme.textTertiary,
        pinsActionToBottom: Bool = false,
        sourceTitle: String = "源文件",
        actionSummary: String? = nil,
        onPrimary: @escaping () -> Void,
        @ViewBuilder source: () -> Source,
        @ViewBuilder output: () -> Output
    ) {
        self.init(
            primaryTitle: primaryTitle,
            primaryIcon: primaryIcon,
            primaryHelp: primaryHelp,
            isPrimaryDisabled: isPrimaryDisabled,
            statusText: statusText,
            statusTone: statusTone,
            pinsActionToBottom: pinsActionToBottom,
            sourceTitle: sourceTitle,
            actionSummary: actionSummary,
            onPrimary: onPrimary,
            showsSourceSection: true,
            showsSettingsSection: false,
            showsOutputSection: true,
            source: source(),
            settings: EmptyView(),
            output: output()
        )
    }
}

extension ImageWorkflowSettingsPanel where Source == EmptyView, Output == EmptyView {
    /// 仅设置项的既有形态（水印/转换/灰度迁移前继续使用）。
    init(
        primaryTitle: String,
        primaryIcon: String? = nil,
        primaryHelp: String,
        isPrimaryDisabled: Bool,
        statusText: String? = nil,
        statusTone: Color = ToolTheme.textTertiary,
        pinsActionToBottom: Bool = false,
        onPrimary: @escaping () -> Void,
        @ViewBuilder settings: () -> Settings
    ) {
        self.init(
            primaryTitle: primaryTitle,
            primaryIcon: primaryIcon,
            primaryHelp: primaryHelp,
            isPrimaryDisabled: isPrimaryDisabled,
            statusText: statusText,
            statusTone: statusTone,
            pinsActionToBottom: pinsActionToBottom,
            sourceTitle: "源文件",
            actionSummary: nil,
            onPrimary: onPrimary,
            showsSourceSection: false,
            showsSettingsSection: true,
            showsOutputSection: false,
            source: EmptyView(),
            settings: settings(),
            output: EmptyView()
        )
    }
}
