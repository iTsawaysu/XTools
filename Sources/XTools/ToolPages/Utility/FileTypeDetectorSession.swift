import Combine
import XToolsCore
import Foundation
import UniformTypeIdentifiers

struct FileTypeFileMetadata: Equatable, Sendable {
    let byteCount: Int64
}

protocol FileTypeFileReading: Sendable {
    func metadata(for url: URL) throws -> FileTypeFileMetadata
    func readLeadingData(from url: URL, maxByteCount: Int) throws -> Data
}

struct FoundationFileTypeFileReader: FileTypeFileReading {
    func metadata(for url: URL) throws -> FileTypeFileMetadata {
        let values: URLResourceValues
        do {
            values = try url.resourceValues(
                forKeys: [.isRegularFileKey, .isPackageKey, .fileSizeKey]
            )
        } catch {
            throw FileTypeDetector.InspectionIssue.metadataReadFailed
        }

        guard values.isRegularFile == true, values.isPackage != true else {
            throw FileTypeDetector.InspectionIssue.notRegularFile
        }
        guard let byteCount = values.fileSize else {
            throw FileTypeDetector.InspectionIssue.metadataReadFailed
        }
        return FileTypeFileMetadata(byteCount: Int64(byteCount))
    }

    func readLeadingData(from url: URL, maxByteCount: Int) throws -> Data {
        do {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            return try handle.read(upToCount: maxByteCount) ?? Data()
        } catch {
            throw FileTypeDetector.InspectionIssue.contentReadFailed
        }
    }
}

@MainActor
final class FileTypeDetectorSession: ObservableObject {
    static let workspaceKey = ToolWorkspaceKey<FileTypeDetectorSession>(toolID: "file-type-detector") { _ in
        FileTypeDetectorSession()
    }

    @Published private(set) var selectedFileURL: URL?
    @Published private(set) var fileName = ""
    @Published private(set) var report: FileTypeReport?
    @Published private(set) var error: String?
    @Published private(set) var warning: String?
    @Published private(set) var isInspecting = false

    var canReset: Bool {
        selectedFileURL != nil
            || !fileName.isEmpty
            || report != nil
            || error != nil
            || warning != nil
            || isInspecting
            || panelTask != nil
    }

    private let reader: any FileTypeFileReading
    private var panelTask: Task<Void, Never>?
    private var activePanelRequestID: UUID?
    private let workGate = AsyncWorkGate()

    init(reader: any FileTypeFileReading = FoundationFileTypeFileReader()) {
        self.reader = reader
    }

    deinit {
        panelTask?.cancel()
    }

    @discardableResult
    func selectFile(filePanel: FileInputPanelClient) -> Task<Void, Never> {
        if let panelTask {
            return panelTask
        }

        let requestID = UUID()
        activePanelRequestID = requestID
        let task = Task { @MainActor [weak self] in
            do {
                guard let url = try await filePanel.selectFile(
                    FileInputPanelRequest(allowedContentTypes: [.data])
                ) else {
                    _ = self?.finishPanelRequest(id: requestID)
                    return
                }
                guard !Task.isCancelled,
                      let self,
                      self.finishPanelRequest(id: requestID) else {
                    return
                }
                self.inspect(url)
            } catch is CancellationError {
                _ = self?.finishPanelRequest(id: requestID)
            } catch {
                guard let self, self.finishPanelRequest(id: requestID) else { return }
                self.error = FileInputPanelFailure.diagnosticMessage(for: error)
            }
        }
        panelTask = task
        return task
    }

    @discardableResult
    func inspect(_ url: URL) -> Task<Void, Never> {
        cancelPanelRequest()
        let generation = workGate.invalidate()

        selectedFileURL = url
        fileName = url.lastPathComponent
        report = nil
        error = nil
        warning = nil
        isInspecting = true

        let reader = self.reader

        enum InspectionOutcome: Sendable {
            case success(FileTypeReport, warning: String?)
            case failure(String)
            case cancelled
        }

        workGate.runDetached {
            let accessedSecurityScope = url.startAccessingSecurityScopedResource()
            defer {
                if accessedSecurityScope {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            do {
                try Task.checkCancellation()
                let metadata = try reader.metadata(for: url)
                try Task.checkCancellation()

                let leadingData: Data?
                let prefixWarning: String?
                do {
                    leadingData = try reader.readLeadingData(
                        from: url,
                        maxByteCount: FileTypeDetector.leadingByteLimit
                    )
                    prefixWarning = nil
                } catch {
                    leadingData = nil
                    prefixWarning = FileTypeDetector.diagnosticMessage(
                        for: error,
                        defaultIssue: .contentReadFailed
                    )
                }
                try Task.checkCancellation()
                let report = FileTypeDetector.inspect(
                    fileName: url.lastPathComponent,
                    byteCount: metadata.byteCount,
                    leadingData: leadingData
                )
                return InspectionOutcome.success(
                    report,
                    warning: prefixWarning ?? report.conflictDiagnostic
                )
            } catch is CancellationError {
                return .cancelled
            } catch {
                return .failure(
                    FileTypeDetector.diagnosticMessage(
                        for: error,
                        defaultIssue: .metadataReadFailed
                    )
                )
            }
        } publish: { [weak self] outcome in
            guard let self, self.workGate.isCurrent(generation) else { return }
            self.isInspecting = false
            switch outcome {
            case .success(let report, let warning):
                self.report = report
                self.fileName = report.fileName
                self.error = nil
                self.warning = warning
            case .failure(let message):
                self.report = nil
                self.error = message
                self.warning = nil
            case .cancelled:
                break
            }
        }

        // Return a completed task handle for API compatibility with callers that await inspect.
        return Task { @MainActor in
            // Busy work is owned by workGate; callers only need a joinable Task.
            while self.isInspecting && self.workGate.isCurrent(generation) {
                try? await Task.sleep(for: .milliseconds(10))
            }
        }
    }

    func reset() {
        cancelPanelRequest()
        cancelInspection()
        selectedFileURL = nil
        fileName = ""
        report = nil
        error = nil
        warning = nil
        isInspecting = false
    }

    func rejectMultipleFileDrop() {
        cancelPanelRequest()
        cancelInspection()
        selectedFileURL = nil
        fileName = ""
        report = nil
        error = SingleFileDropResolver.multipleFilesDiagnostic
        warning = nil
        isInspecting = false
    }

    private func finishPanelRequest(id: UUID) -> Bool {
        guard activePanelRequestID == id else { return false }
        activePanelRequestID = nil
        panelTask = nil
        return true
    }

    private func cancelPanelRequest() {
        activePanelRequestID = nil
        panelTask?.cancel()
        panelTask = nil
    }

    private func cancelInspection() {
        workGate.invalidate()
        isInspecting = false
    }
}
