import AppKit
import Darwin
import Foundation
import SwiftUI
import os
import Testing
import UniformTypeIdentifiers
@testable import XToolsCore
@testable import XTools

@MainActor
@Suite(.serialized)
struct ImageExportConcurrencyTests {
    @Test(arguments: [1, 2])
    func panelResetPreservesPinnedSingleAndBatchBytes(count: Int) async throws {
        let directory = try artifactDirectory()
        let accepted = Data([0x13, 0x27, 0x42])
        let probe = SavePanelResetProbe()
        let session = try await completedSession(count: count, output: accepted) { _, _ in
            ImageWorkflowClient(dialog: ImageWorkflowDialog(
                selectSaveURL: { _, _ in
                    await probe.resetFromPanel()
                    return directory.appendingPathComponent("converted.png")
                },
                selectDirectory: { _, _ in
                    await probe.resetFromPanel()
                    return directory
                }
            ))
        }
        probe.session = session
        probe.paths = session.items.compactMap { item in
            guard case let .done(output) = item.state else { return nil }
            return output.tempURL
        }
        #expect(await save(session) == .saved)
        #expect(probe.panelCount == 1)
        #expect(probe.descriptorsBeforeReset == Array(repeating: 1, count: count))
        #expect(session.items.isEmpty)
        #expect(!session.isSaving)
        #expect(probe.paths.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) })
        // /dev/fd can no longer stat unlinked paths: retain their inode identity
        // before reset and compare descriptors against it after save returns.
        #expect(try probe.openDescriptorsAfterSave() == 0)
        for index in 0..<count {
            let name = count == 1 ? "converted.png" : "source-\(index).png"
            #expect(try Data(contentsOf: directory.appendingPathComponent(name)) == accepted)
        }
        probe.session = nil
    }

    @Test func sessionRejectsAnotherSaveWhileItsWriterIsSuspended() async throws {
        let directory = try artifactDirectory()
        let gate = DispatchSemaphore(value: 0)
        defer { gate.signal() }
        let calls = OSAllocatedUnfairLock(initialState: 0)
        let panelCount = OSAllocatedUnfairLock(initialState: 0)
        let session = try await completedSession(count: 1, output: Data([1, 2, 3])) { _, _ in
            ImageWorkflowClient(
                dialog: ImageWorkflowDialog(selectSaveURL: { _, _ in
                    panelCount.withLock { $0 += 1 }
                    return directory.appendingPathComponent("result.png")
                }),
                writer: ImageWorkflowFileWriter { data, url in
                    let count = calls.withLock { $0 += 1; return $0 }
                    if count == 1 {
                        guard gate.wait(timeout: .now() + 10) == .success else { throw CocoaError(.fileWriteUnknown) }
                    }
                    try data.write(to: url)
                }
            )
        }
        let first = Task { await save(session) }
        try await waitUntil { calls.withLock { $0 } == 1 }
        #expect(session.isSaving)
        #expect(await save(session) == .cancelled)
        #expect(panelCount.withLock { $0 } == 1)
        #expect(calls.withLock { $0 } == 1)
        gate.signal()
        #expect(await first.value == .saved)
        #expect(!session.isSaving)
        #expect(try Data(contentsOf: directory.appendingPathComponent("result.png")) == Data([1, 2, 3]))
    }

    @Test func batchSaveKeepsAcceptedBytesAcrossReconversionAndReset() async throws {
        let directory = try artifactDirectory()
        let gate = DispatchSemaphore(value: 0)
        defer { gate.signal() }
        let calls = OSAllocatedUnfairLock(initialState: 0)
        let accepted = Data([1, 2, 3])
        let replacement = Data([8, 9])
        let session = try await completedSession(count: 2, output: accepted) { _, _ in
            ImageWorkflowClient(
                dialog: ImageWorkflowDialog(selectDirectory: { _, _ in directory }),
                writer: ImageWorkflowFileWriter { data, url in
                    let count = calls.withLock { $0 += 1; return $0 }
                    if count == 1 {
                        guard gate.wait(timeout: .now() + 10) == .success else { throw CocoaError(.fileWriteUnknown) }
                    }
                    try data.write(to: url)
                }
            )
        }
        let acceptedPaths = session.items.compactMap { item -> URL? in
            guard case let .done(output) = item.state else { return nil }
            return output.tempURL
        }
        let saving = Task { await save(session) }
        try await waitUntil { calls.withLock { $0 } == 1 }
        session.convertAll(rendererProvider: { { input in
            ProcessedImage(data: replacement, format: .png, pixelWidth: 1, pixelHeight: 1,
                           originalByteCount: input.data.count, quality: nil, wasResized: false)
        } })
        try await waitUntil { !session.isProcessing && session.completedCount == 2 }
        for item in session.items {
            guard case let .done(output) = item.state else { Issue.record("Expected replacement output"); continue }
            #expect(!acceptedPaths.contains(output.tempURL))
            #expect(try Data(contentsOf: output.tempURL) == replacement)
        }
        #expect(acceptedPaths.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) })
        #expect(try FileManager.default.contentsOfDirectory(atPath: session.spoolDirectory.path).count == 2)
        session.reset()
        #expect(session.items.isEmpty)
        #expect(session.isSaving)
        #expect(await save(session) == .cancelled)
        gate.signal()
        #expect(await saving.value == .saved)
        #expect(!session.isSaving)
        #expect(try Data(contentsOf: directory.appendingPathComponent("source-0.png")) == accepted)
        #expect(try Data(contentsOf: directory.appendingPathComponent("source-1.png")) == accepted)
    }

    @Test(arguments: [1, 2])
    func cancellationAfterWritingReportsTheActualSavedCount(stoppingAfter: Int) async throws {
        let directory = try artifactDirectory()
        let gate = DispatchSemaphore(value: 0)
        defer { gate.signal() }
        let writes = OSAllocatedUnfairLock(initialState: 0)
        let candidates = try (1...2).map { index in
            let source = directory.appendingPathComponent("source-\(index).bin")
            try Data([UInt8(index)]).write(to: source)
            return BatchConversionSaveCandidate(basename: "result-\(index)", tempURL: source, format: .png)
        }
        let client = ImageWorkflowClient(
            dialog: ImageWorkflowDialog(selectDirectory: { _, _ in directory }),
            writer: ImageWorkflowFileWriter { data, url in
                try data.write(to: url)
                let count = writes.withLock { $0 += 1; return $0 }
                if count == stoppingAfter {
                    guard gate.wait(timeout: .now() + 10) == .success else { throw CocoaError(.fileWriteUnknown) }
                }
            }
        )
        let task = Task { try await client.saveConvertedImages(candidates) }
        try await waitUntil { writes.withLock { $0 } == stoppingAfter }
        task.cancel()
        gate.signal()
        do {
            let saved = try await task.value
            #expect(stoppingAfter == 2)
            #expect(saved)
        } catch let failure as ImageWorkflowFailure {
            #expect(stoppingAfter == 1)
            #expect(failure == .partialSaveFailed(savedCount: 1, totalCount: 2))
        }
        #expect(writes.withLock { $0 } == stoppingAfter)
        for index in 1...stoppingAfter {
            #expect(try Data(contentsOf: directory.appendingPathComponent("result-\(index).png")) == Data([UInt8(index)]))
        }
        if stoppingAfter == 1 {
            #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("result-2.png").path))
        }
        for candidate in candidates {
            #expect(try Self.openDescriptorCount(for: candidate.tempURL) == 0)
        }
    }

    @Test func failedSnapshotOpenPreservesPartialSuccessAndClosesDescriptors() async throws {
        let directory = try artifactDirectory()
        let source = directory.appendingPathComponent("source.bin")
        try Data([4, 5]).write(to: source)
        let missing = directory.appendingPathComponent("missing.bin")
        let client = ImageWorkflowClient(dialog: ImageWorkflowDialog(selectDirectory: { _, _ in directory }))
        let candidates = [
            BatchConversionSaveCandidate(basename: "first", tempURL: source, format: .png),
            BatchConversionSaveCandidate(basename: "missing", tempURL: missing, format: .png),
            BatchConversionSaveCandidate(basename: "third", tempURL: source, format: .png)
        ]
        do {
            _ = try await client.saveConvertedImages(candidates)
            Issue.record("Expected the second snapshot to fail")
        } catch let failure as ImageWorkflowFailure {
            #expect(failure == .partialSaveFailed(savedCount: 1, totalCount: 3))
        }
        #expect(try Data(contentsOf: directory.appendingPathComponent("first.png")) == Data([4, 5]))
        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("third.png").path))
        #expect(try Self.openDescriptorCount(for: source) == 0)
    }

    @Test func cancelledBatchPanelClosesEveryPinnedDescriptor() async throws {
        let directory = try artifactDirectory()
        let source = directory.appendingPathComponent("source.bin")
        try Data([1]).write(to: source)
        let descriptorCountInPanel = OSAllocatedUnfairLock(initialState: 0)
        let client = ImageWorkflowClient(dialog: ImageWorkflowDialog(selectDirectory: { _, _ in
            let count = (try? Self.openDescriptorCount(for: source)) ?? -1
            descriptorCountInPanel.withLock { $0 = count }
            return nil
        }))
        let candidate = BatchConversionSaveCandidate(basename: "image", tempURL: source, format: .png)
        #expect(try await client.saveConvertedImages([candidate, candidate]) == false)
        #expect(descriptorCountInPanel.withLock { $0 } == 2)
        #expect(try Self.openDescriptorCount(for: source) == 0)
    }

    @Test func singleAndSpoolSavesWriteActualBytesOffMainThread() async throws {
        let directory = try artifactDirectory()
        let source = directory.appendingPathComponent("source.bin")
        let output = directory.appendingPathComponent("result.png")
        let data = Data(repeating: 0xAB, count: 256 * 1024)
        try data.write(to: source)
        let threads = OSAllocatedUnfairLock(initialState: [Bool]())
        let client = ImageWorkflowClient(
            dialog: ImageWorkflowDialog(selectSaveURL: { _, _ in output }),
            writer: ImageWorkflowFileWriter { bytes, url in
                threads.withLock { $0.append(Thread.isMainThread) }
                try bytes.write(to: url)
            }
        )
        #expect(try await client.saveConvertedImage(at: source, format: .png, defaultBasename: "result"))
        #expect(try Data(contentsOf: output) == data)
        #expect(try await client.saveConvertedImage(data: Data([1, 2, 3]), format: .png, defaultBasename: "result"))
        #expect(try Data(contentsOf: output) == Data([1, 2, 3]))
        #expect(threads.withLock { $0 } == [false, false])
    }

    @Test func batchNamesAndPartialFailureStaySerialOnBackgroundWriter() async throws {
        let directory = try artifactDirectory()
        let source = directory.appendingPathComponent("source.bin")
        try Data([3, 4, 5]).write(to: source)
        try Data([9]).write(to: directory.appendingPathComponent("image.png"))
        let writes = OSAllocatedUnfairLock(initialState: [(String, Bool)]())
        let client = ImageWorkflowClient(
            dialog: ImageWorkflowDialog(selectDirectory: { _, _ in directory }),
            writer: ImageWorkflowFileWriter { data, url in
                let index = writes.withLock { state in
                    state.append((url.lastPathComponent, Thread.isMainThread))
                    return state.count
                }
                if index == 3 { throw CocoaError(.fileWriteUnknown) }
                try data.write(to: url)
            }
        )
        let candidate = BatchConversionSaveCandidate(basename: "image", tempURL: source, format: .png)
        do {
            _ = try await client.saveConvertedImages([candidate, candidate, candidate])
            Issue.record("Expected the third write to fail")
        } catch let failure as ImageWorkflowFailure {
            #expect(failure == .partialSaveFailed(savedCount: 2, totalCount: 3))
        }
        #expect(writes.withLock { $0.map(\.0) } == ["image 2.png", "image 3.png", "image 4.png"])
        #expect(writes.withLock { $0.allSatisfy { !$0.1 } })
        #expect(try Data(contentsOf: directory.appendingPathComponent("image.png")) == Data([9]))
        #expect(try Data(contentsOf: directory.appendingPathComponent("image 3.png")) == Data([3, 4, 5]))
    }

    @Test func cancelledSelectionNeverStartsWriter() async {
        let writes = OSAllocatedUnfairLock(initialState: 0)
        let client = ImageWorkflowClient(
            dialog: ImageWorkflowDialog(selectSaveURL: { _, _ in
                try? await Task.sleep(for: .seconds(1))
                return URL(fileURLWithPath: "/unreachable-cancelled-output.png")
            }),
            writer: ImageWorkflowFileWriter { _, _ in writes.withLock { $0 += 1 } }
        )
        let task = Task { try await client.saveConvertedImage(data: Data([1]), format: .png, defaultBasename: "cancelled") }
        task.cancel()
        #expect((try? await task.value) == false)
        #expect(writes.withLock { $0 } == 0)
    }

    @Test func compressorRecipeEditKeepsAcceptedPendingSelection() async throws {
        let repository = ToolWorkspaceRepository(defaults: UserDefaults(suiteName: "CompressorPending.\(UUID())")!)
        let workspace = repository.model(for: ImageCompressorToolWorkspaceModel.key)
        let host = NSHostingView(rootView: IndexImageCompressorSegment().environmentObject(repository))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 700), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFront(nil)
        defer { window.close() }
        for _ in 0..<5 { host.layoutSubtreeIfNeeded(); try await Task.sleep(for: .milliseconds(20)) }
        let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let data = try #require(bitmap.representation(using: .png, properties: [:]))
        let gate = DispatchSemaphore(value: 0)
        let started = OSAllocatedUnfairLock(initialState: false)
        let client = ImageWorkflowClient(reader: ImageWorkflowFileReader(
            isRegularFile: { _ in true }, byteCount: { _ in data.count },
            readDataWithLimit: { _, _ in
                started.withLock { $0 = true }
                _ = gate.wait(timeout: .now() + 3)
                return data
            }
        ))
        defer { gate.signal() }
        let url = URL(fileURLWithPath: "/pending-compressor.png")
        workspace.session.receiveImageURL(url, allowedContentTypes: [.png], client: client, operation: .compression,
            renderProvider: {
                let maximum = workspace.maxPixelLength
                return { input in
                    ProcessedImage(data: input.data, format: .png, pixelWidth: maximum, pixelHeight: 1, originalByteCount: input.data.count, quality: nil, wasResized: false)
                }
            }, render: { _ in throw CocoaError(.fileReadUnknown) }
        )
        for _ in 0..<100 {
            if started.withLock({ $0 }) { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        try #require(started.withLock { $0 })
        workspace.limitsDimensions = true
        workspace.maxPixelLength = 640
        for _ in 0..<5 { host.layoutSubtreeIfNeeded(); try await Task.sleep(for: .milliseconds(20)) }
        #expect(workspace.session.isProcessing)
        gate.signal()
        for _ in 0..<200 {
            if !workspace.session.isProcessing { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(workspace.session.sourceURL == url)
        #expect(workspace.session.output?.pixelWidth == 640)
    }

    private func artifactDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("xtools-export-regression-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func completedSession(
        count: Int,
        output: Data,
        saveClientBuilder: @escaping ImageSaveClientBuilder
    ) async throws -> ImageBatchConversionSession {
        let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let data = try #require(bitmap.representation(using: .png, properties: [:]))
        let session = ImageBatchConversionSession(saveClientBuilder: saveClientBuilder)
        session.receiveImageURLs((0..<count).map { URL(fileURLWithPath: "/source-\($0).png") },
            allowedContentTypes: [.png], client: ImageWorkflowClient(reader: .constant(data: data)))
        try await waitUntil { !session.isImporting && session.items.count == count }
        session.convertAll(rendererProvider: { { input in
            ProcessedImage(data: output, format: .png, pixelWidth: 1, pixelHeight: 1,
                           originalByteCount: input.data.count, quality: nil, wasResized: false)
        } })
        try await waitUntil { !session.isProcessing && session.completedCount == count }
        return session
    }

    private func save(_ session: ImageBatchConversionSession) async -> ImageSaveOutcome {
        await session.saveAll(defaultBasename: "converted", filePanel: .unavailable,
                              outputPanel: FileOutputPanelClient { _ in nil })
    }

    private func waitUntil(_ predicate: () -> Bool) async throws {
        for _ in 0..<300 {
            if predicate() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        try #require(predicate())
    }

    nonisolated private static func openDescriptorCount(for url: URL) throws -> Int {
        var target = stat()
        guard stat(url.path, &target) == 0 else { throw CocoaError(.fileReadUnknown) }
        return try FileManager.default.contentsOfDirectory(atPath: "/dev/fd").compactMap(Int32.init).count { descriptor in
            var candidate = stat()
            return fstat(descriptor, &candidate) == 0 && candidate.st_ino == target.st_ino && candidate.st_dev == target.st_dev
        }
    }
}

@MainActor
private final class SavePanelResetProbe {
    var session: ImageBatchConversionSession?
    var paths: [URL] = []
    var panelCount = 0
    var descriptorsBeforeReset: [Int] = []
    private var identities: [(dev_t, ino_t)] = []

    func resetFromPanel() {
        panelCount += 1
        do {
            identities = try paths.map { url in
                var value = stat()
                guard stat(url.path, &value) == 0 else { throw CocoaError(.fileReadUnknown) }
                return (value.st_dev, value.st_ino)
            }
            descriptorsBeforeReset = try identities.map { identity in
                try descriptorCount(matching: [identity])
            }
        } catch {
            Issue.record("Unable to inspect accepted spool descriptors: \(error)")
        }
        session?.reset()
    }

    func openDescriptorsAfterSave() throws -> Int {
        try descriptorCount(matching: identities)
    }

    private func descriptorCount(matching identities: [(dev_t, ino_t)]) throws -> Int {
        try FileManager.default.contentsOfDirectory(atPath: "/dev/fd").compactMap(Int32.init).count { descriptor in
            var value = stat()
            return fstat(descriptor, &value) == 0
                && identities.contains { $0.0 == value.st_dev && $0.1 == value.st_ino }
        }
    }
}
