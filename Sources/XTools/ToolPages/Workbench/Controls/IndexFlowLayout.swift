import SwiftUI

// MARK: - IndexFlowLayout

/// Left-aligned layout that wraps its subviews onto new lines when they would
/// overflow the available width — used for preset chips so they reflow with the
/// window instead of being clipped or forced into a fixed grid.
struct IndexFlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        var totalWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if rowWidth > 0, rowWidth + spacing + size.width > maxWidth {
                totalHeight += rowHeight + lineSpacing
                totalWidth = max(totalWidth, rowWidth)
                rowWidth = size.width
                rowHeight = size.height
            } else {
                rowWidth += (rowWidth > 0 ? spacing : 0) + size.width
                rowHeight = max(rowHeight, size.height)
            }
        }
        totalHeight += rowHeight
        totalWidth = max(totalWidth, rowWidth)
        return CGSize(width: min(totalWidth, maxWidth), height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        let maxWidth = bounds.width

        // Pass 1: group subviews into rows and take each row's tallest height
        // (mirrors sizeThatFits exactly).
        var rows: [[Int]] = [[]]
        var rowHeights: [CGFloat] = [0]
        var rowWidth: CGFloat = 0
        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            if rowWidth > 0, rowWidth + spacing + size.width > maxWidth {
                rows.append([])
                rowHeights.append(0)
                rowWidth = 0
            }
            rows[rows.count - 1].append(index)
            rowWidth += (rowWidth > 0 ? spacing : 0) + size.width
            rowHeights[rowHeights.count - 1] = max(rowHeights[rowHeights.count - 1], size.height)
        }

        // Pass 2: place each row, centering mixed-height items on the row's
        // midline so labels, fields, and switches share one visual axis.
        var y = bounds.minY
        for (row, indices) in rows.enumerated() {
            let rowHeight = rowHeights[row]
            var x = bounds.minX
            for index in indices {
                let subview = subviews[index]
                let size = subview.sizeThatFits(.unspecified)
                let itemY = y + (rowHeight - size.height) / 2
                subview.place(at: CGPoint(x: x, y: itemY), anchor: .topLeading, proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += rowHeight + lineSpacing
        }
    }
}
