import Foundation
import Testing
@testable import XToolsCore

struct Base64FileWorkspaceSessionStateTests {
    @Test func changeDirectionBumpsGenerationsAndClearsTransientErrors() {
        var state = Base64FileWorkspaceSessionState()
        state.fileError = "x"
        state.reverseError = "y"
        state.isReadingFile = true
        let g0 = state.fileReadGeneration
        state.changeDirection(to: .decode)
        #expect(state.direction == .decode)
        #expect(state.fileReadGeneration == g0 + 1)
        #expect(state.fileError == nil)
        #expect(state.reverseError == nil)
        #expect(!state.isReadingFile)
    }

    @Test func clearSelectionEmptiesEncodedWorkspace() {
        var state = Base64FileWorkspaceSessionState()
        let selection = Base64FileSelection(
            fileName: "a.bin",
            data: Data([1, 2, 3]),
            mimeType: "application/octet-stream"
        )
        state.applySuccessfulFileRead(selection: selection, preview: nil)
        #expect(state.selectedFile != nil)
        state.clearSelection()
        #expect(state.selectedFile == nil)
        #expect(state.outputPreview == nil)
    }

    @Test func generationGuardsRejectStaleDecode() {
        var state = Base64FileWorkspaceSessionState()
        state.updateReverseInput("YWJj")
        let generation = state.decodeGeneration
        #expect(state.isCurrentDecode(input: "YWJj", generation: generation))
        state.decodeGeneration += 1
        #expect(!state.isCurrentDecode(input: "YWJj", generation: generation))
    }

    @Test func applyDecodedPayloadSetsSourceAndDefaultName() {
        var state = Base64FileWorkspaceSessionState()
        let payload = Base64Conversion.FilePayload(
            data: Data("hi".utf8),
            mimeType: "text/plain",
            fileExtension: "txt"
        )
        state.applyDecodedPayload(
            payload,
            source: .manualInput,
            defaultOutputFileName: "note"
        )
        #expect(state.decodedPayload == payload)
        #expect(state.decodedResultSource == .manualInput)
        #expect(state.defaultOutputFileName == "note")
        #expect(state.outputFileName == "note")

        state.applyDecodedPayload(payload, source: .manualInput, defaultOutputFileName: "next")
        #expect(state.outputFileName == "next")

        state.outputFileName = "chosen-by-user"
        state.applyDecodedPayload(payload, source: .manualInput, defaultOutputFileName: "latest")
        #expect(state.defaultOutputFileName == "latest")
        #expect(state.outputFileName == "chosen-by-user")
    }

    @Test func failedReplacementReadDoesNotInvalidateTheAcceptedPreviewRefresh() {
        var state = Base64FileWorkspaceSessionState()
        let selection = Base64FileSelection(fileName: "a.txt", data: Data("a".utf8), mimeType: "text/plain")
        state.applySuccessfulFileRead(selection: selection, preview: nil)
        state.beginOutputPreviewRefresh()
        let generation = state.outputGeneration

        state.beginFileRead()
        state.applyFileReadFailure("read failed")
        #expect(state.isPreparingOutput)
        #expect(state.isCurrentEncodedOutput(selection: selection, mode: .dataURL, generation: generation))

        let replacement = Base64FileSelection(fileName: "b.txt", data: Data("b".utf8), mimeType: "text/plain")
        state.beginFileRead()
        state.applySuccessfulFileRead(selection: replacement, preview: nil)
        #expect(!state.isPreparingOutput)
        #expect(!state.isCurrentEncodedOutput(selection: selection, mode: .dataURL, generation: generation))
    }

    @Test func fileReadAndSelectionClearInvalidateDecodedSaveBusyState() {
        var state = Base64FileWorkspaceSessionState()
        state.beginSavingDecoded()
        let firstGeneration = state.decodeGeneration
        state.beginFileRead()
        #expect(state.decodeGeneration != firstGeneration)
        #expect(!state.isSavingDecoded)

        state.beginSavingDecoded()
        let secondGeneration = state.decodeGeneration
        state.clearSelection()
        #expect(state.decodeGeneration != secondGeneration)
        #expect(!state.isSavingDecoded)
    }
}
