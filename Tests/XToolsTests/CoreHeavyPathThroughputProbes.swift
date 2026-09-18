import Foundation
import Testing
import XToolsCore

/// Test-only throughput probes for the performance audit (observation policy B).
/// Always runs with the suite; fixtures stay bounded so debug CI stays fast.
/// Timings print to stderr as `CORE_PERF tool=... size=... ms=...`.
struct CoreHeavyPathThroughputProbes {
    private static let warmupIterations = 1
    private static let sampleIterations = 3

    @Test func htmlToMarkdownThroughputAtRepresentativeSizes() {
        let sizes = [32_768, 131_072, 524_288]
        for byteTarget in sizes {
            let html = Self.syntheticArticleHTML(targetUTF8Bytes: byteTarget)
            let samples = Self.measureMilliseconds(label: "html-to-markdown", size: html.utf8.count) {
                _ = HTMLToMarkdownConverter.convert(html)
            }
            #expect(samples.count == Self.sampleIterations)
            #expect(samples.allSatisfy { $0 >= 0 })
        }
    }

    @Test func lineDifferThroughputAtRepresentativeLineCounts() throws {
        // Cell counts: (n+1)^2 — keep well under 12e6 budget and debug-test budget.
        let lineCounts = [200, 500, 1_000]
        for count in lineCounts {
            let left = Self.syntheticLines(count: count, seed: "L")
            let right = Self.syntheticLines(count: count, seed: "R", mutateEvery: 17)
            let samples = try Self.measureMillisecondsThrowing(
                label: "line-differ",
                size: count
            ) {
                _ = try LineDiffer.safeAlignedDiff(left: left, right: right)
            }
            #expect(samples.count == Self.sampleIterations)
        }
    }

    @Test func lineDifferPrefixSuffixTrimmingThroughput() throws {
        let leftPrefix = (1...1500).map { "log-entry-\($0)-timestamp-2026-09-16-level-info" }.joined(separator: "\n")
        let suffix = (1506...3000).map { "log-entry-\($0)-timestamp-2026-09-16-level-info" }.joined(separator: "\n")
        let left = "\(leftPrefix)\nerror-1\nerror-2\nerror-3\nerror-4\nerror-5\n\(suffix)"
        let right = "\(leftPrefix)\nwarning-1\nwarning-2\nwarning-3\nwarning-4\nwarning-5\n\(suffix)"

        let samples = try Self.measureMillisecondsThrowing(
            label: "line-differ-trimmed-3k",
            size: 3000
        ) {
            _ = try LineDiffer.safeAlignedDiff(left: left, right: right)
        }
        #expect(samples.count == Self.sampleIterations)
        #expect(samples.allSatisfy { $0 >= 0 })
        #expect(Self.median(samples) < 50.0)
    }

    @Test func jsonFormatThroughputAtRepresentativeSizes() throws {
        let sizes = [32_768, 131_072]
        for byteTarget in sizes {
            let json = Self.syntheticJSON(targetUTF8Bytes: byteTarget)
            let samples = try Self.measureMillisecondsThrowing(
                label: "json-format",
                size: json.utf8.count
            ) {
                _ = try JSONFormatting.format(json, sortKeys: false, indentWidth: 2)
            }
            #expect(samples.count == Self.sampleIterations)
        }
    }

    // MARK: - Fixtures

    private static func syntheticArticleHTML(targetUTF8Bytes: Int) -> String {
        var body = ""
        body.reserveCapacity(targetUTF8Bytes)
        var index = 0
        while body.utf8.count < targetUTF8Bytes {
            body += "<p>Paragraph \(index) with <strong>bold</strong> and <a href=\"https://example.com/\(index)\">link</a> text for conversion load.</p>\n"
            if index % 20 == 0 {
                body += "<h2>Section \(index)</h2>\n<ul><li>Item A</li><li>Item B</li></ul>\n"
            }
            index += 1
        }
        return "<html><body><h1>Article</h1>\(body)</body></html>"
    }

    private static func syntheticLines(count: Int, seed: String, mutateEvery: Int = 0) -> String {
        var lines: [String] = []
        lines.reserveCapacity(count)
        for index in 0..<count {
            if mutateEvery > 0, index % mutateEvery == 0 {
                lines.append("\(seed)-mut-\(index)-unique-payload")
            } else {
                lines.append("shared-line-\(index)-content")
            }
        }
        return lines.joined(separator: "\n")
    }

    private static func syntheticJSON(targetUTF8Bytes: Int) -> String {
        var items: [String] = []
        var index = 0
        var assembled = ""
        repeat {
            items.append(
                #"{"id":\#(index),"name":"item-\#(index)","active":\#(index % 2 == 0),"score":\#(index).5}"#
            )
            assembled = "[\n" + items.joined(separator: ",\n") + "\n]"
            index += 1
        } while assembled.utf8.count < targetUTF8Bytes
        return assembled
    }

    // MARK: - Timing

    private static func measureMilliseconds(
        label: String,
        size: Int,
        operation: () -> Void
    ) -> [Double] {
        for _ in 0..<warmupIterations {
            operation()
        }
        var samples: [Double] = []
        samples.reserveCapacity(sampleIterations)
        for _ in 0..<sampleIterations {
            let start = ContinuousClock.now
            operation()
            let ms = milliseconds(since: start)
            samples.append(ms)
            emit(label: label, size: size, milliseconds: ms)
        }
        return samples
    }

    private static func measureMillisecondsThrowing(
        label: String,
        size: Int,
        operation: () throws -> Void
    ) throws -> [Double] {
        for _ in 0..<warmupIterations {
            try operation()
        }
        var samples: [Double] = []
        samples.reserveCapacity(sampleIterations)
        for _ in 0..<sampleIterations {
            let start = ContinuousClock.now
            try operation()
            let ms = milliseconds(since: start)
            samples.append(ms)
            emit(label: label, size: size, milliseconds: ms)
        }
        return samples
    }

    private static func milliseconds(since start: ContinuousClock.Instant) -> Double {
        let duration = start.duration(to: .now)
        let components = duration.components
        return Double(components.seconds) * 1_000
            + Double(components.attoseconds) / 1_000_000_000_000_000
    }

    private static func median(_ samples: [Double]) -> Double {
        let ordered = samples.sorted()
        guard !ordered.isEmpty else { return .infinity }
        return ordered[ordered.count / 2]
    }

    private static func emit(label: String, size: Int, milliseconds: Double) {
        let line = String(
            format: "CORE_PERF tool=%@ size=%d ms=%.3f\n",
            label,
            size,
            milliseconds
        )
        FileHandle.standardError.write(Data(line.utf8))
    }
}
