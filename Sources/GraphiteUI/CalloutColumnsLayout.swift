/**
 * File: CalloutColumnsLayout.swift
 * --------------------------------
 * Layer: UI
 * Description: The blocks of a `[!multi-column]` callout laid out side by side by `CalloutColumnArrangement`, wrapping
 *              onto new rows when the note is too narrow and widened by `wide-2` to `wide-5`, as Modular CSS Layout lays them
 *              out in Obsidian.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 28/11/2026
 */

import SwiftUI
import GraphiteCore

/// Places each subview as a column of the arrangement at the width it is offered, rows top to bottom with the
/// arrangement's gap between them, each row as tall as its tallest column and its columns aligned at the top.
struct CalloutColumnsLayout: Layout {
    /// Each column's weight (`wide-2` grows twice as much); a column without one weighs 1.
    var weights: [Int] = []

    struct Cache {
        var width: CGFloat?
        var arrangement = CalloutColumnArrangement(weights: [], availableWidth: 0)
    }

    func makeCache(subviews: Subviews) -> Cache { Cache() }

    func updateCache(_ cache: inout Cache, subviews: Subviews) {
        cache = Cache()
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize {
        let width = proposal.width ?? CalloutColumnArrangement.minimumColumnWidthPoints * CGFloat(max(subviews.count, 1))
        let rowHeights = heights(ofRowsIn: arrangement(width: width, subviews: subviews, cache: &cache), subviews: subviews)
        let gaps = CalloutColumnArrangement.columnGapPoints * CGFloat(max(rowHeights.count - 1, 0))
        return CGSize(width: width, height: rowHeights.reduce(0, +) + gaps)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) {
        let placed = arrangement(width: bounds.width, subviews: subviews, cache: &cache)
        let rowHeights = heights(ofRowsIn: placed, subviews: subviews)
        var top = bounds.minY
        for (row, rowHeight) in zip(placed.rows, rowHeights) {
            var leading = bounds.minX
            for column in row {
                subviews[column.blockIndex].place(at: CGPoint(x: leading, y: top), anchor: .topLeading,
                                                  proposal: ProposedViewSize(width: column.width, height: nil))
                leading += column.width + CalloutColumnArrangement.columnGapPoints
            }
            top += rowHeight + CalloutColumnArrangement.columnGapPoints
        }
    }

    private func arrangement(width: CGFloat, subviews: Subviews, cache: inout Cache) -> CalloutColumnArrangement {
        if cache.width != width {
            cache.width = width
            let columnWeights = subviews.indices.map { index in weights.indices.contains(index) ? weights[index] : 1 }
            cache.arrangement = CalloutColumnArrangement(weights: columnWeights, availableWidth: width)
        }
        return cache.arrangement
    }

    private func heights(ofRowsIn arrangement: CalloutColumnArrangement, subviews: Subviews) -> [CGFloat] {
        arrangement.rows.map { row in
            row.map { column in subviews[column.blockIndex].sizeThatFits(ProposedViewSize(width: column.width, height: nil)).height }.max() ?? 0
        }
    }
}

extension EnvironmentValues {
    /// Whether callouts take the layouts of Modular CSS Layout (`CalloutLayout`): on while the Icons, Covers and
    /// Columns core plugin is, where the reading view and Live Preview are drawn.
    @Entry var drawsCalloutLayouts = false
}
