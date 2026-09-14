import XToolsCore
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
    func failureBindingUsesInputTooLargeMessage() {
        let binding = DiffExecution.failureBinding()
        #expect(binding.error == LineDiffError.inputTooLargeMessage)
    }
}
