/**
 * File: InkLasso.swift
 * --------------------
 * Layer: UI
 * Description: The geometry and the rules of Graphite's lasso: the loop closed from its last point back to
 *              its first, which strokes and pictures it takes, how small a loop is a slip, and how a moved
 *              or resized selection frame carries what it holds.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 04/11/2026
 */
import Foundation
import CoreGraphics
import GraphiteCore

/// The geometry and the rules of Graphite's lasso: which strokes and pictures a loop takes,
/// and how a moved or resized selection frame carries them along.
///
/// The loop is closed from where the hand lifted back to where it came down, as in Goodnotes
/// and Apple Notes: a loop the hand did not finish takes what the closed one encloses. A
/// stroke or a picture the loop goes through is taken when enough of it is inside, not only
/// when all of it is; one the loop's edge merely grazes is not.
enum InkLasso {
    // MARK: The rules, in one place to tune

    /// A stroke is taken when at least this share of its length lies inside the closed loop:
    /// a loop around half of a word takes the strokes it cuts through, as Goodnotes and Apple
    /// Notes do, while a stroke the loop's edge only grazes (a few percent inside), or a long
    /// line passing under a circled word, stays where it is. Owner, 2026-11-04: "if you lasso
    /// a circle and not the entire item the item should be taken too"; it was 60 %.
    static let minimumEnclosedStrokeFraction = 0.35
    /// A picture or a text box is taken when at least this share of its area lies inside the
    /// loop, or when the loop encloses its middle and also reaches past its edge. A loop drawn
    /// wholly on a picture, around writing on it, takes the picture only by this share.
    static let minimumEnclosedPictureFraction = 0.3
    /// A freehand loop shorter than this, in screen points, is a tap.
    static let minimumLoopLength: CGFloat = 24
    /// A freehand loop that, closed, encloses less than this area in square screen points is a
    /// slip, a tap or a short scribble, and selects nothing: closed, a scribble along a line
    /// encloses nothing, and a loop smaller than a circle 9 points across is no deliberate loop.
    static let minimumLoopArea: CGFloat = 64
    /// A tap takes the stroke that passes within this distance of it, in screen points. A
    /// rectangle thinner than this on screen is a slip.
    static let tapReach: CGFloat = 14
    /// How many points along each side of a picture are tested against the loop.
    static let pictureSamplesPerSide = 6
    /// How far apart the points tested along a stroke are, in the drawing's points.
    static let strokeSampleSpacing: CGFloat = 4
    /// The fewest points tested along a stroke shorter than that spacing allows, so a short
    /// stroke grazed at its end is measured as finely as a long one.
    static let minimumStrokeSampleCount = 16

    // MARK: The closed loop

    /// The loop as it selects and as it shows once the hand lifts: closed from its last point
    /// back to its first, whether or not the hand returned there.
    static func closed(_ loop: [CGPoint]) -> [CGPoint] {
        guard loop.count >= 2, let first = loop.first, loop.last != first else { return loop }
        return loop + [first]
    }

    /// Whether the point is inside the closed loop through the points, by the even-odd rule.
    /// The loop closes itself: its last point is joined to its first. Fewer than three points
    /// enclose nothing.
    static func isPoint(_ point: CGPoint, insideLoop loop: [CGPoint]) -> Bool {
        guard loop.count >= 3, var previous = loop.last else { return false }
        var isInside = false
        for current in loop {
            if (current.y > point.y) != (previous.y > point.y),
               point.x < (previous.x - current.x) * (point.y - current.y) / (previous.y - current.y) + current.x {
                isInside.toggle()
            }
            previous = current
        }
        return isInside
    }

    /// The share of the points that lies inside the loop; zero for no points.
    static func enclosedFraction(of points: [CGPoint], inLoop loop: [CGPoint]) -> Double {
        guard !points.isEmpty else { return 0 }
        return Double(points.filter { point in isPoint(point, insideLoop: loop) }.count) / Double(points.count)
    }

    /// The area the loop encloses once closed (by the shoelace formula, a figure eight's lobes
    /// counted against each other), in the loop's square points.
    static func enclosedArea(of loop: [CGPoint]) -> CGFloat {
        guard loop.count >= 3, var previous = loop.last else { return 0 }
        var twiceSignedArea: CGFloat = 0
        for current in loop {
            twiceSignedArea += previous.x * current.y - current.x * previous.y
            previous = current
        }
        return abs(twiceSignedArea) / 2
    }

    static func length(of loop: [CGPoint]) -> CGFloat {
        zip(loop, loop.dropFirst()).reduce(0) { total, pair in total + hypot(pair.1.x - pair.0.x, pair.1.y - pair.0.y) }
    }

    /// Whether a freehand loop is one, not a slip: at least three points, as long as
    /// `minimumLoopLength` and enclosing `minimumLoopArea` on screen once closed.
    static func isFreehandLoopLargeEnough(_ loop: [CGPoint], screenPointsPerLoopPoint: CGFloat) -> Bool {
        guard loop.count >= 3 else { return false }
        return length(of: loop) * screenPointsPerLoopPoint >= minimumLoopLength
            && enclosedArea(of: loop) * screenPointsPerLoopPoint * screenPointsPerLoopPoint >= minimumLoopArea
    }

    /// Whether a rectangle's loop is one, not a slip: both sides at least `tapReach` on screen.
    static func isRectangleLoopLargeEnough(_ loop: [CGPoint], screenPointsPerLoopPoint: CGFloat) -> Bool {
        let loopBounds = bounds(of: loop)
        guard !loopBounds.isNull else { return false }
        return min(loopBounds.width, loopBounds.height) * screenPointsPerLoopPoint >= tapReach
    }

    // MARK: What the loop takes

    /// How far apart to test points along a stroke whose path is this long: `strokeSampleSpacing`,
    /// or closer on a short stroke, so it has at least `minimumStrokeSampleCount` points.
    static func strokeSampleSpacing(forPathLength pathLength: CGFloat) -> CGFloat {
        guard pathLength > 0 else { return strokeSampleSpacing }
        return min(strokeSampleSpacing, pathLength / CGFloat(minimumStrokeSampleCount))
    }

    /// Whether the loop takes a stroke tested at these points, evenly spaced along it.
    static func takesStroke(sampledAt strokePoints: [CGPoint], inLoop loop: [CGPoint]) -> Bool {
        enclosedFraction(of: strokePoints, inLoop: loop) >= minimumEnclosedStrokeFraction
    }

    /// Whether the loop takes a picture or a text box filling `frame` before it is turned
    /// about its middle: `minimumEnclosedPictureFraction` of its area inside, or its middle
    /// inside with the loop also reaching past its edge.
    static func takesPicture(framed frame: CGRect, turnedBy rotationRadians: Double, inLoop loop: [CGPoint]) -> Bool {
        let samples = samplePoints(ofRectangle: frame, turnedBy: rotationRadians)
        if enclosedFraction(of: samples, inLoop: loop) >= minimumEnclosedPictureFraction { return true }
        guard isPoint(CGPoint(x: frame.midX, y: frame.midY), insideLoop: loop) else { return false }
        let outline = corners(ofRectangle: frame, turnedBy: rotationRadians)
        return loop.contains { loopPoint in !isPoint(loopPoint, insideLoop: outline) }
    }

    /// The smallest upright rectangle around the points; null for none.
    static func bounds(of points: [CGPoint]) -> CGRect {
        points.reduce(CGRect.null) { bounds, point in bounds.union(CGRect(origin: point, size: .zero)) }
    }

    /// The loop of a rectangular lasso dragged from one corner to the opposite one.
    static func rectangleLoop(from start: CGPoint, to end: CGPoint) -> [CGPoint] {
        [start, CGPoint(x: end.x, y: start.y), end, CGPoint(x: start.x, y: end.y)]
    }

    /// Points spread evenly over a rectangle turned about its middle, to measure how much
    /// of a picture a loop encloses.
    static func samplePoints(ofRectangle rectangle: CGRect, turnedBy rotationRadians: Double) -> [CGPoint] {
        let middle = CGPoint(x: rectangle.midX, y: rectangle.midY)
        let count = pictureSamplesPerSide
        return (0..<count).flatMap { row in
            (0..<count).map { column in
                let point = CGPoint(x: rectangle.minX + rectangle.width * (CGFloat(column) + 0.5) / CGFloat(count),
                                    y: rectangle.minY + rectangle.height * (CGFloat(row) + 0.5) / CGFloat(count))
                return PictureRotation.point(point, turnedBy: rotationRadians, about: middle)
            }
        }
    }

    /// The four corners of a rectangle turned about its middle, in order around it.
    static func corners(ofRectangle rectangle: CGRect, turnedBy rotationRadians: Double) -> [CGPoint] {
        let middle = CGPoint(x: rectangle.midX, y: rectangle.midY)
        return [CGPoint(x: rectangle.minX, y: rectangle.minY), CGPoint(x: rectangle.maxX, y: rectangle.minY),
                CGPoint(x: rectangle.maxX, y: rectangle.maxY), CGPoint(x: rectangle.minX, y: rectangle.maxY)].map { corner in
            PictureRotation.point(corner, turnedBy: rotationRadians, about: middle)
        }
    }

    // MARK: Carrying the selection

    /// The transform that carries what `frame` surrounds to where `newFrame` surrounds it:
    /// scaled in proportion by the change in width, and moved.
    static func transform(from frame: CGRect, to newFrame: CGRect) -> CGAffineTransform {
        guard frame.width > 0, frame.height > 0 else { return .identity }
        let scale = newFrame.width / frame.width
        return CGAffineTransform(translationX: -frame.minX, y: -frame.minY)
            .concatenating(CGAffineTransform(scaleX: scale, y: scale))
            .concatenating(CGAffineTransform(translationX: newFrame.minX, y: newFrame.minY))
    }
}
