import CoreGraphics

struct SidebarNavigationAnimationTarget: Equatable, Sendable {
    struct Track: Equatable, Sendable {
        let id: String
        let minY: CGFloat
        let height: CGFloat
    }

    let targets: [Track]
    let documentHeight: CGFloat

    init(targets: [Track], documentHeight: CGFloat) {
        self.targets = targets
        self.documentHeight = documentHeight
    }

    init(plan: SidebarNavigationLayoutPlan) {
        targets = plan.targets.map {
            Track(id: $0.id, minY: $0.frame.minY, height: $0.frame.height)
        }
        documentHeight = plan.documentHeight
    }
}

struct SidebarNavigationAnimationToken: Equatable, Sendable {
    let generation: UInt64
    let target: SidebarNavigationAnimationTarget
}

struct SidebarNavigationAnimationGate {
    private(set) var generation: UInt64 = 0
    private var target: SidebarNavigationAnimationTarget?

    mutating func request(
        target: SidebarNavigationAnimationTarget
    ) -> SidebarNavigationAnimationToken {
        generation &+= 1
        self.target = target
        return SidebarNavigationAnimationToken(generation: generation, target: target)
    }

    mutating func synchronize(target: SidebarNavigationAnimationTarget) {
        generation &+= 1
        self.target = target
    }

    func accepts(_ token: SidebarNavigationAnimationToken) -> Bool {
        token.generation == generation && token.target == target
    }
}

struct SidebarNavigationTrackInteraction: Equatable {
    let isHidden: Bool
    let isInteractionEnabled: Bool
    let areControlsEnabled: Bool
    let acceptsPresentationSelection: Bool
    let isAccessibilityHidden: Bool

    static func preparing(targetExpanded: Bool) -> Self {
        Self(
            isHidden: false,
            isInteractionEnabled: false,
            areControlsEnabled: targetExpanded,
            acceptsPresentationSelection: targetExpanded,
            isAccessibilityHidden: true
        )
    }

    static func finalized(targetExpanded: Bool) -> Self {
        Self(
            isHidden: !targetExpanded,
            isInteractionEnabled: targetExpanded,
            areControlsEnabled: targetExpanded,
            acceptsPresentationSelection: false,
            isAccessibilityHidden: !targetExpanded
        )
    }
}
