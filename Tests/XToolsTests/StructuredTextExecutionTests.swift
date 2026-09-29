import Foundation
import Testing
@testable import XToolsCore

struct StructuredTextExecutionTests {
    @Test(arguments: ["JSON", "SQL", "XML", "YAML"])
    func cancelledFormatterDoesNotProduceOutput(_ format: String) async throws {
        let cancelled = await Task.detached {
            withUnsafeCurrentTask { $0?.cancel() }
            do {
                switch format {
                case "JSON": _ = try JSONFormatting.format("{\"a\":1}", sortKeys: false, indentWidth: 2)
                case "SQL": _ = try SQLFormatting.format("select 1")
                case "XML": _ = try XMLFormatting.format("<root/>")
                default: _ = try YAMLPrettifier.formatValidated("a: 1")
                }
                return false
            } catch is CancellationError {
                return true
            } catch {
                return false
            }
        }.value
        #expect(cancelled)
    }
}

extension StructuredTextExecutionTests {
    @Test(arguments: ["JSON", "SQL", "XML", "YAML"])
    func cancellationDuringWorkIsNotOnlyAnEntryCheck(_ format: String) throws {
        let probe = StructuredTextCancellationProbe(cancelAt: 8)
        #expect(throws: CancellationError.self) {
            try StructuredTextExecution.withCancellation({ probe.poll() }) {
                switch format {
                case "JSON":
                    _ = try JSONFormatting.minify("\"" + String(repeating: "a", count: 100_000) + "\"")
                case "SQL":
                    _ = try SQLFormatting.format("select '" + String(repeating: "a", count: 100_000) + "'")
                case "XML":
                    _ = try XMLFormatting.format("<r>" + String(repeating: "<a/>", count: 10_000) + "</r>")
                default:
                    _ = try YAMLPrettifier.formatValidated("value: \"" + String(repeating: "a", count: 100_000) + "\"")
                }
            }
        }
        #expect(probe.count == 8)
    }

    @Test(arguments: ["JSON", "SQL", "XML", "YAML"])
    func outputBudgetRejectsWholeResult(_ format: String) throws {
        #expect(throws: StructuredTextResourceError.self) {
            try StructuredTextExecution.$outputByteLimit.withValue(64) {
                switch format {
                case "JSON": _ = try JSONFormatting.format("[1,2,3,4,5,6,7,8,9,10]", sortKeys: false, indentWidth: 8)
                case "SQL": _ = try SQLFormatting.format("select a,b,c,d,e,f,g,h,i,j,k,l,m,n from tab", options: .init(indentWidth: 8))
                case "XML": _ = try XMLFormatting.format("<r>" + String(repeating: "<a/>", count: 10) + "</r>")
                default: _ = try YAMLPrettifier.formatValidated("a: [one, two, three, four, five, six]", options: .init())
                }
            }
        }
    }

    @Test func pastedInputUsesTheExistingImportByteEnvelope() throws {
        let input = String(repeating: "a", count: StructuredTextExecution.maximumInputBytes + 1)
        for format in ["JSON", "SQL", "XML", "YAML"] {
            do {
                switch format {
                case "JSON": _ = try JSONFormatting.minify(input)
                case "SQL": _ = try SQLFormatting.format(input)
                case "XML": _ = try XMLFormatting.format(input)
                default: _ = try YAMLPrettifier.formatValidated(input)
                }
                Issue.record("Oversized input unexpectedly accepted by \(format)")
            } catch let error as StructuredTextResourceError {
                #expect(error.diagnostic.formatName == format)
                #expect(error.diagnostic.message.contains("15 MB"))
                #expect(error.diagnostic.excerpt == nil)
            }
        }
    }

    @Test func yamlDepthUsesParserEventsAndProtectsComposition() throws {
        let atLimit = String(repeating: "[", count: 64) + "0" + String(repeating: "]", count: 64)
        try YAMLPrettifier.validate(atLimit)
        #expect(throws: StructuredTextResourceError.self) {
            try YAMLPrettifier.validate("[" + atLimit + "]")
        }
        try YAMLPrettifier.validate("value: \"" + String(repeating: "[", count: 100) + "\"")
        try YAMLPrettifier.validate("value: |\n  " + String(repeating: "[", count: 100))
    }

    @Test func yamlAliasesArePreservedWithoutConstructingExpandedValues() throws {
        var input = "a0: &a0 [value]\n"
        for index in 1...24 { input += "a\(index): &a\(index) [*a\(index - 1), *a\(index - 1)]\n" }
        // Over 16 million logical leaves, but only a small shared syntax graph.
        // Validation must not use Yams.load's recursive Any construction.
        let output = try YAMLPrettifier.formatValidated(input, options: .init())
        #expect(output == input.trimmingCharacters(in: .newlines))
        #expect(output.contains("*a23"))
    }

    @Test func recursiveAliasHashingInMappingKeysHasItsOwnBudget() throws {
        var input = "a0: &a0 [value]\n"
        for index in 1...20 { input += "a\(index): &a\(index) [*a\(index - 1), *a\(index - 1)]\n" }
        input += "? *a20\n: value\n"
        #expect(throws: StructuredTextResourceError.self) { try YAMLPrettifier.validate(input) }
    }

    @Test func yamlSingleDocumentValidationAndMultiDocumentFormattingStayDistinct() throws {
        try YAMLPrettifier.validate("")
        try YAMLPrettifier.validate("---\n")
        #expect(throws: YAMLPrettifier.ValidationError.self) {
            try YAMLPrettifier.validate("a: 1\n---\nb: 2\n")
        }
        let output = try YAMLPrettifier.format("a: 1\n---\nb: 2\n", options: .init())
        #expect(output.contains("a: 1"))
        #expect(output.contains("b: 2"))
        #expect(throws: (any Error).self) {
            _ = try YAMLPrettifier.format("a: 1\n---\nb: [", options: .init())
        }
    }

    @Test func boundedBuilderRejectsBeforeExtendingItsStorage() throws {
        try StructuredTextExecution.$outputByteLimit.withValue(8) {
            var output = StructuredTextOutput(format: "JSON")
            try output.append("12345678")
            #expect(throws: StructuredTextResourceError.self) { try output.append("9") }
            #expect(output.text == "12345678")
            #expect(output.byteCount == 8)
        }
    }

    @Test func formatRunnerTreatsCancellationAsQuietEmpty() {
        let outcome: FormatOutcome<String> = FormatRunner.run("still valid") { _ in throw CancellationError() }
        #expect(outcome == .empty)
        #expect(FormatRunner.run("still valid") { $0 } == .produced("still valid"))
    }
}

private final class StructuredTextCancellationProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var polls = 0
    private let cancelAt: Int

    init(cancelAt: Int) { self.cancelAt = cancelAt }
    var count: Int { lock.withLock { polls } }
    func poll() -> Bool {
        lock.withLock {
            polls += 1
            return polls >= cancelAt
        }
    }
}

extension StructuredTextExecutionTests {
    @Test func nestedSortedCompactArraysReuseTheirSortRenderings() throws {
        var input = "0"
        for _ in 0..<28 { input = "[" + input + ",null]" }
        let probe = StructuredTextCancellationProbe(cancelAt: 5_000)
        let output = try StructuredTextExecution.withCancellation({ probe.poll() }) {
            try JSONFormatting.minifyResult(input, sortArrays: true).text
        }
        #expect(!output.isEmpty)
        #expect(output.utf8.count == input.utf8.count)
        #expect(probe.count < 5_000)
    }

    @Test func yamlMappingKeyBudgetAggregatesSharedAliasCost() throws {
        var input = "a0: &a0 [value]\n"
        for index in 1...16 { input += "a\(index): &a\(index) [*a\(index - 1), *a\(index - 1)]\n" }
        // Each key is below the individual limit. Hashing all keys still has
        // aggregate recursive cost, even though their values share storage.
        for index in 0..<10 { input += "? [*a16, key\(index)]\n: value\n" }
        #expect(throws: StructuredTextResourceError.self) { try YAMLPrettifier.validate(input) }
    }
}

extension StructuredTextExecutionTests {
    @Test func yamlMappingKeyBudgetIncludesRepeatedScalarBytes() throws {
        var input = "long: &long " + String(repeating: "x", count: 1_000_000) + "\n"
        for index in 0..<61 { input += "? [*long, key\(index)]\n: value\n" }
        #expect(throws: StructuredTextResourceError.self) { try YAMLPrettifier.validate(input) }
    }
}

extension StructuredTextExecutionTests {
    @Test func extremeNegativeYAMLIndentUsesNativeDefaultWithoutIntegerTrap() throws {
        let input = "root: {value: [one, two]}"
        let output = try YAMLPrettifier.format(input, options: .init(indent: Int.min))
        let expected = try YAMLPrettifier.format(input, options: .init(indent: 0))
        #expect(output == expected)
    }
}

extension StructuredTextExecutionTests {
    @Test(arguments: ["value", "[value]", "{key: value}"])
    func yamlMappingKeyBudgetIncludesExplicitScalarAndContainerTags(_ value: String) throws {
        let tag = "tag:example.test," + String(repeating: "x", count: 100)
        let input = "a: &a !<" + tag + "> " + value + "\n? [*a, unique]\n: result\n"
        try YAMLPrettifier.validate(input)
        #expect(throws: StructuredTextResourceError.self) {
            try YAMLProcessingPreflight.$maximumKeyBytes.withValue(128) {
                try YAMLPrettifier.validate(input)
            }
        }
    }
}
