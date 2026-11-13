/**
 * File: PDFShapeTests.swift
 * -------------------------
 * Layer: Tests
 * Description: Shapes as they are written into a PDF: standard `/Square`, `/Circle` and `/Line` annotations with an
 *              appearance, border, fill and arrow head, read back after a save, found under a point and reshaped.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 13/11/2026
 */

import XCTest
import PDFKit
import CoreGraphics
import GraphiteCore
@testable import GraphiteApple

final class PDFShapeTests: XCTestCase {
    private let red = PDFTextColor(red: 1, green: 0, blue: 0)
    private let yellow = PDFTextColor(red: 1, green: 1, blue: 0)

    private func blankDocument() throws -> PDFDocument {
        try XCTUnwrap(PDFDocument(data: PDFTemplateGenerator.documentData(paper: PaperSpecification(template: .blank))))
    }

    /// The author a test writes as, whatever the name chosen on the device.
    private func author(named name: String) throws -> PDFAnnotationAuthor {
        let suiteName = "PDFShapeTests-\(UUID().uuidString)"
        addTeardownBlock { UserDefaults().removePersistentDomain(forName: suiteName) }
        return PDFAnnotationAuthor(defaults: try XCTUnwrap(UserDefaults(suiteName: suiteName)), ownerName: { name })
    }

    private func reread(_ document: PDFDocument) throws -> PDFDocument {
        try XCTUnwrap(PDFDocument(data: try XCTUnwrap(document.dataRepresentation())))
    }

    func testEachShapeIsItsStandardSubtypeWithAnAppearanceItsColoursAndWidth() throws {
        let shapes: [(PDFShape, String)] = [
            (PDFShape(name: "box", kind: .rectangle, start: CGPoint(x: 100, y: 100), end: CGPoint(x: 300, y: 200), borderColor: red,
                      fillColor: yellow, lineWidth: 2.5), "Square"),
            (PDFShape(name: "ring", kind: .oval, start: CGPoint(x: 300, y: 400), end: CGPoint(x: 100, y: 300), borderColor: red, lineWidth: 1), "Circle"),
            (PDFShape(name: "rule", kind: .line, start: CGPoint(x: 50, y: 600), end: CGPoint(x: 250, y: 650), borderColor: red, lineWidth: 5), "Line"),
            (PDFShape(name: "pointer", kind: .arrow, start: CGPoint(x: 50, y: 500), end: CGPoint(x: 250, y: 550), borderColor: red, lineWidth: 1), "Line"),
        ]
        for (shape, subtype) in shapes {
            let document = try blankDocument()
            try PDFPageManager.apply(.addShape(page: 0, shape: shape), to: document)
            try PDFAnnotationDictionaryReading.withAnnotationDictionaries(in: try XCTUnwrap(document.dataRepresentation())) { dictionaries in
                let annotation = try XCTUnwrap(dictionaries.first)
                XCTAssertEqual(PDFAnnotationDictionaryReading.name("Subtype", in: annotation), subtype)
                XCTAssertTrue(PDFAnnotationDictionaryReading.hasKey("AP", in: annotation), "\(shape.kind): readers that draw only appearances show it.")
                XCTAssertEqual(PDFAnnotationDictionaryReading.string("NM", in: annotation), shape.name)
                XCTAssertEqual(PDFAnnotationDictionaryReading.numbers("C", in: annotation), [1, 0, 0], "\(shape.kind): the border colour.")
                XCTAssertEqual(PDFAnnotationDictionaryReading.integer("F", in: annotation).map { flags in flags & 4 }, 4, "Printable.")
                if shape.kind.isSegment {
                    let line = try XCTUnwrap(PDFAnnotationDictionaryReading.numbers("L", in: annotation))
                    for (written, wanted) in zip(line, [shape.start.x, shape.start.y, shape.end.x, shape.end.y]) {
                        XCTAssertEqual(written, Double(wanted), accuracy: 0.01, "\(shape.kind): /L is the line in page space.")
                    }
                }
            }
            let readBack = try XCTUnwrap(try reread(document).page(at: 0)?.annotations.compactMap(PDFShape.init(annotation:)).first)
            XCTAssertEqual(readBack.kind, shape.kind)
            XCTAssertEqual(readBack.name, shape.name)
            XCTAssertEqual(readBack.borderColor, shape.borderColor)
            XCTAssertEqual(readBack.fillColor, shape.fillColor, "\(shape.kind): the fill, /IC, or none.")
            XCTAssertEqual(readBack.lineWidth, shape.lineWidth, accuracy: 0.01)
            if shape.kind.isSegment {
                XCTAssertEqual(readBack.start.x, shape.start.x, accuracy: 0.01)
                XCTAssertEqual(readBack.end.y, shape.end.y, accuracy: 0.01)
            } else {
                XCTAssertEqual(readBack.boxRectangle, shape.boxRectangle)
            }
        }
    }

    func testAnArrowHasItsHeadAtItsEndAndALineHasNone() throws {
        let document = try blankDocument()
        try PDFPageManager.apply(.addShape(page: 0, shape: PDFShape(name: "arrow", kind: .arrow, start: CGPoint(x: 50, y: 50), end: CGPoint(x: 150, y: 90),
                                                                    borderColor: .black, lineWidth: 1)), to: document)
        try PDFPageManager.apply(.addShape(page: 0, shape: PDFShape(name: "line", kind: .line, start: CGPoint(x: 50, y: 150), end: CGPoint(x: 150, y: 190),
                                                                    borderColor: .black, lineWidth: 1)), to: document)
        let annotations = try XCTUnwrap(try reread(document).page(at: 0)?.annotations)
        let arrow = try XCTUnwrap(annotations.first { annotation in annotation.persistentName == "arrow" })
        let line = try XCTUnwrap(annotations.first { annotation in annotation.persistentName == "line" })
        XCTAssertEqual(arrow.startLineStyle, PDFLineStyle.none)
        XCTAssertEqual(arrow.endLineStyle, .openArrow)
        XCTAssertEqual(line.endLineStyle, PDFLineStyle.none)
    }

    func testAnotherApplicationsLineWithItsHeadAtItsStartIsReadAsAnArrowToThatPoint() throws {
        let annotation = PDFAnnotation(bounds: CGRect(x: 0, y: 0, width: 100, height: 100), forType: .line, withProperties: nil)
        annotation.startPoint = CGPoint(x: 10, y: 10)
        annotation.endPoint = CGPoint(x: 90, y: 90)
        annotation.startLineStyle = .closedArrow
        let shape = try XCTUnwrap(PDFShape(annotation: annotation))
        XCTAssertEqual(shape.kind, .arrow)
        XCTAssertEqual(shape.end, CGPoint(x: 10, y: 10))
        XCTAssertEqual(shape.start, CGPoint(x: 90, y: 90))
    }

    func testReplacingAShapeKeepsItsAuthorAndRemovingItLeavesThePageEmpty() throws {
        let document = try blankDocument()
        let shape = PDFShape(name: "box", kind: .rectangle, start: CGPoint(x: 10, y: 10), end: CGPoint(x: 60, y: 40), borderColor: .black, lineWidth: 1)
        try PDFPageManager.apply(.addShape(page: 0, shape: shape), to: document, author: try author(named: "Ada"))
        let page = try XCTUnwrap(document.page(at: 0))
        let reference = PDFAnnotationReference(annotation: try XCTUnwrap(page.annotations.first), pageIndex: 0)
        try PDFPageManager.apply(.replaceShape(reference, with: shape.moved(by: CGVector(dx: 100, dy: 0))), to: document,
                                 author: try author(named: "Someone Else"))
        let moved = try XCTUnwrap(page.annotations.first)
        XCTAssertEqual(page.annotations.count, 1)
        XCTAssertEqual(moved.bounds.minX, 110, accuracy: 0.01)
        XCTAssertEqual(moved.userName, "Ada", "A moved shape keeps the author it had.")
        try PDFPageManager.apply(.removeAnnotation(PDFAnnotationReference(annotation: moved, pageIndex: 0)), to: document)
        XCTAssertTrue(page.annotations.isEmpty)
    }

    func testAPointIsOnABoxInsideItAndOnALineNearIt() {
        let box = PDFShape(kind: .rectangle, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 100, y: 50), borderColor: .black, lineWidth: 2)
        XCTAssertTrue(box.contains(CGPoint(x: 50, y: 25), tolerance: 0))
        XCTAssertTrue(box.contains(CGPoint(x: 103, y: 25), tolerance: 3))
        XCTAssertFalse(box.contains(CGPoint(x: 110, y: 25), tolerance: 3))
        let oval = PDFShape(kind: .oval, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 100, y: 50), borderColor: .black, lineWidth: 0)
        XCTAssertTrue(oval.contains(CGPoint(x: 50, y: 25), tolerance: 0))
        XCTAssertFalse(oval.contains(CGPoint(x: 2, y: 2), tolerance: 0), "The oval's corner is outside it.")
        let line = PDFShape(kind: .line, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 100, y: 0), borderColor: .black, lineWidth: 2)
        XCTAssertTrue(line.contains(CGPoint(x: 50, y: 4), tolerance: 3))
        XCTAssertFalse(line.contains(CGPoint(x: 50, y: 10), tolerance: 3))
        XCTAssertFalse(line.contains(CGPoint(x: 110, y: 0), tolerance: 3), "Past its end.")
    }

    func testAHandleMovesItsCornerOrPointAndTheOppositeOneStays() {
        let box = PDFShape(kind: .rectangle, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 100, y: 50), borderColor: .black, lineWidth: 1)
        XCTAssertEqual(box.handles.map(\.handle), [.start, .end, .startHorizontalEndVertical, .endHorizontalStartVertical])
        XCTAssertEqual(box.moving(.end, to: CGPoint(x: 200, y: 80)).boxRectangle, CGRect(x: 0, y: 0, width: 200, height: 80))
        XCTAssertEqual(box.moving(.startHorizontalEndVertical, to: CGPoint(x: -20, y: 70)).boxRectangle, CGRect(x: -20, y: 0, width: 120, height: 70))
        XCTAssertEqual(box.moving(.endHorizontalStartVertical, to: CGPoint(x: 60, y: 10)).boxRectangle, CGRect(x: 0, y: 10, width: 60, height: 40))
        XCTAssertEqual(box.moved(by: CGVector(dx: 5, dy: -5)).boxRectangle, CGRect(x: 5, y: -5, width: 100, height: 50))
        let line = PDFShape(kind: .arrow, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 100, y: 0), borderColor: .black, lineWidth: 1)
        XCTAssertEqual(line.handles.map(\.handle), [.start, .end], "A line has its two points only.")
        XCTAssertEqual(line.moving(.start, to: CGPoint(x: 30, y: 30)).start, CGPoint(x: 30, y: 30))
        XCTAssertFalse(PDFShape(kind: .rectangle, start: .zero, end: CGPoint(x: 1, y: 40), borderColor: .black, lineWidth: 1).hasVisibleSize,
                       "A box one point wide is a click, not a shape.")
    }
}
