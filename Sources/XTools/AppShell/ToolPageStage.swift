import SwiftUI

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

/// 01 景深沉降 stage (PAGE-TRANSITIONS t-1): the incoming page fades in while
/// rising 10pt and settling from 99.5% scale (300ms smoothOut); the outgoing
/// page sinks to 99.2% while fading (220ms productiveExit). Both arcs run at
/// once with the incoming layer on top.
///
/// Insertion and departure need *different* timings, which one implicit
/// `.animation` cannot split — so a switch is issued as two explicit
/// transactions inside the same render pass: first `withAnimation(pageDeparture)`
/// parks the old key at its sink pose (opacity 0 + 99.2%), then
/// `withAnimation(pageArrival)` mounts the new key. Rapid re-switching
/// retargets through the same two transactions, which matches the prototype's
/// take-last queue without blocking input. The parked layer stops hit testing
/// and leaves the accessibility tree immediately (prototype:
/// `body.switching #stage { pointer-events: none }`).
///
/// Departed pages stay mounted as *parked* pages (bounded LRU, see
/// `ToolPageStageModel`): revisiting one skips rebuilding the whole page tree
/// and replays the arrival choreography from the same start pose, so the
/// visible motion is frame-identical to a fresh mount. Reduce Motion swaps
/// the page directly and keeps no parked pages; first mount never animates.
@MainActor
struct ToolPageStage<Page: View>: View {
    let target: ToolPageKey
    @ViewBuilder let page: (ToolPageKey) -> Page

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var model = ToolPageStageModel()

    private var displayed: ToolPageKey? { model.displayed }

    var body: some View {
        ZStack {
            ForEach(model.mounted, id: \.self) { key in
                stagedPageView(for: key)
            }
        }
        .onAppear {
            guard displayed == nil else { return }
            swapImmediately(to: target)
        }
        .onChange(of: target) { newKey in
            navigate(to: newKey)
        }
    }

    @ViewBuilder
    private func stagedPageView(for key: ToolPageKey) -> some View {
        let isCurrent = (key == displayed)
        let pagePose = pose(for: key)
        let gen = isCurrent ? model.generation : 0
        let zIndexValue: Double = isCurrent ? 1 : 0

        page(key)
            .modifier(ToolPageParkingModifier(pose: pagePose))
            .zIndex(zIndexValue)
            .allowsHitTesting(isCurrent)
            .accessibilityHidden(!isCurrent)
            .environment(\.toolPageEntryGeneration, gen)
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

        if model.isParked(newKey) {
            model.stageArrivalStart(newKey)
        }
        if let oldKey = displayed {
            withAnimation(ToolMotion.Preset.pageDeparture) {
                model.depart(oldKey)
            }
        }
        withAnimation(ToolMotion.Preset.pageArrival) {
            model.arrive(newKey)
        }
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

/// 停靠页的姿态。`arrivalStart` 与到达过渡的插入起始帧完全一致（透明 +
/// 上浮 `Distance.pageSinkRise` + `Scale.pageArrivalSink`），`parked` 与
/// 离开过渡的结束帧完全一致（透明 + `Scale.pageDepartureSink`）；因此
/// 「停靠 → 唤回」与「全新插入 → 到达」两条路径的可见动效逐帧相同。
private enum ToolPageParkingPose {
    case visible
    case arrivalStart
    case parked
}

private struct ToolPageParkingModifier: ViewModifier {
    let pose: ToolPageParkingPose

    func body(content: Content) -> some View {
        switch pose {
        case .visible:
            content
        case .arrivalStart:
            content
                .opacity(0)
                .offset(y: ToolMotion.Distance.pageSinkRise)
                .scaleEffect(ToolMotion.Scale.pageArrivalSink)
        case .parked:
            content
                .opacity(0)
                .scaleEffect(ToolMotion.Scale.pageDepartureSink)
        }
    }
}
