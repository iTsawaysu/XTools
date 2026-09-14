import XToolsCore
import Foundation
import Testing

struct Base64ConversionTests {
    @Test func conversionErrorsUseFactualMessages() {
        let errors: [Base64Conversion.ConversionError] = [
            .invalidBase64,
            .invalidDataURL,
            .invalidUTF8,
        ]
        for error in errors {
            ToolDiagnosticContract.expectFactual(error.errorDescription ?? "")
        }
    }

    @Test func stringEncodingUsesUTF8() throws {
        let encoded = Base64Conversion.encode("hello 你好")
        let decoded = try Base64Conversion.decode(encoded)

        #expect(encoded == "aGVsbG8g5L2g5aW9")
        #expect(decoded == "hello 你好")
    }

    @Test func decodingTrimsOuterWhitespace() throws {
        let decoded = try Base64Conversion.decode("\n  aGVsbG8=  \t")
        #expect(decoded == "hello")
    }

    @Test func invalidBase64Throws() throws {
        #expect(throws: Base64Conversion.ConversionError.invalidBase64) {
            _ = try Base64Conversion.decode("not base64")
        }
    }

    @Test func invalidBase64PaddingThrows() throws {
        for input in ["Zg", "Zg=", "Zg===", "Zm9v=", "Zm9v==", "====", "AA=A"] {
            #expect(throws: Base64Conversion.ConversionError.invalidBase64) {
                _ = try Base64Conversion.decode(input)
            }
        }
    }

    @Test func invalidUTF8Throws() throws {
        #expect(throws: Base64Conversion.ConversionError.invalidUTF8) {
            _ = try Base64Conversion.decode("//4=")
        }
    }

    @Test func dataURLUsesDefaultMimeType() {
        let data = Data([0, 1, 2, 253, 254, 255])
        let url = Base64Conversion.dataURL(for: data)

        #expect(url == "data:application/octet-stream;base64,AAEC/f7/")
    }

    @Test func encodedOutputCharacterCountMatchesBase64Expansion() {
        #expect(Base64Conversion.encodedOutputCharacterCount(byteCount: 0, mode: .base64) == 0)
        #expect(Base64Conversion.encodedOutputCharacterCount(byteCount: 1, mode: .base64) == 4)
        #expect(Base64Conversion.encodedOutputCharacterCount(byteCount: 2, mode: .base64) == 4)
        #expect(Base64Conversion.encodedOutputCharacterCount(byteCount: 3, mode: .base64) == 4)
        #expect(Base64Conversion.encodedOutputCharacterCount(byteCount: 4, mode: .base64) == 8)

        let dataURLPrefix = "data:image/png;base64,"
        #expect(
            Base64Conversion.encodedOutputCharacterCount(
                byteCount: 4,
                mimeType: "image/png",
                mode: .dataURL
            )
            == dataURLPrefix.count + 8
        )
    }

    @Test func encodedOutputPreviewKeepsSmallOutputsComplete() {
        let data = Data("hello".utf8)
        let preview = Base64Conversion.encodedOutputPreview(
            for: data,
            mimeType: "text/plain",
            mode: .dataURL,
            inlineCharacterLimit: 80,
            fragmentCharacterLimit: 20
        )

        #expect(preview.isTruncated == false)
        #expect(preview.visibleText == "data:text/plain;base64,aGVsbG8=")
        #expect(preview.characterCount == preview.visibleText.count)
        #expect(preview.prefixCharacterCount == preview.visibleText.count)
        #expect(preview.suffixCharacterCount == 0)
    }

    @Test func encodedOutputPreviewTruncatesLargeOutputsWithoutLosingFullCount() {
        let data = Data((0..<9_000).map { UInt8($0 % 251) })
        let fullOutput = Base64Conversion.encodedOutput(for: data, mimeType: "application/octet-stream", mode: .base64)
        let preview = Base64Conversion.encodedOutputPreview(
            for: data,
            mode: .base64,
            inlineCharacterLimit: 1_000,
            fragmentCharacterLimit: 120
        )

        #expect(preview.isTruncated)
        #expect(preview.characterCount == fullOutput.count)
        #expect(preview.visibleText.count < fullOutput.count)
        #expect(fullOutput.hasPrefix(String(preview.visibleText.prefix(preview.prefixCharacterCount))))
        #expect(fullOutput.hasSuffix(String(preview.visibleText.suffix(preview.suffixCharacterCount))))
        #expect(preview.visibleText.contains("预览已截断"))
    }

    @Test func encodedOutputPreviewDefaultPolicyTruncatesMediumLargeOutputs() {
        let data = Data(repeating: 7, count: 60_000)
        let preview = Base64Conversion.encodedOutputPreview(for: data, mode: .base64)

        #expect(preview.isTruncated)
        #expect(preview.characterCount == 80_000)
        #expect(preview.visibleText.count < 4_000)
    }

    @Test func decodedByteCountUpperBoundUsesBase64ExpansionRatio() {
        #expect(Base64Conversion.decodedByteCountUpperBound(forBase64CharacterCount: 0) == 0)
        #expect(Base64Conversion.decodedByteCountUpperBound(forBase64CharacterCount: 1) == 3)
        #expect(Base64Conversion.decodedByteCountUpperBound(forBase64CharacterCount: 4) == 3)
        #expect(Base64Conversion.decodedByteCountUpperBound(forBase64CharacterCount: 5) == 6)
    }

    @Test func decodedByteCountUpperBoundForPayloadHonorsPaddingAndWhitespace() {
        #expect(Base64Conversion.decodedByteCountUpperBound(forBase64Payload: "aGVsbG8=") == 5)
        #expect(Base64Conversion.decodedByteCountUpperBound(forBase64Payload: "aG Vs bG 8=") == 5)
        #expect(Base64Conversion.decodedByteCountUpperBound(forBase64Payload: "AA==") == 1)
    }

    @Test func encodedOutputPreviewIncludesDataURLPrefixWhenTruncated() {
        let data = Data(repeating: 42, count: 9_000)
        let preview = Base64Conversion.encodedOutputPreview(
            for: data,
            mimeType: "image/png",
            mode: .dataURL,
            inlineCharacterLimit: 1_000,
            fragmentCharacterLimit: 120
        )

        #expect(preview.isTruncated)
        #expect(preview.visibleText.hasPrefix("data:image/png;base64,"))
        #expect(preview.characterCount == "data:image/png;base64,".count + ((data.count + 2) / 3) * 4)
    }

    @Test func dataURLParsingExtractsMimeTypeAndPayload() throws {
        let parsed = try Base64Conversion.parseDataURL("data:image/png;base64,iVBORw0KGgo=")

        #expect(parsed.mimeType == "image/png")
        #expect(parsed.base64Payload == "iVBORw0KGgo=")
    }

    @Test func dataURLParsingUsesRFC2397DefaultMediaTypeWhenOmitted() throws {
        let parsed = try Base64Conversion.parseDataURL("data:;base64,aGVsbG8=")
        let payload = try Base64Conversion.decodeFilePayload("data:;base64,aGVsbG8=")

        #expect(parsed.mimeType == "text/plain;charset=us-ascii")
        #expect(payload.mimeType == "text/plain;charset=us-ascii")
        #expect(payload.fileExtension == "txt")
    }

    @Test func dataURLParsingPreservesMediaTypeParameters() throws {
        let parsed = try Base64Conversion.parseDataURL("data:text/plain;charset=UTF-8;base64,aGVsbG8=")
        let payload = try Base64Conversion.decodeFilePayload("data:text/plain;charset=UTF-8;base64,aGVsbG8=")

        #expect(parsed.mimeType == "text/plain;charset=utf-8")
        #expect(payload.mimeType == "text/plain;charset=utf-8")
        #expect(payload.fileExtension == "txt")
    }

    @Test func dataURLParsingSupportsShorthandCharsetParameter() throws {
        let parsed = try Base64Conversion.parseDataURL("data:;charset=UTF-8;base64,aGVsbG8=")

        #expect(parsed.mimeType == "text/plain;charset=utf-8")
    }

    @Test func dataURLParsingAllowsEmptyBase64Payload() throws {
        let input = Base64Conversion.dataURL(for: Data(), mimeType: "application/octet-stream")
        let payload = try Base64Conversion.decodeFilePayload(input)

        #expect(input == "data:application/octet-stream;base64,")
        #expect(payload.data.isEmpty)
        #expect(payload.mimeType == "application/octet-stream")
        #expect(payload.fileExtension == "bin")
    }

    @Test func filePayloadDecodesPlainBase64AndInfersPNG() throws {
        let pngHeader = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        let payload = try Base64Conversion.decodeFilePayload(pngHeader.base64EncodedString())

        #expect(payload.data == pngHeader)
        #expect(payload.mimeType == "image/png")
        #expect(payload.fileExtension == "png")
    }

    @Test func filePayloadDataURLMimeTypeTakesPriorityOverSignature() throws {
        let pngHeader = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        let input = "data:application/pdf;base64,\(pngHeader.base64EncodedString())"
        let payload = try Base64Conversion.decodeFilePayload(input)

        #expect(payload.data == pngHeader)
        #expect(payload.mimeType == "application/pdf") // Data URL MIME type overrides signature
        #expect(payload.fileExtension == "pdf")
    }

    @Test func filePayloadInfersCommonBinaryTypes() {
        let jpeg = Base64Conversion.inferredFileType(for: Data([0xFF, 0xD8, 0xFF, 0xE0]))
        let gif = Base64Conversion.inferredFileType(for: Data("GIF89a".utf8))
        let pdf = Base64Conversion.inferredFileType(for: Data("%PDF-1.7".utf8))
        let unknown = Base64Conversion.inferredFileType(for: Data("hello".utf8))

        #expect(jpeg?.mimeType == "image/jpeg")
        #expect(jpeg?.fileExtension == "jpg")
        #expect(gif?.mimeType == "image/gif")
        #expect(gif?.fileExtension == "gif")
        #expect(pdf?.mimeType == "application/pdf")
        #expect(pdf?.fileExtension == "pdf")
        #expect(unknown == nil)
    }

    @Test func invalidFilePayloadThrowsClearBase64Error() throws {
        #expect(throws: Base64Conversion.ConversionError.invalidBase64) {
            _ = try Base64Conversion.decodeFilePayload("this is not base64")
        }
    }

    @Test func normalizedFileNameAddsMissingExtension() {
        #expect(
            Base64Conversion.normalizedFileName("download", fileExtension: "png")
            == "download.png"
        )
        #expect(
            Base64Conversion.normalizedFileName("report.pdf", fileExtension: "png")
            == "report.pdf"
        )
        #expect(
            Base64Conversion.normalizedFileName("   ", fileExtension: "gif")
            == "download.gif"
        )
    }

    @Test func base64URLDecodingRestoresPaddingAndAlphabet() throws {
        let data = try Base64Conversion.decodeBase64URLData("eyJzdWIiOiIxMjM0In0")
        let decoded = String(data: data, encoding: .utf8)

        #expect(decoded == "{\"sub\":\"1234\"}")
    }

    @Test func converterModeBackfillUsesCurrentValidBase64Output() throws {
        let backfill = ConverterModeBackfill.currentValidOutput(
            input: "hello",
            currentMode: "enc",
            hasError: false
        ) { input, mode in
            mode == "enc" ? Base64Conversion.encode(input) : try Base64Conversion.decode(input)
        }

        #expect(backfill == "aGVsbG8=")
        #expect(try Base64Conversion.decode(backfill ?? "") == "hello")
    }

    @Test func converterModeBackfillRejectsEmptyOrErroredOutput() {
        let emptyOutput = ConverterModeBackfill.currentValidOutput(
            input: "hello",
            currentMode: "enc",
            hasError: false
        ) { _, _ in "" }

        let visibleError = ConverterModeBackfill.currentValidOutput(
            input: "hello",
            currentMode: "enc",
            hasError: true
        ) { input, _ in Base64Conversion.encode(input) }

        let throwingConversion = ConverterModeBackfill.currentValidOutput(
            input: "not base64",
            currentMode: "dec",
            hasError: false
        ) { input, _ in try Base64Conversion.decode(input) }

        #expect(emptyOutput == nil)
        #expect(visibleError == nil)
        #expect(throwingConversion == nil)
    }
}
