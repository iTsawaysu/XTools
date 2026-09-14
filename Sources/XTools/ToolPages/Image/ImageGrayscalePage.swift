import XToolsCore
import SwiftUI

struct IndexImageGrayscalePage: View {
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
        IndexPage("图片灰阶生成器", subtitle: "将彩色图片转为灰度图。", workspaceSemantic: .imagePreviewStage) {
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
    }

    private var emptyUploadPanel: some View {
        IndexPanel("上传图片") {
            VStack(alignment: .leading, spacing: ToolMetrics.Spacing.md) {
                imageSelectionActions

                if session.isProcessing {
                    IndexProgressLabel(message: "正在读取图片…")
                        .foregroundStyle(ToolTheme.textSecondary)
                        .accessibilityLabel("正在读取图片")
                } else {
                    IndexEmptyState(
                        title: "选择图片开始生成灰度图",
                        systemImage: "photo.on.rectangle.angled",
                        message: IndexEmptyStateCopy.autoGenerate("图片"),
                        density: .list
                    )
                    .frame(maxWidth: .infinity, minHeight: 128)
                }
            }
            .indexWorkspaceDiagnostic(session.error)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, ToolMetrics.Spacing.sm)
            .indexDropZone(
                isTargeted: $isImageDropTargeted,
                onFile: receiveImageURL,
                onMultipleFiles: rejectMultipleImageDrop
            )
        }
        .verticallyFilling()
    }

    private var comparisonWorkspacePanel: some View {
        IndexPanel("灰阶工作区") {
            VStack(alignment: .leading, spacing: 12) {
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
                .help("保存灰度图")
            }
        }
        .verticallyFilling()
    }

    @ViewBuilder
    private var imageSelectionActions: some View {
        HStack(spacing: 8) {
            Button(action: selectImage) {
                Label(session.source == nil ? "选择图片" : "更换图片", systemImage: "photo")
                    .font(ToolTypography.buttonSmall)
            }
            .buttonStyle(IndexSmallButtonStyle())
            .accessibilityLabel(session.source == nil ? "选择要生成灰度图的图片" : "更换要生成灰度图的图片")

            if session.source != nil {
                Button {
                    withToolAnimation(ToolMotion.Preset.panelReveal, reduceMotion: reduceMotion) {
                        session.reset()
                    }
                } label: {
                    Label("清除图片", systemImage: IndexActionSymbol.removeResource)
                        .font(ToolTypography.buttonSmall)
                }
                .buttonStyle(IndexSmallButtonStyle())
                .accessibilityLabel("清除当前灰阶图片")
                .help("清除当前灰阶图片")
            }
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
        return "\(metadata.pixelWidth)×\(metadata.pixelHeight) · \(metadata.format?.displayName ?? "未知格式") · \(ByteSizeFormatter.format(bytes: metadata.byteCount))"
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
        if grayscaleAssessment?.requiresExplicitLargerSave == true {
            return "仍然保存更大的文件"
        }
        return "保存"
    }

    private func selectImage() {
        session.selectImage(
            filePanel: fileInputPanelClient,
            allowedContentTypes: ImageWorkflowClient.standardImageContentTypes,
            operation: .grayscale,
            selectionPublisher: publishSelectedImage,
            render: grayscaleRenderer()
        )
    }

    private func receiveImageURL(_ url: URL) {
        session.receiveImageURL(
            url,
            allowedContentTypes: ImageWorkflowClient.standardImageContentTypes,
            operation: .grayscale,
            selectionPublisher: publishSelectedImage,
            render: grayscaleRenderer()
        )
    }

    private func rejectMultipleImageDrop() {
        withToolAnimation(ToolMotion.Preset.panelReveal, reduceMotion: reduceMotion) {
            session.rejectImageInput(SingleFileDropResolver.multipleFilesDiagnostic)
        }
    }

    private func publishSelectedImage(_ selection: ImageInputSelection, _ publish: () -> Void) {
        withToolAnimation(ToolMotion.Preset.panelReveal, reduceMotion: reduceMotion) {
            publish()
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
            switch await session.save(workflow: .grayscale, defaultBasename: "grayscale", filePanel: fileInputPanelClient, outputPanel: fileOutputPanelClient) {
            case .saved:
                toastCenter?.show(ToolFeedbackCopy.savedFile, tone: .success)
            case let .failed(message):
                toastCenter?.show(message, tone: .error)
            case .cancelled, .blocked, .partiallySaved:
                break
            }
        }
    }
}


