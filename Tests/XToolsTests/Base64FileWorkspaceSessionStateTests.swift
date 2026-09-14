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
    }
}
