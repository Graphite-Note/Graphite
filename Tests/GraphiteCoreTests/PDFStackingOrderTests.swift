/**
 * File: PDFStackingOrderTests.swift
 * ---------------------------------
 * Layer: Core tests
 * Description: The stacking order rules of a PDF page's objects and ink, with plain values.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 16/11/2026
 */
import XCTest
@testable import GraphiteCore

final class PDFStackingOrderTests: XCTestCase {
    private func picture(_ name: String) -> PDFStackingEntry { .object(.picture, name: name) }
    private func textBox(_ name: String) -> PDFStackingEntry { .object(.textBox, name: name) }
    private func shape(_ name: String) -> PDFStackingEntry { .object(.shape, name: name) }

    /// The names of the page's layers, the lowest first, "ink" for the ink.
    private func names(_ layers: [PDFStackingOrder.Layer]?, in order: PDFStackingOrder) -> [String]? {
        layers?.map { layer in
            switch layer {
            case .ink: return "ink"
            case .object(let annotationIndex):
                guard case .object(_, let name) = order.entries[annotationIndex] else { return "?" }
                return name ?? "unnamed"
            }
        }
    }

    private func arranged(_ entries: [PDFStackingEntry], moving annotationIndex: Int, _ arrangement: PDFArrangement) -> [String]? {
        let order = PDFStackingOrder(entries: entries)
        guard let layer = order.layer(ofObjectAt: annotationIndex) else { return nil }
        return names(order.arranged(layer, arrangement), in: order)
    }

    /// Two pictures under the ink and a text box over it, as Graphite places them.
    private let usualPage: [PDFStackingEntry] = [.fixed, .object(.picture, name: "P1"), .object(.picture, name: "P2"), .ink, .ink,
                                                 .object(.textBox, name: "T"), .attached(ownerName: "T")]

    func testTheLayersAreTheObjectsAndTheInkAsOneLayerInThePagesOrder() {
        let order = PDFStackingOrder(entries: usualPage)
        XCTAssertEqual(names(order.layers, in: order), ["P1", "P2", "ink", "T"])
        XCTAssertEqual(order.annotationIndices(of: .ink), [3, 4])
        XCTAssertEqual(order.annotationIndices(of: .object(annotationIndex: 5)), [5, 6], "A text box's links go with it.")
        XCTAssertNil(order.layer(ofObjectAt: 0), "Another application's annotation is not arranged.")
        XCTAssertEqual(order.inkPosition, 2)
    }

    func testPicturesArrangedAmongThemselvesStayUnderTheInk() {
        XCTAssertEqual(arranged(usualPage, moving: 1, .bringToFront), ["P2", "ink", "T", "P1"],
                       "Bring to Front puts the picture over the topmost object, the text box over the ink.")
        XCTAssertEqual(arranged(usualPage, moving: 1, .bringForward), ["P2", "P1", "ink", "T"], "Passing a picture under the ink keeps it under the ink.")
        XCTAssertEqual(arranged(usualPage, moving: 2, .sendToBack), ["P2", "P1", "ink", "T"])
        XCTAssertEqual(arranged(usualPage, moving: 2, .sendBackward), ["P2", "P1", "ink", "T"])
    }

    func testAnObjectGoesOverOrUnderTheInkOnlyToPassAnObjectOnTheOtherSide() {
        XCTAssertEqual(arranged(usualPage, moving: 2, .bringForward), ["P1", "ink", "T", "P2"])
        XCTAssertEqual(arranged(usualPage, moving: 5, .sendBackward), ["P1", "T", "P2", "ink"])
        XCTAssertEqual(arranged(usualPage, moving: 5, .sendToBack), ["T", "P1", "P2", "ink"])
    }

    func testAnObjectAlreadyAtTheFrontOrBackStaysWhereItIs() {
        XCTAssertNil(arranged(usualPage, moving: 5, .bringToFront))
        XCTAssertNil(arranged(usualPage, moving: 5, .bringForward), "The ink alone is not a step.")
        XCTAssertNil(arranged(usualPage, moving: 1, .sendToBack))
        XCTAssertNil(arranged(usualPage, moving: 1, .sendBackward))
        XCTAssertNil(arranged([picture("P"), .ink], moving: 0, .bringToFront), "A single object has nothing to pass.")
    }

    func testAPositionPutsALayerBackWhereItWas() {
        let order = PDFStackingOrder(entries: usualPage)
        XCTAssertEqual(names(order.arranged(.object(annotationIndex: 5), .position(0)), in: order), ["T", "P1", "P2", "ink"])
        XCTAssertEqual(names(order.arranged(.object(annotationIndex: 1), .position(99)), in: order), ["P2", "ink", "T", "P1"])
        XCTAssertNil(order.arranged(.object(annotationIndex: 2), .position(1)))
    }

    func testTheInkAsALayerGoesOverOrUnderEveryObject() {
        let order = PDFStackingOrder(entries: usualPage)
        XCTAssertEqual(names(order.arranged(.ink, .bringToFront), in: order), ["P1", "P2", "T", "ink"])
        XCTAssertEqual(names(order.arranged(.ink, .sendToBack), in: order), ["ink", "P1", "P2", "T"])
        XCTAssertNil(order.arranged(.ink, .bringForward))
    }

    func testAChangeKeepsTheLongestStartAlreadyInOrderAndNeverTakesOffFixedAnnotations() {
        let entries: [PDFStackingEntry] = [picture("P1"), .fixed, picture("P2"), .ink, .fixed, textBox("T"), .attached(ownerName: "T"), shape("S")]
        let order = PDFStackingOrder(entries: entries)
        // P1 over the text box: P2 and the ink stay, the text box and the shape are added back after it.
        let newOrder = order.arranged(.object(annotationIndex: 0), .bringForward)
        XCTAssertEqual(names(newOrder, in: order), ["P2", "P1", "ink", "T", "S"])
        XCTAssertEqual(newOrder.map(order.change(to:))?.annotationIndicesAddedBack, [0, 3, 5, 6, 7],
                       "P1 and every layer after it go back; P2 stays; fixed annotations stay.")
        let frontOrder = order.arranged(.object(annotationIndex: 5), .bringToFront)
        XCTAssertEqual(frontOrder.map(order.change(to:))?.annotationIndicesAddedBack, [5, 6], "Only the text box and its link move.")
    }

    func testNewStrokesGoUnderTheObjectsOverTheInk() {
        let order = PDFStackingOrder(entries: [picture("P1"), .ink, picture("P2"), .fixed, textBox("T"), .attached(ownerName: "T")])
        XCTAssertEqual(order.annotationIndicesOverInk, [2, 4, 5])
        XCTAssertEqual(PDFStackingOrder(entries: usualPage).annotationIndicesOverInk, [5, 6])
    }

    func testOnAPageWithoutInkTheFirstStrokeGoesUnderTheTopRunOfTextBoxes() {
        let order = PDFStackingOrder(entries: [picture("P1"), textBox("T1"), shape("S"), textBox("T2"), .attached(ownerName: "T2"), .fixed, textBox("T3")])
        XCTAssertFalse(order.hasInk)
        XCTAssertEqual(order.inkPosition, 3)
        XCTAssertEqual(order.annotationIndicesOverInk, [3, 4, 6])
        XCTAssertEqual(PDFStackingOrder(entries: [textBox("T"), picture("P")]).annotationIndicesOverInk, [], "A picture on top is under the first stroke.")
    }

    func testANewPictureGoesRightUnderTheInk() {
        // The picture was just added on top; it goes where the ink was before it.
        let order = PDFStackingOrder(entries: usualPage + [picture("New")])
        let placed = order.placingTopLayer(at: PDFStackingOrder(entries: usualPage).inkPosition)
        XCTAssertEqual(names(placed, in: order), ["P1", "P2", "New", "ink", "T"])
    }

    func testAnUnnamedShapeIsArrangedByItsPlaceAndLinksWithoutABoxAreFixed() {
        let entries: [PDFStackingEntry] = [.object(.shape, name: nil), .attached(ownerName: "Gone"), shape("S")]
        let order = PDFStackingOrder(entries: entries)
        XCTAssertEqual(names(order.layers, in: order), ["unnamed", "S"])
        XCTAssertEqual(names(order.arranged(.object(annotationIndex: 0), .bringToFront), in: order), ["S", "unnamed"])
        XCTAssertEqual(order.change(to: [.object(annotationIndex: 2), .object(annotationIndex: 0)]).annotationIndicesAddedBack, [0])
    }
}
