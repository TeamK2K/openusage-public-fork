import SwiftUI

/// The wide dashboard's grid: rows of equal-width columns, each row as tall as its tallest card and
/// top-aligned. Deliberately not a lazy grid: every card is measured, so the panel's content-driven
/// height is exact (a lazy grid estimates rows it hasn't built yet), and the children stay one flat
/// list, so a reordered card keeps its identity and slides to its new slot across rows.
struct ColumnGridLayout: Layout {
    var columns: Int
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? idealWidth(of: subviews)
        let heights = rowHeights(width: width, subviews: subviews)
        let height = heights.reduce(0, +) + spacing * CGFloat(max(0, heights.count - 1))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let columnWidth = Self.columnWidth(total: bounds.width, columns: columns, spacing: spacing)
        let cell = ProposedViewSize(width: columnWidth, height: nil)
        var y = bounds.minY
        for (row, rowHeight) in rowHeights(width: bounds.width, subviews: subviews).enumerated() {
            for column in 0..<columns {
                let index = row * columns + column
                guard index < subviews.count else { break }
                let x = bounds.minX + CGFloat(column) * (columnWidth + spacing)
                subviews[index].place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: cell)
            }
            y += rowHeight + spacing
        }
    }

    static func columnWidth(total: CGFloat, columns: Int, spacing: CGFloat) -> CGFloat {
        guard columns > 0 else { return 0 }
        return max(0, (total - spacing * CGFloat(columns - 1)) / CGFloat(columns))
    }

    private func rowHeights(width: CGFloat, subviews: Subviews) -> [CGFloat] {
        guard columns > 0 else { return [] }
        let cell = ProposedViewSize(width: Self.columnWidth(total: width, columns: columns, spacing: spacing), height: nil)
        return stride(from: 0, to: subviews.count, by: columns).map { start in
            subviews[start..<min(start + columns, subviews.count)]
                .map { $0.sizeThatFits(cell).height }
                .max() ?? 0
        }
    }

    /// Only for an unconstrained width proposal: the widest card's ideal width in every column.
    private func idealWidth(of subviews: Subviews) -> CGFloat {
        let widest = subviews.map { $0.sizeThatFits(.unspecified).width }.max() ?? 0
        return widest * CGFloat(columns) + spacing * CGFloat(max(0, columns - 1))
    }
}
