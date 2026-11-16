/**
 * File: PDFShownInkAnnotationTests.swift
 * --------------------------------------
 * Layer: Tests
 * Description: Ink of a shown PDF draws nothing while a page's canvas hides it, draws as PDFKit draws it while shown,
 *              and is drawn as shown for a thumbnail even while hidden.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 12/11/2026
 */
import XCTest
import PDFKit
import GraphiteCore
import GraphiteTestSupport
@testable import GraphiteApple

/// PDFKit on the iPad keeps a layer for every annotation, hidden ones included, and draws it again from the stroke's
/// appearance each time it makes the page's view: a hidden stroke now draws nothing there (`PDFShownInkAnnotation`).
final class PDFShownInkAnnotationTests: XCTestCase {
    private static let pageSize = CGSize(width: 200, height: 200)
    /// Held here: a document holds its delegate weakly.
    private let shownDocumentDelegate = PDFShownInkTestDelegate()

    /// How many dark pixels the annotation draws, at one pixel a point.
    private func darkPixelCount(drawing draw: (CGContext) -> Void) throws -> Int {
        let width = Int(Self.pageSize.width), height = Int(Self.pageSize.height)
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                                              space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue))
        context.setFillColor(gray: 1, alpha: 1)
        context.fill(CGRect(origin: .zero, size: Self.pageSize))
        draw(context)
        let pixels = UnsafeBufferPointer(start: try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self), count: width * height)
        return pixels.filter { pixel in pixel < 128 }.count
    }

    /// A broad stroke read from a file into a shown document, where PDFKit makes it the class the delegate names.
    private func readBackStroke() throws -> (annotation: PDFAnnotation, page: PDFPage, document: PDFDocument) {
        let written = try XCTUnwrap(PDFDocument(data: try DenseHandwritingNotebook.blankPages(count: 1, size: Self.pageSize)))
        PDFPageManager.prepareForWriting(written)
        let outline = [[CGPoint(x: 40, y: 40), CGPoint(x: 160, y: 40), CGPoint(x: 160, y: 70), CGPoint(x: 40, y: 70)]]
        let stroke = PortableInkStroke(name: "stroke", segments: [[CGPoint(x: 40, y: 55), CGPoint(x: 160, y: 55)]], width: 30,
                                       red: 0, green: 0, blue: 0, alpha: 1, outline: outline)
        try PDFPageManager.apply(.updateInk(PDFInkUpdate(pageIndex: 0, group: PDFInkGroups.defaultGroup, removal: .strokes([]), addedStrokes: [stroke],
                                                         editableRecord: nil)), to: written, drawsInkOutlines: true)
        let shown = try XCTUnwrap(PDFDocument(data: try XCTUnwrap(written.dataRepresentation())))
        shown.delegate = shownDocumentDelegate
        let page = try XCTUnwrap(shown.page(at: 0))
        return (try XCTUnwrap(page.annotations.first { annotation in annotation.type == "Ink" }), page, shown)
    }

    func testAShownStrokeDrawsAsPDFKitDrawsItAndNothingWhileHidden() throws {
        let (annotation, page, _) = try readBackStroke()
        XCTAssertTrue(annotation is PDFShownInkAnnotation, "The delegate's class")
        let shownCount = try darkPixelCount { context in page.draw(with: .mediaBox, to: context) }
        XCTAssertGreaterThan(shownCount, 2_500, "The 120 by 30 point stroke is drawn from its saved appearance.")

        annotation.shouldDisplay = false
        XCTAssertEqual(try darkPixelCount { context in annotation.draw(with: .mediaBox, in: context) }, 0, "Hidden, it draws nothing.")
        let thumbnailCount = try darkPixelCount { context in annotation.drawAsShown(with: .mediaBox, in: context) }
        XCTAssertEqual(Double(thumbnailCount), Double(shownCount), accuracy: Double(shownCount) * 0.05, "A thumbnail draws it as it shows.")
    }

    /// Ink drawn in Graphite and shown before it is saved: its outline is drawn while shown, nothing while hidden.
    func testInkDrawnOnAShownPageDrawsNothingWhileHidden() throws {
        let outline = [[CGPoint(x: 40, y: 40), CGPoint(x: 160, y: 40), CGPoint(x: 160, y: 70), CGPoint(x: 40, y: 70)]]
        let stroke = PortableInkStroke(name: "stroke", segments: [[CGPoint(x: 40, y: 55), CGPoint(x: 160, y: 55)]], width: 30,
                                       red: 0, green: 0, blue: 0, alpha: 1, outline: outline)
        let document = try XCTUnwrap(PDFDocument(data: try DenseHandwritingNotebook.blankPages(count: 1, size: Self.pageSize)))
        let page = try XCTUnwrap(document.page(at: 0))
        let annotation = try XCTUnwrap(PDFInkAnnotationFactory.annotation(for: stroke, group: PDFInkGroups.defaultGroup, isForWrittenDocument: false,
                                                                           authorName: nil))
        page.addAnnotation(annotation)
        let shownCount = try darkPixelCount { context in annotation.draw(with: .mediaBox, in: context) }
        XCTAssertGreaterThan(shownCount, 3_000)
        annotation.shouldDisplay = false
        XCTAssertEqual(try darkPixelCount { context in annotation.draw(with: .mediaBox, in: context) }, 0)
        XCTAssertEqual(try darkPixelCount { context in annotation.drawAsShown(with: .mediaBox, in: context) }, shownCount)
    }
}

/// The iPad's mapping of `/Ink` to `PDFShownInkAnnotation`, which `PDFAnnotationDrawingDelegate` makes only where a
/// canvas hides ink, so the Mac's tests can read a stroke back as the iPad does.
private final class PDFShownInkTestDelegate: NSObject, PDFDocumentDelegate {
    func `class`(forAnnotationType annotationType: String) -> AnyClass {
        annotationType == PDFShownInkAnnotation.annotationTypeName ? PDFShownInkAnnotation.self : PDFAnnotation.self
    }
}
