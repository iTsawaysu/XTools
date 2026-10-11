import AppKit
import Combine
import XToolsCore
import Foundation
import UniformTypeIdentifiers

@MainActor
struct ImageWorkflowClient {
    static var standardImageContentTypes: [UTType] {
        contentTypes(for: ImageFileFormat.supportedInputFormats)
    }

    static var faviconInputContentTypes: [UTType] {
        contentTypes(for: ImageFileFormat.supportedInputFormats.filter { $0 != .tiff })
    }

    private let dialog: ImageWorkflowDialog
    private let reader: ImageWorkflowFileReader
    private let writer: ImageWorkflowFileWriter

    init(
        dialog: ImageWorkflowDialog = ImageWorkflowDialog(),
        reader: ImageWorkflowFileReader = ImageWorkflowFileReader(),
        writer: ImageWorkflowFileWriter = ImageWorkflowFileWriter()
    ) {
        self.dialog = dialog
        self.reader = reader
        self.writer = writer
    }

    static func sheet(filePanel: FileInputPanelClient, outputPanel: FileOutputPanelClient) -> ImageWorkflowClient {
        ImageWorkflowClient(dialog: .sheet(filePanel: filePanel, outputPanel: outputPanel))
    }

    func prepareSelectionInBackground(
        from url: URL,
        allowedContentTypes: [UTType]
    ) async throws -> ImageInputSelection {
        let reader = self.reader
        let work = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            let prepared = try Self.prepareSelectionData(
                from: url,
                allowedContentTypes: allowedContentTypes,
                reader: reader
            )
            try Task.checkCancellation()
            return prepared
        }

        do {
            let prepared = try await withTaskCancellationHandler {
                try await work.value
            } onCancel: {
                work.cancel()
            }
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

    /// 批量导入用轻量变体：复用单张的校验/inspect/preview 管线，
    /// 返回边界处即丢弃原图 data，只留元数据与预览字节。
    func prepareImportOverview(
        from url: URL,
        allowedContentTypes: [UTType]
    ) async throws -> ImageImportOverview {
        let selection = try await prepareSelectionInBackground(from: url, allowedContentTypes: allowedContentTypes)
        return ImageImportOverview(metadata: selection.metadata, previewData: selection.previewData)
    }

    nonisolated private static func prepareSelectionData(
        from url: URL,
        allowedContentTypes: [UTType],
        reader: ImageWorkflowFileReader
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
        return try await save(
            data: { output.data },
            defaultFilename: "\(defaultBasename).\(output.format.fileExtension)",
            allowedContentTypes: [Self.utType(for: output.format)]
        )
    }

    func saveArtifact(_ artifact: FaviconArtifact) async throws -> Bool {
        try await save(
            data: { artifact.data },
            defaultFilename: artifact.filename,
            allowedContentTypes: [Self.contentType(for: artifact)]
        )
    }

    func saveArtifacts(_ artifacts: [FaviconArtifact]) async throws -> Bool {
        try await saveAll(artifacts, prompt: "选择 Favicon 部署包保存目录") { artifact, _, _ in
            (artifact.data, artifact.filename)
        }
    }

    /// 单张转换结果保存：conversion 没有"不得大于原图"的闸（canSave 恒真），
    /// 直接走保存面板与写入，不做 assessment 拦截。
    func saveConvertedImage(
        data: Data,
        format: ImageFileFormat,
        defaultBasename: String
    ) async throws -> Bool {
        try await save(
            data: { data },
            defaultFilename: "\(defaultBasename).\(format.fileExtension)",
            allowedContentTypes: [Self.utType(for: format)]
        )
    }

    func saveConvertedImage(
        at tempURL: URL,
        format: ImageFileFormat,
        defaultBasename: String
    ) async throws -> Bool {
        // Capture the accepted single-file result before showing the panel,
        // preserving save even if the workspace is reset while it is open.
        guard !Task.isCancelled else { return false }
        let snapshot = ConvertedImageSaveSnapshot(.init(
            basename: defaultBasename, tempURL: tempURL, format: format
        ))
        let read = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            return try snapshot.readData()
        }
        let result: Result<Bool, Error>
        do {
            let data = try await withTaskCancellationHandler {
                try await read.value
            } onCancel: {
                read.cancel()
            }
            result = .success(try await saveConvertedImage(data: data, format: format, defaultBasename: defaultBasename))
        } catch is CancellationError {
            result = .success(false)
        } catch {
            result = .failure(ImageWorkflowFailure.saveFailed)
        }
        await Task.detached { snapshot.close() }.value
        return try result.get()
    }

    /// 批量保存转换结果：先固定临时文件，再选目录逐张读取并写入
    /// `原名(去扩展).目标扩展`，目录内同名冲突自动追加 " 2"、" 3"…（含本批
    /// 已写入的文件），不覆盖；读取与写入失败均按该张失败计，沿用
    /// partialSaveFailed 语义。临时文件由批量会话写出，不走输入预算的
    /// reader 管线（输出可能合理地超过输入预算）。
    func saveConvertedImages(_ candidates: [BatchConversionSaveCandidate]) async throws -> Bool {
        guard !Task.isCancelled else { return false }
        // Pin session-owned local spool inodes before the first suspension:
        // reset/re-conversion may unlink paths as soon as MainActor yields.
        // Only descriptor opens happen here; image bytes stay on the worker.
        let snapshots = candidates.map(ConvertedImageSaveSnapshot.init)

        let result: Result<Bool, Error>
        do {
            result = .success(try await saveAll(
                snapshots,
                prompt: "保存",
                message: "已转换的 \(candidates.count) 张图片将保存到所选文件夹"
            ) { snapshot, directory, reservedFilenames in
                let data = try snapshot.readData()
                let url = Self.uniqueConvertedImageURL(
                    in: directory,
                    basename: snapshot.candidate.basename,
                    format: snapshot.candidate.format,
                    reservedFilenames: reservedFilenames
                )
                reservedFilenames.insert(url.lastPathComponent)
                return (data, url.lastPathComponent)
            })
        } catch {
            result = .failure(error)
        }
        // Await cleanup even on panel cancellation or partial failure. Reads,
        // writes and closes never overlap, and no output bytes remain resident.
        await Task.detached { snapshots.forEach { $0.close() } }.value
        return try result.get()
    }

    /// 查重含目录内既有文件与本批已占用的名字（写入可能经缓冲 seam，
    /// 不能假设上一张已落盘），冲突时追加 " 2"、" 3"…，不覆盖。
    nonisolated private static func uniqueConvertedImageURL(
        in directory: URL,
        basename: String,
        format: ImageFileFormat,
        reservedFilenames: Set<String>
    ) -> URL {
        let stem = basename.isEmpty ? "converted" : basename
        let filename = "\(stem).\(format.fileExtension)"
        var url = directory.appendingPathComponent(filename)
        var index = 2
        while reservedFilenames.contains(url.lastPathComponent)
            || FileManager.default.fileExists(atPath: url.path) {
            url = directory.appendingPathComponent("\(stem) \(index).\(format.fileExtension)")
            index += 1
        }
        return url
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

    /// 单文件保存的共享骨架：保存面板取消返回 false（静默取消），写入失败
    /// 统一抛 saveFailed。
    private func save(
        data: @escaping @Sendable () throws -> Data,
        defaultFilename: String,
        allowedContentTypes: [UTType]
    ) async throws -> Bool {
        guard !Task.isCancelled,
              let url = await dialog.selectSaveURL(
                defaultFilename: defaultFilename,
                allowedContentTypes: allowedContentTypes
              ), !Task.isCancelled else {
            return false
        }

        let writer = self.writer
        let work = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            let bytes = try data()
            try Task.checkCancellation()
            try writer.write(bytes, to: url)
        }
        do {
            try await withTaskCancellationHandler {
                try await work.value
            } onCancel: {
                work.cancel()
            }
            return true
        } catch is CancellationError {
            return false
        } catch {
            throw ImageWorkflowFailure.saveFailed
        }
    }

    /// One serial background operation owns reads, collision names and writes;
    /// partial failure reports the files actually written before it stopped.
    private func saveAll<Item: Sendable>(
        _ items: [Item],
        prompt: String,
        message: String? = nil,
        item: @escaping @Sendable (Item, URL, inout Set<String>) throws -> (data: Data, filename: String)
    ) async throws -> Bool {
        guard !Task.isCancelled,
              let directory = await dialog.selectDirectory(prompt: prompt, message: message),
              !Task.isCancelled else {
            return false
        }

        let writer = self.writer
        let work = Task.detached(priority: .userInitiated) {
            var savedCount = 0
            var reservedFilenames: Set<String> = []
            do {
                for element in items {
                    try Task.checkCancellation()
                    let (data, filename) = try item(element, directory, &reservedFilenames)
                    try Task.checkCancellation()
                    try writer.write(data, to: directory.appendingPathComponent(filename))
                    savedCount += 1
                }
            } catch {
                if savedCount > 0 {
                    throw ImageWorkflowFailure.partialSaveFailed(savedCount: savedCount, totalCount: items.count)
                }
                if error is CancellationError { throw error }
                throw ImageWorkflowFailure.saveFailed
            }
        }
        do {
            try await withTaskCancellationHandler {
                try await work.value
            } onCancel: {
                work.cancel()
            }
            return true
        } catch is CancellationError {
            return false
        }
    }
}

/// A read-only descriptor pins the accepted inode across atomic re-conversion
/// and reset. At most one descriptor per candidate is held; bytes are read one
/// image at a time. MainActor opens descriptors before suspension; ownership
/// then moves to the serial worker and awaited cleanup, never concurrently.
private final class ConvertedImageSaveSnapshot: @unchecked Sendable {
    let candidate: BatchConversionSaveCandidate
    private var handle: FileHandle?

    init(_ candidate: BatchConversionSaveCandidate) {
        self.candidate = candidate
        // Keep a failed open in its original position: preceding valid images
        // still save, then the existing partial-success contract reports it.
        handle = try? FileHandle(forReadingFrom: candidate.tempURL)
    }

    func readData() throws -> Data {
        guard let handle else { throw ImageWorkflowFailure.saveFailed }
        return try handle.readToEnd() ?? Data()
    }

    func close() {
        try? handle?.close()
        handle = nil
    }

    deinit {
        try? handle?.close()
    }
}
