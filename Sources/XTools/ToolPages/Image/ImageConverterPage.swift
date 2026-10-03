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
            && (!requiresTransparencyFill || selectedTransparencyFill != nil)
    }

    private var requiresTransparencyFill: Bool {
        guard !targetFormat.preservesAlpha else { return false }
        return session.items.contains { $0.metadata.transparency != .opaque }
    }

    private var selectedTransparencyFill: ImageRGBColor? {
        transparencyFillMode.color(customHex: customTransparencyFillHex)
    }

    var body: some View {
        // 间距对齐 IndexPage 标准页面壳的 sectionSpacing（10），与两段平铺时视觉一致。
        // 拖放命中区挂整个内容根容器（参数区、列表、空白处均可接收），但保持静默：
        // 视觉高亮由输入区内容层经共享 isImageDropTargeted 呈现——命中范围大、
        // 指示只标输入框，与常规 App 的拖放语义一致。
        VStack(alignment: .leading, spacing: 10) {
            IndexActionBar {
                IndexOptionGroup {
                    IndexOptionLabel("目标格式")
                    if outputFormats.isEmpty {
                        Text(session.items.isEmpty ? "选择图片后显示" : "无可转换目标")
                            .font(ToolTypography.caption)
                            .foregroundStyle(ToolTheme.textSecondary)
                            .fixedSize(horizontal: true, vertical: false)
                    } else {
                        IndexSegmentedControl(
                            items: outputFormats.map { ($0, $0.displayName) },
                            selection: $targetFormat,
                            selectionStyle: .filled
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
                    IndexOptionGroup {
                        IndexOptionLabel("质量")
                        IndexSlider(value: $quality, range: 0.1...1.0, step: 0)
                            .frame(width: 160)
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
                        Text("\(Int(quality * 100))%")
                            .font(ToolTypography.monoCaption)
                            .foregroundStyle(ToolTheme.textSecondary)
                            .frame(width: 40)
                    }
                }

                if requiresTransparencyFill {
                    IndexOptionGroup {
                        IndexOptionLabel("透明填充")
                        IndexSegmentedControl(
                            items: [
                                (ImageTransparencyFillMode.white, "白色"),
                                (.black, "黑色"),
                                (.custom, "自定义")
                            ],
                            selection: $transparencyFillMode,
                            selectionStyle: .filled
                        )
                        .accessibilityLabel("透明区域填充颜色")
                        .accessibilityValue(transparencyFillAccessibilityValue)
                        .onChange(of: transparencyFillMode) { _ in convert() }

                        if transparencyFillMode == .custom {
                            IndexTextInput(
                                placeholder: "#RGB 或 #RRGGBB",
                                text: $customTransparencyFillHex,
                                height: 30,
                                alignment: .center,
                                selectAllOnFocus: true,
                                onSubmit: normalizeCustomTransparencyFillHex
                            )
                            .frame(width: 118)
                            .accessibilityLabel("自定义透明区域填充颜色")
                            .accessibilityValue(customTransparencyFillAccessibilityValue)
                            .onChange(of: customTransparencyFillHex) { _ in convert() }
                        }
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel("透明区域填充颜色")
                    .accessibilityValue(transparencyFillAccessibilityValue)
                    .help("JPEG 和 HEIC 不支持透明区域；请选择转换前用于填充透明像素的颜色。")
                    // 自定义色无效时就地诊断（页面外壳按优先级合并 workspace 诊断），
                    // 不再让 convert() 静默清空输出。
                    .indexWorkspaceDiagnostic(transparencyFillError)
                }

            }

            IndexPanel("上传图片") {
                VStack(alignment: .leading, spacing: ToolMetrics.Spacing.md) {
                    imageSelectionActions

                    if session.items.isEmpty {
                        // 空态在铺满的输入区内垂直居中，构成完整的拖放区观感。
                        ImageUploadPendingState(isProcessing: session.isImporting, title: "选择图片开始转换", fillsHeight: true)
                    } else if let singleItem = session.singleItem {
                        singleImageStage(singleItem)
                    } else {
                        batchList
                    }
                }
                .indexWorkspaceDiagnostic(session.error)
                // 输入区铺满面板剩余高度：拖放高亮（imageDropHighlight）随之
                // 覆盖整个下方区域，而不是只包住当前内容。
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.vertical, ToolMetrics.Spacing.sm)
                .imageDropHighlight(isActive: isImageDropTargeted)
            }
            .verticallyFilling()
            .onAppear(perform: ensureSupportedTargetFormat)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .multiImageInputDropDestination(
            isTargeted: $isImageDropTargeted,
            onFiles: receiveImageURLs,
            showsHighlight: false
        )
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
            clearTitle: "清空图片"
        )
    }

    /// N=1 时行密度放宽：大缩略图 + 底部摘要/保存按钮，贴近既有单张观感。
    private func singleImageStage(_ item: BatchConversionItem) -> some View {
        IndexImagePreviewStage(
            image: session.sourceImage,
            accessibilityLabel: "待转换的原图",
            maxDisplayWidth: 560,
            maxDisplayHeight: 260,
            spacing: ToolMetrics.Spacing.md
        ) {
            Text("原图: \(ImageOutputPresentation.sourceSummary(item.metadata))")
                .font(ToolTypography.caption)
                .foregroundStyle(ToolTheme.textSecondary)

            if case .converting = item.state {
                IndexProgressSpinner()
            }

            if case let .done(output) = item.state {
                Text("输出: \(output.summaryText)\(transparencyFillOutputSuffix)")
                    .font(ToolTypography.caption)
                    .foregroundStyle(output.requiresExplicitLargerSave ? ToolTheme.warning : ToolTheme.textSecondary)
            }

            if case let .failed(message) = item.state {
                Text(message)
                    .font(ToolTypography.caption)
                    .foregroundStyle(ToolTheme.warning)
            }

            Button {
                saveConverted()
            } label: {
                Label(saveButtonTitle, systemImage: IndexActionSymbol.save)
                    .font(ToolTypography.buttonSmall)
            }
            .buttonStyle(IndexSmallButtonStyle())
            .disabled(session.completedCount == 0 || session.isProcessing)
        }
    }

    /// N>1 紧凑行 + 顶部统计。
    private var batchList: some View {
        VStack(alignment: .leading, spacing: ToolMetrics.Spacing.sm) {
            HStack(spacing: 8) {
                Text(batchStatisticsText)
                    .font(ToolTypography.caption)
                    .foregroundStyle(ToolTheme.textSecondary)
                Spacer(minLength: 8)
                Button {
                    saveConverted()
                } label: {
                    Label(saveButtonTitle, systemImage: IndexActionSymbol.save)
                        .font(ToolTypography.buttonSmall)
                }
                .buttonStyle(IndexSmallButtonStyle())
                .disabled(session.completedCount == 0 || session.isProcessing)
            }

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

    private var batchStatisticsText: String {
        var parts = ["共 \(session.items.count) 张"]
        if session.completedCount > 0 {
            parts.append("\(session.completedCount) 张完成")
        }
        if session.failedCount > 0 {
            parts.append("\(session.failedCount) 张失败")
        }
        return parts.joined(separator: " · ")
    }

    private var saveButtonTitle: String {
        if let singleItem = session.singleItem,
           case let .done(output) = singleItem.state,
           output.requiresExplicitLargerSave {
            return "仍然保存更大的文件"
        }
        return session.completedCount > 1 ? "全部保存" : "转换并保存"
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
            switch await session.saveAll(defaultBasename: "converted", filePanel: fileInputPanelClient, outputPanel: fileOutputPanelClient) {
            case .saved:
                if session.completedCount > 1 {
                    toastCenter?.show(ToolFeedbackCopy.saved(count: session.completedCount), tone: .success)
                } else {
                    toastCenter?.show(ToolFeedbackCopy.savedFile, tone: .success)
                }
            case let .partiallySaved(savedCount, totalCount):
                toastCenter?.show("已保存 \(savedCount)/\(totalCount) 张图片。", tone: .warning)
            case let .failed(message):
                toastCenter?.show(message, tone: .error)
            case .cancelled, .blocked:
                break
            }
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

                Spacer(minLength: 8)

                statusView

                Button(action: onRemove) {
                    Image(systemName: IndexActionSymbol.removeResource)
                        .font(ToolTypography.buttonSmall)
                }
                .buttonStyle(IndexSmallButtonStyle())
                .accessibilityLabel("移除 \(item.filename)")
            }
        }
    }

    @ViewBuilder
    private var statusView: some View {
        switch item.state {
        case .idle:
            Text("待转换")
                .font(ToolTypography.monoCaption)
                .foregroundStyle(ToolTheme.textSecondary)
        case .converting:
            IndexProgressSpinner()
        case let .done(output):
            Text(output.summaryText)
                .font(ToolTypography.monoCaption)
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
