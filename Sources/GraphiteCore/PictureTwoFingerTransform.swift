/**
 * File: PictureTwoFingerTransform.swift
 * -------------------------------------
 * Layer: Core
 * Description: A picture turned, resized and moved by two fingers on it: the point of the picture under the fingers'
 *              middle stays under it, the size stays in proportion and within limits, and the angle is held straight
 *              or at a quarter turn when it comes close, as with the rotate handle.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 17/11/2026
 */

import Foundation
import CoreGraphics

/// Where a picture is while two fingers turn, pinch and move it, from where it was when they
/// came down. Coordinates are those of the view the picture is shown in, with y pointing
/// down, so a positive angle turns clockwise (`PictureRotation`).
public struct PictureTwoFingerTransform: Equatable, Sendable {
    /// The picture's frame before it is turned, about whose middle it turns.
    public var frame: CGRect
    /// The picture's angle, in radians.
    public var rotationRadians: Double

    public init(frame: CGRect, rotationRadians: Double) {
        self.frame = frame
        self.rotationRadians = rotationRadians
    }

    /// The picture after the fingers have moved.
    ///
    /// - Parameters:
    ///   - start: The picture when the fingers came down.
    ///   - fingersMiddleAtStart: The point between the fingers then.
    ///   - fingersMiddle: The point between the fingers now.
    ///   - scale: How much further apart the fingers are than they were (a pinch's scale).
    ///   - turn: How far the line between the fingers has turned, in radians.
    ///   - minimumSideLength: The smallest the shorter side can become, unless it started smaller.
    ///   - maximumSideLength: The largest the longer side can become, unless it started larger.
    ///   - centerLimits: The region the picture's middle stays in, so it is not lost off its page.
    public static func transformed(_ start: PictureTwoFingerTransform, fingersMiddleAtStart: CGPoint, fingersMiddle: CGPoint,
                                   scale: CGFloat, turn: Double, minimumSideLength: CGFloat, maximumSideLength: CGFloat,
                                   centerLimits: CGRect) -> PictureTwoFingerTransform {
        let width = start.frame.width, height = start.frame.height
        guard width > 0, height > 0, scale.isFinite, scale > 0, turn.isFinite else { return start }
        let smallestScale = min(minimumSideLength / min(width, height), 1)
        let largestScale = max(maximumSideLength / max(width, height), 1)
        let keptScale = min(max(scale, smallestScale), largestScale)
        let rotationRadians = PictureRotation.snapped(start.rotationRadians + turn)
        // The turn the picture is shown at, held at a quarter turn when close, so the
        // point under the fingers stays under them at the angle shown.
        let shownTurn = PictureRotation.normalized(rotationRadians - start.rotationRadians)
        let offsetFromFingers = CGPoint(x: (start.frame.midX - fingersMiddleAtStart.x) * keptScale,
                                        y: (start.frame.midY - fingersMiddleAtStart.y) * keptScale)
        let turnedOffset = PictureRotation.vector(offsetFromFingers, turnedBy: shownTurn)
        var center = CGPoint(x: fingersMiddle.x + turnedOffset.x, y: fingersMiddle.y + turnedOffset.y)
        if !centerLimits.isInfinite, !centerLimits.isNull {
            center.x = min(max(center.x, centerLimits.minX), centerLimits.maxX)
            center.y = min(max(center.y, centerLimits.minY), centerLimits.maxY)
        }
        let newWidth = width * keptScale, newHeight = height * keptScale
        return PictureTwoFingerTransform(frame: CGRect(x: center.x - newWidth / 2, y: center.y - newHeight / 2, width: newWidth, height: newHeight),
                                         rotationRadians: rotationRadians)
    }
}
