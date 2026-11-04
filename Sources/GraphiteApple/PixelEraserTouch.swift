/**
 * File: PixelEraserTouch.swift
 * ----------------------------
 * Layer: Apple
 * Description: One touch of Graphite's pixel eraser on a canvas: what of the drawing still shows while it moves,
 *              and the erased drawing it leaves when it lifts.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 04/11/2026
 */
import CoreGraphics
import PencilKit

/// One touch of Graphite's pixel eraser on a canvas, in the drawing's points.
///
/// While the touch moves, the canvas goes on drawing the drawing as it was, and hides its ink
/// outside `shownArea`: everything but what the touch swept, and what UIKit predicts it sweeps
/// next, so the ink goes from under the tip in the frame it is reached. Giving PencilKit a new
/// drawing at every move would make it draw the page anew each time. When the touch lifts, the
/// canvas is given `erasedDrawing` once, which the canvas's owner records as one step of the
/// history, as it records a stroke of PencilKit's own eraser.
public struct PixelEraserTouch {
    public private(set) var pass: PixelEraserPass
    /// Where the canvas shows ink: everything within the bounds the touch began with, but what it swept.
    public private(set) var keptArea: CGPath
    /// The area including what UIKit predicts the touch sweeps next.
    public private(set) var shownArea: CGPath

    /// `shownBounds`: the part of the drawing the canvas can show, in the drawing's points.
    public init(drawing: PKDrawing, width: CGFloat, shownBounds: CGRect) {
        pass = PixelEraserPass(drawing: drawing, width: width)
        keptArea = CGPath(rect: shownBounds, transform: nil)
        shownArea = keptArea
    }

    /// The touch moved on through points, and UIKit predicts it goes on through others; returns
    /// where the canvas shows ink now.
    @discardableResult
    public mutating func move(through points: [CGPoint], predicted predictedPoints: [CGPoint]) -> CGPath {
        if let sweptArea = pass.sweep(through: points) { keptArea = keptArea.subtracting(sweptArea) }
        shownArea = keptArea
        if !predictedPoints.isEmpty, let lastPoint = pass.sweptPoints.last {
            // Begun at the last point, as the next part of the touch would be.
            var predictedSweep = PixelEraserSweep(width: pass.width)
            predictedSweep.extend(through: [lastPoint])
            if let predictedArea = predictedSweep.extend(through: predictedPoints) { shownArea = keptArea.subtracting(predictedArea) }
        }
        return shownArea
    }

    /// The drawing the touch leaves, nil when it cut nothing. `replacedDrawing` is the canvas's
    /// drawing when something replaced the one the touch began on, as undo can: the touch's
    /// whole path then erases that one.
    public func erasedDrawing(replacing replacedDrawing: PKDrawing? = nil) -> PKDrawing? {
        if let replacedDrawing {
            var passOverReplacement = PixelEraserPass(drawing: replacedDrawing, width: pass.width)
            passOverReplacement.sweep(through: pass.sweptPoints)
            return passOverReplacement.hasCut ? passOverReplacement.erasedDrawing() : nil
        }
        return pass.hasCut ? pass.erasedDrawing() : nil
    }
}
