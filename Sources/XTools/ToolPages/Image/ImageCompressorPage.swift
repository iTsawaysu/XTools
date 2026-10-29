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
    @Environment(\.pageAvailableHeight) private var pageAvailableHeight

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

    /// 舞台高度吃掉窗口剩余高度：左预览与右检查器在 960×678 与 1200×800
    /// 下都收在首屏内，底边留出与页面下边距一致的呼吸位。
    private var comparisonStageHeight: CGFloat {
        max(320, pageAvailableHeight - 196)
    }

    var body: some View {
        // 空态不参与分栏：设置栏此时不存在，对半分会把上传区压成半宽。
        if session.source == nil {
            emptyUploadPanel
        } else {
            IndexPairLayout(
                collapseWidth: ToolMetrics.Breakpoint.pairCollapseImageTools,
                fillsHeight: false,
                equalizesHeight: true,
                trailingWidth: 245
            ) {
                comparisonWorkspacePanel
            } trailing: {
                IndexPanel("压缩设置") {
                    ImageWorkflowSettingsPanel(
                        primaryTitle: "保存优化图片",
                        primaryIcon: IndexActionSymbol.save,
                        primaryHelp: session.isSaving ? "正在保存图片" : "保存优化图片",
                        isPrimaryDisabled: !canSaveCompressed || session.isSaving || session.isProcessing,
                        statusText: compressionStatusText,
                        statusTone: compressedAssessment?.canSave == false ? ToolTheme.warning : ToolTheme.textTertiary,
                        pinsActionToBottom: true,
                        onPrimary: saveImage,
                        source: { sourceSection },
                        settings: { compressionSettings },
                        output: { outputSection }
                    )
                }
                .withoutDiagnosticStatusSlot()
                .verticallyFilling()
            }
        }
    }

    /// 检查器「源文件」区：文件名、尺寸与格式，以及更换/清除动作。
    private var sourceSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(sourceFileName)
                .font(ToolTypography.bodyMedium)
                .foregroundStyle(ToolTheme.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)

            Text(sourceMetaText)
                .font(ToolTypography.caption)
                .foregroundStyle(ToolTheme.textTertiary)
                .lineLimit(1)
                .padding(.top, ToolMetrics.Spacing.xs)

            imageSelectionActions
                .padding(.top, ToolMetrics.Spacing.sm)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 检查器「输出」区：只列结果侧的事实，体积与节省比例留在舞台脚注。
    private var outputSection: some View {
        VStack(spacing: 0) {
            ImageInspectorFactRow(label: "格式", value: resultFormatText)
            ImageInspectorFactRow(label: "尺寸", value: resultDimensionsText)
            ImageInspectorFactRow(label: "实际质量", value: resultQualityText)
        }
    }

    /// 设置栏内容：优化偏好与尺寸限制。
    private var compressionSettings: some View {
        VStack(alignment: .leading, spacing: ToolMetrics.Spacing.lg) {
            VStack(alignment: .leading, spacing: ToolMetrics.Spacing.sm) {
                IndexOptionLabel("优化偏好")
                IndexSegmentedControl(
                    items: ImageCompressionPreference.allCases.map { ($0, $0.displayName) },
                    selection: $compressionPreference,
                    selectionStyle: .filled,
                    stretchesToFill: true
                )
                .onChange(of: compressionPreference) { _ in compress() }
            }

            VStack(alignment: .leading, spacing: ToolMetrics.Spacing.sm) {
                IndexOptionSwitch(title: "限制尺寸", isOn: $limitsDimensions)
                    .onChange(of: limitsDimensions) { _ in compress() }
                if limitsDimensions {
                    HStack(spacing: 6) {
                        Text("输出尺寸不超过")
                            .font(ToolTypography.caption)
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
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 只有在结果不可保存时才占用状态行；正常结果的体积、格式与质量已经
    /// 落在脚注和输出摘要里，不在这里重复第二遍。
    private var compressionStatusText: String? {
        guard session.source != nil, !session.isProcessing, let compressedAssessment else { return nil }
        return compressedAssessment.canSave
            ? nil
            : "未生成更小文件，试试「更小体积」或限制尺寸。"
    }

    private var emptyUploadPanel: some View {
        ImageUploadEmptyPanel(
            isDropTargeted: $isImageDropTargeted,
            isProcessing: session.isProcessing,
            diagnostic: session.error,
            emptyStateTitle: "选择图片开始优化",
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
                    accessibilityLabel: "图片优化原图预览",
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
                    title: "优化结果",
                    badgeText: compressionChangeText,
                    badgeTone: compressionChangeTone,
                    image: optimizedPreviewImage,
                    accessibilityLabel: "图片优化结果预览",
                    accessibilityValue: resultPreviewAccessibilityValue,
                    placeholder: previewPlaceholder,
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
            },
            framed: true
        )
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
        }
        .accessibilityElement(children: .combine)
    }

    private var sourceByteText: String {
        session.sourceMetadata.map { ByteSizeFormatter.format(bytes: $0.byteCount) } ?? "-"
    }

    private var sourceFileName: String {
        session.source?.url.lastPathComponent ?? "—"
    }

    private var sourceMetaText: String {
        guard let metadata = session.sourceMetadata else { return "—" }
        let format = metadata.format?.displayName ?? "未知格式"
        return "\(metadata.pixelWidth)×\(metadata.pixelHeight) · \(format)"
    }

    private var resultByteText: String {
        guard let compressedAssessment, compressedAssessment.canSave else { return "—" }
        return ByteSizeFormatter.format(bytes: compressedAssessment.output.byteCount)
    }

    private var resultByteTone: Color {
        guard let compressedAssessment, compressedAssessment.canSave else { return ToolTheme.textTertiary }
        return ImageOutputPresentation.color(for: compressedAssessment)
    }

    private var resultFormatText: String {
        guard let compressedAssessment, compressedAssessment.canSave else { return "—" }
        return compressedAssessment.output.format.displayName
    }

    private var resultDimensionsText: String {
        guard let compressedAssessment, compressedAssessment.canSave else { return "—" }
        let output = compressedAssessment.output
        return "\(output.pixelWidth)×\(output.pixelHeight)"
    }

    private var resultQualityText: String {
        guard let compressedAssessment, compressedAssessment.canSave,
              let quality = compressedAssessment.output.quality else { return "—" }
        return "\(Int(quality * 100))%"
    }

    private var compressionChangeText: String? {
        guard let compressedAssessment, compressedAssessment.canSave else { return nil }
        return ImageOutputPresentation.sizeChangeText(compressedAssessment)
    }

    private var compressionChangeTone: IndexBadgeTone {
        compressedAssessment?.severity == .success ? .success : .warning
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
            renderProvider: compressorRenderer,
            render: compressorRenderer()
        )
    }

    private func receiveImageURL(_ url: URL) {
        session.receiveImageURL(
            url,
            allowedContentTypes: ImageWorkflowClient.standardImageContentTypes,
            operation: .compression,
            selectionPublisher: uploadInteractions.publishSelection,
            renderProvider: compressorRenderer,
            render: compressorRenderer()
        )
    }

    private func rejectMultipleImageDrop() {
        uploadInteractions.rejectMultipleDrop {
            session.rejectImageInput(SingleFileDropResolver.multipleFilesDiagnostic)
        }
    }

    private func compress() {
        guard session.source != nil else { return }
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
            let outcome = await session.save(workflow: .compression, defaultBasename: OutputFileNaming.timestampedBase(source: session.source?.url.lastPathComponent, fallback: "compressed"), filePanel: fileInputPanelClient, outputPanel: fileOutputPanelClient)
            ImageSaveOutcomeToasts.presentSingleOutput(outcome, toastCenter: toastCenter)
        }
    }
}
