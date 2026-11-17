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

    // MARK: Several objects together (Docs/PDF-annotation-todo.md, section 8)

    private func arranged(_ entries: [PDFStackingEntry], together annotationIndices: [Int], _ arrangement: PDFArrangement) -> [String]? {
        let order = PDFStackingOrder(entries: entries)
        let group = Set(annotationIndices.compactMap(order.layer(ofObjectAt:)))
        return names(order.arranged(together: group, arrangement), in: order)
    }

    /// Two pictures under the ink, a text box and a shape over it.
    private let pageWithFourObjects: [PDFStackingEntry] = [.object(.picture, name: "P1"), .object(.picture, name: "P2"), .ink, .object(.textBox, name: "T"),
                                                           .attached(ownerName: "T"), .object(.shape, name: "S")]

    func testObjectsArrangedTogetherKeepTheirOrderAmongThemselves() {
        XCTAssertEqual(arranged(pageWithFourObjects, together: [0, 3], .bringToFront), ["P2", "ink", "S", "P1", "T"],
                       "Both go right over the topmost other object, the lower one under the higher.")
        XCTAssertEqual(arranged(pageWithFourObjects, together: [1, 3], .sendToBack), ["P2", "T", "P1", "ink", "S"],
                       "Both go right under the lowest other object, the lower one under the higher.")
        let pictures: [PDFStackingEntry] = [picture("A"), picture("X"), picture("B"), picture("Y")]
        XCTAssertEqual(arranged(pictures, together: [0, 2], .bringForward), ["X", "A", "Y", "B"], "Each passes the next object outside the group.")
        XCTAssertEqual(arranged(pictures, together: [1, 3], .sendBackward), ["X", "A", "Y", "B"])
    }

    func testObjectsArrangedTogetherPassTheInkOnlyToPassAnObjectOnTheOtherSide() {
        XCTAssertEqual(arranged(pageWithFourObjects, together: [0, 1], .bringForward), ["ink", "T", "P1", "P2", "S"],
                       "Both pictures pass the text box, so they go over the ink.")
        XCTAssertEqual(arranged([picture("P1"), picture("P2"), picture("P3"), .ink, textBox("T")], together: [0, 1], .bringForward),
                       ["P3", "P1", "P2", "ink", "T"], "Passing a picture under the ink keeps them under it.")
    }

    func testObjectsArrangedTogetherThatWouldNotMoveStayWhereTheyAre() {
        XCTAssertNil(arranged(pageWithFourObjects, together: [3, 5], .bringToFront), "Already the topmost two.")
        XCTAssertNil(arranged(pageWithFourObjects, together: [3, 5], .bringForward))
        XCTAssertNil(arranged(pageWithFourObjects, together: [0, 1], .sendToBack), "Already the lowest two.")
        XCTAssertNil(arranged(pageWithFourObjects, together: [0, 1, 3, 5], .bringToFront), "With every object in the group, none is left to pass.")
        XCTAssertNil(arranged(pageWithFourObjects, together: [], .bringToFront))
        XCTAssertNil(arranged(pageWithFourObjects, together: [0, 3], .position(0)), "A group has no single place to go.")
        let order = PDFStackingOrder(entries: pageWithFourObjects)
        XCTAssertEqual(names(order.arranged(together: [.ink, .object(annotationIndex: 0)], .bringToFront), in: order), ["P2", "ink", "T", "S", "P1"],
                       "The ink is left out of a group.")
    }

    func testPlacingPutsLayersBackAtTheirFormerPlaces() throws {
        let order = PDFStackingOrder(entries: pageWithFourObjects)
        let arrangedLayers = try XCTUnwrap(order.arranged(together: [.object(annotationIndex: 1), .object(annotationIndex: 3)], .sendToBack))
        // The page as it is once arranged, then each layer put back where it was.
        let arrangedOrder = PDFStackingOrder(entries: arrangedLayers.flatMap { layer in order.annotationIndices(of: layer).map { index in pageWithFourObjects[index] } })
        XCTAssertEqual(names(arrangedOrder.layers, in: arrangedOrder), ["P2", "T", "P1", "ink", "S"])
        let placed = arrangedOrder.placing([(layer: .object(annotationIndex: 0), position: 1), (layer: .object(annotationIndex: 1), position: 3)])
        XCTAssertEqual(names(placed, in: arrangedOrder), ["P1", "P2", "ink", "T", "S"])
        XCTAssertNil(order.placing([(layer: .object(annotationIndex: 0), position: 0)]), "A layer already at its place moves nothing.")
    }
}
