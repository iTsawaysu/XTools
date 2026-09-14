import XToolsCore
import Testing

struct TextDiffTests {
    @Test func reportsChangedLines() {
        let output = LineDiffer.diff(left: "a\nb", right: "a\nc")

        #expect(
            output ==
            """
            共 1 行不同

              a
            − b
            + c
            """
        )
    }
}
