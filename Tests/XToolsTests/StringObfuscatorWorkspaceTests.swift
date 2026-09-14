@testable import XTools
import XToolsCore
import Foundation
import Testing

struct StringObfuscatorWorkspaceTests {
    @MainActor
    @Test func smallInputAndRecipeChangesRenderImmediately() {
        let counter = StringMaskingCallCounter()
        let model = makeModel(
            synchronousInputByteLimit: 64,
            renderer: { request, shouldCancel in
                counter.increment()
                return Self.render(request, shouldCancel: shouldCancel)
            }
        )

        model.keepFirst = 0
        model.keepLast = 0
        model.input = "abcd"

        #expect(model.output == "****")
        #expect(counter.value == 1)
        #expect(!model.isProcessing)
        #expect(!model.usesNativeOutput)

        model.setReplacementCharacter("👩🏽‍💻#")

        #expect(model.replacementChar == "👩🏽‍💻")
        #expect(model.output == "👩🏽‍💻👩🏽‍💻👩🏽‍💻👩🏽‍💻")
        #expect(counter.value == 2)
        #expect(!model.isProcessing)
    }

    @MainActor
    @Test func inputAboveByteBoundaryClearsOldOutputAndUsesBackgroundRenderer() async {
        let counter = StringMaskingCallCounter()
        let model = makeModel(
            synchronousInputByteLimit: 4,
            debounce: .zero,
            backgroundRenderer: { request in
                counter.increment()
                return "background:\(request.input)"
            }
        )

        model.input = "1234"
        #expect(!model.output.isEmpty)

        model.input = "12345"

        #expect(model.output.isEmpty)
        #expect(model.isProcessing)
        #expect(model.usesNativeOutput)
        await waitUntil { model.output == "background:12345" }

        #expect(counter.value == 1)
        #expect(!model.isProcessing)
    }

    @MainActor
    @Test func defaultBackgroundRendererPublishesACompleteLargeResult() async {
        let model = makeModel(
            synchronousInputByteLimit: 2,
            debounce: .zero
        )
        model.keepFirst = 0
        model.keepLast = 0

        model.input = String(repeating: "a", count: 100_000)

        #expect(model.isProcessing)
        await waitUntil { !model.isProcessing }

        #expect(model.output.count == 100_000)
        #expect(model.output.allSatisfy { $0 == "*" })
        #expect(model.usesNativeOutput)
    }

    @MainActor
    @Test func rapidEditsCannotPublishAnOlderBackgroundResult() async {
        let gate = StringMaskingRenderGate()
        let model = makeModel(
            synchronousInputByteLimit: 2,
            debounce: .zero,
            backgroundRenderer: { request in
                await gate.wait(for: request.input)
            }
        )

        model.input = "first"
        await gate.waitForRequest("first")

        model.input = "latest"
        await gate.waitForRequest("latest")

        await gate.resume("first", with: "old")
        await Task.yield()

        #expect(model.output.isEmpty)
        #expect(model.isProcessing)

        await gate.resume("latest", with: "current")
        await waitUntil { model.output == "current" }

        #expect(!model.isProcessing)
    }

    @MainActor
    @Test func clearCancelsPendingWorkAndRejectsItsLateCompletion() async {
        let gate = StringMaskingRenderGate()
        let model = makeModel(
            synchronousInputByteLimit: 2,
            debounce: .zero,
            backgroundRenderer: { request in
                await gate.wait(for: request.input)
            }
        )

        model.input = "pending"
        await gate.waitForRequest("pending")

        model.clear()

        #expect(model.input.isEmpty)
        #expect(model.output.isEmpty)
        #expect(!model.isProcessing)
        #expect(!model.usesNativeOutput)

        await gate.resume("pending", with: "old")
        await Task.yield()

        #expect(model.output.isEmpty)
        #expect(!model.isProcessing)
    }

    @MainActor
    private func makeModel(
        synchronousInputByteLimit: Int,
        debounce: Duration = .milliseconds(180),
        renderer: @escaping StringObfuscationRenderer = Self.render,
        backgroundRenderer: StringObfuscationBackgroundRenderer? = nil
    ) -> StringObfuscatorToolWorkspaceModel {
        let suiteName = "StringObfuscatorWorkspaceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return StringObfuscatorToolWorkspaceModel(
            preferences: ToolPreferenceStore(defaults: defaults),
            synchronousInputByteLimit: synchronousInputByteLimit,
            debounce: debounce,
            renderer: renderer,
            backgroundRenderer: backgroundRenderer
        )
    }

    nonisolated private static func render(
        _ request: StringObfuscationRequest,
        shouldCancel: @escaping @Sendable () -> Bool
    ) -> String? {
        StringObfuscator.obfuscate(
            request.input,
            keepFirst: request.keepFirst,
            keepLast: request.keepLast,
            keepSpaces: request.keepSpaces,
            replacementCharacter: request.replacementCharacter,
            shouldCancel: shouldCancel
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

private final class StringMaskingCallCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int {
        lock.withLock { count }
    }

    func increment() {
        lock.withLock { count += 1 }
    }
}

private actor StringMaskingRenderGate {
    private var continuations: [String: CheckedContinuation<String?, Never>] = [:]
    private var requests: Set<String> = []

    func wait(for input: String) async -> String? {
        requests.insert(input)
        return await withCheckedContinuation { continuation in
            continuations[input] = continuation
        }
    }

    func waitForRequest(_ input: String) async {
        while !requests.contains(input) {
            await Task.yield()
        }
    }

    func resume(_ input: String, with result: String?) {
        continuations.removeValue(forKey: input)?.resume(returning: result)
    }
}
