import AppKit
import Foundation
import Testing
import UniformTypeIdentifiers
@testable import XTools
@testable import XToolsCore

@MainActor
struct ChallengerM2EmpiricalTests {

    // MARK: - 1. Base64 Roundtrip Oracle Tests (OPT-B1)

    @Test func roundtripArbitraryBinaryBuffersOfVaryingSizes() async throws {
        let testSizes = [0, 1, 2, 3, 4, 15, 16, 17, 255, 256, 1024, 65536]

        for size in testSizes {
            var bytes = [UInt8](repeating: 0, count: size)
            if size > 0 {
                for i in 0..<size {
                    bytes[i] = UInt8(i % 256)
                }
            }
            let originalData = Data(bytes)
            let selection = Base64FileSelection(
                fileName: "test_\(size).bin",
                data: originalData,
                mimeType: "application/octet-stream"
            )

            // Test raw base64 mode
            let rawBase64 = await Base64FileWorkflow.fullOutput(for: selection, mode: .base64)
            let decodedRaw = await Base64FileWorkflow.decodePayload(rawBase64, maxDecodedBytes: size + 100)
            guard case .success(let payloadRaw) = decodedRaw else {
                Issue.record("Failed to decode raw base64 for size \(size)")
                continue
            }
            #expect(payloadRaw.data == originalData, "Payload mismatch for raw base64 size \(size)")

            // Test Data URL mode
            let dataURL = await Base64FileWorkflow.fullOutput(for: selection, mode: .dataURL)
            let decodedDataURL = await Base64FileWorkflow.decodePayload(dataURL, maxDecodedBytes: size + 100)
            guard case .success(let payloadURL) = decodedDataURL else {
                Issue.record("Failed to decode Data URL for size \(size)")
                continue
            }
            #expect(payloadURL.data == originalData, "Payload mismatch for data URL size \(size)")
        }
    }

    @Test func roundtripBoundaryPaddingCases() async throws {
        // 1 byte -> 2 padding chars (==)
        let oneByte = Data([0x41])
        let encoded1 = await Base64FileWorkflow.fullOutput(
            for: Base64FileSelection(fileName: "1.bin", data: oneByte, mimeType: "application/octet-stream"),
            mode: .base64
        )
        #expect(encoded1.hasSuffix("=="))
        let decoded1 = await Base64FileWorkflow.decodePayload(encoded1, maxDecodedBytes: 10)
        guard case .success(let p1) = decoded1 else {
            Issue.record("Expected successful decode for 1 byte")
            return
        }
        #expect(p1.data == oneByte)

        // 2 bytes -> 1 padding char (=)
        let twoBytes = Data([0x41, 0x42])
        let encoded2 = await Base64FileWorkflow.fullOutput(
            for: Base64FileSelection(fileName: "2.bin", data: twoBytes, mimeType: "application/octet-stream"),
            mode: .base64
        )
        #expect(encoded2.hasSuffix("="))
        let decoded2 = await Base64FileWorkflow.decodePayload(encoded2, maxDecodedBytes: 10)
        guard case .success(let p2) = decoded2 else {
            Issue.record("Expected successful decode for 2 bytes")
            return
        }
        #expect(p2.data == twoBytes)

        // 3 bytes -> 0 padding chars
        let threeBytes = Data([0x41, 0x42, 0x43])
        let encoded3 = await Base64FileWorkflow.fullOutput(
            for: Base64FileSelection(fileName: "3.bin", data: threeBytes, mimeType: "application/octet-stream"),
            mode: .base64
        )
        #expect(!encoded3.hasSuffix("="))
        let decoded3 = await Base64FileWorkflow.decodePayload(encoded3, maxDecodedBytes: 10)
        guard case .success(let p3) = decoded3 else {
            Issue.record("Expected successful decode for 3 bytes")
            return
        }
        #expect(p3.data == threeBytes)
    }

    @Test func decodeRejectsMalformedAndPinsLenientBase64Edges() async {
        // 一律拒绝：字母表外字符（含非 ASCII 与 NUL）、长度余 1 的不可能
        // Base64、缺逗号/缺 base64 标记的残缺 data URL。
        let rejected = [
            "???not_base64???",
            "abcde",                             // 5 字符，长度余 1
            "data:",                             // 无逗号
            "data:image/png",                    // 无 base64 标记与逗号
            "data:image/png;base64",             // 无逗号
            "data:image/png;base64,invalid!@#$", // payload 含字母表外字符
            "中文测试内容",
            "\0\0\0\0",
        ]
        for input in rejected {
            let result = await Base64FileWorkflow.decodePayload(input)
            #expect(result == .failure(.invalidPayload), "应拒绝: \(input)")
        }

        // 宽容语义（decodeData 的既有契约）：纯空白与全填充串归一为空数据；
        // 缺失/多余填充补齐后照常解码。
        for input in ["", "   \n\t  ", "======"] {
            let result = await Base64FileWorkflow.decodePayload(input)
            guard case .success(let payload) = result else {
                Issue.record("应按空数据成功解码: \(input)")
                return
            }
            #expect(payload.data.isEmpty)
            #expect(payload.mimeType == "application/octet-stream")
            #expect(payload.fileExtension == "bin")
        }
        for input in ["aGVsbG8", "aGVsbG8==="] {
            let result = await Base64FileWorkflow.decodePayload(input)
            guard case .success(let payload) = result else {
                Issue.record("应按宽容填充语义解码: \(input)")
                return
            }
            #expect(payload.data == Data("hello".utf8))
        }

        // data URL 边界：空 payload 用 URL 元数据产出类型；缺 mime 按 RFC
        // 兜底 text/plain;charset=us-ascii。
        let emptyPNG = await Base64FileWorkflow.decodePayload("data:image/png;base64,")
        guard case .success(let pngPayload) = emptyPNG else {
            Issue.record("空 payload 的 data URL 应成功解码")
            return
        }
        #expect(pngPayload.data.isEmpty)
        #expect(pngPayload.mimeType == "image/png")
        #expect(pngPayload.fileExtension == "png")

        let noMime = await Base64FileWorkflow.decodePayload("data:;base64,aGVsbG8=")
        guard case .success(let plainPayload) = noMime else {
            Issue.record("缺 mime 的 data URL 应成功解码")
            return
        }
        #expect(plainPayload.data == Data("hello".utf8))
        #expect(plainPayload.mimeType == "text/plain;charset=us-ascii")
        #expect(plainPayload.fileExtension == "txt")
    }

    @Test func decodePayloadEnforcesSizeLimitsStrictly() async {
        let payloadData = Data(repeating: 0x5A, count: 100)
        let encoded = payloadData.base64EncodedString()

        // Exactly at limit: passes
        let passResult = await Base64FileWorkflow.decodePayload(encoded, maxDecodedBytes: 100)
        guard case .success(let payload) = passResult else {
            Issue.record("Expected payload to pass at exactly 100 bytes")
            return
        }
        #expect(payload.data.count == 100)

        // 1 byte below required: rejected with .decodedTooLarge
        let failResult = await Base64FileWorkflow.decodePayload(encoded, maxDecodedBytes: 99)
        #expect(failResult == .failure(.decodedTooLarge(maxBytes: 99)))

        // Theoretical upper bound rejection before full decode:
        let hugeLimit = 10
        let largeEncoded = Data(repeating: 0x41, count: 1000).base64EncodedString()
        let earlyReject = await Base64FileWorkflow.decodePayload(largeEncoded, maxDecodedBytes: hugeLimit)
        #expect(earlyReject == .failure(.decodedTooLarge(maxBytes: hugeLimit)))
    }

    @Test func readSelectionHandlesFileSystemEdgeCases() async throws {
        let tempDir = FileManager.default.temporaryDirectory
        let validFile = tempDir.appendingPathComponent("challenger_valid_\(UUID().uuidString).txt")
        let oversizedFile = tempDir.appendingPathComponent("challenger_large_\(UUID().uuidString).bin")
        let subDirectory = tempDir.appendingPathComponent("challenger_dir_\(UUID().uuidString)")
        let nonExistentFile = tempDir.appendingPathComponent("challenger_nonexistent_\(UUID().uuidString).txt")

        try "Hello Empirical Challenger".write(to: validFile, atomically: true, encoding: .utf8)
        try Data(repeating: 0xFF, count: 2048).write(to: oversizedFile)
        try FileManager.default.createDirectory(at: subDirectory, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: validFile)
            try? FileManager.default.removeItem(at: oversizedFile)
            try? FileManager.default.removeItem(at: subDirectory)
        }

        // 1. Valid file within limit
        let validResult = await Base64FileWorkflow.readSelection(from: validFile, maxBytes: 1024)
        guard case .success(let selection) = validResult else {
            Issue.record("Expected successful file read")
            return
        }
        #expect(selection.fileName == validFile.lastPathComponent)
        #expect(selection.data == Data("Hello Empirical Challenger".utf8))

        // 2. Oversized file
        let oversizedResult = await Base64FileWorkflow.readSelection(from: oversizedFile, maxBytes: 1024)
        #expect(oversizedResult == .failure(.tooLarge(fileName: oversizedFile.lastPathComponent, maxBytes: 1024)))

        // 3. Directory instead of regular file
        let dirResult = await Base64FileWorkflow.readSelection(from: subDirectory, maxBytes: 1024)
        #expect(dirResult == .failure(.notRegularFile))

        // 4. Non-existent file
        let nonExistentResult = await Base64FileWorkflow.readSelection(from: nonExistentFile, maxBytes: 1024)
        #expect(nonExistentResult == .failure(.readFailed))
    }

    // MARK: - 2. PanelRequestBox Stress & Concurrency Tests (OPT-B3)

    @Test func panelRequestBoxRapidRequestsPermitOnlySingleInFlightTask() async {
        var box = PanelRequestBox()
        let callCounter = TestLockedCounter(initialValue: 0)
        let signal = TestAsyncSignal()

        // Start first in-flight request
        let task1 = box.request(
            {
                callCounter.increment()
                await signal.wait()
                return "result-1"
            },
            onSuccess: { _ in },
            onError: { _ in }
        )

        #expect(box.hasActiveRequest)
        #expect(box.task != nil)

        // Rapidly fire 50 subsequent requests while task 1 is in-flight
        var tasks: [Task<Void, Never>] = []
        for _ in 0..<50 {
            let t = box.request(
                {
                    callCounter.increment()
                    return "should-not-run"
                },
                onSuccess: { _ in },
                onError: { _ in }
            )
            tasks.append(t)
        }

        // All returned tasks must match task1
        for t in tasks {
            #expect(t == task1)
        }

        // Let task1 finish
        await signal.signal()
        await task1.value

        // Only the first action ran
        #expect(callCounter.count == 1)
        #expect(!box.hasActiveRequest)
        #expect(box.task == nil)

        // Now a new request can be started successfully
        var secondResult: String?
        let task2 = box.request(
            {
                callCounter.increment()
                return "result-2"
            },
            onSuccess: { secondResult = $0 },
            onError: { _ in }
        )
        await task2.value

        #expect(callCounter.count == 2)
        #expect(secondResult == "result-2")
        #expect(!box.hasActiveRequest)
    }

    @Test func panelRequestBoxCancellationSuppressesCallbacks() async {
        var box = PanelRequestBox()
        let signal = TestAsyncSignal()
        var successFired = false
        var errorFired = false

        let task = box.request(
            {
                await signal.wait()
                return "value"
            },
            onSuccess: { _ in successFired = true },
            onError: { _ in errorFired = true }
        )

        #expect(box.hasActiveRequest)

        // Explicitly cancel the box while request is in-flight
        box.cancel()

        #expect(!box.hasActiveRequest)
        #expect(box.task == nil)

        // Unblock action
        await signal.signal()
        await task.value

        // Neither callback should fire
        #expect(!successFired)
        #expect(!errorFired)
    }

    @Test func panelRequestBoxErrorDiagnosticsMapping() async {
        // 1. windowUnavailable
        var box1 = PanelRequestBox()
        var receivedError1: String?
        let t1 = box1.request(
            { throw FileInputPanelFailure.windowUnavailable },
            onSuccess: { _ in },
            onError: { receivedError1 = $0 }
        )
        await t1.value
        #expect(receivedError1 == "暂时无法打开文件选择器。")

        // 2. requestInProgress
        var box2 = PanelRequestBox()
        var receivedError2: String?
        let t2 = box2.request(
            { throw FileInputPanelFailure.requestInProgress },
            onSuccess: { _ in },
            onError: { receivedError2 = $0 }
        )
        await t2.value
        #expect(receivedError2 == "已有文件选择器正在打开。")

        // 3. invalidSelection
        var box3 = PanelRequestBox()
        var receivedError3: String?
        let t3 = box3.request(
            { throw FileInputPanelFailure.invalidSelection },
            onSuccess: { _ in },
            onError: { receivedError3 = $0 }
        )
        await t3.value
        #expect(receivedError3 == "没有取得可用的文件。")

        // 4. Arbitrary unknown error falls back to standard message
        struct RandomFailure: Error {}
        var box4 = PanelRequestBox()
        var receivedError4: String?
        let t4 = box4.request(
            { throw RandomFailure() },
            onSuccess: { _ in },
            onError: { receivedError4 = $0 }
        )
        await t4.value
        #expect(receivedError4 == "暂时无法打开文件选择器。")
    }

    @Test func panelRequestBoxCancellationErrorDoesNotReportError() async {
        var box = PanelRequestBox()
        var errorReported = false

        let task = box.request(
            {
                throw CancellationError()
            },
            onSuccess: { _ in },
            onError: { _ in errorReported = true }
        )
        await task.value

        #expect(!errorReported)
        #expect(!box.hasActiveRequest)
    }

    // MARK: - 3. Image Workflow Client Structured Concurrency & Stress (OPT-B2)

    @Test func imageWorkflowClientStructuredConcurrencyUnderRapidCancellation() async throws {
        // Generate valid 100x100 PNG
        let validPNGData = try Self.makeSampleImageData(width: 100, height: 100, format: .png)
        let sampleURL = URL(fileURLWithPath: "/tmp/sample_\(UUID().uuidString).png")

        let completedCounter = TestLockedCounter(initialValue: 0)
        let cancelledCounter = TestLockedCounter(initialValue: 0)

        // Launch 30 tasks with varied cancellation timings (from 0ms up to 20ms)
        for i in 0..<30 {
            let reader = FakeImageWorkflowReader(
                dataByURL: [sampleURL: validPNGData],
                readDelayByURL: [sampleURL: 0.05]
            )
            let client = ImageWorkflowClient(
                dialog: FakeImageWorkflowDialog(),
                reader: reader,
                writer: FakeImageWorkflowWriter()
            )

            let task = Task {
                do {
                    _ = try await client.prepareSelectionInBackground(from: sampleURL, allowedContentTypes: [UTType.png])
                    completedCounter.increment()
                } catch is CancellationError {
                    cancelledCounter.increment()
                } catch {
                    Issue.record("Unexpected error during rapid cancel test: \(error)")
                }
            }

            if i % 2 == 0 {
                // Rapid cancel
                task.cancel()
            } else {
                // Slightly delayed cancel or let complete
                try await Task.sleep(for: .milliseconds(i % 5))
                if i % 3 == 0 {
                    task.cancel()
                }
            }
            _ = await task.result
        }

        #expect(completedCounter.count + cancelledCounter.count == 30)
        #expect(cancelledCounter.count > 0, "At least some tasks should have observed cancellation")
    }

    @Test func imageWorkflowClientStructuredConcurrencyZeroDeadlockUnderLoad() async throws {
        let validPNGData = try Self.makeSampleImageData(width: 64, height: 64, format: .png)
        let sampleURL = URL(fileURLWithPath: "/tmp/sample_batch_\(UUID().uuidString).png")

        let reader = FakeImageWorkflowReader(
            dataByURL: [sampleURL: validPNGData]
        )
        let client = ImageWorkflowClient(
            dialog: FakeImageWorkflowDialog(),
            reader: reader,
            writer: FakeImageWorkflowWriter()
        )

        // Fire 20 parallel requests concurrently
        var tasks: [Task<Result<ImageInputSelection, Error>, Never>] = []
        for _ in 0..<20 {
            tasks.append(Task { @MainActor in
                do {
                    let sel = try await client.prepareSelectionInBackground(from: sampleURL, allowedContentTypes: [UTType.png])
                    return .success(sel)
                } catch {
                    return .failure(error)
                }
            })
        }

        var results: [Result<ImageInputSelection, Error>] = []
        for t in tasks {
            results.append(await t.value)
        }

        #expect(results.count == 20)
        for r in results {
            guard case .success(let sel) = r else {
                Issue.record("Expected all 20 concurrent tasks to succeed without deadlock")
                continue
            }
            #expect(sel.data == validPNGData)
            #expect(sel.metadata.format == .png)
        }
    }

    // MARK: - 4. BoundedFileReader Edge Cases & Boundaries

    @Test func boundedFileReaderExactByteBoundaries() throws {
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("bounded_test_\(UUID().uuidString).bin")
        let data = Data([0x01, 0x02, 0x03, 0x04, 0x05]) // 5 bytes
        try data.write(to: tempFile)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        // Exact match passes
        #expect(try BoundedFileReader.read(from: tempFile, maxBytes: 5) == data)

        // Generous limit passes
        #expect(try BoundedFileReader.read(from: tempFile, maxBytes: 100) == data)

        // 1 byte short throws tooLarge
        #expect(throws: BoundedFileReader.ReadError.tooLarge) {
            _ = try BoundedFileReader.read(from: tempFile, maxBytes: 4)
        }

        // 0 maxBytes throws tooLarge
        #expect(throws: BoundedFileReader.ReadError.tooLarge) {
            _ = try BoundedFileReader.read(from: tempFile, maxBytes: 0)
        }

        // Negative maxBytes throws tooLarge
        #expect(throws: BoundedFileReader.ReadError.tooLarge) {
            _ = try BoundedFileReader.read(from: tempFile, maxBytes: -1)
        }
    }

    @Test func boundedFileReaderEmptyFile() throws {
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("empty_test_\(UUID().uuidString).bin")
        try Data().write(to: tempFile)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        // Empty file with maxBytes 0 returns empty Data
        let read0 = try BoundedFileReader.read(from: tempFile, maxBytes: 0)
        #expect(read0.isEmpty)

        // Empty file with maxBytes 10 returns empty Data
        let read10 = try BoundedFileReader.read(from: tempFile, maxBytes: 10)
        #expect(read10.isEmpty)
    }

    @Test func boundedFileReaderNonExistentFileThrows() {
        let nonExistent = URL(fileURLWithPath: "/nonexistent_path_\(UUID().uuidString)/file.bin")
        #expect(throws: (any Error).self) {
            _ = try BoundedFileReader.read(from: nonExistent, maxBytes: 1024)
        }
    }

    @Test func imageWorkflowClientRejectsCorruptHeadersGracefully() async throws {
        let corruptPNGData = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00]) // Incomplete/corrupted PNG
        let sampleURL = URL(fileURLWithPath: "/tmp/corrupt_\(UUID().uuidString).png")

        let reader = FakeImageWorkflowReader(
            dataByURL: [sampleURL: corruptPNGData]
        )
        let client = ImageWorkflowClient(
            dialog: FakeImageWorkflowDialog(),
            reader: reader,
            writer: FakeImageWorkflowWriter()
        )

        do {
            _ = try await client.prepareSelectionInBackground(from: sampleURL, allowedContentTypes: [.png])
            Issue.record("Expected corrupt image data to be rejected")
        } catch let err as ImageProcessorError {
            #expect(err == .missingImageProperties)
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    // MARK: - 5. Concrete Struct Seam Equivalence (OPT-B1 & OPT-B2)

    @Test func base64WorkflowProcessingConcreteStructDispatch() async {
        let readCounter = TestLockedCounter()
        let decodeCounter = TestLockedCounter()

        let customProcessor = Base64FileWorkflowProcessing(
            readSelection: { url, _ in
                readCounter.increment()
                return .success(Base64FileSelection(fileName: url.lastPathComponent, data: Data(), mimeType: "text/plain"))
            },
            decodePayload: { _ in
                decodeCounter.increment()
                return .success(Base64Conversion.FilePayload(data: Data(), mimeType: "text/plain", fileExtension: "txt"))
            }
        )

        let session = Base64FileWorkflowSession()
        let readTask = session.readSelectedFile(
            from: URL(fileURLWithPath: "/tmp/custom.txt"),
            processor: customProcessor
        )
        await readTask?.value
        #expect(readCounter.count == 1)

        _ = await customProcessor.decodePayload("dGVzdA==")
        #expect(decodeCounter.count == 1)
    }

    @Test func imageWorkflowClientConcreteStructDispatch() async throws {
        let dialogCounter = TestLockedCounter()
        let fakeDialog = ImageWorkflowDialog(
            selectSaveURL: { name, _ in
                dialogCounter.increment()
                return URL(fileURLWithPath: "/tmp/\(name)")
            }
        )

        let client = ImageWorkflowClient(
            dialog: fakeDialog,
            reader: ImageWorkflowFileReader(),
            writer: ImageWorkflowFileWriter()
        )
        let fakeArtifact = FaviconArtifact(
            id: .faviconICO,
            mediaType: "image/x-icon",
            group: .browser,
            purpose: "test",
            details: "test",
            data: Data([0x01])
        )
        let saved = try await client.saveArtifact(fakeArtifact)
        #expect(saved)
        #expect(dialogCounter.count == 1)
    }

    // MARK: - Helper

    private static func makeSampleImageData(width: Int, height: Int, format: ImageFileFormat) throws -> Data {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            throw ImageProcessorError.renderingFailed
        }
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1.0))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        guard let cgImage = context.makeImage() else {
            throw ImageProcessorError.renderingFailed
        }

        let mutableData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            mutableData,
            format.utTypeIdentifier as CFString,
            1,
            nil
        ) else {
            throw ImageProcessorError.missingImageProperties
        }
        CGImageDestinationAddImage(destination, cgImage, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw ImageProcessorError.missingImageProperties
        }
        return mutableData as Data
    }
}
