/**
 * File: InkLassoStrokes.swift
 * ---------------------------
 * Layer: UI
 * Description: Where a PencilKit stroke runs on the page for Graphite's lasso: its points placed by the
 *              stroke's own transform, spaced and reached in the page's points, whatever zoom drew it.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 05/11/2026
 */
import CoreGraphics
import PencilKit

/// A stroke as the lasso tests it: in the drawing's coordinates, which are the page's points on
/// a PDF page at any zoom of the PDF view and any part of the page its canvas covers
/// (`PDFCanvasShownRegion`). A stroke's path is in its own coordinates and its `transform`
/// places it in the drawing: PencilKit's own lasso moves and resizes a stroke through it, and a
/// stroke may be stored with its points at another scale than the page's. Every distance here,
/// the spacing of the points tested and how far a tap reaches the ink, is on the page, so a
/// stroke is taken alike however it is stored.
extension InkLasso {
    /// How many times a transform enlarges what it carries, by area: 1 for one that is not a
    /// number or flattens everything.
    static func enlargement(of transform: CGAffineTransform) -> CGFloat {
        let enlargement = abs(transform.a * transform.d - transform.b * transform.c).squareRoot()
        return enlargement.isFinite && enlargement > 0 ? enlargement : 1
    }

    /// Where a stroke runs, in the drawing's coordinates: points along its path placed by its
    /// transform, `strokeSampleSpacing` apart on the page or closer on a short stroke
    /// (`strokeSampleSpacing(forPathLength:)` of its length on the page). A dot, such as the
    /// dot of an "i", has a single point, from which PencilKit interpolates none; it is its own
    /// point then, or the middle of its ink, so a loop around it takes it.
    static func pageSamplePoints(of stroke: PKStroke) -> [CGPoint] {
        let enlargement = enlargement(of: stroke.transform)
        let lengthOnPage = length(of: stroke.path.map(\.location)) * enlargement
        let spacingInPath = strokeSampleSpacing(forPathLength: lengthOnPage) / enlargement
        let interpolated = stroke.path.interpolatedPoints(by: .distance(spacingInPath)).map { point in point.location.applying(stroke.transform) }
        if !interpolated.isEmpty { return interpolated }
        let controlPoints = stroke.path.map { point in point.location.applying(stroke.transform) }
        if !controlPoints.isEmpty { return controlPoints }
        return [CGPoint(x: stroke.renderBounds.midX, y: stroke.renderBounds.midY)]
    }

    /// Whether a loop in the drawing's coordinates, closed from its last point to its first,
    /// takes the stroke: `minimumEnclosedStrokeFraction` of its length on the page inside it.
    static func takesStroke(_ stroke: PKStroke, inLoop loop: [CGPoint]) -> Bool {
        let loopBounds = bounds(of: loop)
        guard !loopBounds.isNull, stroke.renderBounds.intersects(loopBounds) else { return false }
        return takesStroke(sampledAt: pageSamplePoints(of: stroke), inLoop: loop)
    }

    /// Whether the stroke's ink passes within `reach` of a point, both in the drawing's
    /// coordinates: a point of its path is as far from the edge of its ink as half its width on
    /// the page, its stored size enlarged by the stroke's transform. A dot without points to
    /// interpolate is reached anywhere within its ink's bounds and the reach.
    static func stroke(_ stroke: PKStroke, passesWithin reach: CGFloat, of point: CGPoint) -> Bool {
        guard stroke.renderBounds.insetBy(dx: -reach, dy: -reach).contains(point) else { return false }
        let enlargement = enlargement(of: stroke.transform)
        let inkPoints = stroke.path.interpolatedPoints(by: .distance(strokeSampleSpacing / enlargement)).map { strokePoint in
            (location: strokePoint.location.applying(stroke.transform), radius: strokePoint.size.width / 2 * enlargement)
        }
        guard !inkPoints.isEmpty else { return true }
        return inkPoints.contains { location, radius in hypot(location.x - point.x, location.y - point.y) <= reach + radius }
    }
}
