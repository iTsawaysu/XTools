import XToolsCore

@available(*, unavailable, message: "Use IndexJSONDiffPage with IndexEditableDiffWorkspace. Legacy JSON diff result pages are retired.")
struct JSONDiffResult {
    let rows: [DiffAlignedRow]
}

@available(*, unavailable, message: "Use IndexJSONDiffPage with IndexEditableDiffWorkspace. Legacy JSON diff result pages are retired.")
struct JSONDiffResultView {}
