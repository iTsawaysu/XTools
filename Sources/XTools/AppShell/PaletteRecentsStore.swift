import Foundation

/// Read-side usage scoring the palette ranks with (recents list + frecency
/// boost). MainActor-isolated because the write side (`PaletteRecentsStore`)
/// owns mutable state; the palette consumes it from its session model.
@MainActor
protocol PaletteUsageScoring {
    /// Exponential-decay frecency: each launch contributes 0.5^(age / 7 days),
    /// so a tool used twice today outranks one used once last week.
    func frecencyScore(for toolID: ToolID, now: Date) -> Double

    /// Distinct tools ordered by most-recent launch, oldest last.
    func recentToolIDs(limit: Int, now: Date) -> [ToolID]
}

/// Zero-usage stand-in: fresh installs and unit tests keep the registry's
/// curated ordering untouched.
struct NoPaletteUsage: PaletteUsageScoring {
    func frecencyScore(for toolID: ToolID, now: Date) -> Double {
        0
    }

    func recentToolIDs(limit: Int, now: Date) -> [ToolID] {
        []
    }
}

/// Raycast/Linear-style palette launch history: a capped ring of timestamped
/// tool activations, persisted through the shell preference store.
///
/// All tool selections record through `ToolNavigationActions.onToolSelected`
/// (palette, sidebar, dashboard and startup resume), so the recents surface
/// shares one mental model with the rest of the shell.
@MainActor
final class PaletteRecentsStore: PaletteUsageScoring {
    private struct LaunchEvent: Codable, Equatable {
        let toolID: String
        let epochSeconds: TimeInterval
    }

    private enum Metrics {
        /// One ring both in memory and on disk (~96 events ≈ 4KB JSON).
        static let eventCap = 96
        static let halfLifeDays: Double = 7
    }

    private var events: [LaunchEvent]
    private let preferences: ToolPreferenceStore?

    init(preferences: ToolPreferenceStore?) {
        self.preferences = preferences
        let stored = preferences?.value(for: AppShellPreferenceKeys.paletteRecents) ?? "[]"
        let decoder = JSONDecoder()
        self.events = (try? decoder.decode([LaunchEvent].self, from: Data(stored.utf8))) ?? []
    }

    func recordLaunch(_ toolID: ToolID, at date: Date = Date()) {
        events.append(
            LaunchEvent(toolID: toolID.rawValue, epochSeconds: date.timeIntervalSince1970)
        )
        if events.count > Metrics.eventCap {
            events.removeFirst(events.count - Metrics.eventCap)
        }
        persist()
    }

    /// Records a selection only when it differs from the immediately previous
    /// one. Startup resume can re-run `onAppear` when a window is reopened;
    /// the persisted ring must not grow with duplicate events in that case.
    func recordLaunchIfChanged(
        _ toolID: ToolID,
        previousToolID: ToolID? = nil,
        at date: Date = Date()
    ) {
        guard previousToolID != toolID,
              events.last?.toolID != toolID.rawValue
        else { return }
        recordLaunch(toolID, at: date)
    }

    func frecencyScore(for toolID: ToolID, now: Date) -> Double {
        let rawID = toolID.rawValue
        let nowSeconds = now.timeIntervalSince1970
        let halfLifeSeconds = Metrics.halfLifeDays * 24 * 3600

        var score: Double = 0
        for event in events where event.toolID == rawID {
            let age = max(0, nowSeconds - event.epochSeconds)
            score += pow(0.5, age / halfLifeSeconds)
        }
        return score
    }

    func recentToolIDs(limit: Int, now: Date) -> [ToolID] {
        guard limit > 0 else { return [] }

        var latestByTool: [String: LaunchEvent] = [:]
        for event in events {
            // Events append chronologically, so an unconditional write keeps
            // each tool's most recent launch — relaunching moves it to the
            // front of the recents ring.
            latestByTool[event.toolID] = event
        }

        return latestByTool
            .sorted { lhs, rhs in
                lhs.value.epochSeconds > rhs.value.epochSeconds
            }
            .prefix(limit)
            .map { ToolID(rawValue: $0.key) }
    }

    /// Serialized as one chunk; the in-memory ring caps the blob size.
    private func persist() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(events),
              let stored = String(data: data, encoding: .utf8)
        else { return }
        preferences?.set(stored, for: AppShellPreferenceKeys.paletteRecents)
    }
}
