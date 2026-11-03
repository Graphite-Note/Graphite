/**
 * File: PDFInkWeightTests.swift
 * -----------------------------
 * Layer: Tests
 * Description: A page's ink weighs the same while PDFKit draws its annotations, in the live document
 *              and in the saved file, as once PencilKit's canvas shows it.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 02/11/2026
 */
#if os(iOS)
import XCTest
import PencilKit
import PDFKit
import GraphiteCore
import GraphiteApple
@testable import GraphiteUI

/// A page's ink weighs the same while PDFKit draws its annotations, in the live document and in
/// the saved file, as once PencilKit's canvas shows it (HUNT-009).
@MainActor
final class PDFInkWeightTests: XCTestCase {
    private static let pixelsPerPoint: CGFloat = 8
    private static let pageSize = CGSize(width: 300, height: 240)

    private func stroke(_ inkType: PKInkingTool.InkType, pointSize: CGFloat, azimuth: CGFloat) -> PKStroke {
        let points = (0...40).map { pointIndex in
            PKStrokePoint(location: CGPoint(x: 40 + CGFloat(pointIndex) * 5, y: 120), timeOffset: Double(pointIndex) / 60, size: CGSize(width: pointSize, height: pointSize),
                          opacity: inkType == .marker ? 1.5 : 1, force: 1, azimuth: azimuth, altitude: .pi / 2)
        }
        return PKStroke(ink: PKInk(inkType, color: .black), path: PKStrokePath(controlPoints: points, creationDate: Date(timeIntervalSince1970: 1_000)))
    }

    /// The width of the dark band across the middle of a picture on white, in points: the rows at
    /// least half as dark as the band's darkest, averaged over many columns.
    private func bandWidth(drawingWith draw: (CGContext) throws -> Void) throws -> Double {
        let scale = Self.pixelsPerPoint
        let width = Int(Self.pageSize.width * scale), height = Int(Self.pageSize.height * scale)
        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        let context = try XCTUnwrap(CGContext(data: &bytes, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                              space: XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB)), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.scaleBy(x: scale, y: scale)
        try draw(context)
        let columns = Array(stride(from: Int(90 * scale), through: Int(210 * scale), by: 7))
        let widths = columns.map { column -> Double in
            let darkness = (0..<height).map { row in 255 - Int(bytes[(row * width + column) * 4]) }
            let peak = darkness.max() ?? 0
            let inkedRows = darkness.indices.filter { row in peak > 0 && darkness[row] * 2 >= peak }
            guard let firstRow = inkedRows.first, let lastRow = inkedRows.last else { return 0 }
            return Double(lastRow - firstRow + 1) / Double(scale)
        }
        return widths.reduce(0, +) / Double(widths.count)
    }

    private func canvasWidth(of stroke: PKStroke) throws -> Double {
        let picture = try XCTUnwrap(PKDrawing(strokes: [stroke]).image(from: CGRect(origin: .zero, size: Self.pageSize), scale: Self.pixelsPerPoint).cgImage)
        return try bandWidth { context in context.draw(picture, in: CGRect(origin: .zero, size: Self.pageSize)) }
    }

    private func pageWidth(of page: PDFPage) throws -> Double {
        try bandWidth { context in page.draw(with: .mediaBox, to: context) }
    }

    private func documentWithBlankPage() throws -> PDFDocument {
        let pageData = NSMutableData()
        var mediaBox = CGRect(origin: .zero, size: Self.pageSize)
        let context = try XCTUnwrap(CGContext(consumer: XCTUnwrap(CGDataConsumer(data: pageData)), mediaBox: &mediaBox, nil))
        context.beginPDFPage(nil)
        context.endPDFPage()
        context.closePDF()
        return try XCTUnwrap(PDFDocument(data: pageData as Data))
    }

    /// Every ink, and the turning inks with their nib across the stroke, along it and between.
    func testAStrokeWeighsTheSameOnTheCanvasInTheLiveDocumentAndInTheSavedFile() throws {
        let quarterTurn = CGFloat.pi / 2
        let inkCases: [(inkType: PKInkingTool.InkType, pointSize: CGFloat, azimuth: CGFloat, tolerance: Double)] = [
            (.pen, 3, 0, 0.08), (.pen, 8, 0, 0.08), (.monoline, 4, 0, 0.08), (.pencil, 4, 0, 0.15),
            (.fountainPen, 5, quarterTurn, 0.1), (.fountainPen, 12, quarterTurn, 0.1), (.fountainPen, 12, quarterTurn / 3, 0.15), (.fountainPen, 12, quarterTurn * 2 / 3, 0.15), (.fountainPen, 12, 0, 0.2),
            (.marker, 12, quarterTurn, 0.1), (.marker, 24, quarterTurn, 0.1), (.marker, 24, quarterTurn / 3, 0.15), (.marker, 24, quarterTurn * 2 / 3, 0.15), (.marker, 24, 0, 0.2)
        ]
        for inkCase in inkCases {
            let stroke = stroke(inkCase.inkType, pointSize: inkCase.pointSize, azimuth: inkCase.azimuth)
            let label = "\(inkCase.inkType.rawValue) size \(inkCase.pointSize) nib \(inkCase.azimuth)"
            let document = try documentWithBlankPage()
            var tracker = PDFPageInkTracker(group: PDFInkGroups.defaultGroup)
            let coordinates = try PageCoordinates(cropBox: CGRect(origin: .zero, size: Self.pageSize), overlaySize: Self.pageSize)
            let update = tracker.update(for: PKDrawing(strokes: [stroke]), pageIndex: 0, coordinates: coordinates)
            try PDFPageManager.apply(.updateInk(update), to: document, drawsInkOutlines: true)
            let drawnByCanvas = try canvasWidth(of: stroke)
            let drawnLive = try pageWidth(of: XCTUnwrap(document.page(at: 0)))
            let reread = try XCTUnwrap(PDFDocument(data: XCTUnwrap(document.dataRepresentation())))
            let drawnFromFile = try pageWidth(of: XCTUnwrap(reread.page(at: 0)))
            print("INK-WEIGHT \(label): canvas \(drawnByCanvas) live \(drawnLive) file \(drawnFromFile)")
            XCTAssertEqual(drawnLive / drawnByCanvas, 1, accuracy: inkCase.tolerance + 0.3 / drawnByCanvas, "Live document, \(label)")
            XCTAssertEqual(drawnFromFile / drawnByCanvas, 1, accuracy: inkCase.tolerance + 0.3 / drawnByCanvas, "Saved file, \(label)")
        }
    }
}
#endif
