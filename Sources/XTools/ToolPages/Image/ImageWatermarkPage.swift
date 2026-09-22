import AppKit
import XToolsCore
import SwiftUI

typealias ImageWatermarkPreviewRenderer = @Sendable (
    _ previewData: Data,
    _ sourcePixelWidth: Int,
    _ sourcePixelHeight: Int,
    _ recipe: ImageWatermarkRecipe
) throws -> Data

@MainActor
final class ImageWatermarkPreviewSession: ObservableObject, ToolWorkspacePayloadEvicting {
    @Published private(set) var image: NSImage?
    @Published private(set) var data: Data?
    @Published private(set) var error: String?
    @Published private(set) var isRendering = false

    private let workGate = AsyncWorkGate()

    func render(
        previewData: Data,
        sourcePixelWidth: Int,
        sourcePixelHeight: Int,
        recipe: ImageWatermarkRecipe,
        renderer: @escaping ImageWatermarkPreviewRenderer = { data, width, height, recipe in
            try ImageProcessor.watermarkPreview(
                data: data,
                sourcePixelWidth: width,
                sourcePixelHeight: height,
                recipe: recipe
            )
        }
    ) {
        invalidate(keepingImage: true)
        isRendering = true
        let currentGeneration = workGate.token

        enum PreviewOutcome: Sendable {
            case success(Data)
            case failure
            case cancelled
        }

        workGate.runDetached {
            do {
                try Task.checkCancellation()
                let data = try renderer(previewData, sourcePixelWidth, sourcePixelHeight, recipe)
                try Task.checkCancellation()
                return PreviewOutcome.success(data)
            } catch is CancellationError {
                return .cancelled
            } catch {
                return .failure
            }
        } publish: { [weak self] outcome in
            guard let self, self.workGate.isCurrent(currentGeneration) else { return }
            self.isRendering = false
            switch outcome {
            case .success(let data):
                guard let image = NSImage(data: data) else {
                    self.image = nil
                    self.data = nil
                    self.error = "水印预览生成失败。"
                    return
                }
                self.image = image
                self.data = data
                self.error = nil
            case .failure:
                self.image = nil
                self.data = nil
                self.error = "水印预览生成失败。"
            case .cancelled:
                break
            }
        }
    }

    func invalidate(keepingImage: Bool) {
        workGate.invalidate()
        isRendering = false
        error = nil
        if !keepingImage {
            image = nil
            data = nil
        }
    }

    func reset() {
        invalidate(keepingImage: false)
    }

    func evictHeavyPayloads() {
        reset()
    }
}

@MainActor
final class ImageWatermarkToolWorkspaceModel: ObservableObject, ToolWorkspacePayloadEvicting {
    static let key = ToolWorkspaceKey<ImageWatermarkToolWorkspaceModel>(toolID: "image-watermark") { preferences in
        ImageWatermarkToolWorkspaceModel(preferences: preferences)
    }

    let session = ImageProcessedOutputSession()
    let previewSession = ImageWatermarkPreviewSession()
    let previewDebouncer = IndexDebouncer()
    let finalDebouncer = IndexDebouncer()

    @Published var watermarkText = "Watermark"
    @Published var opacity: Double {
        didSet { preferences.set(opacity, for: MediaToolPreferenceKeys.imageWatermarkOpacity) }
    }
    @Published var sizeRatio: Double {
        didSet { preferences.set(sizeRatio, for: MediaToolPreferenceKeys.imageWatermarkSizeRatio) }
    }
    @Published var position: ImageWatermarkPosition {
        didSet { preferences.set(position, for: MediaToolPreferenceKeys.imageWatermarkPosition) }
    }
    @Published var textColor: ImageWatermarkTextColor {
        didSet { preferences.set(textColor, for: MediaToolPreferenceKeys.imageWatermarkColor) }
    }

    private let preferences: ToolPreferenceStore

    init(preferences: ToolPreferenceStore) {
        self.preferences = preferences
        opacity = preferences.value(for: MediaToolPreferenceKeys.imageWatermarkOpacity)
        sizeRatio = preferences.value(for: MediaToolPreferenceKeys.imageWatermarkSizeRatio)
        position = preferences.value(for: MediaToolPreferenceKeys.imageWatermarkPosition)
        textColor = preferences.value(for: MediaToolPreferenceKeys.imageWatermarkColor)
    }

    func evictHeavyPayloads() {
        session.evictHeavyPayloads()
        previewSession.evictHeavyPayloads()
        previewDebouncer.cancel()
        finalDebouncer.cancel()
    }
}

struct IndexImageWatermarkPage: View {
    var body: some View {
        ToolWorkspaceHost(key: ImageWatermarkToolWorkspaceModel.key) { workspace, bindings in
            IndexImageWatermarkWorkspaceContent(
                session: workspace.session,
                previewSession: workspace.previewSession,
                previewDebouncer: workspace.previewDebouncer,
                finalDebouncer: workspace.finalDebouncer,
                watermarkText: bindings.watermarkText,
                opacity: bindings.opacity,
                sizeRatio: bindings.sizeRatio,
                position: bindings.position,
                textColor: bindings.textColor
            )
        }
    }
}

private enum WatermarkPreviewCadence {
    case immediate
    case debounced
}

private struct IndexImageWatermarkWorkspaceContent: View {
    private static let previewDebounceDelay: Duration = .milliseconds(90)
    private static let finalDebounceDelay: Duration = .milliseconds(650)
    private static let previewStatusHeight: CGFloat = 18

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.fileInputPanelClient) private var fileInputPanelClient
    @Environment(\.fileOutputPanelClient) private var fileOutputPanelClient
    @Environment(\.toolToastCenter) private var toastCenter

    @ObservedObject var session: ImageProcessedOutputSession
    @ObservedObject var previewSession: ImageWatermarkPreviewSession
    let previewDebouncer: IndexDebouncer
    let finalDebouncer: IndexDebouncer
    @Binding var watermarkText: String
    @Binding var opacity: Double
    @Binding var sizeRatio: Double
    @Binding var position: ImageWatermarkPosition
    @Binding var textColor: ImageWatermarkTextColor
    @State private var isImageDropTargeted = false

    private var sizePercent: Int {
        Int((sizeRatio * 100).rounded())
    }

    private var recipe: ImageWatermarkRecipe {
        recipe(for: session.source)
    }

    private func recipe(for selection: ImageInputSelection?) -> ImageWatermarkRecipe {
        let pixelWidth = selection?.metadata.pixelWidth ?? 1
        let pixelHeight = selection?.metadata.pixelHeight ?? 1
        return ImageWatermarkRecipe(
            text: watermarkText,
            opacity: opacity,
            fontSize: ImageWatermarkSizing.fontSize(
                text: watermarkText,
                sizeRatio: sizeRatio,
                pixelWidth: pixelWidth,
                pixelHeight: pixelHeight
            ),
            position: position,
            color: textColor
        )
    }

    private var resultAssessment: ImageOutputAssessment? {
        session.assessment(for: .watermark)
    }

    private var resultPreviewImage: NSImage? {
        previewSession.image ?? session.outputImage
    }

    var body: some View {
        IndexPage("图片水印", subtitle: "为图片添加黑色或白色文字水印，并保持原格式与尺寸。", workspaceSemantic: .liveImagePreviewStage) {
            IndexActionBar {
                IndexOptionGroup {
                    IndexOptionLabel("透明度")
                    IndexSlider(value: $opacity, range: 0.1...1.0, step: 0)
                        .frame(width: 120)
                        .accessibilityLabel("水印透明度")
                        .accessibilityValue("\(Int(opacity * 100))%")
                        .onChange(of: opacity) { _ in recipeDidChange(previewCadence: .debounced) }

                    IndexOptionDivider()
                    IndexOptionLabel("大小")
                    IndexSlider(value: $sizeRatio, range: ImageWatermarkSizing.ratioRange, step: 0.01)
                        .frame(width: 100)
                        .accessibilityLabel("水印大小")
                        .accessibilityValue("\(sizePercent)%")
                        .help("按图片宽度比例设置水印大小")
                        .onChange(of: sizeRatio) { _ in recipeDidChange(previewCadence: .debounced) }
                    Text("\(sizePercent)%")
                        .font(ToolTypography.monoCaption)
                        .foregroundStyle(ToolTheme.textSecondary)
                        .frame(width: 32, alignment: .trailing)
                        .accessibilityHidden(true)
                }

                IndexOptionGroup {
                    IndexOptionLabel("颜色")
                    IndexInlinePicker(
                        items: [
                            (ImageWatermarkTextColor.white, "白色"),
                            (.black, "黑色")
                        ],
                        selection: $textColor
                    )
                    .help("选择黑色或白色水印文字")
                    .onChange(of: textColor) { _ in recipeDidChange(previewCadence: .immediate) }

                    IndexOptionDivider()

                    WatermarkAnchorOption(position: $position) {
                        recipeDidChange(previewCadence: .immediate)
                    }
                }
            }

            IndexPanel("上传图片", fillsHeight: session.source == nil) {
                VStack(alignment: .leading, spacing: ToolMetrics.Spacing.md) {
                    imageSelectionActions

                    if session.source == nil {
                        watermarkTextField

                        if session.isProcessing {
                            IndexProgressLabel(message: "正在读取图片…")
                                .foregroundStyle(ToolTheme.textSecondary)
                                .accessibilityLabel("正在读取图片")
                        } else {
                            IndexEmptyState(
                                title: "选择图片开始添加水印",
                                systemImage: "photo.on.rectangle.angled",
                                message: IndexEmptyStateCopy.autoGenerate("图片"),
                                density: .list
                            )
                            .frame(maxWidth: .infinity, minHeight: 128)
                        }
                    } else {
                        ViewThatFits(in: .horizontal) {
                            HStack(alignment: .center, spacing: 24) {
                                watermarkTextField
                                sourceIdentity
                            }

                            VStack(alignment: .leading, spacing: ToolMetrics.Spacing.sm) {
                                watermarkTextField
                                sourceIdentity
                            }
                        }
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

            Group {
                if session.source != nil {
                    IndexPanel("水印成品") {
                        VStack(alignment: .leading, spacing: ToolMetrics.Spacing.md) {
                            IndexImagePreviewStage(
                                image: resultPreviewImage,
                                accessibilityLabel: "水印成品预览",
                                placeholder: previewPlaceholder,
                                fillsHeight: true,
                                replacementMotion: .immediate
                            ) {
                                HStack(spacing: ToolMetrics.Spacing.sm) {
                                    if previewSession.isRendering {
                                        IndexProgressSpinner()
                                            .accessibilityLabel("正在更新水印预览")
                                    }

                                    if session.isProcessing {
                                        Text("正在生成可保存原图…")
                                            .font(ToolTypography.caption)
                                            .foregroundStyle(ToolTheme.textSecondary)
                                    } else if let resultAssessment {
                                        Text(ImageOutputPresentation.processingOutputSummary(resultAssessment))
                                            .font(ToolTypography.caption)
                                            .foregroundStyle(resultAssessment.requiresExplicitLargerSave ? ToolTheme.warning : ToolTheme.textSecondary)
                                    }
                                }
                                .frame(height: Self.previewStatusHeight)
                            }
                            .indexWorkspaceDiagnostic(session.error ?? previewSession.error)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    } accessory: {
                        if session.output != nil, !session.isProcessing {
                            Button {
                                saveImage()
                            } label: {
                                Label("保存", systemImage: IndexActionSymbol.save)
                                    .font(ToolTypography.buttonSmall)
                            }
                            .buttonStyle(IndexSmallButtonStyle())
                            .accessibilityLabel("保存水印图片")
                            .help("保存与当前水印设置一致的原尺寸图片")
                        }
                    }
                    .verticallyFilling()
                    .toolTransition(ToolMotion.Transition.modeContent, reduceMotion: reduceMotion)
                }
            }
        }
    }

    private var previewPlaceholder: String {
        if previewSession.isRendering {
            return "正在更新水印预览…"
        }
        if watermarkText.isEmpty {
            return "输入水印文字后显示成品预览"
        }
        return "等待水印预览"
    }

    private var watermarkTextField: some View {
        IndexTextInput(
            placeholder: "水印文字",
            text: $watermarkText,
            onSubmit: applyFinalImmediately
        )
        .frame(minWidth: 220, idealWidth: 300, maxWidth: .infinity)
        .accessibilityLabel("水印文字")
        .onChange(of: watermarkText) { _ in recipeDidChange(previewCadence: .debounced) }
    }

    @ViewBuilder
    private var sourceIdentity: some View {
        if let source = session.source {
            HStack(alignment: .center, spacing: 12) {
                IndexImagePreviewImage(
                    image: source.image,
                    accessibilityLabel: "水印源图片缩略图",
                    maxDisplayWidth: 64,
                    maxDisplayHeight: 48
                )
                .frame(width: 64, height: 48)

                VStack(alignment: .leading, spacing: 4) {
                    Text(source.url.lastPathComponent)
                        .font(ToolTypography.bodyPlain)
                        .foregroundStyle(ToolTheme.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(source.url.lastPathComponent)

                    Text(sourceMetadataSummary)
                        .font(ToolTypography.monoCaption)
                        .foregroundStyle(ToolTheme.textSecondary)
                        .lineLimit(1)
                }
            }
            .frame(width: 300, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("源图片信息")
            .accessibilityValue(sourceAccessibilityValue)
        }
    }

    private var sourceMetadataSummary: String {
        guard let metadata = session.source?.metadata else { return "" }
        return ImageOutputPresentation.sourceSummary(metadata)
    }

    private var sourceAccessibilityValue: String {
        guard let source = session.source else { return "" }
        let metadata = source.metadata
        return "\(source.url.lastPathComponent)，\(metadata.pixelWidth) 乘 \(metadata.pixelHeight)，\(metadata.format?.displayName ?? "未知格式")，\(ByteSizeFormatter.format(bytes: metadata.byteCount))"
    }

    @ViewBuilder
    private var imageSelectionActions: some View {
        HStack(spacing: 8) {
            Button(action: selectImage) {
                Label(session.source == nil ? "选择图片" : "更换图片", systemImage: "photo")
                    .font(ToolTypography.buttonSmall)
            }
            .buttonStyle(IndexSmallButtonStyle())
            .accessibilityLabel(session.source == nil ? "选择要添加水印的图片" : "更换要添加水印的图片")

            if session.source != nil {
                Button(action: clearImage) {
                    Label("清除图片", systemImage: IndexActionSymbol.removeResource)
                        .font(ToolTypography.buttonSmall)
                }
                .buttonStyle(IndexSmallButtonStyle())
                .accessibilityLabel("清除当前水印图片")
                .help("清除当前水印图片")
            }
        }
    }

    private func clearImage() {
        previewDebouncer.cancel()
        finalDebouncer.cancel()
        previewSession.reset()
        withToolAnimation(ToolMotion.Preset.panelReveal, reduceMotion: reduceMotion) {
            session.reset()
        }
    }

    private func selectImage() {
        session.selectImage(
            filePanel: fileInputPanelClient,
            allowedContentTypes: ImageWorkflowClient.standardImageContentTypes,
            operation: .watermark,
            selectionPublisher: publishSelectedImage,
            onSelection: renderInitialPreview,
            renderProvider: { watermarkRenderer() },
            render: watermarkRenderer()
        )
    }

    private func receiveImageURL(_ url: URL) {
        session.receiveImageURL(
            url,
            allowedContentTypes: ImageWorkflowClient.standardImageContentTypes,
            operation: .watermark,
            selectionPublisher: publishSelectedImage,
            onSelection: renderInitialPreview,
            renderProvider: { watermarkRenderer() },
            render: watermarkRenderer()
        )
    }

    private func rejectMultipleImageDrop() {
        previewDebouncer.cancel()
        finalDebouncer.cancel()
        previewSession.reset()
        withToolAnimation(ToolMotion.Preset.panelReveal, reduceMotion: reduceMotion) {
            session.rejectImageInput(SingleFileDropResolver.multipleFilesDiagnostic)
        }
    }

    private func publishSelectedImage(_ selection: ImageInputSelection, _ publish: () -> Void) {
        withToolAnimation(ToolMotion.Preset.panelReveal, reduceMotion: reduceMotion) {
            publish()
        }
    }

    private func renderInitialPreview(_ selection: ImageInputSelection) {
        guard !recipe.text.isEmpty else {
            previewSession.reset()
            return
        }
        renderPreview(selection: selection, recipe: recipe(for: selection))
    }

    private func recipeDidChange(previewCadence: WatermarkPreviewCadence) {
        previewDebouncer.cancel()
        finalDebouncer.cancel()
        previewSession.invalidate(keepingImage: true)

        guard let selection = session.source else {
            if recipe.text.isEmpty {
                previewSession.reset()
            }
            return
        }
        session.clearOutput()

        guard !recipe.text.isEmpty else {
            previewSession.reset()
            return
        }

        let pendingRecipe = recipe
        switch previewCadence {
        case .immediate:
            renderPreview(selection: selection, recipe: pendingRecipe)
        case .debounced:
            previewDebouncer.schedule(Self.previewDebounceDelay) {
                guard let currentSelection = session.source else { return }
                renderPreview(selection: currentSelection, recipe: pendingRecipe)
            }
        }
        finalDebouncer.schedule(Self.finalDebounceDelay) {
            session.renderInBackground(operation: .watermark, watermarkRenderer(recipe: pendingRecipe))
        }
    }

    private func applyFinalImmediately() {
        finalDebouncer.cancel()
        guard session.source != nil, !recipe.text.isEmpty else { return }
        session.clearOutput()
        session.renderInBackground(operation: .watermark, watermarkRenderer())
    }

    private func renderPreview(selection: ImageInputSelection, recipe: ImageWatermarkRecipe) {
        previewSession.render(
            previewData: selection.previewData,
            sourcePixelWidth: selection.metadata.pixelWidth,
            sourcePixelHeight: selection.metadata.pixelHeight,
            recipe: recipe
        )
    }

    private func watermarkRenderer(recipe: ImageWatermarkRecipe? = nil) -> ImageBackgroundOutputRenderer {
        let currentRecipe = recipe ?? self.recipe
        return { selection in
            try ImageProcessor.watermark(
                data: selection.data,
                sourceFilenameExtension: selection.filenameExtension,
                recipe: currentRecipe,
                outputFormat: nil
            )
        }
    }

    private func saveImage() {
        Task { @MainActor in
            switch await session.save(workflow: .watermark, defaultBasename: "watermarked", filePanel: fileInputPanelClient, outputPanel: fileOutputPanelClient) {
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

/// Compact spatial-position trigger. Rendered inside the shared watermark
/// option group row, so the trigger keeps the group's inner-control surface
/// instead of framing its own container.
private struct WatermarkAnchorOption: View {
    @Binding var position: ImageWatermarkPosition
    let onChange: () -> Void
    @State private var isPickerPresented = false

    private let columns = Array(repeating: GridItem(.fixed(28), spacing: 4), count: 3)

    var body: some View {
        IndexOptionLabel("位置")

        Button {
            isPickerPresented.toggle()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "square.grid.3x3")
                    .accessibilityHidden(true)

                Text(position.displayName)
                    .lineLimit(1)

                Image(systemName: "chevron.down")
                    .font(.system(size: ToolMetrics.IconSize.micro, weight: .semibold))
                    .accessibilityHidden(true)
            }
            .font(ToolTypography.controlLabel(weight: .semibold))
            .foregroundStyle(ToolTheme.textPrimary)
            .padding(.horizontal, 9)
            .frame(height: 24)
            .indexSurface(.control, fill: ToolTheme.editorBackground, border: ToolTheme.border)
        }
        .buttonStyle(IndexBareButtonStyle())
        .accessibilityLabel("水印位置")
        .accessibilityValue(position.displayName)
        .help("选择水印位置")
        .popover(isPresented: $isPickerPresented, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 10) {
                Text("水印位置")
                    .font(ToolTypography.panelTitle)
                    .foregroundStyle(ToolTheme.textSecondary)

                LazyVGrid(columns: columns, spacing: 4) {
                    ForEach(ImageWatermarkPosition.allCases, id: \.self) { item in
                        anchorButton(item)
                    }
                }
                .fixedSize()
                .accessibilityElement(children: .contain)
            }
            .padding(ToolMetrics.Spacing.md)
        }
    }

    private func anchorButton(_ item: ImageWatermarkPosition) -> some View {
        WatermarkAnchorCell(
            item: item,
            isSelected: position == item
        ) {
            guard position != item else { return }
            position = item
            onChange()
        }
    }
}

/// One 3×3 anchor cell following the shared row grammar (hover/selected/focus).
private struct WatermarkAnchorCell: View {
    let item: ImageWatermarkPosition
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovering = false
    @FocusState private var isFocused: Bool

    var body: some View {
        Button(action: action) {
            RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.nestedControl, style: .continuous)
                .fill(
                    isSelected ? ToolTheme.selectionFill :
                    isHovering ? ToolTheme.hoverFill :
                    ToolTheme.editorBackground
                )
                .frame(width: 28, height: 28)
                .overlay {
                    Circle()
                        .fill(isSelected ? ToolTheme.accentHover : ToolTheme.textSecondary)
                        .frame(width: 5, height: 5)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: item.alignment)
                        .padding(5)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.nestedControl, style: .continuous)
                        .strokeBorder(isSelected ? ToolTheme.selectionStroke : ToolTheme.border, lineWidth: 1)
                }
                .contentShape(RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.nestedControl, style: .continuous))
        }
        .buttonStyle(IndexBareButtonStyle())
        .onHover { hovering in
            withToolAnimation(ToolMotion.Preset.controlFeedback) { isHovering = hovering }
        }
        .focused($isFocused)
        .indexFocusRing(active: isFocused, cornerRadius: ToolMetrics.CornerRadius.nestedControl)
        .accessibilityLabel(item.displayName)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .help(item.displayName)
    }
}

private extension ImageWatermarkPosition {
    var displayName: String {
        switch self {
        case .topLeft: return "左上"
        case .topCenter: return "上中"
        case .topRight: return "右上"
        case .centerLeft: return "左中"
        case .center: return "居中"
        case .centerRight: return "右中"
        case .bottomLeft: return "左下"
        case .bottomCenter: return "下中"
        case .bottomRight: return "右下"
        }
    }

    var alignment: Alignment {
        switch self {
        case .topLeft: return .topLeading
        case .topCenter: return .top
        case .topRight: return .topTrailing
        case .centerLeft: return .leading
        case .center: return .center
        case .centerRight: return .trailing
        case .bottomLeft: return .bottomLeading
        case .bottomCenter: return .bottom
        case .bottomRight: return .bottomTrailing
        }
    }
}
