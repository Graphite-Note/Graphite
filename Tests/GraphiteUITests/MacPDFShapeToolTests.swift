/**
 * File: MacPDFShapeToolTests.swift
 * --------------------------------
 * Layer: Tests
 * Description: The Mac's Shapes tool in a PDF view: dragging draws the row's shape, a click selects one, a drag moves
 *              it, a handle reshapes it, the row restyles it and Delete removes it, each one step of the history, also
 *              for another application's shape, and the shapes saved as standard annotations.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 13/11/2026
 */

#if os(macOS)
import XCTest
import AppKit
import PDFKit
import GraphiteCore
import GraphiteApple
@testable import GraphiteUI
import GraphiteTestSupport

@MainActor
final class MacPDFShapeToolTests: XCTestCase {
    /// Opened before each test, whose body runs synchronously as AppKit's events do (see `MacPDFPageToolsTests`).
    private var openedHarness: MacPDFPageToolHarness?
    private let red = PDFTextColor(red: 1, green: 0, blue: 0)
    private let blue = PDFTextColor(red: 0, green: 0, blue: 1)

    override func setUp() async throws {
        try await super.setUp()
        openedHarness = try await MacPDFPageToolHarness.open(for: self, prefix: "MacPDFShapeTool")
    }

    private func makeFixture() throws -> MacPDFPageToolHarness {
        let fixture = try XCTUnwrap(openedHarness)
        fixture.choose(.shapes)
        return fixture
    }

    private func assertRectangle(_ actual: CGRect?, _ expected: CGRect, file: StaticString = #filePath, line: UInt = #line) {
        guard let actual else { return XCTFail("No shape.", file: file, line: line) }
        for (got, wanted) in [(actual.minX, expected.minX), (actual.minY, expected.minY), (actual.width, expected.width), (actual.height, expected.height)] {
            XCTAssertEqual(got, wanted, accuracy: 0.01, "\(actual) is not \(expected)", file: file, line: line)
        }
    }

    private func shapes(_ fixture: MacPDFPageToolHarness) -> [PDFShape] {
        fixture.page.annotations.compactMap(PDFShape.init(annotation:))
    }

    func testDraggingDrawsTheRowsShapeAsOneStepAndSelectsIt() throws {
        let fixture = try makeFixture()
        fixture.toolbar.useShapeStyle(PDFMarkupShapeStyle(kind: .oval, borderColor: red, fillColor: blue, width: .bold))
        try fixture.drag(through: [CGPoint(x: 100, y: 400), CGPoint(x: 160, y: 380), CGPoint(x: 250, y: 300)])
        let drawn = try XCTUnwrap(shapes(fixture).first)
        XCTAssertEqual(drawn.kind, .oval)
        XCTAssertEqual(drawn.boxRectangle.minX, 100, accuracy: 0.5)
        XCTAssertEqual(drawn.boxRectangle.maxY, 400, accuracy: 0.5)
        XCTAssertEqual(drawn.boxRectangle.width, 150, accuracy: 0.5)
        XCTAssertEqual(drawn.borderColor, red)
        XCTAssertEqual(drawn.fillColor, blue)
        XCTAssertEqual(drawn.lineWidth, PDFMarkupInkWidth.bold.points)
        XCTAssertEqual(fixture.page.annotations.first?.type, "Circle")
        XCTAssertEqual(fixture.session.undoManager.undoActionName, "Add Oval")
        XCTAssertEqual(fixture.tools?.shapes?.selectedShapeName, drawn.name, "The shape drawn is selected.")

        // A click, outside an undo group of its own: it records nothing.
        fixture.tools?.mouseDown(try fixture.event(.leftMouseDown, at: CGPoint(x: 300, y: 100)))
        fixture.tools?.mouseUp(try fixture.event(.leftMouseUp, at: CGPoint(x: 300, y: 100)))
        XCTAssertEqual(shapes(fixture).count, 1, "A click without a drag draws nothing.")
        XCTAssertNil(fixture.tools?.shapes?.selectedShapeName, "and leaves the selection.")
        fixture.session.undoManager.undo()
        XCTAssertTrue(shapes(fixture).isEmpty)
    }

    func testASelectedShapeIsMovedReshapedRestyledAndDeletedEachAsOneStep() throws {
        let fixture = try makeFixture()
        fixture.toolbar.useShapeStyle(PDFMarkupShapeStyle(kind: .rectangle, borderColor: .black, fillColor: nil, width: .medium))
        try fixture.drag(through: [CGPoint(x: 100, y: 400), CGPoint(x: 200, y: 300)])
        let drawn = try XCTUnwrap(shapes(fixture).first)

        try fixture.drag(through: [CGPoint(x: 150, y: 350), CGPoint(x: 180, y: 330)])
        assertRectangle(shapes(fixture).first?.boxRectangle, drawn.boxRectangle.offsetBy(dx: 30, dy: -20))
        XCTAssertEqual(fixture.session.undoManager.undoActionName, "Move Shape")

        // The handle at the bottom-right corner, moved to make the box wider.
        try fixture.drag(through: [CGPoint(x: 230, y: 280), CGPoint(x: 280, y: 280)])
        XCTAssertEqual(try XCTUnwrap(shapes(fixture).first).boxRectangle.width, 150, accuracy: 0.5)
        XCTAssertEqual(try XCTUnwrap(shapes(fixture).first).boxRectangle.minX, 130, accuracy: 0.5, "The opposite corner stays.")
        XCTAssertEqual(fixture.session.undoManager.undoActionName, "Resize Shape")

        fixture.step { fixture.toolbar.chooseShapeStyle(PDFMarkupShapeStyle(kind: .arrow, borderColor: red, fillColor: blue, width: .fine)) }
        let restyled = try XCTUnwrap(shapes(fixture).first)
        XCTAssertEqual(restyled.kind, .rectangle, "Restyling keeps the shape's kind and place.")
        XCTAssertEqual(restyled.borderColor, red)
        XCTAssertEqual(restyled.fillColor, blue)
        XCTAssertEqual(restyled.lineWidth, PDFMarkupInkWidth.fine.points)
        XCTAssertEqual(fixture.session.undoManager.undoActionName, "Format Shape")

        try fixture.step { XCTAssertTrue(try fixture.pressDelete()) }
        XCTAssertTrue(shapes(fixture).isEmpty)
        XCTAssertEqual(fixture.session.undoManager.undoActionName, "Delete Shape")

        fixture.session.undoManager.undo()
        XCTAssertEqual(shapes(fixture).first?.borderColor, red)
        fixture.session.undoManager.undo()
        XCTAssertEqual(shapes(fixture).first?.borderColor, .black)
        fixture.session.undoManager.undo()
        XCTAssertEqual(try XCTUnwrap(shapes(fixture).first).boxRectangle.width, 100, accuracy: 0.5)
        fixture.session.undoManager.undo()
        assertRectangle(shapes(fixture).first?.boxRectangle, drawn.boxRectangle)
        fixture.session.undoManager.redo()
        assertRectangle(shapes(fixture).first?.boxRectangle, drawn.boxRectangle.offsetBy(dx: 30, dy: -20))
    }

    func testALineIsReshapedByItsEnd() throws {
        let fixture = try makeFixture()
        fixture.toolbar.useShapeStyle(PDFMarkupShapeStyle(kind: .arrow, borderColor: .black, fillColor: nil, width: .medium))
        try fixture.drag(through: [CGPoint(x: 100, y: 100), CGPoint(x: 300, y: 100)])
        XCTAssertEqual(fixture.page.annotations.first?.endLineStyle, .openArrow)
        try fixture.drag(through: [CGPoint(x: 300, y: 100), CGPoint(x: 300, y: 250)])
        let reshaped = try XCTUnwrap(shapes(fixture).first)
        XCTAssertEqual(reshaped.start, CGPoint(x: 100, y: 100))
        XCTAssertEqual(reshaped.end.y, 250, accuracy: 0.5)
        XCTAssertEqual(fixture.session.undoManager.undoActionName, "Resize Shape")
    }

    func testAnotherApplicationsUnnamedShapeIsMovedAndPutBack() throws {
        let fixture = try makeFixture()
        let square = PDFAnnotation(bounds: CGRect(x: 50, y: 50, width: 100, height: 80), forType: .square, withProperties: nil)
        square.color = .green
        square.userName = "Preview User"
        fixture.page.addAnnotation(square)
        XCTAssertNil(square.persistentName)

        try fixture.drag(through: [CGPoint(x: 100, y: 90), CGPoint(x: 200, y: 190)])
        let moved = try XCTUnwrap(shapes(fixture).first)
        assertRectangle(moved.boxRectangle, CGRect(x: 150, y: 150, width: 100, height: 80))
        XCTAssertEqual(fixture.page.annotations.first?.userName, "Preview User", "It keeps its author.")
        XCTAssertEqual(fixture.session.undoManager.undoActionName, "Move Shape")
        fixture.session.undoManager.undo()
        assertRectangle(shapes(fixture).first?.boxRectangle, CGRect(x: 50, y: 50, width: 100, height: 80))
        fixture.session.undoManager.redo()
        XCTAssertEqual(try XCTUnwrap(shapes(fixture).first).boxRectangle.minX, 150, accuracy: 0.5)
    }

    func testShapesAreSavedAsStandardAnnotationsThatReadersShow() async throws {
        let fixture = try makeFixture()
        for kind in PDFShapeKind.allCases {
            fixture.toolbar.useShapeStyle(PDFMarkupShapeStyle(kind: kind, borderColor: red, fillColor: nil, width: .medium))
            let top = 550 - CGFloat(PDFShapeKind.allCases.firstIndex(of: kind) ?? 0) * 120
            try fixture.drag(through: [CGPoint(x: 60, y: top), CGPoint(x: 260, y: top - 80)])
        }
        try await fixture.session.save()
        let reopened = try XCTUnwrap(PDFDocument(url: fixture.location)?.page(at: 0))
        XCTAssertEqual(reopened.annotations.compactMap(\.type).sorted(), ["Circle", "Line", "Line", "Square"])
        XCTAssertEqual(reopened.annotations.compactMap(PDFShape.init(annotation:)).map(\.kind).sorted { first, second in first.rawValue < second.rawValue },
                       [.arrow, .line, .oval, .rectangle])
        // Drawn by PDFKit as the iPad draws the page: the shapes' red is on the page's picture.
        let picture = reopened.thumbnail(of: CGSize(width: 400, height: 600), for: .cropBox)
        let bitmap = try XCTUnwrap(picture.representations.first as? NSBitmapImageRep ?? picture.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))
        let hasRed = (0..<bitmap.pixelsHigh).contains { row in
            (0..<bitmap.pixelsWide).contains { column in
                guard let color = bitmap.colorAt(x: column, y: row)?.usingColorSpace(.sRGB) else { return false }
                return color.redComponent > 0.8 && color.greenComponent < 0.3 && color.blueComponent < 0.3
            }
        }
        XCTAssertTrue(hasRed, "The saved shapes are drawn when the page is.")
    }
}
#endif
