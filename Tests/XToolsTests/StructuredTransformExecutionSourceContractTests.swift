import Foundation
@testable import XTools
import Testing

struct StructuredTransformExecutionSourceContractTests {
    @Test func targetPagesUseOneSharedOffMainExecutionSession() throws {
        let formatSession = try readSource("Sources/XTools/ToolPages/Workbench/Diagnostics/IndexFormatExecutionSession.swift")
        let session = try readSource("Sources/XToolsCore/Utility/SupersedingExecutionSession.swift")
        let worker = try readSource("Sources/XToolsCore/Utility/SupersedingDetachedWorker.swift")
        let workbench = try readSource("Sources/XTools/ToolPages/Workbench/Text/IndexFormatWorkbench.swift")
        contains(session, "SupersedingDetachedWorker(", "Structured transforms must use the shared superseding detached worker")
        contains(formatSession, "cancelInFlight: true", "Structured transforms must cancel superseded in-flight work (latest-wins), not keep running old work")
        contains(worker, "Task.detached(priority: .userInitiated)", "Structured transforms must execute off the main actor")
        contains(worker, "minimumGeneration", "Structured transforms must reject stale generations")
        contains(session, "worker.invalidate(before: currentGeneration)", "A newer schedule must invalidate an already-pending obsolete request before debounce")
        contains(formatSession, "@Published private(set) var isOutputFresh", "Shared execution must publish output freshness")
        contains(formatSession, "var hasStaleResult: Bool", "Freshness must distinguish retained stale output from an empty session")
        contains(formatSession, "func sourceDidChange()", "Input edits must invalidate work without presenting an old result as current")
        contains(workbench, ".disabled(!isOutputFresh)", "Copy and save actions must reject stale output")
        contains(workbench, "hasStaleResult ? \"\\(outputTitle)，结果已过期\" : outputTitle", "An empty output surface must not be announced as stale")
        contains(workbench, "isRunning || input.trimmingCharacters", "Empty or active work must disable the primary action")

        for path in [
            "Sources/XTools/ToolPages/Development/JSONFormatterPage.swift",
            "Sources/XTools/ToolPages/Development/SQLPrettifyPage.swift",
            "Sources/XTools/ToolPages/Development/XMLFormatterPage.swift",
            "Sources/XTools/ToolPages/Development/YAMLPrettifyPage.swift",
            "Sources/XTools/ToolPages/Development/DockerRunToComposePage.swift"
        ] {
            let source = try readSource(path)
            contains(source, "IndexFormatExecutionSession", "\(path) must observe the shared execution session")
            contains(source, "execution.schedule", "\(path) must submit an immutable snapshot to the shared session")
            contains(source, "execution.sourceDidChange()", "\(path) must mark retained output stale when input changes")
            contains(source, "isRunning: execution.isRunning", "\(path) must surface shared running state")
            contains(source, "isOutputFresh: execution.isOutputFresh", "\(path) must surface shared result freshness")
            doesNotContain(source, "workspace.debouncer", "\(path) must not keep a page-local debounce path")
        }
    }

    @Test func structuredTransformPagesKeepWorkbenchAndMotionBoundaries() throws {
        let workbench = try readSource("Sources/XTools/ToolPages/Workbench/Text/IndexTextConversionWorkbench.swift")
        contains(workbench, "fixed equal horizontal pair", "Structured transforms must keep the existing equal split workbench")

        for path in [
            "Sources/XTools/ToolPages/Development/JSONFormatterPage.swift",
            "Sources/XTools/ToolPages/Development/SQLPrettifyPage.swift",
            "Sources/XTools/ToolPages/Development/XMLFormatterPage.swift",
            "Sources/XTools/ToolPages/Development/YAMLPrettifyPage.swift",
            "Sources/XTools/ToolPages/Development/DockerRunToComposePage.swift"
        ] {
            let source = try readSource(path)
            doesNotContain(source, "outputProcessingText:", "\(path) must not introduce a new processing UI")
            contains(source, "IndexFormatWorkbench", "\(path) must keep the shared prototype workbench")
        }
    }
}
