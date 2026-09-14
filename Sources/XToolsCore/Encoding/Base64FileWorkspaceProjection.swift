import Foundation

public enum Base64FileStatusToneKind: Equatable, Sendable {
    case none
    case accent
    case success
    case failure
}

public struct Base64FilePanelStatusProjection: Equatable, Sendable {
    public let text: String
    public let tone: Base64FileStatusToneKind

    public init(text: String, tone: Base64FileStatusToneKind) {
        self.text = text
        self.tone = tone
    }
}

public struct Base64FileMetadataRowProjection: Equatable, Sendable {
    public let label: String
    public let value: String
    public let tone: Base64FileStatusToneKind

    public init(label: String, value: String, tone: Base64FileStatusToneKind) {
        self.label = label
        self.value = value
        self.tone = tone
    }
}

public struct Base64FileWorkspaceProjection: Equatable, Sendable {
    public let filePickerHelp: String
    public let sourceStatus: Base64FilePanelStatusProjection
    public let encodedOutputStatus: Base64FilePanelStatusProjection
    public let decodedResultStatus: Base64FilePanelStatusProjection
    public let encodedOutputSizeSummary: String
    public let outputCharacterCount: Int
    public let encodedOutputUsesBoundedScrolling: Bool
    public let fileClearDisabled: Bool
    public let reverseClearDisabled: Bool
    public let reverseRows: [Base64FileMetadataRowProjection]
    public let decodedPreviewDetail: String?
    public let decodedPreviewNoticeText: String?

    public init(
        filePickerHelp: String,
        sourceStatus: Base64FilePanelStatusProjection,
        encodedOutputStatus: Base64FilePanelStatusProjection,
        decodedResultStatus: Base64FilePanelStatusProjection,
        encodedOutputSizeSummary: String,
        outputCharacterCount: Int,
        encodedOutputUsesBoundedScrolling: Bool,
        fileClearDisabled: Bool,
        reverseClearDisabled: Bool,
        reverseRows: [Base64FileMetadataRowProjection],
        decodedPreviewDetail: String?,
        decodedPreviewNoticeText: String?
    ) {
        self.filePickerHelp = filePickerHelp
        self.sourceStatus = sourceStatus
        self.encodedOutputStatus = encodedOutputStatus
        self.decodedResultStatus = decodedResultStatus
        self.encodedOutputSizeSummary = encodedOutputSizeSummary
        self.outputCharacterCount = outputCharacterCount
        self.encodedOutputUsesBoundedScrolling = encodedOutputUsesBoundedScrolling
        self.fileClearDisabled = fileClearDisabled
        self.reverseClearDisabled = reverseClearDisabled
        self.reverseRows = reverseRows
        self.decodedPreviewDetail = decodedPreviewDetail
        self.decodedPreviewNoticeText = decodedPreviewNoticeText
    }

    public static func make(
        selectedFile: Base64FileSelection?,
        outputMode: Base64Conversion.FileOutputMode,
        outputPreview: Base64Conversion.EncodedFileOutputPreview?,
        isReadingFile: Bool,
        isPreparingOutput: Bool,
        fileError: String?,
        reverseInput: String,
        decodedPayload: Base64Conversion.FilePayload?,
        reverseError: String?,
        isDecoding: Bool,
        hasPreviewImage: Bool,
        inlinePreviewCharacterLimit: Int,
        previewImageByteLimit: Int
    ) -> Base64FileWorkspaceProjection {
        let outputCharacterCount = selectedFile.map {
            Base64Conversion.encodedOutputCharacterCount(
                byteCount: $0.byteCount,
                mimeType: $0.mimeType,
                mode: outputMode
            )
        } ?? 0

        let encodedOutputUsesBoundedScrolling: Bool = {
            guard let outputPreview else { return false }
            return outputPreview.isTruncated ||
                outputPreview.characterCount > inlinePreviewCharacterLimit
        }()

        let sourceStatus: Base64FilePanelStatusProjection = {
            if isReadingFile {
                return Base64FilePanelStatusProjection(text: "正在读取文件", tone: .accent)
            }
            if fileError != nil {
                return Base64FilePanelStatusProjection(text: "文件读取失败", tone: .failure)
            }
            if selectedFile != nil {
                return Base64FilePanelStatusProjection(text: "文件已读取", tone: .success)
            }
            return Base64FilePanelStatusProjection(text: "等待选择文件", tone: .none)
        }()

        let encodedOutputStatus: Base64FilePanelStatusProjection = {
            if isPreparingOutput {
                return Base64FilePanelStatusProjection(text: "正在更新输出", tone: .accent)
            }
            if outputPreview != nil {
                return Base64FilePanelStatusProjection(text: "输出已生成", tone: .success)
            }
            return Base64FilePanelStatusProjection(text: "等待选择文件", tone: .none)
        }()

        let decodedResultStatus: Base64FilePanelStatusProjection = {
            if isDecoding {
                return Base64FilePanelStatusProjection(text: "正在解析输入", tone: .accent)
            }
            if reverseError != nil {
                return Base64FilePanelStatusProjection(text: "输入无效", tone: .failure)
            }
            if decodedPayload != nil {
                return Base64FilePanelStatusProjection(text: "内容有效", tone: .success)
            }
            return Base64FilePanelStatusProjection(text: "等待解码", tone: .none)
        }()

        let encodedOutputSizeSummary: String = {
            guard let selectedFile, outputCharacterCount > 0 else {
                return "复制与保存使用完整输出"
            }
            return "\(ByteSizeFormatter.format(bytes: selectedFile.byteCount)) → \(ByteSizeFormatter.format(bytes: outputCharacterCount))"
        }()

        let fileClearDisabled =
            selectedFile == nil &&
            outputPreview == nil &&
            fileError == nil &&
            !isReadingFile &&
            !isPreparingOutput

        let reverseClearDisabled =
            reverseInput.isEmpty &&
            decodedPayload == nil &&
            reverseError == nil &&
            !isDecoding

        let reverseRows: [Base64FileMetadataRowProjection] = {
            guard let payload = decodedPayload else { return [] }
            return [
                Base64FileMetadataRowProjection(label: "MIME 类型", value: payload.mimeType, tone: .none),
                Base64FileMetadataRowProjection(
                    label: "大小",
                    value: ByteSizeFormatter.format(bytes: payload.data.count),
                    tone: .none
                ),
                Base64FileMetadataRowProjection(label: "状态", value: "解码成功", tone: .success)
            ]
        }()

        let decodedPreviewDetail: String? = {
            guard let payload = decodedPayload else { return nil }
            let kind = payload.mimeType.hasPrefix("text/") ? "文本文件预览" : "文件预览"
            return "\(kind) · \(ByteSizeFormatter.format(bytes: payload.data.count))"
        }()

        let decodedPreviewNoticeText: String? = {
            guard let payload = decodedPayload,
                  isImagePayload(payload),
                  !hasPreviewImage else {
                return nil
            }

            if payload.data.count > previewImageByteLimit {
                return "图片文件超过 \(ByteSizeFormatter.format(bytes: previewImageByteLimit)) 预览上限，可直接保存"
            }

            return "图片文件无法预览，可直接保存"
        }()

        return Base64FileWorkspaceProjection(
            filePickerHelp: selectedFile == nil ? "选择或拖入文件" : "选择或拖入另一个文件",
            sourceStatus: sourceStatus,
            encodedOutputStatus: encodedOutputStatus,
            decodedResultStatus: decodedResultStatus,
            encodedOutputSizeSummary: encodedOutputSizeSummary,
            outputCharacterCount: outputCharacterCount,
            encodedOutputUsesBoundedScrolling: encodedOutputUsesBoundedScrolling,
            fileClearDisabled: fileClearDisabled,
            reverseClearDisabled: reverseClearDisabled,
            reverseRows: reverseRows,
            decodedPreviewDetail: decodedPreviewDetail,
            decodedPreviewNoticeText: decodedPreviewNoticeText
        )
    }

    public static func isImagePayload(_ payload: Base64Conversion.FilePayload) -> Bool {
        payload.mimeType
            .split(separator: ";", maxSplits: 1, omittingEmptySubsequences: false)
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .hasPrefix("image/") == true
    }
}
