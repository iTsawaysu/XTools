import AppKit
import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import XTools
@testable import XToolsCore

@MainActor
struct ImageWorkflowClientTests {
    @Test func imageWorkflowFailureMessagesAreFactualAndTyped() {
        let failures: [ImageWorkflowFailure] = [
            .unreadableImage,
            .notRegularFile,
            .unsupportedInputType,
            .readFailed,
            .saveFailed,
            .partialSaveFailed(savedCount: 2, totalCount: 8),
            .processingFailed(.conversion),
            .processingFailed(.compression),
            .processingFailed(.watermark),
            .processingFailed(.grayscale),
            .processingFailed(.favicon),
            .noConversionTarget,
            .blockedCompressionSave
        ]

        for failure in failures {
            ToolDiagnosticContract.expectFactual(failure.errorDescription ?? "")
        }

        #expect(
            ImageWorkflowFailure.partialSaveFailed(savedCount: 2, totalCount: 8).errorDescription
                == "已保存 2/8 个图标。"
        )
    }

    @Test func prepareSelectionInBackgroundBuildsSelectionFromAnExistingURL() async throws {
        let imageData = try Self.makeImageData(width: 1800, height: 1200, format: .png)
        let url = URL(fileURLWithPath: "/tmp/large-source.png")
        let reader = FakeImageWorkflowReader(dataByURL: [url: imageData])
        let client = ImageWorkflowClient(
            dialog: FakeImageWorkflowDialog(),
            reader: reader,
            writer: FakeImageWorkflowWriter()
        )

        let selection = try await client.prepareSelectionInBackground(
            from: url,
            allowedContentTypes: [.png]
        )

        #expect(selection.url == url)
        #expect(selection.data == imageData)
        #expect(selection.metadata.format == .png)
        #expect(selection.metadata.pixelWidth == 1800)
        #expect(selection.metadata.pixelHeight == 1200)
        #expect(!selection.previewData.isEmpty)
        #expect(max(selection.image.size.width, selection.image.size.height) <= 1024)
        #expect(reader.readURLs == [url])
    }

    @Test func watermarkPreviewSessionPublishesOnlyLatestGenerationAndResetRejectsLateWork() async throws {
        let session = ImageWatermarkPreviewSession()
        let first = try Self.makeImageData(width: 12, height: 8, format: .png)
        let second = try Self.makeImageData(width: 13, height: 9, format: .png)
        let recipe = ImageWatermarkRecipe(
            text: "WM",
            opacity: 0.5,
            fontSize: 24,
            position: .center,
            color: .white
        )

        session.render(
            previewData: first,
            sourcePixelWidth: 12,
            sourcePixelHeight: 8,
            recipe: recipe
        ) { _, _, _, _ in
            Thread.sleep(forTimeInterval: 0.15)
            return first
        }
        session.render(
            previewData: second,
            sourcePixelWidth: 13,
            sourcePixelHeight: 9,
            recipe: recipe
        ) { _, _, _, _ in
            Thread.sleep(forTimeInterval: 0.01)
            return second
        }

        try await Self.waitUntil { session.data == second }
        try await Task.sleep(for: .milliseconds(400))
        #expect(session.data == second)
        #expect(!session.isRendering)

        session.render(
            previewData: first,
            sourcePixelWidth: 12,
            sourcePixelHeight: 8,
            recipe: recipe
        ) { _, _, _, _ in
            Thread.sleep(forTimeInterval: 0.1)
            return first
        }
        session.reset()
        try await Task.sleep(for: .milliseconds(350))
        #expect(session.data == nil)
        #expect(session.image == nil)
        #expect(!session.isRendering)
    }


    @Test func watermarkPreviewSessionKeepsPriorImageUntilReplacementPublishes() async throws {
        let session = ImageWatermarkPreviewSession()
        let first = try Self.makeImageData(width: 12, height: 8, format: .png)
        let second = try Self.makeImageData(width: 13, height: 9, format: .png)
        let recipe = ImageWatermarkRecipe(
            text: "WM",
            opacity: 0.5,
            fontSize: 24,
            position: .bottomRight,
            color: .white
        )

        session.render(
            previewData: first,
            sourcePixelWidth: 12,
            sourcePixelHeight: 8,
            recipe: recipe
        ) { _, _, _, _ in
            first
        }
        try await Self.waitUntil { session.data == first }

        session.render(
            previewData: second,
            sourcePixelWidth: 13,
            sourcePixelHeight: 9,
            recipe: recipe
        ) { _, _, _, _ in
            Thread.sleep(forTimeInterval: 0.08)
            return second
        }

        #expect(session.data == first)
        #expect(session.image != nil)
        #expect(session.isRendering)
        try await Self.waitUntil { session.data == second }
        #expect(!session.isRendering)
    }

    @Test func prepareSelectionInBackgroundRejectsActualFormatOutsideAllowedTypes() async throws {
        let jpegData = try Self.makeImageData(width: 12, height: 8, format: .jpeg)
        let misleadingURL = URL(fileURLWithPath: "/tmp/not-really-png.png")
        let client = ImageWorkflowClient(
            dialog: FakeImageWorkflowDialog(),
            reader: FakeImageWorkflowReader(dataByURL: [misleadingURL: jpegData]),
            writer: FakeImageWorkflowWriter()
        )

        do {
            _ = try await client.prepareSelectionInBackground(
                from: misleadingURL,
                allowedContentTypes: [.png]
            )
            Issue.record("Expected actual JPEG data to be rejected by a PNG-only request")
        } catch let failure as ImageWorkflowFailure {
            #expect(failure == .unsupportedInputType)
        } catch {
            Issue.record("Unexpected failure: \(error)")
        }
    }

    @Test func prepareSelectionInBackgroundRejectsNonRegularFilesBeforeReadingData() async throws {
        let directoryURL = URL(fileURLWithPath: "/tmp/image-folder", isDirectory: true)
        let reader = FakeImageWorkflowReader(
            dataByURL: [directoryURL: Data("must not be read".utf8)],
            nonRegularURLs: [directoryURL]
        )
        let client = ImageWorkflowClient(
            dialog: FakeImageWorkflowDialog(),
            reader: reader,
            writer: FakeImageWorkflowWriter()
        )

        do {
            _ = try await client.prepareSelectionInBackground(
                from: directoryURL,
                allowedContentTypes: ImageWorkflowClient.standardImageContentTypes
            )
            Issue.record("Expected a directory URL to be rejected")
        } catch let failure as ImageWorkflowFailure {
            #expect(failure == .notRegularFile)
        } catch {
            Issue.record("Unexpected failure: \(error)")
        }
        #expect(reader.readURLs.isEmpty)
    }

    @Test func prepareSelectionInBackgroundKeepsStandardTIFFButRejectsItForFavicon() async throws {
        let tiffData = try Self.makeImageData(width: 12, height: 8, format: .tiff)
        let url = URL(fileURLWithPath: "/tmp/source.tiff")
        let client = ImageWorkflowClient(
            dialog: FakeImageWorkflowDialog(),
            reader: FakeImageWorkflowReader(dataByURL: [url: tiffData]),
            writer: FakeImageWorkflowWriter()
        )

        let standardSelection = try await client.prepareSelectionInBackground(
            from: url,
            allowedContentTypes: ImageWorkflowClient.standardImageContentTypes
        )
        #expect(standardSelection.metadata.format == .tiff)

        do {
            _ = try await client.prepareSelectionInBackground(
                from: url,
                allowedContentTypes: ImageWorkflowClient.faviconInputContentTypes
            )
            Issue.record("Expected Favicon input to reject TIFF data")
        } catch let failure as ImageWorkflowFailure {
            #expect(failure == .unsupportedInputType)
        } catch {
            Issue.record("Unexpected failure: \(error)")
        }
    }

    @Test func imageInputContentTypesFollowRuntimeReadableAllowlist() {
        let readable = Set(ImageFileFormat.supportedInputFormats.map(\.utTypeIdentifier))
        let standard = Set(ImageWorkflowClient.standardImageContentTypes.map(\.identifier))
        let favicon = Set(ImageWorkflowClient.faviconInputContentTypes.map(\.identifier))

        #expect(standard == readable)
        #expect(favicon == readable.subtracting([UTType.tiff.identifier]))
        #expect(!favicon.contains(UTType.tiff.identifier))
    }

    @Test func prepareSelectionInBackgroundPropagatesCallerCancellation() async throws {
        let imageData = try Self.makeImageData(width: 12, height: 8, format: .png)
        let url = URL(fileURLWithPath: "/tmp/slow-source.png")
        // Keep the fake read slow enough that cancel is observed before
        // completion even under full-suite main-actor congestion.
        let reader = FakeImageWorkflowReader(
            dataByURL: [url: imageData],
            readDelayByURL: [url: 5.0]
        )
        let client = ImageWorkflowClient(
            dialog: FakeImageWorkflowDialog(),
            reader: reader,
            writer: FakeImageWorkflowWriter()
        )
        let task = Task {
            try await client.prepareSelectionInBackground(from: url, allowedContentTypes: [.png])
        }

        try await Self.waitUntil { reader.readURLs.contains(url) }
        task.cancel()

        do {
            _ = try await task.value
            Issue.record("Expected caller cancellation to cancel image preparation")
        } catch is CancellationError {
            // Expected.
        } catch {
            Issue.record("Unexpected failure: \(error)")
        }
    }

    @Test func unknownImageErrorsMapToStableOperationMessages() {
        let lowLevelError = NSError(
            domain: "NSCocoaErrorDomain",
            code: 4,
            userInfo: [NSLocalizedDescriptionKey: "Cannot write /tmp/private/output.png"]
        )

        let message = ImageWorkflowFailure.diagnosticMessage(
            for: lowLevelError,
            unknownFailure: .processingFailed(.watermark)
        )

        #expect(message == "水印生成失败。")
        ToolDiagnosticContract.expectFactual(
            message,
            sensitiveInputs: ["Cannot write /tmp/private/output.png"]
        )
    }

    @Test func imageProcessorMessagesCoverEveryFailureCategory() {
        let failures: [ImageProcessorError] = [
            .unreadableImage,
            .missingImageProperties,
            .unsupportedFormat(.webP),
            .encodingFailed(.heic),
            .renderingFailed,
            .invalidIconSize(0),
            .inputFileTooLarge(actualBytes: 99_000_000, maxBytes: ImageProcessingBudget.maxInputBytes),
            .imageTooLarge(pixelCount: 99_000_000, maxPixelCount: ImageProcessingBudget.maxPixelCount)
        ]

        for failure in failures {
            ToolDiagnosticContract.expectFactual(failure.errorDescription ?? "")
        }
    }

    @Test func blockedCompressionMessageIsOneStableResultState() {
        #expect(ImageOutputPresentation.blockedCompressionMessage == "未生成更小文件")
        ToolDiagnosticContract.expectFactual(ImageOutputPresentation.blockedCompressionMessage)
    }

    @Test func prepareSelectionInBackgroundReturnsDecodedImageAndMetadata() async throws {
        let imageData = try Self.makeImageData(width: 12, height: 8, format: .png)
        let url = URL(fileURLWithPath: "/tmp/source.png")
        let reader = FakeImageWorkflowReader(dataByURL: [url: imageData])
        let writer = FakeImageWorkflowWriter()
        let client = ImageWorkflowClient(dialog: FakeImageWorkflowDialog(), reader: reader, writer: writer)

        let selection = try await client.prepareSelectionInBackground(from: url, allowedContentTypes: [.png])

        #expect(selection.url == url)
        #expect(selection.data == imageData)
        #expect(selection.metadata.format == .png)
        #expect(selection.metadata.pixelWidth == 12)
        #expect(selection.metadata.pixelHeight == 8)
        #expect(selection.image.size.width > 0)
    }

    @Test func prepareSelectionInBackgroundReadsAndPreparesBoundedPreview() async throws {
        let imageData = try Self.makeImageData(width: 1800, height: 1200, format: .png)
        let url = URL(fileURLWithPath: "/tmp/large-source.png")
        let reader = FakeImageWorkflowReader(dataByURL: [url: imageData])
        let writer = FakeImageWorkflowWriter()
        let client = ImageWorkflowClient(dialog: FakeImageWorkflowDialog(), reader: reader, writer: writer)

        let selection = try await client.prepareSelectionInBackground(from: url, allowedContentTypes: [.png])

        #expect(selection.url == url)
        #expect(selection.data == imageData)
        #expect(selection.metadata.pixelWidth == 1800)
        #expect(selection.metadata.pixelHeight == 1200)
        #expect(max(selection.image.size.width, selection.image.size.height) <= 1024)
        #expect(reader.readURLs == [url])
    }

    @Test func prepareSelectionInBackgroundMapsSystemReadFailureWithoutLeakingPathOrNSError() async {
        let url = URL(fileURLWithPath: "/tmp/private/source.png")
        let systemError = NSError(
            domain: "NSCocoaErrorDomain",
            code: 257,
            userInfo: [NSLocalizedDescriptionKey: "Permission denied: /tmp/private/source.png"]
        )
        let client = ImageWorkflowClient(
            dialog: FakeImageWorkflowDialog(),
            reader: FakeImageWorkflowReader(error: systemError),
            writer: FakeImageWorkflowWriter()
        )

        do {
            _ = try await client.prepareSelectionInBackground(from: url, allowedContentTypes: [.png])
            Issue.record("Expected the system read failure to be normalized")
        } catch let failure as ImageWorkflowFailure {
            #expect(failure == .readFailed)
        } catch {
            Issue.record("Unexpected failure: \(error)")
        }
    }

    @Test func prepareSelectionInBackgroundPreservesSpecificInvalidImageFailure() async throws {
        let url = URL(fileURLWithPath: "/tmp/not-image.png")
        let reader = FakeImageWorkflowReader(dataByURL: [url: Data("not an image".utf8)])
        let client = ImageWorkflowClient(dialog: FakeImageWorkflowDialog(), reader: reader, writer: FakeImageWorkflowWriter())

        do {
            _ = try await client.prepareSelectionInBackground(from: url, allowedContentTypes: [.png])
            Issue.record("Expected invalid image metadata to be rejected")
        } catch let processorError as ImageProcessorError {
            #expect(processorError == .missingImageProperties)
        } catch {
            Issue.record("Unexpected failure: \(error)")
        }
    }

    @Test func prepareSelectionInBackgroundRejectsOversizedReportedFileBeforeReadingData() async throws {
        let url = URL(fileURLWithPath: "/tmp/huge.png")
        let reader = FakeImageWorkflowReader(
            dataByURL: [url: Data("not reached".utf8)],
            byteCountsByURL: [url: ImageProcessingBudget.maxInputBytes + 1]
        )
        let client = ImageWorkflowClient(dialog: FakeImageWorkflowDialog(), reader: reader, writer: FakeImageWorkflowWriter())

        do {
            _ = try await client.prepareSelectionInBackground(from: url, allowedContentTypes: [.png])
            Issue.record("Expected oversized metadata to fail before reading")
        } catch let processorError as ImageProcessorError {
            #expect(processorError == .inputFileTooLarge(
                actualBytes: ImageProcessingBudget.maxInputBytes + 1,
                maxBytes: ImageProcessingBudget.maxInputBytes
            ))
        } catch {
            Issue.record("Unexpected failure: \(error)")
        }
        #expect(reader.readURLs.isEmpty)
        #expect(ImageProcessorError.inputFileTooLarge(
            actualBytes: ImageProcessingBudget.maxInputBytes + 1,
            maxBytes: ImageProcessingBudget.maxInputBytes
        ).errorDescription == "图片文件大小上限为 50 MB，所选文件已超出。")
    }

    @Test func foundationReaderBoundsRealFileWhenMetadataIsMissingOrStale() async throws {
        let maxBytes = 8
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("xtools-image-reader-budget-\(UUID().uuidString).bin")
        let retainedDirectory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Downloads/tmp", isDirectory: true)
        let retainedURL = retainedDirectory.appendingPathComponent(url.lastPathComponent)
        try FileManager.default.createDirectory(at: retainedDirectory, withIntermediateDirectories: true)
        try Data(repeating: 0xA5, count: maxBytes + 1).write(to: url)
        defer { try? FileManager.default.moveItem(at: url, to: retainedURL) }

        let reportedByteCounts: [Int?] = [nil, 1]
        for reportedByteCount in reportedByteCounts {
            let reader = FoundationImageWorkflowReaderWithMetadataOverride(
                reportedByteCount: reportedByteCount,
                maxBytes: maxBytes
            )
            let client = ImageWorkflowClient(
                dialog: FakeImageWorkflowDialog(),
                reader: reader,
                writer: FakeImageWorkflowWriter()
            )

            do {
                _ = try await client.prepareSelectionInBackground(
                    from: url,
                    allowedContentTypes: [.png]
                )
                Issue.record("Expected the bounded Foundation reader to reject the file")
            } catch let processorError as ImageProcessorError {
                #expect(processorError == .inputFileTooLarge(
                    actualBytes: maxBytes + 1,
                    maxBytes: maxBytes
                ))
            } catch {
                Issue.record("Unexpected failure: \(error)")
            }
        }
    }

    @Test func saveProcessedImageBlocksLargerCompressionOutputBeforeShowingSavePanel() async throws {
        let saveURL = URL(fileURLWithPath: "/tmp/compressed.jpg")
        let dialog = FakeImageWorkflowDialog(saveURL: saveURL)
        let writer = FakeImageWorkflowWriter()
        let client = ImageWorkflowClient(dialog: dialog, reader: FakeImageWorkflowReader(), writer: writer)
        let output = Self.processedImage(byteCount: 20, originalByteCount: 10, format: .jpeg)
        let assessment = ImageOutputPolicy.assess(output, for: .compression)

        await #expect(throws: ImageWorkflowFailure.blockedCompressionSave) {
            _ = try await client.saveProcessedImage(output, assessment: assessment, defaultBasename: "compressed")
        }
        #expect(dialog.requestedSaveNames.isEmpty)
        #expect(writer.writes.isEmpty)
    }

    @Test func saveProcessedImageAllowsLargerConversionWatermarkAndGrayscaleOutputs() async throws {
        let output = Self.processedImage(byteCount: 20, originalByteCount: 10, format: .png)

        for workflow in [ImageOutputWorkflow.conversion, .watermark, .grayscale] {
            let saveURL = URL(fileURLWithPath: "/tmp/\(workflow)-output.png")
            let dialog = FakeImageWorkflowDialog(saveURL: saveURL)
            let writer = FakeImageWorkflowWriter()
            let client = ImageWorkflowClient(dialog: dialog, reader: FakeImageWorkflowReader(), writer: writer)
            let assessment = ImageOutputPolicy.assess(output, for: workflow)

            let didSave = try await client.saveProcessedImage(output, assessment: assessment, defaultBasename: "output")

            #expect(didSave)
            #expect(dialog.requestedSaveNames == ["output.png"])
            #expect(writer.writes.map(\.url) == [saveURL])
            #expect(writer.writes.map(\.data) == [output.data])
        }
    }

    @Test func saveArtifactUsesItsRealFilenameAndBytes() async throws {
        let saveURL = URL(fileURLWithPath: "/tmp/favicon.ico")
        let dialog = FakeImageWorkflowDialog(saveURL: saveURL)
        let writer = FakeImageWorkflowWriter()
        let client = ImageWorkflowClient(dialog: dialog, reader: FakeImageWorkflowReader(), writer: writer)
        let artifact = Self.artifact(.faviconICO, data: Data([0, 1, 2, 3]))

        #expect(try await client.saveArtifact(artifact))
        #expect(dialog.requestedSaveNames == ["favicon.ico"])
        #expect(writer.writes.map(\.url) == [saveURL])
        #expect(writer.writes.map(\.data) == [artifact.data])
    }

    @Test func saveArtifactsWritesTheStableFiveFilePackageOrder() async throws {
        let directory = URL(fileURLWithPath: "/tmp/favicon-package", isDirectory: true)
        let dialog = FakeImageWorkflowDialog(directoryURL: directory)
        let writer = FakeImageWorkflowWriter()
        let client = ImageWorkflowClient(dialog: dialog, reader: FakeImageWorkflowReader(), writer: writer)
        let artifacts = FaviconArtifactID.allCases.enumerated().map { index, id in
            Self.artifact(id, data: Data([UInt8(index)]))
        }

        #expect(try await client.saveArtifacts(artifacts))
        #expect(writer.writes.map { $0.url.lastPathComponent } == FaviconArtifactID.allCases.map(\.rawValue))
        #expect(writer.writes.map(\.data) == artifacts.map(\.data))
    }

    @Test func saveArtifactsDistinguishesCancelFirstFailureAndPartialFailure() async throws {
        let artifacts = [
            Self.artifact(.faviconICO, data: Data([1])),
            Self.artifact(.appleTouchIcon, data: Data([2]))
        ]
        let cancelledWriter = FakeImageWorkflowWriter()
        let cancelledClient = ImageWorkflowClient(
            dialog: FakeImageWorkflowDialog(),
            reader: FakeImageWorkflowReader(),
            writer: cancelledWriter
        )
        #expect(try await cancelledClient.saveArtifacts(artifacts) == false)
        #expect(cancelledWriter.writes.isEmpty)

        let directory = URL(fileURLWithPath: "/tmp/favicon-package", isDirectory: true)
        let firstFailureClient = ImageWorkflowClient(
            dialog: FakeImageWorkflowDialog(directoryURL: directory),
            reader: FakeImageWorkflowReader(),
            writer: FakeImageWorkflowWriter(error: ImageSessionTestError.writeFailed, failAfter: 0)
        )
        await #expect(throws: ImageWorkflowFailure.saveFailed) {
            try await firstFailureClient.saveArtifacts(artifacts)
        }

        let partialClient = ImageWorkflowClient(
            dialog: FakeImageWorkflowDialog(directoryURL: directory),
            reader: FakeImageWorkflowReader(),
            writer: FakeImageWorkflowWriter(error: ImageSessionTestError.writeFailed, failAfter: 1)
        )
        await #expect {
            try await partialClient.saveArtifacts(artifacts)
        } throws: { error in
            guard case ImageWorkflowFailure.partialSaveFailed(savedCount: 1, totalCount: 2) = error else {
                return false
            }
            return true
        }
    }

    @Test func saveIconsWritesFaviconIconSetIntoSelectedDirectory() async throws {
        let directory = URL(fileURLWithPath: "/tmp/favicons", isDirectory: true)
        let dialog = FakeImageWorkflowDialog(directoryURL: directory)
        let writer = FakeImageWorkflowWriter()
        let client = ImageWorkflowClient(dialog: dialog, reader: FakeImageWorkflowReader(), writer: writer)
        let icons = [
            GeneratedIcon(size: 16, data: Data([1, 6]), pixelWidth: 16, pixelHeight: 16, format: .png),
            GeneratedIcon(size: 32, data: Data([3, 2]), pixelWidth: 32, pixelHeight: 32, format: .png)
        ]

        let didSave = try await client.saveIcons(icons) { icon in
            "favicon-\(icon.size)x\(icon.size).png"
        }

        #expect(didSave)
        #expect(writer.writes.map { $0.url.lastPathComponent } == [
            "favicon-16x16.png",
            "favicon-32x32.png"
        ])
        #expect(writer.writes.map(\.data) == [Data([1, 6]), Data([3, 2])])
    }

    @Test func saveIconsReportsPartialProgressWhenALaterWriteFails() async throws {
        let directory = URL(fileURLWithPath: "/tmp/icons", isDirectory: true)
        let dialog = FakeImageWorkflowDialog(directoryURL: directory)
        // Fail on the second write so one icon is already on disk when the loop
        // aborts — the failure message must name the partial progress.
        let writer = FakeImageWorkflowWriter(error: ImageSessionTestError.writeFailed, failAfter: 1)
        let client = ImageWorkflowClient(
            dialog: dialog,
            reader: FakeImageWorkflowReader(),
            writer: writer
        )

        let icons = [
            GeneratedIcon(size: 16, data: Data([1, 6]), pixelWidth: 16, pixelHeight: 16, format: .png),
            GeneratedIcon(size: 32, data: Data([1, 3, 2]), pixelWidth: 32, pixelHeight: 32, format: .png)
        ]

        await #expect {
            try await client.saveIcons(icons) { icon in
                "favicon-\(icon.pixelWidth)x\(icon.pixelHeight).png"
            }
        } throws: { error in
            guard case ImageWorkflowFailure.partialSaveFailed(savedCount: 1, totalCount: 2) = error else {
                return false
            }
            return true
        }
        #expect(writer.writes.count == 1)
    }

    @Test func saveIconWritesSingleFaviconPNG() async throws {
        let saveURL = URL(fileURLWithPath: "/tmp/favicon-16x16.png")
        let dialog = FakeImageWorkflowDialog(saveURL: saveURL)
        let writer = FakeImageWorkflowWriter()
        let client = ImageWorkflowClient(dialog: dialog, reader: FakeImageWorkflowReader(), writer: writer)
        let icon = GeneratedIcon(size: 16, data: Data([1, 6]), pixelWidth: 16, pixelHeight: 16, format: .png)

        let didSave = try await client.saveIcon(icon, defaultFilename: "favicon-16x16.png")

        #expect(didSave)
        #expect(dialog.requestedSaveNames == ["favicon-16x16.png"])
        #expect(writer.writes.map(\.url) == [saveURL])
        #expect(writer.writes.map(\.data) == [icon.data])
    }

    @Test func processedOutputSessionReceivesImageURLAndRendersInBackground() async throws {
        let sourceData = try Self.makeImageData(width: 12, height: 8, format: .png)
        let outputData = try Self.makeImageData(width: 10, height: 6, format: .png)
        let url = URL(fileURLWithPath: "/tmp/source.png")
        let client = ImageWorkflowClient(
            dialog: FakeImageWorkflowDialog(),
            reader: FakeImageWorkflowReader(dataByURL: [url: sourceData]),
            writer: FakeImageWorkflowWriter()
        )
        let session = ImageProcessedOutputSession()
        let expected = Self.processedImage(data: outputData, originalByteCount: sourceData.count, format: .png)
        var selectionCount = 0

        session.receiveImageURL(
            url,
            allowedContentTypes: [.png],
            client: client,
            operation: .conversion,
            onSelection: { selection in
                selectionCount += 1
                #expect(selection.url == url)
            }
        ) { input in
            #expect(input.metadata.format == .png)
            return expected
        }
        try await Self.waitForOutput(in: session, matching: expected)

        #expect(selectionCount == 1)
        #expect(session.sourceURL == url)
        #expect(session.sourceMetadata?.format == .png)
        #expect(session.sourceImage?.size.width ?? 0 > 0)
        #expect(session.output == expected)
        #expect(session.outputImage?.size.width ?? 0 > 0)
        #expect(session.error == nil)
    }

    @Test func processedOutputSessionBuildsRendererAfterSelectionPreparation() async throws {
        let sourceData = try Self.makeImageData(width: 12, height: 8, format: .png)
        let staleData = try Self.makeImageData(width: 9, height: 6, format: .png)
        let latestData = try Self.makeImageData(width: 8, height: 5, format: .png)
        let url = URL(fileURLWithPath: "/tmp/slow-watermark-source.png")
        let client = ImageWorkflowClient(
            dialog: FakeImageWorkflowDialog(),
            reader: FakeImageWorkflowReader(
                dataByURL: [url: sourceData],
                readDelayByURL: [url: 0.05]
            ),
            writer: FakeImageWorkflowWriter()
        )
        let session = ImageProcessedOutputSession()
        let stale = Self.processedImage(data: staleData, originalByteCount: sourceData.count, format: .png)
        let latest = Self.processedImage(data: latestData, originalByteCount: sourceData.count, format: .png)
        let rendererSelection = ImageRendererSelectionState()

        session.receiveImageURL(
            url,
            allowedContentTypes: [.png],
            client: client,
            operation: .watermark,
            renderProvider: {
                let output = rendererSelection.usesLatest ? latest : stale
                return { _ in output }
            },
            render: { _ in stale }
        )
        rendererSelection.usesLatest = true
        try await Self.waitForOutput(in: session, matching: latest)

        #expect(session.output == latest)
        #expect(session.output != stale)
    }

    @Test func processedOutputSessionSelectionCancelDoesNotRenderOrRunSelectionHook() async throws {
        let client = ImageWorkflowClient(
            dialog: FakeImageWorkflowDialog(),
            reader: FakeImageWorkflowReader(),
            writer: FakeImageWorkflowWriter()
        )
        let session = ImageProcessedOutputSession()
        var panelWasRequested = false
        var didRunSelectionHook = false
        let unexpectedOutput = Self.processedImage(byteCount: 8, originalByteCount: 10, format: .png)
        let cancelledPanel = FileInputPanelClient { _ in
            panelWasRequested = true
            return nil
        }

        session.selectImage(
            filePanel: cancelledPanel,
            allowedContentTypes: [.png],
            client: client,
            operation: .conversion,
            onSelection: { _ in didRunSelectionHook = true }
        ) { _ in
            unexpectedOutput
        }
        try await Self.waitUntil { panelWasRequested }
        await Task.yield()

        #expect(didRunSelectionHook == false)
        #expect(session.source == nil)
        #expect(session.output == nil)
        #expect(session.error == nil)
    }

    @Test func processedOutputSessionRefreshReplacesOutputAndClearsStaleError() async throws {
        let sourceData = try Self.makeImageData(width: 12, height: 8, format: .png)
        let firstData = try Self.makeImageData(width: 9, height: 6, format: .png)
        let secondData = try Self.makeImageData(width: 8, height: 5, format: .png)
        let url = URL(fileURLWithPath: "/tmp/source.png")
        let client = ImageWorkflowClient(
            dialog: FakeImageWorkflowDialog(),
            reader: FakeImageWorkflowReader(dataByURL: [url: sourceData]),
            writer: FakeImageWorkflowWriter()
        )
        let session = ImageProcessedOutputSession()
        let first = Self.processedImage(data: firstData, originalByteCount: sourceData.count, format: .png)
        let second = Self.processedImage(data: secondData, originalByteCount: sourceData.count, format: .png)

        session.receiveImageURL(
            url,
            allowedContentTypes: [.png],
            client: client,
            operation: .conversion,
            render: { _ in first }
        )
        try await Self.waitForOutput(in: session, matching: first)
        session.render(operation: .conversion) { _ in throw ImageSessionTestError.renderFailed }
        #expect(session.output == nil)
        #expect(session.outputImage == nil)
        #expect(session.error == "图片格式转换失败。")

        session.render(operation: .conversion) { _ in second }
        #expect(session.output == second)
        #expect(session.outputImage?.size.width ?? 0 > 0)
        #expect(session.error == nil)
    }

    @Test @MainActor func processedOutputSessionRendersInBackgroundAndBlocksSaveWhileProcessing() async throws {
        let sourceData = try Self.makeImageData(width: 12, height: 8, format: .png)
        let outputData = try Self.makeImageData(width: 10, height: 6, format: .png)
        let sourceURL = URL(fileURLWithPath: "/tmp/source.png")
        let saveURL = URL(fileURLWithPath: "/tmp/output.png")
        let dialog = FakeImageWorkflowDialog(saveURL: saveURL)
        let writer = FakeImageWorkflowWriter()
        let client = ImageWorkflowClient(
            dialog: dialog,
            reader: FakeImageWorkflowReader(dataByURL: [sourceURL: sourceData]),
            writer: writer
        )
        let session = ImageProcessedOutputSession()
        let expected = Self.processedImage(data: outputData, originalByteCount: sourceData.count, format: .png)

        session.receiveImageURL(
            sourceURL,
            allowedContentTypes: [.png],
            client: client,
            operation: .conversion
        ) { _ in
            Thread.sleep(forTimeInterval: 0.05)
            return expected
        }

        try await Self.waitUntil { session.isProcessing }
        let outputBox = FakeOutputPanelBox()
        #expect(await session.save(
            workflow: .conversion,
            defaultBasename: "output",
            filePanel: .unavailable,
            outputPanel: makeOutputPanelClient(outputBox)
        ) == .cancelled)
        #expect(outputBox.requestedNames.isEmpty)

        try await Self.waitForOutput(in: session)

        #expect(session.isProcessing == false)
        #expect(session.output == expected)
        #expect(session.outputImage?.size.width ?? 0 > 0)
        #expect(session.error == nil)
    }

    @Test @MainActor func processedOutputSessionUsesDirectURLPipelineAndPreservesResultOnPanelCancel() async throws {
        let sourceData = try Self.makeImageData(width: 12, height: 8, format: .png)
        let sourceURL = URL(fileURLWithPath: "/tmp/source.png")
        let client = ImageWorkflowClient(
            dialog: FakeImageWorkflowDialog(),
            reader: FakeImageWorkflowReader(dataByURL: [sourceURL: sourceData]),
            writer: FakeImageWorkflowWriter()
        )
        let output = Self.processedImage(byteCount: 8, originalByteCount: sourceData.count, format: .png)
        let session = ImageProcessedOutputSession()

        session.receiveImageURL(
            sourceURL,
            allowedContentTypes: [.png],
            client: client,
            operation: .conversion,
            render: { _ in output }
        )
        try await Self.waitForOutput(in: session, matching: output)

        var panelWasRequested = false
        let cancelledPanel = FileInputPanelClient { request in
            panelWasRequested = true
            #expect(request.allowedContentTypes == [.png])
            return nil
        }
        session.selectImage(
            filePanel: cancelledPanel,
            allowedContentTypes: [.png],
            client: client,
            operation: .conversion,
            render: { _ in output }
        )
        try await Self.waitUntil { panelWasRequested }
        await Task.yield()

        #expect(session.sourceURL == sourceURL)
        #expect(session.output == output)
        #expect(session.error == nil)
        #expect(session.isProcessing == false)
    }

    @Test @MainActor func processedOutputSessionPanelFailurePreservesResultAndUsesStableDiagnostic() async throws {
        let sourceData = try Self.makeImageData(width: 12, height: 8, format: .png)
        let sourceURL = URL(fileURLWithPath: "/tmp/source.png")
        let client = ImageWorkflowClient(
            dialog: FakeImageWorkflowDialog(),
            reader: FakeImageWorkflowReader(dataByURL: [sourceURL: sourceData]),
            writer: FakeImageWorkflowWriter()
        )
        let output = Self.processedImage(byteCount: 8, originalByteCount: sourceData.count, format: .png)
        let session = ImageProcessedOutputSession()
        session.receiveImageURL(
            sourceURL,
            allowedContentTypes: [.png],
            client: client,
            operation: .conversion,
            render: { _ in output }
        )
        try await Self.waitForOutput(in: session, matching: output)

        let unavailablePanel = FileInputPanelClient { _ in
            throw FileInputPanelFailure.windowUnavailable
        }
        session.selectImage(
            filePanel: unavailablePanel,
            allowedContentTypes: [.png],
            client: client,
            operation: .conversion,
            render: { _ in output }
        )
        try await Self.waitUntil { session.error != nil }

        #expect(session.sourceURL == sourceURL)
        #expect(session.output == output)
        #expect(session.error == "暂时无法打开文件选择器。")
    }

    @Test @MainActor func processedOutputSessionKeepsCurrentRenderAliveWhilePanelIsOpen() async throws {
        let sourceData = try Self.makeImageData(width: 12, height: 8, format: .png)
        let sourceURL = URL(fileURLWithPath: "/tmp/source.png")
        let client = ImageWorkflowClient(
            dialog: FakeImageWorkflowDialog(),
            reader: FakeImageWorkflowReader(dataByURL: [sourceURL: sourceData]),
            writer: FakeImageWorkflowWriter()
        )
        let output = Self.processedImage(byteCount: 8, originalByteCount: sourceData.count, format: .png)
        let session = ImageProcessedOutputSession()
        session.receiveImageURL(
            sourceURL,
            allowedContentTypes: [.png],
            client: client,
            operation: .conversion
        ) { _ in
            Thread.sleep(forTimeInterval: 0.08)
            return output
        }
        try await Self.waitUntil { session.sourceURL == sourceURL && session.isProcessing }

        var panelContinuation: CheckedContinuation<URL?, Never>?
        let pendingPanel = FileInputPanelClient { _ in
            await withCheckedContinuation { continuation in
                panelContinuation = continuation
            }
        }
        session.selectImage(
            filePanel: pendingPanel,
            allowedContentTypes: [.png],
            client: client,
            operation: .conversion,
            render: { _ in output }
        )
        try await Self.waitUntil { panelContinuation != nil }

        try await Self.waitForOutput(in: session, matching: output)
        #expect(session.sourceURL == sourceURL)
        #expect(session.error == nil)

        panelContinuation?.resume(returning: nil)
        panelContinuation = nil
        await Task.yield()

        #expect(session.output == output)
        #expect(session.isProcessing == false)
    }

    @Test @MainActor func processedOutputSessionIgnoresPanelCompletionAfterDirectURLInput() async throws {
        let firstData = try Self.makeImageData(width: 12, height: 8, format: .png)
        let secondData = try Self.makeImageData(width: 10, height: 6, format: .png)
        let firstURL = URL(fileURLWithPath: "/tmp/panel-source.png")
        let secondURL = URL(fileURLWithPath: "/tmp/dropped-source.png")
        let client = ImageWorkflowClient(
            dialog: FakeImageWorkflowDialog(),
            reader: FakeImageWorkflowReader(dataByURL: [
                firstURL: firstData,
                secondURL: secondData
            ]),
            writer: FakeImageWorkflowWriter()
        )
        let firstOutput = Self.processedImage(byteCount: 7, originalByteCount: firstData.count, format: .png)
        let secondOutput = Self.processedImage(byteCount: 6, originalByteCount: secondData.count, format: .png)
        let session = ImageProcessedOutputSession()
        var panelContinuation: CheckedContinuation<URL?, Never>?
        let pendingPanel = FileInputPanelClient { _ in
            await withCheckedContinuation { continuation in
                panelContinuation = continuation
            }
        }

        session.selectImage(
            filePanel: pendingPanel,
            allowedContentTypes: [.png],
            client: client,
            operation: .conversion,
            render: { _ in firstOutput }
        )
        try await Self.waitUntil { panelContinuation != nil }

        session.receiveImageURL(
            secondURL,
            allowedContentTypes: [.png],
            client: client,
            operation: .conversion,
            render: { _ in secondOutput }
        )
        try await Self.waitForOutput(in: session, matching: secondOutput)

        panelContinuation?.resume(returning: firstURL)
        panelContinuation = nil
        try await Task.sleep(nanoseconds: 30_000_000)

        #expect(session.sourceURL == secondURL)
        #expect(session.output == secondOutput)
        #expect(session.output != firstOutput)
        #expect(session.error == nil)
    }

    @Test @MainActor func processedOutputSessionIgnoresSlowerSelectionPreparation() async throws {
        let firstData = try Self.makeImageData(width: 12, height: 8, format: .png)
        let secondData = try Self.makeImageData(width: 10, height: 6, format: .png)
        let firstURL = URL(fileURLWithPath: "/tmp/slow-source.png")
        let secondURL = URL(fileURLWithPath: "/tmp/current-source.png")
        let reader = FakeImageWorkflowReader(
            dataByURL: [firstURL: firstData, secondURL: secondData],
            readDelayByURL: [firstURL: 0.08]
        )
        let client = ImageWorkflowClient(
            dialog: FakeImageWorkflowDialog(),
            reader: reader,
            writer: FakeImageWorkflowWriter()
        )
        let firstOutput = Self.processedImage(byteCount: 7, originalByteCount: firstData.count, format: .png)
        let secondOutput = Self.processedImage(byteCount: 6, originalByteCount: secondData.count, format: .png)
        let session = ImageProcessedOutputSession()

        session.receiveImageURL(
            firstURL,
            allowedContentTypes: [.png],
            client: client,
            operation: .conversion,
            render: { _ in firstOutput }
        )
        try await Self.waitUntil { reader.readURLs.contains(firstURL) }

        session.receiveImageURL(
            secondURL,
            allowedContentTypes: [.png],
            client: client,
            operation: .conversion,
            render: { _ in secondOutput }
        )
        try await Self.waitForOutput(in: session, matching: secondOutput)
        try await Task.sleep(nanoseconds: 120_000_000)

        #expect(session.sourceURL == secondURL)
        #expect(session.output == secondOutput)
        #expect(session.output != firstOutput)
        #expect(session.isProcessing == false)
        #expect(session.error == nil)
    }

    @Test @MainActor func processedOutputSessionRejectsNewInputWithoutKeepingOldResult() async throws {
        let sourceData = try Self.makeImageData(width: 12, height: 8, format: .png)
        let sourceURL = URL(fileURLWithPath: "/tmp/source.png")
        let client = ImageWorkflowClient(
            dialog: FakeImageWorkflowDialog(),
            reader: FakeImageWorkflowReader(dataByURL: [sourceURL: sourceData]),
            writer: FakeImageWorkflowWriter()
        )
        let output = Self.processedImage(byteCount: 8, originalByteCount: sourceData.count, format: .png)
        let session = ImageProcessedOutputSession()
        session.receiveImageURL(
            sourceURL,
            allowedContentTypes: [.png],
            client: client,
            operation: .conversion,
            render: { _ in output }
        )
        try await Self.waitForOutput(in: session, matching: output)

        session.rejectImageInput(SingleFileDropResolver.multipleFilesDiagnostic)

        #expect(session.source == nil)
        #expect(session.output == nil)
        #expect(session.outputImage == nil)
        #expect(session.error == "一次只能拖入一个文件。")
        #expect(session.isProcessing == false)
    }

    @Test @MainActor func processedOutputSessionInvalidNewURLClearsOldResult() async throws {
        let validData = try Self.makeImageData(width: 12, height: 8, format: .png)
        let validURL = URL(fileURLWithPath: "/tmp/valid.png")
        let invalidURL = URL(fileURLWithPath: "/tmp/invalid.png")
        let client = ImageWorkflowClient(
            dialog: FakeImageWorkflowDialog(),
            reader: FakeImageWorkflowReader(dataByURL: [
                validURL: validData,
                invalidURL: Data("not an image".utf8)
            ]),
            writer: FakeImageWorkflowWriter()
        )
        let output = Self.processedImage(byteCount: 8, originalByteCount: validData.count, format: .png)
        let session = ImageProcessedOutputSession()
        session.receiveImageURL(
            validURL,
            allowedContentTypes: [.png],
            client: client,
            operation: .conversion,
            render: { _ in output }
        )
        try await Self.waitForOutput(in: session, matching: output)

        session.receiveImageURL(
            invalidURL,
            allowedContentTypes: [.png],
            client: client,
            operation: .conversion,
            render: { _ in output }
        )
        try await Self.waitUntil { session.error != nil }

        #expect(session.source == nil)
        #expect(session.output == nil)
        #expect(session.outputImage == nil)
        #expect(session.error == "无法读取图片的尺寸信息。")
        #expect(session.isProcessing == false)
    }

    @Test @MainActor func processedOutputSessionReportsMissingConversionTargetWithoutRendering() async throws {
        let sourceData = try Self.makeImageData(width: 12, height: 8, format: .png)
        let sourceURL = URL(fileURLWithPath: "/tmp/source.png")
        let client = ImageWorkflowClient(
            dialog: FakeImageWorkflowDialog(),
            reader: FakeImageWorkflowReader(dataByURL: [sourceURL: sourceData]),
            writer: FakeImageWorkflowWriter()
        )
        let session = ImageProcessedOutputSession()

        session.receiveImageURL(
            sourceURL,
            allowedContentTypes: [.png],
            client: client,
            operation: .conversion,
            shouldRender: { _ in false },
            skippedRenderFailure: .noConversionTarget
        ) { _ in
            fatalError("render must not run without a conversion target")
        }

        try await Self.waitUntil { session.error != nil }

        #expect(session.sourceURL == sourceURL)
        #expect(session.output == nil)
        #expect(session.isProcessing == false)
        #expect(session.error == "当前图片格式没有可用的转换目标。")
    }

    @Test @MainActor func processedOutputSessionDoesNotShowProcessingDuringImageSelectionPanel() async throws {
        let session = ImageProcessedOutputSession()
        var observedProcessingDuringSelection: Bool?
        let panel = FileInputPanelClient { _ in
            observedProcessingDuringSelection = session.isProcessing
            return nil
        }
        let client = ImageWorkflowClient(
            dialog: FakeImageWorkflowDialog(),
            reader: FakeImageWorkflowReader(),
            writer: FakeImageWorkflowWriter()
        )
        let unusedOutput = Self.processedImage(byteCount: 8, originalByteCount: 10, format: .png)

        session.selectImage(
            filePanel: panel,
            allowedContentTypes: [.png],
            client: client,
            operation: .conversion
        ) { _ in
            unusedOutput
        }

        try await Self.waitUntil { observedProcessingDuringSelection != nil }

        #expect(observedProcessingDuringSelection == false)
        #expect(session.isProcessing == false)
        #expect(session.source == nil)
        #expect(session.output == nil)
        #expect(session.error == nil)
    }

    @Test @MainActor func processedOutputSessionIgnoresStaleBackgroundRenderResults() async throws {
        let sourceData = try Self.makeImageData(width: 12, height: 8, format: .png)
        let firstData = try Self.makeImageData(width: 10, height: 6, format: .png)
        let secondData = try Self.makeImageData(width: 9, height: 5, format: .png)
        let sourceURL = URL(fileURLWithPath: "/tmp/source.png")
        let client = ImageWorkflowClient(
            dialog: FakeImageWorkflowDialog(),
            reader: FakeImageWorkflowReader(dataByURL: [sourceURL: sourceData]),
            writer: FakeImageWorkflowWriter()
        )
        let session = ImageProcessedOutputSession()
        let first = Self.processedImage(data: firstData, originalByteCount: sourceData.count, format: .png)
        let second = Self.processedImage(data: secondData, originalByteCount: sourceData.count, format: .png)

        let initial = Self.processedImage(byteCount: 8, originalByteCount: sourceData.count, format: .png)
        session.receiveImageURL(
            sourceURL,
            allowedContentTypes: [.png],
            client: client,
            operation: .conversion,
            render: { _ in initial }
        )
        try await Self.waitForOutput(in: session, matching: initial)
        session.renderInBackground(operation: .conversion) { _ in
            Thread.sleep(forTimeInterval: 0.08)
            return first
        }
        session.renderInBackground(operation: .conversion) { _ in
            second
        }

        try await Self.waitForOutput(in: session, matching: second)
        try await Task.sleep(nanoseconds: 120_000_000)

        #expect(session.output == second)
        #expect(session.isProcessing == false)
        #expect(session.error == nil)
    }

    @Test @MainActor func processedOutputSessionResetClearsCompletedWorkflowState() async throws {
        let sourceData = try Self.makeImageData(width: 12, height: 8, format: .png)
        let outputData = try Self.makeImageData(width: 10, height: 6, format: .png)
        let sourceURL = URL(fileURLWithPath: "/tmp/reset-source.png")
        let client = ImageWorkflowClient(
            dialog: FakeImageWorkflowDialog(),
            reader: FakeImageWorkflowReader(dataByURL: [sourceURL: sourceData]),
            writer: FakeImageWorkflowWriter()
        )
        let output = Self.processedImage(
            data: outputData,
            originalByteCount: sourceData.count,
            format: .png
        )
        let session = ImageProcessedOutputSession()

        session.receiveImageURL(
            sourceURL,
            allowedContentTypes: [.png],
            client: client,
            operation: .conversion,
            render: { _ in output }
        )
        try await Self.waitForOutput(in: session, matching: output)

        session.reset()

        #expect(session.source == nil)
        #expect(session.output == nil)
        #expect(session.outputImage == nil)
        #expect(session.error == nil)
        #expect(session.isProcessing == false)
    }

    @Test @MainActor func processedOutputSessionResetInvalidatesPendingSelectionAndRender() async throws {
        let sourceData = try Self.makeImageData(width: 12, height: 8, format: .png)
        let initialData = try Self.makeImageData(width: 10, height: 6, format: .png)
        let lateData = try Self.makeImageData(width: 9, height: 5, format: .png)
        let sourceURL = URL(fileURLWithPath: "/tmp/reset-pending-source.png")
        let delayedURL = URL(fileURLWithPath: "/tmp/reset-delayed-source.png")
        let reader = FakeImageWorkflowReader(
            dataByURL: [sourceURL: sourceData, delayedURL: sourceData],
            readDelayByURL: [delayedURL: 0.08]
        )
        let client = ImageWorkflowClient(
            dialog: FakeImageWorkflowDialog(),
            reader: reader,
            writer: FakeImageWorkflowWriter()
        )
        let initial = Self.processedImage(
            data: initialData,
            originalByteCount: sourceData.count,
            format: .png
        )
        let late = Self.processedImage(
            data: lateData,
            originalByteCount: sourceData.count,
            format: .png
        )
        let session = ImageProcessedOutputSession()

        session.receiveImageURL(
            sourceURL,
            allowedContentTypes: [.png],
            client: client,
            operation: .conversion,
            render: { _ in initial }
        )
        try await Self.waitForOutput(in: session, matching: initial)

        session.renderInBackground(operation: .conversion) { _ in
            Thread.sleep(forTimeInterval: 0.08)
            return late
        }
        try await Self.waitUntil { session.isProcessing }
        session.reset()
        try await Task.sleep(nanoseconds: 120_000_000)

        #expect(session.source == nil)
        #expect(session.output == nil)
        #expect(session.outputImage == nil)
        #expect(session.error == nil)
        #expect(session.isProcessing == false)

        session.receiveImageURL(
            delayedURL,
            allowedContentTypes: [.png],
            client: client,
            operation: .conversion,
            render: { _ in late }
        )
        try await Self.waitUntil { reader.readURLs.contains(delayedURL) }
        session.reset()
        try await Task.sleep(nanoseconds: 120_000_000)

        #expect(session.source == nil)
        #expect(session.output == nil)
        #expect(session.outputImage == nil)
        #expect(session.error == nil)
        #expect(session.isProcessing == false)
    }

    @Test @MainActor func processedOutputSessionResetInvalidatesPendingPanelCompletion() async throws {
        let sourceData = try Self.makeImageData(width: 12, height: 8, format: .png)
        let sourceURL = URL(fileURLWithPath: "/tmp/reset-panel-source.png")
        let client = ImageWorkflowClient(
            dialog: FakeImageWorkflowDialog(),
            reader: FakeImageWorkflowReader(dataByURL: [sourceURL: sourceData]),
            writer: FakeImageWorkflowWriter()
        )
        let session = ImageProcessedOutputSession()
        var panelWasRequested = false
        let delayedPanel = FileInputPanelClient { _ in
            panelWasRequested = true
            try? await Task.sleep(nanoseconds: 80_000_000)
            return sourceURL
        }

        session.selectImage(
            filePanel: delayedPanel,
            allowedContentTypes: [.png],
            client: client,
            operation: .conversion,
            render: { input in
                ProcessedImage(
                    data: input.data,
                    format: .png,
                    pixelWidth: input.metadata.pixelWidth,
                    pixelHeight: input.metadata.pixelHeight,
                    originalByteCount: input.data.count,
                    quality: nil,
                    wasResized: false
                )
            }
        )
        try await Self.waitUntil { panelWasRequested }
        session.reset()
        try await Task.sleep(nanoseconds: 120_000_000)

        #expect(session.source == nil)
        #expect(session.output == nil)
        #expect(session.outputImage == nil)
        #expect(session.error == nil)
        #expect(session.isProcessing == false)
    }

    @Test func processedOutputSessionBlocksLargerCompressionBeforeSavePanel() async throws {
        let sourceData = try Self.makeImageData(width: 12, height: 8, format: .png)
        let sourceURL = URL(fileURLWithPath: "/tmp/source.png")
        let output = Self.processedImage(byteCount: 20, originalByteCount: 10, format: .jpeg)
        let client = ImageWorkflowClient(
            dialog: FakeImageWorkflowDialog(),
            reader: FakeImageWorkflowReader(dataByURL: [sourceURL: sourceData]),
            writer: FakeImageWorkflowWriter()
        )
        let session = ImageProcessedOutputSession()

        session.receiveImageURL(
            sourceURL,
            allowedContentTypes: [.png],
            client: client,
            operation: .compression,
            render: { _ in output }
        )
        try await Self.waitForOutput(in: session, matching: output)
        let outputBox = FakeOutputPanelBox()
        let outcome = await session.save(
            workflow: .compression,
            defaultBasename: "compressed",
            filePanel: .unavailable,
            outputPanel: makeOutputPanelClient(outputBox)
        )

        // A blocked compression save is a persistent state the user resolves by
        // changing parameters, so it stays in the inline workspace diagnostic.
        #expect(outcome == .blocked)
        #expect(session.error == "当前压缩结果不小于原图，不能作为压缩结果保存。")
        #expect(outputBox.requestedNames.isEmpty)
    }

    @Test func processedOutputSessionAllowsLargerNonCompressionSaves() async throws {
        for workflow in [ImageOutputWorkflow.conversion, .watermark, .grayscale] {
            let sourceData = try Self.makeImageData(width: 12, height: 8, format: .png)
            let sourceURL = URL(fileURLWithPath: "/tmp/source-\(workflow).png")
            let saveURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("xtools-output-\(workflow)-\(UUID().uuidString).png")
            let output = Self.processedImage(byteCount: 20, originalByteCount: 10, format: .png)
            let client = ImageWorkflowClient(
                dialog: FakeImageWorkflowDialog(),
                reader: FakeImageWorkflowReader(dataByURL: [sourceURL: sourceData]),
                writer: FakeImageWorkflowWriter()
            )
            let session = ImageProcessedOutputSession()

            session.receiveImageURL(
                sourceURL,
                allowedContentTypes: [.png],
                client: client,
                operation: .conversion,
                render: { _ in output }
            )
            try await Self.waitForOutput(in: session, matching: output)
            let assessment = try #require(session.assessment(for: workflow))
            #expect(assessment.requiresExplicitLargerSave)

            let outputBox = FakeOutputPanelBox()
            outputBox.url = saveURL
            let outcome = await session.save(
                workflow: workflow,
                defaultBasename: "output",
                filePanel: .unavailable,
                outputPanel: makeOutputPanelClient(outputBox)
            )

            #expect(outcome == .saved)
            #expect(session.error == nil)
            #expect(outputBox.requestedNames == ["output.png"])
            // Session saves use the real Foundation writer; assert through the
            // file that actually landed at the panel-provided URL.
            #expect(FileManager.default.contents(atPath: saveURL.path) == output.data)
        }
    }

    @Test func processedOutputSessionSaveCancelDoesNotSetError() async throws {
        let sourceData = try Self.makeImageData(width: 12, height: 8, format: .png)
        let sourceURL = URL(fileURLWithPath: "/tmp/source.png")
        let output = Self.processedImage(byteCount: 8, originalByteCount: 10, format: .png)
        let client = ImageWorkflowClient(
            dialog: FakeImageWorkflowDialog(saveURL: nil),
            reader: FakeImageWorkflowReader(dataByURL: [sourceURL: sourceData]),
            writer: FakeImageWorkflowWriter()
        )
        let session = ImageProcessedOutputSession()

        session.receiveImageURL(
            sourceURL,
            allowedContentTypes: [.png],
            client: client,
            operation: .conversion,
            render: { _ in output }
        )
        try await Self.waitForOutput(in: session, matching: output)
        let outputBox = FakeOutputPanelBox()
        let outcome = await session.save(
            workflow: .conversion,
            defaultBasename: "output",
            filePanel: .unavailable,
            outputPanel: makeOutputPanelClient(outputBox)
        )

        #expect(outcome == .cancelled)
        #expect(session.error == nil)
    }

    @Test func processedOutputSessionSaveFailureReportsThenSuccessClearsError() async throws {
        let sourceData = try Self.makeImageData(width: 12, height: 8, format: .png)
        let sourceURL = URL(fileURLWithPath: "/tmp/source.png")
        let output = Self.processedImage(byteCount: 8, originalByteCount: 10, format: .png)
        let client = ImageWorkflowClient(
            dialog: FakeImageWorkflowDialog(),
            reader: FakeImageWorkflowReader(dataByURL: [sourceURL: sourceData]),
            writer: FakeImageWorkflowWriter()
        )
        let session = ImageProcessedOutputSession()

        session.receiveImageURL(
            sourceURL,
            allowedContentTypes: [.png],
            client: client,
            operation: .conversion,
            render: { _ in output }
        )
        try await Self.waitForOutput(in: session, matching: output)
        let outputBox = FakeOutputPanelBox()
        // A path inside a missing directory makes the real Foundation writer
        // fail — the session must treat it as a transient `.failed` action
        // result (toast) and not linger in the inline workspace diagnostic.
        outputBox.url = FileManager.default.temporaryDirectory
            .appendingPathComponent("xtools-missing-dir/failed-output.png")
        #expect(await session.save(
            workflow: .conversion,
            defaultBasename: "output",
            filePanel: .unavailable,
            outputPanel: makeOutputPanelClient(outputBox)
        ) == .failed("图片文件保存失败。"))
        #expect(session.error == nil)

        let saveURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("xtools-output-retry-\(UUID().uuidString).png")
        outputBox.url = saveURL
        #expect(await session.save(
            workflow: .conversion,
            defaultBasename: "output",
            filePanel: .unavailable,
            outputPanel: makeOutputPanelClient(outputBox)
        ) == .saved)
        #expect(session.error == nil)
        #expect(FileManager.default.contents(atPath: saveURL.path) == output.data)
    }

    @Test @MainActor func faviconOutputSetSessionSelectionCancelDoesNotGenerate() async throws {
        let client = ImageWorkflowClient(
            dialog: FakeImageWorkflowDialog(),
            reader: FakeImageWorkflowReader(),
            writer: FakeImageWorkflowWriter()
        )
        let session = FaviconOutputSetSession(outputSpecs: [FaviconOutputSpec(size: 16)])
        var panelWasRequested = false
        let cancelledPanel = FileInputPanelClient { _ in
            panelWasRequested = true
            return nil
        }

        session.selectImage(filePanel: cancelledPanel, client: client) { _, _ in
            throw ImageSessionTestError.renderFailed
        }

        try await Self.waitUntil { panelWasRequested }
        await Task.yield()

        #expect(session.source == nil)
        #expect(session.icons.isEmpty)
        #expect(session.error == nil)
    }

    @Test @MainActor func faviconOutputSetSessionUsesDirectURLAndPreservesIconsOnPanelCancel() async throws {
        let sourceData = try Self.makeImageData(width: 12, height: 8, format: .png)
        let sourceURL = URL(fileURLWithPath: "/tmp/source.png")
        let client = ImageWorkflowClient(
            dialog: FakeImageWorkflowDialog(),
            reader: FakeImageWorkflowReader(dataByURL: [sourceURL: sourceData]),
            writer: FakeImageWorkflowWriter()
        )
        let icons = [
            GeneratedIcon(size: 16, data: Data([1, 6]), pixelWidth: 16, pixelHeight: 16, format: .png)
        ]
        let session = FaviconOutputSetSession(outputSpecs: [FaviconOutputSpec(size: 16)])
        session.receiveImageURL(sourceURL, client: client) { _, _ in icons }
        try await Self.waitForIcons(in: session, matching: icons)

        var panelWasRequested = false
        let cancelledPanel = FileInputPanelClient { request in
            panelWasRequested = true
            #expect(request.allowedContentTypes == ImageWorkflowClient.faviconInputContentTypes)
            return nil
        }
        session.selectImage(filePanel: cancelledPanel, client: client) { _, _ in icons }
        try await Self.waitUntil { panelWasRequested }
        await Task.yield()

        #expect(session.sourceURL == sourceURL)
        #expect(session.icons == icons)
        #expect(session.error == nil)
        #expect(session.isProcessing == false)
    }

    @Test @MainActor func faviconOutputSetSessionPanelFailurePreservesIcons() async throws {
        let sourceData = try Self.makeImageData(width: 12, height: 8, format: .png)
        let sourceURL = URL(fileURLWithPath: "/tmp/source.png")
        let client = ImageWorkflowClient(
            dialog: FakeImageWorkflowDialog(),
            reader: FakeImageWorkflowReader(dataByURL: [sourceURL: sourceData]),
            writer: FakeImageWorkflowWriter()
        )
        let icons = [
            GeneratedIcon(size: 16, data: Data([1, 6]), pixelWidth: 16, pixelHeight: 16, format: .png)
        ]
        let session = FaviconOutputSetSession(outputSpecs: [FaviconOutputSpec(size: 16)])
        session.receiveImageURL(sourceURL, client: client) { _, _ in icons }
        try await Self.waitForIcons(in: session, matching: icons)

        let unavailablePanel = FileInputPanelClient { _ in
            throw FileInputPanelFailure.windowUnavailable
        }
        session.selectImage(filePanel: unavailablePanel, client: client) { _, _ in icons }
        try await Self.waitUntil { session.error != nil }

        #expect(session.sourceURL == sourceURL)
        #expect(session.icons == icons)
        #expect(session.error == "暂时无法打开文件选择器。")
        #expect(session.isProcessing == false)
    }

    @Test @MainActor func faviconOutputSetSessionRejectsMultipleFilesWithoutKeepingOldIcons() async throws {
        let sourceData = try Self.makeImageData(width: 12, height: 8, format: .png)
        let sourceURL = URL(fileURLWithPath: "/tmp/source.png")
        let client = ImageWorkflowClient(
            dialog: FakeImageWorkflowDialog(),
            reader: FakeImageWorkflowReader(dataByURL: [sourceURL: sourceData]),
            writer: FakeImageWorkflowWriter()
        )
        let icons = [
            GeneratedIcon(size: 16, data: Data([1, 6]), pixelWidth: 16, pixelHeight: 16, format: .png)
        ]
        let session = FaviconOutputSetSession(outputSpecs: [FaviconOutputSpec(size: 16)])
        session.receiveImageURL(sourceURL, client: client) { _, _ in icons }
        try await Self.waitForIcons(in: session, matching: icons)

        session.rejectImageInput(SingleFileDropResolver.multipleFilesDiagnostic)

        #expect(session.source == nil)
        #expect(session.icons.isEmpty)
        #expect(session.error == "一次只能拖入一个文件。")
        #expect(session.isProcessing == false)
    }

    @Test @MainActor func faviconOutputSetSessionInvalidNewURLClearsOldIcons() async throws {
        let validData = try Self.makeImageData(width: 12, height: 8, format: .png)
        let validURL = URL(fileURLWithPath: "/tmp/valid.png")
        let invalidURL = URL(fileURLWithPath: "/tmp/invalid.png")
        let client = ImageWorkflowClient(
            dialog: FakeImageWorkflowDialog(),
            reader: FakeImageWorkflowReader(dataByURL: [
                validURL: validData,
                invalidURL: Data("not an image".utf8)
            ]),
            writer: FakeImageWorkflowWriter()
        )
        let icons = [
            GeneratedIcon(size: 16, data: Data([1, 6]), pixelWidth: 16, pixelHeight: 16, format: .png)
        ]
        let session = FaviconOutputSetSession(outputSpecs: [FaviconOutputSpec(size: 16)])
        session.receiveImageURL(validURL, client: client) { _, _ in icons }
        try await Self.waitForIcons(in: session, matching: icons)

        session.receiveImageURL(invalidURL, client: client) { _, _ in icons }
        try await Self.waitUntil { session.error != nil }

        #expect(session.source == nil)
        #expect(session.icons.isEmpty)
        #expect(session.error == "无法读取图片的尺寸信息。")
        #expect(session.isProcessing == false)
    }

    @Test @MainActor func faviconOutputSetSessionDoesNotShowProcessingDuringImageSelectionPanel() async throws {
        let session = FaviconOutputSetSession(outputSpecs: [FaviconOutputSpec(size: 16)])
        var observedProcessingDuringSelection: Bool?
        let panel = FileInputPanelClient { _ in
            observedProcessingDuringSelection = session.isProcessing
            return nil
        }
        let client = ImageWorkflowClient(
            dialog: FakeImageWorkflowDialog(),
            reader: FakeImageWorkflowReader(),
            writer: FakeImageWorkflowWriter()
        )

        session.selectImage(filePanel: panel, client: client)

        try await Self.waitUntil { observedProcessingDuringSelection != nil }

        #expect(observedProcessingDuringSelection == false)
        #expect(session.isProcessing == false)
        #expect(session.source == nil)
        #expect(session.icons.isEmpty)
        #expect(session.error == nil)
    }

    @Test @MainActor func faviconOutputSetSessionSelectionFailureReportsReadError() async throws {
        let url = URL(fileURLWithPath: "/tmp/not-image.png")
        let client = ImageWorkflowClient(
            dialog: FakeImageWorkflowDialog(),
            reader: FakeImageWorkflowReader(dataByURL: [url: Data("not an image".utf8)]),
            writer: FakeImageWorkflowWriter()
        )
        let session = FaviconOutputSetSession(outputSpecs: [FaviconOutputSpec(size: 16)])

        session.receiveImageURL(url, client: client)

        try await Self.waitUntil { session.error != nil }

        #expect(session.source == nil)
        #expect(session.icons.isEmpty)
        #expect(session.isProcessing == false)
        #expect(session.error == "无法读取图片的尺寸信息。")
    }

    @Test @MainActor func faviconOutputSetSessionSelectsAndGeneratesIconSet() async throws {
        let sourceData = try Self.makeImageData(width: 12, height: 8, format: .png)
        let sourceURL = URL(fileURLWithPath: "/tmp/source.png")
        let client = ImageWorkflowClient(
            dialog: FakeImageWorkflowDialog(),
            reader: FakeImageWorkflowReader(dataByURL: [sourceURL: sourceData]),
            writer: FakeImageWorkflowWriter()
        )
        let expected = [
            GeneratedIcon(size: 16, data: Data([1, 6]), pixelWidth: 16, pixelHeight: 16, format: .png),
            GeneratedIcon(size: 32, data: Data([3, 2]), pixelWidth: 32, pixelHeight: 32, format: .png)
        ]
        let session = FaviconOutputSetSession(outputSpecs: [
            FaviconOutputSpec(size: 16),
            FaviconOutputSpec(size: 32)
        ])

        var publishedSelectionURL: URL?
        session.receiveImageURL(
            sourceURL,
            client: client,
            selectionPublisher: { selection, publish in
                publishedSelectionURL = selection.url
                publish()
            },
            generator: { data, sizes in
                #expect(data == sourceData)
                #expect(sizes == [16, 32])
                return expected
            }
        )

        try await Self.waitForIcons(in: session, matching: expected)

        #expect(publishedSelectionURL == sourceURL)
        #expect(session.sourceURL == sourceURL)
        #expect(session.sourceImage?.size.width ?? 0 > 0)
        #expect(session.icons == expected)
        #expect(session.icon(for: FaviconOutputSpec(size: 16)) == expected[0])
        #expect(session.error == nil)
        #expect(session.isProcessing == false)
    }

    @Test @MainActor func faviconOutputSetSessionPublishesCompletePackageAtomically() async throws {
        let sourceData = try Self.makeImageData(width: 12, height: 8, format: .png)
        let sourceURL = URL(fileURLWithPath: "/tmp/package-source.png")
        let client = ImageWorkflowClient(
            dialog: FakeImageWorkflowDialog(),
            reader: FakeImageWorkflowReader(dataByURL: [sourceURL: sourceData]),
            writer: FakeImageWorkflowWriter()
        )
        let session = FaviconOutputSetSession()

        session.receiveImageURL(sourceURL, client: client)
        try await Self.waitUntil { session.package != nil }

        #expect(session.package?.artifacts.map(\.id) == [
            .faviconICO,
            .appleTouchIcon,
            .webAppManifest192,
            .webAppManifest512,
            .siteWebManifest
        ])
        #expect(session.package?.iconPreviews.map(\.size) == [16, 32, 48, 180, 192, 512])
        #expect(session.error == nil)
        #expect(session.isProcessing == false)
    }

    @Test @MainActor func faviconOutputSetSessionIgnoresStaleGenerationResults() async throws {
        let firstData = try Self.makeImageData(width: 12, height: 8, format: .png)
        let secondData = try Self.makeImageData(width: 10, height: 6, format: .png)
        let firstURL = URL(fileURLWithPath: "/tmp/first.png")
        let secondURL = URL(fileURLWithPath: "/tmp/second.png")
        let client = ImageWorkflowClient(
            dialog: FakeImageWorkflowDialog(),
            reader: FakeImageWorkflowReader(dataByURL: [
                firstURL: firstData,
                secondURL: secondData
            ]),
            writer: FakeImageWorkflowWriter()
        )
        let firstIcons = [
            GeneratedIcon(size: 16, data: Data([1]), pixelWidth: 16, pixelHeight: 16, format: .png)
        ]
        let secondIcons = [
            GeneratedIcon(size: 16, data: Data([2]), pixelWidth: 16, pixelHeight: 16, format: .png)
        ]
        let session = FaviconOutputSetSession(outputSpecs: [FaviconOutputSpec(size: 16)])

        session.receiveImageURL(firstURL, client: client) { _, _ in
            Thread.sleep(forTimeInterval: 0.08)
            return firstIcons
        }
        try await Self.waitUntil { session.sourceURL == firstURL }

        session.receiveImageURL(secondURL, client: client) { _, _ in
            secondIcons
        }

        try await Self.waitForIcons(in: session, matching: secondIcons)
        try await Task.sleep(nanoseconds: 120_000_000)

        #expect(session.sourceURL == secondURL)
        #expect(session.icons == secondIcons)
        #expect(session.icons != firstIcons)
        #expect(session.error == nil)
    }



    @Test @MainActor func faviconOutputSetSessionResetClearsWorkflowState() async throws {
        let sourceData = try Self.makeImageData(width: 12, height: 8, format: .png)
        let sourceURL = URL(fileURLWithPath: "/tmp/source.png")
        let client = ImageWorkflowClient(
            dialog: FakeImageWorkflowDialog(),
            reader: FakeImageWorkflowReader(dataByURL: [sourceURL: sourceData]),
            writer: FakeImageWorkflowWriter()
        )
        let icons = [
            GeneratedIcon(size: 16, data: Data([1, 6]), pixelWidth: 16, pixelHeight: 16, format: .png)
        ]
        let session = FaviconOutputSetSession(outputSpecs: [FaviconOutputSpec(size: 16)])

        session.receiveImageURL(sourceURL, client: client) { _, _ in icons }
        try await Self.waitForIcons(in: session, matching: icons)

        session.reset()

        #expect(session.source == nil)
        #expect(session.icons.isEmpty)
        #expect(session.error == nil)
        #expect(session.isProcessing == false)
    }

    @Test @MainActor func faviconOutputSetSessionResetInvalidatesPendingGeneration() async throws {
        let sourceData = try Self.makeImageData(width: 12, height: 8, format: .png)
        let sourceURL = URL(fileURLWithPath: "/tmp/reset-favicon-source.png")
        let client = ImageWorkflowClient(
            dialog: FakeImageWorkflowDialog(),
            reader: FakeImageWorkflowReader(dataByURL: [sourceURL: sourceData]),
            writer: FakeImageWorkflowWriter()
        )
        let lateIcons = [
            GeneratedIcon(size: 16, data: Data([1, 6]), pixelWidth: 16, pixelHeight: 16, format: .png)
        ]
        let session = FaviconOutputSetSession(outputSpecs: [FaviconOutputSpec(size: 16)])

        session.receiveImageURL(sourceURL, client: client) { _, _ in
            Thread.sleep(forTimeInterval: 0.08)
            return lateIcons
        }
        try await Self.waitUntil { session.sourceURL == sourceURL && session.isProcessing }
        session.reset()
        try await Task.sleep(nanoseconds: 120_000_000)

        #expect(session.source == nil)
        #expect(session.icons.isEmpty)
        #expect(session.error == nil)
        #expect(session.isProcessing == false)
    }

    private static func makeImageData(width: Int, height: Int, format: ImageFileFormat) throws -> Data {
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        var pixels = [UInt8](repeating: 0, count: width * height * 4)

        for index in stride(from: 0, to: pixels.count, by: 4) {
            pixels[index] = 24
            pixels[index + 1] = 128
            pixels[index + 2] = 220
            pixels[index + 3] = 255
        }

        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let image = CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: width * 4,
                space: colorSpace,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
              ) else {
            throw TestImageError.renderingFailed
        }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, format.utTypeIdentifier as CFString, 1, nil) else {
            throw TestImageError.destinationUnavailable
        }

        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw TestImageError.encodingFailed
        }
        return output as Data
    }

    @MainActor
    private static func waitForOutput(
        in session: ImageProcessedOutputSession,
        matching expected: ProcessedImage? = nil
    ) async throws {
        for _ in 0..<50 {
            if let expected {
                if session.output == expected {
                    return
                }
            } else if session.output != nil {
                return
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    @MainActor
    private static func waitForIcons(
        in session: FaviconOutputSetSession,
        matching expected: [GeneratedIcon]? = nil
    ) async throws {
        try await waitUntil {
            if let expected {
                return session.icons == expected
            }
            return !session.icons.isEmpty
        }
    }

    @MainActor
    private static func waitUntil(_ predicate: @escaping @MainActor () -> Bool) async throws {
        // ~20s budget under full-suite scheduling pressure.
        for _ in 0..<2000 {
            if predicate() {
                return
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        Issue.record("Timed out waiting for image workflow state")
    }

    private static func processedImage(
        byteCount: Int,
        originalByteCount: Int,
        format: ImageFileFormat
    ) -> ProcessedImage {
        ProcessedImage(
            data: Data(repeating: 7, count: byteCount),
            format: format,
            pixelWidth: 1,
            pixelHeight: 1,
            originalByteCount: originalByteCount,
            quality: nil,
            wasResized: false
        )
    }

    private static func artifact(_ id: FaviconArtifactID, data: Data) -> FaviconArtifact {
        FaviconArtifact(
            id: id,
            mediaType: id == .siteWebManifest ? "application/manifest+json" : "image/png",
            group: id == .siteWebManifest ? .configuration : .browser,
            purpose: "test",
            details: "test",
            data: data
        )
    }

    private static func processedImage(
        data: Data,
        originalByteCount: Int,
        format: ImageFileFormat
    ) -> ProcessedImage {
        ProcessedImage(
            data: data,
            format: format,
            pixelWidth: 1,
            pixelHeight: 1,
            originalByteCount: originalByteCount,
            quality: nil,
            wasResized: false
        )
    }

    private enum TestImageError: Error {
        case renderingFailed
        case destinationUnavailable
        case encodingFailed
    }

    private enum ImageSessionTestError: Error, LocalizedError {
        case renderFailed
        case writeFailed

        var errorDescription: String? {
            switch self {
            case .renderFailed:
                return "处理失败"
            case .writeFailed:
                return "写入失败"
            }
        }
    }
}

@MainActor
private final class ImageRendererSelectionState {
    var usesLatest = false
}

private final class FakeImageWorkflowDialog: ImageWorkflowDialoging {
    var saveURL: URL?
    var directoryURL: URL?
    var requestedSaveNames: [String] = []

    init(
        saveURL: URL? = nil,
        directoryURL: URL? = nil
    ) {
        self.saveURL = saveURL
        self.directoryURL = directoryURL
    }

    func selectSaveURL(defaultFilename: String, allowedContentTypes: [UTType]) async -> URL? {
        requestedSaveNames.append(defaultFilename)
        return saveURL
    }

    func selectDirectory(prompt: String) async -> URL? {
        directoryURL
    }
}

/// Session saves now build their own sheet dialog from the two panel clients.
/// These fakes capture the requested filename and hand back a canned URL, so
/// session-level tests assert through the same seam the pages use.
private final class FakeOutputPanelBox: @unchecked Sendable {
    var requestedNames: [String] = []
    var url: URL?
}

@MainActor
private func makeOutputPanelClient(_ box: FakeOutputPanelBox) -> FileOutputPanelClient {
    FileOutputPanelClient { request in
        box.requestedNames.append(request.defaultFilename ?? "")
        return box.url
    }
}

private final class FakeImageWorkflowReader: ImageWorkflowFileReading, @unchecked Sendable {
    var dataByURL: [URL: Data]
    var byteCountsByURL: [URL: Int]
    var nonRegularURLs: Set<URL>
    var readDelayByURL: [URL: TimeInterval]
    var error: Error?
    private let readURLsLock = NSLock()
    private var storedReadURLs: [URL] = []

    var readURLs: [URL] {
        readURLsLock.lock()
        defer { readURLsLock.unlock() }
        return storedReadURLs
    }

    init(
        dataByURL: [URL: Data] = [:],
        byteCountsByURL: [URL: Int] = [:],
        nonRegularURLs: Set<URL> = [],
        readDelayByURL: [URL: TimeInterval] = [:],
        error: Error? = nil
    ) {
        self.dataByURL = dataByURL
        self.byteCountsByURL = byteCountsByURL
        self.nonRegularURLs = nonRegularURLs
        self.readDelayByURL = readDelayByURL
        self.error = error
    }

    func isRegularFile(at url: URL) throws -> Bool {
        if let error { throw error }
        return !nonRegularURLs.contains(url)
    }

    func byteCount(for url: URL) throws -> Int? {
        if let error { throw error }
        return byteCountsByURL[url] ?? dataByURL[url]?.count
    }

    func readData(from url: URL) throws -> Data {
        if let error { throw error }
        readURLsLock.lock()
        storedReadURLs.append(url)
        readURLsLock.unlock()
        if let delay = readDelayByURL[url] {
            Thread.sleep(forTimeInterval: delay)
        }
        return dataByURL[url] ?? Data()
    }
}

private struct FoundationImageWorkflowReaderWithMetadataOverride: ImageWorkflowFileReading {
    let reportedByteCount: Int?
    let maxBytes: Int
    private let foundationReader = FoundationImageWorkflowFileReader()

    func isRegularFile(at url: URL) throws -> Bool {
        try foundationReader.isRegularFile(at: url)
    }

    func byteCount(for url: URL) throws -> Int? {
        reportedByteCount
    }

    func readData(from url: URL) throws -> Data {
        try foundationReader.readData(from: url, maxBytes: maxBytes)
    }
}

private final class FakeImageWorkflowWriter: ImageWorkflowFileWriting {
    var error: Error?
    /// When set, the writer succeeds for the first `failAfter` writes and throws
    /// on the next one, simulating a partial batch failure.
    var failAfter: Int?
    private(set) var writes: [(data: Data, url: URL)] = []

    init(error: Error? = nil, failAfter: Int? = nil) {
        self.error = error
        self.failAfter = failAfter
    }

    func write(_ data: Data, to url: URL) throws {
        // In failAfter mode the first `failAfter` writes succeed and the next
        // one throws, so the general `error` branch must not pre-empt them.
        if let failAfter {
            if writes.count >= failAfter {
                throw error ?? CocoaError(.fileWriteUnknown)
            }
            writes.append((data, url))
            return
        }
        if let error {
            throw error
        }
        writes.append((data, url))
    }
}
