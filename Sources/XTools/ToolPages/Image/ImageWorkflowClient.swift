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
        return try await save(
            data: output.data,
            defaultFilename: "\(defaultBasename).\(output.format.fileExtension)",
            allowedContentTypes: [Self.utType(for: output.format)]
        )
    }

    func saveArtifact(_ artifact: FaviconArtifact) async throws -> Bool {
        try await save(
            data: artifact.data,
            defaultFilename: artifact.filename,
            allowedContentTypes: [Self.contentType(for: artifact)]
        )
    }

    func saveArtifacts(_ artifacts: [FaviconArtifact]) async throws -> Bool {
        try await saveAll(artifacts, prompt: "选择 Favicon 部署包保存目录") { artifact, _ in
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
            data: data,
            defaultFilename: "\(defaultBasename).\(format.fileExtension)",
            allowedContentTypes: [Self.utType(for: format)]
        )
    }

    /// 批量保存转换结果：选目录后逐张读取落盘的临时文件并写入
    /// `原名(去扩展).目标扩展`，目录内同名冲突自动追加 " 2"、" 3"…（含本批
    /// 已写入的文件），不覆盖；读取与写入失败均按该张失败计，沿用
    /// partialSaveFailed 语义。临时文件由批量会话写出，不走输入预算的
    /// reader 管线（输出可能合理地超过输入预算）。
    func saveConvertedImages(_ candidates: [BatchConversionSaveCandidate]) async throws -> Bool {
        var reservedFilenames: Set<String> = []
        return try await saveAll(
            candidates,
            prompt: "保存",
            message: "已转换的 \(candidates.count) 张图片将保存到所选文件夹"
        ) { candidate, directory in
            let data = try Data(contentsOf: candidate.tempURL)
            let url = Self.uniqueConvertedImageURL(
                in: directory,
                basename: candidate.basename,
                format: candidate.format,
                reservedFilenames: reservedFilenames
            )
            reservedFilenames.insert(url.lastPathComponent)
            return (data, url.lastPathComponent)
        }
    }

    /// 查重含目录内既有文件与本批已占用的名字（写入可能经缓冲 seam，
    /// 不能假设上一张已落盘），冲突时追加 " 2"、" 3"…，不覆盖。
    private static func uniqueConvertedImageURL(
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

    func saveIcon(_ icon: GeneratedIcon, defaultFilename: String) async throws -> Bool {
        try await save(data: icon.data, defaultFilename: defaultFilename, allowedContentTypes: [.png])
    }

    func saveIcons(_ icons: [GeneratedIcon], filename: @escaping (GeneratedIcon) -> String) async throws -> Bool {
        try await saveAll(icons, prompt: "选择保存目录") { icon, _ in
            (icon.data, filename(icon))
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

    /// 单文件保存的共享骨架：保存面板取消返回 false（静默取消），写入失败
    /// 统一抛 saveFailed。
    private func save(
        data: Data,
        defaultFilename: String,
        allowedContentTypes: [UTType]
    ) async throws -> Bool {
        guard let url = await dialog.selectSaveURL(
            defaultFilename: defaultFilename,
            allowedContentTypes: allowedContentTypes
        ) else {
            return false
        }

        do {
            try writer.write(data, to: url)
            return true
        } catch {
            throw ImageWorkflowFailure.saveFailed
        }
    }

    /// 批量目录保存的共享骨架：选目录后逐项写入；任一项的读取/命名/写入
    /// 失败按该张失败计——已写入 N-1 张时抛 partialSaveFailed（保留部分
    /// 进度事实），否则抛 saveFailed。
    private func saveAll<Item>(
        _ items: [Item],
        prompt: String,
        message: String? = nil,
        item: (Item, URL) throws -> (data: Data, filename: String)
    ) async throws -> Bool {
        guard let directory = await dialog.selectDirectory(prompt: prompt, message: message) else {
            return false
        }

        var savedCount = 0
        do {
            for element in items {
                let (data, filename) = try item(element, directory)
                try writer.write(data, to: directory.appendingPathComponent(filename))
                savedCount += 1
            }
            return true
        } catch {
            if savedCount > 0 {
                throw ImageWorkflowFailure.partialSaveFailed(
                    savedCount: savedCount,
                    totalCount: items.count
                )
            }
            throw ImageWorkflowFailure.saveFailed
        }
    }
}
