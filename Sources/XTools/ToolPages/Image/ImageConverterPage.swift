import XToolsCore
import SwiftUI

@MainActor
final class ImageConverterToolWorkspaceModel: ObservableObject, ToolWorkspacePayloadEvicting {
    static let key = ToolWorkspaceKey<ImageConverterToolWorkspaceModel>(toolID: "image-converter") { preferences in
        ImageConverterToolWorkspaceModel(preferences: preferences)
    }

    let session = ImageProcessedOutputSession()

    @Published var targetFormat: ImageFileFormat {
        didSet { preferences.set(targetFormat, for: MediaToolPreferenceKeys.imageConverterTargetFormat) }
    }
    @Published var quality: Double {
        didSet { preferences.set(quality, for: MediaToolPreferenceKeys.imageConverterQuality) }
    }
    @Published var transparencyFillMode: ImageTransparencyFillMode {
        didSet {
            preferences.set(
                transparencyFillMode,
                for: MediaToolPreferenceKeys.imageConverterTransparencyFillMode
            )
        }
    }
    @Published var customTransparencyFillHex: String {
        didSet {
            guard let color = ImageRGBColor(hex: customTransparencyFillHex) else { return }
            preferences.set(
                color.hexString,
                for: MediaToolPreferenceKeys.imageConverterCustomTransparencyFillHex
            )
        }
    }

    var transparencyFill: ImageRGBColor? {
        transparencyFillMode.color(customHex: customTransparencyFillHex)
    }

    private let preferences: ToolPreferenceStore

    init(preferences: ToolPreferenceStore) {
        self.preferences = preferences
        targetFormat = preferences.value(for: MediaToolPreferenceKeys.imageConverterTargetFormat)
        quality = preferences.value(for: MediaToolPreferenceKeys.imageConverterQuality)
        transparencyFillMode = preferences.value(for: MediaToolPreferenceKeys.imageConverterTransparencyFillMode)
        customTransparencyFillHex = preferences.value(for: MediaToolPreferenceKeys.imageConverterCustomTransparencyFillHex)
    }

    func evictHeavyPayloads() {
        session.evictHeavyPayloads()
    }
}

struct IndexImageConverterPage: View {
    var body: some View {
        ToolWorkspaceHost(key: ImageConverterToolWorkspaceModel.key) { workspace, bindings in
            IndexImageConverterWorkspaceContent(
                session: workspace.session,
                targetFormat: bindings.targetFormat,
                quality: bindings.quality,
                transparencyFillMode: bindings.transparencyFillMode,
                customTransparencyFillHex: bindings.customTransparencyFillHex
            )
        }
    }
}

private struct IndexImageConverterWorkspaceContent: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.fileInputPanelClient) private var fileInputPanelClient
    @Environment(\.fileOutputPanelClient) private var fileOutputPanelClient
    @Environment(\.toolToastCenter) private var toastCenter

    @ObservedObject var session: ImageProcessedOutputSession
    @Binding var targetFormat: ImageFileFormat
    @Binding var quality: Double
    @Binding var transparencyFillMode: ImageTransparencyFillMode
    @Binding var customTransparencyFillHex: String
    @State private var isImageDropTargeted = false

    private var convertedAssessment: ImageOutputAssessment? {
        session.assessment(for: .conversion)
    }

    private var outputFormats: [ImageFileFormat] {
        guard let metadata = session.sourceMetadata else { return [] }
        return ImageFileFormat.conversionTargetFormats(
            sourceFormat: metadata.format
        )
    }

    private var canConvert: Bool {
        session.sourceMetadata != nil
            && outputFormats.contains(targetFormat)
            && (!requiresTransparencyFill || selectedTransparencyFill != nil)
    }

    private var requiresTransparencyFill: Bool {
        guard let metadata = session.sourceMetadata else { return false }
        return metadata.transparency != .opaque && !targetFormat.preservesAlpha
    }

    private var selectedTransparencyFill: ImageRGBColor? {
        transparencyFillMode.color(customHex: customTransparencyFillHex)
    }

    var body: some View {
        IndexPage("图片格式转换", subtitle: "把图片另存为不同格式；不用于压缩体积。", workspaceSemantic: .imagePreviewStage) {
            IndexActionBar {
                IndexOptionGroup {
                    IndexOptionLabel("目标格式")
                    if outputFormats.isEmpty {
                        Text(session.sourceMetadata == nil ? "选择图片后显示" : "无可转换目标")
                            .font(ToolTypography.caption)
                            .foregroundStyle(ToolTheme.textSecondary)
                            .fixedSize(horizontal: true, vertical: false)
                    } else {
                        IndexInlinePicker(
                            items: outputFormats.map { ($0, $0.displayName) },
                            selection: $targetFormat
                        )
                        .accessibilityLabel("目标格式")
                        .accessibilityValue(targetFormat.displayName)
                        .help("选择输出格式")
                        .onChange(of: targetFormat) { _ in
                            applyDefaultQualityForTarget()
                            convert()
                        }
                    }
                }

                if canConvert && targetFormat.supportsLossyQuality {
                    IndexOptionGroup {
                        IndexOptionLabel("质量")
                        IndexSlider(value: $quality, range: 0.1...1.0, step: 0)
                            .frame(width: 160)
                            .accessibilityLabel("转换质量")
                            .accessibilityValue("\(Int(quality * 100))%")
                            .onChange(of: quality) { _ in convert() }
                        Text("\(Int(quality * 100))%")
                            .font(ToolTypography.monoCaption)
                            .foregroundStyle(ToolTheme.textSecondary)
                            .frame(width: 40)
                    }
                }

                if requiresTransparencyFill {
                    IndexOptionGroup {
                        IndexOptionLabel("透明填充")
                        IndexInlinePicker(
                            items: [
                                (ImageTransparencyFillMode.white, "白色"),
                                (.black, "黑色"),
                                (.custom, "自定义")
                            ],
                            selection: $transparencyFillMode
                        )
                        .accessibilityLabel("透明区域填充颜色")
                        .accessibilityValue(transparencyFillAccessibilityValue)
                        .help("选择转换前用于填充透明像素的颜色")
                        .onChange(of: transparencyFillMode) { _ in convert() }

                        if transparencyFillMode == .custom {
                            IndexTextInput(
                                placeholder: "#RRGGBB",
                                text: $customTransparencyFillHex,
                                height: 30,
                                alignment: .center,
                                selectAllOnFocus: true,
                                onSubmit: normalizeCustomTransparencyFillHex
                            )
                            .frame(width: 92)
                            .accessibilityLabel("自定义透明区域填充颜色")
                            .accessibilityValue(customTransparencyFillAccessibilityValue)
                            .help("输入十六进制颜色")
                            .onChange(of: customTransparencyFillHex) { _ in convert() }
                        }
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel("透明区域填充颜色")
                    .accessibilityValue(transparencyFillAccessibilityValue)
                    .help("JPEG 和 HEIC 不支持透明区域；请选择转换前用于填充透明像素的颜色。")
                }

            }

            IndexPanel("上传图片") {
                VStack(alignment: .leading, spacing: ToolMetrics.Spacing.md) {
                    imageSelectionActions

                    if session.sourceImage != nil {
                        IndexImagePreviewStage(
                            image: session.sourceImage,
                            accessibilityLabel: "待转换的原图",
                            maxDisplayWidth: 560,
                            maxDisplayHeight: 260,
                            spacing: ToolMetrics.Spacing.md
                        ) {
                            if let sourceMetadata = session.sourceMetadata {
                                Text("原图: \(sourceMetadata.pixelWidth)×\(sourceMetadata.pixelHeight) · \(sourceMetadata.format?.displayName ?? "未知格式") · \(ByteSizeFormatter.format(bytes: sourceMetadata.byteCount))")
                                    .font(ToolTypography.caption)
                                    .foregroundStyle(ToolTheme.textSecondary)
                            }

                            if session.isProcessing {
                                IndexProgressSpinner()
                            }

                            if let convertedAssessment {
                                Text("输出: \(ImageOutputPresentation.processingOutputSummary(convertedAssessment))\(transparencyFillOutputSuffix)")
                                    .font(ToolTypography.caption)
                                    .foregroundStyle(convertedAssessment.requiresExplicitLargerSave ? ToolTheme.warning : ToolTheme.textSecondary)
                            }

                            Button {
                                saveConverted()
                            } label: {
                                Label(saveButtonTitle, systemImage: IndexActionSymbol.save)
                                    .font(ToolTypography.buttonSmall)
                            }
                            .buttonStyle(IndexSmallButtonStyle())
                            .disabled(session.output == nil || session.isProcessing)
                        }
                    } else if session.isProcessing {
                        IndexProgressLabel(message: "正在读取图片…")
                            .foregroundStyle(ToolTheme.textSecondary)
                            .accessibilityLabel("正在读取图片")
                    } else {
                        IndexEmptyState(
                            title: "选择图片开始转换",
                            systemImage: "photo.on.rectangle.angled",
                            message: IndexEmptyStateCopy.autoGenerate("图片"),
                            density: .list
                        )
                        .frame(maxWidth: .infinity, minHeight: 128)
                    }
                }
                .indexWorkspaceDiagnostic(session.error)
                .frame(maxWidth: .infinity)
                .padding(.vertical, ToolMetrics.Spacing.sm)
                .indexDropZone(
                    isTargeted: $isImageDropTargeted,
                    onFile: receiveImageURL,
                    onMultipleFiles: rejectMultipleImageDrop
                )
            }
            .verticallyFilling()
        }
        .onAppear(perform: ensureSupportedTargetFormat)
    }

    @ViewBuilder
    private var imageSelectionActions: some View {
        HStack(spacing: 8) {
            Button(action: selectImage) {
                Label(session.source == nil ? "选择图片" : "更换图片", systemImage: "photo")
                    .font(ToolTypography.buttonSmall)
            }
            .buttonStyle(IndexSmallButtonStyle())
            .accessibilityLabel(session.source == nil ? "选择要转换的图片" : "更换要转换的图片")

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
                .accessibilityLabel("清除转换图片")
                .help("清除转换图片")
            }
        }
    }

    private var saveButtonTitle: String {
        if convertedAssessment?.requiresExplicitLargerSave == true {
            return "仍然保存更大的文件"
        }
        return "转换并保存"
    }

    private var transparencyFillOutputSuffix: String {
        guard requiresTransparencyFill, selectedTransparencyFill != nil else { return "" }
        return " · 透明区域已填充为\(transparencyFillDisplayName)"
    }

    private var transparencyFillDisplayName: String {
        switch transparencyFillMode {
        case .unset:
            return "未选择"
        case .white:
            return "白色"
        case .black:
            return "黑色"
        case .custom:
            return selectedTransparencyFill?.hexString ?? "无效颜色"
        }
    }

    private var transparencyFillAccessibilityValue: String {
        selectedTransparencyFill == nil ? "尚未选择" : transparencyFillDisplayName
    }

    private var customTransparencyFillAccessibilityValue: String {
        selectedTransparencyFill?.hexString ?? "格式无效，请输入井号和六位十六进制颜色"
    }

    private func selectImage() {
        session.selectImage(
            filePanel: fileInputPanelClient,
            allowedContentTypes: ImageWorkflowClient.standardImageContentTypes,
            operation: .conversion,
            selectionPublisher: publishSelectedImage,
            onSelection: { _ in ensureSupportedTargetFormat() },
            shouldRender: { selection in
                !ImageFileFormat.conversionTargetFormats(
                    sourceFormat: selection.metadata.format
                ).isEmpty
            },
            skippedRenderFailure: .noConversionTarget,
            render: converterRenderer()
        )
    }

    private func receiveImageURL(_ url: URL) {
        session.receiveImageURL(
            url,
            allowedContentTypes: ImageWorkflowClient.standardImageContentTypes,
            operation: .conversion,
            selectionPublisher: publishSelectedImage,
            onSelection: { _ in ensureSupportedTargetFormat() },
            shouldRender: { selection in
                !ImageFileFormat.conversionTargetFormats(
                    sourceFormat: selection.metadata.format
                ).isEmpty
            },
            skippedRenderFailure: .noConversionTarget,
            render: converterRenderer()
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

    private func convert() {
        ensureSupportedTargetFormat()
        guard canConvert else {
            session.clearOutput()
            return
        }
        session.renderInBackground(operation: .conversion, converterRenderer())
    }

    private func ensureSupportedTargetFormat() {
        guard !outputFormats.contains(targetFormat), let fallback = outputFormats.first else {
            return
        }
        targetFormat = fallback
        applyDefaultQualityForTarget()
    }

    private func applyDefaultQualityForTarget() {
        guard let defaultQuality = targetFormat.defaultConversionQuality else { return }
        quality = defaultQuality
    }

    private func normalizeCustomTransparencyFillHex() {
        customTransparencyFillHex = ImageRGBColor(hex: customTransparencyFillHex)?.hexString
            ?? ImageRGBColor.white.hexString
    }

    private func converterRenderer() -> ImageBackgroundOutputRenderer {
        let format = targetFormat
        let outputQuality = quality
        let transparencyFill = selectedTransparencyFill

        return { selection in
            let targets = ImageFileFormat.conversionTargetFormats(
                sourceFormat: selection.metadata.format
            )
            guard let resolvedFormat = targets.contains(format) ? format : targets.first else {
                throw ImageProcessorError.unsupportedFormat(format)
            }

            return try ImageProcessor.convert(
                data: selection.data,
                to: resolvedFormat,
                quality: resolvedFormat.supportsLossyQuality ? outputQuality : nil,
                maxPixelLength: nil,
                transparencyFill: transparencyFill
            )
        }
    }

    private func saveConverted() {
        Task { @MainActor in
            switch await session.save(workflow: .conversion, defaultBasename: "converted", filePanel: fileInputPanelClient, outputPanel: fileOutputPanelClient) {
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
