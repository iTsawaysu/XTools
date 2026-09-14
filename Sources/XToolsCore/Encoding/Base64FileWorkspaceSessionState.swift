import Foundation

public enum Base64FileWorkflowDirection: String, Equatable, Sendable {
    case encode
    case decode
}

public enum Base64FileOutputAction: Equatable, Sendable {
    case copying
    case saving
    case sending
}

public enum Base64FileDecodedResultSource: Equatable, Sendable {
    case manualInput
    case currentEncodedOutput(fileName: String)
    case encodedTextFile(fileName: String)
}

public enum Base64FileDecodeActivity: Equatable, Sendable {
    case manualInput
    case encodedTextImport
    case encodedOutputPreview
}

public struct Base64FileEncodedWorkspaceState: Equatable, Sendable {
    public let selection: Base64FileSelection?
    public let preview: Base64Conversion.EncodedFileOutputPreview?

    public static let empty = Base64FileEncodedWorkspaceState(selection: nil, preview: nil)

    public init(selection: Base64FileSelection?, preview: Base64Conversion.EncodedFileOutputPreview?) {
        self.selection = selection
        self.preview = preview
    }
}

/// Pure Base64 file workspace state (no AppKit). UI publishes mirrors of these fields.
public struct Base64FileWorkspaceSessionState: Equatable, Sendable {
    public var direction: Base64FileWorkflowDirection
    public var outputMode: Base64Conversion.FileOutputMode
    public var encodedWorkspaceState: Base64FileEncodedWorkspaceState
    public var isReadingFile: Bool
    public var isPreparingOutput: Bool
    public var outputAction: Base64FileOutputAction?
    public var fileError: String?
    public var reverseInput: String
    public var outputFileName: String
    public var defaultOutputFileName: String
    public var decodedPayload: Base64Conversion.FilePayload?
    public var decodedResultSource: Base64FileDecodedResultSource?
    public var reverseError: String?
    public var reverseInputDirty: Bool
    public var decodeActivity: Base64FileDecodeActivity?
    public var isSavingDecoded: Bool

    public var fileReadGeneration: Int
    public var outputGeneration: Int
    public var decodeGeneration: Int

    public var isDecoding: Bool { decodeActivity != nil }
    public var selectedFile: Base64FileSelection? { encodedWorkspaceState.selection }
    public var outputPreview: Base64Conversion.EncodedFileOutputPreview? { encodedWorkspaceState.preview }

    public init(outputMode: Base64Conversion.FileOutputMode = .dataURL) {
        direction = .encode
        self.outputMode = outputMode
        encodedWorkspaceState = .empty
        isReadingFile = false
        isPreparingOutput = false
        outputAction = nil
        fileError = nil
        reverseInput = ""
        outputFileName = "download"
        defaultOutputFileName = "download"
        decodedPayload = nil
        decodedResultSource = nil
        reverseError = nil
        reverseInputDirty = false
        decodeActivity = nil
        isSavingDecoded = false
        fileReadGeneration = 0
        outputGeneration = 0
        decodeGeneration = 0
    }

    public mutating func changeDirection(to newDirection: Base64FileWorkflowDirection) {
        guard direction != newDirection else { return }
        direction = newDirection
        bumpAllGenerations()
        isReadingFile = false
        isPreparingOutput = false
        outputAction = nil
        decodeActivity = nil
        isSavingDecoded = false
        fileError = nil
        reverseError = nil
    }

    public mutating func clearSelection() {
        bumpAllGenerations()
        encodedWorkspaceState = .empty
        isReadingFile = false
        isPreparingOutput = false
        outputAction = nil
        decodeActivity = nil
        fileError = nil
    }

    public mutating func evictHeavyPayloads() {
        clearSelection()
        decodeGeneration += 1
        decodedPayload = nil
        decodedResultSource = nil
        reverseError = nil
        decodeActivity = nil
        isSavingDecoded = false
        reverseInputDirty = false
    }

    /// Updates reverse draft text and invalidates any in-flight decode result.
    public mutating func updateReverseInput(_ newValue: String) {
        reverseInput = newValue
        decodeGeneration += 1
        decodeActivity = nil
        isSavingDecoded = false
        decodedPayload = nil
        decodedResultSource = nil
        reverseError = nil
        reverseInputDirty = !newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public mutating func rejectReverseInputLimit(message: String) {
        decodeGeneration += 1
        decodeActivity = nil
        isSavingDecoded = false
        decodedPayload = nil
        decodedResultSource = nil
        reverseError = message
        reverseInputDirty = !reverseInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public mutating func clearReverseDraft() {
        decodeGeneration += 1
        reverseInput = ""
        decodedPayload = nil
        decodedResultSource = nil
        reverseError = nil
        reverseInputDirty = false
        decodeActivity = nil
        isSavingDecoded = false
    }

    @discardableResult
    public mutating func beginDecodeAttempt(_ activity: Base64FileDecodeActivity) -> Int {
        decodeGeneration += 1
        decodeActivity = activity
        isSavingDecoded = false
        decodedPayload = nil
        decodedResultSource = nil
        reverseError = nil
        return decodeGeneration
    }

    public mutating func finishDecodeAttempt(
        _ activity: Base64FileDecodeActivity,
        generation: Int
    ) {
        guard decodeGeneration == generation, decodeActivity == activity else { return }
        decodeActivity = nil
    }

    public mutating func beginFileRead() {
        bumpAllGenerations()
        isReadingFile = true
        isPreparingOutput = false
        outputAction = nil
        decodeActivity = nil
        fileError = nil
    }

    public mutating func beginOutputPreviewRefresh() {
        outputGeneration += 1
        isPreparingOutput = true
    }

    public mutating func applyOutputPreview(
        selection: Base64FileSelection,
        preview: Base64Conversion.EncodedFileOutputPreview?
    ) {
        encodedWorkspaceState = Base64FileEncodedWorkspaceState(selection: selection, preview: preview)
        isPreparingOutput = false
    }

    public mutating func clearOutputPreviewWorkspace() {
        encodedWorkspaceState = .empty
        isPreparingOutput = false
    }

    public mutating func applySuccessfulFileRead(
        selection: Base64FileSelection,
        preview: Base64Conversion.EncodedFileOutputPreview?
    ) {
        encodedWorkspaceState = Base64FileEncodedWorkspaceState(selection: selection, preview: preview)
        fileError = nil
        isReadingFile = false
    }

    public mutating func applyFileReadFailure(_ message: String) {
        fileError = message
        isReadingFile = false
    }

    public mutating func applyDecodedPayload(
        _ payload: Base64Conversion.FilePayload,
        source: Base64FileDecodedResultSource,
        defaultOutputFileName: String
    ) {
        decodedPayload = payload
        decodedResultSource = source
        reverseError = nil
        reverseInputDirty = false
        decodeActivity = nil
        self.defaultOutputFileName = defaultOutputFileName
        if outputFileName == "download" || outputFileName.isEmpty {
            outputFileName = defaultOutputFileName
        }
    }

    public mutating func applyDecodeFailure(_ message: String) {
        decodedPayload = nil
        decodedResultSource = nil
        reverseError = message
        decodeActivity = nil
    }

    public mutating func bumpAllGenerations() {
        fileReadGeneration += 1
        outputGeneration += 1
        decodeGeneration += 1
    }


    public mutating func beginCopyAction() {
        outputAction = .copying
        fileError = nil
    }

    public mutating func beginSaveEncodedAction() {
        outputAction = .saving
        fileError = nil
    }

    public mutating func beginSendToDecodeAction() {
        outputAction = .sending
    }

    public mutating func clearOutputAction() {
        outputAction = nil
    }

    public mutating func setFileError(_ message: String?) {
        fileError = message
    }

    public mutating func setReverseError(_ message: String?) {
        reverseError = message
    }

    public mutating func beginSavingDecoded() {
        isSavingDecoded = true
        reverseError = nil
    }

    public mutating func endSavingDecoded(error message: String? = nil) {
        isSavingDecoded = false
        if let message {
            reverseError = message
        }
    }

    public func isCurrentFileRead(
        fileGeneration: Int,
        outputGeneration: Int,
        mode: Base64Conversion.FileOutputMode
    ) -> Bool {
        direction == .encode
            && fileReadGeneration == fileGeneration
            && self.outputGeneration == outputGeneration
            && outputMode == mode
    }

    public func isCurrentEncodedOutput(
        selection: Base64FileSelection,
        mode: Base64Conversion.FileOutputMode,
        generation: Int
    ) -> Bool {
        selectedFile?.id == selection.id
            && outputMode == mode
            && outputGeneration == generation
    }

    public func isCurrentDecode(input: String, generation: Int) -> Bool {
        decodeGeneration == generation
            && reverseInput.trimmingCharacters(in: .whitespacesAndNewlines) == input
    }

    public func isCurrentDecodedPayload(
        _ payload: Base64Conversion.FilePayload,
        generation: Int
    ) -> Bool {
        decodeGeneration == generation && decodedPayload == payload
    }
}
