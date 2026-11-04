/**
 * File: PencilEraserWidths.swift
 * ------------------------------
 * Layer: UI
 * Description: The widths the Pencil bar's pixel eraser can have: its three starting sizes, the steps between them,
 *              and what PencilKit makes of them on the screen.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 04/11/2026
 */

import Foundation

/// The pixel eraser's widths, in points of the page (HUNT-004, HUNT-023: it cuts the same gap on
/// the page at every zoom). A width is chosen from `steps`, fine ones close together and broad
/// ones further apart, so one letter or one tiny stroke can be erased and a whole line too.
///
/// PencilKit makes the fixed-width eraser at least `pencilKitWidthOnScreen.lowerBound` points of
/// the screen wide, and the canvas gives it the chosen width times the zoom, so a width below
/// that cuts `pencilKitWidthOnScreen.lowerBound / zoom` of the page: zoom in for a finer cut.
enum PencilEraserWidths {
    /// The three sizes the bar starts with: about a thin pen line, a letter's stroke, and a word's height.
    static let defaultChoices: [Double] = [2, 6, 14]
    /// The three sizes earlier builds started with. A saved state that still holds exactly these was
    /// never changed by the person, so it is given the sizes above.
    static let previousDefaultChoices: [Double] = [18, 36, 64]
    /// The widths a size can be changed to, in points of the page.
    static let range: ClosedRange<Double> = 1...100
    /// The widths PencilKit makes a fixed-width eraser at, in points of the screen
    /// (`PKEraserTool.EraserType.fixedWidthBitmap.validWidthRange`): narrower or wider ones are clamped.
    static let pencilKitWidthOnScreen: ClosedRange<Double> = 16.4...80.4

    /// Every width the size control offers, in order: half a point apart up to ten, then one,
    /// two and five points apart as the eraser gets broader.
    static let steps: [Double] = {
        let fine = stride(from: 1.0, through: 10.0, by: 0.5)
        let medium = stride(from: 11.0, through: 30.0, by: 1.0)
        let broad = stride(from: 32.0, through: 64.0, by: 2.0)
        let broadest = stride(from: 70.0, through: 100.0, by: 5.0)
        return Array(fine) + Array(medium) + Array(broad) + Array(broadest)
    }()

    /// The position in `steps` of the step nearest to a width.
    static func stepIndex(forWidth width: Double) -> Int {
        guard width.isFinite else { return 0 }
        return steps.indices.min { first, second in abs(steps[first] - width) < abs(steps[second] - width) } ?? 0
    }

    /// The step nearest to a width, which is within `range`.
    static func snapped(_ width: Double) -> Double { steps[stepIndex(forWidth: width)] }

    /// Three widths the eraser can erase with, or nil for anything else.
    static func validatedChoices(_ widths: [Double]) -> [Double]? {
        widths.count == defaultChoices.count && widths.allSatisfy(range.contains) ? widths : nil
    }

    /// The three sizes and the one in use of a saved state, which may hold none, the earlier
    /// builds' starting sizes (replaced by the current ones, the size in use keeping its place),
    /// sizes this build would not offer, or a size in use that is not one of the three.
    static func restored(choices savedChoices: [Double]?, widthInUse savedWidth: Double?) -> (choices: [Double], widthInUse: Double) {
        let validChoices = savedChoices.flatMap(validatedChoices)
        if validChoices == previousDefaultChoices {
            let placeInUse = savedWidth.flatMap(previousDefaultChoices.firstIndex(of:)) ?? 1
            return (defaultChoices, defaultChoices[placeInUse])
        }
        let choices = validChoices ?? defaultChoices
        return (choices, savedWidth.flatMap { width in choices.contains(width) ? width : nil } ?? choices[1])
    }

    /// How much of the page the fixed-width eraser cuts for a chosen width, at a zoom of
    /// `screenPointsPerPagePoint` points of the screen to one of the page.
    static func widthOnPage(chosen: Double, screenPointsPerPagePoint: Double) -> Double {
        guard screenPointsPerPagePoint > 0 else { return chosen }
        let widthOnScreen = min(max(chosen * screenPointsPerPagePoint, pencilKitWidthOnScreen.lowerBound), pencilKitWidthOnScreen.upperBound)
        return widthOnScreen / screenPointsPerPagePoint
    }
}
