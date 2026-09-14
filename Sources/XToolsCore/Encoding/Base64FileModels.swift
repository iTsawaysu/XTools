import Foundation

public struct Base64FileSelection: Equatable, Identifiable, Sendable {
    public let id: UUID
    public let fileName: String
    public let data: Data
    public let mimeType: String

    public init(
        id: UUID = UUID(),
        fileName: String,
        data: Data,
        mimeType: String
    ) {
        self.id = id
        self.fileName = fileName
        self.data = data
        self.mimeType = mimeType
    }

    public var byteCount: Int {
        data.count
    }
}

public struct Base64FileEncodedTextInput: Equatable, Sendable {
    public let fileName: String
    public let text: String

    public init(fileName: String, text: String) {
        self.fileName = fileName
        self.text = text
    }
}

/// Shared Base64 file workflow limits (UI and pure projection both read these).
public enum Base64FileLimits {
    public static let previewImageByteLimit = 5 * 1024 * 1024
    public static let previewImageMaxPixelLength = 1_600
    public static let maxDecodedPayloadBytes = 50 * 1024 * 1024
}

public enum Base64FileWorkflowFailure: Error, Equatable, Sendable {
    case notRegularFile
    case tooLarge(fileName: String, maxBytes: Int)
    case decodedTooLarge(maxBytes: Int)
    case reverseInputTooLarge(maxBytes: Int)
    case externalEncodedTextTooLarge(maxBytes: Int)
    case encodedTextNotUTF8
    case readFailed
    case invalidPayload
    case copyFailed
    case saveFailed
}

extension Base64FileWorkflowFailure: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .notRegularFile:
            return "所选项目不是普通文件。"
        case .tooLarge(_, let maxBytes):
            return "所选文件超过 \(ByteSizeFormatter.format(bytes: maxBytes)) 的大小限制。"
        case .decodedTooLarge(let maxBytes):
            return "解码后的文件超过 \(ByteSizeFormatter.format(bytes: maxBytes)) 的大小限制。"
        case .reverseInputTooLarge(let maxBytes):
            return "可编辑的 Base64 或 Data URL 不能超过 \(ByteSizeFormatter.format(bytes: maxBytes))。"
        case .externalEncodedTextTooLarge(let maxBytes):
            return "编码文本文件超过 \(ByteSizeFormatter.format(bytes: maxBytes)) 的大小限制。"
        case .encodedTextNotUTF8:
            return "编码文本文件不是 UTF-8 文本。"
        case .readFailed:
            return "无法读取所选文件。"
        case .invalidPayload:
            return "输入不是有效的 Base64 或 Base64 Data URL。"
        case .copyFailed:
            return "无法复制编码结果。"
        case .saveFailed:
            return "无法保存文件。"
        }
    }
}
