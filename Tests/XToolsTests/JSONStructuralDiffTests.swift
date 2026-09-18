import Foundation
import Testing
@testable import XToolsCore

struct JSONStructuralDiffTests {
    private let labels = JSONDiffValidation.SideLabels(left: "JSON A", right: "JSON B")

    @Test func sameStructureDifferentFormattingHasNoDiffRows() throws {
        let left = #"{"id":1,"name":"Alice","roles":["admin","dev"],"profile":{"age":30,"city":"Shanghai"}}"#
        let right = """
        {
          "id": 1,
          "name": "Alice",
          "roles": [
            "admin",
            "dev"
          ],
          "profile": {
            "age": 30,
            "city": "Shanghai"
          }
        }
        """

        let rows = try comparableRows(left: left, right: right)
        #expect(rows.isEmpty)
    }

    @Test func sameObjectWithDifferentKeyOrderHasNoDiffRows() throws {
        let rows = try comparableRows(
            left: #"{"b":2,"a":{"d":4,"c":3}}"#,
            right: #"{"a":{"c":3,"d":4},"b":2}"#
        )

        #expect(rows.isEmpty)
    }

    @Test func changedValuesStillProduceRows() throws {
        let rows = try comparableRows(
            left: #"{"id":1,"name":"Alice","active":true,"plan":"free"}"#,
            right: #"{"id":1,"name":"Alice Zhang","active":false,"plan":"pro"}"#
        )

        #expect(rows.contains { $0.kind.isDifference })
    }

    @Test func displayTextForDiffMatchesComparableRows() throws {
        let source = #"{"b":2,"a":{"d":4,"c":3}}"#
        let display = try #require(JSONStructuralDiff.displayTextForDiff(source))
        let rows = try comparableRows(left: source, right: #"{"b":3,"a":{"d":4,"c":5}}"#)
        let visibleTexts = rows.flatMap { [$0.left?.text, $0.right?.text].compactMap(\.self) }

        #expect(display.contains(#""a": {"#))
        #expect(display.contains(#""c": 3"#))
        #expect(visibleTexts.contains { $0.contains(#""c": 5"#) })
    }

    @Test func addedAndRemovedFieldsStillProduceRows() throws {
        let left = #"{"id":1,"quota":100,"profile":{"city":"Shanghai","timezone":"Asia/Shanghai"}}"#
        let right = #"{"id":1,"profile":{"city":"Beijing"},"lastLoginAt":"2026-07-07T10:00:00+08:00"}"#

        let rows = try comparableRows(left: left, right: right)
        #expect(rows.contains { $0.kind.isDifference })
    }

    @Test func arrayOrderChangesStillProduceRows() throws {
        let rows = try comparableRows(
            left: #"{"ids":[1,2,3,4],"tags":["json","sql","xml"]}"#,
            right: #"{"ids":[4,3,2,1],"tags":["sql","json","xml"]}"#
        )

        #expect(rows.contains { $0.kind.isDifference })
    }

    @Test func arrayOrderChangesProduceNoRowsWhenIgnoreArrayOrderIsTrue() throws {
        let left = #"{"ids":[1,2,3,4],"tags":["json","sql","xml"]}"#
        let right = #"{"ids":[4,3,2,1],"tags":["sql","json","xml"]}"#
        let decision = try JSONStructuralDiff.cancellableAlignedDiff(
            left: left,
            right: right,
            labels: labels,
            options: JSONDiffOptions(ignoreArrayOrder: true)
        )
        guard case .comparable(let rows) = decision else {
            Issue.record("Expected comparable decision")
            return
        }
        #expect(rows.isEmpty)
    }

    @Test func reversedCanonicalEquivalentUnicodeArraysUseExactSortIdentity() throws {
        let composed = #""caf\u00e9""#
        let decomposed = #""cafe\u0301""#
        let left = "{\"values\":[\(composed),\(decomposed)]}"
        let right = "{\"values\":[\(decomposed),\(composed)]}"

        let decision = try JSONStructuralDiff.cancellableAlignedDiff(
            left: left,
            right: right,
            labels: labels,
            options: JSONDiffOptions(ignoreArrayOrder: true)
        )

        #expect(decision == .comparable([]))
    }

    @Test func typeDifferencesStillProduceRows() throws {
        let rows = try comparableRows(
            left: #"{"count":1,"enabled":true,"empty":null,"id":"001"}"#,
            right: #"{"count":"1","enabled":"true","empty":"","id":1}"#
        )

        #expect(rows.contains { $0.kind.isDifference })
    }

    @Test func canonicallyEquivalentUnicodeSequencesRemainDistinctJSONValues() throws {
        let rows = try comparableRows(
            left: #"{"value":"caf\u00e9"}"#,
            right: #"{"value":"cafe\u0301"}"#
        )

        let changed = try #require(rows.first { $0.kind.isDifference })
        #expect(changed.left?.segments.contains { $0.kind == .removed } == true)
        #expect(changed.right?.segments.contains { $0.kind == .added } == true)
    }

    @Test func invalidRightSideBlocksRows() throws {
        let decision = JSONStructuralDiff.alignedDiff(
            left: #"{"id":1,"name":"Alice"}"#,
            right: #"{"id":1,"name":"Alice",}"#,
            labels: labels
        )

        guard case .invalid(let message) = decision else {
            Issue.record("Expected invalid decision")
            return
        }
        #expect(message.contains("JSON B 格式错误"))
        #expect(message == "JSON B 格式错误：对象末尾多了逗号")
    }

    @Test func bothEmptyStaysQuiet() throws {
        #expect(JSONStructuralDiff.alignedDiff(left: "", right: "   \n", labels: labels) == .empty)
    }

    @Test func comparableJSONAboveDiffBudgetReturnsTooLargeDecision() throws {
        let decision = JSONStructuralDiff.alignedDiff(
            left: #"{"a":1}"#,
            right: #"{"a":2}"#,
            labels: labels,
            budget: LineDiffBudget(maximumLCSCells: 1)
        )

        #expect(decision == .tooLarge(LineDiffError.inputTooLargeMessage))
    }

    @Test func cancellableDiffPropagatesCancellationInsteadOfReportingTooLarge() {
        #expect(throws: CancellationError.self) {
            _ = try JSONStructuralDiff.cancellableAlignedDiff(
                left: #"{"a":1}"#,
                right: #"{"a":2}"#,
                labels: labels,
                shouldCancel: { true }
            )
        }
    }

    @Test func preparedDiffParsesEachNonemptySideOnceAndReusesOutputs() throws {
        let parserProbe = JSONParserStartProbe()
        let prepared = try JSONStructuralDiff.cancellablePreparedDiff(
            left: #"{"name":"first","name":"second","values":[2,1]}"#,
            right: #"{"name":"second","values":[1,2]}"#,
            labels: labels,
            options: JSONDiffOptions(ignoreArrayOrder: true),
            shouldCancel: { false },
            parserDidStart: parserProbe.record
        )

        #expect(parserProbe.count == 2)
        #expect(prepared.leftDisplayText?.contains(#""values": ["#) == true)
        #expect(prepared.rightDisplayText?.contains(#""values": ["#) == true)
        #expect(prepared.warning == "JSON A 含重复 key。")
        guard case .comparable = prepared.decision else {
            Issue.record("Expected comparable prepared result")
            return
        }
    }

    @Test func inputByteBudgetRejectsBeforeStartingEitherJSONParser() throws {
        let parserProbe = JSONParserStartProbe()
        let prepared = try JSONStructuralDiff.cancellablePreparedDiff(
            left: #"{"value":1}"#,
            right: #"{"value":2}"#,
            labels: labels,
            budget: LineDiffBudget(
                maximumLCSCells: 100,
                maximumInputBytesPerSide: 4
            ),
            shouldCancel: { false },
            parserDidStart: parserProbe.record
        )

        #expect(prepared.decision == .tooLarge(LineDiffError.inputTooLargeMessage))
        #expect(parserProbe.count == 0)
    }

    @Test func oneEmptySideStillCompares() throws {
        let rows = try comparableRows(left: "", right: #"{"id":1}"#)
        #expect(rows.contains { $0.kind.isDifference })
    }

    private func comparableRows(left: String, right: String) throws -> [DiffAlignedRow] {
        let decision = JSONStructuralDiff.alignedDiff(left: left, right: right, labels: labels)
        guard case .comparable(let rows) = decision else {
            Issue.record("Expected comparable decision, got \(decision)")
            return []
        }
        return rows
    }
}

private final class JSONParserStartProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var storedCount = 0

    var count: Int { lock.withLock { storedCount } }

    func record() {
        lock.withLock { storedCount += 1 }
    }
}
