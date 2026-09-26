@testable import XTools
import Foundation
import Testing

@MainActor
struct TextEncryptionToolWorkspaceModelTests {
    @Test func explicitRunUsesBackgroundSnapshot() async throws {
        let model = TextEncryptionToolWorkspaceModel(operation: { request in
            TextEncryptionOutcome(
                output: "\(Thread.isMainThread)|\(request.input)|\(request.password)|\(request.mode)|\(request.algorithm)",
                error: nil
            )
        })
        model.input = "message"
        model.password = "secret"
        model.mode = "dec"
        model.algorithm = "AES"

        model.run()
        #expect(model.output.isEmpty)
        try await waitUntil { !model.output.isEmpty }
        #expect(model.output == "false|message|secret|dec|AES")
        #expect(model.error == nil)
    }

    @Test func newerRunCannotBeOverwrittenByNonCooperativeOlderRun() async throws {
        let probe = BlockingEncryptionProbe()
        let model = TextEncryptionToolWorkspaceModel(operation: { probe.run($0) })
        model.input = "first"
        model.password = "old"
        model.run()
        try await waitUntil { probe.hasStarted("first") }

        model.input = "second"
        model.password = "new"
        model.run()
        probe.releaseFirst.signal()
        try await waitUntil { probe.hasStarted("second") }
        #expect(model.output.isEmpty)
        #expect(model.error == nil)

        probe.releaseSecond.signal()
        try await waitUntil { model.output == "second|new|enc|AES-GCM" }
    }

    @Test func clearAndDirectEditsInvalidateRunningWork() async throws {
        for change in 0..<6 {
            let probe = BlockingEncryptionProbe()
            let model = TextEncryptionToolWorkspaceModel(operation: { probe.run($0) })
            model.input = "first"
            model.password = "secret"
            model.run()
            try await waitUntil { probe.hasStarted("first") }

            switch change {
            case 0: model.input = "edited"
            case 1: model.password = "edited"
            case 2: model.mode = "dec"
            case 3: model.algorithm = "AES"
            case 4: model.clearSensitiveState()
            default: model.clearResult()
            }
            #expect(model.output.isEmpty)
            probe.releaseFirst.signal()
            try await waitUntil { probe.hasCompleted("first") }
            try await Task.sleep(for: .milliseconds(100))
            #expect(model.output.isEmpty)
            #expect(model.error == nil)
        }
    }

    @Test func canonicallyEquivalentUnicodeEditsStillInvalidateChangedBytes() async throws {
        for editsInput in [true, false] {
            let oldInput = editsInput ? "é" : "first"
            let probe = BlockingEncryptionProbe(blockedInput: oldInput)
            let model = TextEncryptionToolWorkspaceModel(operation: { probe.run($0) })
            model.input = oldInput
            model.password = editsInput ? "secret" : "é"
            model.run()
            try await waitUntil { probe.hasStarted(oldInput) }

            if editsInput {
                model.input = "e\u{301}"
            } else {
                model.password = "e\u{301}"
            }
            #expect(model.output.isEmpty)
            probe.releaseFirst.signal()
            try await waitUntil { probe.hasCompleted(oldInput) }
            try await Task.sleep(for: .milliseconds(100))
            #expect(model.output.isEmpty)
            #expect(model.error == nil)
        }
    }

    @Test func assigningTheSameBytesKeepsTheRunningRequest() async throws {
        let probe = BlockingEncryptionProbe()
        let model = TextEncryptionToolWorkspaceModel(operation: { probe.run($0) })
        model.input = "first"
        model.password = "secret"
        model.run()
        try await waitUntil { probe.hasStarted("first") }

        model.input = "first"
        model.password = "secret"
        probe.releaseFirst.signal()
        try await waitUntil { model.output == "first|secret|enc|AES-GCM" }
    }

    @Test func modeBackfillAndEmptyPasswordKeepExistingContracts() async throws {
        let model = TextEncryptionToolWorkspaceModel(operation: { request in
            TextEncryptionOutcome(output: "cipher:\(request.input)", error: nil)
        })
        model.input = "plain"
        model.run()
        #expect(model.error == "加密口令不能为空。")

        model.password = "secret"
        model.run()
        try await waitUntil { model.output == "cipher:plain" }
        model.changeMode(to: "dec")
        #expect(model.input == "cipher:plain")
        #expect(model.output.isEmpty)
        #expect(model.error == nil)
    }

    private func waitUntil(
        timeout: Duration = .seconds(5),
        _ condition: @escaping @MainActor () -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while !condition() && clock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        try #require(condition())
    }
}

private final class BlockingEncryptionProbe: @unchecked Sendable {
    let releaseFirst = DispatchSemaphore(value: 0)
    let releaseSecond = DispatchSemaphore(value: 0)
    private let blockedInput: String
    private let lock = NSLock()
    private var started: Set<String> = []
    private var completed: Set<String> = []

    init(blockedInput: String = "first") {
        self.blockedInput = blockedInput
    }

    func hasStarted(_ input: String) -> Bool { lock.withLock { started.contains(input) } }
    func hasCompleted(_ input: String) -> Bool { lock.withLock { completed.contains(input) } }

    func run(_ request: TextEncryptionRequest) -> TextEncryptionOutcome {
        lock.withLock { _ = started.insert(request.input) }
        if request.input == blockedInput {
            _ = releaseFirst.wait(timeout: .now() + 5)
        } else if request.input == "second" {
            _ = releaseSecond.wait(timeout: .now() + 5)
        }
        lock.withLock { _ = completed.insert(request.input) }
        return TextEncryptionOutcome(
            output: "\(request.input)|\(request.password)|\(request.mode)|\(request.algorithm)",
            error: nil
        )
    }
}
