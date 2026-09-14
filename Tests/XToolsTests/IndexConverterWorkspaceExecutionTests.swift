@testable import XTools
import Foundation
import Testing

struct IndexConverterWorkspaceExecutionTests {
    @MainActor
    @Test func defaultExecutionBoundaryUsesTheConservativeMeasuredLimit() {
        #expect(IndexConverterToolWorkspaceModel.defaultSynchronousInputByteLimit == 4 * 1024)
        #expect(IndexConverterToolWorkspaceModel.defaultBackgroundDebounce == .milliseconds(120))
    }

    @MainActor
    @Test func shortRequestExecutesExactlyOnceAndPublishesOneCoherentResult() {
        let counter = LockedConverterCallRecorder()
        let model = makeModel(
            synchronousInputByteLimit: 64,
            convert: { input, mode in
                counter.record(input: input, mode: mode)
                return "\(mode):\(input)"
            }
        )

        model.input = "plain"

        #expect(counter.callCount == 1)
        #expect(counter.calls == [.init(input: "plain", mode: "enc")])
        #expect(model.output == "enc:plain")
        #expect(model.error == nil)
        #expect(!model.isProcessing)
    }

    @MainActor
    @Test func synchronousBoundaryUsesUTF8ByteCount() {
        let counter = LockedConverterCallRecorder()
        let model = makeModel(
            synchronousInputByteLimit: 4,
            convert: { input, mode in
                counter.record(input: input, mode: mode)
                return input
            }
        )

        model.input = "éé"

        #expect(model.input.utf8.count == 4)
        #expect(counter.callCount == 1)
        #expect(model.output == "éé")
        #expect(!model.isProcessing)
    }

    @MainActor
    @Test func inputAboveBoundaryRunsOffMainThreadAndPublishesWhenCurrent() async {
        let counter = LockedConverterCallRecorder()
        let model = makeModel(
            synchronousInputByteLimit: 4,
            backgroundDebounce: .zero,
            convert: { input, mode in
                counter.record(
                    input: input,
                    mode: mode,
                    ranOnMainThread: Thread.isMainThread
                )
                return "background:\(input)"
            }
        )

        model.input = "ééé"

        #expect(model.input.utf8.count == 6)
        #expect(model.output.isEmpty)
        #expect(model.error == nil)
        #expect(model.isProcessing)

        await waitUntil { model.output == "background:ééé" }

        #expect(counter.callCount == 1)
        #expect(counter.ranOnMainThreadValues == [false])
        #expect(!model.isProcessing)
        #expect(model.error == nil)
    }

    @MainActor
    @Test func largeRequestImmediatelyInvalidatesMismatchedOutput() {
        let model = makeModel(
            synchronousInputByteLimit: 4,
            backgroundDebounce: .seconds(30),
            convert: { input, _ in input.uppercased() }
        )

        model.input = "tiny"
        #expect(model.output == "TINY")

        model.input = "larger"

        #expect(model.output.isEmpty)
        #expect(model.error == nil)
        #expect(model.isProcessing)
    }

    @MainActor
    @Test func staleBackgroundSuccessCannotReplaceNewerInput() async {
        let gate = IndexConverterExecutionGate()
        let model = makeModel(
            synchronousInputByteLimit: 2,
            backgroundDebounce: .zero,
            convert: { _, _ in "unused" },
            backgroundExecutor: { request in
                await gate.execute(request)
            }
        )

        model.input = "old"
        let oldRequest = IndexConverterRequest(input: "old", mode: "enc")
        await gate.waitForRequest(oldRequest)

        model.input = "newer"
        let newRequest = IndexConverterRequest(input: "newer", mode: "enc")
        await gate.waitForRequest(newRequest)

        await gate.resume(oldRequest, with: .success("stale"))
        await Task.yield()

        #expect(model.output.isEmpty)
        #expect(model.error == nil)
        #expect(model.isProcessing)

        await gate.resume(newRequest, with: .success("current"))
        await waitUntil { model.output == "current" }

        #expect(model.error == nil)
        #expect(!model.isProcessing)
    }

    @MainActor
    @Test func staleBackgroundErrorCannotReplaceNewerSuccess() async {
        let gate = IndexConverterExecutionGate()
        let model = makeModel(
            synchronousInputByteLimit: 2,
            backgroundDebounce: .zero,
            convert: { _, _ in "unused" },
            backgroundExecutor: { request in
                await gate.execute(request)
            }
        )

        model.input = "old"
        let oldRequest = IndexConverterRequest(input: "old", mode: "enc")
        await gate.waitForRequest(oldRequest)

        model.input = "newer"
        let newRequest = IndexConverterRequest(input: "newer", mode: "enc")
        await gate.waitForRequest(newRequest)

        await gate.resume(oldRequest, with: .failure("旧错误"))
        await Task.yield()
        #expect(model.error == nil)

        await gate.resume(newRequest, with: .success("current"))
        await waitUntil { model.output == "current" }

        #expect(model.error == nil)
        #expect(!model.isProcessing)
    }

    @MainActor
    @Test func currentBackgroundFailurePublishesErrorFromTheSameExecution() async {
        let counter = LockedConverterCallRecorder()
        let model = makeModel(
            synchronousInputByteLimit: 2,
            backgroundDebounce: .zero,
            errorMessage: { error in
                error as? ConverterTestError == .invalid ? "当前输入无效。" : "转换失败。"
            },
            convert: { input, mode in
                counter.record(input: input, mode: mode)
                throw ConverterTestError.invalid
            }
        )

        model.input = "invalid"
        await waitUntil { model.error == "当前输入无效。" }

        #expect(counter.callCount == 1)
        #expect(model.output.isEmpty)
        #expect(!model.isProcessing)
    }

    @MainActor
    @Test func clearInvalidatesPendingWorkAndRestoresEmptyState() async {
        let gate = IndexConverterExecutionGate()
        let model = makeModel(
            synchronousInputByteLimit: 2,
            backgroundDebounce: .zero,
            convert: { _, _ in "unused" },
            backgroundExecutor: { request in
                await gate.execute(request)
            }
        )

        model.input = "pending"
        let request = IndexConverterRequest(input: "pending", mode: "enc")
        await gate.waitForRequest(request)

        model.clear()

        #expect(model.input.isEmpty)
        #expect(model.output.isEmpty)
        #expect(model.error == nil)
        #expect(!model.isProcessing)

        await gate.resume(request, with: .success("stale"))
        await Task.yield()

        #expect(model.output.isEmpty)
        #expect(model.error == nil)
        #expect(!model.isProcessing)
    }

    @MainActor
    @Test func completedOutputBackfillsWithoutReexecutingOldRequest() {
        let counter = LockedConverterCallRecorder()
        let model = makeModel(
            synchronousInputByteLimit: 64,
            convert: { input, mode in
                counter.record(input: input, mode: mode)
                switch (input, mode) {
                case ("plain", "enc"):
                    return "encoded"
                case ("encoded", "dec"):
                    return "plain"
                default:
                    return "unexpected"
                }
            }
        )

        model.input = "plain"
        #expect(model.output == "encoded")

        model.changeMode(to: "dec", backfillModeTransition: { _, _ in true })

        #expect(model.mode == "dec")
        #expect(model.input == "encoded")
        #expect(model.output == "plain")
        #expect(counter.calls == [
            .init(input: "plain", mode: "enc"),
            .init(input: "encoded", mode: "dec")
        ])
    }

    @MainActor
    @Test func failedOutputClearsInvalidInputOnModeChange() {
        let counter = LockedConverterCallRecorder()
        let model = makeModel(
            synchronousInputByteLimit: 64,
            errorMessage: { _ in "编码失败。" },
            convert: { input, mode in
                counter.record(input: input, mode: mode)
                if mode == "enc" {
                    throw ConverterTestError.invalid
                }
                return "decoded:\(input)"
            }
        )

        model.input = "invalid"
        #expect(model.error == "编码失败。")

        model.changeMode(to: "dec", backfillModeTransition: { _, _ in true })

        #expect(model.input.isEmpty)
        #expect(model.output.isEmpty)
        #expect(model.error == nil)
        #expect(counter.calls == [
            .init(input: "invalid", mode: "enc")
        ])
    }

    @MainActor
    @Test func successfulBackfillRequestsCaretPlacementAtTheNewInputEnd() {
        let model = makeModel(
            synchronousInputByteLimit: 64,
            convert: { input, mode in
                mode == "enc" ? "encoded" : "decoded"
            }
        )

        #expect(model.inputReplacementToken == 0)
        model.input = "plain"
        model.changeMode(to: "dec", backfillModeTransition: { _, _ in true })

        #expect(model.input == "encoded")
        #expect(model.inputReplacementToken == 1)

        model.input.append("!")
        #expect(model.inputReplacementToken == 0)

        model.changeMode(to: "enc", backfillModeTransition: { _, _ in true })

        #expect(model.input == "decoded")
        #expect(model.inputReplacementToken == 2)
    }

    @MainActor
    @Test func processingOutputDoesNotBackfillAndOldModeCannotPublish() async {
        let gate = IndexConverterExecutionGate()
        let model = makeModel(
            synchronousInputByteLimit: 2,
            backgroundDebounce: .zero,
            convert: { _, _ in "unused" },
            backgroundExecutor: { request in
                await gate.execute(request)
            }
        )

        model.input = "large"
        let encodingRequest = IndexConverterRequest(input: "large", mode: "enc")
        await gate.waitForRequest(encodingRequest)

        model.changeMode(to: "dec", backfillModeTransition: { _, _ in true })
        let decodingRequest = IndexConverterRequest(input: "large", mode: "dec")
        await gate.waitForRequest(decodingRequest)

        #expect(model.input == "large")
        #expect(model.output.isEmpty)
        #expect(model.isProcessing)

        await gate.resume(encodingRequest, with: .success("encoded"))
        await Task.yield()
        #expect(model.output.isEmpty)

        await gate.resume(decodingRequest, with: .success("decoded"))
        await waitUntil { model.output == "decoded" }

        #expect(model.mode == "dec")
        #expect(model.input == "large")
        #expect(!model.isProcessing)
    }

    @MainActor
    @Test func modeSpecificEmptyPolicyPreservesWhitespaceOnlyForEncoding() {
        let counter = LockedConverterCallRecorder()
        let model = makeModel(
            synchronousInputByteLimit: 64,
            isEmptyInput: { input, mode in
                mode == "enc"
                    ? input.isEmpty
                    : input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            },
            convert: { input, mode in
                counter.record(input: input, mode: mode)
                return "converted"
            }
        )

        model.input = "  "
        #expect(model.output == "converted")
        #expect(counter.callCount == 1)

        model.mode = "dec"

        #expect(model.input == "  ")
        #expect(model.output.isEmpty)
        #expect(model.error == nil)
        #expect(!model.isProcessing)
        #expect(counter.callCount == 1)
    }

    @MainActor
    private func makeModel(
        initialMode: String = "enc",
        synchronousInputByteLimit: Int,
        backgroundDebounce: Duration = .milliseconds(120),
        isEmptyInput: @escaping IndexConverterEmptyInput = { input, _ in input.isEmpty },
        errorMessage: @escaping IndexConverterErrorMessage = { _ in "转换失败。" },
        convert: @escaping IndexConverterOperation,
        backgroundExecutor: IndexConverterBackgroundExecutor? = nil
    ) -> IndexConverterToolWorkspaceModel {
        IndexConverterToolWorkspaceModel(
            initialMode: initialMode,
            synchronousInputByteLimit: synchronousInputByteLimit,
            backgroundDebounce: backgroundDebounce,
            isEmptyInput: isEmptyInput,
            errorMessage: errorMessage,
            convert: convert,
            backgroundExecutor: backgroundExecutor
        )
    }

    @MainActor
    private func waitUntil(
        timeout: Duration = .seconds(20),
        condition: @escaping @MainActor () -> Bool
    ) async {
        let deadline = ContinuousClock.now + timeout
        while !condition(), ContinuousClock.now < deadline {
            await Task.yield()
        }
        #expect(condition())
    }
}

private enum ConverterTestError: Error, Equatable, Sendable {
    case invalid
}

private struct ConverterCall: Equatable, Sendable {
    let input: String
    let mode: String
}

private final class LockedConverterCallRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recordedCalls: [ConverterCall] = []
    private var mainThreadValues: [Bool] = []

    var callCount: Int {
        lock.withLock { recordedCalls.count }
    }

    var calls: [ConverterCall] {
        lock.withLock { recordedCalls }
    }

    var ranOnMainThreadValues: [Bool] {
        lock.withLock { mainThreadValues }
    }

    func record(
        input: String,
        mode: String,
        ranOnMainThread: Bool = Thread.isMainThread
    ) {
        lock.withLock {
            recordedCalls.append(.init(input: input, mode: mode))
            mainThreadValues.append(ranOnMainThread)
        }
    }
}

private actor IndexConverterExecutionGate {
    private var continuations: [IndexConverterRequest: [CheckedContinuation<IndexConverterExecutionResult, Never>]] = [:]
    private var requestCounts: [IndexConverterRequest: Int] = [:]

    func execute(_ request: IndexConverterRequest) async -> IndexConverterExecutionResult {
        requestCounts[request, default: 0] += 1
        return await withCheckedContinuation { continuation in
            continuations[request, default: []].append(continuation)
        }
    }

    func waitForRequest(_ request: IndexConverterRequest) async {
        while requestCounts[request, default: 0] < 1 {
            await Task.yield()
        }
    }

    func resume(
        _ request: IndexConverterRequest,
        with result: IndexConverterExecutionResult
    ) {
        let pending = continuations.removeValue(forKey: request) ?? []
        for continuation in pending {
            continuation.resume(returning: result)
        }
    }
}
