import XToolsCore
import Foundation
import Testing
@testable import XTools

@MainActor
struct HTMLToMarkdownSessionTests {
    @Test func urlRunPublishesStagesAndCleanedResult() async throws {
        let recorder = HTMLSessionStageRecorder()
        let result = Self.urlResult(title: "Article", marker: "ready")
        let session = HTMLToMarkdownSession(
            urlOperation: { _, progress in
                for stage in [
                    HTMLToMarkdownURLPipelineStage.fetching,
                    .extracting,
                    .converting
                ] {
                    await progress(stage)
                    await recorder.append(stage)
                }
                return result
            },
            manualOperation: { _ in
                HTMLToMarkdownConversionResult(markdown: "manual")
            },
            manualDebounce: .milliseconds(10)
        )
        session.urlText = "https://example.com/article"

        session.fetchURL()
        try await Self.waitUntil { session.phase == .ready }

        #expect(session.inputHTML == result.cleanedHTML)
        #expect(session.markdown == result.markdown)
        #expect(session.error == nil)
        #expect(session.warning == nil)
        #expect(await recorder.values == [.fetching, .extracting, .converting])
    }

    @Test func newerURLRunCannotBeOverwrittenByOlderResult() async throws {
        let session = HTMLToMarkdownSession(
            urlOperation: { urlText, progress in
                await progress(.fetching)
                if urlText.contains("slow") {
                    try await Task.sleep(for: .milliseconds(400))
                    return Self.urlResult(title: "Slow", marker: "slow")
                }
                try await Task.sleep(for: .milliseconds(50))
                return Self.urlResult(title: "Fast", marker: "fast")
            },
            manualOperation: { _ in HTMLToMarkdownConversionResult(markdown: "manual") },
            manualDebounce: .milliseconds(10)
        )

        session.urlText = "https://example.com/slow"
        session.fetchURL()
        session.urlText = "https://example.com/fast"
        session.fetchURL()

        try await Self.waitUntil { session.markdown == "fast" }
        try await Task.sleep(for: .milliseconds(500))

        #expect(session.markdown == "fast")
        #expect(session.inputHTML.contains("fast"))
        #expect(session.phase == .ready)
    }

    @Test func manualConversionRunsOffMainThreadAfterDebounce() async throws {
        let session = HTMLToMarkdownSession(
            urlOperation: { _, _ in Self.urlResult(title: "URL", marker: "url") },
            manualOperation: { html in
                HTMLToMarkdownConversionResult(
                    markdown: Thread.isMainThread ? "main" : "background:\(html)"
                )
            },
            manualDebounce: .milliseconds(10)
        )

        session.userEditedHTML("<p>Hello</p>")
        try await Self.waitUntil { session.phase == .ready }

        #expect(session.markdown == "background:<p>Hello</p>")
    }

    @Test func clearCancelsWorkWithoutPublishingFailure() async throws {
        let session = HTMLToMarkdownSession(
            urlOperation: { _, progress in
                await progress(.fetching)
                try await Task.sleep(for: .milliseconds(350))
                throw HTMLReadableArticleExtractionError.readabilityMalformedResult
            },
            manualOperation: { _ in HTMLToMarkdownConversionResult(markdown: "manual") },
            manualDebounce: .milliseconds(10)
        )
        session.urlText = "https://example.com"

        session.fetchURL()
        session.clear()
        try await Task.sleep(for: .milliseconds(450))

        #expect(session.phase == .idle)
        #expect(session.inputHTML.isEmpty)
        #expect(session.markdown.isEmpty)
        #expect(session.error == nil)
        #expect(session.warning == nil)
    }

    @Test func publishingFetchedHTMLDoesNotTriggerManualConversion() async throws {
        let counter = HTMLSessionAtomicCounter()
        let session = HTMLToMarkdownSession(
            urlOperation: { _, progress in
                await progress(.fetching)
                return Self.urlResult(title: "URL", marker: "url")
            },
            manualOperation: { _ in
                counter.increment()
                return HTMLToMarkdownConversionResult(markdown: "manual")
            },
            manualDebounce: .milliseconds(10)
        )
        session.urlText = "https://example.com"

        session.fetchURL()
        try await Self.waitUntil { session.phase == .ready }
        try await Task.sleep(for: .milliseconds(80))

        #expect(counter.value == 0)
        #expect(session.markdown == "url")
    }

    @Test func typedFailuresMapToStableDiagnosticsAndCanRecover() async throws {
        let attempts = HTMLSessionAtomicCounter()
        let session = HTMLToMarkdownSession(
            urlOperation: { _, _ in
                if attempts.incrementAndRead() == 1 {
                    throw HTMLToMarkdownURLFetchError.unsupportedContentType
                }
                return Self.urlResult(title: "Recovered", marker: "recovered")
            },
            manualOperation: { _ in HTMLToMarkdownConversionResult(markdown: "manual") },
            manualDebounce: .milliseconds(10)
        )
        session.urlText = "https://example.com"

        session.fetchURL()
        try await Self.waitUntil { session.phase == .failed }
        #expect(session.error == "URL 返回的不是 HTML 页面。")
        #expect(session.markdown.isEmpty)

        session.fetchURL()
        try await Self.waitUntil { session.phase == .ready }
        #expect(session.markdown == "recovered")
        #expect(session.error == nil)
    }

    @Test func rapidManualEditsDoNotPublishCancelledConversion() async throws {
        let started = HTMLSessionAtomicCounter()
        let finished = HTMLSessionAtomicCounter()
        let session = HTMLToMarkdownSession(
            urlOperation: { _, _ in Self.urlResult(title: "URL", marker: "url") },
            manualOperation: { html in
                started.increment()
                let deadline = ContinuousClock.now + .milliseconds(500)
                while ContinuousClock.now < deadline {
                    try Task.checkCancellation()
                    Thread.sleep(forTimeInterval: 0.01)
                }
                try Task.checkCancellation()
                finished.increment()
                return HTMLToMarkdownConversionResult(markdown: "done:\(html)")
            },
            manualDebounce: .milliseconds(30)
        )

        session.userEditedHTML("<p>first</p>")
        try await Self.waitUntil { session.phase == .converting(.manual) || started.value > 0 }
        session.userEditedHTML("<p>second</p>")
        try await Self.waitUntil { session.markdown == "done:<p>second</p>" }
        try await Task.sleep(for: .milliseconds(250))

        #expect(session.markdown == "done:<p>second</p>")
        #expect(session.phase == .ready)
        #expect(finished.value == 1)
    }

    nonisolated private static func urlResult(title: String, marker: String) -> HTMLToMarkdownURLResult {
        HTMLToMarkdownURLResult(
            finalURL: URL(string: "https://example.com/\(marker)")!,
            title: title,
            cleanedHTML: "<div id=\"readability-page-1\"><h2>\(title)</h2><p>\(marker)</p></div>",
            markdown: marker,
            warnings: []
        )
    }

    private static func waitUntil(
        timeout: Duration = .seconds(20),
        _ predicate: @escaping @MainActor () -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while !predicate() {
            if clock.now >= deadline {
                Issue.record("Timed out waiting for HTMLToMarkdownSession state")
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}

private actor HTMLSessionStageRecorder {
    private(set) var values: [HTMLToMarkdownURLPipelineStage] = []

    func append(_ stage: HTMLToMarkdownURLPipelineStage) {
        values.append(stage)
    }
}

private final class HTMLSessionAtomicCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue = 0

    var value: Int {
        lock.withLock { storedValue }
    }

    func increment() {
        lock.withLock { storedValue += 1 }
    }

    func incrementAndRead() -> Int {
        lock.withLock {
            storedValue += 1
            return storedValue
        }
    }
}
