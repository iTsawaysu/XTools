import Foundation
import Testing
@testable import XToolsCore

struct LineDifferTests {
    @Test func emptyInputs() {
        let result = LineDiffer.diff(left: "", right: "")
        #expect(result == "")
    }

    @Test func identicalInputs() {
        let text = "line1\nline2\nline3"
        let result = LineDiffer.diff(left: text, right: text)
        #expect(result.contains("共 0 行不同"))
        #expect(result.contains("  line1"))
        #expect(result.contains("  line2"))
        #expect(result.contains("  line3"))
    }

    @Test func addedLines() {
        let left = "line1\nline2"
        let right = "line1\nline2\nline3"
        let result = LineDiffer.diff(left: left, right: right)
        #expect(result.contains("共 1 行不同"))
        #expect(result.contains("  line1"))
        #expect(result.contains("  line2"))
        #expect(result.contains("+ line3"))
    }

    @Test func removedLines() {
        let left = "line1\nline2\nline3"
        let right = "line1\nline3"
        let result = LineDiffer.diff(left: left, right: right)

        // The differ shows both lines as changed since left[1]="line2" != right[1]="line3"
        #expect(result.contains("共 2 行不同"))
        #expect(result.contains("  line1"))
        #expect(result.contains("− line2"))
        #expect(result.contains("+ line3"))
    }

    @Test func mixedChanges() {
        let left = "unchanged\nold line\nanother unchanged"
        let right = "unchanged\nnew line\nanother unchanged"
        let result = LineDiffer.diff(left: left, right: right)
        #expect(result.contains("共 1 行不同"))
        #expect(result.contains("  unchanged"))
        #expect(result.contains("− old line"))
        #expect(result.contains("+ new line"))
        #expect(result.contains("  another unchanged"))
    }

    @Test func singleLineChange() {
        let left = "hello"
        let right = "world"
        let result = LineDiffer.diff(left: left, right: right)
        #expect(result.contains("共 1 行不同"))
        #expect(result.contains("− hello"))
        #expect(result.contains("+ world"))
    }

    @Test func emptyLineHandling() {
        let left = "line1\n\nline3"
        let right = "line1\n\nline3"
        let result = LineDiffer.diff(left: left, right: right)
        #expect(result.contains("共 0 行不同"))
        #expect(result.contains("  line1"))
        #expect(result.contains("  "))
        #expect(result.contains("  line3"))
    }

    @Test func displayDiffMarksInsertedLinesWithLineNumbers() {
        let lines = LineDiffer.displayDiff(left: "a\nb", right: "a\nb\nc")

        #expect(lines.count == 3)
        #expect(lines[0].kind == .unchanged)
        #expect(lines[0].oldLineNumber == 1)
        #expect(lines[0].newLineNumber == 1)
        #expect(lines[2].kind == .added)
        #expect(lines[2].oldLineNumber == nil)
        #expect(lines[2].newLineNumber == 3)
        #expect(lines[2].text == "c")
    }

    @Test func displayDiffMarksReplacementAsRemovedThenAdded() {
        let lines = LineDiffer.displayDiff(left: "a\nold\nz", right: "a\nnew\nz")

        #expect(lines.count == 4)
        #expect(lines[1].kind == .removed)
        #expect(lines[1].oldLineNumber == 2)
        #expect(lines[1].newLineNumber == nil)
        #expect(lines[1].text == "old")
        #expect(lines[2].kind == .added)
        #expect(lines[2].oldLineNumber == nil)
        #expect(lines[2].newLineNumber == 2)
        #expect(lines[2].text == "new")
    }

    @Test func alignedDiffPairsReplacementRows() {
        let rows = LineDiffer.alignedDiff(left: "a\nold\nz", right: "a\nnew\nz")

        #expect(rows.count == 3)
        #expect(rows[1].kind == .changed)
        #expect(rows[1].left?.lineNumber == 2)
        #expect(rows[1].right?.lineNumber == 2)
        #expect(rows[1].left?.text == "old")
        #expect(rows[1].right?.text == "new")
        #expect(rows[1].left?.segments == [DiffTextSegment(text: "old", kind: .removed)])
        #expect(rows[1].right?.segments == [DiffTextSegment(text: "new", kind: .added)])
    }

    @Test func alignedDiffHighlightsInlineChanges() {
        let rows = LineDiffer.alignedDiff(left: "delete", right: "delesdfsdfe")

        #expect(rows.count == 1)
        #expect(rows[0].kind == .changed)
        #expect(rows[0].left?.segments.contains(DiffTextSegment(text: "dele", kind: .unchanged)) == true)
        #expect(rows[0].left?.segments.contains { $0.kind == .removed } == true)
        #expect(rows[0].right?.segments.contains { $0.kind == .added && $0.text.contains("sdfsd") } == true)
    }

    @Test func alignedDiffKeepsSharedMiddleWhenOnlyRightInsertsCharacters() {
        let rows = LineDiffer.alignedDiff(left: "abcdef", right: "abXYcdZef")

        #expect(rows.count == 1)
        #expect(rows[0].kind == .changed)
        #expect(rows[0].left?.segments == [
            DiffTextSegment(text: "abcdef", kind: .unchanged)
        ])
        #expect(rows[0].right?.segments == [
            DiffTextSegment(text: "ab", kind: .unchanged),
            DiffTextSegment(text: "XY", kind: .added),
            DiffTextSegment(text: "cd", kind: .unchanged),
            DiffTextSegment(text: "Z", kind: .added),
            DiffTextSegment(text: "ef", kind: .unchanged)
        ])
    }

    @Test func alignedDiffMarksOnlyReplacedInlineCharacters() {
        let rows = LineDiffer.alignedDiff(left: "abXcd", right: "abYcd")

        #expect(rows.count == 1)
        #expect(rows[0].kind == .changed)
        #expect(rows[0].left?.segments == [
            DiffTextSegment(text: "ab", kind: .unchanged),
            DiffTextSegment(text: "X", kind: .removed),
            DiffTextSegment(text: "cd", kind: .unchanged)
        ])
        #expect(rows[0].right?.segments == [
            DiffTextSegment(text: "ab", kind: .unchanged),
            DiffTextSegment(text: "Y", kind: .added),
            DiffTextSegment(text: "cd", kind: .unchanged)
        ])
    }

    @Test func alignedDiffDoesNotPairInsertedLinesWithLaterLongChanges() throws {
        let leftLongDiagnostic = "开发者工具应优先给出清晰、可恢复、可理解的错误信息。格式化工具尤其不能在输入非法时伪造成功结果，因为这会让用户把错误数据复制到生产配置中。"
        let rightLongDiagnostic = "开发者工具应优先给出清晰、可恢复、可理解的错误信息。格式化工具不能在输入非法时伪造成功结果，因为这会让用户把错误数据复制到生产配置中。"
        let leftLongLayout = "对于较长文本，差异视图需要保持滚动同步、行号稳定，并且不要因为一行很长就破坏整体布局。"
        let rightLongLayout = "对于较长文本，差异视图需要保持滚动同步、行号稳定，并且不要因为某一行特别长就破坏整体布局。"

        let rows = LineDiffer.alignedDiff(
            left: """
            Hello world
            This line is unchanged.
            最后一行中文。
            hello world
            name:  Alice
            path:/Users/sun/project
            line 1: keep
            line 2: remove me
            line 3: move later
            line 4: keep
            \(leftLongDiagnostic)
            \(leftLongLayout)
            """,
            right: """
            Hello world
            This line is unchanged.
            最后一行中文。
            Hello World
            name: Alice
            path: /Users/sun/project
            line 1: keep
            line 4: keep
            line 3: move later
            line 5: new line
            \(rightLongDiagnostic)
            \(rightLongLayout)
            """
        )

        #expect(rows.contains {
            $0.kind == .changed
                && $0.left?.text == "hello world"
                && $0.right?.text == "Hello World"
        })
        #expect(rows.contains {
            $0.kind == .changed
                && $0.left?.text == "name:  Alice"
                && $0.right?.text == "name: Alice"
        })
        #expect(rows.contains {
            $0.kind == .changed
                && $0.left?.text == "path:/Users/sun/project"
                && $0.right?.text == "path: /Users/sun/project"
        })

        let removedLine = try #require(rows.first { $0.left?.text == "line 2: remove me" })
        #expect(removedLine.kind == .removed)
        #expect(removedLine.right == nil)

        let addedLine = try #require(rows.first { $0.right?.text == "line 5: new line" })
        #expect(addedLine.kind == .added)
        #expect(addedLine.left == nil)

        let diagnosticRow = try #require(rows.first { $0.left?.text == leftLongDiagnostic })
        #expect(diagnosticRow.kind == .changed)
        #expect(diagnosticRow.right?.text == rightLongDiagnostic)
        #expect(diagnosticRow.left?.segments.contains {
            $0.kind == .removed && $0.text.contains("尤其")
        } == true)

        let layoutRow = try #require(rows.first { $0.left?.text == leftLongLayout })
        #expect(layoutRow.kind == .changed)
        #expect(layoutRow.right?.text == rightLongLayout)
        #expect(layoutRow.right?.segments.contains {
            $0.kind == .added && $0.text.contains("某")
        } == true)
        #expect(layoutRow.right?.segments.contains {
            $0.kind == .added && $0.text.contains("特别")
        } == true)
        #expect(layoutRow.left?.segments.contains {
            $0.kind == .removed && $0.text.contains("很")
        } == true)

        #expect(!rows.contains {
            $0.kind == .changed
                && ($0.left?.text == leftLongDiagnostic || $0.left?.text == leftLongLayout)
                && ($0.right?.text == "line 3: move later" || $0.right?.text == "line 5: new line")
        })
    }

    @Test func safeAlignedDiffRejectsInputsAboveMatrixBudgetBeforeDiffing() throws {
        #expect(LineDiffBudget.estimatedLCSCells(leftLineCount: 2, rightLineCount: 3) == 12)
        #expect(throws: LineDiffError.inputTooLarge(
            leftLineCount: 2,
            rightLineCount: 3,
            maximumLCSCells: 11
        )) {
            _ = try LineDiffer.safeAlignedDiff(
                left: "a\nb",
                right: "a\nb\nc",
                budget: LineDiffBudget(maximumLCSCells: 11)
            )
        }

        let rows = try LineDiffer.safeAlignedDiff(
            left: "a\nold\nz",
            right: "a\nnew\nz",
            budget: LineDiffBudget(maximumLCSCells: 16)
        )
        #expect(rows.count == 3)
        #expect(LineDiffError.inputTooLarge(
            leftLineCount: 2,
            rightLineCount: 3,
            maximumLCSCells: 11
        ).errorDescription == "对比内容过大，无法计算。")
    }

    @Test func safeAlignedDiffPropagatesCancellationWithoutRows() {
        #expect(throws: CancellationError.self) {
            _ = try LineDiffer.safeAlignedDiff(
                left: "left",
                right: "right",
                shouldCancel: { true }
            )
        }
    }

    @Test func dynamicRowAlignmentCooperativelyCancels() {
        let removed = (1...40).map { (index: Int) in
            DiffDisplayLine(
                kind: .removed,
                oldLineNumber: index,
                newLineNumber: nil,
                text: "shared token old value \(index)",
                indent: 0
            )
        }
        let added = (1...40).map { (index: Int) in
            DiffDisplayLine(
                kind: .added,
                oldLineNumber: nil,
                newLineNumber: index,
                text: "shared token new value \(index)",
                indent: 0
            )
        }
        let probe = DiffCancellationProbe(cancelAfterCheck: 8)

        #expect(throws: CancellationError.self) {
            _ = try DiffAlignedRow.pairedRows(
                removed: removed,
                added: added,
                cancellation: DiffCancellationChecker(shouldCancel: probe.shouldCancel)
            )
        }
        #expect(probe.checkCount >= 8)
    }

    @Test func inlineDiffCooperativelyCancels() {
        let left = String(repeating: "ab", count: 150)
        let right = String(repeating: "ac", count: 150)
        let probe = DiffCancellationProbe(cancelAfterCheck: 8)

        #expect(throws: CancellationError.self) {
            _ = try DiffAlignedRow.inlineSegments(
                left: left,
                right: right,
                cancellation: DiffCancellationChecker(shouldCancel: probe.shouldCancel)
            )
        }
        #expect(probe.checkCount >= 8)
    }

    @Test func inlineLCSCancelsWithinASingleOuterRow() {
        let probe = DiffCancellationProbe(cancelAfterCheck: 4)

        #expect(throws: CancellationError.self) {
            _ = try DiffAlignedRow.inlineLCSLengths(
                left: ["a"],
                right: Array(repeating: "b", count: 2_000),
                cancellation: DiffCancellationChecker(shouldCancel: probe.shouldCancel)
            )
        }
        #expect(probe.checkCount >= 4)
    }

    @Test func displayDiffPreservesEmptyLines() {
        let lines = LineDiffer.displayDiff(left: "a\n\nb", right: "a\n\nc")

        #expect(lines.count == 4)
        #expect(lines[1].kind == .unchanged)
        #expect(lines[1].text == "")
        #expect(lines[1].oldLineNumber == 2)
        #expect(lines[1].newLineNumber == 2)
    }

    @Test func treatsCRLFAsOneLineSeparator() {
        let lf = "one\ntwo\nthree"
        let crlf = "one\r\ntwo\r\nthree"

        #expect(LineDiffer.displayDiff(left: lf, right: crlf).allSatisfy { !$0.kind.isDifference })
        #expect(LineDiffer.alignedDiff(left: lf, right: crlf).allSatisfy { !$0.kind.isDifference })
    }

    @Test func displayDiffMarksWholeRightAsAddedWhenLeftIsEmpty() {
        let lines = LineDiffer.displayDiff(left: "", right: "a\nb")

        #expect(lines.count == 2)
        #expect(lines.allSatisfy { $0.kind == .added && $0.oldLineNumber == nil })
        #expect(lines[0].newLineNumber == 1)
        #expect(lines[1].newLineNumber == 2)
    }

    @Test func diffDisplayFilteringDoesNotParseTextPrefixes() {
        let lines = [
            DiffDisplayLine(kind: .unchanged, oldLineNumber: 1, newLineNumber: 1, text: "+ literal plus", indent: 0),
            DiffDisplayLine(kind: .added, oldLineNumber: nil, newLineNumber: 2, text: "added", indent: 0),
            DiffDisplayLine(kind: .structure, oldLineNumber: 2, newLineNumber: 3, text: "}", indent: 0)
        ]

        let textFiltered = lines.diffFiltered(preservesStructure: false)
        #expect(textFiltered.count == 1)
        #expect(textFiltered[0].text == "added") // filtering uses line kind, not text prefix

        let jsonFiltered = lines.diffFiltered(preservesStructure: true)
        #expect(jsonFiltered.count == 2)
        #expect(jsonFiltered[1].kind == .structure)
    }
}

private final class DiffCancellationProbe: @unchecked Sendable {
    private let lock = NSLock()
    private let cancelAfterCheck: Int
    private var storedCheckCount = 0

    init(cancelAfterCheck: Int) {
        self.cancelAfterCheck = cancelAfterCheck
    }

    var checkCount: Int {
        lock.withLock { storedCheckCount }
    }

    func shouldCancel() -> Bool {
        lock.withLock {
            storedCheckCount += 1
            return storedCheckCount >= cancelAfterCheck
        }
    }
}
