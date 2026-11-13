/**
 * File: PDFSignatureInk.swift
 * ---------------------------
 * Layer: UI
 * Description: A signature as ink on a PDF page: its strokes placed in a frame of the page's drawing space, found
 *              again by the creation date they share, and moved or resized by a corner keeping their proportions.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 13/11/2026
 */

import Foundation
import PencilKit
import GraphiteApple

/// A corner of a placed signature's frame, by which it is resized.
enum PDFSignatureCorner: CaseIterable, Sendable {
    case topLeft, topRight, bottomLeft, bottomRight

    /// The corner of `frame`, in a drawing space whose vertical axis runs down.
    func point(of frame: CGRect) -> CGPoint {
        switch self {
        case .topLeft: CGPoint(x: frame.minX, y: frame.minY)
        case .topRight: CGPoint(x: frame.maxX, y: frame.minY)
        case .bottomLeft: CGPoint(x: frame.minX, y: frame.maxY)
        case .bottomRight: CGPoint(x: frame.maxX, y: frame.maxY)
        }
    }

    var opposite: PDFSignatureCorner {
        switch self {
        case .topLeft: .bottomRight
        case .topRight: .bottomLeft
        case .bottomLeft: .topRight
        case .bottomRight: .topLeft
        }
    }
}

/// A signature placed on a page is ordinary ink: strokes in the page's editable ink group,
/// written as the Draw tool's are, so the iPad edits them with PencilKit and every reader
/// shows them. All the strokes of one placement share one creation date, by which the Sign
/// tool finds them again to move, resize or delete them together.
enum PDFSignatureInk {
    /// The width a signature is placed at, in points of the page, unless the page is narrower.
    static let placedWidthPoints: CGFloat = 160
    /// The narrowest a signature can be made by its corners, in points of the page.
    static let narrowestWidthPoints: CGFloat = 16
    /// Two dates this close are one placement's: a drawing written and read back keeps its
    /// dates to well within it, and strokes drawn by hand come far further apart.
    private static let sameDateTolerance: TimeInterval = 0.001

    /// The drawing moved so its strokes start at its top-left corner; nil without a stroke.
    static func normalized(_ drawing: PKDrawing) -> PKDrawing? {
        guard !drawing.strokes.isEmpty else { return nil }
        let bounds = drawing.bounds
        let frame = CGRect(origin: .zero, size: bounds.size)
        return PKDrawing(strokes: drawing.strokes.map { stroke in transformed(stroke, from: bounds, to: frame, creationDate: stroke.path.creationDate) })
    }

    /// Where a signature of `size` goes centred on a point of a page's drawing space of
    /// `pageSize`: `placedWidthPoints` wide, or narrower to fit the page, and inside it.
    static func placedFrame(forSignatureOf size: CGSize, centeredAt center: CGPoint, pageSize: CGSize) -> CGRect {
        guard size.width > 0, size.height > 0 else { return .null }
        let scale = min(placedWidthPoints / size.width, pageSize.width / size.width, pageSize.height / size.height)
        let placedSize = CGSize(width: size.width * scale, height: size.height * scale)
        let originX = min(max(center.x - placedSize.width / 2, 0), max(0, pageSize.width - placedSize.width))
        let originY = min(max(center.y - placedSize.height / 2, 0), max(0, pageSize.height - placedSize.height))
        return CGRect(origin: CGPoint(x: originX, y: originY), size: placedSize)
    }

    /// The signature's strokes filling `frame` of a page's drawing space, all dated `creationDate`.
    static func strokes(of signature: PKDrawing, filling frame: CGRect, creationDate: Date) -> [PKStroke] {
        let bounds = signature.bounds
        return signature.strokes.map { stroke in transformed(stroke, from: bounds, to: frame, creationDate: creationDate) }
    }

    /// The positions in `drawing` of the strokes of the placement dated `creationDate`.
    static func indicesOfStrokes(createdAt creationDate: Date, in drawing: PKDrawing) -> [Int] {
        drawing.strokes.indices.filter { index in
            abs(drawing.strokes[index].path.creationDate.timeIntervalSince(creationDate)) < sameDateTolerance
        }
    }

    /// The frame around the strokes of the placement dated `creationDate`; nil when there are none.
    static func frame(ofStrokesCreatedAt creationDate: Date, in drawing: PKDrawing) -> CGRect? {
        let indices = indicesOfStrokes(createdAt: creationDate, in: drawing)
        guard !indices.isEmpty else { return nil }
        return indices.reduce(CGRect.null) { frame, index in frame.union(drawing.strokes[index].renderBounds) }
    }

    /// `drawing` with the strokes of the placement dated `creationDate` taken from `frame` to
    /// `newFrame`, where they keep their place among the page's strokes; or taken away when
    /// `newFrame` is nil.
    static func drawing(_ drawing: PKDrawing, movingStrokesCreatedAt creationDate: Date, from frame: CGRect, to newFrame: CGRect?) -> PKDrawing {
        let placed = Set(indicesOfStrokes(createdAt: creationDate, in: drawing))
        return PKDrawing(strokes: drawing.strokes.enumerated().compactMap { index, stroke in
            guard placed.contains(index) else { return stroke }
            guard let newFrame else { return nil }
            return transformed(stroke, from: frame, to: newFrame, creationDate: creationDate)
        })
    }

    /// The frame resized by dragging `corner` to `point`: the opposite corner stays, and the
    /// signature keeps its proportions, as wide as the drag asks or as tall, whichever is more.
    static func resized(_ frame: CGRect, draggingCorner corner: PDFSignatureCorner, to point: CGPoint) -> CGRect {
        guard frame.width > 0, frame.height > 0 else { return frame }
        let anchor = corner.opposite.point(of: frame)
        let scale = max(abs(point.x - anchor.x) / frame.width, abs(point.y - anchor.y) / frame.height, narrowestWidthPoints / frame.width)
        let size = CGSize(width: frame.width * scale, height: frame.height * scale)
        let towardsRight = corner == .topRight || corner == .bottomRight, towardsBottom = corner == .bottomLeft || corner == .bottomRight
        return CGRect(x: towardsRight ? anchor.x : anchor.x - size.width, y: towardsBottom ? anchor.y : anchor.y - size.height,
                      width: size.width, height: size.height)
    }

    /// The stroke carried from `frame` to `newFrame`, its points and their drawn widths scaled by the change of width,
    /// with its transform taken into its points. The drawn width is scaled, not the point size: PencilKit draws a pen
    /// point narrower than its size, and a signature placed small with its sizes scaled drew nothing on the iPad.
    private static func transformed(_ stroke: PKStroke, from frame: CGRect, to newFrame: CGRect, creationDate: Date) -> PKStroke {
        let scale = frame.width > 0 ? newFrame.width / frame.width : 1
        let points = stroke.path.map { point in
            let location = point.location.applying(stroke.transform)
            let carried = CGPoint(x: newFrame.minX + (location.x - frame.minX) * scale, y: newFrame.minY + (location.y - frame.minY) * scale)
            return PKStrokePoint(location: carried, timeOffset: point.timeOffset,
                                 size: CGSize(width: PencilStrokeSampler.pointSize(point.size.width, forDrawnWidthScaledBy: scale, inkType: stroke.ink.inkType),
                                              height: PencilStrokeSampler.pointSize(point.size.height, forDrawnWidthScaledBy: scale, inkType: stroke.ink.inkType)),
                                 opacity: point.opacity, force: point.force, azimuth: point.azimuth, altitude: point.altitude)
        }
        return PKStroke(ink: stroke.ink, path: PKStrokePath(controlPoints: points, creationDate: creationDate), transform: .identity, mask: stroke.mask)
    }
}
