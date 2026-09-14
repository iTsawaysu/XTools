import Foundation
import Testing
@testable import XToolsCore

struct AsyncWorkGateTests {
    @MainActor
    @Test func invalidateAdvancesTokenAndDropsStaleSchedule() async {
        let gate = AsyncWorkGate()
        let first = gate.token
        var published = 0

        gate.schedule(debounce: .milliseconds(50)) {
            published += 1
        }
        let second = gate.invalidate()
        #expect(second != first)
        #expect(!gate.isCurrent(first))
        #expect(gate.isCurrent(second))

        // Wait well past the cancelled debounce window without publishing.
        try? await Task.sleep(for: .milliseconds(200))
        #expect(published == 0)
    }

    @MainActor
    @Test func schedulePublishesOnlyForCurrentToken() async throws {
        let gate = AsyncWorkGate()
        var values: [Int] = []

        gate.schedule(debounce: .milliseconds(40)) {
            values.append(1)
        }
        // Stay well under the debounce so the first schedule never fires.
        try? await Task.sleep(for: .milliseconds(5))
        _ = gate.invalidate()
        gate.schedule(debounce: .milliseconds(40)) {
            values.append(2)
        }

        try await waitUntil { values == [2] }
        #expect(values == [2])
    }

    @MainActor
    @Test func runDetachedDropsStaleResults() async throws {
        let gate = AsyncWorkGate()
        var published: [Int] = []

        gate.runDetached {
            try? await Task.sleep(for: .milliseconds(80))
            return 1
        } publish: { value in
            published.append(value)
        }
        _ = gate.invalidate()
        gate.runDetached {
            return 2
        } publish: { value in
            published.append(value)
        }

        try await waitUntil { published == [2] }
        #expect(published == [2])
    }

    @MainActor
    private func waitUntil(
        timeout: Duration = .seconds(20),
        _ condition: @escaping @MainActor () -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while !condition() {
            if clock.now >= deadline {
                Issue.record("Timed out waiting for AsyncWorkGate state")
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}

struct ImageInspectProbeContractTests {
    @Test func inspectTransparencyProbeMaxPixelLengthIsBounded() {
        #expect(ImageProcessor.inspectTransparencyProbeMaxPixelLength == 2_048)
        #expect(ImageProcessor.inspectTransparencyProbeMaxPixelLength > 0)
    }
}
