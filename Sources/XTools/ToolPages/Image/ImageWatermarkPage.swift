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
    /// 并入「图片处理」Hub 后与四段共用 toolID，slot 隔离各自的源图与结果；
    /// 偏好键沿用合并前的 imageWatermark.* 命名。
    static let key = ToolWorkspaceKey<ImageWatermarkToolWorkspaceModel>(toolID: "image-tools", slot: "watermark") { preferences in
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

struct IndexImageWatermarkSegment: View {
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

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.fileInputPanelClient) private var fileInputPanelClient
    @Environment(\.fileOutputPanelClient) private var fileOutputPanelClient
    @Environment(\.toolToastCenter) private var toastCenter
    @Environment(\.pageAvailableHeight) private var pageAvailableHeight

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

    /// 预览舞台高度：与压缩页同一收口（左侧文字工具栏占 78pt，其余一致）。
    private var previewStageHeight: CGFloat {
        max(300, pageAvailableHeight - 260)
    }

    var body: some View {
        // 空态不参与分栏：设置栏此时不存在，对半分会把上传区压成半宽。
        if session.source == nil {
            emptyUploadWell
        } else {
            IndexPairLayout(
                collapseWidth: ToolMetrics.Breakpoint.pairCollapseImageTools,
                fillsHeight: false,
                equalizesHeight: true,
                trailingWidth: 245
            ) {
                previewWorkspacePanel
            } trailing: {
                IndexPanel("水印设置") {
                    ImageWorkflowSettingsPanel(
                        primaryTitle: "保存水印图片",
                        primaryIcon: IndexActionSymbol.save,
                        primaryHelp: session.isSaving ? "正在保存图片" : "保存水印图片",
                        isPrimaryDisabled: session.output == nil || session.isProcessing || session.isSaving,
                        pinsActionToBottom: true,
                        onPrimary: saveImage,
                        source: { sourceSection },
                        settings: { watermarkSettings }
                    )
                }
                .withoutDiagnosticStatusSlot()
                .verticallyFilling()
            }
        }
    }

    /// 预览舞台：顶部一条水印文字工具栏，其下是与压缩页同构的成品预览。
    private var previewWorkspacePanel: some View {
        IndexPanel("预览") {
            VStack(spacing: 0) {
                watermarkTextField
                    .padding(.horizontal, ToolMetrics.Spacing.panelInset)
                    .padding(.top, ToolMetrics.Spacing.panelInset)
                    .padding(.bottom, ToolMetrics.Spacing.md)

                IndexImageComparisonPane(
                    title: "水印成品",
                    image: resultPreviewImage,
                    accessibilityLabel: "水印成品预览",
                    accessibilityValue: previewAccessibilityValue,
                    placeholder: previewPlaceholder,
                    stageHeight: previewStageHeight
                ) {
                    previewFacts
                }
            }
            .indexWorkspaceDiagnostic(session.error ?? previewSession.error)
            .indexDropZone(
                isTargeted: $isImageDropTargeted,
                onFile: receiveImageURL,
                onMultipleFiles: rejectMultipleImageDrop
            )
        }
        .contentInsets(EdgeInsets())
    }

    private var previewFacts: some View {
        HStack(spacing: ToolMetrics.Spacing.sm) {
            if previewSession.isRendering {
                IndexProgressSpinner()
                    .accessibilityLabel("正在更新水印预览")
            }

            Text(previewSummaryText)
                .font(ToolTypography.caption)
                .foregroundStyle(previewSummaryTone)

            Spacer(minLength: 8)

            Text(previewByteText)
                .font(ToolTypography.monoLabel)
                .foregroundStyle(previewByteTone)
        }
        .accessibilityElement(children: .combine)
    }

    private var previewSummaryText: String {
        if previewSession.isRendering {
            return "正在更新预览…"
        }
        if session.isProcessing {
            return "正在生成可保存原图…"
        }
        guard let resultAssessment else {
            return "等待生成"
        }
        return "\(resultAssessment.output.format.displayName) · \(ImageOutputPresentation.sizeChangeText(resultAssessment))"
    }

    private var previewSummaryTone: Color {
        resultAssessment?.requiresExplicitLargerSave == true ? ToolTheme.warning : ToolTheme.textSecondary
    }

    private var previewByteText: String {
        guard let resultAssessment else { return "—" }
        return ByteSizeFormatter.format(bytes: resultAssessment.output.byteCount)
    }

    private var previewByteTone: Color {
        resultAssessment?.requiresExplicitLargerSave == true ? ToolTheme.warning : ToolTheme.textPrimary
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

    /// 检查器「水印设置」区：透明度、大小、颜色与锚点。
    private var watermarkSettings: some View {
        VStack(alignment: .leading, spacing: ToolMetrics.Spacing.lg) {
            VStack(alignment: .leading, spacing: ToolMetrics.Spacing.sm) {
                HStack {
                    IndexOptionLabel("透明度")
                    Spacer(minLength: 8)
                    Text("\(Int(opacity * 100))%")
                        .font(ToolTypography.monoCaption)
                        .foregroundStyle(ToolTheme.textSecondary)
                }
                IndexSlider(value: $opacity, range: 0.1...1.0, step: 0)
                    .accessibilityLabel("水印透明度")
                    .accessibilityValue("\(Int(opacity * 100))%")
                    .onChange(of: opacity) { _ in recipeDidChange(previewCadence: .debounced) }
            }

            VStack(alignment: .leading, spacing: ToolMetrics.Spacing.sm) {
                HStack {
                    IndexOptionLabel("大小")
                    Spacer(minLength: 8)
                    Text("\(sizePercent)% · 按宽度")
                        .font(ToolTypography.monoCaption)
                        .foregroundStyle(ToolTheme.textSecondary)
                }
                IndexSlider(value: $sizeRatio, range: ImageWatermarkSizing.ratioRange, step: 0.01)
                    .accessibilityLabel("水印大小")
                    .accessibilityValue("\(sizePercent)%")
                    .onChange(of: sizeRatio) { _ in recipeDidChange(previewCadence: .debounced) }
            }

            VStack(alignment: .leading, spacing: ToolMetrics.Spacing.sm) {
                IndexOptionLabel("颜色")
                IndexSegmentedControl(
                    items: [
                        (ImageWatermarkTextColor.white, "白色"),
                        (.black, "黑色")
                    ],
                    selection: $textColor,
                    selectionStyle: .filled,
                    stretchesToFill: true
                )
                .onChange(of: textColor) { _ in recipeDidChange(previewCadence: .immediate) }
            }

            VStack(alignment: .leading, spacing: ToolMetrics.Spacing.sm) {
                WatermarkAnchorOption(position: $position) {
                    recipeDidChange(previewCadence: .immediate)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var emptyUploadWell: some View {
        IndexPanel("上传图片") {
            VStack(spacing: ToolMetrics.Spacing.lg) {
                watermarkTextField
                    .frame(maxWidth: 360)

                ImageUploadPendingState(
                    isProcessing: session.isProcessing,
                    title: "选择图片开始添加水印"
                )

                if !session.isProcessing {
                    IndexPrimaryActionButton(
                        title: "选择图片",
                        systemImage: "photo",
                        help: "选择图片",
                        action: selectImage
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
            .indexWorkspaceDiagnostic(session.error)
            .indexDropZone(
                isTargeted: $isImageDropTargeted,
                onFile: receiveImageURL,
                onMultipleFiles: rejectMultipleImageDrop
            )
        }
        .withoutHeader()
        .verticallyFilling()
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

    private var previewAccessibilityValue: String {
        guard let resultAssessment else { return previewPlaceholder }
        return "\(resultAssessment.output.format.displayName)，\(ByteSizeFormatter.format(bytes: resultAssessment.output.byteCount))，\(ImageOutputPresentation.sizeChangeText(resultAssessment))"
    }

    private var watermarkTextField: some View {
        IndexTextInput(
            placeholder: "水印文字",
            text: $watermarkText,
            onSubmit: applyFinalImmediately
        )
        .frame(maxWidth: .infinity)
        .accessibilityLabel("水印文字")
        .onChange(of: watermarkText) { _ in recipeDidChange(previewCadence: .debounced) }
    }

    private var sourceFileName: String {
        session.source?.url.lastPathComponent ?? "—"
    }

    private var sourceMetaText: String {
        guard let metadata = session.sourceMetadata else { return "—" }
        let format = metadata.format?.displayName ?? "未知格式"
        return "\(metadata.pixelWidth)×\(metadata.pixelHeight) · \(format)"
    }

    private var imageSelectionActions: ImageSelectionActionRow {
        ImageSelectionActionRow(
            hasSource: session.source != nil,
            selectAccessibilityLabel: "选择要添加水印的图片",
            replaceAccessibilityLabel: "更换要添加水印的图片",
            clearAccessibilityLabel: "清除当前水印图片",
            onSelect: selectImage,
            onClear: clearImage,
            framed: true
        )
    }

    private func clearImage() {
        previewDebouncer.cancel()
        finalDebouncer.cancel()
        previewSession.reset()
        withToolAnimation(ToolMotion.Preset.panelReveal, reduceMotion: reduceMotion) {
            session.reset()
        }
    }

    private var uploadInteractions: ImageUploadInteractions {
        ImageUploadInteractions(reduceMotion: reduceMotion)
    }

    private func selectImage() {
        session.selectImage(
            filePanel: fileInputPanelClient,
            allowedContentTypes: ImageWorkflowClient.standardImageContentTypes,
            operation: .watermark,
            selectionPublisher: uploadInteractions.publishSelection,
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
            selectionPublisher: uploadInteractions.publishSelection,
            onSelection: renderInitialPreview,
            renderProvider: { watermarkRenderer() },
            render: watermarkRenderer()
        )
    }

    private func rejectMultipleImageDrop() {
        previewDebouncer.cancel()
        finalDebouncer.cancel()
        previewSession.reset()
        uploadInteractions.rejectMultipleDrop {
            session.rejectImageInput(SingleFileDropResolver.multipleFilesDiagnostic)
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
            let outcome = await session.save(workflow: .watermark, defaultBasename: OutputFileNaming.timestampedBase(source: session.source?.url.lastPathComponent, fallback: "watermarked"), filePanel: fileInputPanelClient, outputPanel: fileOutputPanelClient)
            ImageSaveOutcomeToasts.presentSingleOutput(outcome, toastCenter: toastCenter)
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
            .frame(height: ToolMetrics.ControlHeight.small)
            .indexSurface(.control, fill: ToolTheme.editorBackground, border: ToolTheme.border)
        }
        .buttonStyle(IndexBareButtonStyle())
        .accessibilityLabel("水印位置")
        .accessibilityValue(position.displayName)
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
