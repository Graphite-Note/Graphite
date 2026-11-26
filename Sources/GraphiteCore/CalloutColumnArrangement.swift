/**
 * File: CalloutColumnArrangement.swift
 * ------------------------------------
 * Layer: Core
 * Description: How the blocks of a `[!multi-column]` callout are placed side by side, as the Modular CSS Layout
 *              snippet lays them out in Obsidian: columns of at least a minimum width that share the width by their
 *              weights and wrap onto a new row when the note is too narrow, down to one column per row.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

import CoreGraphics
import Foundation

/// How a callout is drawn, by its type, as Modular CSS Layout's snippet draws it in Obsidian.
public enum CalloutLayout: Equatable, Sendable {
    /// A box with its title, as every other callout.
    case box
    /// `[!multi-column]`: no title and no box, its blocks side by side (`CalloutColumnArrangement`).
    case columns
    /// `[!blank]`, `[!blank-container]`: no title and no box, its blocks as they are.
    case contentOnly

    /// The type the snippet lays out in columns.
    public static let columnsType = "multi-column"

    public init(type: String) {
        if type == Self.columnsType {
            self = .columns
        } else if type.contains("blank") {
            // The snippet matches `data-callout*="blank"`: every type with "blank" in it.
            self = .contentOnly
        } else {
            self = .box
        }
    }
}

/// The rows and column widths of a multi-column callout at one width. A pure function of its inputs, so the
/// reading view's layout and its tests compute the same arrangement.
public struct CalloutColumnArrangement: Equatable, Sendable {
    /// One column: which block it holds and how wide it is.
    public struct Column: Equatable, Sendable {
        public let blockIndex: Int
        public let width: CGFloat
    }

    /// The columns of each row, top to bottom.
    public let rows: [[Column]]

    /// The snippet's `--callout-min-width`: no column is narrower, unless the note itself is.
    public static let minimumColumnWidthPoints: CGFloat = 200
    /// The snippet's `--callout-gap` of 1em at the reading view's body size.
    public static let columnGapPoints: CGFloat = 16

    /// Places blocks of the given weights (the snippet's flex-grow: 2 makes a block grow twice as much) in rows of
    /// `availableWidth`.
    /// A row takes blocks while each still gets the minimum width, as flex-wrap does; the width left over is shared
    /// by the row's weights.
    public init(weights: [Int], availableWidth: CGFloat,
                minimumColumnWidth: CGFloat = Self.minimumColumnWidthPoints, gap: CGFloat = Self.columnGapPoints) {
        let width = max(availableWidth, 0)
        var rows: [[Column]] = []
        var rowIndices: [Int] = []
        var usedWidth: CGFloat = 0
        for blockIndex in weights.indices {
            let neededWidth = rowIndices.isEmpty ? minimumColumnWidth : usedWidth + gap + minimumColumnWidth
            if !rowIndices.isEmpty, neededWidth > width {
                rows.append(Self.columns(of: rowIndices, weights: weights, width: width, minimumColumnWidth: minimumColumnWidth, gap: gap))
                rowIndices = []
                usedWidth = 0
            }
            usedWidth = rowIndices.isEmpty ? minimumColumnWidth : usedWidth + gap + minimumColumnWidth
            rowIndices.append(blockIndex)
        }
        if !rowIndices.isEmpty {
            rows.append(Self.columns(of: rowIndices, weights: weights, width: width, minimumColumnWidth: minimumColumnWidth, gap: gap))
        }
        self.rows = rows
    }

    /// Whether every block has a row of its own, as on a phone.
    public var isStacked: Bool { rows.allSatisfy { row in row.count == 1 } }

    private static func columns(of indices: [Int], weights: [Int], width: CGFloat, minimumColumnWidth: CGFloat, gap: CGFloat) -> [Column] {
        let gaps = gap * CGFloat(indices.count - 1)
        let baseWidth = minimumColumnWidth * CGFloat(indices.count)
        let leftOver = max(width - gaps - baseWidth, 0)
        let totalWeight = indices.reduce(0) { sum, index in sum + max(weights[index], 1) }
        return indices.map { index in
            let share = leftOver * CGFloat(max(weights[index], 1)) / CGFloat(totalWeight)
            return Column(blockIndex: index, width: min(minimumColumnWidth + share, width))
        }
    }
}
