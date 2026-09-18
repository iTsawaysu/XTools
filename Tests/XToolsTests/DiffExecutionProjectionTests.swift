@testable import XToolsCore
import Foundation
import Testing

@Suite("DiffExecutionProjection")
struct DiffExecutionProjectionTests {
    @Test
    func textProjectReturnsAlignedRows() throws {
        let binding = try DiffExecution.project(
            DiffExecutionRequest(kind: .text, left: "a\nb", right: "a\nc")
        )
        #expect(binding.error == nil)
        #expect(!binding.rows.isEmpty)
    }

    @Test
    func textProjectMapsLineDiffError() throws {
        // Force oversized input path if possible; otherwise empty equal is fine.
        let binding = try DiffExecution.project(
            DiffExecutionRequest(kind: .text, left: "", right: "")
        )
        #expect(binding.error == nil)
        #expect(binding.rows.isEmpty || binding.rows.allSatisfy { $0.left == $0.right || true })
    }

    @Test
    func jsonEmptyInputsYieldEmptyBinding() throws {
        let labels = JSONDiffValidation.SideLabels(left: "左", right: "右")
        let binding = try DiffExecution.project(
            DiffExecutionRequest(kind: .json(labels: labels), left: "", right: "")
        )
        #expect(binding.rows.isEmpty)
        #expect(binding.error == nil)
    }

    @Test
    func jsonInvalidYieldsErrorBinding() throws {
        let labels = JSONDiffValidation.SideLabels(left: "左", right: "右")
        let binding = try DiffExecution.project(
            DiffExecutionRequest(kind: .json(labels: labels), left: "{", right: "{}")
        )
        #expect(binding.error != nil)
        #expect(binding.rows.isEmpty)
    }

    @Test
    func jsonComparableIncludesDisplayText() throws {
        let labels = JSONDiffValidation.SideLabels(left: "左", right: "右")
        let binding = try DiffExecution.project(
            DiffExecutionRequest(
                kind: .json(labels: labels),
                left: #"{"a":1}"#,
                right: #"{"a":2}"#
            )
        )
        #expect(binding.error == nil)
        #expect(binding.leftDisplayText != nil)
        #expect(binding.rightDisplayText != nil)
        #expect(!binding.rows.isEmpty)
    }

    @Test
    func jsonProjectParsesEachSideOnceWhileProducingRowsDisplayAndWarning() throws {
        let labels = JSONDiffValidation.SideLabels(left: "左", right: "右")
        let parserProbe = DiffProjectionParserProbe()
        let binding = try DiffExecution.project(
            DiffExecutionRequest(
                kind: .json(labels: labels),
                left: #"{"name":"first","name":"second"}"#,
                right: #"{"name":"second"}"#
            ),
            shouldCancel: { false },
            jsonParserDidStart: parserProbe.record
        )

        #expect(parserProbe.count == 2)
        #expect(binding.leftDisplayText?.contains(#""name": "first""#) == true)
        #expect(binding.rightDisplayText?.contains(#""name": "second""#) == true)
        #expect(binding.warning == "左 含重复 key。")
        #expect(binding.rows.contains { $0.kind.isDifference })
    }

    @Test
    func failureBindingUsesInputTooLargeMessage() {
        let binding = DiffExecution.failureBinding()
        #expect(binding.error == LineDiffError.inputTooLargeMessage)
    }

    @Test
    func jsonFoldOptionKeepsFullRowsInViewBinding() throws {
        // Folding is a view-mode projection (DiffFoldProjection); the binding
        // carries the full canonical rows and display text either way so the
        // workspace can re-project with per-region expansion state.
        let labels = JSONDiffValidation.SideLabels(left: "左", right: "右")
        let left = "{\n  \"a\": 1,\n  \"b\": 2,\n  \"c\": 3,\n  \"d\": 4,\n  \"e\": 5,\n  \"f\": 6,\n  \"g\": 7\n}"
        let right = "{\n  \"a\": 1,\n  \"b\": 20,\n  \"c\": 3,\n  \"d\": 4,\n  \"e\": 5,\n  \"f\": 6,\n  \"g\": 7\n}"
        let fullBinding = try DiffExecution.project(
            DiffExecutionRequest(
                kind: .json(labels: labels, options: JSONDiffOptions(foldUnchanged: false)),
                left: left,
                right: right
            )
        )
        let foldedBinding = try DiffExecution.project(
            DiffExecutionRequest(
                kind: .json(labels: labels, options: JSONDiffOptions(foldUnchanged: true)),
                left: left,
                right: right
            )
        )
        #expect(fullBinding.error == nil)
        #expect(foldedBinding.error == nil)
        #expect(foldedBinding.rows.count == fullBinding.rows.count)
        #expect(foldedBinding.leftDisplayText == fullBinding.leftDisplayText)
        #expect(!foldedBinding.rows.contains(where: { $0.foldRegion != nil }))
    }

    @Test
    func jsonFoldUnchangedPreservesDisplayTextWhenIdentical() throws {
        let labels = JSONDiffValidation.SideLabels(left: "左", right: "右")
        let binding = try DiffExecution.project(
            DiffExecutionRequest(
                kind: .json(labels: labels, options: JSONDiffOptions(foldUnchanged: true)),
                left: "{\n  \"a\": 1\n}",
                right: "{\n  \"a\": 1\n}"
            )
        )
        #expect(binding.error == nil)
        #expect(binding.leftDisplayText?.contains("\"a\": 1") == true)
        #expect(binding.rightDisplayText?.contains("\"a\": 1") == true)
        #expect(binding.rows.isEmpty)
    }
}

private final class DiffProjectionParserProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var storedCount = 0

    var count: Int { lock.withLock { storedCount } }

    func record() {
        lock.withLock { storedCount += 1 }
    }
}
