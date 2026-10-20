import SwiftUI
import XToolsDesign

/// Whole-page identity for the 01 景深沉降 transition: a tool page, the
/// personal dashboard, or the empty selection state. The stage treats every
/// branch as one page kind so all four navigation paths (sidebar row, ⌘0,
/// dashboard shortcut card, ⌘K) share one choreography — the dashboard used
/// to fall back to a bare crossfade because it sat outside the tool-page
/// branch.
struct ToolPageKey: Hashable {
    enum Payload: Hashable {
        case tool(ToolID)
        case dashboard
        case emptySelection
    }

    let payload: Payload

    static func tool(_ id: ToolID) -> ToolPageKey {
        ToolPageKey(payload: .tool(id))
    }

    static let dashboard = ToolPageKey(payload: .dashboard)
    static let emptySelection = ToolPageKey(payload: .emptySelection)
}

/// Page stage choreography, selected by `ToolPageTransitionIntent`:
/// - `depth`: incoming rises 10pt from 99.5% (300ms smoothOut), outgoing sinks
///   to 99.2% while fading (220ms productiveExit).
/// - `sharedAxis`: cross-category pages swap on one axis (incoming 18pt below at
///   1.04, outgoing 12pt above at 0.96).
/// - `originBloom`: palette launches expand from the top edge (0.94 -> 1,
///   420ms smoothOut).
/// Reduce Motion and the first mount swap immediately.
///
/// Pages keep the same modifier structure while only pose values change.
/// The arrival start is installed before the page's generation task makes it
/// visible; a stale task cannot complete a newer navigation. Each page chooses
/// its own arrival/departure timing. Reduce Motion swaps directly without parked
/// pages, and the first mount never animates.
@MainActor
struct ToolPageStage<Page: View>: View {
    let target: ToolPageKey
    var intent: ToolPageTransitionIntent = .depth
    @ViewBuilder let page: (ToolPageKey) -> Page

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var model = ToolPageStageModel()
    @State private var activeIntent: ToolPageTransitionIntent = .depth

    private var displayed: ToolPageKey? { model.displayed }

    var body: some View {
        ZStack {
            ForEach(model.mounted, id: \.self) { key in
                stagedPageView(for: key)
            }
        }
        .onAppear {
            guard displayed == nil else { return }
            activeIntent = intent
            swapImmediately(to: target)
        }
        .onChange(of: target) { newKey in
            activeIntent = intent
            navigate(to: newKey)
        }
        .onChange(of: reduceMotion) { enabled in
            if enabled { swapImmediately(to: target) }
        }
    }

    @ViewBuilder
    private func stagedPageView(for key: ToolPageKey) -> some View {
        let isCurrent = (key == displayed)
        let pagePose = pose(for: key)
        let gen = isCurrent ? model.generation : 0
        let zIndexValue: Double = isCurrent ? 1 : 0

        page(key)
            .modifier(ToolPageParkingModifier(pose: pagePose, intent: activeIntent, reduceMotion: reduceMotion))
            .zIndex(zIndexValue)
            .allowsHitTesting(isCurrent)
            .accessibilityHidden(!isCurrent)
            .environment(\.toolPageEntryGeneration, gen)
            .task(id: gen) {
                guard gen > 0, !Task.isCancelled else { return }
                model.finishArrival(key, generation: gen)
            }
    }

    private func pose(for key: ToolPageKey) -> ToolPageParkingPose {
        if model.pendingArrivals.contains(key) {
            return .arrivalStart
        }
        if model.parked.contains(key) {
            return .parked
        }
        return .visible
    }

    private func navigate(to newKey: ToolPageKey) {
        guard newKey != displayed else { return }

        if reduceMotion {
            swapImmediately(to: newKey)
            return
        }

        if let oldKey = displayed {
            model.depart(oldKey)
        }
        model.arrive(newKey)
        model.evictOverflow()
    }

    /// Direct swap with animations disabled: first mount and Reduce Motion.
    private func swapImmediately(to newKey: ToolPageKey) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            model.swapImmediately(to: newKey)
        }
    }
}

private enum ToolPageParkingPose: Equatable {
    case visible
    case arrivalStart
    case parked
}

private struct ToolPageParkingModifier: ViewModifier {
    let pose: ToolPageParkingPose
    var intent: ToolPageTransitionIntent = .depth
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        content
            .opacity(pose == .visible ? 1 : 0)
            .offset(y: offset)
            .scaleEffect(scale, anchor: anchor)
            .animation(reduceMotion ? nil : animation, value: pose)
    }

    private var usesSharedAxis: Bool {
        intent == .sharedAxis
    }

    private var usesBloom: Bool {
        intent == .originBloom
    }

    private var anchor: UnitPoint {
        usesBloom ? .top : .center
    }

    private var offset: CGFloat {
        switch pose {
        case .visible:
            return 0
        case .arrivalStart:
            if usesBloom { return -ToolMotion.Distance.pageBloomDrop }
            return usesSharedAxis ? ToolMotion.Distance.pageSharedAxisRise : ToolMotion.Distance.pageSinkRise
        case .parked:
            return usesSharedAxis ? -ToolMotion.Distance.pageSharedAxisDrop : 0
        }
    }

    private var scale: CGFloat {
        switch pose {
        case .visible:
            return 1
        case .arrivalStart:
            if usesBloom { return ToolMotion.Scale.pageBloomArrival }
            return usesSharedAxis ? ToolMotion.Scale.pageSharedAxisArrival : ToolMotion.Scale.pageArrivalSink
        case .parked:
            return usesSharedAxis ? ToolMotion.Scale.pageSharedAxisDeparture : ToolMotion.Scale.pageDepartureSink
        }
    }

    private var animation: Animation? {
        switch pose {
        case .visible:
            if usesBloom { return ToolMotion.Preset.pageBloomArrival }
            return usesSharedAxis ? ToolMotion.Preset.pageSharedAxisArrival : ToolMotion.Preset.pageArrival
        case .arrivalStart:
            return nil
        case .parked:
            if usesBloom { return ToolMotion.Preset.pageBloomDeparture }
            return usesSharedAxis ? ToolMotion.Preset.pageSharedAxisDeparture : ToolMotion.Preset.pageDeparture
        }
    }
}
