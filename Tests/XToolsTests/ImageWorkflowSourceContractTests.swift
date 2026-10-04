import Foundation
import AppKit
@testable import XTools
import Testing

struct ImageWorkflowSourceContractTests {
    @Test func imageSaveActionsShowSuccessToastOnlyAfterConfirmedSave() throws {
        let uploadSupport = try readSource("Sources/XTools/ToolPages/Image/ImageWorkflowSupport.swift")
        let converter = try readSource("Sources/XTools/ToolPages/Image/ImageConverterPage.swift")
        let compressor = try readSource("Sources/XTools/ToolPages/Image/ImageCompressorPage.swift")
        let grayscale = try readSource("Sources/XTools/ToolPages/Image/ImageGrayscalePage.swift")
        let watermark = try readSource("Sources/XTools/ToolPages/Image/ImageWatermarkPage.swift")
        let favicon = try readSource("Sources/XTools/ToolPages/Image/FaviconGeneratorPage.swift")

        for page in [converter, compressor, grayscale, watermark, favicon] {
            contains(page, "@Environment(\\.toolToastCenter) private var toastCenter", "Image save pages must use the shared toast center for successful save feedback")
        }

        // 成功提示只在 session 返回 .saved 时显示（取消返回 .cancelled、阻止返回 .blocked
        // 都不弹成功 toast）；写盘失败返回 .failed 时弹 error toast；部分成功由计数
        // 映射降级为 warning，其余单输出页对不可能出现的部分结果保持静默。
        // 各页 outcome→toast switch 全部收敛进共享 ImageSaveOutcomeToasts 后，
        // 映射断言改锚共享文件，页面断言改锚路由调用。
        contains(uploadSupport, "case .saved:\n            if let fileName {", "The shared single-output toast mapper must branch on a caller-known file name")
        contains(uploadSupport, "toastCenter?.show(ToolFeedbackCopy.saved(fileName: fileName), tone: .success)", "The shared single-output toast mapper must name the saved file when the caller knows it")
        contains(uploadSupport, "toastCenter?.show(ToolFeedbackCopy.savedFile, tone: .success)", "The shared save mappers must fall back to the generic single-file success copy")
        contains(uploadSupport, "case let .failed(message):\n            toastCenter?.show(message, tone: .error)", "The shared single-output toast mapper must surface a real save failure as an error toast")
        contains(uploadSupport, "case .cancelled, .blocked, .partiallySaved:\n            break", "The shared single-output toast mapper must stay silent for impossible partial outcomes as well as cancel/block")
        for (page, name) in [(compressor, "compressor"), (grayscale, "grayscale"), (watermark, "watermark")] {
            contains(page, "ImageSaveOutcomeToasts.presentSingleOutput(outcome, toastCenter: toastCenter)", "Image \(name) save must route its outcome through the shared single-output toast mapper")
            // 保存面板已 sheet 化：会话保存必须同时接入输入面板与输出面板客户端。
            contains(page, "await session.save(workflow:", "Image \(name) save must await the session's sheet-based save pipeline")
            contains(page, "filePanel: fileInputPanelClient, outputPanel: fileOutputPanelClient", "Image \(name) save must route through the window-scoped sheet panel clients")
        }

        // 计数保存映射（批量转换 + Favicon 整包）：多件成功走计数词表、单件
        // 成功与单输出页同词表、部分成功降级 warning 并保留安全计数、写盘
        // 失败报 error、取消/阻止静默。页面只锚路由调用与各自的计数词表。
        occurrenceCount(uploadSupport, "case let .failed(message):\n            toastCenter?.show(message, tone: .error)", 2, "Every shared save-outcome mapper must surface real save failures as error toasts")
        contains(uploadSupport, "toastCenter?.show(ToolFeedbackCopy.saved(count: savedCount, noun: successNoun), tone: .success)", "The shared counted-save mapper must use the counted save copy for multi-file successes")
        occurrenceCount(uploadSupport, "toastCenter?.show(ToolFeedbackCopy.savedFile, tone: .success)", 2, "Both shared save mappers must fall back to the single-file copy for one saved file")
        contains(uploadSupport, "case let .partiallySaved(partiallySavedCount, totalCount):", "The shared counted-save mapper must handle partial saves structurally")
        contains(uploadSupport, "已保存 \\(partiallySavedCount)/\\(totalCount) \\(partialNoun)。", "The shared counted-save mapper must keep the safe saved/total count concise")
        contains(uploadSupport, "\"已保存 \\(partiallySavedCount)/\\(totalCount) \\(partialNoun)。\", tone: .warning", "The shared counted-save mapper must present partial saves as warning feedback")
        contains(uploadSupport, "case .cancelled, .blocked:\n            break", "The shared counted-save mapper must stay silent for cancel/block save outcomes")
        contains(converter, "ImageSaveOutcomeToasts.presentCountedOutput(", "Image converter must route its batch save outcome through the shared counted-save mapper")
        contains(converter, "savedCount: session.completedCount", "Image converter must report its actual completed count to the shared mapper")
        contains(converter, "partialNoun: \"张图片\"", "Image converter partial-save feedback must keep its image-specific count noun")
        contains(converter, "filePanel: fileInputPanelClient, outputPanel: fileOutputPanelClient", "Image converter save must route through the window-scoped sheet panel clients")
        contains(favicon, "ImageSaveOutcomeToasts.presentCountedOutput(", "Favicon package save must route its outcome through the shared counted-save mapper")
        contains(favicon, "savedCount: package.saveableArtifacts.count", "Favicon package save must derive its count from the actual saveable artifacts")
        contains(favicon, "successNoun: \"部署文件\"", "Favicon package save success must keep the deployment-file noun")
        contains(favicon, "partialNoun: \"个部署文件\"", "Favicon partial-save feedback must keep the deployment-file count noun")
        contains(favicon, "handleSave(await session.saveArtifact(artifact.id, filePanel: fileInputPanelClient, outputPanel: fileOutputPanelClient)", "Favicon single-artifact save must route its confirmed outcome through one toast mapper over the sheet panel clients")
        contains(favicon, "ImageSaveOutcomeToasts.presentSingleOutput(outcome, fileName: filename, toastCenter: toastCenter)", "Favicon single-artifact save must route its confirmed outcome through the shared named-file mapper")
    }

    @Test func imageSourceAndResetTransitionsUseSharedPanelRevealMotion() throws {
        let uploadSupport = try readSource("Sources/XTools/ToolPages/Image/ImageWorkflowSupport.swift")
        let converter = try readSource("Sources/XTools/ToolPages/Image/ImageConverterPage.swift")
        let compressor = try readSource("Sources/XTools/ToolPages/Image/ImageCompressorPage.swift")
        let grayscale = try readSource("Sources/XTools/ToolPages/Image/ImageGrayscalePage.swift")
        let watermark = try readSource("Sources/XTools/ToolPages/Image/ImageWatermarkPage.swift")
        let favicon = try readSource("Sources/XTools/ToolPages/Image/FaviconGeneratorPage.swift")
        let faviconSession = try readSource("Sources/XTools/ToolPages/Image/FaviconOutputSetSession.swift")

        // 源发布的 panelReveal 事务收敛进共享 ImageUploadInteractions 后，
        // 事务断言改锚共享文件，页面断言改锚发布器装配。
        contains(uploadSupport, "func publishSelection(_ selection: ImageInputSelection, _ publish: () -> Void)", "The shared upload interactions must keep source publication motion page-owned")
        contains(uploadSupport, "withToolAnimation(ToolMotion.Preset.panelReveal, reduceMotion: reduceMotion) {\n            publish()\n        }", "The shared upload interactions must execute the session source assignment inside the shared motion transaction")
        for (page, name) in [
            (compressor, "compressor"),
            (grayscale, "grayscale"),
            (watermark, "watermark"),
            (favicon, "favicon")
        ] {
            contains(page, "@Environment(\\.accessibilityReduceMotion) private var reduceMotion", "Image \(name) must honor Reduce Motion for source-workspace transitions")
            doesNotContain(page, "sourceRevealGeneration", "Image \(name) must not use a post-publication nonce that misses the source transition")
            contains(page, "selectionPublisher: uploadInteractions.publishSelection", "Image \(name) must publish accepted selections inside the page-owned motion transaction")
            contains(page, "withToolAnimation(ToolMotion.Preset.panelReveal, reduceMotion: reduceMotion)", "Image \(name) clear/reject transitions must enter an explicit shared motion transaction")
        }

        // 批量转换页的导入发布沿用同一 motion 所有权，只是发布单位从单张换成一批。
        contains(converter, "@Environment(\\.accessibilityReduceMotion) private var reduceMotion", "Image converter must honor Reduce Motion for source-workspace transitions")
        doesNotContain(converter, "sourceRevealGeneration", "Image converter must not use a post-publication nonce that misses the source transition")
        contains(converter, "importPublisher: publishImportedImages", "Image converter must publish accepted imports inside the page-owned motion transaction")
        contains(converter, "withToolAnimation(ToolMotion.Preset.panelReveal, reduceMotion: reduceMotion)", "Image converter clear/remove transitions must enter an explicit shared motion transaction")
        contains(converter, "private func publishImportedImages(_ imported: [BatchConversionItem], _ publish: () -> Void)", "Image converter must keep import publication motion page-owned")
        contains(converter, "publish()", "Image converter must execute the session item assignment inside the shared motion transaction")
        contains(converter, "publish()\n            ensureSupportedTargetFormat()", "Image converter must preserve its source-aware target update after publishing accepted imports")
        contains(faviconSession, "selectionPublisher: @escaping ImageSelectionPublisher", "Favicon selection must expose the same page-owned source publication seam as processed image sessions")
        contains(faviconSession, "selectionPublisher(selection) {", "Favicon selection must publish only a valid prepared source through that seam")
    }

    @Test func imageConverterUsesActualOutputInsteadOfFormatPredictions() throws {
        let converter = try readSource("Sources/XTools/ToolPages/Image/ImageConverterPage.swift")
        let session = try readSource("Sources/XTools/ToolPages/Image/ImageBatchConversionSession.swift")
        let outputPresentation = try readSource("Sources/XTools/ToolPages/Image/ImageOutputPresentation.swift")

        doesNotContain(converter, "PNG 是无损兼容格式。JPEG 已丢失的细节不会恢复", "Image converter must not show tutorial-like PNG growth predictions")
        doesNotContain(converter, "TIFF 是归档/兼容用无损格式。它不会让 JPEG 变清晰", "Image converter must not show tutorial-like TIFF growth predictions")
        doesNotContain(converter, "conversionNotice", "Image converter must not keep a second predictive notice path")
        contains(session, "ImageOutputPolicy.assess(output, for: .conversion)", "Image converter must evaluate output facts from the actual rendered output")
        contains(session, "ImageOutputPresentation.processingOutputSummary(assessment)", "Image converter must precompute the actual output format and size change at conversion time")
        contains(converter, "output.summaryText", "Image converter must show the precomputed actual output facts instead of re-assessing in views")
        doesNotContain(converter, "ImageOutputPolicy.assess", "Image converter views must not re-assess outputs; conversion records carry precomputed facts")
        contains(converter, "output.requiresExplicitLargerSave ? ToolTheme.warning : ToolTheme.textSecondary", "Image converter must emphasize an actual larger output")
        // 「仍然保存更大的文件」词表收敛进 ImageOutputPresentation.saveTitle 后，
        // 字面量断言改锚共享词表，页面断言改锚词表路由。
        contains(converter, "ImageOutputPresentation.saveTitle(", "Image converter must derive its conditional save title from the shared larger-file save vocabulary")
        contains(outputPresentation, "仍然保存更大的文件", "The shared save-title vocabulary must keep the explicit larger-file save wording")
    }

    @Test func watermarkUsesSourceMatchedLossyQualityWithoutCompressionSearch() throws {
        let processor = [
            try readSource("Sources/XToolsCore/Image/ImageProcessor.swift"),
            try readSource("Sources/XToolsCore/Image/ImageProcessorSupport.swift"),
            try readSource("Sources/XToolsCore/Image/ImageProcessingModels.swift"),
        ].joined(separator: "\n")
        let jpegQuality = try readSource("Sources/XToolsCore/Image/JPEGSourceEncodingQuality.swift")
        let watermark = try readSource("Sources/XTools/ToolPages/Image/ImageWatermarkPage.swift")

        contains(processor, "JPEGSourceEncodingQuality.matchedImageIOQuality(for: sourceData)", "JPEG watermark output must match the source quantization signature instead of always requesting maximum quality")
        contains(processor, "watermarkFallbackLossyQuality: Double = 0.92", "Lossy watermark formats without a reliable source-quality match must use the approved high-quality fallback")
        contains(processor, "lossyQualityOverride.map(clampedQuality)", "The legacy explicit-quality overload must retain its caller-owned quality contract")
        doesNotContain(processor, "format.supportsLossyQuality ? highFidelityEncodingQuality : nil", "Watermark output must not upgrade every lossy source to maximum ImageIO quality")
        contains(jpegQuality, "for percentage in 5...100", "JPEG source matching must calibrate tiny ImageIO quality buckets instead of copying a fixed platform mapping")
        contains(jpegQuality, "JPEGQuantizationTables(data: data)", "JPEG source matching must be driven by DQT facts")
        doesNotContain(jpegQuality, "originalByteCount", "JPEG source matching must not target the original file byte count")
        doesNotContain(jpegQuality, "qualityCandidates", "JPEG source matching must not reuse the compression workflow's downward quality search")
        doesNotContain(watermark, #"IndexOptionLabel("质量")"#, "The watermark toolbar must remain focused on watermark controls rather than expose compression settings")
    }


    @Test func liveWatermarkPreviewKeepsStableGeometryAndImmediateDiscreteFeedback() throws {
        let stage = try readSource("Sources/XTools/ToolPages/Image/ImagePreviewStage.swift")
        let watermark = try readSource("Sources/XTools/ToolPages/Image/ImageWatermarkPage.swift")

        contains(stage, "enum IndexImagePreviewReplacementMotion", "The shared image stage must expose an explicit image-replacement motion policy")
        occurrenceCount(stage, "replacementMotion: IndexImagePreviewReplacementMotion = .animated", 2, "Both shared preview-stage initializers must preserve animated replacement as the default for existing callers")
        contains(stage, "replacementMotion == .animated", "The stage must retain image-identity animation only for the default replacement policy")
        contains(stage, "transaction.disablesAnimations = true", "Immediate live replacements must suppress inherited raster crossfades as well as the explicit stage animation")
        contains(watermark, "replacementMotion: .immediate", "The live watermark canvas must opt out of whole-stage replacement animation")
        contains(watermark, "private static let previewStatusHeight: CGFloat = 18", "Watermark preview status must reserve a stable geometry line")
        contains(watermark, ".frame(height: Self.previewStatusHeight", "Watermark processing and output status changes must not resize the canvas proposal")
        contains(watermark, "recipeDidChange(previewCadence: .immediate)", "Watermark position and color controls must request immediate bounded preview feedback")
        occurrenceCount(watermark, "recipeDidChange(previewCadence: .debounced)", 3, "Watermark text, opacity, and font-size edits must retain bounded preview debounce")
        contains(watermark, "case .immediate:", "Watermark recipe updates must have a direct bounded-render path for discrete controls")
        contains(watermark, "case .debounced:", "Watermark recipe updates must retain the shared short debounce path for continuous controls")
        contains(watermark, "finalDebouncer.schedule(Self.finalDebounceDelay)", "Every watermark recipe path must retain delayed source-resolution final rendering")
        doesNotContain(watermark, "withAnimation(.spring", "Watermark anchors must not animate through unrequested intermediate positions")
    }

    @Test func imageToolsUseNonScrollingPreviewStagesWithDisplayBounds() throws {
        let stage = try readSource("Sources/XTools/ToolPages/Image/ImagePreviewStage.swift")
        let uploadSupport = try readSource("Sources/XTools/ToolPages/Image/ImageWorkflowSupport.swift")
        let imageHub = try readSource("Sources/XTools/ToolPages/Image/ImageHubPage.swift")
        let favicon = try readSource("Sources/XTools/ToolPages/Image/FaviconGeneratorPage.swift")
        let converter = try readSource("Sources/XTools/ToolPages/Image/ImageConverterPage.swift")
        let compressor = try readSource("Sources/XTools/ToolPages/Image/ImageCompressorPage.swift")
        let grayscale = try readSource("Sources/XTools/ToolPages/Image/ImageGrayscalePage.swift")
        let watermark = try readSource("Sources/XTools/ToolPages/Image/ImageWatermarkPage.swift")
        let outputPresentation = try readSource("Sources/XTools/ToolPages/Image/ImageOutputPresentation.swift")
        let workflow = [
            try readSource("Sources/XTools/ToolPages/Image/ImageWorkflowClient.swift"),
            try readSource("Sources/XTools/ToolPages/Image/ImageWorkflowModels.swift"),
            try readSource("Sources/XTools/ToolPages/Image/ImageProcessedOutputSession.swift"),
            try readSource("Sources/XTools/ToolPages/Image/ImageBatchConversionSession.swift"),
        ].joined(separator: "\n")
        let faviconSession = try readSource("Sources/XTools/ToolPages/Image/FaviconOutputSetSession.swift")
        let filePanel = try readSource("Sources/XTools/Shared/FileInputPanel.swift")
        let processor = [
            try readSource("Sources/XToolsCore/Image/ImageProcessor.swift"),
            try readSource("Sources/XToolsCore/Image/ImageProcessorSupport.swift"),
            try readSource("Sources/XToolsCore/Image/ImageProcessingModels.swift"),
        ].joined(separator: "\n")
        let preferences = try readSource("Sources/XTools/AppShell/ToolPreferenceStore.swift")

        contains(stage, "struct IndexImagePreviewStage", "Image tools must share an explicit image preview stage semantic")
        contains(stage, "enum IndexImagePreviewStageMetrics", "Image preview stage metrics must stay in one non-generic namespace")
        contains(stage, "static let defaultMaxDisplayWidth: CGFloat = 720", "Image preview stages must define a maximum display width")
        contains(stage, "static let defaultMaxDisplayHeight: CGFloat = 480", "Image preview stages must define a maximum display height")
        contains(stage, ".aspectRatio(contentMode: .fit)", "Image preview stages must show complete proportional images")
        contains(stage, ".frame(maxWidth: maxDisplayWidth, maxHeight: maxDisplayHeight)", "Image preview images must be bounded in both dimensions")
        contains(stage, "let accessibilityLabel: String", "Image preview stages must require caller-owned accessibility names")
        contains(stage, "var accessibilityValue = \"\"", "Image preview stages must support caller-owned result facts")
        contains(stage, ".accessibilityLabel(accessibilityLabel)", "Image preview images must publish their semantic identity")
        contains(stage, ".accessibilityValue(accessibilityValue)", "Image preview images must publish their relevant facts")
        contains(stage, ".toolAnimation(ToolMotion.Preset.controlFeedback, value: isTargeted)", "Image drop targeting feedback must honor the shared motion contract")
        doesNotContain(stage, "ScrollView {", "Image preview stages must not create an internal scroll container")

        // 四个图片工具合并为单入口「图片处理」后，workspaceSemantic 页面壳断言统一改锚 Hub。
        contains(imageHub, "workspaceSemantic: .imagePreviewStage", "The image hub must declare the image preview stage workspace semantic at the page shell")
        // 水印并入 Hub 第五段：断言改锚分段装配，页面壳语义随 Hub 外层滚动。
        contains(imageHub, "case .watermark: IndexImageWatermarkSegment()", "The image hub must mount the watermark workflow as a first-class segment")

        contains(favicon, "IndexImagePreviewStage(\n                            image: image", "Favicon upload preview must use the non-scrolling image preview stage")
        contains(favicon, "maxDisplayWidth: 120", "Favicon source preview must stay compact so generated assets remain primary")
        contains(favicon, "private var faviconSourceSummary", "Favicon source must publish a compact factual summary instead of a second large workspace")
        contains(workflow, "case partiallySaved(savedCount: Int, totalCount: Int)", "Image save outcomes must preserve partial Favicon progress structurally")
        contains(faviconSession, "case let .partialSaveFailed(savedCount, totalCount)", "Favicon session must map only structured partial-save failures to a partial outcome")
        contains(faviconSession, ".partiallySaved(savedCount: savedCount, totalCount: totalCount)", "Favicon session must return safe saved/total counts")
        // 批量转换：轻量导入（不驻留原图 data）+ 世代取消串行转换 + 批量保存委托。
        contains(workflow, "final class ImageBatchConversionSession", "Batch conversion state must live behind its own retained session")
        contains(workflow, "func prepareImportOverview(", "Batch import must reuse the shared preparation pipeline through a lightweight overview")
        contains(workflow, "client.prepareImportOverview", "Batch conversion session must import through the platform client seam")
        contains(workflow, "func saveConvertedImages(", "Batch conversion saves must flow through the platform client seam")
        contains(workflow, "client.saveConvertedImages", "Batch conversion session must delegate directory saves to the platform client seam")
        contains(workflow, "func saveConvertedImage(", "Single converted-output saves must flow through the platform client seam")
        contains(workflow, "client.prepareSelectionInBackground", "Batch conversion re-reads each item through the shared URL preparation pipeline")
        contains(workflow, "renderGate.invalidate()", "Batch conversion re-runs must supersede the previous generation through AsyncWorkGate")
        contains(workflow, "renderGate.isCurrent(generation)", "Batch conversion must protect against stale background results")
        contains(workflow, "static let defaultMaximumItemCount = 100", "Batch conversion must bound the list and save loop scale while outputs stay spooled on disk")
        contains(workflow, "func evictHeavyPayloads()", "Batch conversion session must keep workspace eviction semantics")
        // Favicon 部分保存的呈现语义已收敛进共享计数映射（见保存 toast 测试），
        // 页面断言改锚路由调用；禁词保留在页面层防止文案回潮。
        contains(favicon, "ImageSaveOutcomeToasts.presentCountedOutput(", "Favicon page must handle partial saves through the shared counted-save mapper")
        doesNotContain(favicon, "其余图标保存失败", "Favicon partial-save feedback must not restate what the warning tone and count already show")
        contains(converter, "IndexImagePreviewStage(\n            image: session.sourceImage", "Image converter single-image preview must use the non-scrolling image preview stage")
        contains(converter, ".indexWorkspaceDiagnostic(session.error)", "Image converter errors must remain visible through the non-displacing diagnostic anchor")
        doesNotContain(converter, "IndexPanel(\"转换预览\")", "Image converter must not keep the separate lower conversion preview panel")
        doesNotContain(converter, "IndexImagePreviewStage(image: session.outputImage", "Image converter must not replace the removed preview panel with another output preview")
        contains(compressor, "IndexImageComparisonCard(", "Image compressor comparison panes must use the shared comparison card component")
        contains(compressor, "IndexPairLayout(collapseWidth: 0)", "Image compressor cards must stay side-by-side throughout the validated desktop window range")
        doesNotContain(compressor, "IndexPairLayout(collapseWidth: 760)", "Image compressor must not vertically reflow inside the validated 960-point window floor")
        contains(compressor, "isProcessing: session.isProcessing", "Image compressor result card must own its in-card processing state")
        contains(compressor, "isProcessing: session.isProcessing", "Image compressor must hand its in-card processing state to the shared comparison card")
        contains(compressor, "return \"正在优化图片\"", "Image compressor processing state must publish a concise accessibility value")
        doesNotContain(compressor, ".accessibilityLabel(\"图片优化偏好\")", "Image compressor picker must preserve distinct accessibility names for each optimization option")
        contains(compressor, "title: \"原图\"", "Image compressor source card must identify the original image inside the card")
        contains(compressor, "title: \"优化结果\"", "Image compressor result card must identify the optimized image inside the card")
        contains(compressor, "Text(\"原始大小\")", "Image compressor source facts must stay inside the source card")
        contains(compressor, "Text(\"输出大小\")", "Image compressor output facts must stay inside the result card")
        contains(compressor, "badgeText: compressionChangeText", "Image compressor savings must belong to the result card header")
        contains(compressor, "accessibilityValue: sourcePreviewAccessibilityValue", "Image compressor source preview must expose its own facts")
        contains(compressor, "accessibilityValue: resultPreviewAccessibilityValue", "Image compressor result preview must expose output facts")
        doesNotContain(compressor, "compressionComparisonFooter", "Image compressor must not leave a detached fact block below the comparison")
        doesNotContain(compressor, "IndexImageComparisonStage", "Image compressor must not use the rejected label-plus-bare-image abstraction")
        contains(grayscale, "IndexImageComparisonCard(", "Image grayscale source and result must each own one complete comparison card via the shared component")
        contains(grayscale, "IndexPairLayout(collapseWidth: 0)", "Image grayscale comparison must stay side-by-side throughout the supported desktop window range")
        contains(grayscale, "accessibilityLabel: \"灰阶转换原图预览\"", "Image grayscale source card must expose a named preview")
        contains(grayscale, "accessibilityLabel: \"灰阶转换结果预览\"", "Image grayscale result card must expose a named preview")
        doesNotContain(grayscale, "accessibilityLabel: \"灰阶转换对比预览\"", "Image grayscale must not duplicate the output in a second preview path")
        contains(watermark, "accessibilityLabel: \"水印源图片缩略图\"", "Image watermark source must be a compact identity thumbnail rather than a second large canvas")
        contains(watermark, "maxDisplayWidth: 64", "Image watermark source thumbnail must stay compact enough to preserve the live result viewport")
        contains(watermark, "fillsHeight: true,\n                            replacementMotion: .immediate", "Image watermark result canvas must fill the segment workspace and replace previews immediately")
        contains(watermark, "ViewThatFits(in: .horizontal)", "Image watermark source identity must compactly reflow instead of reserving a tall upload summary")
        contains(watermark, "HStack(alignment: .center, spacing: 24)", "Wide watermark upload content must keep text and source identity in one compact leading group")
        doesNotContain(watermark, "Spacer(minLength: 0)", "Wide watermark upload content must not create a large empty gap between text and source identity")
        contains(watermark, ".frame(minWidth: 220, idealWidth: 300, maxWidth: .infinity)", "The watermark text field must absorb surplus upload width so wide windows do not leave a disconnected dead zone")
        doesNotContain(watermark, "uploadPanelMaximumWidth", "The upload panel must continue participating in the page's full-width responsive layout")
        contains(watermark, ".popover(isPresented: $isPickerPresented", "Image watermark must keep the nine-anchor picker available without permanently increasing the toolbar height")
        contains(watermark, "Image(systemName: \"square.grid.3x3\")", "Image watermark must expose the compact spatial-position trigger")
        contains(watermark, "image: resultPreviewImage,\n                            accessibilityLabel: \"水印成品预览\"", "Image watermark result must be the only primary preview canvas")
        contains(watermark, "onSubmit: applyFinalImmediately", "Image watermark text submit must immediately generate the latest full-resolution result")
        contains(watermark, ".onChange(of: watermarkText) { _ in recipeDidChange(previewCadence: .debounced) }", "Image watermark text changes must enter bounded preview and debounced final pipelines")
        contains(watermark, "previewDebouncer.schedule(Self.previewDebounceDelay)", "Image watermark rapid changes must coalesce bounded preview work")
        contains(watermark, "finalDebouncer.schedule(Self.finalDebounceDelay)", "Image watermark rapid changes must coalesce full-resolution work separately")
        contains(watermark, "workGate.runDetached", "Image watermark bounded preview rendering must run off the main actor through AsyncWorkGate")
        doesNotContain(watermark, "pendingWatermarkTextPreview", "Image watermark must not keep a focus-gated stale-text flag")
        contains(favicon, "Image(nsImage: image)", "Favicon package rows may render fixed-size output thumbnails directly")
        contains(favicon, "private func previewLength(_ size: Int) -> CGFloat", "Large favicon outputs must use bounded preview thumbnails")
        contains(favicon, ".frame(width: previewLength(size), height: previewLength(size))", "Favicon generated thumbnails must stay bounded")
        contains(faviconSession, "FaviconOutputSpec(size: 180)", "Favicon output set must include the Apple touch icon size")
        contains(faviconSession, "FaviconOutputSpec(size: 192)", "Favicon output set must include the package's common PWA icon size")
        contains(faviconSession, "FaviconOutputSpec(size: 512)", "Favicon output set must include the package's large PWA icon size")
        doesNotContain(faviconSession, "FaviconOutputSpec(size: 64)", "The deployment package must not retain the legacy standalone 64px PNG")
        doesNotContain(faviconSession, "FaviconOutputSpec(size: 128)", "The deployment package must not retain the legacy standalone 128px PNG")

        doesNotContain(favicon, "ScrollView {", "Favicon image previews must rely on the tool page outer scroll owner")
        doesNotContain(converter, "ScrollView {", "Image converter previews must rely on the tool page outer scroll owner")
        doesNotContain(compressor, "ScrollView {", "Image compressor previews must rely on the tool page outer scroll owner")
        doesNotContain(grayscale, "ScrollView {", "Image grayscale previews must rely on the tool page outer scroll owner")
        doesNotContain(watermark, "ScrollView {", "Image watermark previews must rely on the tool page outer scroll owner")

        for page in [converter, compressor, grayscale, watermark] {
            doesNotContain(page, "Image(nsImage:", "Single-image workflows must not bypass the preview stage with direct Image(nsImage:) rendering")
        }

        appearsBefore(favicon, "IndexPanel(\"上传图片\"", "IndexPanel(\"Favicon 部署包\")", "Favicon page must keep upload before its deployment package")
        contains(compressor, "if session.source == nil", "Image compressor must use a compact upload state before reserving result workspace height")
        contains(compressor, "private var emptyUploadPanel: some View", "Image compressor empty state must stay a natural-height upload panel")
        // 空态面板收敛进共享 ImageUploadEmptyPanel/ImageUploadPendingState 后，
        // 进度/空态断言改锚共享文件，页面断言改锚共享面板装配。
        contains(uploadSupport, "IndexPanel(\"上传图片\")", "The shared empty upload panel must keep the settled upload panel title")
        contains(uploadSupport, "IndexProgressLabel(message: \"正在读取图片…\", alignment: .center)", "The shared upload pending state must keep source preparation centered like the empty state it replaces")
        // 空态范式统一：占位以 .list 密度按 fillsHeight 垂直居中于输入面板，
        // 主操作是空态自带的 32pt 标准按钮（quiet-until-hover，不用实心
        // accent，避免空面板里出现孤立的强色块）。
        contains(uploadSupport, "buttonStyle(IndexButtonStyle())", "The shared upload empty state must offer its select action through the standard 32-point quiet button")
        contains(uploadSupport, "density: .list", "The shared upload empty state must keep the compact list density that centers cleanly in the filling panel")
        contains(uploadSupport, "func uploadPendingFrame(fillsHeight: Bool)", "The shared upload pending state must own one centering frame for both the empty state and the preparation progress")
        contains(compressor, "ImageUploadEmptyPanel(", "Image compressor empty state must mount the shared natural-height upload panel")
        contains(grayscale, "ImageUploadEmptyPanel(", "Image grayscale empty state must mount the shared natural-height upload panel")
        contains(compressor, "onSelect: selectImage", "Image compressor empty state must wire its centered select action to the shared session pipeline")
        contains(grayscale, "onSelect: selectImage", "Image grayscale empty state must wire its centered select action to the shared session pipeline")
        contains(compressor, "IndexPanel(\"优化工作区\")", "Image compressor must keep one primary result workspace after source selection")
        doesNotContain(compressor, "选择图片后比较原图与优化结果", "Image compressor must not center a sentence inside a page-filling empty canvas")
        doesNotContain(compressor, "IndexPanel(\"优化结果\")", "Image compressor must not repeat output in a second panel")
        contains(grayscale, "if session.source == nil", "Image grayscale must keep a compact upload state before creating its comparison workspace")
        contains(grayscale, "IndexPanel(\"灰阶工作区\")", "Image grayscale must keep one primary comparison workspace after source selection")
        doesNotContain(grayscale, "IndexPanel(\"灰度图\")", "Image grayscale must not repeat the result in a second panel")
        contains(watermark, "if session.source != nil", "Image watermark must not reserve its preview panel before a source exists")
        contains(watermark, "onSelect: selectImage", "Image watermark empty state must wire its centered select action to the shared session pipeline")
        contains(favicon, "if session.sourceImage != nil", "Favicon must not render output rows before a source exists")
        contains(favicon, "onSelect: selectImage", "Favicon empty state must wire its centered select action to the output-set session pipeline")
        doesNotContain(favicon, ".fill(ToolTheme.hoverFill)\n                                        .frame(width: size.previewLength", "Favicon must not render fake icon thumbnails before generation")
        contains(converter, "importPublisher: publishImportedImages", "Image converter import appearance must use the shared panel reveal cadence")
        contains(compressor, ".toolTransition(ToolMotion.Transition.modeContent, reduceMotion: reduceMotion)", "Image compressor upload/workspace replacement must use the shared state transition")
        contains(compressor, "selectionPublisher: uploadInteractions.publishSelection", "Image compressor accepted-source reveal must use an explicit page presentation boundary")
        contains(grayscale, ".toolTransition(ToolMotion.Transition.modeContent, reduceMotion: reduceMotion)", "Image grayscale upload/workspace replacement must use the shared state transition")
        contains(grayscale, "selectionPublisher: uploadInteractions.publishSelection", "Image grayscale generation and clearing must use the shared panel reveal cadence")
        contains(watermark, "selectionPublisher: uploadInteractions.publishSelection", "Image watermark source and preview presence must use the shared panel reveal cadence")
        contains(favicon, "selectionPublisher: uploadInteractions.publishSelection", "Favicon source and output presence must use the shared panel reveal cadence")
        contains(compressor, "isProcessing: session.isProcessing", "Image compressor processing completion must render through the shared comparison card")
        contains(grayscale, "isProcessing: session.isProcessing", "Image grayscale processing completion must render through the shared comparison card")
        let comparisonCard = try readSource("Sources/XTools/Shared/Components/IndexImageComparisonCard.swift")
        contains(comparisonCard, "IndexProgressLabel(message: \"处理中…\")", "The shared comparison card must own the shared processing surface")
        contains(favicon, ".toolAnimation(ToolMotion.Preset.diagnostic, value: session.isProcessing)", "Favicon generation completion must use the shared local state-swap cadence")
        contains(favicon, "IndexProgressLabel(message: \"正在生成部署包…\", layout: .centered)", "Favicon generation must use the sanctioned centered progress layout instead of a hand-built pending row")
        // 空态诊断锚只在无源时生效：源就位后成品面板已持有同一诊断，
        // 双活跃锚会让同一错误出两条 toast/两个 banner。
        contains(favicon, ".indexWorkspaceDiagnostic(session.sourceImage == nil ? session.error : nil)", "Favicon upload empty state must surface import errors without duplicating the output panel's diagnostic while a source exists")

        for page in [favicon, converter, compressor, grayscale, watermark] {
            contains(page, "session.reset()", "Every retained image workflow must expose explicit current-image clearing")
        }

        for page in [favicon, converter, compressor, grayscale, watermark] {
            doesNotContain(page, "NSOpenPanel()", "Image pages must not construct open panels directly")
            doesNotContain(page, "NSSavePanel()", "Image pages must not construct save panels directly")
            doesNotContain(page, "Data(contentsOf:", "Image pages must not read selected files directly")
            doesNotContain(page, "UniformTypeIdentifiers", "Image pages must not map platform content types directly")
        }
        for page in [favicon, compressor, grayscale, watermark] {
            contains(page, "@Environment(\\.fileInputPanelClient) private var fileInputPanelClient", "Every single-image page must receive the shared window-scoped input panel client")
            contains(page, "@State private var isImageDropTargeted = false", "Every single-image page must expose targeted state for its local upload surface")
            contains(page, ".indexDropZone(", "Single-image upload surfaces must use the shared single-file drop modifier")
            contains(page, "session.receiveImageURL(", "Image drops must enter the same URL-based session pipeline as panel selections")
            contains(page, "session.rejectImageInput(SingleFileDropResolver.multipleFilesDiagnostic)", "Single-image pages must reject an entire multi-file batch with the shared diagnostic")
        }
        // 批量转换页换成多文件拖放入口：1..N 张全部进入导入管线，不再整批拒绝。
        contains(converter, "@Environment(\\.fileInputPanelClient) private var fileInputPanelClient", "Image converter must receive the shared window-scoped input panel client")
        contains(converter, "@State private var isImageDropTargeted = false", "Image converter must expose targeted state for its local upload surface")
        contains(converter, ".multiImageInputDropDestination(", "Image converter must attach the shared multi-file drop modifier to its whole-page root container")
        contains(converter, "showsHighlight: false", "The whole-page drop target must stay silent; the visible highlight belongs to the input zone only")
        contains(converter, ".imageDropHighlight(isActive: isImageDropTargeted)", "The upload panel content must carry the drop highlight shared from the whole-page target state")
        contains(converter, "session.receiveImageURLs(", "Image converter drops must enter the same URL-based session pipeline as panel selections")
        contains(converter, "onSelect: addImages", "Image converter empty state must wire its centered select action to the batch import pipeline")
        contains(converter, "session.selectImages(", "Image converter panel selection must request multi-file selection through the batch session")
        doesNotContain(converter, "SingleFileDropResolver.multipleFilesDiagnostic", "Image converter must accept whole multi-file batches instead of rejecting them")
        for page in [favicon, compressor, grayscale] {
            doesNotContain(page, "IndexImagePreviewImage(", "Image pages must use the full preview stage instead of bypassing its non-scrolling semantics")
        }
        contains(watermark, "IndexImagePreviewImage(", "Image watermark may use the shared low-level image surface only for its compact source identity thumbnail")
        doesNotContain(watermark, "IndexImagePreviewStage(\n                                image: source.image", "Image watermark must not reserve a second source preview stage")
        contains(converter, "IndexImagePreviewImage(", "Image converter may use the shared low-level image surface only for its compact batch row thumbnails")

        for page in [compressor, grayscale, watermark] {
            contains(page, "@ObservedObject var session: ImageProcessedOutputSession", "Single-output image content must observe its repository-retained shared session")
            contains(page, "session.selectImage", "Single-output image pages must delegate image selection to the shared session")
            contains(page, "session.save(workflow:", "Single-output image pages must delegate save and output-size protection to the shared session")
            doesNotContain(page, "@State private var selectedImage", "Single-output image pages must not duplicate selected image state")
            doesNotContain(page, "@State private var sourceData", "Single-output image pages must not duplicate source data state")
            doesNotContain(page, "@State private var sourceMetadata", "Single-output image pages must not duplicate source metadata state")
            doesNotContain(page, "@State private var error", "Single-output image pages must not duplicate workflow error state")
            doesNotContain(page, ".saveProcessedImage(", "Single-output image pages must not call platform save workflow directly")
        }
        // 批量转换页改锚批量会话：状态与保存都委托 ImageBatchConversionSession。
        contains(converter, "@ObservedObject var session: ImageBatchConversionSession", "Image converter content must observe its repository-retained batch session")
        contains(converter, "session.saveAll(defaultBasename:", "Image converter must delegate batch save and output-size protection to the batch session")
        doesNotContain(converter, "@State private var selectedImage", "Image converter must not duplicate selected image state")
        doesNotContain(converter, "@State private var sourceData", "Image converter must not duplicate source data state")
        doesNotContain(converter, "@State private var sourceMetadata", "Image converter must not duplicate source metadata state")
        doesNotContain(converter, "@State private var error", "Image converter must not duplicate workflow error state")
        doesNotContain(converter, ".saveProcessedImage(", "Image converter must not call platform save workflow directly")

        contains(favicon, "ToolWorkspaceHost(key: FaviconOutputSetSession.workspaceKey)", "Favicon icon-set workflow must resolve its retained output-set session")
        contains(favicon, "@ObservedObject var session: FaviconOutputSetSession", "Favicon content must observe the retained output-set session")
        contains(favicon, "session.selectImage(", "Favicon page must delegate shared-panel selection and generation to the output-set session")
        contains(favicon, "session.saveArtifact(artifact.id, filePanel: fileInputPanelClient, outputPanel: fileOutputPanelClient)", "Favicon page must delegate named artifact saving to the output-set session over the sheet panels")
        contains(favicon, "session.savePackage(filePanel: fileInputPanelClient, outputPanel: fileOutputPanelClient)", "Favicon page must delegate five-file package saving to the output-set session over the sheet panels")
        contains(faviconSession, "client.prepareSelectionInBackground", "Favicon output-set session must prepare an already selected URL through the platform client seam")
        contains(faviconSession, "client.saveArtifact", "Favicon output-set session must delegate named artifact saving to the platform client seam")
        contains(faviconSession, "client.saveArtifacts", "Favicon output-set session must delegate package saving to the platform client seam")
        contains(faviconSession, "workGate.runDetached", "Favicon icon-set generation must run off the main actor through AsyncWorkGate")
        contains(faviconSession, "generation", "Favicon icon-set generation must protect against stale background results")
        contains(faviconSession, "isProcessing", "Favicon generation must expose in-flight state instead of blocking the UI")
        doesNotContain(favicon, "@State private var selectedImage", "Favicon page must not duplicate selected image state outside the output-set session")
        doesNotContain(favicon, "@State private var sourceData", "Favicon page must not duplicate source data state outside the output-set session")
        doesNotContain(favicon, "@State private var generatedIcons", "Favicon page must not duplicate generated icon state outside the output-set session")
        doesNotContain(favicon, "@State private var error", "Favicon page must not duplicate workflow error state outside the output-set session")
        doesNotContain(favicon, "@State private var selectionTask", "Favicon page must not coordinate selection tasks outside the output-set session")
        doesNotContain(favicon, "@State private var generationTask", "Favicon page must not coordinate generation tasks outside the output-set session")
        doesNotContain(favicon, "ImageProcessedOutputSession()", "Favicon icon sets must not be routed through single-output size protection")
        contains(workflow, "struct ImageWorkflowClient", "Image workflow must have an explicit platform seam")
        contains(workflow, "final class ImageProcessedOutputSession", "Single-output image workflow state must live behind a shared session")
        contains(workflow, "filePanel.selectFile", "Image processed-output session must obtain clicked URLs from the shared panel client")
        contains(workflow, "client.prepareSelectionInBackground", "Image processed-output session must prepare clicked and dropped URLs through one pipeline")
        contains(workflow, "client.saveProcessedImage", "Image processed-output session must delegate saving and output-size protection to the platform client")
        contains(workflow, "func prepareSelectionInBackground(\n        from url: URL,", "Image workflow client must prepare already selected URLs off the main actor")
        contains(workflow, "ImageProcessor.previewImageData", "Image workflow client must prepare bounded source previews instead of decoding full-size preview images on the main actor")
        contains(workflow, "renderGate.runDetached", "Image processed-output rendering must run off the main actor through AsyncWorkGate")
        contains(workflow, "Task.checkCancellation()", "Image processed-output rendering must cooperate with cancellation between expensive stages")
        contains(workflow, "renderGate", "Image processed-output rendering must protect against stale background results via AsyncWorkGate")
        contains(workflow, "isProcessing", "Image processed-output sessions must expose in-flight state for save blocking and progress")
        doesNotContain(workflow, "NSOpenPanel()", "Image workflow client must delegate all panel construction to the sheet panel clients")
        doesNotContain(workflow, "func selectImage(allowedContentTypes: [UTType]) -> URL?", "Image output dialog must not retain input-panel selection")
        contains(workflow, "await dialog.selectDirectory(prompt:", "Favicon batch output directory selection must flow through the shared dialog seam")
        doesNotContain(workflow, "NSSavePanel()", "Image workflow client must not construct save panels — saves go through the sheet output panel")
        contains(workflow, "BoundedFileReader.read(from: url, maxBytes: maxBytes)", "Image workflow must bound selected-file reads even when file metadata is missing or stale")
        contains(workflow, "maxBytes: ImageProcessingBudget.maxInputBytes", "Image workflow bounded reads must use the shared image input budget")
        contains(workflow, "catch BoundedFileReader.ReadError.tooLarge", "Image workflow must preserve the typed image-size failure when a bounded read crosses the budget")
        doesNotContain(workflow, "Data(contentsOf: url)", "Image workflow must not allocate an unbounded selected file before enforcing its input budget")
        contains(workflow, "UTType(format.utTypeIdentifier) ?? .data", "Image workflow client owns image format to UTType mapping")
        contains(processor, "public static func previewImageData", "Image core must expose a bounded preview-data path for source-image UI previews")
        contains(processor, "kCGImageSourceThumbnailMaxPixelSize", "Image preview and resize paths must use ImageIO thumbnail decoding instead of full-size preview decoding")
        contains(filePanel, "private let panel: NSOpenPanel", "Image clicks must reuse the shared AppKit input panel backend")

        contains(converter, "ImageFileFormat.conversionTargetFormats", "Image converter must source target formats from source-aware runtime-supported output formats")
        contains(converter, "items: outputFormats.map", "Image converter picker must only expose runtime-supported output formats")
        contains(converter, ".accessibilityLabel(\"目标格式\")", "Image converter target picker must expose a stable accessibility label")
        contains(converter, ".accessibilityValue(targetFormat.displayName)", "Image converter target picker must expose the selected format")
        contains(converter, "选择图片后显示", "Image converter must wait for source format before presenting target choices")
        contains(converter, "$0.metadata.transparency != .opaque", "Image converter must require fill only for items with actual or unknown transparency")
        contains(converter, "guard !targetFormat.preservesAlpha else { return false }", "Image converter must require fill only when the target drops alpha")
        contains(converter, "ImageTransparencyFillMode.white", "Image converter must offer an explicit white fill choice")
        contains(converter, "(.black, \"黑色\")", "Image converter must offer an explicit black fill choice")
        contains(converter, "(.custom, \"自定义\")", "Image converter must offer a custom fill choice without silently defaulting it")
        contains(converter, "transparencyFill: transparencyFill", "Image converter must pass the visible fill recipe into Core encoding")
        contains(converter, "透明区域已填充为", "Image converter output facts must state the applied transparency fill")
        contains(converter, ".accessibilityLabel(\"透明区域填充颜色\")", "Image converter fill controls must expose a stable accessibility label")
        contains(converter, ".accessibilityValue(transparencyFillAccessibilityValue)", "Image converter fill controls must expose the selected or missing value")
        contains(converter, ".help(\"JPEG 和 HEIC 不支持透明区域；请选择转换前用于填充透明像素的颜色。\")", "Image converter fill controls must explain the lossy boundary where they apply")
        doesNotContain(converter, "ImageFileFormat.allCases.map", "Image converter must not expose unsupported output formats such as WebP")
        doesNotContain(converter, "hasAlpha: metadata.hasAlpha", "Image converter target visibility must not confuse an Alpha channel with transparent pixels")
        contains(converter, "maxDisplayHeight: 260", "Conditional converter controls must retain a bounded preview height so 960-wide layouts keep the output facts and save action reachable")
        contains(workflow, "ImageFileFormat.supportedInputFormats", "Image input panels must follow the runtime-readable product allowlist")
        contains(workflow, "filter { $0 != .tiff }", "Favicon input must keep its intentional TIFF exclusion while inheriting readable modern formats")
        doesNotContain(watermark, "IndexOptionLabel(\"保存为\")", "Image watermark must not expose a format-conversion control in the primary toolbar")
        doesNotContain(watermark, "ImageFileFormat.supportedOutputFormats.map", "Image watermark must not duplicate the format converter target list")
        doesNotContain(watermark, "ImageFileFormat.allCases.map", "Image watermark must not expose unsupported output formats such as WebP")
        doesNotContain(watermark, "IndexOptionLabel(\"格式\")", "Image watermark must not label its save-format choice as a generic format converter")
        doesNotContain(watermark, "IndexOptionLabel(\"质量\")", "Image watermark must not expose image encoding controls in the primary watermark toolbar")
        doesNotContain(watermark, ".accessibilityLabel(\"水印文字颜色\")", "Image watermark color picker must preserve the distinct accessibility name of each color option")
        contains(watermark, "IndexOptionDivider()", "Image watermark must keep opacity and relative size in one compact control group")
        contains(watermark, "outputFormat: nil", "Image watermark must default to source-format saving instead of acting as a converter")
        contains(watermark, "recipe: currentRecipe", "Image watermark final rendering must pass one immutable recipe into Core")
        doesNotContain(watermark, "quality: ImageProcessor.highFidelityEncodingQuality", "Image watermark page must not own or vary lossy encoding quality")
        contains(watermark, "processingOutputSummary", "Image watermark must keep the larger-output warning facts separate from the save action label")
        contains(watermark, #"Label("保存", systemImage: IndexActionSymbol.save)"#, "Image watermark must keep one concise save label using the shared file-save symbol")
        doesNotContain(watermark, "仍然保存更大的文件", "Image watermark must not expand the save button when the result is larger")
        doesNotContain(watermark, "saveButtonTitle", "Image watermark must not keep a second conditional save-title path")
        contains(watermark, "IndexOptionLabel(\"大小\")", "Image watermark must present a visual size control instead of source-pixel font terminology")
        contains(watermark, "IndexSlider(value: $sizeRatio, range: ImageWatermarkSizing.ratioRange, step: 0.01)", "Watermark size must use the approved text-width ratio slider")
        contains(watermark, "Text(\"\\(sizePercent)%\")", "Watermark size must expose a compact visible percentage readout")
        contains(watermark, "ImageWatermarkSizing.fontSize(", "Watermark preview and final recipes must derive source-pixel font size from the shared relative sizing helper")
        doesNotContain(watermark, "IndexNumberInput", "Image watermark must not expose raw source-pixel font input")
        doesNotContain(watermark, "MediaToolPreferenceKeys.imageWatermarkFontSize", "The live watermark model must not restore the obsolete absolute-pixel preference")
        contains(preferences, "static let imageWatermarkSizeRatio = ToolPreferenceKey<Double>.double(\n        \"tools.imageWatermark.sizeRatio.v2\",\n        default: ImageWatermarkSizing.defaultRatio,\n        range: ImageWatermarkSizing.ratioRange", "Watermark size persistence must use the approved v2 relative ratio key")
        contains(grayscale, "ImageProcessor.highFidelityEncodingQuality", "Image grayscale must retain its existing independent maximum-quality encoding policy")
        contains(grayscale, "processingOutputSummary", "Image grayscale must use non-compression output summary without actual-quality labeling")
        contains(grayscale, "ImageOutputPresentation.saveTitle(", "Image grayscale must derive its conditional save title from the shared larger-file save vocabulary")

        contains(compressor, "IndexOptionLabel(\"优化偏好\")", "Image compressor must use user-level optimization preference instead of exposing raw quality first")
        contains(compressor, "IndexOptionSwitch(title: \"限制尺寸\"", "Image compressor must use user-facing dimension-limit wording")
        doesNotContain(compressor, "IndexOptionSwitch(title: \"最大边长\"", "Image compressor must not expose the engineering term maximum side")
        doesNotContain(compressor, "Slider(value: $quality", "Image compressor must not expose a primary raw quality slider")
        contains(grayscale, "session.receiveImageURL(", "Image grayscale rendering must run through the shared URL-based background image session")
        contains(outputPresentation, "\"未生成更小文件\"", "Blocked compression must present one ordinary no-smaller-result state")
        doesNotContain(outputPresentation, "blockedCompressionGuidance(", "Blocked compression must not explain preference or dimension strategy")
        doesNotContain(outputPresentation, "保留原始尺寸时，输出仍不小于原图", "Blocked compression must not narrate internal strategy decisions")
        contains(outputPresentation, "processingOutputSummary", "Non-compression image tools must share a summary path without compression-quality labeling")
        contains(compressor, "ImageCompressionPreference.allCases.map", "Image compressor must expose every optimization preference including smaller-file")
        contains(compressor, "IndexActionBar {", "Image compressor must keep preference and dimension-limit controls on the shared one-line action bar")
        contains(compressor, "ImageOutputPresentation.sizeChangeText(compressedAssessment)", "Image compressor must retain the actual successful size delta in the result card")
        contains(compressor, "ImageOutputPresentation.compressionStatus(compressedAssessment)", "Image compressor result card must retain actual output format, dimensions, and quality")
        contains(compressor, "return ImageOutputPresentation.blockedCompressionMessage", "Blocked compression must use the shared result text as the preview placeholder")
        doesNotContain(compressor, "blockedGuidance", "Image compressor must not keep a second blocked explanation path")
        occurrenceCount(compressor, "ImageOutputPresentation.blockedCompressionMessage", 1, "Blocked compression state must appear exactly once on the result surface")

    }
}
