import AppKit
import Combine
import XToolsCore
import Foundation
import UniformTypeIdentifiers

private final class ImagePreparationCancellationGate: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<PreparedImageInputSelection, Error>?
    private var cancelWork: (() -> Void)?
    private var isFinished = false

    func install(_ continuation: CheckedContinuation<PreparedImageInputSelection, Error>) {
        lock.lock()
        if isFinished {
            lock.unlock()
            continuation.resume(throwing: CancellationError())
            return
        }
        self.continuation = continuation
        lock.unlock()
    }

    func registerCancellation(_ cancel: @escaping () -> Void) {
        lock.lock()
        guard !isFinished else {
            lock.unlock()
            cancel()
            return
        }
        cancelWork = cancel
        lock.unlock()
    }

    func succeed(_ value: PreparedImageInputSelection) {
        finish { $0.resume(returning: value) }
    }

    func fail(_ error: Error) {
        finish { $0.resume(throwing: error) }
    }

    func cancel() {
        finish { $0.resume(throwing: CancellationError()) }
    }

    private func finish(_ resume: (CheckedContinuation<PreparedImageInputSelection, Error>) -> Void) {
        lock.lock()
        guard !isFinished else {
            lock.unlock()
            return
        }
        isFinished = true
        let continuation = self.continuation
        self.continuation = nil
        let cancelWork = self.cancelWork
        self.cancelWork = nil
        lock.unlock()
        cancelWork?()
        if let continuation {
            resume(continuation)
        }
    }
}

@MainActor
struct ImageWorkflowClient {
    static var standardImageContentTypes: [UTType] {
        contentTypes(for: ImageFileFormat.supportedInputFormats)
    }

    static var faviconInputContentTypes: [UTType] {
        contentTypes(for: ImageFileFormat.supportedInputFormats.filter { $0 != .tiff })
    }

    private let dialog: any ImageWorkflowDialoging
    private let reader: any ImageWorkflowFileReading
    private let writer: any ImageWorkflowFileWriting

    init(
        dialog: any ImageWorkflowDialoging = NoOpImageWorkflowDialog(),
        reader: any ImageWorkflowFileReading = FoundationImageWorkflowFileReader(),
        writer: any ImageWorkflowFileWriting = FoundationImageWorkflowFileWriter()
    ) {
        self.dialog = dialog
        self.reader = reader
        self.writer = writer
    }

    func prepareSelectionInBackground(
        from url: URL,
        allowedContentTypes: [UTType]
    ) async throws -> ImageInputSelection {
        let reader = self.reader
        let gate = ImagePreparationCancellationGate()

        do {
            let prepared = try await withTaskCancellationHandler(operation: {
                try await withCheckedThrowingContinuation {
                    (continuation: CheckedContinuation<PreparedImageInputSelection, Error>) in
                    gate.install(continuation)
                    let work = Task.detached(priority: .userInitiated) {
                        do {
                            try Task.checkCancellation()
                            let prepared = try Self.prepareSelectionData(
                                from: url,
                                allowedContentTypes: allowedContentTypes,
                                reader: reader
                            )
                            try Task.checkCancellation()
                            gate.succeed(prepared)
                        } catch {
                            gate.fail(error)
                        }
                    }
                    gate.registerCancellation { work.cancel() }
                }
            }, onCancel: {
                gate.cancel()
            })
            try Task.checkCancellation()
            return try makeSelection(from: url, prepared: prepared)
        } catch is CancellationError {
            throw CancellationError()
        } catch let failure as ImageWorkflowFailure {
            throw failure
        } catch let processorError as ImageProcessorError {
            throw processorError
        } catch {
            throw ImageWorkflowFailure.readFailed
        }
    }

    private func makeSelection(from url: URL, prepared: PreparedImageInputSelection) throws -> ImageInputSelection {
        guard let image = NSImage(data: prepared.previewData) else {
            throw ImageWorkflowFailure.unreadableImage
        }

        return ImageInputSelection(
            data: prepared.data,
            previewData: prepared.previewData,
            image: image,
            url: url,
            metadata: prepared.metadata
        )
    }

    nonisolated private static func prepareSelectionData(
        from url: URL,
        allowedContentTypes: [UTType],
        reader: any ImageWorkflowFileReading
    ) throws -> PreparedImageInputSelection {
        let accessedSecurityScope = url.startAccessingSecurityScopedResource()
        defer {
            if accessedSecurityScope {
                url.stopAccessingSecurityScopedResource()
            }
        }

        guard try reader.isRegularFile(at: url) else {
            throw ImageWorkflowFailure.notRegularFile
        }
        if let byteCount = try reader.byteCount(for: url) {
            try ImageProcessingBudget.validateInputByteCount(byteCount)
        }
        let data = try reader.readData(from: url)
        try ImageProcessingBudget.validateInputByteCount(data.count)
        let metadata = try ImageProcessor.inspect(data: data, filenameExtension: url.pathExtension)
        guard let format = metadata.format,
              let actualContentType = UTType(format.utTypeIdentifier),
              allowedContentTypes.contains(where: { actualContentType.conforms(to: $0) }) else {
            throw ImageWorkflowFailure.unsupportedInputType
        }
        let previewData = try ImageProcessor.previewImageData(data: data)
        return PreparedImageInputSelection(
            data: data,
            metadata: metadata,
            previewData: previewData
        )
    }

    func saveProcessedImage(
        _ output: ProcessedImage,
        assessment: ImageOutputAssessment,
        defaultBasename: String
    ) async throws -> Bool {
        guard assessment.canSave else {
            throw ImageWorkflowFailure.blockedCompressionSave
        }
        return try await writeProcessedImageAfterSavePanel(output, defaultBasename: defaultBasename)
    }

    func saveArtifact(_ artifact: FaviconArtifact) async throws -> Bool {
        let contentType = Self.contentType(for: artifact)
        guard let url = await dialog.selectSaveURL(
            defaultFilename: artifact.filename,
            allowedContentTypes: [contentType]
        ) else {
            return false
        }

        do {
            try writer.write(artifact.data, to: url)
            return true
        } catch {
            throw ImageWorkflowFailure.saveFailed
        }
    }

    func saveArtifacts(_ artifacts: [FaviconArtifact]) async throws -> Bool {
        guard let directory = await dialog.selectDirectory(prompt: "选择 Favicon 部署包保存目录") else {
            return false
        }

        var savedCount = 0
        do {
            for artifact in artifacts {
                try writer.write(artifact.data, to: directory.appendingPathComponent(artifact.filename))
                savedCount += 1
            }
            return true
        } catch {
            if savedCount > 0 {
                throw ImageWorkflowFailure.partialSaveFailed(
                    savedCount: savedCount,
                    totalCount: artifacts.count
                )
            }
            throw ImageWorkflowFailure.saveFailed
        }
    }

    func saveIcon(_ icon: GeneratedIcon, defaultFilename: String) async throws -> Bool {
        guard let url = await dialog.selectSaveURL(defaultFilename: defaultFilename, allowedContentTypes: [.png]) else {
            return false
        }

        do {
            try writer.write(icon.data, to: url)
            return true
        } catch {
            throw ImageWorkflowFailure.saveFailed
        }
    }

    func saveIcons(_ icons: [GeneratedIcon], filename: (GeneratedIcon) -> String) async throws -> Bool {
        guard let directory = await dialog.selectDirectory(prompt: "选择保存目录") else {
            return false
        }

        // Report partial progress: if the Nth write fails, N-1 files are already
        // on disk. A bare "save failed" would hide those, so the message names
        // how many succeeded before the failure.
        var savedCount = 0
        do {
            for icon in icons {
                try writer.write(icon.data, to: directory.appendingPathComponent(filename(icon)))
                savedCount += 1
            }
            return true
        } catch {
            if savedCount > 0 {
                throw ImageWorkflowFailure.partialSaveFailed(
                    savedCount: savedCount,
                    totalCount: icons.count
                )
            }
            throw ImageWorkflowFailure.saveFailed
        }
    }

    private static func utType(for format: ImageFileFormat) -> UTType {
        UTType(format.utTypeIdentifier) ?? .data
    }

    private static func contentType(for artifact: FaviconArtifact) -> UTType {
        UTType(mimeType: artifact.mediaType)
            ?? UTType(filenameExtension: (artifact.filename as NSString).pathExtension)
            ?? .data
    }

    private static func contentTypes(for formats: [ImageFileFormat]) -> [UTType] {
        formats.compactMap { UTType($0.utTypeIdentifier) }
    }

    private func writeProcessedImageAfterSavePanel(
        _ output: ProcessedImage,
        defaultBasename: String
    ) async throws -> Bool {
        let defaultFilename = "\(defaultBasename).\(output.format.fileExtension)"
        guard let url = await dialog.selectSaveURL(
            defaultFilename: defaultFilename,
            allowedContentTypes: [Self.utType(for: output.format)]
        ) else {
            return false
        }

        do {
            try writer.write(output.data, to: url)
            return true
        } catch {
            throw ImageWorkflowFailure.saveFailed
        }
    }
}
