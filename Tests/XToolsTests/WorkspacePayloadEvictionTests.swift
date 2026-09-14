@testable import XTools
import XToolsCore
import Foundation
import Testing

@MainActor
struct WorkspacePayloadEvictionTests {
    private static func defaults() -> UserDefaults {
        let name = "WorkspacePayloadEvictionTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func base64EvictsFileBytesButKeepsReverseDraftText() {
        let repository = ToolWorkspaceRepository(defaults: Self.defaults())
        let session = repository.model(for: Base64FileWorkflowSession.workspaceKey)

        session.outputFileName = "kept-name"
        let tinyPNG: [UInt8] = [
            0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A
        ]
        let base64 = Data(tinyPNG).base64EncodedString()
        session.updateReverseInput(base64)
        session.evictHeavyPayloads()

        #expect(session.selectedFile == nil)
        #expect(session.decodedPayload == nil)
        #expect(session.previewImage == nil)
        #expect(session.outputPreview == nil)
        #expect(session.reverseInput == base64)
        #expect(session.outputFileName == "kept-name")

        let restored = repository.model(for: Base64FileWorkflowSession.workspaceKey)
        #expect(restored === session)
        #expect(restored.reverseInput == base64)
        #expect(restored.selectedFile == nil)
    }

    @Test func repositoryEvictsOnlyMatchingToolID() {
        let repository = ToolWorkspaceRepository(defaults: Self.defaults())
        let base64 = repository.model(for: Base64FileWorkflowSession.workspaceKey)
        let grayscale = repository.model(for: ImageProcessedOutputSession.grayscaleWorkspaceKey)

        base64.updateReverseInput("keep-me")
        #expect(grayscale.source == nil)

        repository.evictHeavyPayloads(for: Base64FileWorkflowSession.workspaceKey.toolID)
        #expect(base64.reverseInput == "keep-me")
        #expect(base64.selectedFile == nil)

        repository.evictHeavyPayloads(for: ImageProcessedOutputSession.grayscaleWorkspaceKey.toolID)
        #expect(grayscale.source == nil)
        #expect(grayscale.output == nil)
    }

    @Test func imageConverterWorkspaceEvictsNestedSessionPayloads() {
        let repository = ToolWorkspaceRepository(defaults: Self.defaults())
        let workspace = repository.model(for: ImageConverterToolWorkspaceModel.key)
        #expect(workspace.session.source == nil)
        workspace.evictHeavyPayloads()
        #expect(workspace.session.source == nil)
        #expect(workspace.session.output == nil)
        #expect(workspace.session.outputImage == nil)
    }

    @Test func watermarkWorkspaceEvictsNestedSessionsAndKeepsTextRecipe() {
        let repository = ToolWorkspaceRepository(defaults: Self.defaults())
        let workspace = repository.model(for: ImageWatermarkToolWorkspaceModel.key)
        workspace.watermarkText = "Keep watermark"
        workspace.evictHeavyPayloads()
        #expect(workspace.watermarkText == "Keep watermark")
        #expect(workspace.session.source == nil)
        #expect(workspace.previewSession.image == nil)
        #expect(workspace.previewSession.data == nil)
    }

    @Test func jwtSensitiveDraftsAreNotEvictedBecauseModelDoesNotConform() {
        let repository = ToolWorkspaceRepository(defaults: Self.defaults())
        let jwt = repository.model(for: JWTToolWorkspaceModel.key)
        jwt.session.generateSecret = "secret-stays"
        jwt.session.generatePayload = #"{"sub":"x"}"#
        repository.evictHeavyPayloads(for: JWTToolWorkspaceModel.key.toolID)
        #expect(jwt.session.generateSecret == "secret-stays")
        #expect(jwt.session.generatePayload == #"{"sub":"x"}"#)
    }
}
