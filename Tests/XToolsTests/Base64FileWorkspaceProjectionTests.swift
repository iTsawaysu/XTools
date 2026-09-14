@testable import XToolsCore
import Foundation
import Testing

struct Base64FileWorkspaceProjectionTests {
    @Test func idleEncodeWorkspaceUsesWaitingCopyAndDisablesFileClear() {
        let projection = Self.make()

        #expect(projection.filePickerHelp == "选择或拖入文件")
        #expect(projection.sourceStatus == .init(text: "等待选择文件", tone: .none))
        #expect(projection.encodedOutputStatus == .init(text: "等待选择文件", tone: .none))
        #expect(projection.decodedResultStatus == .init(text: "等待解码", tone: .none))
        #expect(projection.encodedOutputSizeSummary == "复制与保存使用完整输出")
        #expect(projection.outputCharacterCount == 0)
        #expect(projection.encodedOutputUsesBoundedScrolling == false)
        #expect(projection.fileClearDisabled)
        #expect(projection.reverseClearDisabled)
        #expect(projection.reverseRows.isEmpty)
        #expect(projection.decodedPreviewDetail == nil)
        #expect(projection.decodedPreviewNoticeText == nil)
    }

    @Test func readingAndReadySourceStatusesMatchWorkbenchCopy() {
        let reading = Self.make(isReadingFile: true)
        #expect(reading.sourceStatus == .init(text: "正在读取文件", tone: .accent))
        #expect(!reading.fileClearDisabled)

        let failed = Self.make(fileError: "boom")
        #expect(failed.sourceStatus == .init(text: "文件读取失败", tone: .failure))

        let ready = Self.make(selectedFile: Self.selection(data: Data("hi".utf8)))
        #expect(ready.sourceStatus == .init(text: "文件已读取", tone: .success))
        #expect(ready.filePickerHelp == "选择或拖入另一个文件")
        #expect(ready.outputCharacterCount > 0)
        #expect(ready.encodedOutputSizeSummary.contains("→"))
        #expect(!ready.fileClearDisabled)
    }

    @Test func encodedOutputStatusAndBoundedScrollingFollowPreview() {
        let preparing = Self.make(isPreparingOutput: true)
        #expect(preparing.encodedOutputStatus == .init(text: "正在更新输出", tone: .accent))

        let shortPreview = Base64Conversion.EncodedFileOutputPreview(
            mode: .base64,
            mimeType: "application/octet-stream",
            sourceByteCount: 5,
            characterCount: 100,
            visibleText: "abc",
            isTruncated: false,
            prefixCharacterCount: 100,
            suffixCharacterCount: 0
        )
        let short = Self.make(
            selectedFile: Self.selection(data: Data("hello".utf8)),
            outputPreview: shortPreview,
            inlinePreviewCharacterLimit: 512
        )
        #expect(short.encodedOutputStatus == .init(text: "输出已生成", tone: .success))
        #expect(short.encodedOutputUsesBoundedScrolling == false)

        let longPreview = Base64Conversion.EncodedFileOutputPreview(
            mode: .base64,
            mimeType: "application/octet-stream",
            sourceByteCount: 5,
            characterCount: 600,
            visibleText: String(repeating: "a", count: 20),
            isTruncated: false,
            prefixCharacterCount: 600,
            suffixCharacterCount: 0
        )
        let long = Self.make(outputPreview: longPreview, inlinePreviewCharacterLimit: 512)
        #expect(long.encodedOutputUsesBoundedScrolling)

        let truncated = Self.make(
            outputPreview: Base64Conversion.EncodedFileOutputPreview(
                mode: .dataURL,
                mimeType: "application/octet-stream",
                sourceByteCount: 1,
                characterCount: 10,
                visibleText: "x",
                isTruncated: true,
                prefixCharacterCount: 5,
                suffixCharacterCount: 5
            )
        )
        #expect(truncated.encodedOutputUsesBoundedScrolling)
    }

    @Test func decodedStatusesRowsAndNoticesMatchWorkbenchCopy() {
        let decoding = Self.make(isDecoding: true)
        #expect(decoding.decodedResultStatus == .init(text: "正在解析输入", tone: .accent))
        #expect(!decoding.reverseClearDisabled)

        let invalid = Self.make(reverseError: "bad")
        #expect(invalid.decodedResultStatus == .init(text: "输入无效", tone: .failure))

        let payload = Base64Conversion.FilePayload(
            data: Data("hello".utf8),
            mimeType: "text/plain",
            fileExtension: "txt"
        )
        let success = Self.make(decodedPayload: payload)
        #expect(success.decodedResultStatus == .init(text: "内容有效", tone: .success))
        #expect(success.reverseRows.map(\.label) == ["MIME 类型", "大小", "状态"])
        #expect(success.reverseRows.map(\.value) == [
            "text/plain",
            ByteSizeFormatter.format(bytes: 5),
            "解码成功"
        ])
        #expect(success.reverseRows.map(\.tone) == [.none, .none, .success])
        #expect(success.decodedPreviewDetail == "文本文件预览 · \(ByteSizeFormatter.format(bytes: 5))")
        #expect(success.decodedPreviewNoticeText == nil)

        let binary = Base64Conversion.FilePayload(
            data: Data([0x00, 0x01]),
            mimeType: "application/octet-stream",
            fileExtension: "bin"
        )
        #expect(Self.make(decodedPayload: binary).decodedPreviewDetail == "文件预览 · \(ByteSizeFormatter.format(bytes: 2))")
    }

    @Test func imagePayloadNoticeCoversOverLimitAndUnpreviewable() {
        let overLimit = Base64Conversion.FilePayload(
            data: Data(repeating: 1, count: 12),
            mimeType: "image/png; charset=binary",
            fileExtension: "png"
        )
        #expect(Base64FileWorkspaceProjection.isImagePayload(overLimit))

        let noticeOver = Self.make(
            decodedPayload: overLimit,
            hasPreviewImage: false,
            previewImageByteLimit: 8
        )
        #expect(
            noticeOver.decodedPreviewNoticeText ==
                "图片文件超过 \(ByteSizeFormatter.format(bytes: 8)) 预览上限，可直接保存"
        )

        let noticeFail = Self.make(
            decodedPayload: overLimit,
            hasPreviewImage: false,
            previewImageByteLimit: 100
        )
        #expect(noticeFail.decodedPreviewNoticeText == "图片文件无法预览，可直接保存")

        let withImage = Self.make(
            decodedPayload: overLimit,
            hasPreviewImage: true,
            previewImageByteLimit: 8
        )
        #expect(withImage.decodedPreviewNoticeText == nil)
    }

    private static func selection(data: Data) -> Base64FileSelection {
        Base64FileSelection(
            fileName: "sample.bin",
            data: data,
            mimeType: "application/octet-stream"
        )
    }

    private static func make(
        selectedFile: Base64FileSelection? = nil,
        outputMode: Base64Conversion.FileOutputMode = .dataURL,
        outputPreview: Base64Conversion.EncodedFileOutputPreview? = nil,
        isReadingFile: Bool = false,
        isPreparingOutput: Bool = false,
        fileError: String? = nil,
        reverseInput: String = "",
        decodedPayload: Base64Conversion.FilePayload? = nil,
        reverseError: String? = nil,
        isDecoding: Bool = false,
        hasPreviewImage: Bool = false,
        inlinePreviewCharacterLimit: Int = 512,
        previewImageByteLimit: Int = Base64FileLimits.previewImageByteLimit
    ) -> Base64FileWorkspaceProjection {
        Base64FileWorkspaceProjection.make(
            selectedFile: selectedFile,
            outputMode: outputMode,
            outputPreview: outputPreview,
            isReadingFile: isReadingFile,
            isPreparingOutput: isPreparingOutput,
            fileError: fileError,
            reverseInput: reverseInput,
            decodedPayload: decodedPayload,
            reverseError: reverseError,
            isDecoding: isDecoding,
            hasPreviewImage: hasPreviewImage,
            inlinePreviewCharacterLimit: inlinePreviewCharacterLimit,
            previewImageByteLimit: previewImageByteLimit
        )
    }
}
