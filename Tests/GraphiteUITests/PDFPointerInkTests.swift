/**
 * File: PDFPointerInkTests.swift
 * ------------------------------
 * Layer: Tests
 * Description: Ink drawn with the Mac's pointer as PencilKit strokes in a page's drawing space, which strokes the
 *              eraser touches, the Draw tool's stored style, and the Text Box tool's press and drag decisions.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 13/11/2026
 */

import XCTest
import PencilKit
import GraphiteCore
@testable import GraphiteUI

final class PDFPointerInkTests: XCTestCase {
    private let cropBox = CGRect(x: 0, y: 0, width: 400, height: 600)

    private func samples(_ points: [CGPoint]) -> [PDFPointerInkSample] {
        points.enumerated().map { index, point in PDFPointerInkSample(pagePoint: point, timeSeconds: 10 + Double(index) / 60) }
    }

    func testAStrokeIsInTheDrawingSpaceFromThePagesTopLeftAtTheStylesWidth() throws {
        let coordinates = try PDFPointerInk.coordinates(of: cropBox)
        let style = PDFMarkupInkStyle(color: PDFTextColor(red: 1, green: 0, blue: 0), width: .bold)
        let stroke = try XCTUnwrap(PDFPointerInk.stroke(through: samples([CGPoint(x: 50, y: 550), CGPoint(x: 150, y: 550)]), style: style,
                                                        coordinates: coordinates, creationDate: Date(timeIntervalSince1970: 1)))
        XCTAssertEqual(stroke.path.count, 2)
        XCTAssertEqual(stroke.path[0].location.x, 50, accuracy: 0.001)
        XCTAssertEqual(stroke.path[0].location.y, 50, accuracy: 0.001, "Page y = 550 is 50 points from the top of a 600-point page.")
        XCTAssertEqual(stroke.path[0].size.width, 5, accuracy: 0.001)
        XCTAssertEqual(stroke.path[1].timeOffset, 1.0 / 60, accuracy: 0.0001)
        XCTAssertEqual(stroke.ink.inkType, .pen)
    }

    func testPlacesTooCloseAreDroppedAndAClickLeavesADot() throws {
        let coordinates = try PDFPointerInk.coordinates(of: cropBox)
        let close = try XCTUnwrap(PDFPointerInk.stroke(through: samples([CGPoint(x: 10, y: 10), CGPoint(x: 10.1, y: 10), CGPoint(x: 20, y: 10)]),
                                                       style: .default, coordinates: coordinates, creationDate: Date()))
        XCTAssertEqual(close.path.count, 2)
        let dot = try XCTUnwrap(PDFPointerInk.stroke(through: samples([CGPoint(x: 10, y: 10)]), style: .default, coordinates: coordinates, creationDate: Date()))
        XCTAssertEqual(dot.path.count, 2, "A click is drawn to a second place, so readers show a dot.")
        XCTAssertNil(PDFPointerInk.stroke(through: [], style: .default, coordinates: coordinates, creationDate: Date()))
    }

    func testTheEraserFindsTheStrokesItPassesLatestFirst() throws {
        let coordinates = try PDFPointerInk.coordinates(of: cropBox)
        func line(_ fromPoint: CGPoint, _ toPoint: CGPoint) throws -> PKStroke {
            try XCTUnwrap(PDFPointerInk.stroke(through: samples([fromPoint, toPoint]), style: .default, coordinates: coordinates, creationDate: Date()))
        }
        let drawing = PKDrawing(strokes: [try line(CGPoint(x: 0, y: 500), CGPoint(x: 200, y: 500)),
                                          try line(CGPoint(x: 100, y: 400), CGPoint(x: 100, y: 590)),
                                          try line(CGPoint(x: 300, y: 100), CGPoint(x: 390, y: 100))])
        let crossing = coordinates.overlayPoint(fromPDF: CGPoint(x: 100, y: 500))
        XCTAssertEqual(PDFPointerInk.indicesOfStrokes(in: drawing, touching: crossing), [1, 0])
        XCTAssertEqual(PDFPointerInk.indicesOfStrokes(in: drawing, touching: coordinates.overlayPoint(fromPDF: CGPoint(x: 150, y: 503))), [0],
                       "Within reach of the stroke counts.")
        XCTAssertEqual(PDFPointerInk.indicesOfStrokes(in: drawing, touching: coordinates.overlayPoint(fromPDF: CGPoint(x: 250, y: 300))), [])
        let fastPass = PDFPointerInk.indicesOfStrokes(in: drawing, alongSegmentFrom: coordinates.overlayPoint(fromPDF: CGPoint(x: 340, y: 50)),
                                                      to: coordinates.overlayPoint(fromPDF: CGPoint(x: 340, y: 150)))
        XCTAssertEqual(fastPass, [2], "A stroke between two far places of the pointer is passed all the same.")
    }

    func testTheInkStyleIsKeptByItsNameAndAnUnknownNameIsRefused() throws {
        let style = PDFMarkupInkStyle(color: try XCTUnwrap(PDFTextColor(hex: "#086ddd")), width: .fine)
        XCTAssertEqual(style.rawValue, "fine #086ddd")
        XCTAssertEqual(PDFMarkupInkStyle(rawValue: style.rawValue), style)
        XCTAssertEqual(PDFMarkupInkStyle.default.rawValue, "medium #000000")
        XCTAssertNil(PDFMarkupInkStyle(rawValue: "huge #000000"))
        XCTAssertNil(PDFMarkupInkStyle(rawValue: "fine"))
    }

    func testOnlyThePageToolsTakePressesFromPDFKit() {
        XCTAssertEqual(PDFMarkupTool.allCases.filter(\.takesPagePresses), [.draw, .eraseInk, .textBox])
        for tool in [PDFMarkupTool.draw, .eraseInk, .textBox] {
            XCTAssertNil(tool.styleToApplyOnMouseUp(style: .default, selectionHasText: true, clickChoseExistingMark: false))
        }
    }

    func testATextBoxPressPlacesSelectsTypesResizesOrEndsTyping() {
        typealias Press = PDFTextBoxPointerPress
        XCTAssertEqual(Press.outcome(pressedBoxName: nil, pressedHandle: nil, selectedBoxName: nil, isTyping: false, clickCount: 1), .placeNewBox)
        XCTAssertEqual(Press.outcome(pressedBoxName: nil, pressedHandle: nil, selectedBoxName: "A", isTyping: false, clickCount: 1), .deselect,
                       "A click away from the selected box lets it go rather than placing another.")
        XCTAssertEqual(Press.outcome(pressedBoxName: "B", pressedHandle: nil, selectedBoxName: "A", isTyping: false, clickCount: 1), .select(boxName: "B"))
        XCTAssertEqual(Press.outcome(pressedBoxName: "B", pressedHandle: nil, selectedBoxName: nil, isTyping: false, clickCount: 2), .beginTyping(boxName: "B"))
        XCTAssertEqual(Press.outcome(pressedBoxName: nil, pressedHandle: .trailing, selectedBoxName: "A", isTyping: false, clickCount: 1),
                       .resize(boxName: "A", edge: .trailing))
        XCTAssertEqual(Press.outcome(pressedBoxName: nil, pressedHandle: nil, selectedBoxName: "A", isTyping: true, clickCount: 1),
                       .endTyping(selectingBoxName: nil))
        XCTAssertEqual(Press.outcome(pressedBoxName: "B", pressedHandle: nil, selectedBoxName: "A", isTyping: true, clickCount: 1),
                       .endTyping(selectingBoxName: "B"))
    }

    func testADragMovesABoxOrMakesItWiderFromEitherSide() {
        let box = PDFTextBox(name: "A", runs: [], origin: CGPoint(x: 100, y: 500), width: 200, height: 20, rotationRadians: 0, style: .plain)
        XCTAssertEqual(PDFTextBoxPointerDrag.moved(box, by: CGVector(dx: 10, dy: -5)).origin, CGPoint(x: 110, y: 495))
        let wider = PDFTextBoxPointerDrag.resized(box, from: .trailing, by: CGVector(dx: 40, dy: 30))
        XCTAssertEqual(wider.width, 240, accuracy: 0.001, "Only the part along the text counts.")
        XCTAssertEqual(wider.origin, box.origin)
        let fromLeading = PDFTextBoxPointerDrag.resized(box, from: .leading, by: CGVector(dx: 50, dy: 0))
        XCTAssertEqual(fromLeading.width, 150, accuracy: 0.001)
        XCTAssertEqual(fromLeading.origin.x, 150, accuracy: 0.001, "The trailing side stays where it is.")
        XCTAssertEqual(PDFTextBoxPointerDrag.resized(box, from: .trailing, by: CGVector(dx: -500, dy: 0)).width, PDFTextBox.minimumWidth)
    }
}
