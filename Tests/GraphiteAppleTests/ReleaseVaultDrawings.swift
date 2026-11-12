/**
 * File: ReleaseVaultDrawings.swift
 * --------------------------------
 * Layer: Tests
 * Description: The release vault's drawing made with every Pencil tool (each ink, eraser cuts, strokes moved by the
 *              lasso, the shapes of the shape tool, a placed picture), saved as Graphite saves a drawing in PNG, SVG
 *              and PDF, and a drawing without paper.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 12/11/2026
 */

#if os(macOS)
import Foundation
import AppKit
import PencilKit
import GraphiteCore
@testable import GraphiteApple

/// The strokes a person makes trying every tool of the fixed bar on one page (Docs/Release-test-vault-todo.md, section 1):
/// a row of each ink, a line and a wave cut through by the pixel eraser, a small word moved by the lasso, and the shapes
/// the shape tool makes. They are made from points here, as no Pencil can draw in a test, and kept the same on every run.
enum ReleaseVaultDrawings {
    /// The drawing's canvas in points; the PNG is drawn at twice that, as the iPad saves drawings.
    static let canvasSize = CGSize(width: 900, height: 560)
    /// A fixed date keeps the files the same on every run.
    static let strokeDate = Date(timeIntervalSince1970: 1_793_000_000)

    /// Every ink of the fixed bar (`PencilInk`), in its own colour, with the width the bar offers in the middle.
    static var inkRow: [(ink: PKInk.InkType, color: NSColor, width: CGFloat)] {
        [(.pen, .black, 4), (.monoline, NSColor(red: 0.1, green: 0.3, blue: 0.85, alpha: 1), 4),
         (.fountainPen, NSColor(red: 0.1, green: 0.45, blue: 0.25, alpha: 1), 6), (.reed, NSColor(red: 0.45, green: 0.25, blue: 0.1, alpha: 1), 12),
         (.pencil, .darkGray, 5), (.crayon, .systemOrange, 14), (.watercolor, .systemTeal, 18), (.marker, .systemYellow, 26)]
    }

    static func drawing() -> PKDrawing {
        PKDrawing(strokes: inkStrokes() + erasedStrokes() + lassoMovedStrokes() + shapeStrokes())
    }

    /// Row one: a wave in each ink, the highlighter last, drawn over the pen's wave as it is drawn over text.
    static func inkStrokes() -> [PKStroke] {
        inkRow.enumerated().map { inkIndex, entry in
            let left = 30 + CGFloat(inkIndex) * 108
            let points = (0...24).map { step in
                CGPoint(x: left + CGFloat(step) * 3.6, y: 70 + 18 * sin(CGFloat(step) / 24 * 2 * .pi))
            }
            return stroke(through: points, ink: PKInk(entry.ink, color: entry.color), width: entry.width)
        }
    }

    /// Row two: a thick line and a watercolor band, each cut through twice by the pixel eraser, as `PixelEraserPass` cuts
    /// them: the line becomes three pieces, the band two.
    static func erasedStrokes() -> [PKStroke] {
        let line = stroke(through: segmentPoints(from: CGPoint(x: 30, y: 170), to: CGPoint(x: 400, y: 170)), ink: PKInk(.pen, color: .black), width: 8)
        let band = stroke(through: segmentPoints(from: CGPoint(x: 30, y: 220), to: CGPoint(x: 400, y: 220)),
                          ink: PKInk(.watercolor, color: .systemPink), width: 24)
        var erased = PixelEraserPass.erasing(PKDrawing(strokes: [line, band]), along: [CGPoint(x: 150, y: 140), CGPoint(x: 150, y: 250)], width: 18)
        erased = PixelEraserPass.erasing(erased, along: [CGPoint(x: 280, y: 150), CGPoint(x: 280, y: 190)], width: 18)
        return erased.strokes
    }

    /// Row two, right: a small handwritten "ok" drawn at the left and moved by the lasso to the right and turned a little,
    /// as the lasso leaves strokes: their points kept, a transform of their own.
    static func lassoMovedStrokes() -> [PKStroke] {
        let letterO = (0...20).map { step in
            CGPoint(x: 500 + 16 * cos(CGFloat(step) / 20 * 2 * .pi), y: 200 + 20 * sin(CGFloat(step) / 20 * 2 * .pi))
        }
        let letterKStem = segmentPoints(from: CGPoint(x: 530, y: 170), to: CGPoint(x: 530, y: 222))
        let letterKArms = [CGPoint(x: 556, y: 182), CGPoint(x: 532, y: 202), CGPoint(x: 558, y: 222)]
        let move = CGAffineTransform(translationX: 220, y: 40).rotated(by: -0.12)
        return [letterO, letterKStem, letterKArms].map { points in
            let drawn = stroke(through: points, ink: PKInk(.pen, color: NSColor(red: 0.6, green: 0.1, blue: 0.5, alpha: 1)), width: 4)
            return PKStroke(ink: drawn.ink, path: drawn.path, transform: move, mask: nil)
        }
    }

    /// Row three: each shape the shape tool makes (`RecognizedShape`), drawn along its outline as `PencilShapes` draws it.
    static func shapeStrokes() -> [PKStroke] {
        let shapes: [RecognizedShape] = [
            .line(start: CGPoint(x: 30, y: 330), end: CGPoint(x: 130, y: 330)),
            .arrow(start: CGPoint(x: 30, y: 400), end: CGPoint(x: 130, y: 400)),
            .arc(center: CGPoint(x: 210, y: 380), radius: 50, startAngle: .pi, sweepAngle: .pi * 0.9),
            .curvedArrow(center: CGPoint(x: 330, y: 400), radius: 50, startAngle: .pi * 1.1, sweepAngle: .pi * 0.8),
            .ellipse(center: CGPoint(x: 450, y: 380), horizontalRadius: 45, verticalRadius: 45, rotation: 0),
            .ellipse(center: CGPoint(x: 570, y: 380), horizontalRadius: 55, verticalRadius: 30, rotation: 0.4),
            .polygon(corners: [CGPoint(x: 650, y: 430), CGPoint(x: 700, y: 330), CGPoint(x: 750, y: 430)]),
            .polygon(corners: [CGPoint(x: 780, y: 340), CGPoint(x: 870, y: 340), CGPoint(x: 870, y: 420), CGPoint(x: 780, y: 420)]),
        ]
        let ink = PKInk(.monoline, color: NSColor(red: 0.15, green: 0.35, blue: 0.75, alpha: 1))
        return shapes.map { shape in stroke(through: shape.outlinePoints(spacing: 4), ink: ink, width: 4, evenPressure: true) }
    }

    /// The picture placed on the drawing, low on the canvas: a picture of the vault's own, as a person places one.
    static func placedPicture(_ pictureData: Data) -> DrawingBackgroundImage {
        DrawingBackgroundImage(imageData: pictureData, frame: CGRect(x: 40, y: 450, width: 96, height: 96), rotationRadians: 0.15)
    }

    // MARK: Files

    /// The drawing on white as a PNG carrying its strokes and its picture (`GraphitePNG`).
    static func pngData(pictureData: Data, background: DrawingBackground = .white) throws -> Data {
        let drawing = drawing()
        let picture = placedPicture(pictureData)
        let image = try renderedImage(of: drawing, picture: background == .transparent ? nil : picture, onWhite: background != .transparent)
        let payload = DrawingPayload(width: canvasSize.width, height: canvasSize.height, background: background, strokes: drawing.dataRepresentation(),
                                     pictures: background == .transparent ? [] : [picture])
        return try GraphitePNG.encode(imageData: ImageEncoding.pngData(from: image), drawing: payload)
    }

    /// The same drawing as Graphite's SVG drawing file: its outlines, its picture, and its strokes in the metadata.
    static func svgData(pictureData: Data) throws -> Data {
        let (vector, payload) = vectorDrawing(pictureData: pictureData)
        return try SVGDrawingFile.encode(vector, payload: payload)
    }

    /// The same drawing as Graphite's PDF drawing file.
    static func pdfData(pictureData: Data) throws -> Data {
        let (vector, payload) = vectorDrawing(pictureData: pictureData)
        return try PDFDrawingFile.encode(vector, payload: payload)
    }

    private static func vectorDrawing(pictureData: Data) -> (VectorDrawing, DrawingPayload) {
        let drawing = drawing()
        let picture = placedPicture(pictureData)
        let ink = PencilVectorConverter.vectorDrawing(from: drawing, size: canvasSize, background: .white)
        let vector = VectorDrawing(size: canvasSize, background: .white, pictures: [picture], shapes: ink.shapes)
        let payload = DrawingPayload(width: canvasSize.width, height: canvasSize.height, background: .white, strokes: drawing.dataRepresentation(),
                                     pictures: [picture])
        return (vector, payload)
    }

    /// The canvas at twice its size: white (or clear), the picture, then the ink, as the iPad composes a saved drawing.
    private static func renderedImage(of drawing: PKDrawing, picture: DrawingBackgroundImage?, onWhite: Bool) throws -> CGImage {
        let canvas = CGRect(origin: .zero, size: canvasSize)
        // PencilKit draws black ink white in the dark appearance, as on a dark canvas; a drawing is saved as it looks on paper.
        var renderedInk: NSImage?
        NSAppearance(named: .aqua)?.performAsCurrentDrawingAppearance { renderedInk = drawing.image(from: canvas, scale: 2) }
        guard let inkImage = renderedInk?.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let context = CGContext(data: nil, width: Int(canvasSize.width * 2), height: Int(canvasSize.height * 2), bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw GraphiteError.invalidFile("The drawing could not be drawn.")
        }
        let pixelBounds = CGRect(x: 0, y: 0, width: canvasSize.width * 2, height: canvasSize.height * 2)
        if onWhite {
            context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
            context.fill(pixelBounds)
        }
        if let picture, let pictureImage = NSImage(data: picture.imageData)?.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            // The canvas counts down from the top; the bitmap counts up from the bottom.
            let frame = picture.frame
            context.saveGState()
            context.translateBy(x: frame.midX * 2, y: (canvasSize.height - frame.midY) * 2)
            context.rotate(by: -picture.rotationRadians)
            context.draw(pictureImage, in: CGRect(x: -frame.width, y: -frame.height, width: frame.width * 2, height: frame.height * 2))
            context.restoreGState()
        }
        context.draw(inkImage, in: pixelBounds)
        guard let image = context.makeImage() else { throw GraphiteError.invalidFile("The drawing could not be drawn.") }
        return image
    }

    // MARK: Strokes

    static func segmentPoints(from start: CGPoint, to end: CGPoint, steps: Int = 30) -> [CGPoint] {
        (0...steps).map { step in
            let fraction = CGFloat(step) / CGFloat(steps)
            return CGPoint(x: start.x + (end.x - start.x) * fraction, y: start.y + (end.y - start.y) * fraction)
        }
    }

    /// A stroke through the points, its pressure rising and falling along it as a hand's does, or even for a shape.
    static func stroke(through points: [CGPoint], ink: PKInk, width: CGFloat, evenPressure: Bool = false) -> PKStroke {
        let controlPoints = points.enumerated().map { pointIndex, location in
            let progress = CGFloat(pointIndex) / CGFloat(max(points.count - 1, 1))
            let force = evenPressure ? 1 : 0.7 + 0.5 * sin(progress * .pi)
            return PKStrokePoint(location: location, timeOffset: TimeInterval(pointIndex) / 60, size: CGSize(width: width * force, height: width * force),
                                 opacity: 1, force: force, azimuth: 0, altitude: .pi / 2)
        }
        return PKStroke(ink: ink, path: PKStrokePath(controlPoints: controlPoints, creationDate: strokeDate))
    }
}
#endif
