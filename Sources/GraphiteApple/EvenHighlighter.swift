/**
 * File: EvenHighlighter.swift
 * ---------------------------
 * Layer: Apple
 * Description: Graphite's even highlighter: a marker stroke drawn again through its points with one upright tip as
 *              wide as the tool, at an even pressure, in a color that leaves the text under it readable.
 *
 * Authors: Bahey Shalash
 * Version: 0.3
 * Date: 16/11/2026
 */
#if canImport(UIKit)
import Foundation
import PencilKit

/// Graphite's even highlighter. PencilKit's marker draws as a felt tip does: broader as
/// Apple Pencil tilts, and broader or finer as it turns, so the same highlight over a line
/// of text comes out a different height each time. With the even highlighter, a marker
/// stroke just drawn is drawn again through the same points with one tip as wide as the tool,
/// at an even pressure, turned across the stroke at every point, whatever the angle the
/// Pencil was held at: a highlight is as tall across a line of text as the tool is wide, and
/// as wide in any other direction.
///
/// PencilKit gives no way to change a stroke while it is drawn, and its live stroke follows
/// the Pencil's tilt. So while the even highlighter is in use, the canvas draws with an
/// invisible stand-in of the tool (`invisibleStandIn(for:)`) and shows the stroke itself: the
/// even stroke through the points so far, drawn by PencilKit (`evenStroke(through:width:ink:)`),
/// until the even stroke replaces the invisible one at the lift (`HistoryCanvasView`).
public enum EvenHighlighter {
    /// The angle of an upright tip: the Pencil held straight up from the page.
    static let uprightAltitude: CGFloat = .pi / 2
    /// The direction of the tip on a stroke along the page's rows: PencilKit's marker tip is
    /// a chisel, and turned this way its long side stands across the rows, as an upright
    /// Pencil's and a finger's do. On a stroke in any other direction the tip turns with it.
    static let tipAzimuth: CGFloat = .pi / 2
    /// How much longer than a point's size the marker's chisel draws, measured on PencilKit
    /// (iOS 27, macOS 27): a point of size 38 draws a band 57 to 58 points tall across a
    /// horizontal stroke, and PencilKit gives a finger's or an upright Pencil's points two
    /// thirds of the tool's width. An earlier version gave the points the whole width,
    /// lengthwise, which drew highlights about 40 percent thinner than the tool.
    public static let chiselLengthPerPointSize: CGFloat = 1.5
    /// The opacity of every point. PencilKit gives a marker's points more than 1, and less the
    /// faster the Pencil moves (1.5 down to about 1.3 for a quick finger stroke), and draws
    /// them stronger the more they have: 1 draws the color at about four fifths, 1.5 at about
    /// nine tenths. The even stroke takes the value of a slow, steady stroke everywhere.
    public static let tipOpacity: CGFloat = 1.5
    /// The pressure of every point: one for the whole stroke, which the stroke shown while it is
    /// drawn also has, before its average could be known (HUNT-356).
    static let tipForce: CGFloat = 1
    /// The random seed of every even stroke's texture, which the stroke shown while it is drawn
    /// also has: the seed of the stroke PencilKit makes is known only at the lift (HUNT-356).
    static let textureSeed: UInt32 = 0
    /// How much of the highlighter color's alpha the even stroke's ink keeps. PencilKit draws a
    /// canvas's ink over a PDF's page in the normal blend, so the even stroke at the color's full
    /// alpha drew its band at nine tenths of the color and hid the text under it: on the owner's
    /// iPad on 2026-11-04 a black bar under the band showed 0.87 as light as the band beside it
    /// (HUNT-002). At this fraction the band is about half the color, as PencilKit's own
    /// highlighter drew the same stroke on the simulator, and the text stays dark under it. The
    /// stroke shown while it is drawn takes the same color, so nothing changes at the lift.
    public static let colorAlphaFraction: CGFloat = 0.55

    /// The color the even stroke draws in for the highlighter's color.
    public static func inkColor(for highlighterColor: UIColor) -> UIColor {
        highlighterColor.withAlphaComponent(highlighterColor.cgColor.alpha * colorAlphaFraction)
    }

    /// The stroke with every point's tip drawing a band `width` points across in the
    /// drawing, turned across the stroke and at one pressure, in `ink`
    /// (the stroke's own when nil). Nil for a stroke that is not marker ink or has no points,
    /// and for a width that is not a positive number.
    public static func evenStroke(_ stroke: PKStroke, width: CGFloat, ink: PKInk? = nil) -> PKStroke? {
        let controlPoints = Array(stroke.path)
        guard stroke.ink.inkType == .marker, !controlPoints.isEmpty, width.isFinite, width > 0 else { return nil }
        // A point's size is in the stroke's own coordinates, which its transform scales
        // into the drawing's.
        let transform = stroke.transform
        let transformScale = abs(transform.a * transform.d - transform.b * transform.c).squareRoot()
        guard transformScale.isFinite, transformScale > 0 else { return nil }
        let tipSide = width / chiselLengthPerPointSize / transformScale
        let tipSize = CGSize(width: tipSide, height: tipSide)
        let azimuths = tipAzimuths(along: controlPoints.map(\.location), reach: tipSide)
        let evenPoints = zip(controlPoints, azimuths).map { point, azimuth in
            PKStrokePoint(location: point.location, timeOffset: point.timeOffset, size: tipSize, opacity: tipOpacity,
                          force: tipForce, azimuth: azimuth, altitude: uprightAltitude)
        }
        // One random seed for every even stroke: the ink's texture is the one shown while the stroke was drawn.
        return PKStroke(ink: ink ?? stroke.ink, path: PKStrokePath(controlPoints: evenPoints, creationDate: stroke.path.creationDate),
                        transform: transform, mask: stroke.mask, randomSeed: textureSeed)
    }

    /// The tip's direction at each point: across the stroke there, from the points `reach`
    /// before and after it, so a hand's tremble does not turn it. A stroke too short to have
    /// a direction, as a dot, has the tip of a stroke along the rows.
    static func tipAzimuths(along locations: [CGPoint], reach: CGFloat) -> [CGFloat] {
        func distance(_ first: CGPoint, _ second: CGPoint) -> CGFloat { hypot(second.x - first.x, second.y - first.y) }
        let directedAzimuths: [CGFloat?] = locations.indices.map { pointIndex in
            let location = locations[pointIndex]
            var earlierIndex = pointIndex
            while earlierIndex > 0, distance(locations[earlierIndex], location) < reach { earlierIndex -= 1 }
            var laterIndex = pointIndex
            while laterIndex < locations.count - 1, distance(locations[laterIndex], location) < reach { laterIndex += 1 }
            let earlier = locations[earlierIndex], later = locations[laterIndex]
            guard distance(earlier, later) > 0 else { return nil }
            return atan2(later.y - earlier.y, later.x - earlier.x) + tipAzimuth
        }
        // A point without a direction of its own takes the one before it, or the first.
        var lastAzimuth = directedAzimuths.compactMap { azimuth in azimuth }.first ?? tipAzimuth
        return directedAzimuths.map { azimuth in
            if let azimuth { lastAzimuth = azimuth }
            return lastAzimuth
        }
    }

    /// A tool that draws nothing, with the highlighter's width and ink type, for the canvas
    /// to draw with while the even highlighter is in use: its live stroke would follow the
    /// Pencil's tilt and then change at the lift.
    public static func invisibleStandIn(for highlighter: PKInkingTool) -> PKInkingTool {
        let invisibleColor = highlighter.color.withAlphaComponent(0)
        return PKInkingTool(highlighter.inkType, color: invisibleColor, width: highlighter.width, azimuth: highlighter.azimuth)
    }

    /// Whether ink is the invisible stand-in's, which no stroke may keep.
    public static func isInvisible(_ ink: PKInk) -> Bool {
        ink.inkType == .marker && ink.color.cgColor.alpha == 0
    }

    /// The even stroke through points of the drawing, as it will be once the Pencil lifts, for
    /// the canvas to show while the stroke is drawn: PencilKit draws it, so what is shown during
    /// the stroke is what is kept after it (HUNT-356). Nil without points or a usable width.
    public static func evenStroke(through locations: [CGPoint], width: CGFloat, ink: PKInk) -> PKStroke? {
        let drawnPoints = locations.enumerated().map { pointIndex, location in
            PKStrokePoint(location: location, timeOffset: TimeInterval(pointIndex) * timeBetweenShownPoints, size: CGSize(width: width, height: width),
                          opacity: tipOpacity, force: tipForce, azimuth: tipAzimuth, altitude: uprightAltitude)
        }
        let drawnStroke = PKStroke(ink: PKInk(.marker, color: ink.color), path: PKStrokePath(controlPoints: drawnPoints, creationDate: shownStrokeCreationDate))
        return evenStroke(drawnStroke, width: width, ink: ink)
    }

    /// The time between the points of a stroke shown while it is drawn; a marker's look does not depend on it.
    static let timeBetweenShownPoints: TimeInterval = 0.008
    /// The creation date of a stroke only shown, never kept; how it looks does not depend on it.
    static let shownStrokeCreationDate = Date(timeIntervalSinceReferenceDate: 0)
}
#endif
