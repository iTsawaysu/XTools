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

enum ImageWorkflowFailure: Error, Equatable {
    case unreadableImage
    case notRegularFile
    case unsupportedInputType
    case readFailed
    case saveFailed
    case partialSaveFailed(savedCount: Int, totalCount: Int)
    case processingFailed(ImageProcessingOperation)
    case noConversionTarget
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
        case .noConversionTarget:
            return "当前图片格式没有可用的转换目标。"
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
protocol ImageWorkflowDialoging {
    func selectSaveURL(defaultFilename: String, allowedContentTypes: [UTType]) async -> URL?
    func selectDirectory(prompt: String) async -> URL?
}

protocol ImageWorkflowFileReading: Sendable {
    func isRegularFile(at url: URL) throws -> Bool
    func byteCount(for url: URL) throws -> Int?
    func readData(from url: URL) throws -> Data
}

extension ImageWorkflowFileReading {
    func isRegularFile(at url: URL) throws -> Bool {
        true
    }

    func byteCount(for url: URL) throws -> Int? {
        nil
    }
}

protocol ImageWorkflowFileWriting {
    func write(_ data: Data, to url: URL) throws
}

typealias ImageSelectionPublisher = (_ selection: ImageInputSelection, _ publish: () -> Void) -> Void
typealias ImageProcessedOutputRenderer = (ImageInputSelection) throws -> ProcessedImage
typealias ImageBackgroundOutputRenderer = @Sendable (ImageProcessingInput) throws -> ProcessedImage
typealias ImageBackgroundOutputRendererProvider = @MainActor () -> ImageBackgroundOutputRenderer

struct NoOpImageWorkflowDialog: ImageWorkflowDialoging {
    func selectSaveURL(defaultFilename: String, allowedContentTypes: [UTType]) async -> URL? { nil }
    func selectDirectory(prompt: String) async -> URL? { nil }
}

struct SheetImageWorkflowDialog: ImageWorkflowDialoging {
    let filePanel: FileInputPanelClient
    let outputPanel: FileOutputPanelClient

    func selectSaveURL(defaultFilename: String, allowedContentTypes: [UTType]) async -> URL? {
        let request = FileOutputPanelRequest(defaultFilename: defaultFilename, allowedContentTypes: allowedContentTypes)
        return try? await outputPanel.selectFile(request)
    }

    func selectDirectory(prompt: String) async -> URL? {
        let request = FileInputPanelRequest(prompt: prompt, canChooseDirectories: true, canChooseFiles: false)
        return try? await filePanel.selectFile(request)
    }
}

struct FoundationImageWorkflowFileReader: ImageWorkflowFileReading {
    func isRegularFile(at url: URL) throws -> Bool {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isPackageKey])
        return values.isRegularFile == true && values.isPackage != true
    }

    func byteCount(for url: URL) throws -> Int? {
        try url.resourceValues(forKeys: [.fileSizeKey]).fileSize
    }

    func readData(from url: URL) throws -> Data {
        try readData(from: url, maxBytes: ImageProcessingBudget.maxInputBytes)
    }

    func readData(from url: URL, maxBytes: Int) throws -> Data {
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
}

struct FoundationImageWorkflowFileWriter: ImageWorkflowFileWriting {
    func write(_ data: Data, to url: URL) throws {
        try data.write(to: url)
    }
}
