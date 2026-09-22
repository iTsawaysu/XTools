import Foundation
import SwiftUI

#if DEBUG
import AppKit
import os
#endif

struct ToolPageEntryTraceContext: Equatable, Sendable {
    let toolID: ToolID
    let title: String
}

private struct ToolPageEntryTraceContextKey: EnvironmentKey {
    static let defaultValue: ToolPageEntryTraceContext? = nil
}

extension EnvironmentValues {
    var toolPageEntryTraceContext: ToolPageEntryTraceContext? {
        get { self[ToolPageEntryTraceContextKey.self] }
        set { self[ToolPageEntryTraceContextKey.self] = newValue }
    }
}

@MainActor
enum ToolPageEntryTrace {
#if DEBUG
    private static let log = OSLog(
        subsystem: Bundle.main.bundleIdentifier ?? "XTools",
        category: "ToolPageEntry"
    )
    private static var activeEntryIDs: [ToolID: OSSignpostID] = [:]
    private static var activeFocusIDs: [String: OSSignpostID] = [:]
    private static var focusPendingToolIDs: Set<ToolID> = []
    private static var entryStartedAt: [ToolID: ContinuousClock.Instant] = [:]

    private static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["TOOLS_TOOL_PAGE_TRACE"] == "1"
            || ProcessInfo.processInfo.environment["TOOLS_TOOL_PAGE_BENCHMARK"] == "1"
    }

    private static var isBenchmarkEnabled: Bool {
        ProcessInfo.processInfo.environment["TOOLS_TOOL_PAGE_BENCHMARK"] == "1"
    }
#endif

    static func toolSelected(_ tool: RegisteredTool) {
#if DEBUG
        guard isEnabled else { return }

        if let existingID = activeEntryIDs[tool.id] {
            os_signpost(
                .end,
                log: log,
                name: "Tool Page Entry",
                signpostID: existingID,
                "tool=%{public}@ status=%{public}@",
                tool.id.rawValue as NSString,
                "interrupted" as NSString
            )
        }

        let signpostID = OSSignpostID(log: log)
        activeEntryIDs[tool.id] = signpostID
        entryStartedAt[tool.id] = .now
        os_signpost(
            .begin,
            log: log,
            name: "Tool Page Entry",
            signpostID: signpostID,
            "tool=%{public}@ title=%{public}@",
            tool.id.rawValue as NSString,
            tool.title as NSString
        )
#endif
    }

    static func makePageStarted(_ tool: RegisteredTool) {
#if DEBUG
        guard isEnabled, let signpostID = activeEntryIDs[tool.id] else { return }
        os_signpost(
            .event,
            log: log,
            name: "Tool Make Page Started",
            signpostID: signpostID,
            "tool=%{public}@",
            tool.id.rawValue as NSString
        )
#endif
    }

    static func makePageFinished(_ tool: RegisteredTool) {
#if DEBUG
        guard isEnabled, let signpostID = activeEntryIDs[tool.id] else { return }
        os_signpost(
            .event,
            log: log,
            name: "Tool Make Page Finished",
            signpostID: signpostID,
            "tool=%{public}@",
            tool.id.rawValue as NSString
        )
#endif
    }

    static func pageAppeared(_ context: ToolPageEntryTraceContext) {
#if DEBUG
        guard isEnabled, let signpostID = activeEntryIDs[context.toolID] else { return }
        os_signpost(
            .event,
            log: log,
            name: "Tool Page Appeared",
            signpostID: signpostID,
            "tool=%{public}@ title=%{public}@",
            context.toolID.rawValue as NSString,
            context.title as NSString
        )
        emitBenchmarkPhaseMeasurement(context, phase: "appeared")

        guard !focusPendingToolIDs.contains(context.toolID) else { return }
        endEntryIfActive(context, status: "page-visible")
#endif
    }

    static func inputFocusRequested(_ context: ToolPageEntryTraceContext?, placeholder: String) {
#if DEBUG
        guard isEnabled, let context, let entryID = activeEntryIDs[context.toolID] else { return }
        let focusKey = focusKey(for: context, placeholder: placeholder)
        let focusID = OSSignpostID(log: log)
        focusPendingToolIDs.insert(context.toolID)
        activeFocusIDs[focusKey] = focusID
        os_signpost(
            .begin,
            log: log,
            name: "Tool Primary Input Focus",
            signpostID: focusID,
            "tool=%{public}@ placeholder=%{public}@",
            context.toolID.rawValue as NSString,
            placeholder as NSString
        )
        os_signpost(
            .event,
            log: log,
            name: "Tool Primary Input Focus Requested",
            signpostID: entryID,
            "tool=%{public}@ placeholder=%{public}@",
            context.toolID.rawValue as NSString,
            placeholder as NSString
        )
#endif
    }

    static func inputFocusCompleted(_ context: ToolPageEntryTraceContext?, placeholder: String) {
#if DEBUG
        guard isEnabled, let context else { return }

        let focusKey = focusKey(for: context, placeholder: placeholder)
        if let focusID = activeFocusIDs.removeValue(forKey: focusKey) {
            os_signpost(
                .end,
                log: log,
                name: "Tool Primary Input Focus",
                signpostID: focusID,
                "tool=%{public}@ placeholder=%{public}@",
                context.toolID.rawValue as NSString,
                placeholder as NSString
            )
        }

        if let entryID = activeEntryIDs.removeValue(forKey: context.toolID) {
            os_signpost(
                .end,
                log: log,
                name: "Tool Page Entry",
                signpostID: entryID,
                "tool=%{public}@ status=%{public}@",
                context.toolID.rawValue as NSString,
                "primary-input-ready" as NSString
            )
            emitBenchmarkReadyMeasurement(context)
        }
        focusPendingToolIDs.remove(context.toolID)
#endif
    }

#if DEBUG
    private static func focusKey(for context: ToolPageEntryTraceContext, placeholder: String) -> String {
        "\(context.toolID.rawValue)\u{0}\(placeholder)"
    }

    private static func endEntryIfActive(_ context: ToolPageEntryTraceContext, status: String) {
        guard let entryID = activeEntryIDs.removeValue(forKey: context.toolID) else { return }
        os_signpost(
            .end,
            log: log,
            name: "Tool Page Entry",
            signpostID: entryID,
            "tool=%{public}@ status=%{public}@",
            context.toolID.rawValue as NSString,
            status as NSString
        )
        emitBenchmarkReadyMeasurement(context)
    }

    private static func emitBenchmarkPhaseMeasurement(_ context: ToolPageEntryTraceContext, phase: String) {
        guard isBenchmarkEnabled,
              let startedAt = entryStartedAt[context.toolID]
        else {
            return
        }

        let line = String(
            format: "TOOL_PAGE_ENTRY_PHASE_RESULT tool=%@ title=%@ phase=%@ milliseconds=%.3f\n",
            context.toolID.rawValue,
            context.title,
            phase,
            startedAt.duration(to: .now).milliseconds
        )
        FileHandle.standardError.write(Data(line.utf8))
    }

    private static func emitBenchmarkReadyMeasurement(_ context: ToolPageEntryTraceContext) {
        guard isBenchmarkEnabled,
              let startedAt = entryStartedAt.removeValue(forKey: context.toolID)
        else {
            return
        }

        emitBenchmarkPhaseMeasurement(context, phase: "ready", startedAt: startedAt)
        let line = String(
            format: "TOOL_PAGE_ENTRY_RESULT tool=%@ title=%@ milliseconds=%.3f\n",
            context.toolID.rawValue,
            context.title,
            startedAt.duration(to: .now).milliseconds
        )
        FileHandle.standardError.write(Data(line.utf8))
    }

    private static func emitBenchmarkPhaseMeasurement(_ context: ToolPageEntryTraceContext, phase: String, startedAt: ContinuousClock.Instant) {
        guard isBenchmarkEnabled else { return }

        let line = String(
            format: "TOOL_PAGE_ENTRY_PHASE_RESULT tool=%@ title=%@ phase=%@ milliseconds=%.3f\n",
            context.toolID.rawValue,
            context.title,
            phase,
            startedAt.duration(to: .now).milliseconds
        )
        FileHandle.standardError.write(Data(line.utf8))
    }

#endif
}

@MainActor
enum ToolPageEntryBenchmark {
#if DEBUG
    private static var didStart = false
#endif

    static func runIfRequested(
        registry: ToolRegistry,
        navigationActions: ToolNavigationActions
    ) {
#if DEBUG
        guard ProcessInfo.processInfo.environment["TOOLS_TOOL_PAGE_BENCHMARK"] == "1",
              !didStart
        else {
            return
        }
        didStart = true

        let tools = benchmarkQueries.compactMap {
            registry.tool(for: ToolID(rawValue: $0)) ?? registry.matchingTools(query: $0).first
        }
        guard tools.count == benchmarkQueries.count else {
            FileHandle.standardError.write(Data("TOOL_PAGE_ENTRY_BENCHMARK_ERROR missing-tools\n".utf8))
            NSApp.terminate(nil)
            return
        }

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            for _ in 0..<5 {
                for tool in tools {
                    _ = navigationActions.selectTool(tool.id)
                    try? await Task.sleep(for: .milliseconds(700))
                }
            }
            try? await Task.sleep(for: .milliseconds(500))
            NSApp.terminate(nil)
        }
#endif
    }

#if DEBUG
    private static var benchmarkQueries: [String] {
        guard let rawValue = ProcessInfo.processInfo.environment["TOOLS_TOOL_PAGE_BENCHMARK_QUERIES"] else {
            return ["roman", "http", "color"]
        }

        let queries = rawValue
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return queries.isEmpty ? ["roman", "http", "color"] : queries
    }
#endif

}
