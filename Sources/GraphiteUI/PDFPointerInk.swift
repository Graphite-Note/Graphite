/**
 * File: PDFPointerInk.swift
 * -------------------------
 * Layer: UI
 * Description: Ink drawn with a mouse or trackpad as the iPad's Pencil ink is kept: a PencilKit stroke through the
 *              pointer's places on a page, and which strokes of a page's drawing a point of the eraser touches.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 13/11/2026
 */

import Foundation
import PencilKit
import GraphiteCore
import GraphiteApple
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// One place of the pointer while drawing: on the page, in the page's coordinates, and when, in seconds.
struct PDFPointerInkSample: Equatable, Sendable {
    let pagePoint: CGPoint
    let timeSeconds: TimeInterval
}

/// Ink drawn with the pointer, made the way the iPad's Pencil ink is: a PencilKit stroke in
/// the drawing space of the page (`PageCoordinates`, the page's points from its top-left
/// corner), so the iPad opens it with PencilKit and edits it as its own.
enum PDFPointerInk {
    /// Places closer than this to the last one kept, in points of the page, add nothing a reader can see.
    static let shortestStepPoints: CGFloat = 0.5
    /// A click with no movement still leaves a dot: its one place is drawn to a second this far away.
    static let dotLengthPoints: CGFloat = 0.01
    /// How near a stroke the eraser must pass to remove it, beyond the stroke's own half width, in points.
    static let eraserReachPoints: CGFloat = 4
    /// The step at which a stroke's path is followed when the eraser looks for it, in points.
    private static let hitTestStepPoints: CGFloat = 1

    /// The stroke through the samples, in the drawing space `coordinates` give, with the
    /// style's colour and width; nil without a sample.
    static func stroke(through samples: [PDFPointerInkSample], style: PDFMarkupInkStyle, coordinates: PageCoordinates,
                       creationDate: Date) -> PKStroke? {
        guard let firstSample = samples.first else { return nil }
        var kept = [firstSample]
        for sample in samples.dropFirst() {
            guard let last = kept.last else { continue }
            if hypot(sample.pagePoint.x - last.pagePoint.x, sample.pagePoint.y - last.pagePoint.y) >= shortestStepPoints { kept.append(sample) }
        }
        if kept.count == 1 {
            kept.append(PDFPointerInkSample(pagePoint: CGPoint(x: firstSample.pagePoint.x + dotLengthPoints, y: firstSample.pagePoint.y),
                                            timeSeconds: firstSample.timeSeconds))
        }
        let widthScale = coordinates.overlaySize.width / coordinates.cropBox.width
        // The style's width is the width drawn: PencilKit draws a pen point narrower than its size, and nothing below a
        // size of 2, so Fine ink written at its width as the size was invisible on the iPad (seen 2026-11-13).
        let side = PencilStrokeSampler.pointSize(forDrawnWidth: CGFloat(style.width.points) * widthScale, inkType: .pen)
        let pointSize = CGSize(width: side, height: side)
        let controlPoints = kept.map { sample in
            PKStrokePoint(location: coordinates.overlayPoint(fromPDF: sample.pagePoint), timeOffset: max(0, sample.timeSeconds - firstSample.timeSeconds),
                          size: pointSize, opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }
        let ink = PKInk(.pen, color: platformColor(style.color))
        return PKStroke(ink: ink, path: PKStrokePath(controlPoints: controlPoints, creationDate: creationDate))
    }

    /// The positions in `drawing` of the strokes that pass within reach of a point of the
    /// drawing space, latest first, as the eraser takes the stroke on top.
    static func indicesOfStrokes(in drawing: PKDrawing, touching drawingPoint: CGPoint, reach: CGFloat = eraserReachPoints) -> [Int] {
        var touched: [Int] = []
        for (index, stroke) in drawing.strokes.enumerated().reversed() {
            guard stroke.renderBounds.insetBy(dx: -reach, dy: -reach).contains(drawingPoint) else { continue }
            if passes(stroke, within: reach, of: drawingPoint) { touched.append(index) }
        }
        return touched
    }

    /// The strokes the eraser passes on its way from one point of the drawing space to the
    /// next: the pointer's places come far apart when it moves fast, and a stroke between
    /// them is passed all the same.
    static func indicesOfStrokes(in drawing: PKDrawing, alongSegmentFrom startPoint: CGPoint, to endPoint: CGPoint,
                                 reach: CGFloat = eraserReachPoints) -> [Int] {
        let length = hypot(endPoint.x - startPoint.x, endPoint.y - startPoint.y)
        let stepCount = max(1, Int((length / max(reach, hitTestStepPoints)).rounded(.up)))
        var touched: [Int] = []
        for stepIndex in 0...stepCount {
            let fraction = CGFloat(stepIndex) / CGFloat(stepCount)
            let point = CGPoint(x: startPoint.x + (endPoint.x - startPoint.x) * fraction, y: startPoint.y + (endPoint.y - startPoint.y) * fraction)
            for index in indicesOfStrokes(in: drawing, touching: point, reach: reach) where !touched.contains(index) { touched.append(index) }
        }
        return touched
    }

    private static func passes(_ stroke: PKStroke, within reach: CGFloat, of drawingPoint: CGPoint) -> Bool {
        for point in stroke.path.interpolatedPoints(by: .distance(hitTestStepPoints)) {
            let location = point.location.applying(stroke.transform)
            let radius = max(point.size.width, point.size.height) / 2 + reach
            if hypot(location.x - drawingPoint.x, location.y - drawingPoint.y) <= radius { return true }
        }
        return false
    }

    /// The drawing space of a page: its crop box in points, from its top-left corner, as the
    /// iPad's canvas over an upright page has it (`PDFPageCanvasView.drawingSize`).
    static func coordinates(of cropBox: CGRect) throws -> PageCoordinates {
        try PageCoordinates(cropBox: cropBox, overlaySize: cropBox.size)
    }

    #if canImport(UIKit)
    private static func platformColor(_ color: PDFTextColor) -> UIColor {
        UIColor(red: CGFloat(color.red), green: CGFloat(color.green), blue: CGFloat(color.blue), alpha: 1)
    }
    #else
    private static func platformColor(_ color: PDFTextColor) -> NSColor {
        NSColor(srgbRed: CGFloat(color.red), green: CGFloat(color.green), blue: CGFloat(color.blue), alpha: 1)
    }
    #endif
}
