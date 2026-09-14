enum IndexDiffSyntax {
    case plain
    case json
}

@available(*, unavailable, message: "Use IndexEditableDiffWorkspace. The legacy side-by-side diff reader is retired.")
struct IndexSideBySideDiffReader {}
