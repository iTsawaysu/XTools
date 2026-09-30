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
/// Insertion and removal need *different* timings, which one implicit
/// `.animation` cannot split — so a switch is issued as two explicit
/// transactions inside the same render pass: first `withAnimation(pageDeparture)`
/// unmounts the old key (SwiftUI keeps the departing instance alive until its
/// removal transition finishes), then `withAnimation(pageArrival)` mounts the
/// new key. Rapid re-switching retargets through the same two transactions,
/// which matches the prototype's take-last queue without blocking input.
/// The departing layer stops hit testing and leaves the accessibility tree
/// immediately (prototype: `body.switching #stage { pointer-events: none }`).
/// Reduce Motion swaps the page directly; first mount never animates.
@MainActor
struct ToolPageStage<Page: View>: View {
    let target: ToolPageKey
    @ViewBuilder let page: (ToolPageKey) -> Page

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var mounted: [ToolPageKey] = []
    @State private var displayed: ToolPageKey?

    var body: some View {
        ZStack {
            ForEach(mounted, id: \.self) { key in
                page(key)
                    .zIndex(key == displayed ? 1 : 0)
                    .allowsHitTesting(key == displayed)
                    .accessibilityHidden(key != displayed)
            }
        }
        .onAppear {
            guard mounted.isEmpty else { return }
            swapImmediately(to: target)
        }
        .onChange(of: target) { newKey in
            navigate(to: newKey)
        }
    }

    private func navigate(to newKey: ToolPageKey) {
        guard newKey != displayed else { return }

        if reduceMotion {
            swapImmediately(to: newKey)
            return
        }

        if let oldKey = displayed {
            withAnimation(ToolMotion.Preset.pageDeparture) {
                mounted.removeAll { $0 == oldKey }
            }
        }
        withAnimation(ToolMotion.Preset.pageArrival) {
            mounted.append(newKey)
            displayed = newKey
        }
    }

    /// Direct swap with animations disabled: first mount and Reduce Motion.
    private func swapImmediately(to newKey: ToolPageKey) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            mounted = [newKey]
            displayed = newKey
        }
    }
}
