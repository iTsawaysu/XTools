import AppKit
import Combine
import XToolsCore
import Foundation
import UniformTypeIdentifiers

struct ImageInputSelection {
    let data: Data
    let previewData: Data
    let image: NSImage
    let url: URL
    let metadata: ImageMetadata

    var filenameExtension: String? {
        let value = url.pathExtension
        return value.isEmpty ? nil : value
    }
}

struct ImageProcessingInput: Sendable {
    let data: Data
    let filenameExtension: String?
    let metadata: ImageMetadata
}

struct PreparedImageInputSelection: Sendable {
    let data: Data
    let metadata: ImageMetadata
    let previewData: Data
}

/// 批量导入的轻量概览：仅元数据与小图预览数据。不携带原图 data，
/// 导入完成后内存中无原图字节驻留（转换时再逐张经 reader 管线重读）。
struct ImageImportOverview: Sendable {
    let metadata: ImageMetadata
    let previewData: Data
}

/// 批量保存的候选条目：转换输出已落盘临时目录，保存时按需读取后写入。
struct BatchConversionSaveCandidate {
    let basename: String
    let tempURL: URL
    let format: ImageFileFormat
}

enum ImageWorkflowFailure: Error, Equatable {
    case unreadableImage
    case notRegularFile
    case unsupportedInputType
    case readFailed
    case saveFailed
    case partialSaveFailed(savedCount: Int, totalCount: Int)
    case processingFailed(ImageProcessingOperation)
    case blockedCompressionSave
}

enum ImageProcessingOperation: Equatable {
    case conversion
    case compression
    case watermark
    case grayscale
    case favicon

    var failureMessage: String {
        switch self {
        case .conversion:
            return "图片格式转换失败。"
        case .compression:
            return "图片压缩失败。"
        case .watermark:
            return "水印生成失败。"
        case .grayscale:
            return "灰度图片生成失败。"
        case .favicon:
            return "Favicon 生成失败。"
        }
    }
}

/// Transient save outcome, distinct from persistent `session.error` (which also
/// carries render/read diagnostics). `.blocked` stays silent because the owning
/// result surface already explains that no saveable result exists.
enum ImageSaveOutcome: Equatable {
    case saved
    case partiallySaved(savedCount: Int, totalCount: Int)
    case cancelled
    case blocked
    case failed(String)
}

extension ImageWorkflowFailure: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .unreadableImage:
            return "所选文件不包含可读取的图片数据。"
        case .notRegularFile:
            return "请选择普通图片文件。"
        case .unsupportedInputType:
            return "不支持所选图片的文件格式。"
        case .readFailed:
            return "图片文件读取失败。"
        case .saveFailed:
            return "图片文件保存失败。"
        case let .partialSaveFailed(savedCount, totalCount):
            return "已保存 \(savedCount)/\(totalCount) 个图标。"
        case let .processingFailed(operation):
            return operation.failureMessage
        case .blockedCompressionSave:
            return "当前压缩结果不小于原图，不能作为压缩结果保存。"
        }
    }

    static func diagnosticMessage(for error: Error, unknownFailure: ImageWorkflowFailure) -> String {
        if let failure = error as? ImageWorkflowFailure,
           let message = failure.errorDescription {
            return message
        }

        if let processorError = error as? ImageProcessorError,
           let message = processorError.errorDescription {
            return message
        }

        return unknownFailure.errorDescription ?? "图片处理失败。"
    }
}

@MainActor
struct ImageWorkflowDialog: Sendable {
    var selectSaveURL: @Sendable (String, [UTType]) async -> URL? = { _, _ in nil }
    var selectDirectory: @Sendable (String, String?) async -> URL? = { _, _ in nil }

    func selectSaveURL(defaultFilename: String, allowedContentTypes: [UTType]) async -> URL? {
        await selectSaveURL(defaultFilename, allowedContentTypes)
    }

    func selectDirectory(prompt: String, message: String? = nil) async -> URL? {
        await selectDirectory(prompt, message)
    }

    static func sheet(filePanel: FileInputPanelClient, outputPanel: FileOutputPanelClient) -> ImageWorkflowDialog {
        ImageWorkflowDialog(
            selectSaveURL: { defaultFilename, allowedContentTypes in
                let request = FileOutputPanelRequest(defaultFilename: defaultFilename, allowedContentTypes: allowedContentTypes)
                return try? await outputPanel.selectFile(request)
            },
            selectDirectory: { prompt, message in
                let request = FileInputPanelRequest(
                    prompt: prompt,
                    message: message,
                    canChooseDirectories: true,
                    canChooseFiles: false
                )
                return try? await filePanel.selectFile(request)
            }
        )
    }
}

struct ImageWorkflowFileReader: Sendable {
    var isRegularFile: @Sendable (URL) throws -> Bool = { url in
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isPackageKey])
        return values.isRegularFile == true && values.isPackage != true
    }
    var byteCount: @Sendable (URL) throws -> Int? = { url in
        try url.resourceValues(forKeys: [.fileSizeKey]).fileSize
    }
    var readDataWithLimit: @Sendable (URL, Int) throws -> Data = { url, maxBytes in
        do {
            return try BoundedFileReader.read(from: url, maxBytes: maxBytes)
        } catch BoundedFileReader.ReadError.tooLarge {
            let actualBytes = maxBytes == Int.max ? Int.max : maxBytes + 1
            throw ImageProcessorError.inputFileTooLarge(
                actualBytes: actualBytes,
                maxBytes: maxBytes
            )
        }
    }

    func isRegularFile(at url: URL) throws -> Bool {
        try isRegularFile(url)
    }

    func byteCount(for url: URL) throws -> Int? {
        try byteCount(url)
    }

    func readData(from url: URL) throws -> Data {
        try readData(from: url, maxBytes: ImageProcessingBudget.maxInputBytes)
    }

    func readData(from url: URL, maxBytes: Int) throws -> Data {
        try readDataWithLimit(url, maxBytes)
    }

    static func constant(data: Data) -> ImageWorkflowFileReader {
        ImageWorkflowFileReader(
            isRegularFile: { _ in true },
            byteCount: { _ in data.count },
            readDataWithLimit: { _, _ in data }
        )
    }
}

struct ImageWorkflowFileWriter: Sendable {
    var writeHandler: @Sendable (Data, URL) throws -> Void = { data, url in
        try data.write(to: url)
    }

    func write(_ data: Data, to url: URL) throws {
        try writeHandler(data, url)
    }
}

typealias ImageSelectionPublisher = (_ selection: ImageInputSelection, _ publish: () -> Void) -> Void
typealias ImageBackgroundOutputRenderer = @Sendable (ImageProcessingInput) throws -> ProcessedImage
typealias ImageBackgroundOutputRendererProvider = @MainActor () -> ImageBackgroundOutputRenderer
