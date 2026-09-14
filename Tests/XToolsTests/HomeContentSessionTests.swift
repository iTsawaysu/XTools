import Foundation
import Testing
@testable import XTools
@testable import XToolsCore

@Suite(.serialized)
@MainActor
struct HomeContentSessionTests {
    @Test func automaticDetectionSelectsOnlySupportedActions() async throws {
        let session = HomeContentSession()
        #expect(session.selectedAction == nil)

        session.input = #"{"value":1}"#
        try await Self.waitUntil { !session.isDetecting }
        #expect(session.detection == .json)
        #expect(session.selectedAction == .jsonFormat)
        #expect(session.canRun)

        session.input = "ordinary text"
        try await Self.waitUntil { !session.isDetecting }
        #expect(session.detection == nil)
        #expect(session.selectedAction == nil)
        #expect(!session.canRun)
    }

    @Test func unsupportedDetectionHasNoAutomaticDefault() async throws {
        let session = HomeContentSession(detect: { _ in .xml })
        session.input = "<value>text</value>"
        try await Self.waitUntil { !session.isDetecting }

        #expect(session.detection == .xml)
        #expect(session.selectedAction == nil)
        #expect(!session.canRun)
        session.run()
        #expect(session.result == nil)
        #expect(!session.isProcessing)
    }

    @Test func manualSelectionWinsLateDetectionAndStaysStickyAcrossEdits() async throws {
        let session = HomeContentSession(detect: { input in
            try? await Task.sleep(for: .milliseconds(80))
            return input.hasPrefix("{") ? .json : .urlEncoded
        })

        session.input = #"{"value":1}"#
        session.selectedAction = .base64Decode
        try await Self.waitUntil { !session.isDetecting }
        #expect(session.detection == .json)
        #expect(session.selectedAction == .base64Decode)
        #expect(!session.usesAutomaticActionSelection)

        session.input = "hello%20world%21"
        try await Self.waitUntil { !session.isDetecting }
        #expect(session.detection == .urlEncoded)
        #expect(session.selectedAction == .base64Decode)

        session.useAutomaticActionSelection()
        #expect(session.usesAutomaticActionSelection)
        #expect(session.selectedAction == .urlDecode)
    }

    @Test func automaticModeCannotRunBeforeDetectionFinishes() async throws {
        let session = HomeContentSession(detect: { _ in
            try? await Task.sleep(for: .milliseconds(80))
            return .json
        })
        session.input = #"{"value":1}"#

        #expect(session.isDetecting)
        #expect(session.selectedAction == nil)
        #expect(!session.canRun)
        session.run()
        #expect(session.result == nil)
        #expect(!session.isProcessing)

        try await Self.waitUntil { !session.isDetecting }
        #expect(session.selectedAction == .jsonFormat)
        #expect(session.canRun)
    }

    @Test func editsActionChangesAndCollapseUpdateOnlyCurrentPresentation() async throws {
        let session = HomeContentSession(process: { action, input in
            .success(HomeContentResult(text: "\(action.rawValue):\(input)"))
        })
        session.selectedAction = .urlDecode
        session.input = "one"
        try await Self.waitUntil { !session.isDetecting }
        session.run()
        try await Self.waitUntil { session.result != nil }

        session.toggleOutputCollapsed()
        #expect(session.isOutputCollapsed)
        #expect(session.result?.text == "urlDecode:one")

        session.selectedAction = .base64Decode
        #expect(session.result == nil)
        #expect(session.failure == nil)
        #expect(!session.isOutputCollapsed)

        session.run()
        try await Self.waitUntil { session.result != nil }
        session.input = "two"
        #expect(session.result == nil)
        #expect(session.failure == nil)
        #expect(!session.isOutputCollapsed)
    }

    @Test func staleExecutionCannotOverwriteNewerResult() async throws {
        let slowOperation = SuspendedHomeOperation<HomeContentResult>()
        let session = HomeContentSession(process: { _, input in
            if input == "slow" {
                return .success(await slowOperation.waitForValue())
            }
            return .success(HomeContentResult(text: "result:\(input)"))
        })

        session.selectedAction = .urlDecode
        session.input = "slow"
        try await Self.waitUntil { !session.isDetecting }
        session.run()
        await slowOperation.waitUntilStarted()

        session.input = "latest"
        try await Self.waitUntil { !session.isDetecting }
        session.run()
        try await Self.waitUntil { session.result?.text == "result:latest" }

        await slowOperation.resume(with: HomeContentResult(text: "result:slow"))
        await Task.yield()
        #expect(session.result?.text == "result:latest")
        #expect(!session.isProcessing)
    }

    @Test func staleDetectionCannotChooseAnActionForNewInput() async throws {
        let slowDetection = SuspendedHomeOperation<SmartPasteDetector.Kind?>()
        let session = HomeContentSession(detect: { input in
            if input == "slow" {
                return await slowDetection.waitForValue()
            }
            return .urlEncoded
        })

        session.input = "slow"
        await slowDetection.waitUntilStarted()
        session.input = "latest"
        try await Self.waitUntil { session.detection == .urlEncoded && !session.isDetecting }

        await slowDetection.resume(with: .json)
        await Task.yield()
        #expect(session.detection == .urlEncoded)
        #expect(session.selectedAction == .urlDecode)
    }

    @Test func clearInvalidatesSuspendedWorkAndRestoresAutomaticEmptyState() async throws {
        let pendingOperation = SuspendedHomeOperation<HomeContentResult>()
        let session = HomeContentSession(process: { _, _ in
            .success(await pendingOperation.waitForValue())
        })
        session.selectedAction = .urlDecode
        session.input = "pending"
        try await Self.waitUntil { !session.isDetecting }
        session.run()
        await pendingOperation.waitUntilStarted()

        session.clear()
        await pendingOperation.resume(with: HomeContentResult(text: "late"))
        await Task.yield()

        #expect(session.input.isEmpty)
        #expect(session.selectedAction == nil)
        #expect(session.detection == nil)
        #expect(session.result == nil)
        #expect(session.failure == nil)
        #expect(!session.isDetecting)
        #expect(!session.isProcessing)
        #expect(session.usesAutomaticActionSelection)
        #expect(!session.isOutputCollapsed)
        #expect(!session.canRun)
    }

    @Test func clearAfterJSONResultPreservesAutomaticSelectionForLaterBase64() async throws {
        let session = HomeContentSession()
        session.input = #"{"value":1}"#
        try await Self.waitUntil { !session.isDetecting }
        #expect(session.selectedAction == .jsonFormat)

        session.run()
        try await Self.waitUntil { session.result != nil }
        session.clear()
        #expect(session.usesAutomaticActionSelection)
        #expect(session.selectedAction == nil)

        session.input = "ordinary text"
        try await Self.waitUntil { !session.isDetecting }
        #expect(session.usesAutomaticActionSelection)
        #expect(session.selectedAction == nil)

        session.input = "5L2g5aW9IFhUb29scw=="
        try await Self.waitUntil { !session.isDetecting }
        #expect(session.detection == .base64)
        #expect(session.usesAutomaticActionSelection)
        #expect(session.selectedAction == .base64Decode)
        #expect(session.canRun)
    }

    @Test func emptyOversizedAndPasteboardFailureAreNonDestructive() async throws {
        let session = HomeContentSession(process: { _, input in
            .success(HomeContentResult(text: input))
        })
        session.selectedAction = .urlDecode
        session.input = "current"
        try await Self.waitUntil { !session.isDetecting }
        session.run()
        try await Self.waitUntil { session.result != nil }
        let currentResult = session.result

        session.reportPasteboardUnavailable()
        #expect(session.input == "current")
        #expect(session.result == currentResult)
        #expect(session.failure == "剪贴板中没有可粘贴的文本。")

        session.input = " \n "
        session.run()
        #expect(session.failure == nil)
        #expect(!session.canRun)

        session.input = String(
            repeating: "a",
            count: HomeContentProcessor.maximumCharacterCount + 1
        )
        #expect(session.input.count == HomeContentProcessor.maximumCharacterCount + 1)
        #expect(session.failure?.contains("32768") == true)
        #expect(!session.isDetecting)
        #expect(!session.isProcessing)
        #expect(!session.canRun)
    }

    @Test func repositoryRetainsSessionOnlyForItsOwnLifetime() {
        let suiteName = "HomeContentSessionTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let firstRepository = ToolWorkspaceRepository(defaults: defaults)
        let first = firstRepository.model(for: HomeContentSession.key)
        first.selectedAction = .urlDecode
        first.input = "window draft"

        #expect(firstRepository.model(for: HomeContentSession.key) === first)

        let newRepository = ToolWorkspaceRepository(defaults: defaults)
        let fresh = newRepository.model(for: HomeContentSession.key)
        #expect(fresh !== first)
        #expect(fresh.input.isEmpty)
        #expect(fresh.selectedAction == nil)
        #expect(fresh.result == nil)
        #expect(fresh.usesAutomaticActionSelection)
    }

    private static func waitUntil(
        timeout: Duration = .seconds(5),
        _ condition: @escaping @MainActor () -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while !condition() {
            if clock.now >= deadline {
                throw HomeContentSessionTestTimeout()
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}

private struct HomeContentSessionTestTimeout: Error, CustomStringConvertible {
    var description: String {
        "Timed out waiting for HomeContentSession state"
    }
}

private actor SuspendedHomeOperation<Value: Sendable> {
    private var hasStarted = false
    private var startedWaiters: [CheckedContinuation<Void, Never>] = []
    private var valueWaiter: CheckedContinuation<Value, Never>?

    func waitForValue() async -> Value {
        hasStarted = true
        let waiters = startedWaiters
        startedWaiters.removeAll()
        waiters.forEach { $0.resume() }
        return await withCheckedContinuation { valueWaiter = $0 }
    }

    func waitUntilStarted() async {
        guard !hasStarted else { return }
        await withCheckedContinuation { startedWaiters.append($0) }
    }

    func resume(with value: Value) {
        valueWaiter?.resume(returning: value)
        valueWaiter = nil
    }
}
