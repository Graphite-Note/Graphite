/**
 * File: PencilColorArrangement.swift
 * ----------------------------------
 * Layer: UI
 * Description: Where a color dragged along the Pencil bar lands, how far the others slide aside while it moves, and
 *              when the row scrolls under it. Pure: the bar's view feeds it the drag's travel and draws what it returns.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 17/11/2026
 */

import Foundation

/// The arithmetic of arranging a row of equally spaced colors by dragging one, as Apple's markup palette does: the
/// dragged color follows the finger along the row, the colors between its place and where it would land slide one place
/// aside, and letting go puts it there. A drag moves a color along the row only: it never leaves the row's line, so the
/// row does not seem to move up or down (the report of 2026-11-17), and removing a color is its menu's.
struct PencilColorArrangement: Equatable {
    /// How many colors the row arranges (black, which always comes first, is not one of them).
    let colorCount: Int
    /// The distance from one color's center to the next, in points.
    let swatchPitch: Double

    /// The place the color dragged from `originalIndex` lands on after travelling `horizontalTravel` points along the
    /// row: the nearest place, and the first or last when the drag goes past either end.
    func destinationIndex(draggedFrom originalIndex: Int, horizontalTravel: Double) -> Int {
        guard colorCount > 0, swatchPitch > 0, horizontalTravel.isFinite else { return max(0, min(originalIndex, colorCount - 1)) }
        let placesTravelled = (horizontalTravel / swatchPitch).rounded()
        let unclampedIndex = Double(originalIndex) + placesTravelled
        return Int(max(0, min(unclampedIndex, Double(colorCount - 1))))
    }

    /// How far, in points, the color at `index` slides aside while the color dragged from `originalIndex` would land on
    /// `destinationIndex`: one place towards the dragged color's own place when it lies between that place and the
    /// landing place, and nothing otherwise.
    func slideOffset(ofColorAt index: Int, draggedFrom originalIndex: Int, destinationIndex: Int) -> Double {
        guard index != originalIndex else { return 0 }
        if originalIndex < destinationIndex, index > originalIndex, index <= destinationIndex { return -swatchPitch }
        if originalIndex > destinationIndex, index >= destinationIndex, index < originalIndex { return swatchPitch }
        return 0
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
