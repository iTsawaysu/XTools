import XToolsCore
import SwiftUI

@MainActor
final class ImageCompressorToolWorkspaceModel: ObservableObject, ToolWorkspacePayloadEvicting {
    static let key = ToolWorkspaceKey<ImageCompressorToolWorkspaceModel>(toolID: "image-tools", slot: "compressor") { preferences in
        ImageCompressorToolWorkspaceModel(preferences: preferences)
    }

    let session = ImageProcessedOutputSession()

    @Published var compressionPreference: ImageCompressionPreference {
        didSet { preferences.set(compressionPreference, for: MediaToolPreferenceKeys.imageCompressorPreference) }
    }
    @Published var limitsDimensions: Bool {
        didSet { preferences.set(limitsDimensions, for: MediaToolPreferenceKeys.imageCompressorLimitsDimensions) }
    }
    @Published var maxPixelLength: Int {
        didSet { preferences.set(maxPixelLength, for: MediaToolPreferenceKeys.imageCompressorMaxPixelLength) }
    }

    private let preferences: ToolPreferenceStore

    init(preferences: ToolPreferenceStore) {
        self.preferences = preferences
        compressionPreference = preferences.value(for: MediaToolPreferenceKeys.imageCompressorPreference)
        limitsDimensions = preferences.value(for: MediaToolPreferenceKeys.imageCompressorLimitsDimensions)
        maxPixelLength = preferences.value(for: MediaToolPreferenceKeys.imageCompressorMaxPixelLength)
    }

    func evictHeavyPayloads() {
        session.evictHeavyPayloads()
    }
}

struct IndexImageCompressorSegment: View {
    var body: some View {
        ToolWorkspaceHost(key: ImageCompressorToolWorkspaceModel.key) { workspace, bindings in
            IndexImageCompressorWorkspaceContent(
                session: workspace.session,
                compressionPreference: bindings.compressionPreference,
                limitsDimensions: bindings.limitsDimensions,
                maxPixelLength: bindings.maxPixelLength
            )
        }
    }
}

private struct IndexImageCompressorWorkspaceContent: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.fileInputPanelClient) private var fileInputPanelClient
    @Environment(\.fileOutputPanelClient) private var fileOutputPanelClient
    @Environment(\.toolToastCenter) private var toastCenter

    @ObservedObject var session: ImageProcessedOutputSession
    @Binding var compressionPreference: ImageCompressionPreference
    @Binding var limitsDimensions: Bool
    @Binding var maxPixelLength: Int
    @State private var isImageDropTargeted = false

    private var canSaveCompressed: Bool {
        compressedAssessment?.canSave == true
    }

    private var optimizedPreviewImage: NSImage? {
        canSaveCompressed ? session.outputImage : nil
    }

    private var previewPlaceholder: String {
        if compressedAssessment?.canSave == false {
            return ImageOutputPresentation.blockedCompressionMessage
        }
        return "选择图片后显示优化结果"
    }

    private var compressedAssessment: ImageOutputAssessment? {
        session.assessment(for: .compression)
    }

    var body: some View {
        IndexActionBar {
            IndexOptionGroup {
                IndexOptionLabel("优化偏好")
                IndexSegmentedControl(
                    items: ImageCompressionPreference.allCases.map { ($0, $0.displayName) },
                    selection: $compressionPreference,
                    selectionStyle: .filled
                )
                .onChange(of: compressionPreference) { _ in compress() }
            }

            IndexOptionGroup {
                IndexOptionSwitch(title: "限制尺寸", isOn: $limitsDimensions)
                    .onChange(of: limitsDimensions) { _ in compress() }
                if limitsDimensions {
                    Text("输出尺寸不超过")
                        .font(ToolTypography.label)
                        .foregroundStyle(ToolTheme.textSecondary)
                    IndexNumberInput(value: $maxPixelLength, range: 128...12000, fieldWidth: 62)
                        .accessibilityLabel("输出最大像素边长")
                        .onChange(of: maxPixelLength) { _ in compress() }
                    Text("px")
                        .font(ToolTypography.monoCaption)
                        .foregroundStyle(ToolTheme.textSecondary)
                }
            }
        }

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
            emptyStateTitle: "选择图片开始优化",
            actions: imageSelectionActions,
            onDropFile: receiveImageURL,
            onDropMultipleFiles: rejectMultipleImageDrop
        )
    }

    private var comparisonWorkspacePanel: some View {
        IndexPanel("优化工作区") {
            VStack(alignment: .leading, spacing: ToolMetrics.Spacing.md) {
                imageSelectionActions

                IndexPairLayout(collapseWidth: 0) {
                    IndexImageComparisonCard(
                        title: "原图",
                        image: session.sourceImage,
                        accessibilityLabel: "图片优化原图预览",
                        accessibilityValue: sourcePreviewAccessibilityValue,
                        placeholder: "等待原图预览"
                    ) {
                        sourceCardFacts
                    }
                } trailing: {
                    IndexImageComparisonCard(
                        title: "优化结果",
                        badgeText: compressionChangeText,
                        badgeTone: .neutral,
                        image: optimizedPreviewImage,
                        accessibilityLabel: "图片优化结果预览",
                        accessibilityValue: resultPreviewAccessibilityValue,
                        placeholder: previewPlaceholder,
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
            if canSaveCompressed {
                Button {
                    saveImage()
                } label: {
                    Label("保存", systemImage: IndexActionSymbol.save)
                        .font(ToolTypography.buttonSmall)
                }
                .buttonStyle(IndexSmallButtonStyle())
                .accessibilityLabel("保存优化图片")
            }
        }
        .verticallyFilling()
    }

    private var imageSelectionActions: ImageSelectionActionRow {
        ImageSelectionActionRow(
            hasSource: session.source != nil,
            selectAccessibilityLabel: "选择要优化的图片",
            replaceAccessibilityLabel: "更换要优化的图片",
            clearAccessibilityLabel: "清除当前优化图片",
            onSelect: selectImage,
            onClear: {
                withToolAnimation(ToolMotion.Preset.panelReveal, reduceMotion: reduceMotion) {
                    session.reset()
                }
            }
        )
    }

    private var sourceCardFacts: some View {
        HStack(spacing: 12) {
            Text("原始大小")
                .font(ToolTypography.caption)
                .foregroundStyle(ToolTheme.textSecondary)
            Spacer(minLength: 8)
            Text(sourceByteText)
                .font(ToolTypography.monoLabel)
                .foregroundStyle(ToolTheme.textPrimary)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var resultCardFacts: some View {
        if let compressedAssessment, compressedAssessment.canSave {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 12) {
                    Text("输出大小")
                        .font(ToolTypography.caption)
                        .foregroundStyle(ToolTheme.textSecondary)
                    Spacer(minLength: 8)
                    Text(ByteSizeFormatter.format(bytes: compressedAssessment.output.byteCount))
                        .font(ToolTypography.monoLabel)
                        .foregroundStyle(ImageOutputPresentation.color(for: compressedAssessment))
                }

                Text(ImageOutputPresentation.compressionStatus(compressedAssessment))
                    .font(ToolTypography.caption)
                    .foregroundStyle(ToolTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var sourceByteText: String {
        session.sourceMetadata.map { ByteSizeFormatter.format(bytes: $0.byteCount) } ?? "-"
    }

    private var compressionChangeText: String? {
        guard let compressedAssessment, compressedAssessment.canSave else { return nil }
        return ImageOutputPresentation.sizeChangeText(compressedAssessment)
    }

    private var sourcePreviewAccessibilityValue: String {
        "原始大小 \(sourceByteText)"
    }

    private var resultPreviewAccessibilityValue: String {
        if session.isProcessing {
            return "正在优化图片"
        }
        guard let compressedAssessment, compressedAssessment.canSave else {
            return previewPlaceholder
        }
        return "输出大小 \(ByteSizeFormatter.format(bytes: compressedAssessment.output.byteCount))，\(ImageOutputPresentation.compressionStatus(compressedAssessment))"
    }

    private var uploadInteractions: ImageUploadInteractions {
        ImageUploadInteractions(reduceMotion: reduceMotion)
    }

    private func selectImage() {
        session.selectImage(
            filePanel: fileInputPanelClient,
            allowedContentTypes: ImageWorkflowClient.standardImageContentTypes,
            operation: .compression,
            selectionPublisher: uploadInteractions.publishSelection,
            render: compressorRenderer()
        )
    }

    private func receiveImageURL(_ url: URL) {
        session.receiveImageURL(
            url,
            allowedContentTypes: ImageWorkflowClient.standardImageContentTypes,
            operation: .compression,
            selectionPublisher: uploadInteractions.publishSelection,
            render: compressorRenderer()
        )
    }

    private func rejectMultipleImageDrop() {
        uploadInteractions.rejectMultipleDrop {
            session.rejectImageInput(SingleFileDropResolver.multipleFilesDiagnostic)
        }
    }

    private func compress() {
        session.renderInBackground(operation: .compression, compressorRenderer())
    }

    private func compressorRenderer() -> ImageBackgroundOutputRenderer {
        let preference = compressionPreference
        let dimensionLimit = limitsDimensions ? maxPixelLength : nil
        let optimizer = AppImageOptimizer.make()

        return { selection in
            try ImageProcessor.compress(
                data: selection.data,
                sourceFilenameExtension: selection.filenameExtension,
                quality: preference.qualityUpperBound,
                minimumQuality: preference.qualityLowerBound,
                maxPixelLength: dimensionLimit,
                optimizer: optimizer
            )
        }
    }

    private func saveImage() {
        Task { @MainActor in
            let outcome = await session.save(workflow: .compression, defaultBasename: "compressed", filePanel: fileInputPanelClient, outputPanel: fileOutputPanelClient)
            ImageSaveOutcomeToasts.presentSingleOutput(outcome, toastCenter: toastCenter)
        }
    }
}
