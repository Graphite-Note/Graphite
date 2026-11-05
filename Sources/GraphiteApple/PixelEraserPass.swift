/**
 * File: PixelEraserPass.swift
 * ---------------------------
 * Layer: Apple
 * Description: Graphite's own pixel eraser: the path one touch of it sweeps, and the strokes of a drawing cut
 *              where it passes, as PencilKit's fixed-width eraser cuts them, at any width.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 04/11/2026
 */
import CoreGraphics
import Foundation
import PencilKit
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// The area one touch of the pixel eraser sweeps, in the drawing's points: a line of the eraser's
/// width through the touch's points, with round ends and joins, as a round tip drawn along them.
public struct PixelEraserSweep {
    /// The eraser's width in the drawing's points.
    public let width: CGFloat
    /// Every point the touch went through, in order, without repeats.
    public private(set) var points: [CGPoint] = []

    public init(width: CGFloat) {
        self.width = width.isFinite ? max(width, Self.narrowestWidth) : Self.narrowestWidth
    }

    /// A width narrower than this sweeps this much: a path of no width covers nothing.
    static let narrowestWidth: CGFloat = 0.01

    /// Takes the touch on through points; returns the area that part of the touch swept, from the
    /// last point before them on, or nil when the touch did not move on.
    ///
    /// A part after the first begins square at the last point, whose round end the part before
    /// already swept: two round ends over one another meet along a whole arc, and cutting one away
    /// after the other leaves slivers along it.
    @discardableResult
    public mutating func extend(through newPoints: [CGPoint]) -> CGPath? {
        var movedPoints: [CGPoint] = []
        for point in newPoints where point.x.isFinite && point.y.isFinite && point != (movedPoints.last ?? points.last) {
            movedPoints.append(point)
        }
        guard let lastMovedPoint = movedPoints.last else { return nil }
        defer { points += movedPoints }
        guard let lastPointBefore = points.last else { return Self.area(sweptAlong: movedPoints, width: width) }
        let line = CGMutablePath()
        line.move(to: lastPointBefore)
        line.addLines(between: [lastPointBefore] + movedPoints)
        let band = line.copy(strokingWithWidth: width, lineCap: .butt, lineJoin: .round, miterLimit: 10)
        return band.union(Self.spot(at: lastMovedPoint, width: width))
    }

    /// The whole area the touch swept.
    public var area: CGPath? { Self.area(sweptAlong: points, width: width) }

    /// The area a round tip of `width` covers when drawn through the points; a tip that never moved
    /// covers a round spot.
    public static func area(sweptAlong points: [CGPoint], width: CGFloat) -> CGPath? {
        guard let firstPoint = points.first else { return nil }
        guard points.contains(where: { point in point != firstPoint }) else { return spot(at: firstPoint, width: width) }
        let line = CGMutablePath()
        line.addLines(between: points)
        return line.copy(strokingWithWidth: width, lineCap: .round, lineJoin: .round, miterLimit: 10)
    }

    static func spot(at point: CGPoint, width: CGFloat) -> CGPath {
        CGPath(ellipseIn: CGRect(x: point.x - width / 2, y: point.y - width / 2, width: width, height: width), transform: nil)
    }

    /// How far a point is from the nearest of the segments.
    static func distance(from point: CGPoint, toNearestOf segments: [(start: CGPoint, end: CGPoint)]) -> CGFloat {
        var nearest = CGFloat.infinity
        for segment in segments {
            nearest = min(nearest, distance(from: point, toSegmentFrom: segment.start, to: segment.end))
        }
        return nearest
    }

    /// The segments between the touch's points, a touch that never moved being one of no length.
    static func segments(through linePoints: [CGPoint]) -> [(start: CGPoint, end: CGPoint)] {
        guard let firstPoint = linePoints.first else { return [] }
        guard linePoints.count > 1 else { return [(firstPoint, firstPoint)] }
        return zip(linePoints, linePoints.dropFirst()).map { start, end in (start, end) }
    }

    private static func distance(from point: CGPoint, toSegmentFrom start: CGPoint, to end: CGPoint) -> CGFloat {
        let segmentX = end.x - start.x, segmentY = end.y - start.y
        let squaredLength = segmentX * segmentX + segmentY * segmentY
        guard squaredLength > 0 else { return hypot(point.x - start.x, point.y - start.y) }
        let fraction = min(max(((point.x - start.x) * segmentX + (point.y - start.y) * segmentY) / squaredLength, 0), 1)
        return hypot(point.x - (start.x + segmentX * fraction), point.y - (start.y + segmentY * fraction))
    }
}

/// One touch of Graphite's pixel eraser across a drawing: the strokes it crosses are cut where it
/// passes, as PencilKit's fixed-width eraser cuts them, at any width (PencilKit makes its own no
/// narrower than 16.4 points of the screen).
///
/// PencilKit's eraser keeps a stroke's path and hides what it erased with the stroke's `mask`, the
/// part still shown, in the stroke's own space (moved with its transform); a stroke cut through
/// becomes one stroke for each piece, and one erased entirely is gone. A pass does the same: while
/// the touch moves, each stroke it crosses loses the area just swept from its mask, the strokes
/// being found by their bounds first, so a move costs the strokes it reaches, not the page's
/// (`FR-104`); when the touch lifts, `erasedDrawing` gives each piece of a stroke cut through its
/// own stroke. The drawing holds only strokes with masks, as PencilKit's eraser leaves them, which
/// PencilKit, every build of Graphite and its saved files read unchanged.
public struct PixelEraserPass {
    /// A point of a stroke's center line with the ink across it, in the drawing's points.
    struct InkSample {
        /// Where the point is on the stroke's path: 0 at the first control point, 1 at the next.
        let parametricValue: CGFloat
        let point: CGPoint
        /// Half the width the ink is drawn across its way there.
        let halfWidth: CGFloat
        /// The direction across the stroke there, of length 1.
        let across: CGVector
    }

    public let width: CGFloat
    /// The strokes as the drawing had them before the touch.
    private let originalStrokes: [PKStroke]
    private let strokeBounds: [CGRect]
    /// Where each stroke the touch cut still shows, in the stroke's own space: its mask to be.
    private var visibleAreasByStroke: [Int: CGPath] = [:]
    private var inkSamplesByStroke: [Int: [InkSample]] = [:]
    public private(set) var cutStrokeIndices = Set<Int>()
    private var erasedStrokeIndices = Set<Int>()
    private var sweep: PixelEraserSweep
    /// The segments between the touch's points so far.
    private var sweptSegments: [(start: CGPoint, end: CGPoint)] = []
    /// The strokes each cut stroke becomes, made while the touch moves on (`finishPieces`).
    private var piecesByStroke: [Int: [PKStroke]] = [:]
    /// The cut strokes whose pieces are still to be made, oldest cut first.
    private var strokesAwaitingPieces: [Int] = []
    /// The strokes the last move cut: the touch is still on them, so their pieces wait.
    private var strokesCutByLastMove = Set<Int>()

    public init(drawing: PKDrawing, width: CGFloat) {
        originalStrokes = drawing.strokes
        strokeBounds = originalStrokes.map(\.renderBounds)
        sweep = PixelEraserSweep(width: width)
        self.width = sweep.width
    }

    /// The points the touch has gone through so far, in the drawing's points.
    public var sweptPoints: [CGPoint] { sweep.points }

    /// Whether the touch has cut any stroke.
    public var hasCut: Bool { !cutStrokeIndices.isEmpty }

    /// The drawing erased along points by one touch of an eraser `width` wide.
    public static func erasing(_ drawing: PKDrawing, along points: [CGPoint], width: CGFloat) -> PKDrawing {
        var pass = PixelEraserPass(drawing: drawing, width: width)
        pass.sweep(through: points)
        return pass.erasedDrawing()
    }

    /// Takes the touch on through points of the drawing and cuts what it swept out of every stroke
    /// it reaches. Returns the area swept, nil when the touch did not move on.
    @discardableResult
    public mutating func sweep(through points: [CGPoint]) -> CGPath? {
        let lastPointBefore = sweep.points.last
        let pointCountBefore = sweep.points.count
        guard let sweptArea = sweep.extend(through: points) else { return nil }
        let newSegments = PixelEraserSweep.segments(through: (lastPointBefore.map { lastPoint in [lastPoint] } ?? []) + sweep.points[pointCountBefore...])
        sweptSegments += newSegments
        let sweptBounds = sweptArea.boundingBoxOfPath
        strokesCutByLastMove = []
        for strokeIndex in originalStrokes.indices where strokeBounds[strokeIndex].intersects(sweptBounds) && !erasedStrokeIndices.contains(strokeIndex) {
            cutStroke(at: strokeIndex, by: sweptArea, sweptAlong: newSegments)
        }
        return sweptArea
    }

    /// Makes the pieces of the strokes cut earlier in the touch, for at most `seconds`, so that
    /// the lift has little left to make: a stroke the touch has left is cut no more until it
    /// comes back, when its pieces are made again. Returns how many strokes still wait.
    @discardableResult
    public mutating func finishPieces(forAtMost seconds: Double) -> Int {
        let deadline = DispatchTime.now().uptimeNanoseconds + UInt64(max(seconds, 0) * 1_000_000_000)
        var waitingStrokes: [Int] = []
        for (position, strokeIndex) in strokesAwaitingPieces.enumerated() {
            guard DispatchTime.now().uptimeNanoseconds < deadline else {
                waitingStrokes += strokesAwaitingPieces[position...]
                break
            }
            guard !strokesCutByLastMove.contains(strokeIndex) else {
                waitingStrokes.append(strokeIndex)
                continue
            }
            piecesByStroke[strokeIndex] = erasedStrokeIndices.contains(strokeIndex)
                ? [] : pieces(ofStrokeAt: strokeIndex, sweptAlong: sweptSegments)
        }
        strokesAwaitingPieces = waitingStrokes
        return waitingStrokes.count
    }

    /// The drawing as the touch leaves it: a stroke cut through is one stroke for each piece left,
    /// in the stroke's place, and a stroke erased entirely is gone.
    public func erasedDrawing() -> PKDrawing {
        var erasedStrokes: [PKStroke] = []
        erasedStrokes.reserveCapacity(originalStrokes.count + cutStrokeIndices.count)
        for strokeIndex in originalStrokes.indices {
            guard cutStrokeIndices.contains(strokeIndex) else {
                erasedStrokes.append(originalStrokes[strokeIndex])
                continue
            }
            if erasedStrokeIndices.contains(strokeIndex) { continue }
            erasedStrokes += piecesByStroke[strokeIndex] ?? pieces(ofStrokeAt: strokeIndex, sweptAlong: sweptSegments)
        }
        return PKDrawing(strokes: erasedStrokes)
    }

    // MARK: Cutting

    private mutating func cutStroke(at strokeIndex: Int, by sweptArea: CGPath, sweptAlong sweptSegments: [(start: CGPoint, end: CGPoint)]) {
        let samples = cachedInkSamples(ofStrokeAt: strokeIndex)
        guard samples.contains(where: { sample in isReached(sample, bySegments: sweptSegments) }) else { return }
        let stroke = originalStrokes[strokeIndex]
        guard var drawingToStroke = Self.invertible(stroke.transform), let sweptAreaInStroke = sweptArea.copy(using: &drawingToStroke) else { return }
        let visibleArea = visibleAreasByStroke[strokeIndex] ?? Self.visibleAreaInStrokeSpace(of: stroke, inkBounds: strokeBounds[strokeIndex])
        let remainingArea = visibleArea.subtracting(sweptAreaInStroke)
        cutStrokeIndices.insert(strokeIndex)
        strokesCutByLastMove.insert(strokeIndex)
        // Pieces made before this cut are made again once the touch has left the stroke.
        piecesByStroke[strokeIndex] = nil
        if !strokesAwaitingPieces.contains(strokeIndex) { strokesAwaitingPieces.append(strokeIndex) }
        let remainingBounds = remainingArea.boundingBoxOfPath
        guard !remainingArea.isEmpty, !remainingBounds.isNull, remainingBounds.width > 0, remainingBounds.height > 0 else {
            erasedStrokeIndices.insert(strokeIndex)
            return
        }
        visibleAreasByStroke[strokeIndex] = remainingArea
    }

    /// Whether the eraser, along the segments, reached the ink across a sample.
    private func isReached(_ sample: InkSample, bySegments segments: [(start: CGPoint, end: CGPoint)]) -> Bool {
        let reach = sample.halfWidth + width / 2
        let nearSegments = segments.filter { segment in
            sample.point.x >= min(segment.start.x, segment.end.x) - reach && sample.point.x <= max(segment.start.x, segment.end.x) + reach
                && sample.point.y >= min(segment.start.y, segment.end.y) - reach && sample.point.y <= max(segment.start.y, segment.end.y) + reach
        }
        return !nearSegments.isEmpty && PixelEraserSweep.distance(from: sample.point, toNearestOf: nearSegments) <= reach
    }

    /// Where a stroke shows, in its own space, filled with the nonzero rule: its mask, or the
    /// rectangle around its ink when nothing of it was erased yet. The rectangle keeps the stroke's
    /// bounds as small as its ink: PencilKit gives a masked stroke the bounds of its mask.
    private static func visibleAreaInStrokeSpace(of stroke: PKStroke, inkBounds: CGRect) -> CGPath {
        if let mask = stroke.mask {
            #if canImport(UIKit)
            let usesEvenOddRule = mask.usesEvenOddFillRule
            #else
            let usesEvenOddRule = mask.windingRule == .evenOdd
            #endif
            return usesEvenOddRule ? mask.cgPath.normalized(using: .evenOdd) : mask.cgPath
        }
        let boundsInStroke = invertible(stroke.transform).map { drawingToStroke in inkBounds.applying(drawingToStroke) } ?? inkBounds
        return CGPath(rect: boundsInStroke.insetBy(dx: -inkBoundsMargin, dy: -inkBoundsMargin), transform: nil)
    }

    /// Room around a stroke's ink for what PencilKit draws past its bounds, in points.
    private static let inkBoundsMargin: CGFloat = 2

    private static func invertible(_ transform: CGAffineTransform) -> CGAffineTransform? {
        let determinant = transform.a * transform.d - transform.b * transform.c
        guard determinant.isFinite, abs(determinant) > 1e-9 else { return nil }
        return transform.inverted()
    }

    // MARK: Samples

    /// The distance between two samples along a stroke at most, in the stroke's own points: finer
    /// than the narrowest cut.
    private static let sampleSpacing: CGFloat = 0.5

    private mutating func cachedInkSamples(ofStrokeAt strokeIndex: Int) -> [InkSample] {
        if let samples = inkSamplesByStroke[strokeIndex] { return samples }
        let samples = Self.inkSamples(of: originalStrokes[strokeIndex])
        inkSamplesByStroke[strokeIndex] = samples
        return samples
    }

    /// Points of the stroke's center line, close together, with the ink across them, in the drawing's points.
    static func inkSamples(of stroke: PKStroke) -> [InkSample] {
        let controlPoints = Array(stroke.path)
        guard let firstControlPoint = controlPoints.first else { return [] }
        let transform = stroke.transform
        let widthScale = abs(transform.a * transform.d - transform.b * transform.c).squareRoot()
        let inkType = stroke.ink.inkType
        // Each run between two control points is sampled as finely as its length asks.
        var parametricValues: [CGFloat] = []
        for (controlIndex, pair) in zip(controlPoints, controlPoints.dropFirst()).enumerated() {
            let controlGap = hypot(pair.1.location.x - pair.0.location.x, pair.1.location.y - pair.0.location.y)
            let stepCount = max(Int((controlGap / sampleSpacing).rounded(.up)), 1)
            for step in 0..<stepCount { parametricValues.append(CGFloat(controlIndex) + CGFloat(step) / CGFloat(stepCount)) }
        }
        parametricValues.append(CGFloat(controlPoints.count - 1))
        let path = stroke.path
        let interpolatedPoints = controlPoints.count > 1
            ? parametricValues.map { parametricValue in path.interpolatedPoint(at: parametricValue) } : [firstControlPoint]
        return interpolatedPoints.indices.map { pointIndex in
            let strokePoint = interpolatedPoints[pointIndex]
            let earlier = interpolatedPoints[max(pointIndex - 1, 0)].location
            let later = interpolatedPoints[min(pointIndex + 1, interpolatedPoints.count - 1)].location
            let alongX = (later.x - earlier.x) * transform.a + (later.y - earlier.y) * transform.c
            let alongY = (later.x - earlier.x) * transform.b + (later.y - earlier.y) * transform.d
            let alongLength = hypot(alongX, alongY)
            let across = alongLength > 0 ? CGVector(dx: -alongY / alongLength, dy: alongX / alongLength) : CGVector(dx: 0, dy: 1)
            let nibAcrossness = earlier == later ? 1 : abs(sin(Double(strokePoint.azimuth) - atan2(Double(later.y - earlier.y), Double(later.x - earlier.x))))
            let drawnWidth = PencilInkRenderedWidth.drawnWidth(forPointSize: Double(max(strokePoint.size.width, strokePoint.size.height)),
                                                               inkType: inkType, nibAcrossness: nibAcrossness)
            return InkSample(parametricValue: parametricValues[min(pointIndex, parametricValues.count - 1)], point: strokePoint.location.applying(transform),
                             halfWidth: CGFloat(drawnWidth) * widthScale / 2, across: across)
        }
    }

    // MARK: Pieces

    /// Where across its ink a sample is looked at, in shares of half its width either side of the center line.
    private static let probedSharesOfHalfWidth: [CGFloat] = [0, 0.5, -0.5, 0.95, -0.95]
    /// How much wider than its widest point a piece's own area is, for what PencilKit draws past a point's width.
    private static let pieceAreaWidthFactor: CGFloat = 3

    /// The strokes a cut stroke becomes: one for each run of its center line whose ink still shows,
    /// none when nothing shows. A stroke still in one piece keeps its mask. Each piece keeps the whole
    /// path, as PencilKit's eraser keeps it, and a mask of its own run alone, so no two pieces draw
    /// over one another, as a translucent ink would show. (A piece given only the control points of
    /// its run is drawn differently in a pencil's grain and a highlighter's end.)
    private func pieces(ofStrokeAt strokeIndex: Int, sweptAlong sweptSegments: [(start: CGPoint, end: CGPoint)]) -> [PKStroke] {
        let stroke = originalStrokes[strokeIndex]
        let samples = inkSamplesByStroke[strokeIndex] ?? Self.inkSamples(of: stroke)
        guard let visibleArea = visibleAreasByStroke[strokeIndex], !samples.isEmpty,
              var drawingToStroke = Self.invertible(stroke.transform) else { return [stroke] }
        let originalArea = stroke.mask.map { _ in Self.visibleAreaInStrokeSpace(of: stroke, inkBounds: strokeBounds[strokeIndex]) }
        let strokeReach = strokeBounds[strokeIndex].insetBy(dx: -width, dy: -width)
        let nearSegments = sweptSegments.filter { segment in
            strokeReach.intersects(CGRect(x: min(segment.start.x, segment.end.x), y: min(segment.start.y, segment.end.y),
                                          width: abs(segment.end.x - segment.start.x), height: abs(segment.end.y - segment.start.y)))
        }
        // The mask is what showed before less the area swept, which is every point within half the
        // eraser's width of the touch's line: a probe is looked up by its distance, not in the mask.
        let halfEraserWidth = width / 2
        let isShown = samples.map { sample in
            let isNearTouch = isReached(sample, bySegments: nearSegments)
            return Self.probes(of: sample).contains { probe in
                if isNearTouch, PixelEraserSweep.distance(from: probe, toNearestOf: nearSegments) <= halfEraserWidth { return false }
                return originalArea?.contains(probe.applying(drawingToStroke), using: .winding) ?? true
            }
        }
        let runs = Self.shownRuns(isShown)
        guard runs.count > 1 else {
            return runs.isEmpty ? [] : [PKStroke(ink: stroke.ink, path: stroke.path, transform: stroke.transform,
                                                 mask: PlatformBezierPath(cgPath: visibleArea), randomSeed: stroke.randomSeed)]
        }
        let pieceWidth = (samples.map(\.halfWidth).max() ?? 0) * 2 * Self.pieceAreaWidthFactor + Self.inkBoundsMargin * 2
        return runs.compactMap { run in
            // From the erased sample before the run to the one after it, square there, round at the stroke's own ends.
            let firstIndex = max(run.lowerBound - 1, 0), lastIndex = min(run.upperBound + 1, samples.count - 1)
            // Every few samples are enough for an area this much wider than the ink.
            let runPoints = Self.everyFew(samples[firstIndex...lastIndex].map(\.point))
            let runArea = Self.area(along: runPoints, width: pieceWidth,
                                    roundStart: firstIndex == 0, roundEnd: lastIndex == samples.count - 1)
            guard let runAreaInStroke = runArea?.copy(using: &drawingToStroke) else { return nil }
            return PKStroke(ink: stroke.ink, path: stroke.path, transform: stroke.transform,
                            mask: PlatformBezierPath(cgPath: visibleArea.intersection(runAreaInStroke)), randomSeed: stroke.randomSeed)
        }
    }

    /// How many samples a piece's area skips between the points it goes through.
    private static let runAreaSampleStride = 4

    /// Every `runAreaSampleStride`-th point, the first and the last always.
    private static func everyFew(_ points: [CGPoint]) -> [CGPoint] {
        guard points.count > 2, let lastPoint = points.last else { return points }
        var keptPoints = Swift.stride(from: 0, to: points.count - 1, by: runAreaSampleStride).map { pointIndex in points[pointIndex] }
        keptPoints.append(lastPoint)
        return keptPoints
    }

    /// The runs of samples that show, in order.
    static func shownRuns(_ isShown: [Bool]) -> [ClosedRange<Int>] {
        var runs: [ClosedRange<Int>] = []
        var runStart: Int?
        for (sampleIndex, shows) in isShown.enumerated() {
            if shows, runStart == nil { runStart = sampleIndex }
            if !shows, let start = runStart {
                runs.append(start...(sampleIndex - 1))
                runStart = nil
            }
        }
        if let runStart { runs.append(runStart...(isShown.count - 1)) }
        return runs
    }

    /// The area along points, `width` wide, with round or square ends.
    private static func area(along points: [CGPoint], width: CGFloat, roundStart: Bool, roundEnd: Bool) -> CGPath? {
        guard let firstPoint = points.first, let lastPoint = points.last, points.count > 1 else {
            return points.first.map { point in PixelEraserSweep.spot(at: point, width: width) }
        }
        let line = CGMutablePath()
        line.addLines(between: points)
        var area = line.copy(strokingWithWidth: width, lineCap: .butt, lineJoin: .round, miterLimit: 10)
        if roundStart { area = area.union(PixelEraserSweep.spot(at: firstPoint, width: width)) }
        if roundEnd { area = area.union(PixelEraserSweep.spot(at: lastPoint, width: width)) }
        return area
    }

    /// Where ink is looked for across a sample: its middle and towards both edges.
    private static func probes(of sample: InkSample) -> [CGPoint] {
        probedSharesOfHalfWidth.map { share in
            let reach = sample.halfWidth * share
            return CGPoint(x: sample.point.x + sample.across.dx * reach, y: sample.point.y + sample.across.dy * reach)
        }
    }
}

#if canImport(UIKit)
private typealias PlatformBezierPath = UIBezierPath
#else
private typealias PlatformBezierPath = NSBezierPath
#endif
