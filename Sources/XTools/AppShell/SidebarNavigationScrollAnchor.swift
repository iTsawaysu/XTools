import CoreGraphics

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
