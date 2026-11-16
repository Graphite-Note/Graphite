/**
 * File: PDFMarkupShapeStyle.swift
 * -------------------------------
 * Layer: UI
 * Description: The shape the Mac's Shapes tool draws next, with its border colour, fill and line width, kept on the
 *              device by one stored name.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 13/11/2026
 */

import Foundation
import GraphiteCore
import GraphiteApple

/// The kind, border colour, fill and line width of the next shape the Shapes tool draws,
/// chosen in the markup row and kept on the device as `rectangle medium #000000 none`.
struct PDFMarkupShapeStyle: Hashable, Sendable, RawRepresentable {
    var kind: PDFShapeKind
    var borderColor: PDFTextColor
    /// The inside of a rectangle or oval; nil leaves it clear.
    var fillColor: PDFTextColor?
    var width: PDFMarkupInkWidth

    static let `default` = PDFMarkupShapeStyle(kind: .rectangle, borderColor: .black, fillColor: nil, width: .medium)
    private static let noFillName = "none"

    init(kind: PDFShapeKind, borderColor: PDFTextColor, fillColor: PDFTextColor?, width: PDFMarkupInkWidth) {
        self.kind = kind
        self.borderColor = borderColor
        self.fillColor = fillColor
        self.width = width
    }

    /// The look of a shape on the page, its line width the nearest of the row's.
    init(shape: PDFShape) {
        let nearestWidth = PDFMarkupInkWidth.allCases.min { first, second in
            abs(first.points - shape.lineWidth) < abs(second.points - shape.lineWidth)
        } ?? .medium
        self.init(kind: shape.kind, borderColor: shape.borderColor, fillColor: shape.fillColor, width: nearestWidth)
    }

    var rawValue: String { "\(kind.rawValue) \(width.rawValue) \(borderColor.hex) \(fillColor?.hex ?? Self.noFillName)" }

    /// The style kept under a name, or nil for a name no style has, such as one from a newer version.
    init?(rawValue: String) {
        let parts = rawValue.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard parts.count == 4, let kind = PDFShapeKind(rawValue: parts[0]), let width = PDFMarkupInkWidth(rawValue: parts[1]),
              let borderColor = PDFTextColor(hex: parts[2]) else { return nil }
        let fillColor: PDFTextColor?
        if parts[3] == Self.noFillName {
            fillColor = nil
        } else {
            guard let color = PDFTextColor(hex: parts[3]) else { return nil }
            fillColor = color
        }
        self.init(kind: kind, borderColor: borderColor, fillColor: fillColor, width: width)
    }

    /// A shape of this style between two points of a page.
    func shape(from start: CGPoint, to end: CGPoint) -> PDFShape {
        PDFShape(kind: kind, start: start, end: end, borderColor: borderColor, fillColor: fillColor, lineWidth: width.points)
    }

    /// `shape` with this style's colours and width; its kind and place stay.
    func restyling(_ shape: PDFShape) -> PDFShape {
        PDFShape(name: shape.name, kind: shape.kind, start: shape.start, end: shape.end, borderColor: borderColor, fillColor: fillColor,
                 lineWidth: width.points, author: shape.author)
    }
}
