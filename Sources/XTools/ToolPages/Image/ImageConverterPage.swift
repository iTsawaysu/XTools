import XToolsCore
import SwiftUI

@MainActor
final class ImageConverterToolWorkspaceModel: ObservableObject, ToolWorkspacePayloadEvicting {
    static let key = ToolWorkspaceKey<ImageConverterToolWorkspaceModel>(toolID: "image-tools", slot: "converter") { preferences in
        ImageConverterToolWorkspaceModel(preferences: preferences)
    }

    let session = ImageBatchConversionSession()

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

struct IndexImageConverterSegment: View {
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
    @Environment(\.pageAvailableHeight) private var pageAvailableHeight

    @ObservedObject var session: ImageBatchConversionSession
    @Binding var targetFormat: ImageFileFormat
    @Binding var quality: Double
    @Binding var transparencyFillMode: ImageTransparencyFillMode
    @Binding var customTransparencyFillHex: String
    @State private var isImageDropTargeted = false
    /// 自定义透明填充色无效时的就地诊断；有效或未启用自定义时为 nil。
    /// 与 session.error 同槽展示（页面既有错误机制），但优先级更高。
    @State private var transparencyFillError: String?
    /// 质量滑杆拖动是连续变更：单张沿用 90ms trailing 防抖；批量模式会对
    /// 全部图片逐张重转，90ms 对 N 张串行重转过短，升到 250ms（ADR-0018
    /// 连续变更短防抖，对齐水印的双轨配方）；AsyncWorkGate 的世代取消语义不变。
    @State private var qualityDebouncer = IndexDebouncer()
    private static let singleQualityDebounceDelay: Duration = .milliseconds(90)
    private static let batchQualityDebounceDelay: Duration = .milliseconds(250)
    /// 自定义填充色是逐字符键入的连续变更：每键全量重转在批量模式下代价过高，
    /// 复用同一防抖配方（ADR-0018）。
    @State private var fillHexDebouncer = IndexDebouncer()
    private static let fillHexDebounceDelay: Duration = .milliseconds(250)

    /// 目标格式候选 = 所有已导入图片源格式可用转换目标的交集；
    /// 交集为空（含任一源格式无目标）时提示"无可转换目标"。
    private var outputFormats: [ImageFileFormat] {
        var candidates: [ImageFileFormat]?
        for sourceFormat in session.items.map(\.metadata.format) {
            let targets = ImageFileFormat.conversionTargetFormats(sourceFormat: sourceFormat)
            if let current = candidates {
                candidates = current.filter { targets.contains($0) }
            } else {
                candidates = targets
            }
        }
        return candidates ?? []
    }

    private var canConvert: Bool {
        !session.items.isEmpty
            && outputFormats.contains(targetFormat)
            && (!hasKnownTransparency || selectedTransparencyFill != nil)
    }

    private var hasKnownTransparency: Bool {
        !targetFormat.preservesAlpha && session.items.contains { $0.metadata.transparency == .transparent }
    }

    private var requiresTransparencyFill: Bool {
        guard !targetFormat.preservesAlpha else { return false }
        return session.items.contains { $0.metadata.transparency != .opaque }
    }

    private var selectedTransparencyFill: ImageRGBColor? {
        transparencyFillMode.color(customHex: customTransparencyFillHex)
    }

    var body: some View {
        // 间距对齐 IndexPage 标准页面壳的 sectionSpacing（panelSection = 10），
        // 与两段平铺时视觉一致。拖放命中区挂整个内容根容器（参数区、列表、
        // 空白处均可接收），但保持静默：视觉高亮由输入区内容层经共享
        // isImageDropTargeted 呈现——命中范围大、指示只标输入框，与常规
        // App 的拖放语义一致。
        VStack(alignment: .leading, spacing: ToolMetrics.Spacing.panelSection) {
            // 空态不参与分栏：设置栏此时不存在，对半分会把上传区压成半宽。
            if session.items.isEmpty {
                emptyUploadWell
            } else {
                IndexPairLayout(
                    collapseWidth: ToolMetrics.Breakpoint.pairCollapseImageTools,
                    fillsHeight: false,
                    equalizesHeight: true,
                    trailingWidth: 245
                ) {
                    queuePanel
                } trailing: {
                    IndexPanel("转换设置") {
                        ImageWorkflowSettingsPanel(
                            primaryTitle: saveButtonTitle,
                            primaryIcon: IndexActionSymbol.save,
                            primaryHelp: session.isSaving ? "正在保存图片" : "保存转换结果",
                            isPrimaryDisabled: session.completedCount == 0 || session.isProcessing || session.isSaving,
                            pinsActionToBottom: true,
                            sourceTitle: session.singleItem == nil ? "队列" : "源文件",
                            onPrimary: saveConverted,
                            source: { queueSection },
                            settings: { outputSettings },
                            output: { converterOutputSection }
                        )
                    }
                    .verticallyFilling()
                }
                .onAppear(perform: ensureSupportedTargetFormat)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .multiImageInputDropDestination(
            isTargeted: $isImageDropTargeted,
            onFiles: receiveImageURLs,
            showsHighlight: false
        )
    }

    /// 检查器与舞台等高：舞台固定占满首屏，列表在舞台内滚动。
    private var stagePanelHeight: CGFloat {
        max(420, pageAvailableHeight - 118)
    }

    private var stagePanelTitle: String {
        session.singleItem == nil ? "转换队列" : "预览"
    }

    /// 转换舞台：单张为预览 + 标准脚注，多张为可滚动列表。
    private var queuePanel: some View {
        IndexPanel(stagePanelTitle) {
            Group {
                if let singleItem = session.singleItem {
                    singleImageStage(singleItem)
                } else {
                    ScrollView {
                        batchList
                            .padding(ToolMetrics.Spacing.panelInset)
                    }
                }
            }
            .indexWorkspaceDiagnostic(session.error)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .imageDropHighlight(isActive: isImageDropTargeted)
        }
        .contentInsets(EdgeInsets())
        .verticallyFilling()
        .frame(height: stagePanelHeight)
    }

    /// 空态：无面板头的拖放井。
    private var emptyUploadWell: some View {
        IndexPanel("上传图片") {
            VStack(spacing: ToolMetrics.Spacing.lg) {
                ImageUploadPendingState(
                    isProcessing: session.isImporting,
                    title: "选择图片开始转换"
                )

                if !session.isImporting {
                    IndexPrimaryActionButton(
                        title: "选择图片",
                        systemImage: "photo",
                        help: "选择图片",
                        action: addImages
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
            .imageDropHighlight(isActive: isImageDropTargeted)
        }
        .withoutHeader()
        .verticallyFilling()
    }

    /// 检查器「队列」区：单张时显示文件名与源摘要，多张时显示张数与总大小。
    private var queueSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(queuePrimaryText)
                .font(ToolTypography.bodyMedium)
                .foregroundStyle(ToolTheme.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)

            Text(queueMetaText)
                .font(ToolTypography.caption)
                .foregroundStyle(ToolTheme.textTertiary)
                .lineLimit(1)
                .padding(.top, ToolMetrics.Spacing.xs)

            imageSelectionActions
                .padding(.top, ToolMetrics.Spacing.sm)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var queuePrimaryText: String {
        if let singleItem = session.singleItem {
            return singleItem.filename
        }
        return "\(session.items.count) 张图片"
    }

    private var queueMetaText: String {
        if let singleItem = session.singleItem {
            return ImageOutputPresentation.sourceSummary(singleItem.metadata)
        }
        let totalBytes = session.items.reduce(0) { $0 + $1.metadata.byteCount }
        return "总计 \(ByteSizeFormatter.format(bytes: totalBytes))"
    }

    /// 设置栏内容：目标格式、质量、透明填充。
    private var outputSettings: some View {
        VStack(alignment: .leading, spacing: ToolMetrics.Spacing.lg) {
            VStack(alignment: .leading, spacing: ToolMetrics.Spacing.sm) {
                IndexOptionLabel("目标格式")
                if outputFormats.isEmpty {
                    Text("无可转换目标")
                        .font(ToolTypography.caption)
                        .foregroundStyle(ToolTheme.textSecondary)
                } else {
                    IndexSegmentedControl(
                        items: outputFormats.map { ($0, $0.displayName) },
                        selection: $targetFormat,
                        selectionStyle: .filled,
                        stretchesToFill: true
                    )
                    .accessibilityLabel("目标格式")
                    .accessibilityValue(targetFormat.displayName)
                    .onChange(of: targetFormat) { _ in
                        applyDefaultQualityForTarget()
                        convert()
                    }
                }
            }

            if canConvert && targetFormat.supportsLossyQuality {
                VStack(alignment: .leading, spacing: ToolMetrics.Spacing.sm) {
                    HStack {
                        IndexOptionLabel("质量")
                        Spacer(minLength: 8)
                        Text("\(Int(quality * 100))%")
                            .font(ToolTypography.monoCaption)
                            .foregroundStyle(ToolTheme.textSecondary)
                    }
                    IndexSlider(value: $quality, range: 0.1...1.0, step: 0)
                        .accessibilityLabel("转换质量")
                        .accessibilityValue("\(Int(quality * 100))%")
                        .onChange(of: quality) { _ in
                            qualityDebouncer.schedule(
                                session.items.count > 1
                                    ? Self.batchQualityDebounceDelay
                                    : Self.singleQualityDebounceDelay
                            ) {
                                convert()
                            }
                        }
                }
            }

            if requiresTransparencyFill {
                VStack(alignment: .leading, spacing: ToolMetrics.Spacing.sm) {
                    IndexOptionLabel("透明填充")
                    IndexSegmentedControl(
                        items: [
                            (ImageTransparencyFillMode.white, "白色"),
                            (.black, "黑色"),
                            (.custom, "自定义")
                        ],
                        selection: $transparencyFillMode,
                        selectionStyle: .filled,
                        stretchesToFill: true
                    )
                    .accessibilityLabel("透明区域填充颜色")
                    .accessibilityValue(transparencyFillAccessibilityValue)
                    .onChange(of: transparencyFillMode) { _ in convert() }

                    if transparencyFillMode == .custom {
                        IndexTextInput(
                            placeholder: "#RGB 或 #RRGGBB",
                            text: $customTransparencyFillHex,
                            alignment: .center,
                            selectAllOnFocus: true,
                            onSubmit: normalizeCustomTransparencyFillHex
                        )
                        .accessibilityLabel("自定义透明区域填充颜色")
                        .accessibilityValue(customTransparencyFillAccessibilityValue)
                        .onChange(of: customTransparencyFillHex) { _ in
                            fillHexDebouncer.schedule(Self.fillHexDebounceDelay) {
                                convert()
                            }
                        }
                    }

                    Text("JPEG 和 HEIC 不支持透明区域；请选择转换前用于填充透明像素的颜色。")
                        .font(ToolTypography.caption)
                        .foregroundStyle(ToolTheme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("透明区域填充颜色")
                .accessibilityValue(transparencyFillAccessibilityValue)
                .indexWorkspaceDiagnostic(transparencyFillError)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var imageSelectionActions: ImageSelectionActionRow {
        ImageSelectionActionRow(
            hasSource: !session.items.isEmpty,
            selectAccessibilityLabel: "选择要转换的图片",
            replaceAccessibilityLabel: "添加要转换的图片",
            clearAccessibilityLabel: "清除全部转换图片",
            onSelect: addImages,
            onClear: {
                withToolAnimation(ToolMotion.Preset.panelReveal, reduceMotion: reduceMotion) {
                    session.reset()
                }
                resumePendingConversions()
            },
            changeTitle: "添加图片",
            clearTitle: session.singleItem == nil ? "清空队列" : "清除图片",
            framed: true
        )
    }

    /// 单张舞台：预览居中，底部固定 40pt 脚注（原始/输出体积与变化）。
    private func singleImageStage(_ item: BatchConversionItem) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            IndexImagePreviewStage(
                image: session.sourceImage,
                accessibilityLabel: "待转换的原图",
                accessibilityValue: sourcePreviewAccessibilityValue(item),
                maxDisplayWidth: 640,
                maxDisplayHeight: 400
            )
            .padding(.horizontal, ToolMetrics.Spacing.panelInset)
            Spacer(minLength: 0)
            Rectangle().fill(ToolTheme.border).frame(height: 0.5)
            singleItemFooter(item)
        }
    }

    private func singleItemFooter(_ item: BatchConversionItem) -> some View {
        HStack(spacing: ToolMetrics.Spacing.sm) {
            Text("原始大小")
                .font(ToolTypography.caption)
                .foregroundStyle(ToolTheme.textSecondary)
            Text(ByteSizeFormatter.format(bytes: item.metadata.byteCount))
                .font(ToolTypography.monoLabel)
                .foregroundStyle(ToolTheme.textPrimary)

            Spacer(minLength: 8)

            switch item.state {
            case .idle:
                Text("待转换")
                    .font(ToolTypography.caption)
                    .foregroundStyle(ToolTheme.textSecondary)
            case .converting:
                IndexProgressSpinner()
                    .accessibilityLabel("正在转换图片")
                Text("正在转换…")
                    .font(ToolTypography.caption)
                    .foregroundStyle(ToolTheme.textSecondary)
            case let .failed(message):
                Text(message)
                    .font(ToolTypography.caption)
                    .foregroundStyle(ToolTheme.warning)
                    .lineLimit(1)
            case let .done(output):
                Text("输出大小")
                    .font(ToolTypography.caption)
                    .foregroundStyle(ToolTheme.textSecondary)
                Text(ByteSizeFormatter.format(bytes: output.byteCount))
                    .font(ToolTypography.monoLabel)
                    .foregroundStyle(output.requiresExplicitLargerSave ? ToolTheme.warning : ToolTheme.textPrimary)
                Text(changeText(source: item.metadata.byteCount, output: output.byteCount))
                    .font(ToolTypography.caption)
                    .foregroundStyle(output.byteCount <= item.metadata.byteCount ? ToolTheme.success : ToolTheme.warning)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 40)
        .background(ToolTheme.panelBackground)
        .accessibilityElement(children: .combine)
    }

    private func sourcePreviewAccessibilityValue(_ item: BatchConversionItem) -> String {
        let metadata = item.metadata
        let format = metadata.format?.displayName ?? "未知格式"
        return "\(metadata.pixelWidth)×\(metadata.pixelHeight)，\(format)，\(ByteSizeFormatter.format(bytes: metadata.byteCount))"
    }

    private func changeText(source: Int, output: Int) -> String {
        guard source > 0 else { return "—" }
        let percent = Int(((Double(output) - Double(source)) / Double(source) * 100).rounded())
        if percent < 0 { return "减少 \(abs(percent))%" }
        if percent > 0 { return "增大 \(percent)%" }
        return "无变化"
    }

    /// N>1 紧凑行。
    private var batchList: some View {
        VStack(alignment: .leading, spacing: ToolMetrics.Spacing.sm) {
            ForEach(session.items) { item in
                BatchConversionRow(item: item) {
                    withToolAnimation(ToolMotion.Preset.panelReveal, reduceMotion: reduceMotion) {
                        session.removeItem(id: item.id)
                    }
                    resumePendingConversions()
                }
            }
        }
    }

    @ViewBuilder
    private var converterOutputSection: some View {
        if let singleItem = session.singleItem {
            VStack(spacing: 0) {
                ImageInspectorFactRow(label: "格式", value: singleOutputFormat(singleItem))
                ImageInspectorFactRow(label: "尺寸", value: singleOutputDimensions(singleItem))
                if let quality = singleOutputQuality(singleItem) {
                    ImageInspectorFactRow(label: "实际质量", value: "\(Int(quality * 100))%")
                }
                ImageInspectorFactRow(
                    label: "体积变化",
                    value: singleOutputChange(singleItem),
                    valueTone: singleOutputChangeTone(singleItem)
                )
            }
        } else {
            VStack(spacing: 0) {
                ImageInspectorFactRow(label: "已完成", value: "\(session.completedCount) / \(session.items.count)")
                if session.failedCount > 0 {
                    ImageInspectorFactRow(label: "失败", value: "\(session.failedCount)", valueTone: ToolTheme.warning)
                }
                ImageInspectorFactRow(label: "输出总计", value: completedOutputTotalText)
                ImageInspectorFactRow(label: "体积变化", value: batchChangeText, valueTone: batchChangeTone)
            }
        }
    }

    private func singleOutput(_ item: BatchConversionItem) -> BatchConversionOutput? {
        guard case let .done(output) = item.state else { return nil }
        return output
    }

    private func singleOutputFormat(_ item: BatchConversionItem) -> String {
        singleOutput(item)?.format.displayName ?? "—"
    }

    private func singleOutputDimensions(_ item: BatchConversionItem) -> String {
        guard let output = singleOutput(item) else { return "—" }
        return "\(output.pixelWidth)×\(output.pixelHeight)"
    }

    private func singleOutputQuality(_ item: BatchConversionItem) -> Double? {
        singleOutput(item)?.quality
    }

    private func singleOutputChange(_ item: BatchConversionItem) -> String {
        guard let output = singleOutput(item) else { return "—" }
        return changeText(source: item.metadata.byteCount, output: output.byteCount)
    }

    private func singleOutputChangeTone(_ item: BatchConversionItem) -> Color {
        guard let output = singleOutput(item) else { return ToolTheme.textTertiary }
        return output.byteCount <= item.metadata.byteCount ? ToolTheme.success : ToolTheme.warning
    }

    private var completedOutputs: [BatchConversionOutput] {
        session.items.compactMap { singleOutput($0) }
    }

    private var completedSourceBytes: Int {
        session.items.reduce(0) { total, item in
            guard case .done = item.state else { return total }
            return total + item.metadata.byteCount
        }
    }

    private var completedOutputBytes: Int {
        completedOutputs.reduce(0) { $0 + $1.byteCount }
    }

    private var completedOutputTotalText: String {
        completedOutputs.isEmpty ? "—" : ByteSizeFormatter.format(bytes: completedOutputBytes)
    }

    private var batchChangeText: String {
        guard !completedOutputs.isEmpty else { return "—" }
        return changeText(source: completedSourceBytes, output: completedOutputBytes)
    }

    private var batchChangeTone: Color {
        guard !completedOutputs.isEmpty else { return ToolTheme.textTertiary }
        return completedOutputBytes <= completedSourceBytes ? ToolTheme.success : ToolTheme.warning
    }

    private var saveButtonTitle: String {
        let requiresExplicitLargerSave: Bool = {
            guard let singleItem = session.singleItem,
                  case let .done(output) = singleItem.state else { return false }
            return output.requiresExplicitLargerSave
        }()
        return ImageOutputPresentation.saveTitle(
            requiresExplicitLargerSave: requiresExplicitLargerSave,
            fallback: session.completedCount > 1 ? "全部保存" : "转换并保存"
        )
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

    private func addImages() {
        session.selectImages(
            filePanel: fileInputPanelClient,
            allowedContentTypes: ImageWorkflowClient.standardImageContentTypes,
            importPublisher: publishImportedImages,
            onImport: { convert() }
        )
    }

    private func receiveImageURLs(_ urls: [URL]) {
        session.receiveImageURLs(
            urls,
            allowedContentTypes: ImageWorkflowClient.standardImageContentTypes,
            importPublisher: publishImportedImages,
            onImport: { convert() }
        )
    }

    private func publishImportedImages(_ imported: [BatchConversionItem], _ publish: () -> Void) {
        // 新导入会改变目标格式交集，导入事务内同步校正偏好格式。
        withToolAnimation(ToolMotion.Preset.panelReveal, reduceMotion: reduceMotion) {
            publish()
            ensureSupportedTargetFormat()
        }
    }

    private func convert() {
        ensureSupportedTargetFormat()
        guard canConvert else {
            // 自定义填充色无效时给出就地诊断，而不是静默清空输出。
            if transparencyFillMode == .custom,
               requiresTransparencyFill,
               selectedTransparencyFill == nil {
                transparencyFillError = "自定义透明填充颜色无效：请输入 #RGB、#RGBA、#RRGGBB 或 #RRGGBBAA 格式的十六进制颜色。"
            } else {
                transparencyFillError = nil
            }
            session.clearOutputs()
            return
        }
        transparencyFillError = nil
        session.convertAll(rendererProvider: { converterRenderer() })
    }

    /// 移除单张会取消在途的转换轮：待转换的项在此续跑，
    /// 已完成的输出在同参数下依然有效，不参与重转。
    private func resumePendingConversions() {
        guard canConvert else { return }
        session.convertPendingItems(rendererProvider: { converterRenderer() })
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
        // 无效输入保留原文并依赖 convert() 的就地诊断，不再静默重置为白色。
        guard let color = ImageRGBColor(hex: customTransparencyFillHex) else { return }
        customTransparencyFillHex = color.hexString
    }

    private func converterRenderer() -> ImageBackgroundOutputRenderer {
        let format = targetFormat
        let outputQuality = quality
        let transparencyFill = selectedTransparencyFill

        return { input in
            let targets = ImageFileFormat.conversionTargetFormats(
                sourceFormat: input.metadata.format
            )
            guard let resolvedFormat = targets.contains(format) ? format : targets.first else {
                throw ImageProcessorError.unsupportedFormat(format)
            }

            return try ImageProcessor.convert(
                data: input.data,
                to: resolvedFormat,
                quality: resolvedFormat.supportsLossyQuality ? outputQuality : nil,
                maxPixelLength: nil,
                transparencyFill: transparencyFill
            )
        }
    }

    private func saveConverted() {
        Task { @MainActor in
            let savedCount = session.completedCount
            let outcome = await session.saveAll(defaultBasename: OutputFileNaming.timestampedBase(source: session.singleItem?.filename, fallback: "converted"), filePanel: fileInputPanelClient, outputPanel: fileOutputPanelClient)
            ImageSaveOutcomeToasts.presentCountedOutput(
                outcome,
                savedCount: savedCount,
                partialNoun: "张图片",
                toastCenter: toastCenter
            )
        }
    }
}

/// N>1 的紧凑行：缩略图 · 文件名 · 源摘要 · 状态/输出摘要 · 行移除。
private struct BatchConversionRow: View {
    let item: BatchConversionItem
    let onRemove: () -> Void

    var body: some View {
        IndexSurfaceRow(horizontalPadding: 10, verticalPadding: 8) {
            HStack(alignment: .center, spacing: ToolMetrics.Spacing.md) {
                IndexImagePreviewImage(
                    image: item.thumbnail,
                    accessibilityLabel: "待转换的原图",
                    accessibilityValue: item.filename,
                    maxDisplayWidth: 44,
                    maxDisplayHeight: 44
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.filename)
                        .font(ToolTypography.bodyPlain)
                        .foregroundStyle(ToolTheme.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(ImageOutputPresentation.sourceSummary(item.metadata))
                        .font(ToolTypography.caption)
                        .foregroundStyle(ToolTheme.textSecondary)
                        .lineLimit(1)
                }

                Spacer(minLength: ToolMetrics.Spacing.sm)

                statusView

                IndexIconButton(
                    systemImage: IndexActionSymbol.removeResource,
                    help: "移除 \(item.filename)",
                    action: onRemove
                )
            }
        }
    }

    @ViewBuilder
    private var statusView: some View {
        switch item.state {
        case .idle:
            Text("待转换")
                .font(ToolTypography.caption)
                .foregroundStyle(ToolTheme.textSecondary)
        case .converting:
            IndexProgressSpinner()
                .accessibilityLabel("正在转换图片")
        case let .done(output):
            Text(output.summaryText)
                .font(ToolTypography.caption)
                .foregroundStyle(output.requiresExplicitLargerSave ? ToolTheme.warning : ToolTheme.textSecondary)
                .lineLimit(1)
        case let .failed(message):
            Text(message)
                .font(ToolTypography.caption)
                .foregroundStyle(ToolTheme.warning)
                .lineLimit(2)
                .multilineTextAlignment(.trailing)
        }
    }
}
