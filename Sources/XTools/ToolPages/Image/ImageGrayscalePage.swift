import XToolsCore
import SwiftUI

struct IndexImageGrayscaleSegment: View {
    var body: some View {
        ToolWorkspaceHost(key: ImageProcessedOutputSession.grayscaleWorkspaceKey) { session, _ in
            IndexImageGrayscaleWorkspaceContent(session: session)
        }
    }
}

private struct IndexImageGrayscaleWorkspaceContent: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.fileInputPanelClient) private var fileInputPanelClient
    @Environment(\.fileOutputPanelClient) private var fileOutputPanelClient
    @Environment(\.toolToastCenter) private var toolToastCenter
    @Environment(\.pageAvailableHeight) private var pageAvailableHeight

    /// 检查器按内容收口，但不越过舞台高度；内容超出时由面板内部滚动
    /// 并保持主 CTA 吸底。
    private var inspectorMaxHeight: CGFloat {
        max(320, pageAvailableHeight - 118)
    }


    @ObservedObject var session: ImageProcessedOutputSession
    @State private var isImageDropTargeted = false

    private var grayscaleAssessment: ImageOutputAssessment? {
        session.assessment(for: .grayscale)
    }

    /// 与压缩页同一舞台高度：预览与检查器在最小窗口与宽窗下都收在首屏内。
    private var comparisonStageHeight: CGFloat {
        max(320, pageAvailableHeight - 196)
    }

    private var sourceFormatBadge: String? {
        session.sourceMetadata?.format?.displayName
    }

    var body: some View {
        // 空态不参与分栏：设置栏此时不存在，对半分会把上传区压成半宽。
        if session.source == nil {
            emptyUploadPanel
        } else {
            IndexPairLayout(
                collapseWidth: ToolMetrics.Breakpoint.pairCollapseImageTools,
                fillsHeight: false,
                equalizesHeight: false,
                trailingWidth: 245
            ) {
                comparisonWorkspacePanel
            } trailing: {
                IndexPanel("灰度设置", accessory: {
                    if let badge = sourceFormatBadge {
                        IndexBadge(badge, tone: .neutral, isCapsule: true)
                    }
                }) {
                    ImageWorkflowSettingsPanel(
                        primaryTitle: saveButtonTitle,
                        primaryIcon: IndexActionSymbol.save,
                        primaryHelp: session.isSaving ? "正在保存图片" : "保存灰度图",
                        isPrimaryDisabled: session.output == nil || session.isProcessing || session.isSaving,
                        pinsActionToBottom: true,
                        onPrimary: saveImage,
                        source: { sourceSection },
                        settings: { grayscaleNote },
                        output: { outputSection }
                    )
                }
                .withoutDiagnosticStatusSlot()
                .frame(maxHeight: inspectorMaxHeight)
            }
        }
    }

    private var grayscaleNote: some View {
        Text("灰度图保留原尺寸与格式，不做额外压缩。")
            .font(ToolTypography.caption)
            .foregroundStyle(ToolTheme.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 检查器「源文件」区：文件名与元信息一行，更换/清除收在行尾。
    private var sourceSection: some View {
        ImageInspectorSourceRow(
            title: sourceFileName,
            subtitle: sourceMetaText,
            replaceAccessibilityLabel: "更换要生成灰度图的图片",
            clearAccessibilityLabel: "清除当前灰阶图片",
            onReplace: selectImage,
            onClear: {
                withToolAnimation(ToolMotion.Preset.panelReveal, reduceMotion: reduceMotion) {
                    session.reset()
                }
            }
        )
    }

    /// 检查器「输出」区：格式、尺寸与体积变化；绝对体积留在舞台脚注。
    private var outputSection: some View {
        VStack(spacing: 0) {
            ImageInspectorFactRow(label: "格式", value: resultFormatText)
            ImageInspectorFactRow(label: "尺寸", value: resultDimensionsText)
            ImageInspectorFactRow(
                label: "体积变化",
                value: resultChangeText,
                valueTone: resultChangeTone
            )
        }
    }

    private var emptyUploadPanel: some View {
        ImageUploadEmptyPanel(
            isDropTargeted: $isImageDropTargeted,
            isProcessing: session.isProcessing,
            diagnostic: session.error,
            emptyStateTitle: "选择图片开始生成灰度图",
            onSelect: selectImage,
            onDropFile: receiveImageURL,
            onDropMultipleFiles: rejectMultipleImageDrop
        )
    }

    private var comparisonWorkspacePanel: some View {
        IndexPanel("预览") {
            HStack(spacing: 0) {
                IndexImageComparisonPane(
                    title: "原图",
                    image: session.sourceImage,
                    accessibilityLabel: "灰阶转换原图预览",
                    accessibilityValue: sourcePreviewAccessibilityValue,
                    placeholder: "等待原图预览",
                    stageHeight: comparisonStageHeight
                ) {
                    sourceCardFacts
                }

                Rectangle()
                    .fill(ToolTheme.border)
                    .frame(width: 0.5)

                IndexImageComparisonPane(
                    title: "灰度图",
                    image: session.outputImage,
                    accessibilityLabel: "灰阶转换结果预览",
                    accessibilityValue: resultPreviewAccessibilityValue,
                    placeholder: "等待灰度图结果",
                    isProcessing: session.isProcessing,
                    stageHeight: comparisonStageHeight
                ) {
                    resultCardFacts
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .indexWorkspaceDiagnostic(session.error)
            .indexDropZone(
                isTargeted: $isImageDropTargeted,
                onFile: receiveImageURL,
                onMultipleFiles: rejectMultipleImageDrop
            )
        }
        .contentInsets(EdgeInsets())
    }

    private var sourceCardFacts: some View {
        HStack(spacing: ToolMetrics.Spacing.sm) {
            Text("原始大小")
                .font(ToolTypography.caption)
                .foregroundStyle(ToolTheme.textSecondary)
            Spacer(minLength: 8)
            Text(sourceByteText)
                .font(ToolTypography.monoLabel)
                .foregroundStyle(ToolTheme.textPrimary)
                .toolNumericTransition(value: sourceByteText)
        }
        .accessibilityElement(children: .combine)
    }

    private var resultCardFacts: some View {
        HStack(spacing: ToolMetrics.Spacing.sm) {
            Text("输出大小")
                .font(ToolTypography.caption)
                .foregroundStyle(ToolTheme.textSecondary)
            Spacer(minLength: 8)
            Text(resultByteText)
                .font(ToolTypography.monoLabel)
                .foregroundStyle(resultByteTone)
                .toolNumericTransition(value: resultByteText)
        }
        .accessibilityElement(children: .combine)
    }

    private var sourceByteText: String {
        session.sourceMetadata.map { ByteSizeFormatter.format(bytes: $0.byteCount) } ?? "—"
    }

    private var sourceFileName: String {
        session.source?.url.lastPathComponent ?? "—"
    }

    private var sourceMetaText: String {
        guard let metadata = session.sourceMetadata else { return "—" }
        return ImageOutputPresentation.sourceSummary(metadata)
    }

    private var resultByteText: String {
        guard let grayscaleAssessment else { return "—" }
        return ByteSizeFormatter.format(bytes: grayscaleAssessment.output.byteCount)
    }

    private var resultByteTone: Color {
        guard let grayscaleAssessment else { return ToolTheme.textTertiary }
        return grayscaleAssessment.requiresExplicitLargerSave ? ToolTheme.warning : ToolTheme.textPrimary
    }

    private var resultFormatText: String {
        grayscaleAssessment?.output.format.displayName ?? "—"
    }

    private var resultDimensionsText: String {
        guard let output = grayscaleAssessment?.output else { return "—" }
        return "\(output.pixelWidth)×\(output.pixelHeight)"
    }

    private var resultChangeText: String {
        guard let grayscaleAssessment else { return "—" }
        return ImageOutputPresentation.sizeChangeText(grayscaleAssessment)
    }

    private var resultChangeTone: Color {
        guard let grayscaleAssessment else { return ToolTheme.textTertiary }
        return grayscaleAssessment.sizeDeltaPercent <= 0 ? ToolTheme.success : ToolTheme.warning
    }

    private var sourcePreviewAccessibilityValue: String {
        "原始大小 \(sourceByteText)"
    }

    private var resultPreviewAccessibilityValue: String {
        if session.isProcessing {
            return "正在生成灰度图"
        }
        guard let grayscaleAssessment else {
            return "等待灰度图结果"
        }
        return ImageOutputPresentation.processingOutputSummary(grayscaleAssessment)
    }

    private var saveButtonTitle: String {
        ImageOutputPresentation.saveTitle(
            requiresExplicitLargerSave: grayscaleAssessment?.requiresExplicitLargerSave == true,
            fallback: "保存"
        )
    }

    private var uploadInteractions: ImageUploadInteractions {
        ImageUploadInteractions(reduceMotion: reduceMotion)
    }

    private func selectImage() {
        session.selectImage(
            filePanel: fileInputPanelClient,
            allowedContentTypes: ImageWorkflowClient.standardImageContentTypes,
            operation: .grayscale,
            selectionPublisher: uploadInteractions.publishSelection,
            render: grayscaleRenderer()
        )
    }

    private func receiveImageURL(_ url: URL) {
        session.receiveImageURL(
            url,
            allowedContentTypes: ImageWorkflowClient.standardImageContentTypes,
            operation: .grayscale,
            selectionPublisher: uploadInteractions.publishSelection,
            render: grayscaleRenderer()
        )
    }

    private func rejectMultipleImageDrop() {
        uploadInteractions.rejectMultipleDrop {
            session.rejectImageInput(SingleFileDropResolver.multipleFilesDiagnostic)
        }
    }

    private func grayscaleRenderer() -> ImageBackgroundOutputRenderer {
        { selection in
            try ImageProcessor.grayscale(
                data: selection.data,
                sourceFilenameExtension: selection.filenameExtension,
                outputFormat: nil,
                quality: ImageProcessor.highFidelityEncodingQuality
            )
        }
    }

    private func saveImage() {
        Task { @MainActor in
            let outcome = await session.save(workflow: .grayscale, defaultBasename: OutputFileNaming.timestampedBase(source: session.source?.url.lastPathComponent, fallback: "grayscale"), filePanel: fileInputPanelClient, outputPanel: fileOutputPanelClient)
            ImageSaveOutcomeToasts.presentSingleOutput(outcome, toastCenter: toolToastCenter)
        }
    }
}
