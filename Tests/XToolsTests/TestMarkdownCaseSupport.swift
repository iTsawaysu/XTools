import XToolsCore
import Foundation
import Testing

struct MarkdownDevelopmentCase: Sendable {
    let id: String
    let title: String
    let body: String
    let codeBlocks: [String]
}

enum TestMarkdownCaseSupport {
    static let prefixes = [
        "JSON-FMT", "SQL-FMT", "XML-FMT", "YAML-FMT",
        "JSON-DIFF", "TEXT-DIFF", "REGEX", "DOCKER"
    ]

    static func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    /// Development-tool case inventory used by TestMarkdown*Coverage tests.
    /// Bundled as a test-target resource (`Fixtures/test.md`).
    static func testMarkdownURL() throws -> URL {
        try #require(
            Bundle.module.url(forResource: "test", withExtension: "md"),
            "XToolsTests resource Fixtures/test.md is missing from Bundle.module"
        )
    }

    static func loadCases() throws -> [String: MarkdownDevelopmentCase] {
        let markdown = try String(
            contentsOf: testMarkdownURL(),
            encoding: .utf8
        )
        let headingPattern = #"^### ((?:JSON-FMT|SQL-FMT|XML-FMT|YAML-FMT|JSON-DIFF|TEXT-DIFF|REGEX|DOCKER)-\d+) · (.+)$"#
        let headingRegex = try NSRegularExpression(pattern: headingPattern, options: [.anchorsMatchLines])
        let fullRange = NSRange(markdown.startIndex..<markdown.endIndex, in: markdown)
        let matches = headingRegex.matches(in: markdown, range: fullRange)
        var result: [String: MarkdownDevelopmentCase] = [:]

        for (index, match) in matches.enumerated() {
            guard let idRange = Range(match.range(at: 1), in: markdown),
                  let titleRange = Range(match.range(at: 2), in: markdown),
                  let headingRange = Range(match.range, in: markdown) else {
                continue
            }

            let bodyEnd: String.Index
            if index + 1 < matches.count,
               let nextRange = Range(matches[index + 1].range, in: markdown) {
                bodyEnd = nextRange.lowerBound
            } else if let nextSection = markdown.range(of: "\n## 9. ", range: headingRange.upperBound..<markdown.endIndex) {
                bodyEnd = nextSection.lowerBound
            } else {
                bodyEnd = markdown.endIndex
            }

            let id = String(markdown[idRange])
            let title = String(markdown[titleRange])
            let body = String(markdown[headingRange.lowerBound..<bodyEnd])
            let codeBlocks = try fencedCodeBlocks(in: body)
            result[id] = MarkdownDevelopmentCase(id: id, title: title, body: body, codeBlocks: codeBlocks)
        }

        return result
    }

    static func testCase(_ id: String) throws -> MarkdownDevelopmentCase {
        let cases = try loadCases()
        return try #require(cases[id], "Fixtures/test.md 缺少案例 \(id)")
    }

    static func block(_ testCase: MarkdownDevelopmentCase, _ index: Int) throws -> String {
        try #require(
            testCase.codeBlocks.indices.contains(index) ? testCase.codeBlocks[index] : nil,
            "\(testCase.id) 缺少第 \(index + 1) 个代码块"
        )
    }

    static func readSource(_ relativePath: String) throws -> String {
        try String(contentsOf: repositoryRoot().appendingPathComponent(relativePath), encoding: .utf8)
    }

    static func jsonDiagnostic(_ input: String) throws -> FormatDiagnostic {
        do {
            _ = try JSONFormatting.format(input, sortKeys: false, indentWidth: 2)
            Issue.record("Expected invalid JSON: \(input)")
            return FormatDiagnostic(formatName: "JSON", message: "未产生预期错误")
        } catch let error as JSONFormatting.FormattingError {
            return error.diagnostic
        }
    }

    static func sqlDiagnostic(_ input: String) throws -> FormatDiagnostic {
        do {
            _ = try SQLFormatting.format(input)
            Issue.record("Expected invalid SQL: \(input)")
            return FormatDiagnostic(formatName: "SQL", message: "未产生预期错误")
        } catch let error as SQLFormatting.ValidationError {
            return error.diagnostic
        }
    }

    static func xmlDiagnostic(_ input: String) throws -> FormatDiagnostic {
        do {
            _ = try XMLFormatting.format(input)
            Issue.record("Expected invalid XML: \(input)")
            return FormatDiagnostic(formatName: "XML", message: "未产生预期错误")
        } catch let error as XMLFormatting.FormattingError {
            return error.diagnostic
        }
    }

    static func yamlDiagnostic(_ input: String) throws -> FormatDiagnostic {
        do {
            _ = try YAMLPrettifier.formatValidated(input)
            Issue.record("Expected invalid YAML: \(input)")
            return FormatDiagnostic(formatName: "YAML", message: "未产生预期错误")
        } catch let error as YAMLPrettifier.ValidationError {
            return error.diagnostic
        }
    }

    static func comparableJSONRows(left: String, right: String) throws -> [DiffAlignedRow] {
        let labels = JSONDiffValidation.SideLabels(left: "JSON A", right: "JSON B")
        let decision = JSONStructuralDiff.alignedDiff(left: left, right: right, labels: labels)
        guard case .comparable(let rows) = decision else {
            Issue.record("Expected comparable JSON, got \(decision)")
            return []
        }
        return rows
    }

    static func assertFactual(_ diagnostic: FormatDiagnostic) {
        #expect(diagnostic.displayMessage == diagnostic.message)
        #expect(diagnostic.workspaceMessage == diagnostic.message)
        #expect(!diagnostic.message.contains("处理方式："))
        #expect(!diagnostic.message.contains("The operation"))
        #expect(!diagnostic.message.contains("Error Domain"))
    }

    private static func fencedCodeBlocks(in body: String) throws -> [String] {
        let pattern = #"^```[^\n]*\n(.*?)^```[ \t]*$"#
        let regex = try NSRegularExpression(
            pattern: pattern,
            options: [.anchorsMatchLines, .dotMatchesLineSeparators]
        )
        let range = NSRange(body.startIndex..<body.endIndex, in: body)
        return regex.matches(in: body, range: range).compactMap { match in
            guard let capture = Range(match.range(at: 1), in: body) else { return nil }
            var value = String(body[capture])
            if value.hasSuffix("\n") {
                value.removeLast()
            }
            return value
        }
    }
}

struct TestMarkdownCoverageInventoryTests {
    @Test func everyTargetCaseHasAnExecutableMatrixEntry() throws {
        let actual = Set(try TestMarkdownCaseSupport.loadCases().keys)
        let expected = Set(
            (1...20).map { String(format: "JSON-FMT-%02d", $0) }
            + (1...16).map { String(format: "SQL-FMT-%02d", $0) }
            + (1...12).map { String(format: "XML-FMT-%02d", $0) }
            + (1...14).map { String(format: "YAML-FMT-%02d", $0) }
            + (1...14).map { String(format: "JSON-DIFF-%02d", $0) }
            + (1...13).map { String(format: "TEXT-DIFF-%02d", $0) }
            + (1...19).map { String(format: "REGEX-%02d", $0) }
            + (1...20).map { String(format: "DOCKER-%02d", $0) }
        )

        #expect(actual == expected)
        #expect(actual.count == 128)
    }
}
