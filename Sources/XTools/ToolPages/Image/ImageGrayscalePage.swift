import XToolsCore
import SwiftUI
import XToolsDesign

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

    private var grayscaleAssessment: ImageOutputAssessment? {
        session.assessment(for: .grayscale)
    }

    var body: some View {
        IndexImageCompareWorkbench(
            panelTitle: "灰阶工作区",
            resultTitle: "灰度图",
            emptyTitle: "选择图片开始生成灰度图",
            placeholder: "等待灰度图结果",
            selectLabel: "选择要生成灰度图的图片",
            replaceLabel: "更换要生成灰度图的图片",
            clearLabel: "清除当前灰阶图片",
            sourceImage: session.sourceImage,
            resultImage: session.outputImage,
            isProcessing: session.isProcessing,
            diagnostic: session.error,
            canSave: session.output != nil && !session.isProcessing,
            saveLabel: saveButtonTitle,
            onSelect: selectImage,
            onDropURL: receiveImageURL,
            onDropMultiple: rejectMultipleImageDrop,
            onClear: {
                withToolAnimation(ToolMotion.Preset.panelReveal, reduceMotion: reduceMotion) {
                    session.reset()
                }
            },
            onSave: saveImage
        ) {
            sourceCardFacts
        } resultFacts: {
            resultCardFacts
        }
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

