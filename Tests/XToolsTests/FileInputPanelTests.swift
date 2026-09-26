import AppKit
import Foundation
@testable import XTools
import Testing
import UniformTypeIdentifiers

@MainActor
struct FileInputPanelTests {
    @Test func coordinatorCreatesBackendLazilyAndReusesItAcrossConfiguredRequests() async throws {
        let backend = FakeFileInputPanelBackend()
        var constructionCount = 0
        let coordinator = FileInputPanelCoordinator {
            constructionCount += 1
            return backend
        }
        let window = makeWindow()
        coordinator.attach(to: window)

        #expect(constructionCount == 0)

        let sourceRequest = FileInputPanelRequest(
            allowedContentTypes: [.data],
            prompt: "选择源文件",
            title: "源文件",
            message: "选择一个普通文件"
        )
        let sourceTask = Task { @MainActor in
            try await coordinator.selectFile(sourceRequest)
        }
        guard await backend.waitForPresentation(count: 1) else {
            sourceTask.cancel()
            return
        }
        let sourceURL = URL(fileURLWithPath: "/tmp/source.bin")
        backend.completeLatest(with: .selected(sourceURL))

        #expect(try await sourceTask.value == sourceURL)
        #expect(constructionCount == 1)

        let encodedTextRequest = FileInputPanelRequest(
            allowedContentTypes: [.plainText],
            prompt: nil,
            title: nil,
            message: nil
        )
        let encodedTextTask = Task { @MainActor in
            try await coordinator.selectFile(encodedTextRequest)
        }
        guard await backend.waitForPresentation(count: 2) else {
            encodedTextTask.cancel()
            return
        }
        backend.completeLatest(with: .cancelled)

        #expect(try await encodedTextTask.value == nil)
        #expect(constructionCount == 1)
        #expect(backend.requests.count == 2)
        #expect(backend.requests[0].allowedContentTypes == [.data])
        #expect(backend.requests[0].prompt == "选择源文件")
        #expect(backend.requests[0].title == "源文件")
        #expect(backend.requests[0].message == "选择一个普通文件")
        #expect(backend.requests[1].allowedContentTypes == [.plainText])
        #expect(backend.requests[1].prompt == nil)
        #expect(backend.requests[1].title == nil)
        #expect(backend.requests[1].message == nil)
    }

    @Test func missingWindowFailsWithoutConstructingBackend() async {
        var constructionCount = 0
        let coordinator = FileInputPanelCoordinator {
            constructionCount += 1
            return FakeFileInputPanelBackend()
        }

        do {
            _ = try await coordinator.selectFile(FileInputPanelRequest(allowedContentTypes: [.data]))
            Issue.record("Expected a missing owning window to reject the request")
        } catch let failure as FileInputPanelFailure {
            #expect(failure == .windowUnavailable)
            #expect(failure.errorDescription == "暂时无法打开文件选择器。")
        } catch {
            Issue.record("Unexpected failure: \(error)")
        }

        #expect(constructionCount == 0)
    }

    @Test func concurrentRequestFailsImmediatelyAndIsNeverQueued() async throws {
        let backend = FakeFileInputPanelBackend()
        let coordinator = FileInputPanelCoordinator { backend }
        let window = makeWindow()
        coordinator.attach(to: window)

        let firstTask = Task { @MainActor in
            try await coordinator.selectFile(FileInputPanelRequest(allowedContentTypes: [.data]))
        }
        guard await backend.waitForPresentation(count: 1) else {
            firstTask.cancel()
            return
        }

        do {
            _ = try await coordinator.selectFile(FileInputPanelRequest(allowedContentTypes: [.plainText]))
            Issue.record("Expected a concurrent request to be rejected")
        } catch let failure as FileInputPanelFailure {
            #expect(failure == .requestInProgress)
            #expect(failure.errorDescription == "已有文件选择器正在打开。")
        } catch {
            Issue.record("Unexpected failure: \(error)")
        }

        #expect(backend.presentationCount == 1)
        backend.completeLatest(with: .cancelled)
        #expect(try await firstTask.value == nil)
        #expect(backend.presentationCount == 1)
    }

    @Test func taskCancellationCancelsActiveSheetAndIgnoresLateCompletion() async {
        let backend = FakeFileInputPanelBackend()
        let coordinator = FileInputPanelCoordinator { backend }
        let window = makeWindow()
        coordinator.attach(to: window)

        let task = Task { @MainActor in
            try await coordinator.selectFile(FileInputPanelRequest(allowedContentTypes: [.data]))
        }
        guard await backend.waitForPresentation(count: 1) else {
            task.cancel()
            return
        }
        task.cancel()

        do {
            _ = try await task.value
            Issue.record("Expected the cancelled selection task to throw CancellationError")
        } catch is CancellationError {
            // Expected cancellation is silent at the workflow boundary.
        } catch {
            Issue.record("Unexpected failure: \(error)")
        }

        #expect(backend.cancelCount == 1)
        backend.completeLatest(with: .selected(URL(fileURLWithPath: "/tmp/late.bin")))

        let nextTask = Task { @MainActor in
            try await coordinator.selectFile(FileInputPanelRequest(allowedContentTypes: [.plainText]))
        }
        guard await backend.waitForPresentation(count: 2) else {
            nextTask.cancel()
            return
        }
        backend.completeLatest(with: .cancelled)
        #expect((try? await nextTask.value) == nil)
    }

    @Test func confirmedResponseWithoutURLUsesStableFailure() async {
        let backend = FakeFileInputPanelBackend()
        let coordinator = FileInputPanelCoordinator { backend }
        let window = makeWindow()
        coordinator.attach(to: window)

        let task = Task { @MainActor in
            try await coordinator.selectFile(FileInputPanelRequest(allowedContentTypes: [.data]))
        }
        guard await backend.waitForPresentation(count: 1) else {
            task.cancel()
            return
        }
        backend.completeLatest(with: .selected(nil))

        do {
            _ = try await task.value
            Issue.record("Expected an empty confirmed response to fail")
        } catch let failure as FileInputPanelFailure {
            #expect(failure == .invalidSelection)
            #expect(failure.errorDescription == "没有取得可用的文件。")
        } catch {
            Issue.record("Unexpected failure: \(error)")
        }
    }

    @Test func detachingOwningWindowCancelsOnlyItsActiveRequest() async {
        let backend = FakeFileInputPanelBackend()
        let coordinator = FileInputPanelCoordinator { backend }
        let firstWindow = makeWindow()
        let secondWindow = makeWindow()
        coordinator.attach(to: firstWindow)

        let firstTask = Task { @MainActor in
            try await coordinator.selectFile(FileInputPanelRequest(allowedContentTypes: [.data]))
        }
        guard await backend.waitForPresentation(count: 1) else {
            firstTask.cancel()
            return
        }
        coordinator.attach(to: secondWindow)

        do {
            _ = try await firstTask.value
            Issue.record("Expected rebinding to cancel the old window request")
        } catch is CancellationError {
            // Expected.
        } catch {
            Issue.record("Unexpected failure: \(error)")
        }

        #expect(backend.cancelCount == 1)
        coordinator.detach(from: firstWindow)

        let secondTask = Task { @MainActor in
            try await coordinator.selectFile(FileInputPanelRequest(allowedContentTypes: [.plainText]))
        }
        guard await backend.waitForPresentation(count: 2) else {
            secondTask.cancel()
            return
        }
        backend.completeLatest(with: .cancelled)
        #expect((try? await secondTask.value) == nil)
    }

    @Test func singleFileDropResolverRejectsWholeMultiFileBatch() {
        let first = URL(fileURLWithPath: "/tmp/first.bin")
        let second = URL(fileURLWithPath: "/tmp/second.bin")

        #expect(SingleFileDropResolver.resolve([]) == .unhandled)
        #expect(SingleFileDropResolver.resolve([first]) == .accepted(first))
        #expect(SingleFileDropResolver.resolve([first, second]) == .rejectedMultipleFiles)
        #expect(SingleFileDropResolver.multipleFilesDiagnostic == "一次只能拖入一个文件。")
    }

    @Test func platformFailureDiagnosticNeverExposesSystemPayload() {
        let sensitivePath = "/Users/example/private/source.bin"
        let systemError = NSError(
            domain: NSCocoaErrorDomain,
            code: NSFileReadNoPermissionError,
            userInfo: [NSLocalizedDescriptionKey: "Permission denied: \(sensitivePath)"]
        )

        let message = FileInputPanelFailure.diagnosticMessage(for: systemError)

        #expect(message == "暂时无法打开文件选择器。")
        #expect(!message.contains(sensitivePath))
    }

    @Test func sharedBackendAndRootKeepWindowScopedReusablePanelContract() throws {
        let panelSource = try readSource("Sources/XTools/Shared/FileInputPanel.swift")
        let rootSource = try readSource("Sources/XTools/AppShell/RootView.swift")

        contains(panelSource, "private let panel: NSOpenPanel", "The AppKit backend must retain one open panel")
        occurrenceCount(panelSource, "NSOpenPanel()", 1, "The shared file input infrastructure must have one lazy production construction site")
        contains(panelSource, "panel.canChooseFiles = request.canChooseFiles", "Every request must drive file selection from its request")
        contains(panelSource, "panel.canChooseDirectories = request.canChooseDirectories", "Every request must drive directory selection from its request")
        contains(panelSource, "panel.allowsMultipleSelection = false", "Every request must restore single selection")
        contains(panelSource, "panel.allowedContentTypes = request.allowedContentTypes", "Every request must replace content-type filtering")
        contains(panelSource, "panel.allowsOtherFileTypes = false", "Every request must reject types outside the request")
        contains(panelSource, "panel.prompt = request.prompt", "Every request must reset prompt text")
        contains(panelSource, "panel.title = request.title ?? \"\"", "Every request must reset title text")
        contains(panelSource, "panel.message = request.message", "Every request must reset message text")
        contains(panelSource, "panel.delegate = nil", "Every request must clear stale delegates")
        contains(panelSource, "panel.accessoryView = nil", "Every request must clear stale accessory views")
        contains(panelSource, "panel.treatsFilePackagesAsDirectories = false", "Every request must keep packages out of directory navigation")
        contains(panelSource, "panel.resolvesAliases = true", "Every request must preserve ordinary alias resolution")
        contains(panelSource, "panel.beginSheetModal(for: window)", "File input must stay attached to its owning window")
        doesNotContain(panelSource, "runModal()", "File input must not start a synchronous modal event loop")
        doesNotContain(panelSource, "NSApp.keyWindow", "The coordinator must not guess its owner from global key-window state")
        doesNotContain(panelSource, "NSApp.mainWindow", "The coordinator must not guess its owner from global main-window state")

        contains(rootSource, "@StateObject private var fileInputPanelCoordinator = FileInputPanelCoordinator()", "RootView must own the panel for its window lifetime")
        contains(rootSource, ".background(FileInputPanelWindowBinder(coordinator: fileInputPanelCoordinator))", "RootView must bind the coordinator to its actual window")
        contains(rootSource, ".environment(\\.fileInputPanelClient, fileInputPanelCoordinator.client)", "RootView must inject one client into every tool page")
    }

    private func makeWindow() -> NSWindow {
        NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
    }
}

@MainActor
private final class FakeFileInputPanelBackend: FileInputPanelBackend {
    private var completions: [@MainActor (FileInputPanelBackendResult) -> Void] = []
    private(set) var requests: [FileInputPanelRequest] = []
    private(set) var presentationCount = 0
    private(set) var cancelCount = 0

    func configure(for request: FileInputPanelRequest) {
        requests.append(request)
    }

    func beginSheetModal(
        for _: NSWindow,
        completion: @escaping @MainActor (FileInputPanelBackendResult) -> Void
    ) {
        presentationCount += 1
        completions.append(completion)
    }

    func cancel() {
        cancelCount += 1
    }

    func completeLatest(with result: FileInputPanelBackendResult) {
        guard let completion = completions.popLast() else {
            Issue.record("No pending file panel completion")
            return
        }
        completion(result)
    }

    func waitForPresentation(count: Int, timeout: Duration = .seconds(20)) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while presentationCount < count, ContinuousClock.now < deadline {
            await Task.yield()
        }
        guard presentationCount >= count else {
            Issue.record("Timed out waiting for file panel presentation \(count)")
            return false
        }
        return true
    }
}
