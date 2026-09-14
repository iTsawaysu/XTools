import CoreGraphics

enum SidebarNavigationTrackKind: Equatable {
    case header
    case tool(ToolID)
    case spacing
}

struct SidebarNavigationTrackTarget: Equatable {
    let id: String
    let groupID: String
    let kind: SidebarNavigationTrackKind
    let frame: CGRect
    let naturalHeight: CGFloat
}

struct SidebarNavigationLayoutPlan: Equatable {
    let targets: [SidebarNavigationTrackTarget]
    let documentHeight: CGFloat
}

enum SidebarNavigationLayout {
    static let horizontalPadding: CGFloat = 10
    static let verticalPadding: CGFloat = 12

    static func plan(
        entries: [SidebarNavigationEntry],
        width: CGFloat
    ) -> SidebarNavigationLayoutPlan {
        let trackWidth = max(0, width - horizontalPadding * 2)
        var y = verticalPadding
        let targets = entries.map { entry in
            let target = SidebarNavigationTrackTarget(
                id: entry.id,
                groupID: entry.groupID,
                kind: kind(for: entry),
                frame: CGRect(
                    x: horizontalPadding,
                    y: y,
                    width: trackWidth,
                    height: entry.presentedHeight
                ),
                naturalHeight: entry.naturalHeight
            )
            y += entry.presentedHeight
            return target
        }

        return SidebarNavigationLayoutPlan(
            targets: targets,
            documentHeight: y + verticalPadding
        )
    }

    private static func kind(for entry: SidebarNavigationEntry) -> SidebarNavigationTrackKind {
        switch entry.content {
        case .header:
            return .header
        case .item(let item, _):
            return .tool(item.id)
        case .spacing:
            return .spacing
        }
    }
}

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

struct SidebarNavigationPresentationHitTarget: Equatable {
    let toolID: ToolID
    let frame: CGRect
}

enum SidebarNavigationPresentationHitTesting {
    static func toolID(
        at point: CGPoint,
        targets: [SidebarNavigationPresentationHitTarget]
    ) -> ToolID? {
        targets.reversed().first { target in
            !target.frame.isEmpty && target.frame.contains(point)
        }?.toolID
    }
}

struct SidebarNavigationSectionBounds: Equatable, Sendable {
    let headerMinY: CGFloat
    let sectionMaxY: CGFloat

    init(headerMinY: CGFloat, sectionMaxY: CGFloat) {
        self.headerMinY = headerMinY
        self.sectionMaxY = sectionMaxY
    }
}

struct SidebarNavigationScrollAnchor: Equatable {
    private let savedOriginY: CGFloat
    private let expandedSectionBounds: SidebarNavigationSectionBounds?

    static func capture(
        originY: CGFloat,
        documentHeight: CGFloat,
        viewportHeight: CGFloat,
        expandedSectionBounds: SidebarNavigationSectionBounds? = nil
    ) -> Self {
        Self(
            savedOriginY: max(0, originY),
            expandedSectionBounds: expandedSectionBounds
        )
    }

    func resolvedOriginY(
        documentHeight: CGFloat,
        viewportHeight: CGFloat
    ) -> CGFloat {
        let maximumOriginY = max(0, documentHeight - viewportHeight)

        guard let bounds = expandedSectionBounds else {
            return min(savedOriginY, maximumOriginY)
        }

        let currentTop = savedOriginY
        let currentBottom = savedOriginY + viewportHeight

        // Case 1: If the header was scrolled above current viewport, bring it into view at top
        if bounds.headerMinY < currentTop {
            return max(0, min(bounds.headerMinY, maximumOriginY))
        }

        // Case 2: If the section already fits within current viewport, maintain origin (0px displacement)
        if bounds.sectionMaxY <= currentBottom {
            return min(savedOriginY, maximumOriginY)
        }

        // Case 3: Target-Aware Smart Reveal
        // Reveal expanded children below, but never scroll the section header past the top.
        // Maintain 6pt breathing room under the top boundary for visual comfort.
        let topBreathingRoom: CGFloat = 6
        let idealOriginY = bounds.sectionMaxY - viewportHeight
        let guardedOriginY = min(idealOriginY, max(0, bounds.headerMinY - topBreathingRoom))
        let targetOriginY = max(savedOriginY, guardedOriginY)

        return max(0, min(targetOriginY, maximumOriginY))
    }
}
