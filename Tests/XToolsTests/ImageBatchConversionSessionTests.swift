import AppKit
import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import XTools
@testable import XToolsCore

@MainActor
struct ImageBatchConversionSessionTests {
    // MARK: - Import

    @Test func importSkipsInvalidEntriesAndSummarizesOnce() async throws {
        let goodFirst = try Self.makeImageData(width: 12, height: 8, format: .png)
        let goodSecond = try Self.makeImageData(width: 9, height: 6, format: .png)
        let firstURL = URL(fileURLWithPath: "/tmp/batch-first.png")
        let brokenURL = URL(fileURLWithPath: "/tmp/batch-broken.png")
        let secondURL = URL(fileURLWithPath: "/tmp/batch-second.png")
        let session = ImageBatchConversionSession()
        var publishedFilenames: [String] = []

        session.receiveImageURLs(
            [firstURL, brokenURL, secondURL],
            allowedContentTypes: [.png],
            client: Self.makeClient(dataByURL: [
                firstURL: goodFirst,
                brokenURL: Data("not an image".utf8),
                secondURL: goodSecond
            ]),
            importPublisher: { imported, publish in
                publishedFilenames = imported.map(\.filename)
                publish()
            }
        )

        try await Self.waitUntil { session.items.count == 2 && session.error != nil }

        #expect(publishedFilenames == ["batch-first.png", "batch-second.png"])
        #expect(session.items.map(\.url) == [firstURL, secondURL])
        #expect(session.items.allSatisfy { $0.thumbnail.size.width > 0 })
        #expect(session.items.allSatisfy { $0.state == .idle })
        #expect(!session.isImporting)
        #expect(session.error == "已跳过 1 张：batch-broken.png（无法读取图片的尺寸信息）。")
        ToolDiagnosticContract.expectFactual(session.error ?? "")
    }

    @Test func importRejectsEntriesBeyondTheItemCountCap() async throws {
        let imageData = try Self.makeImageData(width: 12, height: 8, format: .png)
        let firstURL = URL(fileURLWithPath: "/tmp/cap-first.png")
        let secondURL = URL(fileURLWithPath: "/tmp/cap-second.png")
        let thirdURL = URL(fileURLWithPath: "/tmp/cap-third.png")
        let session = ImageBatchConversionSession(maximumItemCount: 2)

        session.receiveImageURLs(
            [firstURL, secondURL, thirdURL],
            allowedContentTypes: [.png],
            client: Self.makeClient(dataByURL: [
                firstURL: imageData,
                secondURL: imageData,
                thirdURL: imageData
            ])
        )
        try await Self.waitUntil { session.error != nil }

        #expect(session.items.map(\.url) == [firstURL, secondURL])
        #expect(session.error == "已跳过 1 张：cap-third.png（超出 2 张上限）。")

        // 已达上限后的追加导入整批跳过，不减少既有项。
        let fourthURL = URL(fileURLWithPath: "/tmp/cap-fourth.png")
        session.receiveImageURLs(
            [fourthURL],
            allowedContentTypes: [.png],
            client: Self.makeClient(dataByURL: [fourthURL: imageData])
        )
        try await Self.waitUntil { session.error == "已跳过 1 张：cap-fourth.png（超出 2 张上限）。" }

        #expect(session.items.map(\.url) == [firstURL, secondURL])
    }

    @Test func importSkipSummaryCompactsLongListsAndNames() {
        #expect(ImageBatchConversionSession.importSkipSummary([]) == nil)
        #expect(
            ImageBatchConversionSession.importSkipSummary([
                (name: "a.png", reason: "不支持所选图片的文件格式。")
            ]) == "已跳过 1 张：a.png（不支持所选图片的文件格式）。"
        )
        let many = (0..<4).map { (name: "file-\($0).png", reason: "图片文件读取失败。") }
        let summary = ImageBatchConversionSession.importSkipSummary(many)
        #expect(summary == "已跳过 4 张：file-0.png（图片文件读取失败）、file-1.png（图片文件读取失败）等。")
        let longName = String(repeating: "长", count: 40) + ".png"
        let longSummary = ImageBatchConversionSession.importSkipSummary([(name: longName, reason: "图片文件读取失败。")]) ?? ""
        #expect(longSummary.count < ToolDiagnosticContract.maximumMessageCharacters)
    }

    @Test func selectImagesRequestsMultiSelectionThroughThePanel() async throws {
        let imageData = try Self.makeImageData(width: 12, height: 8, format: .png)
        let firstURL = URL(fileURLWithPath: "/tmp/panel-first.png")
        let secondURL = URL(fileURLWithPath: "/tmp/panel-second.png")
        var capturedRequest: FileInputPanelRequest?
        let panel = FileInputPanelClient(
            select: { _ in nil },
            selectFiles: { request in
                capturedRequest = request
                return [firstURL, secondURL]
            }
        )
        let session = ImageBatchConversionSession()

        session.selectImages(
            filePanel: panel,
            allowedContentTypes: ImageWorkflowClient.standardImageContentTypes,
            client: Self.makeClient(dataByURL: [firstURL: imageData, secondURL: imageData])
        )
        try await Self.waitUntil { session.items.count == 2 }

        #expect(capturedRequest?.allowsMultipleSelection == true)
        #expect(session.error == nil)

        // 面板取消返回 nil：导入静默结束，不产生错误诊断。
        let cancelledPanel = FileInputPanelClient(
            select: { _ in nil },
            selectFiles: { _ in nil }
        )
        session.selectImages(
            filePanel: cancelledPanel,
            allowedContentTypes: ImageWorkflowClient.standardImageContentTypes,
            client: Self.makeClient()
        )
        await Task.yield()
        try await Task.sleep(for: .milliseconds(50))
        #expect(session.items.count == 2)
        #expect(session.error == nil)
    }

    // MARK: - Conversion

    @Test func convertAllTransitionsItemsSeriallyAndKeepsFailuresIsolated() async throws {
        let firstData = try Self.makeImageData(width: 12, height: 8, format: .png)
        let secondData = try Self.makeImageData(width: 5, height: 3, format: .png)
        let firstURL = URL(fileURLWithPath: "/tmp/serial-first.png")
        let secondURL = URL(fileURLWithPath: "/tmp/serial-second.png")
        let session = ImageBatchConversionSession()
        session.receiveImageURLs(
            [firstURL, secondURL],
            allowedContentTypes: [.png],
            client: Self.makeClient(dataByURL: [firstURL: firstData, secondURL: secondData])
        )
        try await Self.waitUntil { session.items.count == 2 }

        let renderOrder = RenderOrderBox()
        let doneOutput = Self.processedImage(data: Data([9]), originalByteCount: firstData.count, format: .png)
        session.convertAll(rendererProvider: {
            { input in
                renderOrder.append(input.metadata.pixelWidth)
                if input.metadata.pixelWidth == 5 {
                    throw ImageProcessorError.encodingFailed(.png)
                }
                return doneOutput
            }
        })
        try await Self.waitUntil { session.completedCount == 1 && session.failedCount == 1 }

        #expect(renderOrder.values == [12, 5])
        guard case let .done(record) = session.items[0].state else {
            Issue.record("Expected the first item to finish with a spooled record")
            return
        }
        #expect(record.format == .png)
        #expect(record.byteCount == doneOutput.byteCount)
        #expect(record.originalByteCount == firstData.count)
        #expect(record.requiresExplicitLargerSave == false)
        #expect(record.summaryText == ImageOutputPresentation.processingOutputSummary(
            ImageOutputPolicy.assess(doneOutput, for: .conversion)
        ))
        // 输出落盘：tempURL 文件存在且内容等于渲染输出 data。
        #expect(try Data(contentsOf: record.tempURL) == doneOutput.data)
        #expect(session.items[1].state == .failed("无法将图片编码为 PNG。"))
        #expect(!session.isProcessing)
        #expect(session.error == nil)
        #expect(session.completedCount == 1)
        #expect(session.failedCount == 1)
    }

    @Test func convertAllSupersedesThePreviousGeneration() async throws {
        let imageData = try Self.makeImageData(width: 12, height: 8, format: .png)
        let url = URL(fileURLWithPath: "/tmp/supersede.png")
        let session = ImageBatchConversionSession()
        session.receiveImageURLs(
            [url],
            allowedContentTypes: [.png],
            client: Self.makeClient(dataByURL: [url: imageData])
        )
        try await Self.waitUntil { session.items.count == 1 }

        let stale = Self.processedImage(data: Data([1]), originalByteCount: imageData.count, format: .png)
        let latest = Self.processedImage(data: Data([2]), originalByteCount: imageData.count, format: .png)

        session.convertAll(rendererProvider: {
            { _ in
                Thread.sleep(forTimeInterval: 0.12)
                return stale
            }
        })
        try await Self.waitUntil { session.isProcessing }
        session.convertAll(rendererProvider: {
            { _ in latest }
        })

        try await Self.waitUntil {
            if case .done = session.items.first?.state { return true }
            return false
        }
        try await Task.sleep(for: .milliseconds(220))

        #expect(!session.isProcessing)
        #expect(session.error == nil)
        // 上一轮在写入前即被取消：落盘内容始终是最新一代输出。
        guard case let .done(record) = session.items[0].state else {
            Issue.record("Expected the item to finish with a spooled record")
            return
        }
        #expect(try Data(contentsOf: record.tempURL) == latest.data)
    }

    @Test func convertPendingItemsResumesIdleEntriesWithoutResettingSettledOutputs() async throws {
        let firstData = try Self.makeImageData(width: 12, height: 8, format: .png)
        let secondData = try Self.makeImageData(width: 5, height: 3, format: .png)
        let thirdData = try Self.makeImageData(width: 7, height: 4, format: .png)
        let firstURL = URL(fileURLWithPath: "/tmp/resume-first.png")
        let secondURL = URL(fileURLWithPath: "/tmp/resume-second.png")
        let thirdURL = URL(fileURLWithPath: "/tmp/resume-third.png")
        let session = ImageBatchConversionSession()
        session.receiveImageURLs(
            [firstURL, secondURL, thirdURL],
            allowedContentTypes: [.png],
            client: Self.makeClient(dataByURL: [
                firstURL: firstData, secondURL: secondData, thirdURL: thirdData
            ])
        )
        try await Self.waitUntil { session.items.count == 3 }

        let initialOutput = Self.processedImage(data: Data([1]), originalByteCount: firstData.count, format: .png)
        let resumedOutput = Self.processedImage(data: Data([2]), originalByteCount: firstData.count, format: .png)
        session.convertAll(rendererProvider: {
            { input in
                if input.metadata.pixelWidth == 5 {
                    Thread.sleep(forTimeInterval: 0.3)
                }
                return initialOutput
            }
        })
        // 第一张完成、第二张仍在转换时移除它：在途轮被取消，第三张回到待转换。
        try await Self.waitUntil { session.completedCount == 1 && session.isProcessing }
        session.removeItem(id: session.items[1].id)
        #expect(!session.isProcessing)
        #expect(session.items[1].state == .idle)

        session.convertPendingItems(rendererProvider: { { _ in resumedOutput } })
        try await Self.waitUntil { session.completedCount == 2 && !session.isProcessing }

        #expect(session.error == nil)
        guard case let .done(first) = session.items[0].state,
              case let .done(second) = session.items[1].state else {
            Issue.record("Expected both remaining items to finish with spooled records")
            return
        }
        #expect(try Data(contentsOf: first.tempURL) == initialOutput.data)
        #expect(try Data(contentsOf: second.tempURL) == resumedOutput.data)
    }

    @Test func spoolWriteFailuresFailOnlyTheAffectedItem() {
        #expect(ImageBatchConversionSession.itemFailureMessage(for: OutputSpoolWriteFailure()) == "转换结果写入临时文件失败。")
        ToolDiagnosticContract.expectFactual(
            ImageBatchConversionSession.itemFailureMessage(for: OutputSpoolWriteFailure())
        )
    }

    // MARK: - Save

    @Test func saveAllUsesSingleFilePanelForOneCompletedItem() async throws {
        let imageData = try Self.makeImageData(width: 12, height: 8, format: .png)
        let url = URL(fileURLWithPath: "/tmp/save-single.png")
        let saveURL = URL(fileURLWithPath: "/tmp/save-single-output.png")
        let dialog = FakeBatchDialog(saveURL: saveURL)
        let writer = FakeBatchWriter()
        let session = ImageBatchConversionSession(
            saveClientBuilder: { _, _ in
                ImageWorkflowClient(dialog: dialog, reader: FakeBatchReader(), writer: writer)
            }
        )
        session.receiveImageURLs(
            [url],
            allowedContentTypes: [.png],
            client: Self.makeClient(dataByURL: [url: imageData])
        )
        try await Self.waitUntil { session.items.count == 1 }
        let output = Self.processedImage(data: imageData, originalByteCount: imageData.count, format: .png)
        session.convertAll(rendererProvider: { { _ in output } })
        try await Self.waitUntil { session.completedCount == 1 }

        guard case let .done(record) = session.items[0].state else {
            Issue.record("Expected the item to finish with a spooled record")
            return
        }
        #expect(try Data(contentsOf: record.tempURL) == output.data)

        #expect(await session.saveAll(
            defaultBasename: "converted",
            filePanel: .unavailable,
            outputPanel: FileOutputPanelClient { _ in nil }
        ) == .saved)
        #expect(dialog.requestedSaveNames == ["converted.png"])
        #expect(writer.writes.map(\.url) == [saveURL])
        // N=1 读取临时文件 data 后经 saveConvertedImage 写入。
        #expect(writer.writes.map(\.data) == [output.data])
        #expect(session.error == nil)

        // 保存面板取消保持静默。
        dialog.saveURL = nil
        #expect(await session.saveAll(
            defaultBasename: "converted",
            filePanel: .unavailable,
            outputPanel: FileOutputPanelClient { _ in nil }
        ) == .cancelled)
    }

    @Test func saveAllWritesBatchIntoSelectedDirectoryAndMapsPartialFailure() async throws {
        let imageData = try Self.makeImageData(width: 12, height: 8, format: .png)
        let firstURL = URL(fileURLWithPath: "/tmp/save-batch-first.png")
        let secondURL = URL(fileURLWithPath: "/tmp/save-batch-second.png")
        let directory = URL(fileURLWithPath: "/tmp/save-batch-dir", isDirectory: true)
        let output = Self.processedImage(data: imageData, originalByteCount: imageData.count, format: .jpeg)

        var lastDialog: FakeBatchDialog?
        func makeCompletedSession(writer: FakeBatchWriter) -> ImageBatchConversionSession {
            let dialog = FakeBatchDialog(directoryURL: directory)
            lastDialog = dialog
            let session = ImageBatchConversionSession(
                saveClientBuilder: { _, _ in
                    ImageWorkflowClient(dialog: dialog, reader: FakeBatchReader(), writer: writer)
                }
            )
            session.receiveImageURLs(
                [firstURL, secondURL],
                allowedContentTypes: [.png],
                client: Self.makeClient(dataByURL: [firstURL: imageData, secondURL: imageData])
            )
            return session
        }

        let successWriter = FakeBatchWriter()
        let successSession = makeCompletedSession(writer: successWriter)
        try await Self.waitUntil { successSession.items.count == 2 }
        successSession.convertAll(rendererProvider: { { _ in output } })
        try await Self.waitUntil { successSession.completedCount == 2 }

        #expect(await successSession.saveAll(
            defaultBasename: "converted",
            filePanel: .unavailable,
            outputPanel: FileOutputPanelClient { _ in nil }
        ) == .saved)
        #expect(successWriter.writes.map { $0.url.lastPathComponent } == ["save-batch-first.jpg", "save-batch-second.jpg"])
        // 批量写入的数据来自落盘临时文件的读取结果。
        #expect(successWriter.writes.map(\.data) == [output.data, output.data])
        // 目录面板确认按钮为「保存」，message 说明即将写入的张数。
        #expect(lastDialog?.requestedDirectoryMessages.count == 1)
        #expect(lastDialog?.requestedDirectoryMessages.first?.prompt == "保存")
        #expect(lastDialog?.requestedDirectoryMessages.first?.message == "已转换的 2 张图片将保存到所选文件夹")

        let partialWriter = FakeBatchWriter(error: BatchTestError.writeFailed, failAfter: 1)
        let partialSession = makeCompletedSession(writer: partialWriter)
        try await Self.waitUntil { partialSession.items.count == 2 }
        partialSession.convertAll(rendererProvider: { { _ in output } })
        try await Self.waitUntil { partialSession.completedCount == 2 }

        #expect(await partialSession.saveAll(
            defaultBasename: "converted",
            filePanel: .unavailable,
            outputPanel: FileOutputPanelClient { _ in nil }
        ) == .partiallySaved(savedCount: 1, totalCount: 2))

        // 没有完成项时保持 blocked 静默语义。
        let emptySession = ImageBatchConversionSession(
            saveClientBuilder: { _, _ in
                ImageWorkflowClient(dialog: FakeBatchDialog(), reader: FakeBatchReader(), writer: FakeBatchWriter())
            }
        )
        #expect(await emptySession.saveAll(
            defaultBasename: "converted",
            filePanel: .unavailable,
            outputPanel: FileOutputPanelClient { _ in nil }
        ) == .blocked)
    }

    // MARK: - Removal / eviction

    @Test func removeItemEvictionAndResetClearStateAndCancelWork() async throws {
        let imageData = try Self.makeImageData(width: 12, height: 8, format: .png)
        let firstURL = URL(fileURLWithPath: "/tmp/remove-first.png")
        let secondURL = URL(fileURLWithPath: "/tmp/remove-second.png")
        let session = ImageBatchConversionSession()
        session.receiveImageURLs(
            [firstURL, secondURL],
            allowedContentTypes: [.png],
            client: Self.makeClient(dataByURL: [firstURL: imageData, secondURL: imageData])
        )
        try await Self.waitUntil { session.items.count == 2 }
        let output = Self.processedImage(data: imageData, originalByteCount: imageData.count, format: .png)
        session.convertAll(rendererProvider: { { _ in output } })
        try await Self.waitUntil { session.completedCount == 2 }

        // clearOutputs 释放全部完成项的临时文件并回到待转换。
        guard case let .done(cleared) = session.items[0].state else {
            Issue.record("Expected a spooled record before clearOutputs")
            return
        }
        session.clearOutputs()
        #expect(session.items.allSatisfy { $0.state == .idle })
        #expect(!FileManager.default.fileExists(atPath: cleared.tempURL.path))

        session.convertAll(rendererProvider: { { _ in output } })
        try await Self.waitUntil { session.completedCount == 2 }
        guard case let .done(removed) = session.items[0].state else {
            Issue.record("Expected a spooled record after re-conversion")
            return
        }

        session.removeItem(id: session.items[0].id)
        #expect(session.items.map(\.url) == [secondURL])
        #expect(session.completedCount == 1)
        #expect(!session.isProcessing)
        // 移除单张即删除该张临时文件；会话子目录保留给仍在列表中的输出。
        #expect(!FileManager.default.fileExists(atPath: removed.tempURL.path))
        #expect(FileManager.default.fileExists(atPath: session.spoolDirectory.path))

        session.evictHeavyPayloads()
        #expect(session.items.isEmpty)
        #expect(session.error == nil)
        #expect(!session.isProcessing)
        #expect(!session.isImporting)
        // 会话级清理删除整个落盘子目录。
        #expect(!FileManager.default.fileExists(atPath: session.spoolDirectory.path))

        session.receiveImageURLs(
            [firstURL],
            allowedContentTypes: [.png],
            client: Self.makeClient(dataByURL: [firstURL: imageData])
        )
        try await Self.waitUntil { session.items.count == 1 }
        session.reset()
        #expect(session.items.isEmpty)
        #expect(session.error == nil)
        #expect(!FileManager.default.fileExists(atPath: session.spoolDirectory.path))
    }

    // MARK: - Fixtures

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
            throw BatchTestError.renderingFailed
        }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, format.utTypeIdentifier as CFString, 1, nil) else {
            throw BatchTestError.destinationUnavailable
        }

        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw BatchTestError.encodingFailed
        }
        return output as Data
    }

    private static func makeClient(
        dataByURL: [URL: Data] = [:],
        saveURL: URL? = nil,
        directoryURL: URL? = nil
    ) -> ImageWorkflowClient {
        ImageWorkflowClient(
            dialog: FakeBatchDialog(saveURL: saveURL, directoryURL: directoryURL),
            reader: FakeBatchReader(dataByURL: dataByURL),
            writer: FakeBatchWriter()
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

    private static func waitUntil(
        timeout: Duration = .seconds(20),
        _ condition: @escaping @MainActor () -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while !condition(), clock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(condition())
    }
}

/// 渲染闭包在非主线程执行，用锁记录逐张调用顺序。
private final class RenderOrderBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [Int] = []

    var values: [Int] {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }

    func append(_ value: Int) {
        lock.lock()
        stored.append(value)
        lock.unlock()
    }
}

private enum BatchTestError: Error {
    case writeFailed
    case renderingFailed
    case destinationUnavailable
    case encodingFailed
}

@MainActor
private final class FakeBatchDialog: ImageWorkflowDialoging {
    var saveURL: URL?
    var directoryURL: URL?
    private(set) var requestedSaveNames: [String] = []
    private(set) var requestedDirectoryMessages: [(prompt: String, message: String?)] = []

    init(saveURL: URL? = nil, directoryURL: URL? = nil) {
        self.saveURL = saveURL
        self.directoryURL = directoryURL
    }

    func selectSaveURL(defaultFilename: String, allowedContentTypes: [UTType]) async -> URL? {
        requestedSaveNames.append(defaultFilename)
        return saveURL
    }

    func selectDirectory(prompt: String, message: String?) async -> URL? {
        requestedDirectoryMessages.append((prompt, message))
        return directoryURL
    }
}

private final class FakeBatchReader: ImageWorkflowFileReading, @unchecked Sendable {
    var dataByURL: [URL: Data]

    init(dataByURL: [URL: Data] = [:]) {
        self.dataByURL = dataByURL
    }

    func isRegularFile(at url: URL) throws -> Bool { true }

    func byteCount(for url: URL) throws -> Int? {
        dataByURL[url]?.count
    }

    func readData(from url: URL) throws -> Data {
        dataByURL[url] ?? Data()
    }
}

private final class FakeBatchWriter: ImageWorkflowFileWriting {
    var error: Error?
    var failAfter: Int?
    private(set) var writes: [(data: Data, url: URL)] = []

    init(error: Error? = nil, failAfter: Int? = nil) {
        self.error = error
        self.failAfter = failAfter
    }

    func write(_ data: Data, to url: URL) throws {
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
