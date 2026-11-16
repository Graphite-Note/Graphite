/**
 * File: PencilSizeDot.swift
 * -------------------------
 * Layer: UI
 * Description: How large the dot beside the Pencil tools is drawn for a width.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 16/11/2026
 */

import SwiftUI

/// How large the bar draws the dot of one of its sizes: by the width it stands for, so a
/// width changed in its popover shows on the bar at once, and the dots of every ink compare.
/// Widths run from half a point (monoline) to a hundred (the eraser), far more than a dot
/// beside the tools can show as drawn, so the dot grows with the width's logarithm, within a
/// range that stays visible and fits the 28-point button: each of a tool's three starting
/// sizes is about two points from the next.
enum PencilSizeDot {
    static let smallestDiameter: Double = 3.5
    static let largestDiameter: Double = 22
    /// The widths drawn as the smallest and the largest dot; narrower and wider ones are clamped.
    static let narrowestWidth: Double = 0.5
    static let widestWidth: Double = 60

    static func diameter(forWidth width: Double) -> Double {
        guard width.isFinite, width > narrowestWidth else { return smallestDiameter }
        let fraction = min(log(width / narrowestWidth) / log(widestWidth / narrowestWidth), 1)
        return smallestDiameter + (largestDiameter - smallestDiameter) * fraction
    }
}
