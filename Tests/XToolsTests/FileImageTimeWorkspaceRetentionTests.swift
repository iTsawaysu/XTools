import AppKit
import Foundation
import Testing
import UniformTypeIdentifiers
@testable import XTools
@testable import XToolsCore

struct Base64FileWorkspaceRetentionTests {
    @MainActor
    @Test func workflowStateSurvivesNavigationAndOnlyOutputModeRelaunches() {
        let defaults = Self.defaults()
        let repository = ToolWorkspaceRepository(defaults: defaults)
        let session = repository.model(for: Base64FileWorkflowSession.workspaceKey)

        session.changeDirection(to: .decode)
        session.updateReverseInput("session-only-base64")
        session.outputFileName = "session-only-name"
        session.changeOutputMode(to: .base64)

        let restored = repository.model(for: Base64FileWorkflowSession.workspaceKey)
        #expect(restored === session)
        #expect(restored.direction == .decode)
        #expect(restored.reverseInput == "session-only-base64")
        #expect(restored.outputFileName == "session-only-name")
        #expect(restored.outputMode == .base64)

        let relaunched = ToolWorkspaceRepository(defaults: defaults)
            .model(for: Base64FileWorkflowSession.workspaceKey)
        #expect(relaunched !== session)
        #expect(relaunched.direction == .encode)
        #expect(relaunched.outputMode == .base64)
        #expect(relaunched.reverseInput.isEmpty)
        #expect(relaunched.outputFileName == "download")
        #expect(relaunched.selectedFile == nil)
        #expect(relaunched.outputPreview == nil)
        #expect(relaunched.decodedPayload == nil)
        #expect(relaunched.previewImage == nil)
    }

    @MainActor
    @Test func invalidStoredOutputModeFallsBackToDataURL() {
        let defaults = Self.defaults()
        defaults.set("future-mode", forKey: MediaToolPreferenceKeys.base64FileOutputMode.rawKey)

        let session = ToolWorkspaceRepository(defaults: defaults)
            .model(for: Base64FileWorkflowSession.workspaceKey)
        #expect(session.outputMode == .dataURL)
    }

    @Test func pageUsesRepositorySessionAndKeepsDropTargetLocal() throws {
        let source = try readSource("Sources/XTools/ToolPages/Converter/Base64FilePage.swift")
        contains(source, "ToolWorkspaceHost(key: Base64FileWorkflowSession.workspaceKey)", "Base64 file page must resolve its workflow from the root repository")
        contains(source, "@ObservedObject var session: Base64FileWorkflowSession", "Base64 file content must observe the retained workflow session")
        contains(source, "@State private var isFileDropTargeted = false", "Base64 file drop targeting must remain view-scoped")
        doesNotContain(source, "@StateObject private var session = Base64FileWorkflowSession()", "Base64 file work must not be destroyed with page identity")
    }

    private static func defaults() -> UserDefaults {
        let suiteName = "Base64FileWorkspaceRetentionTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}

struct ImageWorkspaceRetentionTests {
    @MainActor
    @Test func singleOutputImageSessionsAndApprovedRecipesSurviveNavigation() {
        let defaults = Self.defaults()
        let repository = ToolWorkspaceRepository(defaults: defaults)

        let converter = repository.model(for: ImageConverterToolWorkspaceModel.key)
        converter.targetFormat = .jpeg
        converter.quality = 0.64
        converter.session.rejectImageInput("converter-session-error")

        let compressor = repository.model(for: ImageCompressorToolWorkspaceModel.key)
        compressor.compressionPreference = .smallerFile
        compressor.limitsDimensions = true
        compressor.maxPixelLength = 2560
        compressor.session.rejectImageInput("compressor-session-error")

        let watermark = repository.model(for: ImageWatermarkToolWorkspaceModel.key)
        watermark.watermarkText = "session-only-watermark"
        watermark.opacity = 0.7
        watermark.sizeRatio = 0.18
        watermark.position = .topLeft
        watermark.session.rejectImageInput("watermark-session-error")

        let grayscale = repository.model(for: ImageProcessedOutputSession.grayscaleWorkspaceKey)
        grayscale.rejectImageInput("grayscale-session-error")

        #expect(repository.model(for: ImageConverterToolWorkspaceModel.key) === converter)
        #expect(converter.session.error == "converter-session-error")
        #expect(repository.model(for: ImageCompressorToolWorkspaceModel.key) === compressor)
        #expect(compressor.session.error == "compressor-session-error")
        #expect(repository.model(for: ImageWatermarkToolWorkspaceModel.key) === watermark)
        #expect(watermark.watermarkText == "session-only-watermark")
        #expect(watermark.session.error == "watermark-session-error")
        #expect(repository.model(for: ImageProcessedOutputSession.grayscaleWorkspaceKey) === grayscale)
        #expect(grayscale.error == "grayscale-session-error")
    }

    @MainActor
    @Test func imageSessionResetPreservesApprovedRecipesAndWatermarkDraft() {
        let defaults = Self.defaults()
        let repository = ToolWorkspaceRepository(defaults: defaults)

        let converter = repository.model(for: ImageConverterToolWorkspaceModel.key)
        converter.targetFormat = .jpeg
        converter.quality = 0.64
        converter.session.rejectImageInput("converter-session-error")

        let compressor = repository.model(for: ImageCompressorToolWorkspaceModel.key)
        compressor.compressionPreference = .smallerFile
        compressor.limitsDimensions = true
        compressor.maxPixelLength = 2560
        compressor.session.rejectImageInput("compressor-session-error")

        let watermark = repository.model(for: ImageWatermarkToolWorkspaceModel.key)
        watermark.watermarkText = "session-only-watermark"
        watermark.opacity = 0.7
        watermark.sizeRatio = 0.18
        watermark.position = .topLeft
        watermark.session.rejectImageInput("watermark-session-error")

        converter.session.reset()
        compressor.session.reset()
        watermark.session.reset()

        #expect(converter.targetFormat == .jpeg)
        #expect(converter.quality == 0.64)
        #expect(converter.session.error == nil)
        #expect(compressor.compressionPreference == .smallerFile)
        #expect(compressor.limitsDimensions)
        #expect(compressor.maxPixelLength == 2560)
        #expect(compressor.session.error == nil)
        #expect(watermark.watermarkText == "session-only-watermark")
        #expect(watermark.opacity == 0.7)
        #expect(watermark.sizeRatio == 0.18)
        #expect(watermark.position == .topLeft)
        #expect(watermark.session.error == nil)
    }

    @MainActor
    @Test func imageRenderCompletesAfterVisiblePageOwnerDisappears() async throws {
        let repository = ToolWorkspaceRepository(defaults: Self.defaults())
        let imageData = try Self.makePNGData()
        let url = URL(fileURLWithPath: "/tmp/retained-image.png")
        let client = ImageWorkflowClient(
            dialog: RetentionImageDialog(),
            reader: RetentionImageReader(data: imageData),
            writer: RetentionImageWriter()
        )
        let originalIdentifier: ObjectIdentifier

        do {
            let workspace = repository.model(for: ImageConverterToolWorkspaceModel.key)
            originalIdentifier = ObjectIdentifier(workspace)
            workspace.session.receiveImageURL(
                url,
                allowedContentTypes: [.png],
                client: client,
                operation: .conversion
            ) { input in
                Thread.sleep(forTimeInterval: 0.15)
                return ProcessedImage(
                    data: input.data,
                    format: .png,
                    pixelWidth: input.metadata.pixelWidth,
                    pixelHeight: input.metadata.pixelHeight,
                    originalByteCount: input.data.count,
                    quality: nil,
                    wasResized: false
                )
            }
        }

        let restoredWhileRunning = repository.model(for: ImageConverterToolWorkspaceModel.key)
        #expect(ObjectIdentifier(restoredWhileRunning) == originalIdentifier)
        try await Self.waitUntil { restoredWhileRunning.session.output != nil }
        #expect(restoredWhileRunning.session.sourceURL == url)
        #expect(restoredWhileRunning.session.output?.data == imageData)
        #expect(!restoredWhileRunning.session.isProcessing)
        #expect(restoredWhileRunning.session.error == nil)
    }

    @MainActor
    @Test func newRepositoryRestoresOnlyApprovedImageRecipes() {
        let defaults = Self.defaults()
        let first = ToolWorkspaceRepository(defaults: defaults)
        let converter = first.model(for: ImageConverterToolWorkspaceModel.key)
        converter.targetFormat = .jpeg
        converter.quality = 0.64
        converter.transparencyFillMode = .custom
        converter.customTransparencyFillHex = "#336699"
        converter.session.rejectImageInput("must-not-persist")

        let compressor = first.model(for: ImageCompressorToolWorkspaceModel.key)
        compressor.compressionPreference = .smallerFile
        compressor.limitsDimensions = true
        compressor.maxPixelLength = 2560
        compressor.session.rejectImageInput("must-not-persist")

        let watermark = first.model(for: ImageWatermarkToolWorkspaceModel.key)
        watermark.watermarkText = "must-not-persist"
        watermark.opacity = 0.7
        watermark.sizeRatio = 0.18
        watermark.position = .topLeft
        watermark.textColor = .black
        watermark.session.rejectImageInput("must-not-persist")

        let relaunched = ToolWorkspaceRepository(defaults: defaults)
        let relaunchedConverter = relaunched.model(for: ImageConverterToolWorkspaceModel.key)
        let relaunchedCompressor = relaunched.model(for: ImageCompressorToolWorkspaceModel.key)
        let relaunchedWatermark = relaunched.model(for: ImageWatermarkToolWorkspaceModel.key)
        let relaunchedGrayscale = relaunched.model(for: ImageProcessedOutputSession.grayscaleWorkspaceKey)

        #expect(relaunchedConverter.targetFormat == .jpeg)
        #expect(relaunchedConverter.quality == 0.64)
        #expect(relaunchedConverter.transparencyFillMode == .custom)
        #expect(relaunchedConverter.customTransparencyFillHex == "#336699")
        #expect(relaunchedConverter.transparencyFill == ImageRGBColor(red: 0x33, green: 0x66, blue: 0x99))
        #expect(relaunchedConverter.session.source == nil)
        #expect(relaunchedConverter.session.output == nil)
        #expect(relaunchedConverter.session.error == nil)

        #expect(relaunchedCompressor.compressionPreference == .smallerFile)
        #expect(relaunchedCompressor.limitsDimensions)
        #expect(relaunchedCompressor.maxPixelLength == 2560)
        #expect(relaunchedCompressor.session.source == nil)
        #expect(relaunchedCompressor.session.output == nil)
        #expect(relaunchedCompressor.session.error == nil)

        #expect(relaunchedWatermark.watermarkText == "Watermark")
        #expect(relaunchedWatermark.opacity == 0.7)
        #expect(relaunchedWatermark.sizeRatio == 0.18)
        #expect(relaunchedWatermark.position == .topLeft)
        #expect(relaunchedWatermark.textColor == .black)
        #expect(relaunchedWatermark.session.source == nil)
        #expect(relaunchedWatermark.session.output == nil)
        #expect(relaunchedWatermark.session.error == nil)

        #expect(relaunchedGrayscale.source == nil)
        #expect(relaunchedGrayscale.output == nil)
        #expect(relaunchedGrayscale.error == nil)
    }

    @MainActor
    @Test func invalidImagePreferencesUseTypedFallbackOrContinuousClamping() {
        let defaults = Self.defaults()
        defaults.set("future-format", forKey: MediaToolPreferenceKeys.imageConverterTargetFormat.rawKey)
        defaults.set(9.0, forKey: MediaToolPreferenceKeys.imageConverterQuality.rawKey)
        defaults.set("future-fill", forKey: MediaToolPreferenceKeys.imageConverterTransparencyFillMode.rawKey)
        defaults.set("invalid", forKey: MediaToolPreferenceKeys.imageConverterCustomTransparencyFillHex.rawKey)
        defaults.set("future-preference", forKey: MediaToolPreferenceKeys.imageCompressorPreference.rawKey)
        defaults.set(99_999, forKey: MediaToolPreferenceKeys.imageCompressorMaxPixelLength.rawKey)
        defaults.set(0.0, forKey: MediaToolPreferenceKeys.imageWatermarkOpacity.rawKey)
        defaults.set(5_000.0, forKey: MediaToolPreferenceKeys.imageWatermarkFontSize.rawKey)
        defaults.set(5.0, forKey: MediaToolPreferenceKeys.imageWatermarkSizeRatio.rawKey)
        defaults.set("future-position", forKey: MediaToolPreferenceKeys.imageWatermarkPosition.rawKey)
        defaults.set("future-color", forKey: MediaToolPreferenceKeys.imageWatermarkColor.rawKey)

        let repository = ToolWorkspaceRepository(defaults: defaults)
        let converter = repository.model(for: ImageConverterToolWorkspaceModel.key)
        let compressor = repository.model(for: ImageCompressorToolWorkspaceModel.key)
        let watermark = repository.model(for: ImageWatermarkToolWorkspaceModel.key)

        #expect(converter.targetFormat == .png)
        #expect(converter.quality == 1.0)
        #expect(converter.transparencyFillMode == .unset)
        #expect(converter.customTransparencyFillHex == "#FFFFFF")
        #expect(converter.transparencyFill == nil)
        #expect(compressor.compressionPreference == .balanced)
        #expect(compressor.maxPixelLength == 1920)
        #expect(watermark.opacity == 0.1)
        #expect(watermark.sizeRatio == 0.80)
        #expect(watermark.position == .bottomRight)
        #expect(watermark.textColor == .white)
    }

    @MainActor
    @Test func watermarkSizeRatioRestoresApprovedRelativeValue() {
        let defaults = Self.defaults()
        defaults.set(0.32, forKey: MediaToolPreferenceKeys.imageWatermarkSizeRatio.rawKey)

        let repository = ToolWorkspaceRepository(defaults: defaults)
        let watermark = repository.model(for: ImageWatermarkToolWorkspaceModel.key)

        #expect(watermark.sizeRatio == 0.32)
    }

    @MainActor
    @Test func legacyAbsoluteWatermarkFontSizeDoesNotOverrideRelativeDefault() {
        let defaults = Self.defaults()
        defaults.set(500.0, forKey: MediaToolPreferenceKeys.imageWatermarkFontSize.rawKey)

        let repository = ToolWorkspaceRepository(defaults: defaults)
        let watermark = repository.model(for: ImageWatermarkToolWorkspaceModel.key)

        #expect(watermark.sizeRatio == 0.30)
    }

    @Test func imagePagesUseRetainedModelsWithoutMovingDropOrFocusPresentation() throws {
        let converter = try readSource("Sources/XTools/ToolPages/Image/ImageConverterPage.swift")
        let compressor = try readSource("Sources/XTools/ToolPages/Image/ImageCompressorPage.swift")
        let watermark = try readSource("Sources/XTools/ToolPages/Image/ImageWatermarkPage.swift")
        let grayscale = try readSource("Sources/XTools/ToolPages/Image/ImageGrayscalePage.swift")

        contains(converter, "ToolWorkspaceHost(key: ImageConverterToolWorkspaceModel.key)", "Image converter must resolve its retained workspace")
        contains(compressor, "ToolWorkspaceHost(key: ImageCompressorToolWorkspaceModel.key)", "Image compressor must resolve its retained workspace")
        contains(watermark, "ToolWorkspaceHost(key: ImageWatermarkToolWorkspaceModel.key)", "Image watermark must resolve its retained workspace")
        contains(grayscale, "ToolWorkspaceHost(key: ImageProcessedOutputSession.grayscaleWorkspaceKey)", "Image grayscale must resolve its retained session")

        for page in [converter, compressor, watermark, grayscale] {
            contains(page, "@State private var isImageDropTargeted = false", "Image drop highlighting must remain view-scoped")
            doesNotContain(page, "@StateObject private var session = ImageProcessedOutputSession()", "Image work must not be destroyed with page identity")
        }
        doesNotContain(watermark, "@State private var isEditingWatermarkText", "Watermark preview scheduling must not depend on field-focus state")
        contains(watermark, "let previewDebouncer = IndexDebouncer()", "Watermark bounded-preview debounce must belong to the retained workspace")
        contains(watermark, "let finalDebouncer = IndexDebouncer()", "Watermark full-resolution debounce must belong to the retained workspace")
        doesNotContain(watermark, "@State private var debounceTask", "Watermark pending render must not disappear with page-local state")
    }

    @MainActor
    @Test func mediaPreferenceKeysExcludePathsTextAndBinaryResults() {
        let expected = Set([
            "tools.base64File.outputMode.v1",
            "tools.imageConverter.targetFormat.v1",
            "tools.imageConverter.quality.v1",
            "tools.imageConverter.transparencyFillMode.v1",
            "tools.imageConverter.customTransparencyFillHex.v1",
            "tools.imageCompressor.preference.v1",
            "tools.imageCompressor.limitsDimensions.v1",
            "tools.imageCompressor.maxPixelLength.v1",
            "tools.imageWatermark.opacity.v1",
            "tools.imageWatermark.fontSize.v1",
            "tools.imageWatermark.sizeRatio.v2",
            "tools.imageWatermark.position.v1",
            "tools.imageWatermark.color.v1"
        ])
        #expect(Set(MediaToolPreferenceKeys.allRawKeys) == expected)

        for rawKey in MediaToolPreferenceKeys.allRawKeys {
            let normalized = rawKey.lowercased()
            #expect(!normalized.contains("path"))
            #expect(!normalized.contains("url"))
            #expect(!normalized.contains("filename"))
            #expect(!normalized.contains("text"))
            #expect(!normalized.contains("source"))
            #expect(!normalized.contains("preview"))
            #expect(!normalized.contains("outputdata"))
            #expect(!normalized.contains("result"))
            #expect(!normalized.contains("error"))
        }
    }

    private static func defaults() -> UserDefaults {
        let suiteName = "ImageWorkspaceRetentionTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    @MainActor
    private static func waitUntil(
        timeout: Duration = .seconds(20),
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while !condition(), clock.now < deadline {
            try await Task.sleep(for: .milliseconds(25))
        }
        #expect(condition())
    }

    @MainActor
    private static func makePNGData() throws -> Data {
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 2,
            pixelsHigh: 2,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ), let data = bitmap.representation(using: .png, properties: [:]) else {
            throw ImageWorkflowFailure.unreadableImage
        }
        return data
    }

}

struct FileAndFaviconWorkspaceRetentionTests {
    @MainActor
    @Test func faviconAndFileDetectorSessionsSurviveNavigationButNotRelaunch() {
        let defaults = Self.defaults()
        let repository = ToolWorkspaceRepository(defaults: defaults)

        let favicon = repository.model(for: FaviconOutputSetSession.workspaceKey)
        favicon.rejectImageInput("favicon-session-error")
        let detector = repository.model(for: FileTypeDetectorSession.workspaceKey)
        detector.rejectMultipleFileDrop()

        #expect(repository.model(for: FaviconOutputSetSession.workspaceKey) === favicon)
        #expect(favicon.error == "favicon-session-error")
        #expect(repository.model(for: FileTypeDetectorSession.workspaceKey) === detector)
        #expect(detector.error == SingleFileDropResolver.multipleFilesDiagnostic)

        let relaunched = ToolWorkspaceRepository(defaults: defaults)
        let relaunchedFavicon = relaunched.model(for: FaviconOutputSetSession.workspaceKey)
        let relaunchedDetector = relaunched.model(for: FileTypeDetectorSession.workspaceKey)
        #expect(relaunchedFavicon.source == nil)
        #expect(relaunchedFavicon.icons.isEmpty)
        #expect(relaunchedFavicon.error == nil)
        #expect(relaunchedDetector.selectedFileURL == nil)
        #expect(relaunchedDetector.report == nil)
        #expect(relaunchedDetector.error == nil)
    }

    @MainActor
    @Test func faviconGenerationCompletesWhileOnlyRepositoryOwnsTheSession() async throws {
        let repository = ToolWorkspaceRepository(defaults: Self.defaults())
        let key = ToolWorkspaceKey(
            toolID: ToolID(rawValue: "favicon-generator"),
            slot: "continuity-test"
        ) { _ in
            FaviconOutputSetSession(outputSpecs: [FaviconOutputSpec(size: 16)])
        }
        let session = repository.model(for: key)
        let url = URL(fileURLWithPath: "/tmp/retained-favicon.png")
        let imageData = try Self.makePNGData()
        let client = ImageWorkflowClient(
            dialog: RetentionImageDialog(),
            reader: RetentionImageReader(data: imageData),
            writer: RetentionImageWriter()
        )

        session.receiveImageURL(url, client: client) { _, sizes in
            Thread.sleep(forTimeInterval: 0.15)
            return sizes.map {
                GeneratedIcon(size: $0, data: Data([UInt8($0)]), pixelWidth: $0, pixelHeight: $0, format: .png)
            }
        }

        let restoredWhileRunning = repository.model(for: key)
        #expect(restoredWhileRunning === session)
        try await Self.waitUntil { !restoredWhileRunning.icons.isEmpty }
        #expect(restoredWhileRunning.icons.map(\.size) == [16])
        #expect(restoredWhileRunning.error == nil)
    }

    @MainActor
    @Test func fileInspectionCompletesWhileOnlyRepositoryOwnsTheSession() async throws {
        let repository = ToolWorkspaceRepository(defaults: Self.defaults())
        let key = ToolWorkspaceKey(
            toolID: ToolID(rawValue: "file-type-detector"),
            slot: "continuity-test"
        ) { _ in
            FileTypeDetectorSession(reader: SlowRetentionFileTypeReader())
        }
        let session = repository.model(for: key)
        session.inspect(URL(fileURLWithPath: "/tmp/retained.json"))

        let restoredWhileRunning = repository.model(for: key)
        #expect(restoredWhileRunning === session)
        try await Self.waitUntil { restoredWhileRunning.report != nil }
        #expect(restoredWhileRunning.report?.fileName == "retained.json")
        #expect(restoredWhileRunning.error == nil)
    }

    @Test func pagesUseRepositorySessionsAndNavigationDoesNotCancelFavicon() throws {
        let favicon = try readSource("Sources/XTools/ToolPages/Image/FaviconGeneratorPage.swift")
        let fileType = try readSource("Sources/XTools/ToolPages/Utility/FileTypeDetectorPage.swift")

        contains(favicon, "ToolWorkspaceHost(key: FaviconOutputSetSession.workspaceKey)", "Favicon page must resolve its retained session")
        contains(favicon, "@ObservedObject var session: FaviconOutputSetSession", "Favicon content must observe the retained session")
        contains(favicon, "@State private var isImageDropTargeted = false", "Favicon drop highlighting must remain view-scoped")
        doesNotContain(favicon, ".onDisappear", "Ordinary navigation must not cancel Favicon generation")
        doesNotContain(favicon, "session.cancelGeneration()", "Favicon page disappearance must not become an operation cancellation boundary")

        contains(fileType, "ToolWorkspaceHost(key: FileTypeDetectorSession.workspaceKey)", "File detector page must resolve its retained session")
        contains(fileType, "@ObservedObject var session: FileTypeDetectorSession", "File detector content must observe the retained session")
        contains(fileType, "@State private var isFileDropTargeted = false", "File detector drop highlighting must remain view-scoped")
    }

    private static func defaults() -> UserDefaults {
        let suiteName = "FileAndFaviconWorkspaceRetentionTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    @MainActor
    private static func waitUntil(
        timeout: Duration = .seconds(20),
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while !condition(), clock.now < deadline {
            try await Task.sleep(for: .milliseconds(25))
        }
        #expect(condition())
    }

    @MainActor
    private static func makePNGData() throws -> Data {
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 2,
            pixelsHigh: 2,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ), let data = bitmap.representation(using: .png, properties: [:]) else {
            throw ImageWorkflowFailure.unreadableImage
        }
        return data
    }
}

@MainActor
private struct RetentionImageDialog: ImageWorkflowDialoging {
    func selectSaveURL(defaultFilename: String, allowedContentTypes: [UTType]) -> URL? { nil }
    func selectDirectory(prompt: String) -> URL? { nil }
}

private struct RetentionImageReader: ImageWorkflowFileReading {
    let data: Data

    func isRegularFile(at url: URL) throws -> Bool { true }
    func byteCount(for url: URL) throws -> Int? { data.count }
    func readData(from url: URL) throws -> Data { data }
}

private struct RetentionImageWriter: ImageWorkflowFileWriting {
    func write(_ data: Data, to url: URL) throws {}
}

private struct SlowRetentionFileTypeReader: FileTypeFileReading {
    func metadata(for url: URL) throws -> FileTypeFileMetadata {
        Thread.sleep(forTimeInterval: 0.15)
        return FileTypeFileMetadata(byteCount: 2)
    }

    func readLeadingData(from url: URL, maxByteCount: Int) throws -> Data {
        Data("{}".utf8.prefix(maxByteCount))
    }
}

struct TimeWorkspaceRetentionTests {
    @MainActor
    @Test func chronometerUsesRetainedMonotonicStateAndRelaunchResets() {
        let defaults = Self.defaults()
        let repository = ToolWorkspaceRepository(defaults: defaults)
        let workspace = repository.model(for: ChronometerToolWorkspaceModel.key)

        workspace.chronometer.start(at: 10)
        let lap = ChronometerLap(interval: 2.5, split: 2.5)
        #expect(workspace.chronometer.recordLap(at: 12.5) == lap)

        let restored = repository.model(for: ChronometerToolWorkspaceModel.key)
        #expect(restored === workspace)
        #expect(restored.chronometer.isRunning)
        #expect(restored.chronometer.elapsed(at: 15) == 5)
        #expect(restored.chronometer.laps == [lap])

        let relaunched = ToolWorkspaceRepository(defaults: defaults)
            .model(for: ChronometerToolWorkspaceModel.key)
        #expect(relaunched !== workspace)
        #expect(!relaunched.chronometer.isRunning)
        #expect(relaunched.chronometer.elapsed(at: 15) == 0)
        #expect(relaunched.chronometer.laps.isEmpty)
    }

    @MainActor
    @Test func dateCalculatorWorkSurvivesNavigationAndRelaunchResets() {
        let defaults = Self.defaults()
        let repository = ToolWorkspaceRepository(defaults: defaults)
        let workspace = repository.model(for: DateCalcToolWorkspaceModel.key)

        workspace.session.includeEndDate = true
        workspace.session.amount = 45
        workspace.session.op = "0"
        workspace.session.markStartInvalidPaste()

        let restored = repository.model(for: DateCalcToolWorkspaceModel.key)
        #expect(restored === workspace)
        #expect(restored.session.includeEndDate)
        #expect(restored.session.amount == 45)
        #expect(restored.session.op == "0")
        #expect(restored.session.startInputError != nil)

        let relaunched = ToolWorkspaceRepository(defaults: defaults)
            .model(for: DateCalcToolWorkspaceModel.key)
        #expect(relaunched !== workspace)
        #expect(!relaunched.session.includeEndDate)
        #expect(relaunched.session.amount == 30)
        #expect(relaunched.session.op == "1")
        #expect(relaunched.session.startInputError == nil)
    }

    @Test func timePagesKeepTimelineAndCalendarPresentationViewScoped() throws {
        let chronometer = try readSource("Sources/XTools/ToolPages/Time/ChronometerPage.swift")
        let dateCalculator = try readSource("Sources/XTools/ToolPages/Time/DateCalculatorPage.swift")
        let timezone = try readSource("Sources/XTools/ToolPages/Time/TimezoneViewerPage.swift")
        let deviceInfo = try readSource("Sources/XTools/ToolPages/Utility/DeviceInformationPage.swift")

        contains(chronometer, "ToolWorkspaceHost(key: ChronometerToolWorkspaceModel.key)", "Chronometer must resolve retained monotonic state")
        contains(chronometer, "@Binding var chronometer: ChronometerState", "Visible chronometer content must bind the retained Core value")
        contains(chronometer, ".animation(minimumInterval: 0.01, paused: !chronometer.isRunning)", "Chronometer paused animation schedule must remain mounted only with visible page content")
        let chronometerModel = sourceSlice(chronometer, from: "final class ChronometerToolWorkspaceModel", to: "struct IndexChronometerPage")
        doesNotContain(chronometerModel, "TimelineView", "Retained chronometer state must not keep a hidden high-frequency view alive")

        contains(dateCalculator, "ToolWorkspaceHost(key: DateCalcToolWorkspaceModel.key)", "Date calculator must resolve its retained workspace")
        contains(dateCalculator, "@Binding var session: DateCalcWorkspace", "Date calculator content must bind the retained Core workspace")
        contains(dateCalculator, "@State private var showsCalendar = false", "Calendar presentation must remain view-scoped")

        contains(timezone, "@StateObject private var favoriteStore = TimezoneViewerFavoriteStore()", "Timezone existing favorite persistence owner must remain unchanged")
        contains(timezone, "@StateObject private var disclosureSections = TimezoneViewerDisclosureExpansionStore()", "Timezone existing disclosure persistence owner must remain unchanged")
        doesNotContain(timezone, "ToolWorkspaceHost(", "Timezone current-time TimelineView does not need retained workspace ownership")

        contains(deviceInfo, "@StateObject private var session = DeviceInformationSession()", "Device information must capture a fresh visible-page snapshot on return")
        contains(deviceInfo, "session.refresh()", "Device information refresh wiring must remain intact")
        doesNotContain(deviceInfo, "ToolWorkspaceHost(", "Device information stale system snapshots must not be retained across navigation")
    }

    private static func defaults() -> UserDefaults {
        let suiteName = "TimeWorkspaceRetentionTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
