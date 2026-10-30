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
/// Pages keep the same modifier structure while only pose values change.
/// The arrival start is installed before the page's generation task makes it
/// visible; a stale task cannot complete a newer navigation. Each page chooses
/// its own arrival/departure timing. Reduce Motion swaps directly without parked
/// pages, and the first mount never animates.
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
            .modifier(ToolPageParkingModifier(pose: pagePose, reduceMotion: reduceMotion))
            .zIndex(zIndexValue)
            .allowsHitTesting(isCurrent)
            .accessibilityHidden(!isCurrent)
            .environment(\.toolPageEntryGeneration, gen)
            // 停靠页不进 AppKit 的 tooltip 跟踪：透明页若继续注册 tooltip，
            // 鼠标扫过当前位置会弹出上一个页面的提示。
            .environment(\.toolInteractionIsLive, isCurrent)
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
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        content
            .opacity(pose == .visible ? 1 : 0)
            .offset(y: pose == .arrivalStart ? ToolMotion.Distance.pageRise : 0)
            .animation(reduceMotion ? nil : animation, value: pose)
    }

    private var animation: Animation? {
        switch pose {
        case .visible: ToolMotion.Preset.pageEnter
        case .arrivalStart: nil
        case .parked: ToolMotion.Preset.pageExit
        }
    }
}
