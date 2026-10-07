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
