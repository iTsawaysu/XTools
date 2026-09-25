import AppKit
import Combine
import XToolsCore
import Foundation
import ImageIO
import UniformTypeIdentifiers

// Core owns pure workspace enums/state; UI session publishes them.

struct Base64FileImagePreview: @unchecked Sendable {
    let image: CGImage
    let pixelSize: CGSize

    @MainActor
    func makeNSImage() -> NSImage {
        NSImage(cgImage: image, size: pixelSize)
    }
}

enum Base64FileWorkflow {
    static let previewImageByteLimit = Base64FileLimits.previewImageByteLimit
    static let previewImageMaxPixelLength = Base64FileLimits.previewImageMaxPixelLength
    static let maxDecodedPayloadBytes = Base64FileLimits.maxDecodedPayloadBytes

    /// Keeps detached work cancellable when the owning workspace is superseded.
    /// The generation checks in the session still guard publication; this helper
    /// additionally forwards task cancellation to the detached worker.
    private static func runDetached<Output: Sendable>(
        _ operation: @escaping @Sendable () -> Output
    ) async -> Output {
        let task = Task.detached(priority: .userInitiated, operation: operation)
        return await withTaskCancellationHandler(operation: {
            await task.value
        }, onCancel: {
            task.cancel()
        })
    }

    static func readSelection(
        from url: URL,
        maxBytes: Int
    ) async -> Result<Base64FileSelection, Base64FileWorkflowFailure> {
        await runDetached {
            do {
                let hasScopedAccess = url.startAccessingSecurityScopedResource()
                defer {
                    if hasScopedAccess {
                        url.stopAccessingSecurityScopedResource()
                    }
                }

                let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isPackageKey, .contentTypeKey])
                guard values.isRegularFile == true, values.isPackage != true else {
                    return .failure(.notRegularFile)
                }
                guard let fileSize = values.fileSize, fileSize <= maxBytes else {
                    return .failure(.tooLarge(fileName: url.lastPathComponent, maxBytes: maxBytes))
                }

                let data: Data
                do {
                    data = try BoundedFileReader.read(from: url, maxBytes: maxBytes)
                } catch BoundedFileReader.ReadError.tooLarge {
                    return .failure(.tooLarge(fileName: url.lastPathComponent, maxBytes: maxBytes))
                }
                return .success(
                    Base64FileSelection(
                        fileName: url.lastPathComponent,
                        data: data,
                        mimeType: mimeType(for: data, resourceValues: values)
                    )
                )
            } catch let failure as Base64FileWorkflowFailure {
                return .failure(failure)
            } catch {
                return .failure(.readFailed)
            }
        }
    }

    static func outputPreview(
        for selection: Base64FileSelection,
        mode: Base64Conversion.FileOutputMode
    ) async -> Base64Conversion.EncodedFileOutputPreview {
        await runDetached {
            Base64Conversion.encodedOutputPreview(
                for: selection.data,
                mimeType: selection.mimeType,
                mode: mode
            )
        }
    }

    static func fullOutput(
        for selection: Base64FileSelection,
        mode: Base64Conversion.FileOutputMode
    ) async -> String {
        await runDetached {
            Base64Conversion.encodedOutput(
                for: selection.data,
                mimeType: selection.mimeType,
                mode: mode
            )
        }
    }

    static func decodePayload(
        _ input: String,
        maxDecodedBytes: Int = maxDecodedPayloadBytes
    ) async -> Result<Base64Conversion.FilePayload, Base64FileWorkflowFailure> {
        await runDetached {
            do {
                let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
                let encodedPayload = try encodedPayload(in: trimmed)
                guard Base64Conversion.decodedByteCountUpperBound(forBase64Payload: encodedPayload) <= maxDecodedBytes else {
                    return .failure(.decodedTooLarge(maxBytes: maxDecodedBytes))
                }

                let payload = try Base64Conversion.decodeFilePayload(trimmed)
                guard payload.data.count <= maxDecodedBytes else {
                    return .failure(.decodedTooLarge(maxBytes: maxDecodedBytes))
                }
                return .success(payload)
            } catch let failure as Base64FileWorkflowFailure {
                return .failure(failure)
            } catch {
                return .failure(.invalidPayload)
            }
        }
    }

    static func decodedPayload(for selection: Base64FileSelection) async -> Base64Conversion.FilePayload {
        await runDetached {
            Base64Conversion.FilePayload(
                data: selection.data,
                mimeType: selection.mimeType,
                fileExtension: fileExtension(for: selection)
            )
        }
    }

    static func readEncodedText(
        from url: URL,
        maxBytes: Int
    ) async -> Result<Base64FileEncodedTextInput, Base64FileWorkflowFailure> {
        await runDetached {
            do {
                let hasScopedAccess = url.startAccessingSecurityScopedResource()
                defer {
                    if hasScopedAccess {
                        url.stopAccessingSecurityScopedResource()
                    }
                }

                let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isPackageKey])
                guard values.isRegularFile == true, values.isPackage != true else {
                    return .failure(.notRegularFile)
                }
                if let fileSize = values.fileSize, fileSize > maxBytes {
                    return .failure(.externalEncodedTextTooLarge(maxBytes: maxBytes))
                }

                let data: Data
                do {
                    data = try BoundedFileReader.read(from: url, maxBytes: maxBytes)
                } catch BoundedFileReader.ReadError.tooLarge {
                    return .failure(.externalEncodedTextTooLarge(maxBytes: maxBytes))
                }
                guard let text = String(data: data, encoding: .utf8) else {
                    return .failure(.encodedTextNotUTF8)
                }

                return .success(Base64FileEncodedTextInput(fileName: url.lastPathComponent, text: text))
            } catch let failure as Base64FileWorkflowFailure {
                return .failure(failure)
            } catch {
                return .failure(.readFailed)
            }
        }
    }

    static func write(_ data: Data, to url: URL) async -> Result<Void, Base64FileWorkflowFailure> {
        await runDetached {
            do {
                try data.write(to: url, options: .atomic)
                return .success(())
            } catch {
                return .failure(.saveFailed)
            }
        }
    }

    static func write(_ text: String, to url: URL) async -> Result<Void, Base64FileWorkflowFailure> {
        await runDetached {
            do {
                try text.write(to: url, atomically: true, encoding: .utf8)
                return .success(())
            } catch {
                return .failure(.saveFailed)
            }
        }
    }

    static func previewImage(for payload: Base64Conversion.FilePayload) async -> Base64FileImagePreview? {
        await runDetached {
            guard payload.mimeType.hasPrefix("image/"),
                  payload.data.count <= previewImageByteLimit,
                  let source = CGImageSourceCreateWithData(payload.data as CFData, [
                      kCGImageSourceShouldCache: false
                  ] as CFDictionary) else {
                return nil
            }

            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: previewImageMaxPixelLength
            ]
            guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
                return nil
            }

            return Base64FileImagePreview(
                image: image,
                pixelSize: CGSize(width: image.width, height: image.height)
            )
        }
    }

    static func outputFileName(
        sourceFileName: String,
        mode: Base64Conversion.FileOutputMode
    ) -> String {
        let fallback = "encoded"
        let baseName = URL(fileURLWithPath: sourceFileName).deletingPathExtension().lastPathComponent
        let safeBaseName = baseName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? fallback : baseName

        switch mode {
        case .base64:
            return "\(safeBaseName).base64.txt"
        case .dataURL:
            return "\(safeBaseName).data-url.txt"
        }
    }

    private static func mimeType(for data: Data, resourceValues values: URLResourceValues) -> String {
        values.contentType?.preferredMIMEType
            ?? Base64Conversion.inferredFileType(for: data)?.mimeType
            ?? "application/octet-stream"
    }

    private static func fileExtension(for selection: Base64FileSelection) -> String {
        let sourceExtension = URL(fileURLWithPath: selection.fileName).pathExtension
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !sourceExtension.isEmpty {
            return sourceExtension
        }

        return Base64Conversion.fileType(forMIMEType: selection.mimeType)?.fileExtension
            ?? Base64Conversion.inferredFileType(for: selection.data)?.fileExtension
            ?? "bin"
    }

    private static func encodedPayload(in trimmed: String) throws -> String {
        if trimmed.lowercased().hasPrefix("data:") {
            return try Base64Conversion.parseDataURL(trimmed).base64Payload
        } else {
            return trimmed
        }
    }
}

@MainActor
protocol Base64FileWorkflowProcessing: Sendable {
    func readSelection(
        from url: URL,
        maxBytes: Int
    ) async -> Result<Base64FileSelection, Base64FileWorkflowFailure>

    func outputPreview(
        for selection: Base64FileSelection,
        mode: Base64Conversion.FileOutputMode
    ) async -> Base64Conversion.EncodedFileOutputPreview

    func fullOutput(
        for selection: Base64FileSelection,
        mode: Base64Conversion.FileOutputMode
    ) async -> String

    func serializeUTF8(_ text: String) async -> Data

    func decodePayload(_ input: String) async -> Result<Base64Conversion.FilePayload, Base64FileWorkflowFailure>

    func decodedPayload(for selection: Base64FileSelection) async -> Base64Conversion.FilePayload

    func readEncodedText(
        from url: URL,
        maxBytes: Int
    ) async -> Result<Base64FileEncodedTextInput, Base64FileWorkflowFailure>

    func previewImage(for payload: Base64Conversion.FilePayload) async -> Base64FileImagePreview?

    func write(_ data: Data, to url: URL) async -> Result<Void, Base64FileWorkflowFailure>

    func write(_ text: String, to url: URL) async -> Result<Void, Base64FileWorkflowFailure>
}

extension Base64FileWorkflowProcessing {
    func readSelection(
        from url: URL,
        maxBytes: Int
    ) async -> Result<Base64FileSelection, Base64FileWorkflowFailure> {
        await Base64FileWorkflow.readSelection(from: url, maxBytes: maxBytes)
    }

    func outputPreview(
        for selection: Base64FileSelection,
        mode: Base64Conversion.FileOutputMode
    ) async -> Base64Conversion.EncodedFileOutputPreview {
        await Base64FileWorkflow.outputPreview(for: selection, mode: mode)
    }

    func fullOutput(
        for selection: Base64FileSelection,
        mode: Base64Conversion.FileOutputMode
    ) async -> String {
        await Base64FileWorkflow.fullOutput(for: selection, mode: mode)
    }

    func serializeUTF8(_ text: String) async -> Data {
        await Task.detached(priority: .userInitiated) {
            Data(text.utf8)
        }.value
    }

    func decodePayload(_ input: String) async -> Result<Base64Conversion.FilePayload, Base64FileWorkflowFailure> {
        await Base64FileWorkflow.decodePayload(input)
    }

    func decodedPayload(for selection: Base64FileSelection) async -> Base64Conversion.FilePayload {
        await Base64FileWorkflow.decodedPayload(for: selection)
    }

    func readEncodedText(
        from url: URL,
        maxBytes: Int
    ) async -> Result<Base64FileEncodedTextInput, Base64FileWorkflowFailure> {
        await Base64FileWorkflow.readEncodedText(from: url, maxBytes: maxBytes)
    }

    func previewImage(for payload: Base64Conversion.FilePayload) async -> Base64FileImagePreview? {
        await Base64FileWorkflow.previewImage(for: payload)
    }

    func write(_ data: Data, to url: URL) async -> Result<Void, Base64FileWorkflowFailure> {
        await Base64FileWorkflow.write(data, to: url)
    }

    func write(_ text: String, to url: URL) async -> Result<Void, Base64FileWorkflowFailure> {
        await Base64FileWorkflow.write(text, to: url)
    }
}

struct Base64FileWorkflowLive: Base64FileWorkflowProcessing {}

@MainActor
protocol Base64FileWorkflowDialoging: Sendable {
    func selectEncodedOutputURL(defaultFilename: String) async -> URL?
    func selectDecodedOutputURL(defaultFilename: String, fileExtension: String) async -> URL?
}

@MainActor
protocol Base64FilePasteboardWriting: Sendable {
    /// Takes pre-serialized UTF-8 so callers can build the payload off the
    /// main thread; NSPasteboard itself must only be touched on main.
    func writeUTF8(_ data: Data) -> Bool
}

@MainActor
struct Base64FileWorkflowClient: Sendable {
    private let dialog: any Base64FileWorkflowDialoging
    private let pasteboard: any Base64FilePasteboardWriting

    init(
        dialog: any Base64FileWorkflowDialoging = NoOpBase64FileWorkflowDialog(),
        pasteboard: any Base64FilePasteboardWriting = AppKitBase64FilePasteboard()
    ) {
        self.dialog = dialog
        self.pasteboard = pasteboard
    }

    func selectEncodedOutputURL(defaultFilename: String) async -> URL? {
        await dialog.selectEncodedOutputURL(defaultFilename: defaultFilename)
    }

    func selectDecodedOutputURL(defaultFilename: String, fileExtension: String) async -> URL? {
        await dialog.selectDecodedOutputURL(defaultFilename: defaultFilename, fileExtension: fileExtension)
    }

    /// Sheet-based production dialog bound to the window-scoped output panel.
    static func sheet(outputPanel: FileOutputPanelClient) -> Base64FileWorkflowClient {
        Base64FileWorkflowClient(dialog: SheetBase64FileWorkflowDialog(outputPanel: outputPanel))
    }

    func copyUTF8(_ data: Data) -> Bool {
        pasteboard.writeUTF8(data)
    }
}

/// Default no-op dialog: the page always injects the sheet dialog bound to
/// the window-scoped output panel client.
struct NoOpBase64FileWorkflowDialog: Base64FileWorkflowDialoging {
    func selectEncodedOutputURL(defaultFilename: String) async -> URL? { nil }
    func selectDecodedOutputURL(defaultFilename: String, fileExtension: String) async -> URL? { nil }
}

/// Sheet-based save dialog: selection suspends the caller instead of running
/// a synchronous modal event loop.
struct SheetBase64FileWorkflowDialog: Base64FileWorkflowDialoging {
    let outputPanel: FileOutputPanelClient

    func selectEncodedOutputURL(defaultFilename: String) async -> URL? {
        let request = FileOutputPanelRequest(
            defaultFilename: defaultFilename,
            allowedContentTypes: [.plainText],
            prompt: "存储"
        )
        return try? await outputPanel.selectFile(request)
    }

    func selectDecodedOutputURL(defaultFilename: String, fileExtension: String) async -> URL? {
        var allowedContentTypes: [UTType] = []
        if let contentType = UTType(filenameExtension: fileExtension) {
            allowedContentTypes = [contentType]
        }
        let request = FileOutputPanelRequest(
            defaultFilename: defaultFilename,
            allowedContentTypes: allowedContentTypes,
            prompt: "存储"
        )
        return try? await outputPanel.selectFile(request)
    }
}

@MainActor
private struct AppKitBase64FilePasteboard: Base64FilePasteboardWriting {
    func writeUTF8(_ data: Data) -> Bool {
        NSPasteboard.general.clearContents()
        return NSPasteboard.general.setData(data, forType: .string)
    }
}

@MainActor
final class Base64FileWorkflowSession: ObservableObject, ToolWorkspacePayloadEvicting {
    static let workspaceKey = ToolWorkspaceKey<Base64FileWorkflowSession>(
        toolID: "base64-file-converter"
    ) { preferences in
        Base64FileWorkflowSession(preferences: preferences)
    }

    static let maxFileBytes = 50 * 1024 * 1024
    static let editableReverseInputByteLimit = 1 * 1024 * 1024
    static let externalEncodedTextByteLimit = 16 * 1024 * 1024
    static let reverseInputUndoLevels = 20
    static let encodedTextContentTypes: [UTType] = [
        .plainText,
        .text,
        UTType(filenameExtension: "base64"),
        UTType(filenameExtension: "data-url")
    ].compactMap { $0 }

    /// Single pure-state source of truth. UI reads project through computed fields.
    @Published private(set) var state: Base64FileWorkspaceSessionState
    @Published private(set) var previewImage: NSImage?

    var direction: Base64FileWorkflowDirection { state.direction }
    var outputMode: Base64Conversion.FileOutputMode { state.outputMode }
    var isReadingFile: Bool { state.isReadingFile }
    var isPreparingOutput: Bool { state.isPreparingOutput }
    var outputAction: Base64FileOutputAction? { state.outputAction }
    var fileError: String? { state.fileError }
    var reverseInput: String { state.reverseInput }
    var outputFileName: String {
        get { state.outputFileName }
        set {
            guard state.outputFileName != newValue else { return }
            mutate { $0.outputFileName = newValue }
        }
    }
    var defaultOutputFileName: String { state.defaultOutputFileName }
    var decodedPayload: Base64Conversion.FilePayload? { state.decodedPayload }
    var decodedResultSource: Base64FileDecodedResultSource? { state.decodedResultSource }
    var reverseError: String? { state.reverseError }
    var reverseInputDirty: Bool { state.reverseInputDirty }
    var decodeActivity: Base64FileDecodeActivity? { state.decodeActivity }
    var isSavingDecoded: Bool { state.isSavingDecoded }
    var isDecoding: Bool { state.isDecoding }
    var selectedFile: Base64FileSelection? { state.selectedFile }
    var outputPreview: Base64Conversion.EncodedFileOutputPreview? { state.outputPreview }

    private let preferences: ToolPreferenceStore?

    init(preferences: ToolPreferenceStore? = nil) {
        self.preferences = preferences
        let mode = preferences?.value(for: MediaToolPreferenceKeys.base64FileOutputMode) ?? .dataURL
        state = Base64FileWorkspaceSessionState(outputMode: mode)
    }

    func changeDirection(to newDirection: Base64FileWorkflowDirection) {
        mutate { $0.changeDirection(to: newDirection) }
    }

    @discardableResult
    func changeOutputMode(
        to newMode: Base64Conversion.FileOutputMode,
        processor: any Base64FileWorkflowProcessing = Base64FileWorkflowLive()
    ) -> Task<Void, Never>? {
        guard !isReadingFile, outputMode != newMode else { return nil }
        mutate {
            $0.outputMode = newMode
            $0.setFileError(nil)
        }
        preferences?.set(newMode, for: MediaToolPreferenceKeys.base64FileOutputMode)
        return refreshOutputPreview(processor: processor)
    }

    @discardableResult
    func selectSourceFile(
        filePanel: FileInputPanelClient,
        maxBytes: Int = maxFileBytes,
        processor: any Base64FileWorkflowProcessing = Base64FileWorkflowLive()
    ) -> Task<Void, Never> {
        Task {
            do {
                guard let url = try await filePanel.selectFile(
                    FileInputPanelRequest(allowedContentTypes: [.data])
                ) else {
                    return
                }
                await readSelectedFile(from: url, maxBytes: maxBytes, processor: processor)?.value
            } catch is CancellationError {
                return
            } catch {
                mutate { $0.setFileError(FileInputPanelFailure.diagnosticMessage(for: error)) }
            }
        }
    }

    @discardableResult
    func readSelectedFile(
        from url: URL,
        maxBytes: Int = maxFileBytes,
        processor: any Base64FileWorkflowProcessing = Base64FileWorkflowLive()
    ) -> Task<Void, Never>? {
        guard !isReadingFile else { return nil }

        mutate { $0.beginFileRead() }
        let fileGeneration = state.fileReadGeneration
        let outputGeneration = state.outputGeneration
        let mode = outputMode

        return Task {
            let result = await processor.readSelection(from: url, maxBytes: maxBytes)
            guard isCurrentFileRead(
                fileGeneration: fileGeneration,
                outputGeneration: outputGeneration,
                mode: mode
            ) else { return }
            if Task.isCancelled {
                mutate { $0.isReadingFile = false }
                return
            }

            switch result {
            case .success(let selection):
                let preview = await processor.outputPreview(for: selection, mode: mode)
                guard isCurrentFileRead(
                    fileGeneration: fileGeneration,
                    outputGeneration: outputGeneration,
                    mode: mode
                ) else { return }
                if Task.isCancelled {
                    mutate { $0.isReadingFile = false }
                    return
                }

                mutate { $0.applySuccessfulFileRead(selection: selection, preview: preview) }
            case .failure(let failure):
                mutate {
                    $0.applyFileReadFailure(failure.errorDescription ?? "无法读取所选文件。")
                }
            }
        }
    }

    @discardableResult
    func refreshOutputPreview(
        processor: any Base64FileWorkflowProcessing = Base64FileWorkflowLive()
    ) -> Task<Void, Never>? {
        guard let selectedFile else {
            mutate { $0.clearOutputPreviewWorkspace() }
            return nil
        }

        mutate { $0.beginOutputPreviewRefresh() }
        let generation = state.outputGeneration
        let mode = outputMode

        return Task {
            let preview = await processor.outputPreview(for: selectedFile, mode: mode)
            guard isCurrentEncodedOutput(selection: selectedFile, mode: mode, generation: generation) else {
                return
            }

            mutate { $0.applyOutputPreview(selection: selectedFile, preview: preview) }
        }
    }

    func clearSelection() {
        mutate { $0.clearSelection() }
    }

    /// Drops file bytes, previews, and decoded payloads while keeping reverse
    /// draft text, direction, output mode, and filename preferences.
    func evictHeavyPayloads() {
        mutate { $0.evictHeavyPayloads() }
        previewImage = nil
    }

    func rejectMultipleSourceFileDrop() {
        clearSelection()
        mutate { $0.setFileError(SingleFileDropResolver.multipleFilesDiagnostic) }
    }

    @discardableResult
    func copyFullOutput(
        client: Base64FileWorkflowClient = Base64FileWorkflowClient(),
        processor: any Base64FileWorkflowProcessing = Base64FileWorkflowLive(),
        onSuccess: @escaping @MainActor () -> Void = {}
    ) -> Task<Void, Never>? {
        guard direction == .encode, outputAction == nil, !isReadingFile, !isPreparingOutput,
              let selectedFile else { return nil }

        let mode = outputMode
        let generation = state.outputGeneration
        mutate { $0.beginCopyAction() }

        return Task {
            let text = await processor.fullOutput(for: selectedFile, mode: mode)
            guard isCurrentOutputAction(.copying, selection: selectedFile, mode: mode, generation: generation),
                  !Task.isCancelled else {
                finishOutputAction(.copying, generation: generation)
                return
            }

            // Serialize UTF-8 off the main thread; the payload can be tens
            // of megabytes for large files.
            let utf8 = await processor.serializeUTF8(text)
            guard isCurrentOutputAction(.copying, selection: selectedFile, mode: mode, generation: generation),
                  !Task.isCancelled else {
                finishOutputAction(.copying, generation: generation)
                return
            }
            if client.copyUTF8(utf8) {
                mutate { $0.setFileError(nil) }
                onSuccess()
            } else {
                mutate {
                    $0.setFileError(
                        Base64FileWorkflowFailure.copyFailed.errorDescription ?? "无法复制编码结果。"
                    )
                }
            }
            finishOutputAction(.copying, generation: generation)
        }
    }

    @discardableResult
    func saveEncodedOutput(
        client: Base64FileWorkflowClient = Base64FileWorkflowClient(),
        processor: any Base64FileWorkflowProcessing = Base64FileWorkflowLive(),
        onSuccess: @escaping @MainActor () -> Void = {}
    ) -> Task<Void, Never>? {
        guard direction == .encode, outputAction == nil, !isReadingFile, !isPreparingOutput,
              let selectedFile else { return nil }

        let mode = outputMode
        let generation = state.outputGeneration
        let defaultFilename = Base64FileWorkflow.outputFileName(sourceFileName: selectedFile.fileName, mode: mode)

        mutate { $0.beginSaveEncodedAction() }

        return Task {
            // Sheet selection suspends here; a cancelled panel ends the busy state.
            guard let url = await client.selectEncodedOutputURL(defaultFilename: defaultFilename) else {
                finishOutputAction(.saving, generation: generation)
                return
            }

            guard isCurrentOutputAction(.saving, selection: selectedFile, mode: mode, generation: generation),
                  !Task.isCancelled else {
                finishOutputAction(.saving, generation: generation)
                return
            }

            let text = await processor.fullOutput(for: selectedFile, mode: mode)
            guard isCurrentOutputAction(.saving, selection: selectedFile, mode: mode, generation: generation),
                  !Task.isCancelled else {
                finishOutputAction(.saving, generation: generation)
                return
            }

            let result = await processor.write(text, to: url)
            guard isCurrentOutputAction(.saving, selection: selectedFile, mode: mode, generation: generation),
                  !Task.isCancelled else {
                finishOutputAction(.saving, generation: generation)
                return
            }

            switch result {
            case .success:
                mutate { $0.setFileError(nil) }
                onSuccess()
            case .failure(let failure):
                mutate { $0.setFileError(failure.errorDescription ?? "无法保存文件。") }
            }
            finishOutputAction(.saving, generation: generation)
        }
    }

    func updateReverseInput(_ newValue: String) {
        guard newValue.utf8.count <= Self.editableReverseInputByteLimit else {
            rejectReverseInputLimit()
            return
        }

        guard reverseInput != newValue else { return }

        mutate { $0.updateReverseInput(newValue) }
        previewImage = nil
    }

    func rejectReverseInputLimit(maxBytes: Int = editableReverseInputByteLimit) {
        mutate {
            $0.rejectReverseInputLimit(
                message: Base64FileWorkflowFailure.reverseInputTooLarge(maxBytes: maxBytes).errorDescription
                    ?? "可编辑的 Base64 或 Data URL 不能超过限制。"
            )
        }
        previewImage = nil
    }

    @discardableResult
    func decodeReverseInput(
        processor: any Base64FileWorkflowProcessing = Base64FileWorkflowLive()
    ) -> Task<Void, Never>? {
        let trimmed = reverseInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            clearReverse()
            return nil
        }

        let generation = beginDecodeAttempt(.manualInput)
        let inputSnapshot = trimmed
        mutate { $0.reverseInputDirty = false }

        return Task {
            let result = await processor.decodePayload(inputSnapshot)
            let decodedPreview: Base64FileImagePreview?
            if case .success(let payload) = result {
                decodedPreview = await processor.previewImage(for: payload)
            } else {
                decodedPreview = nil
            }

            guard isCurrentDecode(input: inputSnapshot, generation: generation) else { return }

            switch result {
            case .success(let payload):
                applyDecodedPayload(
                    payload,
                    preview: decodedPreview,
                    source: .manualInput,
                    defaultOutputFileName: "download"
                )
            case .failure(let failure):
                mutate {
                    $0.applyDecodeFailure(
                        failure.errorDescription ?? "输入不是有效的 Base64 或 Base64 Data URL。"
                    )
                }
                previewImage = nil
            }
            finishDecodeAttempt(.manualInput, generation: generation)
        }
    }

    @discardableResult
    func sendCurrentOutputToDecodeResult(
        processor: any Base64FileWorkflowProcessing = Base64FileWorkflowLive()
    ) -> Task<Void, Never>? {
        guard direction == .encode, outputAction == nil, !isReadingFile, !isPreparingOutput,
              let selectedFile else { return nil }

        let generation = beginDecodeAttempt(.encodedOutputPreview)
        let outputGeneration = state.outputGeneration
        let mode = outputMode
        mutate { $0.beginSendToDecodeAction() }

        return Task {
            let payload = await processor.decodedPayload(for: selectedFile)
            guard isCurrentOutputAction(.sending, selection: selectedFile, mode: mode, generation: outputGeneration),
                  state.decodeGeneration == generation, !Task.isCancelled else {
                if state.decodeGeneration == generation {
                    finishOutputAction(.sending, generation: outputGeneration)
                }
                finishDecodeAttempt(.encodedOutputPreview, generation: generation)
                return
            }
            let decodedPreview = await processor.previewImage(for: payload)
            guard isCurrentOutputAction(.sending, selection: selectedFile, mode: mode, generation: outputGeneration),
                  state.decodeGeneration == generation, !Task.isCancelled else {
                if state.decodeGeneration == generation {
                    finishOutputAction(.sending, generation: outputGeneration)
                }
                finishDecodeAttempt(.encodedOutputPreview, generation: generation)
                return
            }

            mutate {
                $0.reverseInputDirty = !$0.reverseInput
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .isEmpty
            }
            applyDecodedPayload(
                payload,
                preview: decodedPreview,
                source: .currentEncodedOutput(fileName: selectedFile.fileName),
                defaultOutputFileName: selectedFile.fileName
            )
            mutate {
                $0.direction = .decode
                $0.clearOutputAction(.sending, generation: outputGeneration)
            }
            finishDecodeAttempt(.encodedOutputPreview, generation: generation)
        }
    }

    @discardableResult
    func importEncodedTextFile(
        filePanel: FileInputPanelClient,
        processor: any Base64FileWorkflowProcessing = Base64FileWorkflowLive()
    ) -> Task<Void, Never> {
        Task {
            do {
                guard let url = try await filePanel.selectFile(
                    FileInputPanelRequest(allowedContentTypes: Self.encodedTextContentTypes)
                ) else {
                    return
                }
                await importEncodedTextFile(from: url, processor: processor).value
            } catch is CancellationError {
                return
            } catch {
                mutate { $0.setReverseError(FileInputPanelFailure.diagnosticMessage(for: error)) }
            }
        }
    }

    @discardableResult
    func importEncodedTextFile(
        from url: URL,
        processor: any Base64FileWorkflowProcessing = Base64FileWorkflowLive()
    ) -> Task<Void, Never> {

        let generation = beginDecodeAttempt(.encodedTextImport)

        return Task {
            let inputResult = await processor.readEncodedText(
                from: url,
                maxBytes: Self.externalEncodedTextByteLimit
            )
            guard state.decodeGeneration == generation else { return }
            if Task.isCancelled {
                finishDecodeAttempt(.encodedTextImport, generation: generation)
                return
            }

            switch inputResult {
            case .success(let input):
                await decodeExternalEncodedText(
                    input.text,
                    source: .encodedTextFile(fileName: input.fileName),
                    defaultOutputFileName: defaultImportedOutputName(for: input.fileName),
                    processor: processor,
                    existingGeneration: generation
                )?.value
            case .failure(let failure):
                mutate {
                    $0.setReverseError(failure.errorDescription ?? "无法读取所选文件。")
                }
                finishDecodeAttempt(.encodedTextImport, generation: generation)
            }
        }
    }

    @discardableResult
    func saveDecodedPayload(
        client: Base64FileWorkflowClient = Base64FileWorkflowClient(),
        processor: any Base64FileWorkflowProcessing = Base64FileWorkflowLive(),
        onSuccess: @escaping @MainActor () -> Void = {}
    ) -> Task<Void, Never>? {
        guard !isSavingDecoded, let payload = decodedPayload else { return nil }

        let generation = state.decodeGeneration
        let defaultFilename = Base64Conversion.normalizedFileName(outputFileName, fileExtension: payload.fileExtension)

        mutate { $0.beginSavingDecoded() }

        return Task {
            // Sheet selection suspends here; a cancelled panel ends the busy state.
            guard let url = await client.selectDecodedOutputURL(
                defaultFilename: defaultFilename,
                fileExtension: payload.fileExtension
            ) else {
                finishDecodedSave(generation: generation)
                return
            }

            guard isSavingDecoded, isCurrentDecodedPayload(payload, generation: generation),
                  !Task.isCancelled else {
                finishDecodedSave(generation: generation)
                return
            }

            let result = await processor.write(payload.data, to: url)
            guard isSavingDecoded, isCurrentDecodedPayload(payload, generation: generation),
                  !Task.isCancelled else {
                finishDecodedSave(generation: generation)
                return
            }

            switch result {
            case .success:
                mutate { $0.setReverseError(nil) }
                onSuccess()
            case .failure(let failure):
                finishDecodedSave(
                    generation: generation,
                    error: failure.errorDescription ?? "无法保存文件。"
                )
                return
            }
            finishDecodedSave(generation: generation)
        }
    }

    func clearReverse() {
        mutate { $0.clearReverseDraft() }
        previewImage = nil
    }

    func resetOutputFileName() {
        outputFileName = defaultOutputFileName
    }

    @discardableResult
    private func decodeExternalEncodedText(
        _ text: String,
        source: Base64FileDecodedResultSource,
        defaultOutputFileName: String,
        processor: any Base64FileWorkflowProcessing,
        existingGeneration: Int? = nil
    ) -> Task<Void, Never>? {
        let generation = existingGeneration ?? beginDecodeAttempt(.encodedTextImport)

        guard text.utf8.count <= Self.externalEncodedTextByteLimit else {
            mutate {
                $0.setReverseError(
                    Base64FileWorkflowFailure.externalEncodedTextTooLarge(
                        maxBytes: Self.externalEncodedTextByteLimit
                    ).errorDescription
                )
            }
            finishDecodeAttempt(.encodedTextImport, generation: generation)
            return nil
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            mutate {
                $0.setReverseError(Base64FileWorkflowFailure.invalidPayload.errorDescription)
            }
            finishDecodeAttempt(.encodedTextImport, generation: generation)
            return nil
        }

        return Task {
            let result = await processor.decodePayload(trimmed)
            let decodedPreview: Base64FileImagePreview?
            if case .success(let payload) = result {
                decodedPreview = await processor.previewImage(for: payload)
            } else {
                decodedPreview = nil
            }

            guard state.decodeGeneration == generation else { return }

            switch result {
            case .success(let payload):
                applyDecodedPayload(
                    payload,
                    preview: decodedPreview,
                    source: source,
                    defaultOutputFileName: defaultOutputFileName
                )
            case .failure(let failure):
                mutate {
                    $0.applyDecodeFailure(
                        failure.errorDescription ?? "输入不是有效的 Base64 或 Base64 Data URL。"
                    )
                }
                previewImage = nil
            }
            finishDecodeAttempt(.encodedTextImport, generation: generation)
        }
    }

    @discardableResult
    private func beginDecodeAttempt(_ activity: Base64FileDecodeActivity) -> Int {
        var generation = 0
        mutate {
            generation = $0.beginDecodeAttempt(activity)
        }
        previewImage = nil
        return generation
    }

    private func finishDecodeAttempt(
        _ activity: Base64FileDecodeActivity,
        generation: Int
    ) {
        mutate { $0.finishDecodeAttempt(activity, generation: generation) }
    }

    private func applyDecodedPayload(
        _ payload: Base64Conversion.FilePayload,
        preview: Base64FileImagePreview?,
        source: Base64FileDecodedResultSource,
        defaultOutputFileName defaultName: String
    ) {
        mutate {
            $0.applyDecodedPayload(
                payload,
                source: source,
                defaultOutputFileName: defaultName
            )
        }
        previewImage = preview?.makeNSImage()
    }

    private func defaultImportedOutputName(for fileName: String) -> String {
        let baseName = URL(fileURLWithPath: fileName)
            .deletingPathExtension()
            .lastPathComponent
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return baseName.isEmpty ? "download" : baseName
    }

    private func mutate(_ body: (inout Base64FileWorkspaceSessionState) -> Void) {
        var next = state
        body(&next)
        state = next
    }

    private func isCurrentEncodedOutput(
        selection: Base64FileSelection,
        mode: Base64Conversion.FileOutputMode,
        generation: Int
    ) -> Bool {
        state.isCurrentEncodedOutput(
            selection: selection,
            mode: mode,
            generation: generation
        )
    }

    private func isCurrentOutputAction(
        _ action: Base64FileOutputAction,
        selection: Base64FileSelection,
        mode: Base64Conversion.FileOutputMode,
        generation: Int
    ) -> Bool {
        outputAction == action
            && isCurrentEncodedOutput(selection: selection, mode: mode, generation: generation)
    }

    private func finishOutputAction(_ action: Base64FileOutputAction, generation: Int) {
        mutate { $0.clearOutputAction(action, generation: generation) }
    }

    private func finishDecodedSave(generation: Int, error: String? = nil) {
        mutate { $0.endSavingDecoded(generation: generation, error: error) }
    }

    private func isCurrentFileRead(
        fileGeneration: Int,
        outputGeneration: Int,
        mode: Base64Conversion.FileOutputMode
    ) -> Bool {
        state.isCurrentFileRead(
            fileGeneration: fileGeneration,
            outputGeneration: outputGeneration,
            mode: mode
        )
    }

    private func isCurrentDecode(input: String, generation: Int) -> Bool {
        state.isCurrentDecode(input: input, generation: generation)
    }

    private func isCurrentDecodedPayload(
        _ payload: Base64Conversion.FilePayload,
        generation: Int
    ) -> Bool {
        state.isCurrentDecodedPayload(payload, generation: generation)
    }
}
