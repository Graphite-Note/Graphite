/**
 * File: PencilInkRenderedWidth.swift
 * ----------------------------------
 * Layer: Apple
 * Description: How wide PencilKit draws a stroke point of a given size, for each ink an imported stroke
 *              uses.
 *
 * Authors: Bahey Shalash
 * Version: 0.6
 * Date: 13/11/2026
 */
import Foundation
import PencilKit
import GraphiteCore
import NotebookImport

/// How wide PencilKit draws a stroke point of a given size, for each ink an imported stroke uses. A point's
/// `PKStrokePoint.size` is not the width PencilKit draws, and the relation differs for each ink.
///
/// Measured from `PKDrawing.image(from:scale:)`, which draws identically on iPadOS 27 and macOS 27: straight strokes at
/// 4 pixels per point, counting as ink the rows at least half as opaque as the stroke's middle, averaged over three
/// renderings. Force, altitude and drawing speed do not change the drawn width of stored points. The azimuth turns
/// the fountain pen's nib and the marker's tip; the widths here are with them across the stroke, as
/// `ImportedStrokeBuilder` turns them, and `nibTurnMeasurements` tells the rest of the way round. The pencil's grain
/// makes its edge vary by about 2%.
enum PencilInkRenderedWidth {
    /// One measurement: a point size and the width PencilKit draws it, both in points.
    struct Measurement: Equatable {
        let pointSize: Double
        let renderedWidth: Double
    }

    /// Monoline, pen and the fountain pen across: exactly twice the size less 4 points, nothing below a size of 2.
    static let solidInkMeasurements = [Measurement(pointSize: 2, renderedWidth: 0), Measurement(pointSize: 48, renderedWidth: 92)]
    static let pencilMeasurements = [
        Measurement(pointSize: 0.25, renderedWidth: 0.14), Measurement(pointSize: 0.5, renderedWidth: 0.41),
        Measurement(pointSize: 0.75, renderedWidth: 0.67), Measurement(pointSize: 1, renderedWidth: 0.99),
        Measurement(pointSize: 1.25, renderedWidth: 1.39), Measurement(pointSize: 1.5, renderedWidth: 1.95),
        Measurement(pointSize: 1.75, renderedWidth: 2.63), Measurement(pointSize: 2, renderedWidth: 3.07),
        Measurement(pointSize: 2.5, renderedWidth: 4.04), Measurement(pointSize: 3, renderedWidth: 4.96),
        Measurement(pointSize: 4, renderedWidth: 6.82), Measurement(pointSize: 6, renderedWidth: 10.35),
        Measurement(pointSize: 8, renderedWidth: 13.75), Measurement(pointSize: 12, renderedWidth: 20.7),
        Measurement(pointSize: 16, renderedWidth: 27.6), Measurement(pointSize: 24, renderedWidth: 40.9),
        Measurement(pointSize: 32, renderedWidth: 55.4), Measurement(pointSize: 48, renderedWidth: 82.8)
    ]
    static let markerMeasurements = [
        Measurement(pointSize: 0.25, renderedWidth: 0.12), Measurement(pointSize: 0.5, renderedWidth: 0.36),
        Measurement(pointSize: 0.75, renderedWidth: 0.97), Measurement(pointSize: 1, renderedWidth: 1.5),
        Measurement(pointSize: 1.5, renderedWidth: 2), Measurement(pointSize: 2, renderedWidth: 2.5),
        Measurement(pointSize: 2.5, renderedWidth: 3.5), Measurement(pointSize: 3, renderedWidth: 4),
        Measurement(pointSize: 4, renderedWidth: 5.29), Measurement(pointSize: 5, renderedWidth: 6.75),
        Measurement(pointSize: 6, renderedWidth: 8), Measurement(pointSize: 8, renderedWidth: 10.75),
        Measurement(pointSize: 12, renderedWidth: 16.25), Measurement(pointSize: 16, renderedWidth: 21.5),
        Measurement(pointSize: 24, renderedWidth: 32.5), Measurement(pointSize: 32, renderedWidth: 43.75),
        Measurement(pointSize: 48, renderedWidth: 65.63)
    ]

    /// How much of its width across the stroke a turning ink draws with its nib part way round: the nib's angle to the
    /// stroke's way is written as the sine of it, every 15 degrees (and at 7.5) from along it (0) to across it (1). Measured at 8 pixels
    /// per point, sizes 5, 12 and 24 agreeing to 0.02 (2026-11-02). A straight line between the two ends drew 22% too wide
    /// for a fountain pen at 15 degrees. The fountain pen's nib draws as an ellipse does; the marker's tip does not.
    private static let nibAcrossnessSteps = [0, 0.1305, 0.259, 0.5, 0.707, 0.866, 0.966, 1]
    private static let fountainPenNibTurnMeasurements = [0.25, 0.28, 0.365, 0.545, 0.735, 0.875, 0.962, 1]
    private static let markerNibTurnMeasurements = [0.362, 0.39, 0.466, 0.623, 0.771, 0.897, 0.977, 1]

    private static func fractionOfWidthAcross(nibAcrossness: Double, measurements: [Double]) -> Double {
        let acrossness = min(max(nibAcrossness, 0), 1)
        let upperIndex = max(nibAcrossnessSteps.firstIndex { step in step >= acrossness } ?? nibAcrossnessSteps.count - 1, 1)
        let lowerStep = nibAcrossnessSteps[upperIndex - 1], upperStep = nibAcrossnessSteps[upperIndex]
        let lower = measurements[upperIndex - 1], upper = measurements[upperIndex]
        return lower + (acrossness - lowerStep) * (upper - lower) / (upperStep - lowerStep)
    }

    /// In increasing order of both size and width.
    static func measurements(for ink: ImportedStroke.Ink) -> [Measurement] {
        switch ink {
        case .monoline, .pen, .fountainPen: solidInkMeasurements
        case .pencil: pencilMeasurements
        case .highlighter: markerMeasurements
        }
    }

    /// The tables of the inks whose drawn width does not turn with the nib. PencilKit's ink types are not frozen, so
    /// the measured inks are named, by the raw name of their ink type, and every other one has none.
    private static let measurementsByInkName: [String: [Measurement]] = [
        PKInkingTool.InkType.pen.rawValue: solidInkMeasurements, PKInkingTool.InkType.monoline.rawValue: solidInkMeasurements,
        PKInkingTool.InkType.pencil.rawValue: pencilMeasurements
    ]

    /// The width PencilKit draws a point of `pointSize` in this ink, interpolated as `pointSize(forRenderedWidth:ink:)`
    /// is, or nil for an ink whose drawn width turns with its nib (fountain pen, highlighter) or was not measured
    /// (crayon, watercolor, reed pen): for those the point size is the best width there is. Below a size of 2 the pen
    /// and the monoline draw nothing.
    static func renderedWidth(forPointSize pointSize: Double, inkType: PKInkingTool.InkType) -> Double? {
        guard let table = measurementsByInkName[inkType.rawValue], let narrowest = table.first, table.count > 1,
              pointSize.isFinite, pointSize > 0 else { return nil }
        if pointSize <= narrowest.pointSize { return narrowest.renderedWidth * pointSize / narrowest.pointSize }
        let upperIndex = max(table.firstIndex { measurement in measurement.pointSize >= pointSize } ?? table.count - 1, 1)
        let lower = table[upperIndex - 1], upper = table[upperIndex]
        return lower.renderedWidth + (pointSize - lower.pointSize) * (upper.renderedWidth - lower.renderedWidth) / (upper.pointSize - lower.pointSize)
    }

    /// The tables of every ink measured, turning inks included, with their nib across the stroke.
    private static func acrossMeasurements(forInkType inkType: PKInkingTool.InkType) -> [Measurement]? {
        switch inkType {
        case .pen, .monoline, .fountainPen: solidInkMeasurements
        case .pencil: pencilMeasurements
        case .marker: markerMeasurements
        default: nil
        }
    }

    private static func interpolatedWidth(forPointSize pointSize: Double, in table: [Measurement]) -> Double {
        guard let narrowest = table.first, table.count > 1 else { return pointSize }
        if pointSize <= narrowest.pointSize { return narrowest.renderedWidth * pointSize / narrowest.pointSize }
        let upperIndex = max(table.firstIndex { measurement in measurement.pointSize >= pointSize } ?? table.count - 1, 1)
        let lower = table[upperIndex - 1], upper = table[upperIndex]
        return lower.renderedWidth + (pointSize - lower.pointSize) * (upper.renderedWidth - lower.renderedWidth) / (upper.pointSize - lower.pointSize)
    }

    /// How wide PencilKit draws a point of a stroke across its way, for saved outlines: a turning
    /// ink draws as its table tells with its nib across the stroke and a part of that as the nib
    /// turns (`nibAcrossnessSteps`; along the stroke the fountain pen draws a quarter, the marker
    /// 0.36). `nibAcrossness` is the sine of the nib's angle to the stroke: 1 across, 0 along. An
    /// ink not measured keeps its point size.
    static func drawnWidth(forPointSize pointSize: Double, inkType: PKInkingTool.InkType, nibAcrossness: Double) -> Double {
        guard pointSize.isFinite, pointSize > 0, let table = acrossMeasurements(forInkType: inkType) else { return pointSize }
        let across = interpolatedWidth(forPointSize: pointSize, in: table)
        switch inkType {
        case .fountainPen: return across * fractionOfWidthAcross(nibAcrossness: nibAcrossness, measurements: fountainPenNibTurnMeasurements)
        case .marker: return across * fractionOfWidthAcross(nibAcrossness: nibAcrossness, measurements: markerNibTurnMeasurements)
        default: return across
        }
    }

    /// The point size that draws a stroke `scale` times as wide as a point of `pointSize` draws:
    /// a point's size is not its drawn width, so multiplying it would not scale what is seen
    /// (a pen's point of 4.8 draws 5.6; at half the size 2.4 draws 0.8, and below 2 nothing).
    /// An ink not measured, and a point too small to draw, go by the scale.
    static func pointSize(_ pointSize: Double, forDrawnWidthScaledBy scale: Double, inkType: PKInkingTool.InkType) -> Double {
        guard scale.isFinite, scale > 0, pointSize.isFinite, pointSize > 0, let table = acrossMeasurements(forInkType: inkType) else
            { return pointSize * scale }
        let drawnWidth = interpolatedWidth(forPointSize: pointSize, in: table)
        guard drawnWidth > 0 else { return pointSize * scale }
        return Self.pointSize(forRenderedWidth: drawnWidth * scale, in: table)
    }

    /// The point size PencilKit draws `drawnWidth` points wide across the stroke in this ink type, for ink made from a
    /// width rather than a Pencil, as the Mac's pointer draws it; the width itself for an ink not measured.
    static func pointSize(forDrawnWidth drawnWidth: Double, inkType: PKInkingTool.InkType) -> Double {
        guard drawnWidth.isFinite, drawnWidth > 0, let table = acrossMeasurements(forInkType: inkType) else { return drawnWidth }
        return pointSize(forRenderedWidth: drawnWidth, in: table)
    }

    /// The point size PencilKit draws `renderedWidth` points wide in this ink: interpolated between the two nearest
    /// measurements, beyond the widest along the last two, and below the narrowest towards nothing. A width that is
    /// not a positive number gives the size of the narrowest measurement.
    static func pointSize(forRenderedWidth renderedWidth: Double, ink: ImportedStroke.Ink) -> Double {
        pointSize(forRenderedWidth: renderedWidth, in: measurements(for: ink))
    }

    private static func pointSize(forRenderedWidth renderedWidth: Double, in table: [Measurement]) -> Double {
        guard let narrowest = table.first, table.count > 1 else { return 0 }
        guard renderedWidth.isFinite, renderedWidth > 0 else { return narrowest.pointSize }
        if renderedWidth <= narrowest.renderedWidth, narrowest.renderedWidth > 0 {
            return narrowest.pointSize * renderedWidth / narrowest.renderedWidth
        }
        let upperIndex = max(table.firstIndex { measurement in measurement.renderedWidth >= renderedWidth } ?? table.count - 1, 1)
        let lower = table[upperIndex - 1], upper = table[upperIndex]
        let widthRange = upper.renderedWidth - lower.renderedWidth
        guard widthRange > 0 else { return upper.pointSize }
        return lower.pointSize + (renderedWidth - lower.renderedWidth) * (upper.pointSize - lower.pointSize) / widthRange
    }
}
