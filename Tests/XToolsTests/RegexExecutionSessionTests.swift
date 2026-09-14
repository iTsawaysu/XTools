@testable import XTools
import XToolsCore
import Foundation
import Testing

@MainActor
struct RegexExecutionSessionTests {
    @Test func newerRunCannotBeOverwrittenByOlderResult() async throws {
        let operation: RegexMatchOperation = { pattern, text, flags in
            if pattern == "slow" {
                Thread.sleep(forTimeInterval: 0.2)
            }
            return try RegexMatcher.analyze(pattern: pattern, in: text, flags: flags)
        }
        let session = RegexExecutionSession()

        session.run(pattern: "slow", text: "slow", flags: "g", operation: operation)
        session.run(pattern: "fast", text: "fast", flags: "g", operation: operation)

        try await waitUntil { session.report?.pattern == "fast" }
        try await Task.sleep(for: .milliseconds(500))
        #expect(session.report?.pattern == "fast")
        #expect(session.reportSourceText == "fast")
        #expect(session.error == nil)
        #expect(!session.isRunning)
    }

    @Test func errorClearsOutputAndValidRunRecovers() async throws {
        let session = RegexExecutionSession()

        session.run(pattern: "(", text: "abc", flags: "g")
        try await waitUntil { session.error != nil }
        #expect(session.report == nil)
        #expect(session.reportSourceText == nil)

        session.run(pattern: #"\d+"#, text: "a12", flags: "g")
        try await waitUntil { session.report?.matches.first?.value == "12" }
        #expect(session.reportSourceText == "a12")
        #expect(session.error == nil)
        #expect(!session.isRunning)
    }

    @Test func emptyPatternCancelsAndClearsExistingState() async throws {
        let session = RegexExecutionSession()
        session.run(pattern: "abc", text: "abc", flags: "g")
        try await waitUntil { session.report != nil }

        session.run(pattern: "", text: "private text", flags: "g")

        #expect(session.report == nil)
        #expect(session.reportSourceText == nil)
        #expect(session.error == nil)
        #expect(!session.isRunning)
    }

    @Test func catastrophicPatternCompletesOffMainActorWithFactualError() async throws {
        let session = RegexExecutionSession()
        let text = String(repeating: "A", count: 50_000) + "C"

        session.run(pattern: "(A+)+B", text: text, flags: "g")
        #expect(session.isRunning)
        try await waitUntil { session.error != nil }

        #expect(session.error == "正则表达式计算量过大。")
        #expect(session.report == nil)
        #expect(session.reportSourceText == nil)
        ToolDiagnosticContract.expectFactual(
            session.error ?? "",
            sensitiveInputs: [String(text.prefix(256))]
        )
    }

    private func waitUntil(
        timeout: Duration = .seconds(20),
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while clock.now < deadline {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("Timed out waiting for regex execution state")
    }
}
