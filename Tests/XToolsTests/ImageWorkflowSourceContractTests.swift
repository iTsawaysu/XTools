import Foundation
import AppKit
@testable import XTools
import Testing

/// Image workflow source contracts.
///
/// Retained anchors: session delegation seams (no page-owned image state),
/// sheet panel clients (no direct NSOpenPanel/NSSavePanel), bounded reads,
/// AsyncWorkGate generation protection, preview stage semantics, and save
/// outcome toast routing. Multi-line needles, copy nouns, and per-label
/// accessibility text anchors were retired.
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

        // 成功提示只在 session 返回 .saved 时显示（取消/阻止/部分成功映射由
        // 共享 ImageSaveOutcomeToasts 负责）；页面只锚路由调用。
        contains(uploadSupport, "ToolFeedbackCopy.saved(fileName: fileName), tone: .success", "The shared single-output toast mapper must name the saved file when the caller knows it")
        contains(uploadSupport, "toastCenter?.show(ToolFeedbackCopy.savedFile, tone: .success)", "The shared save mappers must fall back to the generic single-file success copy")
        occurrenceCount(uploadSupport, "tone: .error", 2, "Every shared save-outcome mapper must surface real save failures as error toasts")
        contains(uploadSupport, "case .cancelled, .blocked, .partiallySaved:", "The shared single-output toast mapper must stay silent for cancel/block outcomes")
        contains(uploadSupport, "toastCenter?.show(ToolFeedbackCopy.saved(count: savedCount, noun: successNoun), tone: .success)", "The shared counted-save mapper must use the counted save copy for multi-file successes")
        contains(uploadSupport, "case let .partiallySaved(partiallySavedCount, totalCount):", "The shared counted-save mapper must handle partial saves structurally")
        for (page, name) in [(compressor, "compressor"), (grayscale, "grayscale"), (watermark, "watermark")] {
            contains(page, "ImageSaveOutcomeToasts.presentSingleOutput(outcome, toastCenter: toastCenter)", "Image \(name) save must route its outcome through the shared single-output toast mapper")
            contains(page, "filePanel: fileInputPanelClient, outputPanel: fileOutputPanelClient", "Image \(name) save must route through the window-scoped sheet panel clients")
        }
        contains(converter, "ImageSaveOutcomeToasts.presentCountedOutput(", "Image converter must route its batch save outcome through the shared counted-save mapper")
        contains(converter, "savedCount: session.completedCount", "Image converter must report its actual completed count to the shared mapper")
        contains(favicon, "ImageSaveOutcomeToasts.presentCountedOutput(", "Favicon package save must route its outcome through the shared counted-save mapper")
        contains(favicon, "savedCount: package.saveableArtifacts.count", "Favicon package save must derive its count from the actual saveable artifacts")
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
        contains(uploadSupport, "withToolAnimation(ToolMotion.Preset.panelReveal, reduceMotion: reduceMotion)", "The shared upload interactions must execute the session source assignment inside the shared motion transaction")
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
        contains(converter, "private func publishImportedImages(_ imported: [BatchConversionItem], _ publish: () -> Void)", "Image converter must keep import publication motion page-owned")
        contains(faviconSession, "selectionPublisher: @escaping ImageSelectionPublisher", "Favicon selection must expose the same page-owned source publication seam as processed image sessions")
    }

    @Test func imageConverterUsesActualOutputInsteadOfFormatPredictions() throws {
        let converter = try readSource("Sources/XTools/ToolPages/Image/ImageConverterPage.swift")
        let session = try readSource("Sources/XTools/ToolPages/Image/ImageBatchConversionSession.swift")
        let outputPresentation = try readSource("Sources/XTools/ToolPages/Image/ImageOutputPresentation.swift")

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
        contains(watermark, "recipeDidChange(previewCadence: .immediate)", "Watermark position and color controls must request immediate bounded preview feedback")
        occurrenceCount(watermark, "recipeDidChange(previewCadence: .debounced)", 3, "Watermark text, opacity, and font-size edits must retain bounded preview debounce")
        contains(watermark, "case .immediate:", "Watermark recipe updates must have a direct bounded-render path for discrete controls")
        contains(watermark, "case .debounced:", "Watermark recipe updates must retain the shared short debounce path for continuous controls")
        contains(watermark, "finalDebouncer.schedule(Self.finalDebounceDelay)", "Every watermark recipe path must retain delayed source-resolution final rendering")
        doesNotContain(watermark, "withAnimation(.spring", "Watermark anchors must not animate through unrequested intermediate positions")
    }

    @Test func imageToolsUseNonScrollingPreviewStagesWithSessionBackedState() throws {
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
        let preferences = try readSource("Sources/XTools/Shared/Preferences/MediaToolPreferenceKeys.swift")

        // Shared preview stage: bounded, proportional, accessible, non-scrolling.
        contains(stage, "struct IndexImagePreviewStage", "Image tools must share an explicit image preview stage semantic")
        contains(stage, "enum IndexImagePreviewStageMetrics", "Image preview stage metrics must stay in one non-generic namespace")
        contains(stage, ".aspectRatio(contentMode: .fit)", "Image preview stages must show complete proportional images")
        contains(stage, ".frame(maxWidth: maxDisplayWidth, maxHeight: maxDisplayHeight)", "Image preview images must be bounded in both dimensions")
        contains(stage, "let accessibilityLabel: String", "Image preview stages must require caller-owned accessibility names")
        contains(stage, ".accessibilityValue(accessibilityValue)", "Image preview images must publish their relevant facts")
        doesNotContain(stage, "ScrollView {", "Image preview stages must not create an internal scroll container")

        // 四个图片工具合并为单入口「图片处理」后，workspaceSemantic 页面壳断言统一改锚 Hub。
        contains(imageHub, "workspaceSemantic: .imagePreviewStage", "The image hub must declare the image preview stage workspace semantic at the page shell")
        contains(imageHub, "case .watermark: IndexImageWatermarkSegment()", "The image hub must mount the watermark workflow as a first-class segment")

        // Batch conversion session: lightweight import + generation-cancelled
        // serial conversion + delegated batch saves.
        contains(workflow, "case partiallySaved(savedCount: Int, totalCount: Int)", "Image save outcomes must preserve partial Favicon progress structurally")
        contains(faviconSession, "case let .partialSaveFailed(savedCount, totalCount)", "Favicon session must map only structured partial-save failures to a partial outcome")
        contains(workflow, "final class ImageBatchConversionSession", "Batch conversion state must live behind its own retained session")
        contains(workflow, "func prepareImportOverview(", "Batch import must reuse the shared preparation pipeline through a lightweight overview")
        contains(workflow, "client.prepareImportOverview", "Batch conversion session must import through the platform client seam")
        contains(workflow, "client.saveConvertedImages", "Batch conversion session must delegate directory saves to the platform client seam")
        contains(workflow, "client.prepareSelectionInBackground", "Batch conversion re-reads each item through the shared URL preparation pipeline")
        contains(workflow, "renderGate.invalidate()", "Batch conversion re-runs must supersede the previous generation through AsyncWorkGate")
        contains(workflow, "renderGate.isCurrent(generation)", "Batch conversion must protect against stale background results")
        contains(workflow, "static let defaultMaximumItemCount = 100", "Batch conversion must bound the list and save loop scale while outputs stay spooled on disk")
        contains(workflow, "func evictHeavyPayloads()", "Batch conversion session must keep workspace eviction semantics")

        // Per-page preview surfaces and result cards.
        contains(favicon, "IndexImagePreviewStage(", "Favicon upload preview must use the non-scrolling image preview stage")
        contains(converter, "IndexImagePreviewStage(", "Image converter single-image preview must use the non-scrolling image preview stage")
        contains(converter, ".indexWorkspaceDiagnostic(session.error)", "Image converter errors must remain visible through the non-displacing diagnostic anchor")
        doesNotContain(converter, "IndexPanel(\"转换预览\")", "Image converter must not keep the separate lower conversion preview panel")
        contains(compressor, "IndexImageComparisonCard(", "Image compressor comparison panes must use the shared comparison card component")
        contains(compressor, "IndexPairLayout(collapseWidth: 0)", "Image compressor cards must stay side-by-side throughout the validated desktop window range")
        doesNotContain(compressor, "IndexPairLayout(collapseWidth: 760)", "Image compressor must not vertically reflow inside the validated 960-point window floor")
        doesNotContain(compressor, "compressionComparisonFooter", "Image compressor must not leave a detached fact block below the comparison")
        doesNotContain(compressor, "IndexImageComparisonStage", "Image compressor must not use the rejected label-plus-bare-image abstraction")
        contains(grayscale, "IndexImageComparisonCard(", "Image grayscale source and result must each own one complete comparison card via the shared component")
        contains(grayscale, "IndexPairLayout(collapseWidth: 0)", "Image grayscale comparison must stay side-by-side throughout the supported desktop window range")
        let comparisonCard = try readSource("Sources/XTools/Shared/Components/IndexImageComparisonCard.swift")
        contains(comparisonCard, "IndexProgressLabel(message: \"处理中…\")", "The shared comparison card must own the shared processing surface")
        contains(favicon, ".toolAnimation(ToolMotion.Preset.diagnostic, value: session.isProcessing)", "Favicon generation completion must use the shared local state-swap cadence")
        contains(favicon, ".indexWorkspaceDiagnostic(session.sourceImage == nil ? session.error : nil)", "Favicon upload empty state must surface import errors without duplicating the output panel's diagnostic while a source exists")
        contains(favicon, "Image(nsImage: image)", "Favicon package rows may render fixed-size output thumbnails directly")
        contains(favicon, "private func previewLength(_ size: Int) -> CGFloat", "Large favicon outputs must use bounded preview thumbnails")
        contains(faviconSession, "FaviconOutputSpec(size: 180)", "Favicon output set must include the Apple touch icon size")
        contains(faviconSession, "FaviconOutputSpec(size: 192)", "Favicon output set must include the package's common PWA icon size")
        contains(faviconSession, "FaviconOutputSpec(size: 512)", "Favicon output set must include the package's large PWA icon size")
        doesNotContain(faviconSession, "FaviconOutputSpec(size: 64)", "The deployment package must not retain the legacy standalone 64px PNG")
        doesNotContain(faviconSession, "FaviconOutputSpec(size: 128)", "The deployment package must not retain the legacy standalone 128px PNG")
        appearsBefore(favicon, "IndexPanel(\"上传图片\"", "IndexPanel(\"Favicon 部署包\")", "Favicon page must keep upload before its deployment package")

        // No page owns an internal scroller or bypasses the preview stage.
        for (name, page) in [("favicon", favicon), ("converter", converter), ("compressor", compressor), ("grayscale", grayscale), ("watermark", watermark)] {
            doesNotContain(page, "ScrollView {", "\(name) previews must rely on the tool page outer scroll owner")
        }
        for page in [converter, compressor, grayscale, watermark] {
            doesNotContain(page, "Image(nsImage:", "Single-image workflows must not bypass the preview stage with direct Image(nsImage:) rendering")
        }
        for page in [favicon, compressor, grayscale] {
            doesNotContain(page, "IndexImagePreviewImage(", "Image pages must use the full preview stage instead of bypassing its non-scrolling semantics")
        }
        contains(watermark, "IndexImagePreviewImage(", "Image watermark may use the shared low-level image surface only for its compact source identity thumbnail")
        contains(watermark, "maxDisplayWidth: 64", "Image watermark source thumbnail must stay compact enough to preserve the live result viewport")
        contains(converter, "IndexImagePreviewImage(", "Image converter may use the shared low-level image surface only for its compact batch row thumbnails")

        // Every retained workflow exposes explicit reset; no page touches
        // panels, raw file data, or platform type mapping directly.
        for page in [favicon, converter, compressor, grayscale, watermark] {
            contains(page, "session.reset()", "Every retained image workflow must expose explicit current-image clearing")
            doesNotContain(page, "NSOpenPanel()", "Image pages must not construct open panels directly")
            doesNotContain(page, "NSSavePanel()", "Image pages must not construct save panels directly")
            doesNotContain(page, "Data(contentsOf:", "Image pages must not read selected files directly")
            doesNotContain(page, "UniformTypeIdentifiers", "Image pages must not map platform content types directly")
        }
        for (name, page) in [("favicon", favicon), ("compressor", compressor), ("grayscale", grayscale), ("watermark", watermark)] {
            contains(page, "@Environment(\\.fileInputPanelClient) private var fileInputPanelClient", "The \(name) page must receive the shared window-scoped input panel client")
            contains(page, ".indexDropZone(", "\(name) upload surfaces must use the shared single-file drop modifier")
            contains(page, "session.receiveImageURL(", "\(name) drops must enter the same URL-based session pipeline as panel selections")
            contains(page, "session.rejectImageInput(SingleFileDropResolver.multipleFilesDiagnostic)", "The \(name) page must reject an entire multi-file batch with the shared diagnostic")
        }
        // 批量转换页换成多文件拖放入口：1..N 张全部进入导入管线，不再整批拒绝。
        contains(converter, "@Environment(\\.fileInputPanelClient) private var fileInputPanelClient", "Image converter must receive the shared window-scoped input panel client")
        contains(converter, ".multiImageInputDropDestination(", "Image converter must attach the shared multi-file drop modifier to its whole-page root container")
        contains(converter, ".imageDropHighlight(isActive: isImageDropTargeted)", "The upload panel content must carry the drop highlight shared from the whole-page target state")
        contains(converter, "session.receiveImageURLs(", "Image converter drops must enter the same URL-based session pipeline as panel selections")
        contains(converter, "session.selectImages(", "Image converter panel selection must request multi-file selection through the batch session")
        doesNotContain(converter, "SingleFileDropResolver.multipleFilesDiagnostic", "Image converter must accept whole multi-file batches instead of rejecting them")

        // Single-output pages delegate state and saving to the shared session.
        for page in [compressor, grayscale, watermark] {
            contains(page, "@ObservedObject var session: ImageProcessedOutputSession", "Single-output image content must observe its repository-retained shared session")
            contains(page, "session.selectImage", "Single-output image pages must delegate image selection to the shared session")
            contains(page, "session.save(workflow:", "Single-output image pages must delegate save and output-size protection to the shared session")
            doesNotContain(page, "@State private var selectedImage", "Single-output image pages must not duplicate selected image state")
            doesNotContain(page, "@State private var sourceData", "Single-output image pages must not duplicate source data state")
            doesNotContain(page, "@State private var error", "Single-output image pages must not duplicate workflow error state")
            doesNotContain(page, ".saveProcessedImage(", "Single-output image pages must not call platform save workflow directly")
        }
        contains(converter, "@ObservedObject var session: ImageBatchConversionSession", "Image converter content must observe its repository-retained batch session")
        contains(converter, "session.saveAll(defaultBasename:", "Image converter must delegate batch save and output-size protection to the batch session")
        doesNotContain(converter, "@State private var selectedImage", "Image converter must not duplicate selected image state")
        doesNotContain(converter, "@State private var error", "Image converter must not duplicate workflow error state")

        contains(favicon, "ToolWorkspaceHost(key: FaviconOutputSetSession.workspaceKey)", "Favicon icon-set workflow must resolve its retained output-set session")
        contains(favicon, "@ObservedObject var session: FaviconOutputSetSession", "Favicon content must observe the retained output-set session")
        contains(favicon, "session.savePackage(filePanel: fileInputPanelClient, outputPanel: fileOutputPanelClient)", "Favicon page must delegate five-file package saving to the output-set session over the sheet panels")
        contains(faviconSession, "client.saveArtifact", "Favicon output-set session must delegate named artifact saving to the platform client seam")
        contains(faviconSession, "client.saveArtifacts", "Favicon output-set session must delegate package saving to the platform client seam")
        contains(faviconSession, "workGate.runDetached", "Favicon icon-set generation must run off the main actor through AsyncWorkGate")
        doesNotContain(favicon, "@State private var selectedImage", "Favicon page must not duplicate selected image state outside the output-set session")
        doesNotContain(favicon, "@State private var generatedIcons", "Favicon page must not duplicate generated icon state outside the output-set session")

        // The platform client seam owns panels, bounded reads, and rendering.
        contains(workflow, "struct ImageWorkflowClient", "Image workflow must have an explicit platform seam")
        contains(workflow, "final class ImageProcessedOutputSession", "Single-output image workflow state must live behind a shared session")
        contains(workflow, "filePanel.selectFile", "Image processed-output session must obtain clicked URLs from the shared panel client")
        contains(workflow, "client.saveProcessedImage", "Image processed-output session must delegate saving and output-size protection to the platform client")
        contains(workflow, "ImageProcessor.previewImageData", "Image workflow client must prepare bounded source previews instead of decoding full-size preview images on the main actor")
        contains(workflow, "renderGate.runDetached", "Image processed-output rendering must run off the main actor through AsyncWorkGate")
        contains(workflow, "Task.checkCancellation()", "Image processed-output rendering must cooperate with cancellation between expensive stages")
        doesNotContain(workflow, "NSOpenPanel()", "Image workflow client must delegate all panel construction to the sheet panel clients")
        doesNotContain(workflow, "NSSavePanel()", "Image workflow client must not construct save panels — saves go through the sheet output panel")
        contains(workflow, "await dialog.selectDirectory(prompt:", "Favicon batch output directory selection must flow through the shared dialog seam")
        contains(workflow, "BoundedFileReader.read(from: url, maxBytes: maxBytes)", "Image workflow must bound selected-file reads even when file metadata is missing or stale")
        contains(workflow, "maxBytes: ImageProcessingBudget.maxInputBytes", "Image workflow bounded reads must use the shared image input budget")
        contains(workflow, "catch BoundedFileReader.ReadError.tooLarge", "Image workflow must preserve the typed image-size failure when a bounded read crosses the budget")
        doesNotContain(workflow, "Data(contentsOf: url)", "Image workflow must not allocate an unbounded selected file before enforcing its input budget")
        contains(workflow, "ImageFileFormat.supportedInputFormats", "Image input panels must follow the runtime-readable product allowlist")
        contains(workflow, "filter { $0 != .tiff }", "Favicon input must keep its intentional TIFF exclusion while inheriting readable modern formats")
        contains(processor, "public static func previewImageData", "Image core must expose a bounded preview-data path for source-image UI previews")
        contains(processor, "kCGImageSourceThumbnailMaxPixelSize", "Image preview and resize paths must use ImageIO thumbnail decoding instead of full-size preview decoding")
        contains(filePanel, "private let panel: NSOpenPanel", "Image clicks must reuse the shared AppKit input panel backend")

        // Converter formats come from runtime support; watermark stays a
        // non-converter; grayscale keeps max-quality encoding.
        contains(converter, "ImageFileFormat.conversionTargetFormats", "Image converter must source target formats from source-aware runtime-supported output formats")
        contains(converter, "items: outputFormats.map", "Image converter picker must only expose runtime-supported output formats")
        doesNotContain(converter, "ImageFileFormat.allCases.map", "Image converter must not expose unsupported output formats such as WebP")
        contains(converter, "$0.metadata.transparency != .opaque", "Image converter must require fill only for items with actual or unknown transparency")
        contains(converter, "guard !targetFormat.preservesAlpha else { return false }", "Image converter must require fill only when the target drops alpha")
        contains(converter, "transparencyFill: transparencyFill", "Image converter must pass the visible fill recipe into Core encoding")
        doesNotContain(watermark, "IndexOptionLabel(\"保存为\")", "Image watermark must not expose a format-conversion control in the primary toolbar")
        doesNotContain(watermark, "ImageFileFormat.allCases.map", "Image watermark must not expose unsupported output formats such as WebP")
        doesNotContain(watermark, "IndexOptionLabel(\"质量\")", "Image watermark must not expose image encoding controls in the primary watermark toolbar")
        contains(watermark, "outputFormat: nil", "Image watermark must default to source-format saving instead of acting as a converter")
        contains(watermark, "recipe: currentRecipe", "Image watermark final rendering must pass one immutable recipe into Core")
        doesNotContain(watermark, "quality: ImageProcessor.highFidelityEncodingQuality", "Image watermark page must not own or vary lossy encoding quality")
        contains(watermark, "IndexOptionLabel(\"大小\")", "Image watermark must present a visual size control instead of source-pixel font terminology")
        contains(watermark, "ImageWatermarkSizing.fontSize(", "Watermark preview and final recipes must derive source-pixel font size from the shared relative sizing helper")
        doesNotContain(watermark, "IndexNumberInput", "Image watermark must not expose raw source-pixel font input")
        doesNotContain(watermark, "MediaToolPreferenceKeys.imageWatermarkFontSize", "The live watermark model must not restore the obsolete absolute-pixel preference")
        contains(preferences, "imageWatermarkSizeRatio", "Watermark size persistence must use the approved v2 relative ratio key")
        contains(grayscale, "ImageProcessor.highFidelityEncodingQuality", "Image grayscale must retain its existing independent maximum-quality encoding policy")
        contains(grayscale, "ImageOutputPresentation.saveTitle(", "Image grayscale must derive its conditional save title from the shared larger-file save vocabulary")

        contains(compressor, "IndexOptionLabel(\"优化偏好\")", "Image compressor must use user-level optimization preference instead of exposing raw quality first")
        contains(compressor, "IndexOptionSwitch(title: \"限制尺寸\"", "Image compressor must use user-facing dimension-limit wording")
        doesNotContain(compressor, "IndexOptionSwitch(title: \"最大边长\"", "Image compressor must not expose the engineering term maximum side")
        doesNotContain(compressor, "Slider(value: $quality", "Image compressor must not expose a primary raw quality slider")
        contains(compressor, "ImageCompressionPreference.allCases.map", "Image compressor must expose every optimization preference including smaller-file")
        contains(compressor, "IndexActionBar {", "Image compressor must keep preference and dimension-limit controls on the shared one-line action bar")
        contains(compressor, "ImageOutputPresentation.sizeChangeText(compressedAssessment)", "Image compressor must retain the actual successful size delta in the result card")
        contains(compressor, "ImageOutputPresentation.compressionStatus(compressedAssessment)", "Image compressor result card must retain actual output format, dimensions, and quality")
        contains(outputPresentation, "\"未生成更小文件\"", "Blocked compression must present one ordinary no-smaller-result state")
        doesNotContain(outputPresentation, "blockedCompressionGuidance(", "Blocked compression must not explain preference or dimension strategy")
        contains(outputPresentation, "processingOutputSummary", "Non-compression image tools must share a summary path without compression-quality labeling")
        doesNotContain(compressor, "blockedGuidance", "Image compressor must not keep a second blocked explanation path")
        occurrenceCount(compressor, "ImageOutputPresentation.blockedCompressionMessage", 1, "Blocked compression state must appear exactly once on the result surface")

        // 空态/上传面板收敛进共享 ImageUploadEmptyPanel 后，页面断言改锚装配。
        contains(uploadSupport, "struct ImageUploadEmptyPanel: View", "The shared upload empty panel must exist for natural-height upload states")
        contains(uploadSupport, "buttonStyle(IndexButtonStyle())", "The shared upload empty state must offer its select action through the standard quiet button")
        contains(uploadSupport, "func uploadPendingFrame(fillsHeight: Bool)", "The shared upload pending state must own one centering frame for both the empty state and the preparation progress")
        contains(compressor, "ImageUploadEmptyPanel(", "Image compressor empty state must mount the shared natural-height upload panel")
        contains(grayscale, "ImageUploadEmptyPanel(", "Image grayscale empty state must mount the shared natural-height upload panel")
        contains(compressor, "IndexPanel(\"优化工作区\")", "Image compressor must keep one primary result workspace after source selection")
        doesNotContain(compressor, "IndexPanel(\"优化结果\")", "Image compressor must not repeat output in a second panel")
        contains(grayscale, "IndexPanel(\"灰阶工作区\")", "Image grayscale must keep one primary comparison workspace after source selection")
        doesNotContain(grayscale, "IndexPanel(\"灰度图\")", "Image grayscale must not repeat the result in a second panel")
        contains(watermark, "if session.source != nil", "Image watermark must not reserve its preview panel before a source exists")
        contains(favicon, "if session.sourceImage != nil", "Favicon must not render output rows before a source exists")
        contains(watermark, "onSubmit: applyFinalImmediately", "Image watermark text submit must immediately generate the latest full-resolution result")
        doesNotContain(watermark, "pendingWatermarkTextPreview", "Image watermark must not keep a focus-gated stale-text flag")
        contains(watermark, "workGate.runDetached", "Image watermark bounded preview rendering must run off the main actor through AsyncWorkGate")
        contains(grayscale, "session.receiveImageURL(", "Image grayscale rendering must run through the shared URL-based background image session")
    }
}
