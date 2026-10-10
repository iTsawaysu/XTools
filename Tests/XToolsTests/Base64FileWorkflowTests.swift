import Combine
import XToolsCore
import Foundation
@testable import XTools
import Testing

@MainActor
struct Base64FileWorkflowTests {
    @Test func decodePayloadRejectsDecodedOutputAboveLimitBeforeMaterializingFile() async {
        let encoded = Data(repeating: 65, count: 12).base64EncodedString()
        let result = await Base64FileWorkflow.decodePayload(encoded, maxDecodedBytes: 8)

        #expect(result == .failure(.decodedTooLarge(maxBytes: 8)))
    }

    @Test func decodePayloadAcceptsDecodedOutputAtLimit() async throws {
        let data = Data("hello".utf8)
        let result = await Base64FileWorkflow.decodePayload(data.base64EncodedString(), maxDecodedBytes: data.count)

        guard case .success(let payload) = result else {
            Issue.record("Expected Base64 payload to decode under the configured limit")
            return
        }

        #expect(payload.data == data)
        #expect(payload.mimeType == "application/octet-stream")
        #expect(payload.fileExtension == "bin")
    }

    @Test func decodePayloadAcceptsEmptyDataURLPayload() async throws {
        let result = await Base64FileWorkflow.decodePayload("data:application/octet-stream;base64,", maxDecodedBytes: 0)

        guard case .success(let payload) = result else {
            Issue.record("Expected empty Data URL payload to round-trip as a zero-byte file")
            return
        }

        #expect(payload.data.isEmpty)
        #expect(payload.mimeType == "application/octet-stream")
        #expect(payload.fileExtension == "bin")
    }

    @Test func sessionReadSelectionBuildsPreviewThroughProcessor() async {
        let session = Base64FileWorkflowSession()
        let processor = FakeBase64FileWorkflowProcessor()
        let selection = Self.selection(fileName: "sample.bin", data: Data("hello".utf8))
        processor.readSelectionResult = .success(selection)

        await session.readSelectedFile(from: URL(fileURLWithPath: "/tmp/sample.bin"), processor: processor)?.value

        #expect(session.selectedFile == selection)
        #expect(session.outputPreview?.visibleText == "data:application/octet-stream;base64,aGVsbG8=")
        #expect(session.isReadingFile == false)
        #expect(session.isPreparingOutput == false)
        #expect(processor.previewRequests.map(\.mode) == [.dataURL])
    }

    @Test func sessionKeepsReadyWorkspaceVisibleWhileReadingAReplacement() async {
        let session = Base64FileWorkflowSession()
        let processor = FakeBase64FileWorkflowProcessor()
        let originalSelection = Self.selection(fileName: "original.bin", data: Data("original".utf8))
        processor.readSelectionResult = .success(originalSelection)
        await session.readSelectedFile(
            from: URL(fileURLWithPath: "/tmp/original.bin"),
            processor: processor
        )?.value
        let originalPreview = session.outputPreview

        let replacementRead = SuspendedTestValue<Result<Base64FileSelection, Base64FileWorkflowFailure>>()
        processor.readSelectionHandler = { _, _ in
            await replacementRead.wait()
        }
        let replacementTask = session.readSelectedFile(
            from: URL(fileURLWithPath: "/tmp/replacement.bin"),
            processor: processor
        )
        await replacementRead.waitForRequest()

        #expect(session.isReadingFile)
        #expect(session.selectedFile == originalSelection)
        #expect(session.outputPreview == originalPreview)

        let replacementSelection = Self.selection(fileName: "replacement.bin", data: Data("replacement".utf8))
        replacementRead.resume(.success(replacementSelection))
        await replacementTask?.value

        #expect(session.selectedFile == replacementSelection)
        #expect(session.outputPreview?.visibleText.contains("cmVwbGFjZW1lbnQ=") == true)
        #expect(session.isReadingFile == false)
    }

    @Test func sessionWaitsForReplacementPreviewBeforePublishingItsSelection() async {
        let session = Base64FileWorkflowSession()
        let processor = FakeBase64FileWorkflowProcessor()
        let replacementSelection = Self.selection(fileName: "replacement.bin", data: Data("replacement".utf8))
        let suspendedPreview = SuspendedTestValue<Base64Conversion.EncodedFileOutputPreview>()
        processor.readSelectionResult = .success(replacementSelection)
        processor.outputPreviewHandler = { _, _ in
            await suspendedPreview.wait()
        }

        let task = session.readSelectedFile(
            from: URL(fileURLWithPath: "/tmp/replacement.bin"),
            processor: processor
        )
        await suspendedPreview.waitForRequest()

        #expect(session.isReadingFile)
        #expect(session.selectedFile == nil)
        #expect(session.outputPreview == nil)

        let expectedPreview = Base64Conversion.encodedOutputPreview(
            for: replacementSelection.data,
            mimeType: replacementSelection.mimeType,
            mode: .dataURL
        )
        suspendedPreview.resume(expectedPreview)
        await task?.value

        #expect(session.selectedFile == replacementSelection)
        #expect(session.outputPreview == expectedPreview)
        #expect(session.isReadingFile == false)
        #expect(session.isPreparingOutput == false)
    }

    @Test func sessionKeepsReadyWorkspaceWhenReplacementReadFails() async {
        let session = Base64FileWorkflowSession()
        let processor = FakeBase64FileWorkflowProcessor()
        let originalSelection = Self.selection(fileName: "original.bin", data: Data("original".utf8))
        processor.readSelectionResult = .success(originalSelection)
        await session.readSelectedFile(
            from: URL(fileURLWithPath: "/tmp/original.bin"),
            processor: processor
        )?.value
        let originalPreview = session.outputPreview

        processor.readSelectionResult = .failure(.readFailed)
        await session.readSelectedFile(
            from: URL(fileURLWithPath: "/tmp/unreadable.bin"),
            processor: processor
        )?.value

        #expect(session.selectedFile == originalSelection)
        #expect(session.outputPreview == originalPreview)
        #expect(session.fileError == "无法读取所选文件。")
        #expect(session.isReadingFile == false)
    }

    @Test func sessionKeepsReadyPreviewVisibleWhileOutputModeRefreshes() async {
        let session = Base64FileWorkflowSession()
        let processor = FakeBase64FileWorkflowProcessor()
        let selection = Self.selection(fileName: "mode-switch.bin", data: Data("mode switch".utf8))
        processor.readSelectionResult = .success(selection)
        await session.readSelectedFile(
            from: URL(fileURLWithPath: "/tmp/mode-switch.bin"),
            processor: processor
        )?.value
        let originalPreview = session.outputPreview
        let suspendedPreview = SuspendedTestValue<Base64Conversion.EncodedFileOutputPreview>()
        processor.outputPreviewHandler = { _, _ in
            await suspendedPreview.wait()
        }

        let refreshTask = session.changeOutputMode(to: .base64, processor: processor)
        await suspendedPreview.waitForRequest()

        #expect(session.outputMode == .base64)
        #expect(session.isPreparingOutput)
        #expect(session.selectedFile == selection)
        #expect(session.outputPreview == originalPreview)

        let expectedPreview = Base64Conversion.encodedOutputPreview(
            for: selection.data,
            mimeType: selection.mimeType,
            mode: .base64
        )
        suspendedPreview.resume(expectedPreview)
        await refreshTask?.value

        #expect(session.outputPreview == expectedPreview)
        #expect(session.isPreparingOutput == false)
    }

    @Test func rapidOutputModeSwitchPublishesOnlyTheLatestPreview() async {
        let session = Base64FileWorkflowSession()
        let processor = FakeBase64FileWorkflowProcessor()
        let selection = Self.selection(fileName: "rapid-switch.bin", data: Data("rapid switch".utf8))
        processor.readSelectionResult = .success(selection)
        await session.readSelectedFile(
            from: URL(fileURLWithPath: "/tmp/rapid-switch.bin"),
            processor: processor
        )?.value
        let originalPreview = session.outputPreview
        let base64Preview = SuspendedTestValue<Base64Conversion.EncodedFileOutputPreview>()
        let dataURLPreview = SuspendedTestValue<Base64Conversion.EncodedFileOutputPreview>()
        processor.outputPreviewHandler = { _, mode in
            switch mode {
            case .base64:
                await base64Preview.wait()
            case .dataURL:
                await dataURLPreview.wait()
            }
        }

        let base64Task = session.changeOutputMode(to: .base64, processor: processor)
        await base64Preview.waitForRequest()
        let dataURLTask = session.changeOutputMode(to: .dataURL, processor: processor)
        await dataURLPreview.waitForRequest()

        base64Preview.resume(Base64Conversion.encodedOutputPreview(
            for: selection.data,
            mimeType: selection.mimeType,
            mode: .base64
        ))
        await base64Task?.value

        #expect(session.outputMode == .dataURL)
        #expect(session.outputPreview == originalPreview)
        #expect(session.isPreparingOutput)

        let expectedPreview = Base64Conversion.encodedOutputPreview(
            for: selection.data,
            mimeType: selection.mimeType,
            mode: .dataURL
        )
        dataURLPreview.resume(expectedPreview)
        await dataURLTask?.value

        #expect(session.outputPreview == expectedPreview)
        #expect(session.isPreparingOutput == false)
    }

    @Test func sessionClearRejectsAStalePendingFileImport() async {
        let session = Base64FileWorkflowSession()
        let processor = FakeBase64FileWorkflowProcessor()
        let suspendedRead = SuspendedTestValue<Result<Base64FileSelection, Base64FileWorkflowFailure>>()
        processor.readSelectionHandler = { _, _ in
            await suspendedRead.wait()
        }

        let task = session.readSelectedFile(
            from: URL(fileURLWithPath: "/tmp/pending.bin"),
            processor: processor
        )
        await suspendedRead.waitForRequest()
        session.clearSelection()

        #expect(session.selectedFile == nil)
        #expect(session.outputPreview == nil)
        #expect(session.isReadingFile == false)

        suspendedRead.resume(.success(Self.selection(fileName: "stale.bin")))
        await task?.value

        #expect(session.selectedFile == nil)
        #expect(session.outputPreview == nil)
        #expect(session.isReadingFile == false)
    }

    @Test func cancelledFileReadEndsBusyStateWithoutReplacingSelection() async {
        let session = Base64FileWorkflowSession()
        let processor = FakeBase64FileWorkflowProcessor()
        let suspendedRead = SuspendedTestValue<Result<Base64FileSelection, Base64FileWorkflowFailure>>()
        processor.readSelectionHandler = { _, _ in await suspendedRead.wait() }

        let task = session.readSelectedFile(
            from: URL(fileURLWithPath: "/tmp/cancelled.bin"),
            processor: processor
        )
        await suspendedRead.waitForRequest()
        task?.cancel()
        suspendedRead.resume(.success(Self.selection(fileName: "cancelled.bin")))
        await task?.value

        #expect(session.isReadingFile == false)
        #expect(session.selectedFile == nil)
        #expect(session.fileError == nil)
    }

    @Test func cancelledFilePreviewEndsBusyStateWithoutPublishingSelection() async {
        let session = Base64FileWorkflowSession()
        let processor = FakeBase64FileWorkflowProcessor()
        let selection = Self.selection(fileName: "cancelled.bin")
        let suspendedPreview = SuspendedTestValue<Base64Conversion.EncodedFileOutputPreview>()
        processor.readSelectionResult = .success(selection)
        processor.outputPreviewHandler = { _, _ in await suspendedPreview.wait() }

        let task = session.readSelectedFile(
            from: URL(fileURLWithPath: "/tmp/cancelled.bin"),
            processor: processor
        )
        await suspendedPreview.waitForRequest()
        task?.cancel()
        suspendedPreview.resume(Base64Conversion.encodedOutputPreview(
            for: selection.data,
            mimeType: selection.mimeType,
            mode: .dataURL
        ))
        await task?.value

        #expect(session.isReadingFile == false)
        #expect(session.selectedFile == nil)
        #expect(session.outputPreview == nil)
        #expect(session.fileError == nil)
    }

    @Test func sessionDirectionChangeKeepsReadyWorkspaceAndRejectsPendingReplacement() async {
        let session = Base64FileWorkflowSession()
        let processor = FakeBase64FileWorkflowProcessor()
        let originalSelection = Self.selection(fileName: "original.bin", data: Data("original".utf8))
        processor.readSelectionResult = .success(originalSelection)
        await session.readSelectedFile(
            from: URL(fileURLWithPath: "/tmp/original.bin"),
            processor: processor
        )?.value
        let originalPreview = session.outputPreview

        let suspendedRead = SuspendedTestValue<Result<Base64FileSelection, Base64FileWorkflowFailure>>()
        processor.readSelectionHandler = { _, _ in
            await suspendedRead.wait()
        }
        let task = session.readSelectedFile(
            from: URL(fileURLWithPath: "/tmp/replacement.bin"),
            processor: processor
        )
        await suspendedRead.waitForRequest()
        session.changeDirection(to: .decode)

        #expect(session.direction == .decode)
        #expect(session.selectedFile == originalSelection)
        #expect(session.outputPreview == originalPreview)
        #expect(session.isReadingFile == false)

        suspendedRead.resume(.success(Self.selection(fileName: "stale.bin")))
        await task?.value

        #expect(session.selectedFile == originalSelection)
        #expect(session.outputPreview == originalPreview)
        #expect(session.isReadingFile == false)
    }

    @Test func sessionPublishesSelectedFileBeforeEndingReadBusyState() async {
        let session = Base64FileWorkflowSession()
        let processor = FakeBase64FileWorkflowProcessor()
        processor.readSelectionResult = .success(Self.selection(fileName: "smooth.bin"))
        var didBeginReading = false
        var observedIdleEmptyState = false
        let observation = session.objectWillChange.sink {
            if session.isReadingFile {
                didBeginReading = true
            }
            if didBeginReading,
               !session.isReadingFile,
               session.selectedFile == nil,
               session.fileError == nil {
                observedIdleEmptyState = true
            }
        }

        await session.readSelectedFile(
            from: URL(fileURLWithPath: "/tmp/smooth.bin"),
            processor: processor
        )?.value

        #expect(observedIdleEmptyState == false)
        #expect(session.selectedFile?.fileName == "smooth.bin")
        #expect(session.isReadingFile == false)
        _ = observation
    }

    @Test func sessionPublishesReadErrorBeforeEndingBusyState() async {
        let session = Base64FileWorkflowSession()
        let processor = FakeBase64FileWorkflowProcessor()
        processor.readSelectionResult = .failure(.readFailed)
        var didBeginReading = false
        var observedIdleEmptyState = false
        let observation = session.objectWillChange.sink {
            if session.isReadingFile {
                didBeginReading = true
            }
            if didBeginReading,
               !session.isReadingFile,
               session.selectedFile == nil,
               session.fileError == nil {
                observedIdleEmptyState = true
            }
        }

        await session.readSelectedFile(
            from: URL(fileURLWithPath: "/tmp/unreadable.bin"),
            processor: processor
        )?.value

        #expect(observedIdleEmptyState == false)
        #expect(session.fileError == "无法读取所选文件。")
        #expect(session.isReadingFile == false)
        _ = observation
    }

    @Test func sessionSelectSourceFileUsesSharedPanelAndPreservesStateOnCancelOrPanelFailure() async {
        let session = Base64FileWorkflowSession()
        let processor = FakeBase64FileWorkflowProcessor()
        let sourceURL = URL(fileURLWithPath: "/tmp/source.bin")
        let selection = Self.selection(fileName: "source.bin")
        processor.readSelectionResult = .success(selection)
        var requests: [FileInputPanelRequest] = []
        let successfulPanel = FileInputPanelClient { request in
            requests.append(request)
            return sourceURL
        }

        await session.selectSourceFile(filePanel: successfulPanel, processor: processor).value

        #expect(requests.map(\.allowedContentTypes) == [[.data]])
        #expect(processor.readSelectionRequests.map(\.url) == [sourceURL])
        #expect(session.selectedFile == selection)

        let cancelledPanel = FileInputPanelClient { _ in nil }
        await session.selectSourceFile(filePanel: cancelledPanel, processor: processor).value
        #expect(session.selectedFile == selection)
        #expect(session.fileError == nil)

        let unavailablePanel = FileInputPanelClient { _ in
            throw FileInputPanelFailure.windowUnavailable
        }
        await session.selectSourceFile(filePanel: unavailablePanel, processor: processor).value
        #expect(session.selectedFile == selection)
        #expect(session.fileError == "暂时无法打开文件选择器。")
    }

    @Test func sessionRejectsMultipleSourceFileDropAsAWhole() async {
        let session = Base64FileWorkflowSession()
        let processor = FakeBase64FileWorkflowProcessor()
        processor.readSelectionResult = .success(Self.selection())
        await session.readSelectedFile(from: URL(fileURLWithPath: "/tmp/source.bin"), processor: processor)?.value

        session.rejectMultipleSourceFileDrop()

        #expect(session.selectedFile == nil)
        #expect(session.outputPreview == nil)
        #expect(session.fileError == "一次只能拖入一个文件。")
        #expect(session.isReadingFile == false)
    }

    @Test func sessionModeSwitchClearsDecodeErrorAndBusyState() async {
        let session = Base64FileWorkflowSession()
        let processor = FakeBase64FileWorkflowProcessor()
        processor.decodeResult = .failure(.invalidPayload)

        session.updateReverseInput("not base64")
        await session.decodeReverseInput(processor: processor)?.value
        #expect(session.reverseError == "输入不是有效的 Base64 或 Base64 Data URL。")

        session.changeDirection(to: .decode)

        #expect(session.direction == .decode)
        #expect(session.reverseError == nil)
        #expect(session.fileError == nil)
        #expect(session.isDecoding == false)
        #expect(session.isSavingDecoded == false)
        #expect(session.outputAction == nil)
    }

    @Test func sessionCopyWritesFullOutputAndReportsFailure() async {
        let session = Base64FileWorkflowSession()
        let processor = FakeBase64FileWorkflowProcessor()
        let dialog = FakeBase64FileDialog()
        let pasteboard = FakeBase64Pasteboard()
        let client = Base64FileWorkflowClient(dialog: dialog, pasteboard: pasteboard)
        processor.readSelectionResult = .success(Self.selection())
        processor.fullOutputText = "complete-output"

        await session.readSelectedFile(from: URL(fileURLWithPath: "/tmp/source.bin"), processor: processor)?.value
        await session.copyFullOutput(client: client, processor: processor)?.value
        #expect(pasteboard.strings == ["complete-output"])
        #expect(session.fileError == nil)

        pasteboard.shouldSucceed = false
        await session.copyFullOutput(client: client, processor: processor)?.value
        #expect(pasteboard.strings == ["complete-output"])
        #expect(session.fileError == "无法复制编码结果。")
        #expect(session.outputAction == nil)
    }

    @Test func sessionStaleCopyResultDoesNotWritePasteboard() async {
        let session = Base64FileWorkflowSession()
        let processor = FakeBase64FileWorkflowProcessor()
        let pasteboard = FakeBase64Pasteboard()
        let client = Base64FileWorkflowClient(dialog: FakeBase64FileDialog(), pasteboard: pasteboard)
        let fullOutput = SuspendedTestValue<String>()
        processor.readSelectionResult = .success(Self.selection())
        processor.fullOutputHandler = { _, _ in
            await fullOutput.wait()
        }

        await session.readSelectedFile(from: URL(fileURLWithPath: "/tmp/source.bin"), processor: processor)?.value
        let copyTask = session.copyFullOutput(client: client, processor: processor)
        await fullOutput.waitForRequest()
        session.changeOutputMode(to: .base64, processor: processor)
        fullOutput.resume("stale-output")
        await copyTask?.value

        #expect(pasteboard.strings.isEmpty)
        #expect(session.outputAction == nil)
        #expect(session.fileError == nil)
    }

    @Test func sessionModeChangeDuringCopySerializationDoesNotWritePasteboard() async {
        let session = Base64FileWorkflowSession()
        let processor = FakeBase64FileWorkflowProcessor()
        let pasteboard = FakeBase64Pasteboard()
        let serialization = SuspendedTestValue<Data>()
        let client = Base64FileWorkflowClient(dialog: FakeBase64FileDialog(), pasteboard: pasteboard)
        processor.readSelectionResult = .success(Self.selection())
        processor.serializeUTF8Handler = { _ in await serialization.wait() }

        await session.readSelectedFile(from: URL(fileURLWithPath: "/tmp/source.bin"), processor: processor)?.value
        let copyTask = session.copyFullOutput(client: client, processor: processor)
        await serialization.waitForRequest()
        await session.changeOutputMode(to: .base64, processor: processor)?.value
        serialization.resume(Data("stale-output".utf8))
        await copyTask?.value

        #expect(pasteboard.strings.isEmpty)
        #expect(session.fileError == nil)
    }

    @Test func sessionReplacementDuringCopySerializationDoesNotWritePasteboard() async {
        let session = Base64FileWorkflowSession()
        let processor = FakeBase64FileWorkflowProcessor()
        let pasteboard = FakeBase64Pasteboard()
        let serialization = SuspendedTestValue<Data>()
        let client = Base64FileWorkflowClient(dialog: FakeBase64FileDialog(), pasteboard: pasteboard)
        processor.readSelectionResult = .success(Self.selection())
        processor.serializeUTF8Handler = { _ in await serialization.wait() }

        await session.readSelectedFile(from: URL(fileURLWithPath: "/tmp/source.bin"), processor: processor)?.value
        let copyTask = session.copyFullOutput(client: client, processor: processor)
        await serialization.waitForRequest()
        let replacement = Base64FileSelection(
            fileName: "replacement.bin",
            data: Data("replacement".utf8),
            mimeType: "application/octet-stream"
        )
        processor.readSelectionResult = .success(replacement)
        await session.readSelectedFile(from: URL(fileURLWithPath: "/tmp/replacement.bin"), processor: processor)?.value
        serialization.resume(Data("stale-output".utf8))
        await copyTask?.value

        #expect(session.selectedFile == replacement)
        #expect(pasteboard.strings.isEmpty)
        #expect(session.fileError == nil)
    }

    @Test func sessionStaleCopyCannotClearNewCopyBusyState() async {
        let session = Base64FileWorkflowSession()
        let processor = FakeBase64FileWorkflowProcessor()
        let oldSerialization = SuspendedTestValue<Data>()
        let newSerialization = SuspendedTestValue<Data>()
        let pasteboard = FakeBase64Pasteboard()
        let client = Base64FileWorkflowClient(dialog: FakeBase64FileDialog(), pasteboard: pasteboard)
        processor.readSelectionResult = .success(Self.selection())
        processor.serializeUTF8Handler = { text in
            if text == "old-output" { return await oldSerialization.wait() }
            return await newSerialization.wait()
        }
        processor.fullOutputText = "old-output"

        await session.readSelectedFile(from: URL(fileURLWithPath: "/tmp/source.bin"), processor: processor)?.value
        let oldCopy = session.copyFullOutput(client: client, processor: processor)
        await oldSerialization.waitForRequest()
        session.clearSelection()

        let replacement = Base64FileSelection(
            fileName: "replacement.bin",
            data: Data("replacement".utf8),
            mimeType: "application/octet-stream"
        )
        processor.readSelectionResult = .success(replacement)
        processor.fullOutputText = "new-output"
        await session.readSelectedFile(from: URL(fileURLWithPath: "/tmp/replacement.bin"), processor: processor)?.value
        let newCopy = session.copyFullOutput(client: client, processor: processor)
        await newSerialization.waitForRequest()
        #expect(session.outputAction == .copying)

        oldSerialization.resume(Data("old-output".utf8))
        await oldCopy?.value
        #expect(session.outputAction == .copying)
        #expect(pasteboard.strings.isEmpty)

        newSerialization.resume(Data("new-output".utf8))
        await newCopy?.value
        #expect(pasteboard.strings == ["new-output"])
        #expect(session.outputAction == nil)
    }

    @Test func sessionCancelledCopyDoesNotWritePasteboard() async {
        let session = Base64FileWorkflowSession()
        let processor = FakeBase64FileWorkflowProcessor()
        let serialization = SuspendedTestValue<Data>()
        let pasteboard = FakeBase64Pasteboard()
        let client = Base64FileWorkflowClient(dialog: FakeBase64FileDialog(), pasteboard: pasteboard)
        processor.readSelectionResult = .success(Self.selection())
        processor.serializeUTF8Handler = { _ in await serialization.wait() }

        await session.readSelectedFile(from: URL(fileURLWithPath: "/tmp/source.bin"), processor: processor)?.value
        let copyTask = session.copyFullOutput(client: client, processor: processor)
        await serialization.waitForRequest()
        copyTask?.cancel()
        serialization.resume(Data("cancelled-output".utf8))
        await copyTask?.value

        #expect(pasteboard.strings.isEmpty)
        #expect(session.outputAction == nil)
        #expect(session.fileError == nil)
    }

    @Test func sessionEncodedSaveHandlesCancelSuccessFailureAndStaleResult() async {
        let session = Base64FileWorkflowSession()
        let processor = FakeBase64FileWorkflowProcessor()
        let dialog = FakeBase64FileDialog()
        let client = Base64FileWorkflowClient(dialog: dialog, pasteboard: FakeBase64Pasteboard())
        processor.readSelectionResult = .success(Self.selection(fileName: "source.png", data: Data([1, 2, 3]), mimeType: "image/png"))
        processor.fullOutputText = "encoded-output"

        await session.readSelectedFile(from: URL(fileURLWithPath: "/tmp/source.png"), processor: processor)?.value
        await session.saveEncodedOutput(client: client, processor: processor)?.value
        #expect(dialog.encodedSaveNames == ["source.data-url.txt"])
        #expect(processor.textWrites.isEmpty)
        #expect(session.fileError == nil)

        dialog.encodedURL = URL(fileURLWithPath: "/tmp/output.txt")
        await session.saveEncodedOutput(client: client, processor: processor)?.value
        #expect(processor.textWrites.map(\.text) == ["encoded-output"])
        #expect(processor.textWrites.map(\.url) == [URL(fileURLWithPath: "/tmp/output.txt")])
        #expect(session.fileError == nil)

        processor.writeTextResult = .failure(.saveFailed)
        await session.saveEncodedOutput(client: client, processor: processor)?.value
        #expect(session.fileError == "无法保存文件。")

        let staleOutput = SuspendedTestValue<String>()
        processor.writeTextResult = .success(())
        processor.fullOutputHandler = { _, _ in
            await staleOutput.wait()
        }
        let writeCountBeforeStale = processor.textWrites.count
        let staleTask = session.saveEncodedOutput(client: client, processor: processor)
        await staleOutput.waitForRequest()
        session.clearSelection()
        staleOutput.resume("stale")
        await staleTask?.value

        #expect(processor.textWrites.count == writeCountBeforeStale)
        #expect(session.outputAction == nil)
    }

    @Test func sessionOldSavePanelCancelCannotClearNewCopyBusyState() async {
        let session = Base64FileWorkflowSession()
        let processor = FakeBase64FileWorkflowProcessor()
        let dialog = FakeBase64FileDialog()
        let panel = SuspendedTestValue<URL?>()
        let newSerialization = SuspendedTestValue<Data>()
        let pasteboard = FakeBase64Pasteboard()
        let client = Base64FileWorkflowClient(dialog: dialog, pasteboard: pasteboard)
        dialog.encodedURLHandler = { _ in await panel.wait() }
        processor.readSelectionResult = .success(Self.selection())
        processor.serializeUTF8Handler = { _ in await newSerialization.wait() }

        await session.readSelectedFile(from: URL(fileURLWithPath: "/tmp/source.bin"), processor: processor)?.value
        let oldSave = session.saveEncodedOutput(client: client, processor: processor)
        await panel.waitForRequest()
        session.clearSelection()
        let replacement = Base64FileSelection(
            fileName: "replacement.bin",
            data: Data("replacement".utf8),
            mimeType: "application/octet-stream"
        )
        processor.readSelectionResult = .success(replacement)
        await session.readSelectedFile(from: URL(fileURLWithPath: "/tmp/replacement.bin"), processor: processor)?.value
        let newCopy = session.copyFullOutput(client: client, processor: processor)
        await newSerialization.waitForRequest()

        panel.resume(nil)
        await oldSave?.value
        #expect(session.outputAction == .copying)
        #expect(processor.textWrites.isEmpty)

        newSerialization.resume(Data("new-output".utf8))
        await newCopy?.value
        #expect(session.outputAction == nil)
    }

    @Test func sessionCancelledSaveDoesNotStartDiskWrite() async {
        let session = Base64FileWorkflowSession()
        let processor = FakeBase64FileWorkflowProcessor()
        let dialog = FakeBase64FileDialog()
        let panel = SuspendedTestValue<URL?>()
        let client = Base64FileWorkflowClient(dialog: dialog, pasteboard: FakeBase64Pasteboard())
        dialog.encodedURLHandler = { _ in await panel.wait() }
        processor.readSelectionResult = .success(Self.selection())

        await session.readSelectedFile(from: URL(fileURLWithPath: "/tmp/source.bin"), processor: processor)?.value
        let saveTask = session.saveEncodedOutput(client: client, processor: processor)
        await panel.waitForRequest()
        saveTask?.cancel()
        panel.resume(URL(fileURLWithPath: "/tmp/output.txt"))
        await saveTask?.value

        #expect(processor.textWrites.isEmpty)
        #expect(session.outputAction == nil)
        #expect(session.fileError == nil)
    }

    @Test func sessionCancellationAfterSaveWriteStartsDoesNotReportSuccess() async {
        let session = Base64FileWorkflowSession()
        let processor = FakeBase64FileWorkflowProcessor()
        let dialog = FakeBase64FileDialog()
        let writeResult = SuspendedTestValue<Result<Void, Base64FileWorkflowFailure>>()
        let client = Base64FileWorkflowClient(dialog: dialog, pasteboard: FakeBase64Pasteboard())
        dialog.encodedURL = URL(fileURLWithPath: "/tmp/output.txt")
        processor.readSelectionResult = .success(Self.selection())
        processor.writeTextHandler = { _, _ in await writeResult.wait() }
        var successCount = 0

        await session.readSelectedFile(from: URL(fileURLWithPath: "/tmp/source.bin"), processor: processor)?.value
        let saveTask = session.saveEncodedOutput(client: client, processor: processor) {
            successCount += 1
        }
        await writeResult.waitForRequest()
        saveTask?.cancel()
        writeResult.resume(.success(()))
        await saveTask?.value

        #expect(processor.textWrites.count == 1)
        #expect(successCount == 0)
        #expect(session.outputAction == nil)
        #expect(session.fileError == nil)
    }

    @Test func sessionDecodeHandlesDirtyStateFailureSuccessAndStaleResult() async {
        let session = Base64FileWorkflowSession()
        let processor = FakeBase64FileWorkflowProcessor()
        let payload = Base64Conversion.FilePayload(
            data: Data("hello".utf8),
            mimeType: "text/plain",
            fileExtension: "txt"
        )

        session.updateReverseInput("first")
        #expect(session.reverseInputDirty)
        processor.decodeResult = .failure(.decodedTooLarge(maxBytes: 4))
        await session.decodeReverseInput(processor: processor)?.value
        #expect(session.reverseError == "解码后的文件超过 4 B 的大小限制。")
        #expect(session.decodedPayload == nil)

        processor.decodeResult = .success(payload)
        session.updateReverseInput(Data("hello".utf8).base64EncodedString())
        await session.decodeReverseInput(processor: processor)?.value
        #expect(session.decodedPayload == payload)
        #expect(session.decodedResultSource == .manualInput)
        #expect(session.outputFileName == "download")
        #expect(session.reverseError == nil)
        #expect(session.reverseInputDirty == false)

        let suspendedDecode = SuspendedTestValue<Result<Base64Conversion.FilePayload, Base64FileWorkflowFailure>>()
        processor.decodeHandler = { _ in
            await suspendedDecode.wait()
        }
        session.updateReverseInput("stale")
        let decodeTask = session.decodeReverseInput(processor: processor)
        await suspendedDecode.waitForRequest()
        session.updateReverseInput("new input")
        suspendedDecode.resume(.success(payload))
        await decodeTask?.value

        #expect(session.decodedPayload == nil)
        #expect(session.reverseInputDirty)
        #expect(session.isDecoding == false)
    }

    @Test func sessionManualDecodeKeepsItsActivityUntilOutcomeIsPublished() async {
        let session = Base64FileWorkflowSession()
        let processor = FakeBase64FileWorkflowProcessor()
        let payload = Base64Conversion.FilePayload(
            data: Data("hello".utf8),
            mimeType: "text/plain",
            fileExtension: "txt"
        )
        let suspendedDecode = SuspendedTestValue<Result<Base64Conversion.FilePayload, Base64FileWorkflowFailure>>()
        processor.decodeHandler = { _ in
            await suspendedDecode.wait()
        }
        session.updateReverseInput("aGVsbG8=")
        var didBeginDecoding = false
        var observedIdleEmptyState = false
        let observation = session.objectWillChange.sink {
            if session.isDecoding {
                didBeginDecoding = true
            }
            if didBeginDecoding,
               !session.isDecoding,
               session.decodedPayload == nil,
               session.reverseError == nil {
                observedIdleEmptyState = true
            }
        }

        let decodeTask = session.decodeReverseInput(processor: processor)
        await suspendedDecode.waitForRequest()

        #expect(session.decodeActivity == .manualInput)
        suspendedDecode.resume(.success(payload))
        await decodeTask?.value

        #expect(observedIdleEmptyState == false)
        #expect(session.decodedPayload == payload)
        #expect(session.decodeActivity == nil)
        _ = observation
    }

    @Test func sessionManualDecodePublishesFailureBeforeEndingActivity() async {
        let session = Base64FileWorkflowSession()
        let processor = FakeBase64FileWorkflowProcessor()
        processor.decodeResult = .failure(.invalidPayload)
        session.updateReverseInput("not-base64")
        var didBeginDecoding = false
        var observedIdleEmptyState = false
        let observation = session.objectWillChange.sink {
            if session.isDecoding {
                didBeginDecoding = true
            }
            if didBeginDecoding,
               !session.isDecoding,
               session.decodedPayload == nil,
               session.reverseError == nil {
                observedIdleEmptyState = true
            }
        }

        await session.decodeReverseInput(processor: processor)?.value

        #expect(observedIdleEmptyState == false)
        #expect(session.reverseError == "输入不是有效的 Base64 或 Base64 Data URL。")
        #expect(session.decodeActivity == nil)
        _ = observation
    }

    @Test func sessionRejectsReverseInputAboveEditableLimitAndClearsDecodedState() async {
        let session = Base64FileWorkflowSession()
        let processor = FakeBase64FileWorkflowProcessor()
        let payload = Base64Conversion.FilePayload(
            data: Data("hello".utf8),
            mimeType: "text/plain",
            fileExtension: "txt"
        )
        let validInput = Data("hello".utf8).base64EncodedString()
        processor.decodeResult = .success(payload)

        session.updateReverseInput(validInput)
        await session.decodeReverseInput(processor: processor)?.value
        #expect(session.decodedPayload == payload)
        #expect(session.reverseInputDirty == false)

        let oversizedInput = String(
            repeating: "A",
            count: Base64FileWorkflowSession.editableReverseInputByteLimit + 1
        )
        session.updateReverseInput(oversizedInput)

        #expect(session.reverseInput == validInput)
        #expect(session.decodedPayload == nil)
        #expect(session.decodedResultSource == nil)
        #expect(session.previewImage == nil)
        #expect(session.reverseInputDirty)
        #expect(session.isDecoding == false)
        #expect(session.isSavingDecoded == false)
        #expect(session.reverseError?.contains("1 MB") == true)
        #expect(session.reverseError == "可编辑的 Base64 或 Data URL 不能超过 1 MB。")
    }

    @Test func sessionSendsCurrentOutputToDecodeResultWithoutParsingBase64() async {
        let session = Base64FileWorkflowSession()
        let processor = FakeBase64FileWorkflowProcessor()
        let selection = Self.selection(fileName: "photo.png", data: Data([0x89, 0x50, 0x4E, 0x47]), mimeType: "image/png")
        processor.readSelectionResult = .success(selection)

        session.updateReverseInput("small editable draft")
        await session.readSelectedFile(from: URL(fileURLWithPath: "/tmp/photo.png"), processor: processor)?.value
        await session.sendCurrentOutputToDecodeResult(processor: processor)?.value

        #expect(session.direction == .decode)
        #expect(session.reverseInput == "small editable draft")
        #expect(session.decodedPayload?.data == selection.data)
        #expect(session.decodedPayload?.mimeType == "image/png")
        #expect(session.decodedPayload?.fileExtension == "png")
        #expect(session.decodedResultSource == .currentEncodedOutput(fileName: "photo.png"))
        #expect(session.outputFileName == "photo.png")
        #expect(processor.decodeInputs.isEmpty)
        #expect(processor.directDecodeSelections == [selection])

        let dialog = FakeBase64FileDialog()
        let client = Base64FileWorkflowClient(dialog: dialog, pasteboard: FakeBase64Pasteboard())
        await session.saveDecodedPayload(client: client, processor: processor)?.value
        #expect(dialog.decodedSaveNames == ["photo.png"])
    }

    @Test func sessionPreparesCurrentOutputResultBeforeSwitchingDirectionAndEndingActivity() async {
        let session = Base64FileWorkflowSession()
        let processor = FakeBase64FileWorkflowProcessor()
        let selection = Self.selection(fileName: "source.bin", data: Data("hello".utf8))
        let payload = Base64Conversion.FilePayload(
            data: selection.data,
            mimeType: selection.mimeType,
            fileExtension: "bin"
        )
        let suspendedPayload = SuspendedTestValue<Base64Conversion.FilePayload>()
        processor.readSelectionResult = .success(selection)
        processor.decodedPayloadHandler = { _ in
            await suspendedPayload.wait()
        }
        await session.readSelectedFile(
            from: URL(fileURLWithPath: "/tmp/source.bin"),
            processor: processor
        )?.value
        var observedDecodeDirectionWithoutPayload = false
        let observation = session.objectWillChange.sink {
            if session.direction == .decode, session.decodedPayload == nil {
                observedDecodeDirectionWithoutPayload = true
            }
        }

        let previewTask = session.sendCurrentOutputToDecodeResult(processor: processor)
        await suspendedPayload.waitForRequest()

        #expect(session.direction == .encode)
        #expect(session.decodeActivity == .encodedOutputPreview)
        suspendedPayload.resume(payload)
        await previewTask?.value

        #expect(observedDecodeDirectionWithoutPayload == false)
        #expect(session.direction == .decode)
        #expect(session.decodedPayload == payload)
        #expect(session.decodeActivity == nil)
        _ = observation
    }

    @Test func sessionModeChangeInvalidatesPendingSendWithoutClearingNewCopy() async {
        let session = Base64FileWorkflowSession()
        let processor = FakeBase64FileWorkflowProcessor()
        let suspendedPayload = SuspendedTestValue<Base64Conversion.FilePayload>()
        let newSerialization = SuspendedTestValue<Data>()
        let pasteboard = FakeBase64Pasteboard()
        let client = Base64FileWorkflowClient(dialog: FakeBase64FileDialog(), pasteboard: pasteboard)
        let selection = Self.selection()
        processor.readSelectionResult = .success(selection)
        processor.decodedPayloadHandler = { _ in await suspendedPayload.wait() }
        processor.serializeUTF8Handler = { _ in await newSerialization.wait() }

        await session.readSelectedFile(from: URL(fileURLWithPath: "/tmp/source.bin"), processor: processor)?.value
        let oldSend = session.sendCurrentOutputToDecodeResult(processor: processor)
        await suspendedPayload.waitForRequest()
        await session.changeOutputMode(to: .base64, processor: processor)?.value
        #expect(session.outputAction == nil)
        #expect(session.decodeActivity == nil)
        let newCopy = session.copyFullOutput(client: client, processor: processor)
        await newSerialization.waitForRequest()

        suspendedPayload.resume(Base64Conversion.FilePayload(
            data: selection.data,
            mimeType: selection.mimeType,
            fileExtension: "bin"
        ))
        await oldSend?.value
        #expect(session.direction == .encode)
        #expect(session.decodedPayload == nil)
        #expect(session.outputAction == .copying)

        newSerialization.resume(Data("new-output".utf8))
        await newCopy?.value
        #expect(session.outputAction == nil)
    }

    @Test func sessionCancelledSendDoesNotPublishDecodedResult() async {
        let session = Base64FileWorkflowSession()
        let processor = FakeBase64FileWorkflowProcessor()
        let suspendedPayload = SuspendedTestValue<Base64Conversion.FilePayload>()
        let selection = Self.selection()
        processor.readSelectionResult = .success(selection)
        processor.decodedPayloadHandler = { _ in await suspendedPayload.wait() }

        await session.readSelectedFile(from: URL(fileURLWithPath: "/tmp/source.bin"), processor: processor)?.value
        let sendTask = session.sendCurrentOutputToDecodeResult(processor: processor)
        await suspendedPayload.waitForRequest()
        sendTask?.cancel()
        suspendedPayload.resume(Base64Conversion.FilePayload(
            data: selection.data,
            mimeType: selection.mimeType,
            fileExtension: "bin"
        ))
        await sendTask?.value

        #expect(session.direction == .encode)
        #expect(session.decodedPayload == nil)
        #expect(session.outputAction == nil)
        #expect(session.decodeActivity == nil)
    }

    @Test func sessionEncodedTextFileImportReadsThroughProcessorAndUsesSourceBasename() async {
        let session = Base64FileWorkflowSession()
        let processor = FakeBase64FileWorkflowProcessor()
        let dialog = FakeBase64FileDialog()
        let client = Base64FileWorkflowClient(dialog: dialog, pasteboard: FakeBase64Pasteboard())
        let importURL = URL(fileURLWithPath: "/tmp/photo-data-url.txt")
        var requests: [FileInputPanelRequest] = []
        let filePanel = FileInputPanelClient { request in
            requests.append(request)
            return importURL
        }
        processor.readEncodedTextResult = .success(
            Base64FileEncodedTextInput(fileName: "photo-data-url.txt", text: "data:image/png;base64,iVBORw0KGgo=")
        )

        session.updateReverseInput("manual draft")
        await session.importEncodedTextFile(filePanel: filePanel, processor: processor).value

        #expect(requests.count == 1)
        #expect(requests[0].allowedContentTypes.contains(.plainText))
        #expect(requests[0].allowedContentTypes.contains(.text))
        #expect(processor.encodedTextReads.map(\.url) == [importURL])
        #expect(processor.encodedTextReads.map(\.maxBytes) == [Base64FileWorkflowSession.externalEncodedTextByteLimit])
        #expect(session.reverseInput == "manual draft")
        #expect(session.decodedPayload?.mimeType == "image/png")
        #expect(session.decodedPayload?.fileExtension == "png")
        #expect(session.decodedResultSource == .encodedTextFile(fileName: "photo-data-url.txt"))
        #expect(session.outputFileName == "photo-data-url")

        await session.saveDecodedPayload(client: client, processor: processor)?.value
        #expect(dialog.decodedSaveNames == ["photo-data-url.png"])
    }

    @Test func sessionPublishesImportedDecodeOutcomeBeforeEndingBusyState() async {
        let session = Base64FileWorkflowSession()
        let processor = FakeBase64FileWorkflowProcessor()
        let payload = Base64Conversion.FilePayload(
            data: Data("hello".utf8),
            mimeType: "text/plain",
            fileExtension: "txt"
        )
        processor.readEncodedTextResult = .success(
            Base64FileEncodedTextInput(fileName: "hello.base64", text: "aGVsbG8=")
        )
        processor.decodeResult = .success(payload)
        var didBeginDecoding = false
        var observedIdleEmptyState = false
        let observation = session.objectWillChange.sink {
            if session.isDecoding {
                didBeginDecoding = true
            }
            if didBeginDecoding,
               !session.isDecoding,
               session.decodedPayload == nil,
               session.reverseError == nil {
                observedIdleEmptyState = true
            }
        }

        await session.importEncodedTextFile(
            from: URL(fileURLWithPath: "/tmp/hello.base64"),
            processor: processor
        ).value

        #expect(observedIdleEmptyState == false)
        #expect(session.decodedPayload == payload)
        #expect(session.isDecoding == false)
        _ = observation
    }

    @Test func sessionPublishesImportedReadErrorBeforeEndingBusyState() async {
        let session = Base64FileWorkflowSession()
        let processor = FakeBase64FileWorkflowProcessor()
        processor.readEncodedTextResult = .failure(.readFailed)
        var didBeginDecoding = false
        var observedIdleEmptyState = false
        let observation = session.objectWillChange.sink {
            if session.isDecoding {
                didBeginDecoding = true
            }
            if didBeginDecoding,
               !session.isDecoding,
               session.decodedPayload == nil,
               session.reverseError == nil {
                observedIdleEmptyState = true
            }
        }

        await session.importEncodedTextFile(
            from: URL(fileURLWithPath: "/tmp/unreadable.base64"),
            processor: processor
        ).value

        #expect(observedIdleEmptyState == false)
        #expect(session.reverseError == "无法读取所选文件。")
        #expect(session.isDecoding == false)
        _ = observation
    }

    @Test func staleEncodedTextReadDoesNotEndNewerImportBusyState() async {
        let session = Base64FileWorkflowSession()
        let processor = FakeBase64FileWorkflowProcessor()
        let firstRead = SuspendedTestValue<Result<Base64FileEncodedTextInput, Base64FileWorkflowFailure>>()
        let secondRead = SuspendedTestValue<Result<Base64FileEncodedTextInput, Base64FileWorkflowFailure>>()
        processor.readEncodedTextHandler = { url, _ in
            if url.lastPathComponent == "first.base64" {
                return await firstRead.wait()
            }
            return await secondRead.wait()
        }

        let firstTask = session.importEncodedTextFile(
            from: URL(fileURLWithPath: "/tmp/first.base64"),
            processor: processor
        )
        await firstRead.waitForRequest()
        #expect(session.decodeActivity == .encodedTextImport)
        let secondTask = session.importEncodedTextFile(
            from: URL(fileURLWithPath: "/tmp/second.base64"),
            processor: processor
        )
        await secondRead.waitForRequest()

        firstRead.resume(.failure(.readFailed))
        await firstTask.value

        #expect(session.isDecoding)

        secondRead.resume(.failure(.readFailed))
        await secondTask.value
        #expect(session.isDecoding == false)
        #expect(session.decodeActivity == nil)
    }

    @Test func cancelledEncodedTextReadEndsOnlyItsOwnDecodeActivity() async {
        let session = Base64FileWorkflowSession()
        let processor = FakeBase64FileWorkflowProcessor()
        let suspendedRead = SuspendedTestValue<Result<Base64FileEncodedTextInput, Base64FileWorkflowFailure>>()
        processor.readEncodedTextHandler = { _, _ in await suspendedRead.wait() }

        let task = session.importEncodedTextFile(
            from: URL(fileURLWithPath: "/tmp/cancelled.base64"),
            processor: processor
        )
        await suspendedRead.waitForRequest()
        task.cancel()
        suspendedRead.resume(.failure(.readFailed))
        await task.value

        #expect(session.decodeActivity == nil)
        #expect(session.reverseError == nil)
        #expect(session.decodedPayload == nil)
    }

    @Test func staleEncodedTextDecodeDoesNotEndNewerImportBusyState() async {
        let session = Base64FileWorkflowSession()
        let processor = FakeBase64FileWorkflowProcessor()
        let payload = Base64Conversion.FilePayload(
            data: Data("hello".utf8),
            mimeType: "text/plain",
            fileExtension: "txt"
        )
        let firstDecode = SuspendedTestValue<Result<Base64Conversion.FilePayload, Base64FileWorkflowFailure>>()
        let secondDecode = SuspendedTestValue<Result<Base64Conversion.FilePayload, Base64FileWorkflowFailure>>()
        processor.readEncodedTextHandler = { url, _ in
            .success(Base64FileEncodedTextInput(fileName: url.lastPathComponent, text: url.lastPathComponent))
        }
        processor.decodeHandler = { input in
            if input == "first.base64" {
                return await firstDecode.wait()
            }
            return await secondDecode.wait()
        }

        let firstTask = session.importEncodedTextFile(
            from: URL(fileURLWithPath: "/tmp/first.base64"),
            processor: processor
        )
        await firstDecode.waitForRequest()
        let secondTask = session.importEncodedTextFile(
            from: URL(fileURLWithPath: "/tmp/second.base64"),
            processor: processor
        )
        await secondDecode.waitForRequest()

        firstDecode.resume(.success(payload))
        await firstTask.value

        #expect(session.isDecoding)

        secondDecode.resume(.success(payload))
        await secondTask.value
        #expect(session.decodedPayload == payload)
        #expect(session.isDecoding == false)
    }

    @Test func sessionEncodedTextFileImportHandlesCancelFailureInvalidAndTooLarge() async {
        let session = Base64FileWorkflowSession()
        let processor = FakeBase64FileWorkflowProcessor()
        let cancelledPanel = FileInputPanelClient { _ in nil }

        await session.importEncodedTextFile(filePanel: cancelledPanel, processor: processor).value
        #expect(processor.encodedTextReads.isEmpty)
        #expect(session.reverseError == nil)

        let importURL = URL(fileURLWithPath: "/tmp/input.base64")
        let filePanel = FileInputPanelClient { _ in importURL }
        processor.readEncodedTextResult = .failure(.readFailed)
        await session.importEncodedTextFile(filePanel: filePanel, processor: processor).value
        #expect(session.reverseError == "无法读取所选文件。")

        processor.readEncodedTextResult = .success(Base64FileEncodedTextInput(fileName: "input.base64", text: "not base64"))
        await session.importEncodedTextFile(filePanel: filePanel, processor: processor).value
        #expect(session.reverseError == "输入不是有效的 Base64 或 Base64 Data URL。")

        processor.readEncodedTextResult = .success(
            Base64FileEncodedTextInput(
                fileName: "huge.base64",
                text: String(repeating: "A", count: Base64FileWorkflowSession.externalEncodedTextByteLimit + 1)
            )
        )
        await session.importEncodedTextFile(filePanel: filePanel, processor: processor).value
        #expect(session.reverseError?.contains("16 MB") == true)

        let unavailablePanel = FileInputPanelClient { _ in
            throw FileInputPanelFailure.requestInProgress
        }
        await session.importEncodedTextFile(filePanel: unavailablePanel, processor: processor).value
        #expect(session.reverseError == "已有文件选择器正在打开。")
    }

    @Test func sessionDecodedSaveHandlesCancelSuccessFailureAndStalePayload() async {
        let session = Base64FileWorkflowSession()
        let processor = FakeBase64FileWorkflowProcessor()
        let dialog = FakeBase64FileDialog()
        let client = Base64FileWorkflowClient(dialog: dialog, pasteboard: FakeBase64Pasteboard())
        let payload = Base64Conversion.FilePayload(
            data: Data("hello".utf8),
            mimeType: "text/plain",
            fileExtension: "txt"
        )
        processor.decodeResult = .success(payload)

        session.updateReverseInput(Data("hello".utf8).base64EncodedString())
        await session.decodeReverseInput(processor: processor)?.value
        await session.saveDecodedPayload(client: client, processor: processor)?.value
        #expect(dialog.decodedSaveNames == ["download.txt"])
        #expect(processor.dataWrites.isEmpty)
        #expect(session.reverseError == nil)

        dialog.decodedURL = URL(fileURLWithPath: "/tmp/download.txt")
        await session.saveDecodedPayload(client: client, processor: processor)?.value
        #expect(processor.dataWrites.map(\.data) == [payload.data])
        #expect(processor.dataWrites.map(\.url) == [URL(fileURLWithPath: "/tmp/download.txt")])
        #expect(session.reverseError == nil)

        processor.writeDataResult = .failure(.saveFailed)
        await session.saveDecodedPayload(client: client, processor: processor)?.value
        #expect(session.reverseError == "无法保存文件。")

        processor.writeDataResult = .success(())
        let writeCountBeforeStale = processor.dataWrites.count
        let staleWrite = SuspendedTestValue<Result<Void, Base64FileWorkflowFailure>>()
        processor.writeDataHandler = { _, _ in
            await staleWrite.wait()
        }
        let staleTask = session.saveDecodedPayload(client: client, processor: processor)
        await staleWrite.waitForRequest()
        session.clearReverse()
        staleWrite.resume(.success(()))
        await staleTask?.value

        #expect(processor.dataWrites.count == writeCountBeforeStale + 1)
        #expect(session.decodedPayload == nil)
        #expect(session.reverseError == nil)
        #expect(session.isSavingDecoded == false)
    }

    @Test func sessionOldDecodedWriteCannotClearNewSaveBusyState() async {
        let session = Base64FileWorkflowSession()
        let processor = FakeBase64FileWorkflowProcessor()
        let dialog = FakeBase64FileDialog()
        let client = Base64FileWorkflowClient(dialog: dialog, pasteboard: FakeBase64Pasteboard())
        let oldWrite = SuspendedTestValue<Result<Void, Base64FileWorkflowFailure>>()
        let newWrite = SuspendedTestValue<Result<Void, Base64FileWorkflowFailure>>()
        let oldPayload = Base64Conversion.FilePayload(
            data: Data("old".utf8), mimeType: "text/plain", fileExtension: "txt"
        )
        let newPayload = Base64Conversion.FilePayload(
            data: Data("new".utf8), mimeType: "text/plain", fileExtension: "txt"
        )
        dialog.decodedURL = URL(fileURLWithPath: "/tmp/download.txt")
        processor.writeDataHandler = { data, _ in
            if data == oldPayload.data { return await oldWrite.wait() }
            return await newWrite.wait()
        }
        session.changeDirection(to: .decode)
        session.updateReverseInput("b2xk")
        processor.decodeResult = .success(oldPayload)
        await session.decodeReverseInput(processor: processor)?.value
        let oldSave = session.saveDecodedPayload(client: client, processor: processor)
        await oldWrite.waitForRequest()

        session.changeDirection(to: .encode)
        session.changeDirection(to: .decode)
        session.updateReverseInput("bmV3")
        processor.decodeResult = .success(newPayload)
        await session.decodeReverseInput(processor: processor)?.value
        let newSave = session.saveDecodedPayload(client: client, processor: processor)
        await newWrite.waitForRequest()
        #expect(session.isSavingDecoded)

        oldWrite.resume(.success(()))
        await oldSave?.value
        #expect(session.isSavingDecoded)
        #expect(session.decodedPayload == newPayload)
        #expect(session.reverseError == nil)

        newWrite.resume(.success(()))
        await newSave?.value
        #expect(!session.isSavingDecoded)
        #expect(processor.dataWrites.map(\.data) == [oldPayload.data, newPayload.data])
    }

    @Test func sessionCancelledDecodedSaveDoesNotPublishWriteCompletion() async {
        let session = Base64FileWorkflowSession()
        let processor = FakeBase64FileWorkflowProcessor()
        let dialog = FakeBase64FileDialog()
        let client = Base64FileWorkflowClient(dialog: dialog, pasteboard: FakeBase64Pasteboard())
        let writeResult = SuspendedTestValue<Result<Void, Base64FileWorkflowFailure>>()
        let payload = Base64Conversion.FilePayload(
            data: Data("saved".utf8), mimeType: "text/plain", fileExtension: "txt"
        )
        dialog.decodedURL = URL(fileURLWithPath: "/tmp/download.txt")
        processor.decodeResult = .success(payload)
        processor.writeDataHandler = { _, _ in await writeResult.wait() }
        var successCount = 0

        session.changeDirection(to: .decode)
        session.updateReverseInput("c2F2ZWQ=")
        await session.decodeReverseInput(processor: processor)?.value
        let saveTask = session.saveDecodedPayload(client: client, processor: processor) {
            successCount += 1
        }
        await writeResult.waitForRequest()
        saveTask?.cancel()
        writeResult.resume(.success(()))
        await saveTask?.value

        #expect(processor.dataWrites.map(\.data) == [payload.data])
        #expect(successCount == 0)
        #expect(!session.isSavingDecoded)
        #expect(session.reverseError == nil)
    }

    @Test func everyWorkflowFailureUsesFactualMessageWithoutSystemPayload() {
        let sensitiveFileName = "/Users/example/private/token-output.txt"
        let failures: [Base64FileWorkflowFailure] = [
            .notRegularFile,
            .tooLarge(fileName: sensitiveFileName, maxBytes: 1024),
            .decodedTooLarge(maxBytes: 1024),
            .reverseInputTooLarge(maxBytes: 1024),
            .externalEncodedTextTooLarge(maxBytes: 1024),
            .encodedTextNotUTF8,
            .readFailed,
            .invalidPayload,
            .copyFailed,
            .saveFailed,
        ]

        for failure in failures {
            ToolDiagnosticContract.expectFactual(
                failure.errorDescription ?? "",
                sensitiveInputs: [sensitiveFileName]
            )
        }
    }

    // MARK: - Challenger M2 并入：roundtrip 属性与边界输入

    @Test func roundtripArbitraryBinaryBuffersOfVaryingSizes() async throws {
        let testSizes = [0, 1, 2, 3, 4, 15, 16, 17, 255, 256, 1024, 65536]

        for size in testSizes {
            var bytes = [UInt8](repeating: 0, count: size)
            if size > 0 {
                for i in 0..<size {
                    bytes[i] = UInt8(i % 256)
                }
            }
            let originalData = Data(bytes)
            let selection = Base64FileSelection(
                fileName: "test_\(size).bin",
                data: originalData,
                mimeType: "application/octet-stream"
            )

            let rawBase64 = await Base64FileWorkflow.fullOutput(for: selection, mode: .base64)
            let decodedRaw = await Base64FileWorkflow.decodePayload(rawBase64, maxDecodedBytes: size + 100)
            guard case .success(let payloadRaw) = decodedRaw else {
                Issue.record("Failed to decode raw base64 for size \(size)")
                continue
            }
            #expect(payloadRaw.data == originalData, "Payload mismatch for raw base64 size \(size)")

            let dataURL = await Base64FileWorkflow.fullOutput(for: selection, mode: .dataURL)
            let decodedDataURL = await Base64FileWorkflow.decodePayload(dataURL, maxDecodedBytes: size + 100)
            guard case .success(let payloadURL) = decodedDataURL else {
                Issue.record("Failed to decode Data URL for size \(size)")
                continue
            }
            #expect(payloadURL.data == originalData, "Payload mismatch for data URL size \(size)")
        }
    }

    @Test func roundtripBoundaryPaddingCases() async throws {
        // 1 byte -> 2 padding chars (==)
        let oneByte = Data([0x41])
        let encoded1 = await Base64FileWorkflow.fullOutput(
            for: Base64FileSelection(fileName: "1.bin", data: oneByte, mimeType: "application/octet-stream"),
            mode: .base64
        )
        #expect(encoded1.hasSuffix("=="))
        let decoded1 = await Base64FileWorkflow.decodePayload(encoded1, maxDecodedBytes: 10)
        guard case .success(let p1) = decoded1 else {
            Issue.record("Expected successful decode for 1 byte")
            return
        }
        #expect(p1.data == oneByte)

        // 2 bytes -> 1 padding char (=)
        let twoBytes = Data([0x41, 0x42])
        let encoded2 = await Base64FileWorkflow.fullOutput(
            for: Base64FileSelection(fileName: "2.bin", data: twoBytes, mimeType: "application/octet-stream"),
            mode: .base64
        )
        #expect(encoded2.hasSuffix("="))
        let decoded2 = await Base64FileWorkflow.decodePayload(encoded2, maxDecodedBytes: 10)
        guard case .success(let p2) = decoded2 else {
            Issue.record("Expected successful decode for 2 bytes")
            return
        }
        #expect(p2.data == twoBytes)

        // 3 bytes -> 0 padding chars
        let threeBytes = Data([0x41, 0x42, 0x43])
        let encoded3 = await Base64FileWorkflow.fullOutput(
            for: Base64FileSelection(fileName: "3.bin", data: threeBytes, mimeType: "application/octet-stream"),
            mode: .base64
        )
        #expect(!encoded3.hasSuffix("="))
        let decoded3 = await Base64FileWorkflow.decodePayload(encoded3, maxDecodedBytes: 10)
        guard case .success(let p3) = decoded3 else {
            Issue.record("Expected successful decode for 3 bytes")
            return
        }
        #expect(p3.data == threeBytes)
    }

    @Test func decodeRejectsMalformedAndPinsLenientBase64Edges() async {
        // 一律拒绝：字母表外字符（含非 ASCII 与 NUL）、长度余 1 的不可能
        // Base64、缺逗号/缺 base64 标记的残缺 data URL。
        let rejected = [
            "???not_base64???",
            "abcde",                             // 5 字符，长度余 1
            "data:",                             // 无逗号
            "data:image/png",                    // 无 base64 标记与逗号
            "data:image/png;base64",             // 无逗号
            "data:image/png;base64,invalid!@#$", // payload 含字母表外字符
            "中文测试内容",
            "\0\0\0\0",
        ]
        for input in rejected {
            let result = await Base64FileWorkflow.decodePayload(input)
            #expect(result == .failure(.invalidPayload), "应拒绝: \(input)")
        }

        // 宽容语义（decodeData 的既有契约）：纯空白与全填充串归一为空数据；
        // 缺失/多余填充补齐后照常解码。
        for input in ["", "   \n\t  ", "======"] {
            let result = await Base64FileWorkflow.decodePayload(input)
            guard case .success(let payload) = result else {
                Issue.record("应按空数据成功解码: \(input)")
                return
            }
            #expect(payload.data.isEmpty)
            #expect(payload.mimeType == "application/octet-stream")
            #expect(payload.fileExtension == "bin")
        }
        for input in ["aGVsbG8", "aGVsbG8==="] {
            let result = await Base64FileWorkflow.decodePayload(input)
            guard case .success(let payload) = result else {
                Issue.record("应按宽容填充语义解码: \(input)")
                return
            }
            #expect(payload.data == Data("hello".utf8))
        }

        // data URL 边界：空 payload 用 URL 元数据产出类型；缺 mime 按 RFC
        // 兜底 text/plain;charset=us-ascii。
        let emptyPNG = await Base64FileWorkflow.decodePayload("data:image/png;base64,")
        guard case .success(let pngPayload) = emptyPNG else {
            Issue.record("空 payload 的 data URL 应成功解码")
            return
        }
        #expect(pngPayload.data.isEmpty)
        #expect(pngPayload.mimeType == "image/png")
        #expect(pngPayload.fileExtension == "png")

        let noMime = await Base64FileWorkflow.decodePayload("data:;base64,aGVsbG8=")
        guard case .success(let plainPayload) = noMime else {
            Issue.record("缺 mime 的 data URL 应成功解码")
            return
        }
        #expect(plainPayload.data == Data("hello".utf8))
        #expect(plainPayload.mimeType == "text/plain;charset=us-ascii")
        #expect(plainPayload.fileExtension == "txt")
    }

    @Test func readSelectionHandlesFileSystemEdgeCases() async throws {
        let tempDir = FileManager.default.temporaryDirectory
        let validFile = tempDir.appendingPathComponent("workflow_valid_\(UUID().uuidString).txt")
        let oversizedFile = tempDir.appendingPathComponent("workflow_large_\(UUID().uuidString).bin")
        let subDirectory = tempDir.appendingPathComponent("workflow_dir_\(UUID().uuidString)")
        let nonExistentFile = tempDir.appendingPathComponent("workflow_nonexistent_\(UUID().uuidString).txt")

        try "Hello Empirical Challenger".write(to: validFile, atomically: true, encoding: .utf8)
        try Data(repeating: 0xFF, count: 2048).write(to: oversizedFile)
        try FileManager.default.createDirectory(at: subDirectory, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: validFile)
            try? FileManager.default.removeItem(at: oversizedFile)
            try? FileManager.default.removeItem(at: subDirectory)
        }

        let validResult = await Base64FileWorkflow.readSelection(from: validFile, maxBytes: 1024)
        guard case .success(let selection) = validResult else {
            Issue.record("Expected successful file read")
            return
        }
        #expect(selection.fileName == validFile.lastPathComponent)
        #expect(selection.data == Data("Hello Empirical Challenger".utf8))

        let oversizedResult = await Base64FileWorkflow.readSelection(from: oversizedFile, maxBytes: 1024)
        #expect(oversizedResult == .failure(.tooLarge(fileName: oversizedFile.lastPathComponent, maxBytes: 1024)))

        let dirResult = await Base64FileWorkflow.readSelection(from: subDirectory, maxBytes: 1024)
        #expect(dirResult == .failure(.notRegularFile))

        let nonExistentResult = await Base64FileWorkflow.readSelection(from: nonExistentFile, maxBytes: 1024)
        #expect(nonExistentResult == .failure(.readFailed))
    }

    private static func selection(
        fileName: String = "source.bin",
        data: Data = Data("hello".utf8),
        mimeType: String = "application/octet-stream"
    ) -> Base64FileSelection {
        Base64FileSelection(
            id: UUID(uuidString: "C69F65D1-7BD9-4F54-B031-0956DA8F07D1")!,
            fileName: fileName,
            data: data,
            mimeType: mimeType
        )
    }
}

@MainActor
private final class FakeBase64FileWorkflowProcessor: @unchecked Sendable {
    var readSelectionResult: Result<Base64FileSelection, Base64FileWorkflowFailure> = .success(
        Base64FileSelection(fileName: "source.bin", data: Data("hello".utf8), mimeType: "application/octet-stream")
    )
    var readSelectionHandler: ((URL, Int) async -> Result<Base64FileSelection, Base64FileWorkflowFailure>)?
    var outputPreviewHandler: ((Base64FileSelection, Base64Conversion.FileOutputMode) async -> Base64Conversion.EncodedFileOutputPreview)?
    var fullOutputText = "full-output"
    var fullOutputHandler: ((Base64FileSelection, Base64Conversion.FileOutputMode) async -> String)?
    var serializeUTF8Handler: ((String) async -> Data)?
    var decodeResult: Result<Base64Conversion.FilePayload, Base64FileWorkflowFailure>?
    var decodeHandler: ((String) async -> Result<Base64Conversion.FilePayload, Base64FileWorkflowFailure>)?
    var decodedPayloadHandler: ((Base64FileSelection) async -> Base64Conversion.FilePayload)?
    var readEncodedTextResult: Result<Base64FileEncodedTextInput, Base64FileWorkflowFailure> = .failure(.readFailed)
    var readEncodedTextHandler: ((URL, Int) async -> Result<Base64FileEncodedTextInput, Base64FileWorkflowFailure>)?
    var writeTextResult: Result<Void, Base64FileWorkflowFailure> = .success(())
    var writeTextHandler: ((String, URL) async -> Result<Void, Base64FileWorkflowFailure>)?
    var writeDataResult: Result<Void, Base64FileWorkflowFailure> = .success(())
    var writeDataHandler: ((Data, URL) async -> Result<Void, Base64FileWorkflowFailure>)?
    private(set) var previewRequests: [(selection: Base64FileSelection, mode: Base64Conversion.FileOutputMode)] = []
    private(set) var readSelectionRequests: [(url: URL, maxBytes: Int)] = []
    private(set) var decodeInputs: [String] = []
    private(set) var directDecodeSelections: [Base64FileSelection] = []
    private(set) var encodedTextReads: [(url: URL, maxBytes: Int)] = []
    private(set) var textWrites: [(text: String, url: URL)] = []
    private(set) var dataWrites: [(data: Data, url: URL)] = []

    var processing: Base64FileWorkflowProcessing {
        Base64FileWorkflowProcessing(
            readSelection: { [weak self] url, maxBytes in
                guard let self else { return .failure(.readFailed) }
                return await self.readSelection(from: url, maxBytes: maxBytes)
            },
            outputPreview: { [weak self] selection, mode in
                guard let self else {
                    return Base64Conversion.encodedOutputPreview(for: selection.data, mimeType: selection.mimeType, mode: mode)
                }
                return await self.outputPreview(for: selection, mode: mode)
            },
            fullOutput: { [weak self] selection, mode in
                guard let self else { return "" }
                return await self.fullOutput(for: selection, mode: mode)
            },
            serializeUTF8: { [weak self] text in
                guard let self else { return Data(text.utf8) }
                return await self.serializeUTF8(text)
            },
            decodePayload: { [weak self] input in
                guard let self else { return .failure(.invalidPayload) }
                return await self.decodePayload(input)
            },
            decodedPayload: { [weak self] selection in
                guard let self else { return await Base64FileWorkflow.decodedPayload(for: selection) }
                return await self.decodedPayload(for: selection)
            },
            readEncodedText: { [weak self] url, maxBytes in
                guard let self else { return .failure(.readFailed) }
                return await self.readEncodedText(from: url, maxBytes: maxBytes)
            },
            previewImage: { [weak self] payload in
                guard let self else { return nil }
                return await self.previewImage(for: payload)
            },
            writeData: { [weak self] data, url in
                guard let self else { return .failure(.saveFailed) }
                return await self.write(data, to: url)
            },
            writeText: { [weak self] text, url in
                guard let self else { return .failure(.saveFailed) }
                return await self.write(text, to: url)
            }
        )
    }

    func readSelection(
        from url: URL,
        maxBytes: Int
    ) async -> Result<Base64FileSelection, Base64FileWorkflowFailure> {
        readSelectionRequests.append((url, maxBytes))
        if let readSelectionHandler {
            return await readSelectionHandler(url, maxBytes)
        }
        return readSelectionResult
    }

    func outputPreview(
        for selection: Base64FileSelection,
        mode: Base64Conversion.FileOutputMode
    ) async -> Base64Conversion.EncodedFileOutputPreview {
        previewRequests.append((selection, mode))
        if let outputPreviewHandler {
            return await outputPreviewHandler(selection, mode)
        }
        return Base64Conversion.encodedOutputPreview(
            for: selection.data,
            mimeType: selection.mimeType,
            mode: mode
        )
    }

    func fullOutput(
        for selection: Base64FileSelection,
        mode: Base64Conversion.FileOutputMode
    ) async -> String {
        if let fullOutputHandler {
            return await fullOutputHandler(selection, mode)
        }
        return fullOutputText
    }

    func serializeUTF8(_ text: String) async -> Data {
        if let serializeUTF8Handler {
            return await serializeUTF8Handler(text)
        }
        return Data(text.utf8)
    }

    func decodePayload(_ input: String) async -> Result<Base64Conversion.FilePayload, Base64FileWorkflowFailure> {
        decodeInputs.append(input)
        if let decodeHandler {
            return await decodeHandler(input)
        }
        if let decodeResult {
            return decodeResult
        }
        return await Base64FileWorkflow.decodePayload(input)
    }

    func decodedPayload(for selection: Base64FileSelection) async -> Base64Conversion.FilePayload {
        directDecodeSelections.append(selection)
        if let decodedPayloadHandler {
            return await decodedPayloadHandler(selection)
        }
        return await Base64FileWorkflow.decodedPayload(for: selection)
    }

    func readEncodedText(
        from url: URL,
        maxBytes: Int
    ) async -> Result<Base64FileEncodedTextInput, Base64FileWorkflowFailure> {
        encodedTextReads.append((url, maxBytes))
        if let readEncodedTextHandler {
            return await readEncodedTextHandler(url, maxBytes)
        }
        return readEncodedTextResult
    }

    func previewImage(for _: Base64Conversion.FilePayload) async -> Base64FileImagePreview? {
        nil
    }

    func write(_ data: Data, to url: URL) async -> Result<Void, Base64FileWorkflowFailure> {
        if let writeDataHandler {
            let result = await writeDataHandler(data, url)
            if case .success = result {
                dataWrites.append((data, url))
            }
            return result
        }
        if case .success = writeDataResult {
            dataWrites.append((data, url))
        }
        return writeDataResult
    }

    func write(_ text: String, to url: URL) async -> Result<Void, Base64FileWorkflowFailure> {
        if let writeTextHandler {
            let result = await writeTextHandler(text, url)
            if case .success = result {
                textWrites.append((text, url))
            }
            return result
        }
        if case .success = writeTextResult {
            textWrites.append((text, url))
        }
        return writeTextResult
    }
}

@MainActor
private final class FakeBase64FileDialog: @unchecked Sendable {
    var encodedURL: URL?
    var encodedURLHandler: ((String) async -> URL?)?
    var decodedURL: URL?
    private(set) var encodedSaveNames: [String] = []
    private(set) var decodedSaveNames: [String] = []

    func selectEncodedOutputURL(defaultFilename: String) async -> URL? {
        encodedSaveNames.append(defaultFilename)
        if let encodedURLHandler {
            return await encodedURLHandler(defaultFilename)
        }
        return encodedURL
    }

    func selectDecodedOutputURL(defaultFilename: String, fileExtension _: String) async -> URL? {
        decodedSaveNames.append(defaultFilename)
        return decodedURL
    }
}

@MainActor
private final class FakeBase64Pasteboard: @unchecked Sendable {
    var shouldSucceed = true
    private(set) var payloads: [Data] = []

    var strings: [String] {
        payloads.map { String(decoding: $0, as: UTF8.self) }
    }

    func writeUTF8(_ data: Data) -> Bool {
        guard shouldSucceed else { return false }
        payloads.append(data)
        return true
    }
}

extension Base64FileWorkflowClient {
    fileprivate init(dialog: FakeBase64FileDialog? = nil, pasteboard: FakeBase64Pasteboard? = nil) {
        self.init(
            selectEncodedOutputURL: { await dialog?.selectEncodedOutputURL(defaultFilename: $0) },
            selectDecodedOutputURL: { await dialog?.selectDecodedOutputURL(defaultFilename: $0, fileExtension: $1) },
            pasteboard: Base64FileWorkflowClient.PasteboardWriter(
                write: { data in
                    MainActor.assumeIsolated {
                        pasteboard?.writeUTF8(data) ?? true
                    }
                }
            )
        )
    }
}

fileprivate extension Base64FileWorkflowSession {
    @discardableResult
    func readSelectedFile(
        from url: URL,
        maxBytes: Int = Base64FileWorkflowSession.maxFileBytes,
        processor: FakeBase64FileWorkflowProcessor
    ) -> Task<Void, Never>? {
        readSelectedFile(from: url, maxBytes: maxBytes, processor: processor.processing)
    }

    @discardableResult
    func changeOutputMode(
        to newMode: Base64Conversion.FileOutputMode,
        processor: FakeBase64FileWorkflowProcessor
    ) -> Task<Void, Never>? {
        changeOutputMode(to: newMode, processor: processor.processing)
    }

    @discardableResult
    func refreshOutputPreview(
        processor: FakeBase64FileWorkflowProcessor
    ) -> Task<Void, Never>? {
        refreshOutputPreview(processor: processor.processing)
    }

    @discardableResult
    func selectSourceFile(
        filePanel: FileInputPanelClient,
        maxBytes: Int = Base64FileWorkflowSession.maxFileBytes,
        processor: FakeBase64FileWorkflowProcessor
    ) -> Task<Void, Never> {
        selectSourceFile(filePanel: filePanel, maxBytes: maxBytes, processor: processor.processing)
    }

    @discardableResult
    func copyFullOutput(
        client: Base64FileWorkflowClient = Base64FileWorkflowClient(),
        processor: FakeBase64FileWorkflowProcessor,
        onSuccess: @escaping @MainActor () -> Void = {}
    ) -> Task<Void, Never>? {
        copyFullOutput(client: client, processor: processor.processing, onSuccess: onSuccess)
    }

    @discardableResult
    func saveEncodedOutput(
        client: Base64FileWorkflowClient = Base64FileWorkflowClient(),
        processor: FakeBase64FileWorkflowProcessor,
        onSuccess: @escaping @MainActor () -> Void = {}
    ) -> Task<Void, Never>? {
        saveEncodedOutput(client: client, processor: processor.processing, onSuccess: onSuccess)
    }

    @discardableResult
    func decodeReverseInput(
        processor: FakeBase64FileWorkflowProcessor
    ) -> Task<Void, Never>? {
        decodeReverseInput(processor: processor.processing)
    }

    @discardableResult
    func sendCurrentOutputToDecodeResult(
        processor: FakeBase64FileWorkflowProcessor
    ) -> Task<Void, Never>? {
        sendCurrentOutputToDecodeResult(processor: processor.processing)
    }

    @discardableResult
    func importEncodedTextFile(
        filePanel: FileInputPanelClient,
        processor: FakeBase64FileWorkflowProcessor
    ) -> Task<Void, Never> {
        importEncodedTextFile(filePanel: filePanel, processor: processor.processing)
    }

    @discardableResult
    func importEncodedTextFile(
        from url: URL,
        processor: FakeBase64FileWorkflowProcessor
    ) -> Task<Void, Never> {
        importEncodedTextFile(from: url, processor: processor.processing)
    }

    @discardableResult
    func saveDecodedPayload(
        client: Base64FileWorkflowClient = Base64FileWorkflowClient(),
        processor: FakeBase64FileWorkflowProcessor,
        onSuccess: @escaping @MainActor () -> Void = {}
    ) -> Task<Void, Never>? {
        saveDecodedPayload(client: client, processor: processor.processing, onSuccess: onSuccess)
    }
}

@MainActor
private final class SuspendedTestValue<Value: Sendable> {
    private var valueContinuation: CheckedContinuation<Value, Never>?
    private var requestContinuation: CheckedContinuation<Void, Never>?

    func wait() async -> Value {
        await withCheckedContinuation { continuation in
            valueContinuation = continuation
            requestContinuation?.resume()
            requestContinuation = nil
        }
    }

    func waitForRequest() async {
        if valueContinuation != nil {
            return
        }

        await withCheckedContinuation { continuation in
            requestContinuation = continuation
        }
    }

    func resume(_ value: Value) {
        valueContinuation?.resume(returning: value)
        valueContinuation = nil
    }
}
