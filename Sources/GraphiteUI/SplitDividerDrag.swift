/**
 * File: SplitDividerDrag.swift
 * ----------------------------
 * Layer: UI
 * Description: A drag of the divider between the two sides, kept apart from the saved layout until it ends.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 01/11/2026
 */

import CoreGraphics
import GraphiteCore

/// A drag of the divider between the two sides. While it lasts the split is this drag's own
/// state, which the panes draw; the layout takes the fraction once, when the drag ends. The
/// layout is saved with every change, so assigning each frame of the drag to it wrote the
/// tab layout to the device many times a second.
struct SplitDividerDrag: Equatable {
    private var startFraction: Double?
    /// Where the divider is while it is dragged; nil when it is not.
    private(set) var fraction: Double?

    /// The split after the finger moved `translation` from where the drag began, at a layout
    /// that was split at `layoutFraction` then, within the range a split may have.
    mutating func change(translation: CGFloat, availableWidth: CGFloat, layoutFraction: Double) -> Double {
        let start = startFraction ?? layoutFraction
        startFraction = start
        let range = TabLayout.splitFractionRange
        let moved = min(max(start + Double(translation / max(availableWidth, 1)), range.lowerBound), range.upperBound)
        fraction = moved
        return moved
    }

    /// Ends the drag, returning the split to give the layout; nil when the divider did not move.
    mutating func end() -> Double? {
        defer { startFraction = nil; fraction = nil }
        return fraction
    }
}
