@testable import XTools
@testable import XToolsCore
import Foundation
import AppKit
import Testing

@MainActor
struct WorkspacePayloadEvictionTests {
    private static func defaults() -> UserDefaults {
        let name = "WorkspacePayloadEvictionTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func base64KeepsDecodedFileAndDraftDuringEviction() async throws {
        let repository = ToolWorkspaceRepository(defaults: Self.defaults())
        let session = repository.model(for: Base64FileWorkflowSession.workspaceKey)

        let data = try imageData()
        let base64 = data.base64EncodedString()
        session.updateReverseInput(base64)
        await session.decodeReverseInput()?.value
        try #require(session.decodedPayload?.data == data)
        try #require(session.previewImage != nil)
        session.outputFileName = "kept-name"
        repository.evictHeavyPayloads { $0 == Base64FileWorkflowSession.workspaceKey.toolID }

        #expect(session.selectedFile == nil)
        #expect(session.decodedPayload?.data == data)
        #expect(session.previewImage != nil)
        #expect(session.outputPreview == nil)
        #expect(session.reverseInput == base64)
        #expect(session.outputFileName == "kept-name")

        let restored = repository.model(for: Base64FileWorkflowSession.workspaceKey)
        #expect(restored === session)
        #expect(restored.reverseInput == base64)
        #expect(restored.selectedFile == nil)
    }

    @Test func repositoryEvictsOnlyMatchingToolID() async throws {
        let repository = ToolWorkspaceRepository(defaults: Self.defaults())
        let regex = repository.model(for: RegexToolWorkspaceModel.key)
        let diff = repository.model(for: IndexTextDiffSegment.key)
        regex.execution.run(pattern: "[a-z]", text: "abc", flags: "g")
        diff.left = "alpha\nbeta\n"
        diff.right = "alpha\ngamma\n"
        try await waitForPayload { regex.execution.report != nil && !diff.diffRows.isEmpty }

        repository.evictHeavyPayloads { $0 == IndexTextDiffSegment.key.toolID }
        #expect(diff.diffRows.isEmpty)
        #expect(regex.execution.report?.matches.count == 3)
    }

    @Test func imageConverterKeepsAcceptedFileAndSpooledOutputDuringEviction() async throws {
        let repository = ToolWorkspaceRepository(defaults: Self.defaults())
        let workspace = repository.model(for: ImageConverterToolWorkspaceModel.key)
        let data = try imageData()
        workspace.session.receiveImageURLs(
            [URL(fileURLWithPath: "/eviction.png")], allowedContentTypes: [.png],
            client: ImageWorkflowClient(reader: .constant(data: data))
        )
        try await waitForPayload { !workspace.session.isImporting }
        try #require(workspace.session.items.count == 1)
        workspace.session.convertAll(rendererProvider: { Self.passthroughImage })
        try await waitForPayload { !workspace.session.isProcessing }
        let item = try #require(workspace.session.items.first)
        guard case let .done(output) = item.state else {
            Issue.record("Expected a real spooled output before eviction")
            return
        }
        #expect(try Data(contentsOf: output.tempURL) == data)
        repository.evictHeavyPayloads { $0 == ImageConverterToolWorkspaceModel.key.toolID }
        #expect(workspace.session.items.count == 1)
        #expect(try Data(contentsOf: output.tempURL) == data)
    }

    @Test func watermarkKeepsSourceAndGeneratedOutputsDuringEviction() async throws {
        let repository = ToolWorkspaceRepository(defaults: Self.defaults())
        let workspace = repository.model(for: ImageWatermarkToolWorkspaceModel.key)
        workspace.watermarkText = "Keep watermark"
        let data = try imageData()
        try await load(data, into: workspace.session)
        workspace.previewSession.render(
            previewData: data, sourcePixelWidth: 2, sourcePixelHeight: 2,
            recipe: ImageWatermarkRecipe(text: "Keep watermark", opacity: 0.5, fontSize: 12, position: .center, color: .white),
            renderer: { data, _, _, _ in data }
        )
        try await waitForPayload { !workspace.previewSession.isRendering }
        try #require(workspace.previewSession.data == data)
        try #require(workspace.previewSession.image != nil)
        repository.evictHeavyPayloads { $0 == ImageWatermarkToolWorkspaceModel.key.toolID }
        #expect(workspace.watermarkText == "Keep watermark")
        #expect(workspace.session.source?.data == data)
        #expect(workspace.session.output?.data == data)
        #expect(workspace.session.outputImage != nil)
        #expect(workspace.previewSession.image != nil)
        #expect(workspace.previewSession.data == data)
    }

    private func imageData() throws -> Data {
        let bitmap = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ))
        return try #require(bitmap.representation(using: .png, properties: [:]))
    }

    private func load(_ data: Data, into session: ImageProcessedOutputSession) async throws {
        session.receiveImageURL(
            URL(fileURLWithPath: "/eviction.png"), allowedContentTypes: [.png],
            client: ImageWorkflowClient(reader: .constant(data: data)), operation: .grayscale,
            render: Self.passthroughImage
        )
        try await waitForPayload { !session.isProcessing }
        try #require(session.source?.data == data)
        try #require(session.output?.data == data)
        try #require(session.outputImage != nil)
    }

    nonisolated private static func passthroughImage(_ input: ImageProcessingInput) -> ProcessedImage {
        ProcessedImage(data: input.data, format: .png, pixelWidth: 2, pixelHeight: 2,
                       originalByteCount: input.data.count, quality: nil, wasResized: false)
    }

    private func waitForPayload(_ condition: @MainActor () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(20))
        while !condition(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        try #require(condition())
    }

    @Test func jwtSensitiveDraftsAreNotEvictedBecauseModelDoesNotConform() {
        let repository = ToolWorkspaceRepository(defaults: Self.defaults())
        let jwt = repository.model(for: JWTToolWorkspaceModel.key)
        jwt.session.generateSecret = "secret-stays"
        jwt.session.generatePayload = #"{"sub":"x"}"#
        repository.evictHeavyPayloads { $0 == JWTToolWorkspaceModel.key.toolID }
        #expect(jwt.session.generateSecret == "secret-stays")
        #expect(jwt.session.generatePayload == #"{"sub":"x"}"#)
    }

    @Test func diffWorkspaceEvictsRowsButKeepsDrafts() async {
        let workspace = DiffToolWorkspaceModel(kind: .text)
        workspace.left = "alpha\nbeta\n"
        workspace.right = "alpha\ngamma\n"
        // 等待防抖后的 diff 计算落地，让 binding 持有对齐行集。
        let deadline = Date().addingTimeInterval(5)
        while workspace.diffRows.isEmpty, Date() < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
        #expect(!workspace.diffRows.isEmpty)

        workspace.evictHeavyPayloads()
        #expect(workspace.diffRows.isEmpty)
        #expect(workspace.left == "alpha\nbeta\n")
        #expect(workspace.right == "alpha\ngamma\n")
        #expect(workspace.execution.isRunning == false)
    }

    @Test func regexWorkspaceEvictsAndRestoresReportFromCurrentDrafts() async throws {
        let repository = ToolWorkspaceRepository(defaults: Self.defaults())
        let workspace = repository.model(for: RegexToolWorkspaceModel.key)
        workspace.pattern = "a+"
        workspace.text = "aaa bb aaa"
        // 页面经由 debouncer 触发执行；测试直接执行同一入口即可拿到报告。
        workspace.execution.run(pattern: workspace.pattern, text: workspace.text, flags: workspace.flags)
        let deadline = Date().addingTimeInterval(5)
        while workspace.execution.report == nil, Date() < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
        #expect(workspace.execution.report != nil)

        workspace.evictHeavyPayloads()
        #expect(workspace.execution.report == nil)
        #expect(workspace.execution.reportSourceText == nil)
        #expect(workspace.execution.isRunning == false)
        #expect(workspace.pattern == "a+")
        #expect(workspace.text == "aaa bb aaa")

        workspace.text = "aaaa bb"
        workspace.restoreResultIfNeeded()
        try await waitForPayload { workspace.execution.report != nil }
        #expect(workspace.execution.report?.matches.count == 1)
        #expect(workspace.execution.reportSourceText == "aaaa bb")
    }
}
