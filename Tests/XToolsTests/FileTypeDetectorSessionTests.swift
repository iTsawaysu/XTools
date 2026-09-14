import Foundation
import Testing
import UniformTypeIdentifiers
@testable import XTools
@testable import XToolsCore

@MainActor
struct FileTypeDetectorSessionTests {
    @Test func inspectionReadsMetadataAndBoundedPrefixOffMainActor() async {
        let url = URL(fileURLWithPath: "/tmp/payload.json")
        let reader = FakeFileTypeFileReader(
            byteCountsByURL: [url: 8],
            leadingDataByURL: [url: Data("{\"a\":1}".utf8)]
        )
        let session = FileTypeDetectorSession(reader: reader)

        await session.inspect(url).value

        #expect(session.selectedFileURL == url)
        #expect(session.fileName == "payload.json")
        #expect(session.report?.resolvedMIMEType == "application/json")
        #expect(session.report?.headerBytes == "7B 22 61 22 3A 31 7D")
        #expect(session.error == nil)
        #expect(session.warning == nil)
        #expect(session.isInspecting == false)
        #expect(reader.requestedLeadingByteCounts == [FileTypeDetector.leadingByteLimit])
        #expect(reader.observedMainThread == false)
    }

    @Test func prefixFailureKeepsMetadataReportAndSurfacesWarning() async {
        let url = URL(fileURLWithPath: "/tmp/archive.zip")
        let reader = FakeFileTypeFileReader(
            byteCountsByURL: [url: 42],
            leadingDataByURL: [:],
            prefixIssuesByURL: [url: .contentReadFailed]
        )
        let session = FileTypeDetectorSession(reader: reader)

        await session.inspect(url).value

        #expect(session.report?.fileName == "archive.zip")
        #expect(session.report?.contentMIMEType == "(无法读取)")
        #expect(session.report?.resolvedMIMEType == "application/zip")
        #expect(session.report?.contentStatus == .unreadable)
        #expect(session.report?.headerBytes == "(无法读取)")
        #expect(session.error == nil)
        #expect(session.warning == "无法读取文件开头内容，内容签名和文件头可能不完整。")
        #expect(session.isInspecting == false)
    }

    @Test func conflictingExtensionAndContentSurfaceAStableWarning() async {
        let url = URL(fileURLWithPath: "/tmp/private-report.jpg")
        let reader = FakeFileTypeFileReader(
            byteCountsByURL: [url: 8],
            leadingDataByURL: [url: Data("%PDF-1.7".utf8)]
        )
        let session = FileTypeDetectorSession(reader: reader)

        await session.inspect(url).value

        #expect(session.report?.extensionMIMEType == "image/jpeg")
        #expect(session.report?.contentMIMEType == "application/pdf")
        #expect(session.report?.resolvedMIMEType == "application/pdf")
        #expect(session.report?.evidenceAgreement == .conflicting)
        #expect(session.error == nil)
        #expect(session.warning == "扩展名与内容不一致，最终按内容判定为 application/pdf。")
        #expect(session.warning?.contains(url.path) == false)
        #expect(session.warning?.contains(url.lastPathComponent) == false)
    }

    @Test func compatibleGenericTextEvidenceDoesNotSurfaceAWarning() async {
        let url = URL(fileURLWithPath: "/tmp/README.md")
        let reader = FakeFileTypeFileReader(
            byteCountsByURL: [url: 7],
            leadingDataByURL: [url: Data("Heading".utf8)]
        )
        let session = FileTypeDetectorSession(reader: reader)

        await session.inspect(url).value

        #expect(session.report?.extensionMIMEType == "text/markdown")
        #expect(session.report?.contentMIMEType == "text/plain")
        #expect(session.report?.resolvedMIMEType == "text/markdown")
        #expect(session.report?.evidenceAgreement == .compatible)
        #expect(session.warning == nil)
    }

    @Test func metadataFailureClearsOldReportAndKeepsAttemptedFileName() async {
        let validURL = URL(fileURLWithPath: "/tmp/valid.txt")
        let invalidURL = URL(fileURLWithPath: "/tmp/folder", isDirectory: true)
        let reader = FakeFileTypeFileReader(
            byteCountsByURL: [validURL: 3],
            leadingDataByURL: [validURL: Data("abc".utf8)],
            metadataIssuesByURL: [invalidURL: .notRegularFile]
        )
        let session = FileTypeDetectorSession(reader: reader)
        await session.inspect(validURL).value

        await session.inspect(invalidURL).value

        #expect(session.selectedFileURL == invalidURL)
        #expect(session.fileName == "folder")
        #expect(session.report == nil)
        #expect(session.error == "所选项目不是普通文件。")
        #expect(session.warning == nil)
        #expect(session.isInspecting == false)
    }

    @Test func newerInspectionWinsWhenOlderReaderFinishesLater() async throws {
        let slowURL = URL(fileURLWithPath: "/tmp/slow.json")
        let currentURL = URL(fileURLWithPath: "/tmp/current.pdf")
        let reader = FakeFileTypeFileReader(
            byteCountsByURL: [slowURL: 2, currentURL: 5],
            leadingDataByURL: [
                slowURL: Data("{}".utf8),
                currentURL: Data("%PDF-".utf8)
            ],
            metadataDelayByURL: [slowURL: 0.08]
        )
        let session = FileTypeDetectorSession(reader: reader)

        let slowTask = session.inspect(slowURL)
        try await Self.waitUntil { reader.metadataURLs.contains(slowURL) }
        let currentTask = session.inspect(currentURL)
        await currentTask.value
        await slowTask.value

        #expect(session.selectedFileURL == currentURL)
        #expect(session.fileName == "current.pdf")
        #expect(session.report?.resolvedMIMEType == "application/pdf")
        #expect(session.error == nil)
        #expect(session.warning == nil)
        #expect(session.isInspecting == false)
    }

    @Test func multipleFileRejectionCancelsPendingInspectionAndClearsOldResult() async throws {
        let oldURL = URL(fileURLWithPath: "/tmp/old.txt")
        let slowURL = URL(fileURLWithPath: "/tmp/slow.txt")
        let reader = FakeFileTypeFileReader(
            byteCountsByURL: [oldURL: 3, slowURL: 4],
            leadingDataByURL: [oldURL: Data("old".utf8), slowURL: Data("slow".utf8)],
            metadataDelayByURL: [slowURL: 0.08]
        )
        let session = FileTypeDetectorSession(reader: reader)
        await session.inspect(oldURL).value

        let slowTask = session.inspect(slowURL)
        try await Self.waitUntil { reader.metadataURLs.contains(slowURL) }
        session.rejectMultipleFileDrop()
        await slowTask.value

        #expect(session.selectedFileURL == nil)
        #expect(session.fileName.isEmpty)
        #expect(session.report == nil)
        #expect(session.error == SingleFileDropResolver.multipleFilesDiagnostic)
        #expect(session.warning == nil)
        #expect(session.isInspecting == false)
    }

    @Test func panelSelectionUsesDataRequestAndEntersTheURLPipeline() async throws {
        let url = URL(fileURLWithPath: "/tmp/source.bin")
        let reader = FakeFileTypeFileReader(
            byteCountsByURL: [url: 3],
            leadingDataByURL: [url: Data([0xFF, 0xD8, 0xFF])]
        )
        let session = FileTypeDetectorSession(reader: reader)
        var requestedTypes: [UTType] = []
        let panel = FileInputPanelClient { request in
            requestedTypes = request.allowedContentTypes
            return url
        }

        await session.selectFile(filePanel: panel).value
        try await Self.waitUntil { session.report != nil }

        #expect(requestedTypes == [.data])
        #expect(session.selectedFileURL == url)
        #expect(session.report?.resolvedMIMEType == "image/jpeg")
    }

    @Test func panelCancellationPreservesCurrentReportAndDiagnosticState() async {
        let url = URL(fileURLWithPath: "/tmp/current.txt")
        let reader = FakeFileTypeFileReader(
            byteCountsByURL: [url: 7],
            leadingDataByURL: [:],
            prefixIssuesByURL: [url: .contentReadFailed]
        )
        let session = FileTypeDetectorSession(reader: reader)
        await session.inspect(url).value
        let currentReport = session.report
        let currentWarning = session.warning

        await session.selectFile(filePanel: FileInputPanelClient { _ in nil }).value

        #expect(session.selectedFileURL == url)
        #expect(session.report == currentReport)
        #expect(session.error == nil)
        #expect(session.warning == currentWarning)
        #expect(session.warning == "无法读取文件开头内容，内容签名和文件头可能不完整。")
    }

    @Test func panelFailurePreservesCurrentReportAndUsesStableDiagnostic() async {
        let url = URL(fileURLWithPath: "/tmp/current.txt")
        let reader = FakeFileTypeFileReader(
            byteCountsByURL: [url: 7],
            leadingDataByURL: [url: Data("current".utf8)]
        )
        let session = FileTypeDetectorSession(reader: reader)
        await session.inspect(url).value
        let currentReport = session.report

        await session.selectFile(filePanel: FileInputPanelClient { _ in
            throw FileInputPanelFailure.windowUnavailable
        }).value

        #expect(session.selectedFileURL == url)
        #expect(session.report == currentReport)
        #expect(session.error == "暂时无法打开文件选择器。")
    }

    @Test func resetClearsCompletedReportWarningAndErrorStates() async {
        let warningURL = URL(fileURLWithPath: "/tmp/reset-warning.zip")
        let warningReader = FakeFileTypeFileReader(
            byteCountsByURL: [warningURL: 42],
            leadingDataByURL: [:],
            prefixIssuesByURL: [warningURL: .contentReadFailed]
        )
        let session = FileTypeDetectorSession(reader: warningReader)

        #expect(!session.canReset)
        await session.inspect(warningURL).value
        #expect(session.canReset)
        #expect(session.selectedFileURL == warningURL)
        #expect(!session.fileName.isEmpty)
        #expect(session.report != nil)
        #expect(session.warning != nil)
        session.reset()
        #expect(!session.canReset)
        #expect(session.selectedFileURL == nil)
        #expect(session.fileName.isEmpty)
        #expect(session.report == nil)
        #expect(session.error == nil)
        #expect(session.warning == nil)
        #expect(!session.isInspecting)

        let errorURL = URL(fileURLWithPath: "/tmp/reset-error.bin")
        let errorReader = FakeFileTypeFileReader(
            byteCountsByURL: [:],
            leadingDataByURL: [:],
            metadataIssuesByURL: [errorURL: .metadataReadFailed]
        )
        let errorSession = FileTypeDetectorSession(reader: errorReader)
        await errorSession.inspect(errorURL).value
        #expect(errorSession.canReset)
        #expect(errorSession.error != nil)
        errorSession.reset()
        #expect(!errorSession.canReset)
        #expect(errorSession.selectedFileURL == nil)
        #expect(errorSession.fileName.isEmpty)
        #expect(errorSession.report == nil)
        #expect(errorSession.error == nil)
        #expect(errorSession.warning == nil)
        #expect(!errorSession.isInspecting)
    }

    @Test func resetCancelsInspectionAndRejectsLateCompletion() async throws {
        let url = URL(fileURLWithPath: "/tmp/reset-running.json")
        let reader = FakeFileTypeFileReader(
            byteCountsByURL: [url: 12],
            leadingDataByURL: [url: Data("{\"late\":1}".utf8)],
            metadataDelayByURL: [url: 0.15]
        )
        let session = FileTypeDetectorSession(reader: reader)

        let task = session.inspect(url)
        #expect(session.canReset)
        #expect(session.isInspecting)
        session.reset()
        #expect(!session.canReset)
        #expect(session.selectedFileURL == nil)
        #expect(session.fileName.isEmpty)
        #expect(session.report == nil)
        #expect(session.error == nil)
        #expect(session.warning == nil)
        #expect(!session.isInspecting)

        await task.value
        try await Task.sleep(for: .milliseconds(80))
        #expect(!session.canReset)
        #expect(session.selectedFileURL == nil)
        #expect(session.fileName.isEmpty)
        #expect(session.report == nil)
        #expect(session.error == nil)
        #expect(session.warning == nil)
        #expect(!session.isInspecting)
    }

    @Test func resetCancelsPendingPanelAndIgnoresItsLateSelection() async throws {
        let url = URL(fileURLWithPath: "/tmp/reset-panel-late.json")
        let reader = FakeFileTypeFileReader(
            byteCountsByURL: [url: 12],
            leadingDataByURL: [url: Data("{\"late\":1}".utf8)]
        )
        let session = FileTypeDetectorSession(reader: reader)
        var continuation: CheckedContinuation<URL?, Never>?
        let panel = FileInputPanelClient { _ in
            await withCheckedContinuation { pending in
                continuation = pending
            }
        }

        let panelTask = session.selectFile(filePanel: panel)
        try await Self.waitUntil { continuation != nil }
        #expect(session.canReset)
        session.reset()
        #expect(!session.canReset)
        continuation?.resume(returning: url)
        await panelTask.value
        try await Task.sleep(for: .milliseconds(80))

        #expect(reader.metadataURLs.isEmpty)
        #expect(session.selectedFileURL == nil)
        #expect(session.fileName.isEmpty)
        #expect(session.report == nil)
        #expect(session.error == nil)
        #expect(session.warning == nil)
        #expect(!session.isInspecting)
        #expect(!session.canReset)
    }

    @Test func uploadPanelOwnsTheResetWithoutChangingBodyOrResultLayout() throws {
        let page = try readSource("Sources/XTools/ToolPages/Utility/FileTypeDetectorPage.swift")
        let session = try readSource("Sources/XTools/ToolPages/Utility/FileTypeDetectorSession.swift")

        contains(page, "IndexClearButton(\n                    isDisabled: !session.canReset,\n                    action: session.reset", "File detector reset must use the existing upload-panel header")
        contains(page, ".indexDropZone(", "File detector reset must preserve the shared drop target")
        contains(page, "IndexPanel(\"检测结果\")", "File detector reset must preserve the existing result panel")
        contains(session, "func reset()", "File detector reset must be owned by the retained session")
        contains(session, "cancelPanelRequest()", "File detector reset must cancel a pending panel request")
        contains(session, "cancelInspection()", "File detector reset must cancel and generation-invalidate inspection")
    }

    @Test func foundationReaderRejectsDirectoriesAsNonRegularFiles() {
        let reader = FoundationFileTypeFileReader()

        do {
            _ = try reader.metadata(for: URL(fileURLWithPath: "/tmp", isDirectory: true))
            Issue.record("Expected a directory to be rejected")
        } catch let issue as FileTypeDetector.InspectionIssue {
            #expect(issue == .notRegularFile)
        } catch {
            Issue.record("Unexpected failure: \(error)")
        }
    }

    private static func waitUntil(_ predicate: @escaping @MainActor () -> Bool) async throws {
        for _ in 0..<50 {
            if predicate() {
                return
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        Issue.record("Timed out waiting for detector state")
    }
}

private final class FakeFileTypeFileReader: FileTypeFileReading, @unchecked Sendable {
    let byteCountsByURL: [URL: Int64]
    let leadingDataByURL: [URL: Data]
    let metadataIssuesByURL: [URL: FileTypeDetector.InspectionIssue]
    let prefixIssuesByURL: [URL: FileTypeDetector.InspectionIssue]
    let metadataDelayByURL: [URL: TimeInterval]

    private let lock = NSLock()
    private var storedMetadataURLs: [URL] = []
    private var storedRequestedLeadingByteCounts: [Int] = []
    private var storedObservedMainThread = false

    var metadataURLs: [URL] {
        lock.withLock { storedMetadataURLs }
    }

    var requestedLeadingByteCounts: [Int] {
        lock.withLock { storedRequestedLeadingByteCounts }
    }

    var observedMainThread: Bool {
        lock.withLock { storedObservedMainThread }
    }

    init(
        byteCountsByURL: [URL: Int64],
        leadingDataByURL: [URL: Data],
        metadataIssuesByURL: [URL: FileTypeDetector.InspectionIssue] = [:],
        prefixIssuesByURL: [URL: FileTypeDetector.InspectionIssue] = [:],
        metadataDelayByURL: [URL: TimeInterval] = [:]
    ) {
        self.byteCountsByURL = byteCountsByURL
        self.leadingDataByURL = leadingDataByURL
        self.metadataIssuesByURL = metadataIssuesByURL
        self.prefixIssuesByURL = prefixIssuesByURL
        self.metadataDelayByURL = metadataDelayByURL
    }

    func metadata(for url: URL) throws -> FileTypeFileMetadata {
        lock.withLock {
            storedMetadataURLs.append(url)
            storedObservedMainThread = storedObservedMainThread || Thread.isMainThread
        }
        if let delay = metadataDelayByURL[url] {
            Thread.sleep(forTimeInterval: delay)
        }
        if let issue = metadataIssuesByURL[url] {
            throw issue
        }
        guard let byteCount = byteCountsByURL[url] else {
            throw FileTypeDetector.InspectionIssue.metadataReadFailed
        }
        return FileTypeFileMetadata(byteCount: byteCount)
    }

    func readLeadingData(from url: URL, maxByteCount: Int) throws -> Data {
        lock.withLock {
            storedRequestedLeadingByteCounts.append(maxByteCount)
            storedObservedMainThread = storedObservedMainThread || Thread.isMainThread
        }
        if let issue = prefixIssuesByURL[url] {
            throw issue
        }
        return leadingDataByURL[url] ?? Data()
    }
}
