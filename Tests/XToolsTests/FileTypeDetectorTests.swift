import Foundation
import Testing
@testable import XToolsCore

struct FileTypeDetectorTests {
    @Test func extractsAndNormalizesExtension() {
        let report = FileTypeDetector.inspect(fileName: "photo.PNG", byteCount: 10, leadingData: Data([0x89]))
        #expect(report.fileExtension == "PNG")
    }

    @Test func matchingExtensionAndContentKeepIndependentEvidence() {
        let bytes = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        let report = FileTypeDetector.inspect(fileName: "photo.png", byteCount: Int64(bytes.count), leadingData: bytes)

        #expect(report.extensionMIMEType == "image/png")
        #expect(report.contentMIMEType == "image/png")
        #expect(report.resolvedMIMEType == "image/png")
        #expect(report.evidenceAgreement == .matching)
        #expect(report.contentStatus == .available)
    }

    @Test func highSpecificityContentConflictUsesContentAndExplainsTheEvidence() {
        let bytes = Data("%PDF-1.7".utf8)
        let report = FileTypeDetector.inspect(fileName: "private-report.jpg", byteCount: Int64(bytes.count), leadingData: bytes)

        #expect(report.fileExtension == "jpg")
        #expect(report.extensionMIMEType == "image/jpeg")
        #expect(report.contentMIMEType == "application/pdf")
        #expect(report.resolvedMIMEType == "application/pdf")
        #expect(report.evidenceAgreement == .conflicting)
        #expect(report.conflictDiagnostic == "扩展名与内容不一致，最终按内容判定为 application/pdf。")
        #expect(report.conflictDiagnostic?.contains("private-report.jpg") == false)
        ToolDiagnosticContract.expectFactual(
            report.conflictDiagnostic ?? "",
            sensitiveInputs: ["private-report.jpg", "/tmp/private-report.jpg"]
        )
    }

    @Test func genericTextIsCompatibleWithMarkdownAndKeepsTheMoreSpecificExtension() {
        let report = FileTypeDetector.inspect(fileName: "README.md", byteCount: 7, leadingData: Data("Heading".utf8))

        #expect(report.extensionMIMEType == "text/markdown")
        #expect(report.contentMIMEType == "text/plain")
        #expect(report.contentEvidence?.specificity == .genericText)
        #expect(report.evidenceAgreement == .compatible)
        #expect(report.resolvedMIMEType == "text/markdown")
        #expect(report.conflictDiagnostic == nil)
    }

    @Test func genericTextIsCompatibleWithSVGAndKeepsTheMoreSpecificExtension() {
        let bytes = Data("<svg xmlns=\"http://www.w3.org/2000/svg\"></svg>".utf8)
        let report = FileTypeDetector.inspect(fileName: "icon.svg", byteCount: Int64(bytes.count), leadingData: bytes)

        #expect(report.extensionMIMEType == "image/svg+xml")
        #expect(report.contentMIMEType == "text/plain")
        #expect(report.evidenceAgreement == .compatible)
        #expect(report.resolvedMIMEType == "image/svg+xml")
        #expect(report.conflictDiagnostic == nil)
    }

    @Test func genericZIPContainerIsCompatibleWithJARAndKeepsArchiveSemantics() {
        let bytes = Data([0x50, 0x4B, 0x03, 0x04])
        let report = FileTypeDetector.inspect(fileName: "library.jar", byteCount: Int64(bytes.count), leadingData: bytes)

        #expect(report.extensionMIMEType == "application/java-archive")
        #expect(report.contentMIMEType == "application/zip")
        #expect(report.contentEvidence?.specificity == .genericContainer)
        #expect(report.evidenceAgreement == .compatible)
        #expect(report.resolvedMIMEType == "application/java-archive")
        #expect(report.conflictDiagnostic == nil)
    }

    @Test func specificJSONContentWinsOverGenericPlainTextExtensionWithoutConflict() {
        let bytes = Data("{\"ok\":true}".utf8)
        let report = FileTypeDetector.inspect(fileName: "payload.txt", byteCount: Int64(bytes.count), leadingData: bytes)

        #expect(report.extensionMIMEType == "text/plain")
        #expect(report.contentMIMEType == "application/json")
        #expect(report.contentEvidence?.specificity == .specific)
        #expect(report.evidenceAgreement == .compatible)
        #expect(report.resolvedMIMEType == "application/json")
        #expect(report.conflictDiagnostic == nil)
    }

    @Test func genericContentThatCannotProveCompatibilityIsIndeterminateAndDoesNotWarn() {
        let bytes = Data("plain text prefix".utf8)
        let report = FileTypeDetector.inspect(fileName: "photo.jpg", byteCount: Int64(bytes.count), leadingData: bytes)

        #expect(report.extensionMIMEType == "image/jpeg")
        #expect(report.contentMIMEType == "text/plain")
        #expect(report.evidenceAgreement == .indeterminate)
        #expect(report.resolvedMIMEType == "image/jpeg")
        #expect(report.conflictDiagnostic == nil)
    }

    @Test func recognizableContentWithoutExtensionIsContentOnly() {
        let bytes = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        let report = FileTypeDetector.inspect(fileName: "upload", byteCount: Int64(bytes.count), leadingData: bytes)

        #expect(report.fileExtension == "(无)")
        #expect(report.extensionMIMEType == "(未知)")
        #expect(report.contentMIMEType == "image/png")
        #expect(report.resolvedMIMEType == "image/png")
        #expect(report.evidenceAgreement == .contentOnly)
    }

    @Test func knownExtensionWithUnknownContentIsExtensionOnly() {
        let report = FileTypeDetector.inspect(fileName: "document.pdf", byteCount: 2, leadingData: Data([0x00, 0xFF]))

        #expect(report.extensionMIMEType == "application/pdf")
        #expect(report.contentMIMEType == "(未知)")
        #expect(report.resolvedMIMEType == "application/pdf")
        #expect(report.evidenceAgreement == .extensionOnly)
        #expect(report.contentStatus == .available)
    }

    @Test func unknownExtensionAndUnknownContentStayUnknown() {
        let report = FileTypeDetector.inspect(fileName: "upload", byteCount: 2, leadingData: Data([0x00, 0xFF]))

        #expect(report.extensionMIMEType == "(未知)")
        #expect(report.contentMIMEType == "(未知)")
        #expect(report.resolvedMIMEType == "(未知)")
        #expect(report.evidenceAgreement == .unknown)
        #expect(report.contentStatus == .available)
    }

    @Test func emptyFileKeepsExtensionEvidenceAndLabelsContentAsEmpty() {
        let report = FileTypeDetector.inspect(fileName: "empty.txt", byteCount: 0, leadingData: Data())

        #expect(report.extensionMIMEType == "text/plain")
        #expect(report.contentMIMEType == "(空文件)")
        #expect(report.resolvedMIMEType == "text/plain")
        #expect(report.evidenceAgreement == .extensionOnly)
        #expect(report.contentStatus == .empty)
        #expect(report.headerBytes == "(空文件)")
    }

    @Test func unreadablePrefixKeepsExtensionEvidenceAndLabelsContentAsUnreadable() {
        let report = FileTypeDetector.inspect(fileName: "archive.zip", byteCount: nil, leadingData: nil)

        #expect(report.extensionMIMEType == "application/zip")
        #expect(report.contentMIMEType == "(无法读取)")
        #expect(report.resolvedMIMEType == "application/zip")
        #expect(report.evidenceAgreement == .extensionOnly)
        #expect(report.contentStatus == .unreadable)
        #expect(report.headerBytes == "(无法读取)")
        #expect(report.fileSize == "(未知)")
    }

    @Test func recognizesCommonBinarySignatures() {
        #expect(FileTypeDetector.inspect(fileName: "photo", byteCount: 3, leadingData: Data([0xFF, 0xD8, 0xFF])).resolvedMIMEType == "image/jpeg")
        #expect(FileTypeDetector.inspect(fileName: "image", byteCount: 6, leadingData: Data("GIF89a".utf8)).resolvedMIMEType == "image/gif")
        #expect(FileTypeDetector.inspect(fileName: "doc", byteCount: 5, leadingData: Data("%PDF-".utf8)).resolvedMIMEType == "application/pdf")
        #expect(FileTypeDetector.inspect(fileName: "archive", byteCount: 4, leadingData: Data([0x50, 0x4B, 0x03, 0x04])).resolvedMIMEType == "application/zip")
        #expect(FileTypeDetector.inspect(fileName: "compressed", byteCount: 2, leadingData: Data([0x1F, 0x8B])).resolvedMIMEType == "application/gzip")
    }

    @Test func detectsJSONFromTextPrefixWithoutExtension() {
        let report = FileTypeDetector.inspect(fileName: "payload", byteCount: 8, leadingData: Data("  {\"a\":1}".utf8))

        #expect(report.fileExtension == "(无)")
        #expect(report.contentMIMEType == "application/json")
        #expect(report.resolvedMIMEType == "application/json")
        #expect(report.evidenceAgreement == .contentOnly)
    }

    @Test func headerBytesAreUppercaseHexOfFirst16Bytes() {
        let bytes = Data((0..<20).map { UInt8($0) })
        let report = FileTypeDetector.inspect(fileName: "x.bin", byteCount: 20, leadingData: bytes)

        #expect(report.headerBytes == "00 01 02 03 04 05 06 07 08 09 0A 0B 0C 0D 0E 0F")
    }

    @Test func fileSizeUsesByteSizeFormatterFormat() {
        // Locks the file-size column to the project-wide ByteSizeFormatter
        // (the former ByteCountFormatter(.file) output diverged: "512 bytes"
        // vs "512 B", "999 KB" vs "976 KB").
        func fileSize(_ byteCount: Int64) -> String {
            FileTypeDetector.inspect(fileName: "x.txt", byteCount: byteCount, leadingData: Data([0x41])).fileSize
        }
        #expect(fileSize(0) == "0 B")
        #expect(fileSize(512) == "512 B")
        #expect(fileSize(1024) == "1 KB")
        #expect(fileSize(1536) == "1.5 KB")
        #expect(fileSize(999_424) == "976 KB")
    }

    @Test func fileNameIsPreserved() {
        let report = FileTypeDetector.inspect(fileName: "my file.tar.gz", byteCount: 5, leadingData: Data([0x1F]))
        #expect(report.fileName == "my file.tar.gz")
        #expect(report.fileExtension == "gz")
    }

    @Test func exposesLeadingByteReadLimit() {
        #expect(FileTypeDetector.leadingByteLimit == 64)
    }

    @Test func inspectionIssuesAreSpecificFactualMessages() {
        let cases: [(FileTypeDetector.InspectionIssue, String)] = [
            (.notRegularFile, "所选项目不是普通文件。"),
            (.metadataReadFailed, "无法读取文件的基本信息。"),
            (.contentReadFailed, "无法读取文件开头内容，内容签名和文件头可能不完整。")
        ]

        for (issue, expected) in cases {
            #expect(issue.errorDescription == expected)
            ToolDiagnosticContract.expectFactual(expected)
        }
    }

    @Test func systemFileErrorsNeverExposePathsOrNSErrorText() {
        let lowLevelError = NSError(
            domain: "NSCocoaErrorDomain",
            code: 257,
            userInfo: [NSLocalizedDescriptionKey: "Permission denied: /tmp/private/secret.bin"]
        )
        let message = FileTypeDetector.diagnosticMessage(
            for: lowLevelError,
            defaultIssue: .contentReadFailed
        )

        #expect(message == "无法读取文件开头内容，内容签名和文件头可能不完整。")
        ToolDiagnosticContract.expectFactual(
            message,
            sensitiveInputs: ["Permission denied: /tmp/private/secret.bin"]
        )
    }
}
