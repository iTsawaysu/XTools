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
    @Environment(\.toolToastCenter) private var toastCenter

    @ObservedObject var session: ImageProcessedOutputSession
    @State private var isImageDropTargeted = false

    private var grayscaleAssessment: ImageOutputAssessment? {
        session.assessment(for: .grayscale)
    }

    var body: some View {
        Group {
            if session.source == nil {
                emptyUploadPanel
                    .toolTransition(ToolMotion.Transition.modeContent, reduceMotion: reduceMotion)
            } else {
                comparisonWorkspacePanel
                    .toolTransition(ToolMotion.Transition.modeContent, reduceMotion: reduceMotion)
            }
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
        IndexPanel("灰阶工作区") {
            VStack(alignment: .leading, spacing: ToolMetrics.Spacing.md) {
                imageSelectionActions

                IndexPairLayout(collapseWidth: 0) {
                    IndexImageComparisonCard(
                        title: "原图",
                        image: session.sourceImage,
                        accessibilityLabel: "灰阶转换原图预览",
                        accessibilityValue: sourcePreviewAccessibilityValue,
                        placeholder: "等待原图预览"
                    ) {
                        sourceCardFacts
                    }
                } trailing: {
                    IndexImageComparisonCard(
                        title: "灰度图",
                        image: session.outputImage,
                        accessibilityLabel: "灰阶转换结果预览",
                        accessibilityValue: resultPreviewAccessibilityValue,
                        placeholder: "等待灰度图结果",
                        isProcessing: session.isProcessing
                    ) {
                        resultCardFacts
                    }
                }
            }
            .indexWorkspaceDiagnostic(session.error)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .indexDropZone(
                isTargeted: $isImageDropTargeted,
                onFile: receiveImageURL,
                onMultipleFiles: rejectMultipleImageDrop
            )
        } accessory: {
            if session.output != nil && !session.isProcessing {
                Button {
                    saveImage()
                } label: {
                    Label(saveButtonTitle, systemImage: IndexActionSymbol.save)
                        .font(ToolTypography.buttonSmall)
                }
                .buttonStyle(IndexSmallButtonStyle())
                .accessibilityLabel("保存灰度图")
            }
        }
        .verticallyFilling()
    }

    private var imageSelectionActions: ImageSelectionActionRow {
        ImageSelectionActionRow(
            hasSource: session.source != nil,
            selectAccessibilityLabel: "选择要生成灰度图的图片",
            replaceAccessibilityLabel: "更换要生成灰度图的图片",
            clearAccessibilityLabel: "清除当前灰阶图片",
            onSelect: selectImage,
            onClear: {
                withToolAnimation(ToolMotion.Preset.panelReveal, reduceMotion: reduceMotion) {
                    session.reset()
                }
            }
        )
    }

    private var sourceCardFacts: some View {
        Text(sourceSummary)
            .font(ToolTypography.caption)
            .foregroundStyle(ToolTheme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var resultCardFacts: some View {
        if let grayscaleAssessment {
            Text(ImageOutputPresentation.processingOutputSummary(grayscaleAssessment))
                .font(ToolTypography.caption)
                .foregroundStyle(grayscaleAssessment.requiresExplicitLargerSave ? ToolTheme.warning : ToolTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var sourceSummary: String {
        guard let metadata = session.sourceMetadata else { return "等待原图信息" }
        return ImageOutputPresentation.sourceSummary(metadata)
    }

    private var sourcePreviewAccessibilityValue: String {
        "原图，\(sourceSummary)"
    }

    private var resultPreviewAccessibilityValue: String {
        if session.isProcessing {
            return "正在生成灰度图"
        }
        guard let grayscaleAssessment else { return "等待灰度图结果" }
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
            let outcome = await session.save(workflow: .grayscale, defaultBasename: "grayscale", filePanel: fileInputPanelClient, outputPanel: fileOutputPanelClient)
            ImageSaveOutcomeToasts.presentSingleOutput(outcome, toastCenter: toastCenter)
        }
    }
}

