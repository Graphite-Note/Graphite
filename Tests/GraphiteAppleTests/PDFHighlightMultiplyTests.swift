/**
 * File: PDFHighlightMultiplyTests.swift
 * -------------------------------------
 * Layer: Tests
 * Description: A highlight in a saved PDF stays see-through over what it crosses, in any reader,
 *              and a highlight saved as a solid band is written again at the page's next edit.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 01/11/2026
 */
import XCTest
import PDFKit
import PencilKit
import CoreGraphics
import GraphiteCore
@testable import GraphiteApple

final class PDFHighlightMultiplyTests: XCTestCase {
    private static let pageSize = CGSize(width: 300, height: 200)

    /// A page whose "text" is a black bar across its middle.
    private func documentWithBlackBar() throws -> PDFDocument {
        let pageData = NSMutableData()
        var mediaBox = CGRect(origin: .zero, size: Self.pageSize)
        let context = try XCTUnwrap(CGContext(consumer: XCTUnwrap(CGDataConsumer(data: pageData)), mediaBox: &mediaBox, nil))
        context.beginPDFPage(nil)
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fill(CGRect(x: 40, y: 96, width: 220, height: 8))
        context.endPDFPage()
        context.closePDF()
        return try XCTUnwrap(PDFDocument(data: pageData as Data))
    }

    private func highlightStroke(creationSeconds: TimeInterval = 100) -> PKStroke {
        let points = (0...20).map { step in
            PKStrokePoint(location: CGPoint(x: 60 + CGFloat(step) * 9, y: 100), timeOffset: TimeInterval(step) / 60, size: CGSize(width: 16, height: 16),
                          opacity: 1.5, force: 1, azimuth: .pi / 2, altitude: .pi / 2)
        }
        return PKStroke(ink: PKInk(.marker, color: PencilColorForTests.yellow), path: PKStrokePath(controlPoints: points, creationDate: Date(timeIntervalSince1970: creationSeconds)))
    }

    private var coordinates: PageCoordinates {
        get throws { try PageCoordinates(cropBox: CGRect(origin: .zero, size: Self.pageSize), overlaySize: Self.pageSize) }
    }

    /// The page as a reader draws it, annotations included, in RGBA rows from the top.
    private func rendered(_ page: PDFPage) throws -> (bytes: [UInt8], width: Int) {
        let width = Int(Self.pageSize.width), height = Int(Self.pageSize.height)
        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        let context = try XCTUnwrap(CGContext(data: &bytes, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                              space: XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB)), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(origin: .zero, size: Self.pageSize))
        page.draw(with: .mediaBox, to: context)
        return (bytes, width)
    }

    private func pixel(_ rendering: (bytes: [UInt8], width: Int), x: Int, y: Int) -> (red: UInt8, green: UInt8, blue: UInt8) {
        let offset = (y * rendering.width + x) * 4
        return (rendering.bytes[offset], rendering.bytes[offset + 1], rendering.bytes[offset + 2])
    }

    func testASavedHighlightLeavesWhatItCrossesReadableInAnotherReader() throws {
        let document = try documentWithBlackBar()
        var tracker = PDFPageInkTracker(group: PDFInkGroups.defaultGroup)
        let update = tracker.update(for: PKDrawing(strokes: [highlightStroke()]), pageIndex: 0, coordinates: try coordinates)
        try PDFPageManager.apply(.updateInk(update), to: document, drawsInkOutlines: true)
        let reread = try XCTUnwrap(PDFDocument(data: XCTUnwrap(document.dataRepresentation())))
        let rendering = try rendered(try XCTUnwrap(reread.page(at: 0)))
        let underBand = pixel(rendering, x: 150, y: 100)
        XCTAssertLessThan(underBand.red, 40, "The bar under the highlight stays dark, not covered in yellow.")
        XCTAssertLessThan(underBand.green, 40)
        let onPaper = pixel(rendering, x: 150, y: 93)
        XCTAssertGreaterThan(onPaper.red, 200, "On white paper the highlight is its color.")
        XCTAssertLessThan(onPaper.blue, 150, "It is there: yellow has little blue.")
    }

    func testAHighlightsAppearanceAsksForMultiplyAndAPensDoesNot() throws {
        let document = try documentWithBlackBar()
        var tracker = PDFPageInkTracker(group: PDFInkGroups.defaultGroup)
        let penPoints = (0...5).map { step in
            PKStrokePoint(location: CGPoint(x: 60 + CGFloat(step) * 9, y: 40), timeOffset: TimeInterval(step) / 60, size: CGSize(width: 4, height: 4), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }
        let pen = PKStroke(ink: PKInk(.pen, color: .black), path: PKStrokePath(controlPoints: penPoints, creationDate: Date(timeIntervalSince1970: 50)))
        let update = tracker.update(for: PKDrawing(strokes: [pen, highlightStroke()]), pageIndex: 0, coordinates: try coordinates)
        XCTAssertEqual(update.addedStrokes.map(\.multipliesOverPage), [false, true])
        try PDFPageManager.apply(.updateInk(update), to: document, drawsInkOutlines: true)
        let annotations = try XCTUnwrap(document.page(at: 0)).annotations
        XCTAssertEqual(annotations.filter { annotation in annotation.value(forAnnotationKey: PDFPageManager.inkMultipliesKey) != nil }.count, 1)
    }

    /// A file written before: its highlight's annotation has no multiply. Reading changes
    /// nothing; the next edit of that page writes the highlight again, with the same look.
    func testAnOlderSolidHighlightIsWrittenAgainAtThePagesNextEditAndNotBefore() throws {
        let drawing = PKDrawing(strokes: [highlightStroke()])
        let record = PDFEditableInkRecord(drawingData: drawing.dataRepresentation(), strokeNames: ["old-highlight"])
        let group = PDFEditableInkGroup(group: PDFInkGroups.defaultGroup, record: record)
        let restored = try XCTUnwrap(PDFPageInkTracker.restoring(group))
        var tracker = restored.tracker
        var penPoints: [PKStrokePoint] = []
        for step in 0...5 {
            penPoints.append(PKStrokePoint(location: CGPoint(x: 60 + CGFloat(step) * 9, y: 40), timeOffset: TimeInterval(step) / 60, size: CGSize(width: 4, height: 4), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2))
        }
        let pen = PKStroke(ink: PKInk(.pen, color: .black), path: PKStrokePath(controlPoints: penPoints, creationDate: Date(timeIntervalSince1970: 200)))
        XCTAssertNil(tracker.updateAppending(pen, at: 1, pageIndex: 0, coordinates: try coordinates), "The whole page's update takes the old highlight along.")
        let update = tracker.update(for: PKDrawing(strokes: restored.drawing.strokes + [pen]), pageIndex: 0, coordinates: try coordinates)
        XCTAssertEqual(update.removal, .strokes(["old-highlight"]))
        XCTAssertEqual(update.addedStrokes.map(\.multipliesOverPage), [true, false])
        var multipliedTracker = try XCTUnwrap(PDFPageInkTracker.restoring(PDFEditableInkGroup(group: PDFInkGroups.defaultGroup, record: record, multipliedStrokeNames: ["old-highlight"]))).tracker
        XCTAssertNotNil(multipliedTracker.updateAppending(pen, at: 1, pageIndex: 0, coordinates: try coordinates), "A highlight already multiplied stays as it is.")
    }

    /// The dot of an "i": one touch, one point.
    func testADotOfOnePointIsSavedAndItsOutlineIsThere() throws {
        let point = PKStrokePoint(location: CGPoint(x: 100, y: 100), timeOffset: 0, size: CGSize(width: 5, height: 5), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        let dot = PKStroke(ink: PKInk(.pen, color: .black), path: PKStrokePath(controlPoints: [point], creationDate: Date(timeIntervalSince1970: 300)))
        let portable = try XCTUnwrap(PDFPageInkTracker.portableStroke(for: dot, name: "dot", coordinates: try coordinates))
        XCTAssertFalse(portable.segments.isEmpty)
        XCTAssertFalse(try XCTUnwrap(portable.outline).isEmpty, "A round mark, not nothing.")
        let shapes = PencilVectorConverter.vectorDrawing(from: PKDrawing(strokes: [dot]), size: Self.pageSize, background: .transparent).shapes
        XCTAssertEqual(shapes.count, 1, "SVG and PDF drawings keep it too.")
    }
}

/// The bar's highlighter color, as a color of the platform.
private enum PencilColorForTests {
    #if canImport(UIKit)
    static let yellow = UIColor(red: 0.965, green: 0.843, blue: 0.263, alpha: 1)
    #else
    static let yellow = NSColor(srgbRed: 0.965, green: 0.843, blue: 0.263, alpha: 1)
    #endif
}
