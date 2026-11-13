/**
 * File: PDFShape.swift
 * --------------------
 * Layer: Apple
 * Description: Rectangles, ovals, lines and arrows on a PDF page as the standard `/Square`, `/Circle` and `/Line`
 *              annotations, read back from any application's file, and moved or reshaped by a handle.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 13/11/2026
 */
import Foundation
import CoreGraphics
import PDFKit
import GraphiteCore
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// The shapes Graphite draws, each a standard annotation that Preview, Acrobat and the
/// iPad's PDFKit show with the appearance PDFKit writes for it.
public enum PDFShapeKind: String, Sendable, Hashable, CaseIterable, Identifiable {
    case rectangle, oval, line, arrow
    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .rectangle: "Rectangle"
        case .oval: "Oval"
        case .line: "Line"
        case .arrow: "Arrow"
        }
    }

    public var annotationSubtype: PDFAnnotationSubtype {
        switch self {
        case .rectangle: .square
        case .oval: .circle
        case .line, .arrow: .line
        }
    }

    /// The subtype without its slash, as PDFKit reads it back.
    public var annotationTypeName: String {
        switch self {
        case .rectangle: "Square"
        case .oval: "Circle"
        case .line, .arrow: "Line"
        }
    }

    /// Whether the shape is a segment between two points rather than a box between two corners.
    public var isSegment: Bool { self == .line || self == .arrow }
}

/// Why a change of a shape was not made.
public enum PDFShapeError: Error, LocalizedError, Equatable {
    /// The shape the change names is no longer on its page, as after an undo.
    case shapeMissing

    public var errorDescription: String? {
        switch self {
        case .shapeMissing: "This shape no longer exists."
        }
    }
}

/// A handle of a shape: its two points, and for a box the two other corners, named by the
/// point each takes its horizontal and vertical place from.
public enum PDFShapeHandle: Sendable, Hashable, CaseIterable {
    case start, end
    /// The corner at the start's horizontal place and the end's vertical place.
    case startHorizontalEndVertical
    /// The corner at the end's horizontal place and the start's vertical place.
    case endHorizontalStartVertical
}

/// One shape on a page, in page space. A box (rectangle or oval) fills the rectangle
/// between `start` and `end`; a line or arrow runs from `start` to `end`, the arrow's head at `end`.
public struct PDFShape: Sendable, Equatable {
    /// Stored as the standard `/NM` annotation name so the shape can be found again.
    public var name: String
    public var kind: PDFShapeKind
    public var start: CGPoint
    public var end: CGPoint
    public var borderColor: PDFTextColor
    /// The inside of a box; nil leaves it clear. A line has none.
    public var fillColor: PDFTextColor?
    public var lineWidth: Double
    /// The author of a shape read from a file, written again instead of the current user's
    /// name when the shape is moved or put back; nil for a shape Graphite draws.
    public var author: String?

    /// How far beyond its line a line's rectangle reaches, in points, so readers do not cut its round ends.
    private static let segmentMargin: CGFloat = 1
    /// How long an arrow's head is, at least and per point of line width.
    private static let shortestArrowHead: CGFloat = 6
    private static let arrowHeadPerLineWidth: CGFloat = 4

    public init(name: String = UUID().uuidString, kind: PDFShapeKind, start: CGPoint, end: CGPoint, borderColor: PDFTextColor,
                fillColor: PDFTextColor? = nil, lineWidth: Double, author: String? = nil) {
        self.name = name
        self.kind = kind
        self.start = start
        self.end = end
        self.borderColor = borderColor
        self.fillColor = kind.isSegment ? nil : fillColor
        self.lineWidth = lineWidth.isFinite ? max(0, lineWidth) : 1
        self.author = author
    }

    /// Reads a `/Square`, `/Circle` or `/Line` back, Graphite's or another application's;
    /// nil for any other annotation. A line with an ending at its start only is read with
    /// its points swapped, so its arrow is at `end`.
    public init?(annotation: PDFAnnotation) {
        let bounds = annotation.bounds
        let lineWidth = Double(annotation.border?.lineWidth ?? 1)
        let borderColor = Self.textColor(of: annotation.color) ?? .black
        let name = annotation.persistentName ?? UUID().uuidString
        let author = annotation.userName
        let boxKinds: [PDFShapeKind] = [.rectangle, .oval]
        if let kind = boxKinds.first(where: { kind in kind.annotationTypeName == annotation.type }) {
            self.init(name: name, kind: kind, start: CGPoint(x: bounds.minX, y: bounds.minY), end: CGPoint(x: bounds.maxX, y: bounds.maxY),
                      borderColor: borderColor, fillColor: annotation.interiorColor.flatMap(Self.textColor(of:)), lineWidth: lineWidth, author: author)
        } else if annotation.type == PDFShapeKind.line.annotationTypeName {
            var start = CGPoint(x: bounds.minX + annotation.startPoint.x, y: bounds.minY + annotation.startPoint.y)
            var end = CGPoint(x: bounds.minX + annotation.endPoint.x, y: bounds.minY + annotation.endPoint.y)
            let hasStartEnding = annotation.startLineStyle != .none, hasEndEnding = annotation.endLineStyle != .none
            if hasStartEnding && !hasEndEnding { swap(&start, &end) }
            self.init(name: name, kind: hasStartEnding || hasEndEnding ? .arrow : .line, start: start, end: end, borderColor: borderColor,
                      lineWidth: lineWidth, author: author)
        } else {
            return nil
        }
    }

    /// The rectangle a box fills.
    public var boxRectangle: CGRect {
        CGRect(x: min(start.x, end.x), y: min(start.y, end.y), width: abs(end.x - start.x), height: abs(end.y - start.y))
    }

    /// The annotation's rectangle: a box's own, a line's around its points, its width and an arrow's head.
    public var bounds: CGRect {
        guard kind.isSegment else { return boxRectangle }
        let reach = CGFloat(lineWidth) / 2 + Self.segmentMargin + (kind == .arrow ? arrowHeadLength : 0)
        return boxRectangle.insetBy(dx: -reach, dy: -reach)
    }

    private var arrowHeadLength: CGFloat {
        max(Self.shortestArrowHead, CGFloat(lineWidth) * Self.arrowHeadPerLineWidth)
    }

    /// Whether a shape this size is worth keeping: a click without a drag draws none.
    public var hasVisibleSize: Bool {
        let rectangle = boxRectangle
        return kind.isSegment ? hypot(rectangle.width, rectangle.height) >= 2 : rectangle.width >= 2 && rectangle.height >= 2
    }

    // MARK: Pointing

    /// Whether a point of the page is on the shape: inside a box, filled or not, or near a
    /// line, `tolerance` points beyond its edge.
    public func contains(_ pagePoint: CGPoint, tolerance: CGFloat) -> Bool {
        let halfWidth = CGFloat(lineWidth) / 2
        switch kind {
        case .rectangle:
            return boxRectangle.insetBy(dx: -(halfWidth + tolerance), dy: -(halfWidth + tolerance)).contains(pagePoint)
        case .oval:
            let rectangle = boxRectangle
            let horizontalRadius = rectangle.width / 2 + halfWidth + tolerance, verticalRadius = rectangle.height / 2 + halfWidth + tolerance
            guard horizontalRadius > 0, verticalRadius > 0 else { return false }
            let horizontal = (pagePoint.x - rectangle.midX) / horizontalRadius, vertical = (pagePoint.y - rectangle.midY) / verticalRadius
            return horizontal * horizontal + vertical * vertical <= 1
        case .line, .arrow:
            return Self.distance(from: pagePoint, toSegmentFrom: start, to: end) <= halfWidth + tolerance
        }
    }

    /// The handles of the shape and where they are: a line's two points, a box's four corners.
    public var handles: [(handle: PDFShapeHandle, pagePoint: CGPoint)] {
        var placed: [(handle: PDFShapeHandle, pagePoint: CGPoint)] = [(.start, start), (.end, end)]
        if !kind.isSegment {
            placed.append((.startHorizontalEndVertical, CGPoint(x: start.x, y: end.y)))
            placed.append((.endHorizontalStartVertical, CGPoint(x: end.x, y: start.y)))
        }
        return placed
    }

    /// The shape moved by `delta`, in page points.
    public func moved(by delta: CGVector) -> PDFShape {
        var moved = self
        moved.start = CGPoint(x: start.x + delta.dx, y: start.y + delta.dy)
        moved.end = CGPoint(x: end.x + delta.dx, y: end.y + delta.dy)
        return moved
    }

    /// The shape with one handle dragged to a point of the page; the opposite handle stays.
    public func moving(_ handle: PDFShapeHandle, to pagePoint: CGPoint) -> PDFShape {
        var reshaped = self
        switch handle {
        case .start: reshaped.start = pagePoint
        case .end: reshaped.end = pagePoint
        case .startHorizontalEndVertical:
            reshaped.start.x = pagePoint.x
            reshaped.end.y = pagePoint.y
        case .endHorizontalStartVertical:
            reshaped.end.x = pagePoint.x
            reshaped.start.y = pagePoint.y
        }
        return reshaped
    }

    private static func distance(from point: CGPoint, toSegmentFrom start: CGPoint, to end: CGPoint) -> CGFloat {
        let segment = CGVector(dx: end.x - start.x, dy: end.y - start.y)
        let lengthSquared = segment.dx * segment.dx + segment.dy * segment.dy
        guard lengthSquared > 0 else { return hypot(point.x - start.x, point.y - start.y) }
        let fraction = min(1, max(0, ((point.x - start.x) * segment.dx + (point.y - start.y) * segment.dy) / lengthSquared))
        return hypot(point.x - (start.x + segment.dx * fraction), point.y - (start.y + segment.dy * fraction))
    }

    // MARK: The annotation

    /// The standard annotation for this shape. PDFKit writes its appearance (`/AP`) with
    /// the file, so readers that draw only appearances show it too. A shape read from a
    /// file keeps its author; a new one gets `authorName`.
    func makeAnnotation(authorName: String?) -> PDFAnnotation {
        let annotationBounds = bounds
        let annotation = PDFAnnotation(bounds: annotationBounds, forType: kind.annotationSubtype, withProperties: nil)
        let border = PDFBorder()
        border.lineWidth = CGFloat(lineWidth)
        annotation.border = border
        annotation.color = Self.platformColor(borderColor)
        if let fillColor { annotation.interiorColor = Self.platformColor(fillColor) }
        if kind.isSegment {
            // Relative to the rectangle's corner, as PDFKit keeps them; it writes `/L` in page space.
            annotation.startPoint = CGPoint(x: start.x - annotationBounds.minX, y: start.y - annotationBounds.minY)
            annotation.endPoint = CGPoint(x: end.x - annotationBounds.minX, y: end.y - annotationBounds.minY)
            annotation.startLineStyle = .none
            annotation.endLineStyle = kind == .arrow ? .openArrow : .none
        }
        PDFAnnotationAuthor.write(author ?? authorName, on: annotation)
        annotation.shouldPrint = true
        annotation.setPersistentName(name)
        return annotation
    }

    /// Whether an annotation is a shape Graphite reads: a `/Square`, `/Circle` or `/Line`.
    public static func isShape(_ annotation: PDFAnnotation) -> Bool {
        PDFShapeKind.allCases.contains { kind in kind.annotationTypeName == annotation.type }
    }

    #if canImport(UIKit)
    private static func platformColor(_ color: PDFTextColor) -> UIColor {
        UIColor(red: CGFloat(color.red), green: CGFloat(color.green), blue: CGFloat(color.blue), alpha: 1)
    }

    private static func textColor(of color: UIColor) -> PDFTextColor? { textColor(of: color.cgColor) }
    #else
    private static func platformColor(_ color: PDFTextColor) -> NSColor {
        NSColor(srgbRed: CGFloat(color.red), green: CGFloat(color.green), blue: CGFloat(color.blue), alpha: 1)
    }

    private static func textColor(of color: NSColor) -> PDFTextColor? { textColor(of: color.cgColor) }
    #endif

    /// A colour in sRGB; nil for a transparent one, which PDFKit gives for a missing `/C` or `/IC`.
    private static func textColor(of color: CGColor) -> PDFTextColor? {
        guard let components = color.converted(to: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                               intent: .defaultIntent, options: nil)?.components,
              components.count >= 3, components.count < 4 || components[3] > 0 else { return nil }
        return PDFTextColor(red: Double(components[0]), green: Double(components[1]), blue: Double(components[2]))
    }
}

extension PDFPageManager {
    /// A new annotation rather than new bounds, as for a picture: PDFKit would show one read
    /// from a file with the appearance it was written with. It keeps the former's author.
    static func replaceShape(_ reference: PDFAnnotationReference, with shape: PDFShape, on page: PDFPage, authorName: String?) throws {
        guard let annotation = referencedAnnotation(reference, on: page), PDFShape.isShape(annotation) else { throw PDFShapeError.shapeMissing }
        page.removeAnnotation(annotation)
        var replacement = shape
        replacement.author = shape.author ?? annotation.userName
        page.addAnnotation(replacement.makeAnnotation(authorName: authorName))
    }
}
