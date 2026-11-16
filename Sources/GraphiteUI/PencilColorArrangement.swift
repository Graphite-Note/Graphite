/**
 * File: PencilColorArrangement.swift
 * ----------------------------------
 * Layer: UI
 * Description: Where a color dragged along the Pencil bar lands, how far the others slide aside while it moves, when a
 *              drag takes it off the row, and when the row scrolls under it. Pure: the bar's view feeds it the drag's
 *              travel and draws what it returns.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 13/11/2026
 */

import Foundation

/// The arithmetic of arranging a row of equally spaced colors by dragging one, as Apple's markup palette does: the
/// dragged color follows the finger, the colors between its place and where it would land slide one place aside, and
/// letting go puts it there. A drag far enough across the row takes the color off it instead, and the row closes up.
struct PencilColorArrangement: Equatable {
    /// How many colors the row arranges (black, which always comes first, is not one of them).
    let colorCount: Int
    /// The distance from one color's center to the next, in points.
    let swatchPitch: Double
    /// How far across the row, up or down, a drag must take a color for letting go to remove it.
    let removalDistance: Double

    /// What letting go does.
    enum Outcome: Equatable {
        /// The color goes to this place in the row; its own place leaves the order unchanged.
        case arranged(destinationIndex: Int)
        /// The color leaves the row.
        case removed
    }

    /// The place the color dragged from `originalIndex` lands on after travelling `horizontalTravel` points along the
    /// row: the nearest place, and the first or last when the drag goes past either end.
    func destinationIndex(draggedFrom originalIndex: Int, horizontalTravel: Double) -> Int {
        guard colorCount > 0, swatchPitch > 0, horizontalTravel.isFinite else { return max(0, min(originalIndex, colorCount - 1)) }
        let placesTravelled = (horizontalTravel / swatchPitch).rounded()
        let unclampedIndex = Double(originalIndex) + placesTravelled
        return Int(max(0, min(unclampedIndex, Double(colorCount - 1))))
    }

    /// What letting go after this travel does: off the row when the drag went far enough across it, else a place.
    func outcome(draggedFrom originalIndex: Int, horizontalTravel: Double, verticalTravel: Double) -> Outcome {
        if abs(verticalTravel) > removalDistance { return .removed }
        return .arranged(destinationIndex: destinationIndex(draggedFrom: originalIndex, horizontalTravel: horizontalTravel))
    }

    /// How far, in points, the color at `index` slides aside while the color dragged from `originalIndex` would have
    /// this outcome: one place towards the dragged color's own place when it lies between that place and the landing
    /// place, every later color one place back when the color would leave the row, and nothing otherwise.
    func slideOffset(ofColorAt index: Int, draggedFrom originalIndex: Int, outcome: Outcome) -> Double {
        guard index != originalIndex else { return 0 }
        switch outcome {
        case .removed:
            return index > originalIndex ? -swatchPitch : 0
        case .arranged(let destinationIndex):
            if originalIndex < destinationIndex, index > originalIndex, index <= destinationIndex { return -swatchPitch }
            if originalIndex > destinationIndex, index >= destinationIndex, index < originalIndex { return swatchPitch }
            return 0
        }
    }

    /// Which way a scrolling row scrolls under a drag at `location` points from its visible left edge: towards the
    /// start (-1) within the last part of a color of the left edge, towards the end (1) within that of the right edge,
    /// and not at all (0) between.
    func scrollDirection(atVisibleLocation location: Double, visibleWidth: Double) -> Int {
        let edgeMargin = swatchPitch * 0.75
        guard visibleWidth > edgeMargin * 2 else { return 0 }
        if location < edgeMargin { return -1 }
        if location > visibleWidth - edgeMargin { return 1 }
        return 0
    }
}
