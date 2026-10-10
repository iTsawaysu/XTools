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
        backend.completeLatest(with: .selected([sourceURL]))

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
        backend.completeLatest(with: .selected([URL(fileURLWithPath: "/tmp/late.bin")]))

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
        backend.completeLatest(with: .selected([]))

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

    @Test func selectFilesReturnsWholeConfirmedBatchAndSharesTheRequestPipeline() async throws {
        let backend = FakeFileInputPanelBackend()
        let coordinator = FileInputPanelCoordinator { backend }
        let window = makeWindow()
        coordinator.attach(to: window)

        let first = URL(fileURLWithPath: "/tmp/first.png")
        let second = URL(fileURLWithPath: "/tmp/second.png")
        let task = Task { @MainActor in
            try await coordinator.selectFiles(
                FileInputPanelRequest(allowedContentTypes: [.png], allowsMultipleSelection: true)
            )
        }
        guard await backend.waitForPresentation(count: 1) else {
            task.cancel()
            return
        }
        #expect(backend.requests.last?.allowsMultipleSelection == true)
        backend.completeLatest(with: .selected([first, second]))

        #expect(try await task.value == [first, second])

        // 单选请求在多选结果数组上取 first，语义与既有 selectFile 一致。
        let singleTask = Task { @MainActor in
            try await coordinator.selectFile(
                FileInputPanelRequest(allowedContentTypes: [.png], allowsMultipleSelection: true)
            )
        }
        guard await backend.waitForPresentation(count: 2) else {
            singleTask.cancel()
            return
        }
        backend.completeLatest(with: .selected([second, first]))
        #expect(try await singleTask.value == second)

        // 多选请求与单选共用互斥管线：活动请求未完成时立即拒绝。
        let pendingTask = Task { @MainActor in
            try await coordinator.selectFiles(FileInputPanelRequest(allowedContentTypes: [.png]))
        }
        guard await backend.waitForPresentation(count: 3) else {
            pendingTask.cancel()
            return
        }
        do {
            _ = try await coordinator.selectFiles(FileInputPanelRequest(allowedContentTypes: [.png]))
            Issue.record("Expected a concurrent multi-select request to be rejected")
        } catch let failure as FileInputPanelFailure {
            #expect(failure == .requestInProgress)
        } catch {
            Issue.record("Unexpected failure: \(error)")
        }
        backend.completeLatest(with: .cancelled)
        #expect(try await pendingTask.value == nil)
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

// MARK: - Challenger M2 并入：PanelRequestBox（Shared/PanelRequestBox.swift 的唯一测试覆盖）

@MainActor
struct PanelRequestBoxTests {
    @Test func panelRequestBoxRapidRequestsPermitOnlySingleInFlightTask() async {
        var box = PanelRequestBox()
        let callCounter = TestLockedCounter(initialValue: 0)
        let signal = TestAsyncSignal()

        // Start first in-flight request
        let task1 = box.request(
            {
                callCounter.increment()
                await signal.wait()
                return "result-1"
            },
            onSuccess: { _ in },
            onError: { _ in }
        )

        #expect(box.hasActiveRequest)
        #expect(box.task != nil)

        // Rapidly fire 50 subsequent requests while task 1 is in-flight
        var tasks: [Task<Void, Never>] = []
        for _ in 0..<50 {
            let t = box.request(
                {
                    callCounter.increment()
                    return "should-not-run"
                },
                onSuccess: { _ in },
                onError: { _ in }
            )
            tasks.append(t)
        }

        // All returned tasks must match task1
        for t in tasks {
            #expect(t == task1)
        }

        // Let task1 finish
        await signal.signal()
        await task1.value

        // Only the first action ran
        #expect(callCounter.count == 1)
        #expect(!box.hasActiveRequest)
        #expect(box.task == nil)

        // Now a new request can be started successfully
        var secondResult: String?
        let task2 = box.request(
            {
                callCounter.increment()
                return "result-2"
            },
            onSuccess: { secondResult = $0 },
            onError: { _ in }
        )
        await task2.value

        #expect(callCounter.count == 2)
        #expect(secondResult == "result-2")
        #expect(!box.hasActiveRequest)
    }

    @Test func panelRequestBoxCancellationSuppressesCallbacks() async {
        var box = PanelRequestBox()
        let signal = TestAsyncSignal()
        var successFired = false
        var errorFired = false

        let task = box.request(
            {
                await signal.wait()
                return "value"
            },
            onSuccess: { _ in successFired = true },
            onError: { _ in errorFired = true }
        )

        #expect(box.hasActiveRequest)

        // Explicitly cancel the box while request is in-flight
        box.cancel()

        #expect(!box.hasActiveRequest)
        #expect(box.task == nil)

        // Unblock action
        await signal.signal()
        await task.value

        // Neither callback should fire
        #expect(!successFired)
        #expect(!errorFired)
    }

    @Test func panelRequestBoxErrorDiagnosticsMapping() async {
        // 1. windowUnavailable
        var box1 = PanelRequestBox()
        var receivedError1: String?
        let t1 = box1.request(
            { throw FileInputPanelFailure.windowUnavailable },
            onSuccess: { _ in },
            onError: { receivedError1 = $0 }
        )
        await t1.value
        #expect(receivedError1 == "暂时无法打开文件选择器。")

        // 2. requestInProgress
        var box2 = PanelRequestBox()
        var receivedError2: String?
        let t2 = box2.request(
            { throw FileInputPanelFailure.requestInProgress },
            onSuccess: { _ in },
            onError: { receivedError2 = $0 }
        )
        await t2.value
        #expect(receivedError2 == "已有文件选择器正在打开。")

        // 3. invalidSelection
        var box3 = PanelRequestBox()
        var receivedError3: String?
        let t3 = box3.request(
            { throw FileInputPanelFailure.invalidSelection },
            onSuccess: { _ in },
            onError: { receivedError3 = $0 }
        )
        await t3.value
        #expect(receivedError3 == "没有取得可用的文件。")

        // 4. Arbitrary unknown error falls back to standard message
        struct RandomFailure: Error {}
        var box4 = PanelRequestBox()
        var receivedError4: String?
        let t4 = box4.request(
            { throw RandomFailure() },
            onSuccess: { _ in },
            onError: { receivedError4 = $0 }
        )
        await t4.value
        #expect(receivedError4 == "暂时无法打开文件选择器。")
    }

    @Test func panelRequestBoxCancellationErrorDoesNotReportError() async {
        var box = PanelRequestBox()
        var errorReported = false

        let task = box.request(
            {
                throw CancellationError()
            },
            onSuccess: { _ in },
            onError: { _ in errorReported = true }
        )
        await task.value

        #expect(!errorReported)
        #expect(!box.hasActiveRequest)
    }
}
