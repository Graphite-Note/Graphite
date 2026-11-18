/**
 * File: PDFStackingOrderSessionTests.swift
 * ----------------------------------------
 * Layer: Tests
 * Description: Arranging a PDF page's pictures, text boxes and shapes through the session, one or several together:
 *              each arrangement is one step of the PDF's history, a deleted object comes back at its place, and the
 *              saved file keeps the order.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 16/11/2026
 */
import XCTest
import PDFKit
import GraphiteCore
import GraphiteApple
@testable import GraphiteUI
import GraphiteTestSupport

@MainActor
final class PDFStackingOrderSessionTests: XCTestCase {
    private var directory: URL!

    override func setUp() async throws {
        directory = try TemporaryVault.make(prefix: "PDFStackingOrder", for: self).root
    }

    private func openSession() async throws -> (PDFSession, URL) {
        let location = directory.appendingPathComponent("Notebook-\(UUID().uuidString).pdf")
        var mediaBox = CGRect(x: 0, y: 0, width: 400, height: 600)
        let context = try XCTUnwrap(CGContext(location as CFURL, mediaBox: &mediaBox, nil))
        context.beginPDFPage(nil)
        context.endPDFPage()
        context.closePDF()
        let session = try await PDFSession.open(location)
        session.undoManager.groupsByEvent = false
        return (session, location)
    }

    private func step(in session: PDFSession, _ operation: () async throws -> Void) async rethrows {
        session.undoManager.beginUndoGrouping()
        defer { session.undoManager.endUndoGrouping() }
        try await operation()
    }

    private func imageData() throws -> Data {
        let context = try XCTUnwrap(CGContext(data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB)), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(srgbRed: 0, green: 0.5, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        return try ImageEncoding.pngData(from: try XCTUnwrap(context.makeImage()))
    }

    private func names(on page: PDFPage) -> [String] {
        page.annotations.compactMap { annotation in PDFPageManager.isPicture(annotation) || PDFShape.isShape(annotation)
            || annotation.type == PDFTextBox.annotationTypeName ? annotation.persistentName : nil }
    }

    /// A page with a picture, a text box over it and a shape over both, as each is placed.
    private func pageWithThreeObjects(in session: PDFSession) async throws -> (page: PDFPage, picture: String, box: PDFTextBox, shape: PDFShape) {
        try await step(in: session) { try await session.addPicture(imageData: try imageData()) }
        let page = try XCTUnwrap(session.document.page(at: 0))
        let pictureName = try XCTUnwrap(session.pictures(on: page).first?.name)
        let box = PDFTextBox(name: "box-1", runs: [PDFTextRun(text: "Over the picture", attributes: .plain)], origin: CGPoint(x: 150, y: 320), width: 120,
                             height: 30, rotationRadians: 0, style: PDFTextBoxDefaults.original.boxStyle)
        try await step(in: session) { try session.changeTextBox(from: nil, to: box, on: session.historyPage(for: page), actionName: "Add Text Box") }
        let shape = PDFShape(name: "shape-1", kind: .oval, start: CGPoint(x: 140, y: 280), end: CGPoint(x: 260, y: 340),
                             borderColor: PDFTextColor(red: 1, green: 0, blue: 0), lineWidth: 2)
        try await step(in: session) { try session.addShape(shape, on: page) }
        return (page, pictureName, box, shape)
    }

    func testEachArrangementIsOneStepThatUndoTakesBack() async throws {
        let (session, location) = try await openSession()
        let (page, pictureName, box, shape) = try await pageWithThreeObjects(in: session)
        XCTAssertEqual(names(on: page), [pictureName, box.name, shape.name])

        session.textBoxActivity = .selected(PDFTextBoxSelection(boxName: box.name, page: session.historyPage(for: page)))
        XCTAssertEqual(session.possibleArrangementsOfSelectedTextBox, [.bringToFront, .bringForward, .sendBackward, .sendToBack])
        try await step(in: session) { try session.arrangeSelectedTextBox(.bringToFront) }
        XCTAssertEqual(names(on: page), [pictureName, shape.name, box.name])
        XCTAssertEqual(session.undoAvailability.undoActionName, "Bring to Front")
        XCTAssertEqual(session.possibleArrangementsOfSelectedTextBox, [.sendBackward, .sendToBack])

        let shapeAnnotation = try XCTUnwrap(session.shapeAnnotation(named: shape.name, on: page))
        try await step(in: session) { try session.arrange(shapeAnnotation, on: page, .sendToBack) }
        XCTAssertEqual(names(on: page), [shape.name, pictureName, box.name])
        XCTAssertEqual(session.undoAvailability.undoActionName, "Send to Back")

        let picture = PDFPictureSelection(pictureName: pictureName, page: session.historyPage(for: page))
        try await step(in: session) { try session.arrangePicture(picture, .bringForward) }
        XCTAssertEqual(names(on: page), [shape.name, box.name, pictureName])

        session.undoAvailability.undo()
        XCTAssertEqual(names(on: page), [shape.name, pictureName, box.name])
        session.undoAvailability.undo()
        XCTAssertEqual(names(on: page), [pictureName, shape.name, box.name])
        session.undoAvailability.undo()
        XCTAssertEqual(names(on: page), [pictureName, box.name, shape.name])
        session.undoAvailability.redo()
        XCTAssertEqual(names(on: page), [pictureName, shape.name, box.name])

        try await session.save()
        XCTAssertEqual(names(on: try XCTUnwrap(PDFDocument(url: location)?.page(at: 0))), [pictureName, shape.name, box.name],
                       "The saved file has the order shown, as every reader draws it.")
    }

    func testAnArrangementThatWouldNotMoveTheObjectAddsNoStep() async throws {
        let (session, _) = try await openSession()
        let (page, pictureName, box, shape) = try await pageWithThreeObjects(in: session)
        let boxAnnotation = try XCTUnwrap(page.annotations.first { annotation in annotation.persistentName == box.name })
        try await step(in: session) { try session.arrange(boxAnnotation, on: page, .bringForward) }
        XCTAssertEqual(session.undoAvailability.undoActionName, "Bring Forward")
        // On top already: nothing moves, and no step is added.
        try session.arrange(boxAnnotation, on: page, .bringForward)
        XCTAssertEqual(session.undoAvailability.undoActionName, "Bring Forward")
        session.undoAvailability.undo()
        XCTAssertEqual(names(on: page), [pictureName, box.name, shape.name], "One undo takes back the one move.")
        XCTAssertEqual(session.undoAvailability.undoActionName, "Add Oval")
    }

    func testADeletedObjectComesBackAtItsPlaceWhenUndone() async throws {
        let (session, _) = try await openSession()
        let (page, pictureName, box, shape) = try await pageWithThreeObjects(in: session)
        let picture = PDFPictureSelection(pictureName: pictureName, page: session.historyPage(for: page))
        try await step(in: session) { try session.arrangePicture(picture, .bringToFront) }
        XCTAssertEqual(names(on: page), [box.name, shape.name, pictureName])

        try await step(in: session) { try session.removePicture(picture) }
        session.textBoxActivity = .selected(PDFTextBoxSelection(boxName: box.name, page: session.historyPage(for: page)))
        try await step(in: session) { try session.deleteSelectedTextBox() }
        let shapeAnnotation = try XCTUnwrap(session.shapeAnnotation(named: shape.name, on: page))
        try await step(in: session) { try session.changeShape(shapeAnnotation, on: page, to: nil, actionName: "Delete Shape") }
        XCTAssertEqual(names(on: page), [])

        session.undoAvailability.undo()
        session.undoAvailability.undo()
        session.undoAvailability.undo()
        XCTAssertEqual(names(on: page), [box.name, shape.name, pictureName], "Each comes back where it was, not where a new one goes.")
    }

    func testInkToFrontAndBackIsOneStepThatUndoTakesBack() async throws {
        let (session, location) = try await openSession()
        let (page, pictureName, box, shape) = try await pageWithThreeObjects(in: session)
        let stroke = PortableInkStroke(name: "ink-1", segments: [[CGPoint(x: 100, y: 300), CGPoint(x: 300, y: 300)]], width: 3, red: 0, green: 0, blue: 0,
                                       alpha: 1, outline: nil)
        try session.apply(.updateInk(PDFInkUpdate(pageIndex: 0, group: PDFInkGroups.defaultGroup, removal: .strokes([]), addedStrokes: [stroke],
                                                  editableRecord: nil)))
        func layerNames() -> [String] {
            page.annotations.compactMap { annotation in
                annotation.value(forAnnotationKey: PDFPageManager.groupKey) != nil ? "ink" : names(on: page).contains(annotation.persistentName ?? "")
                    ? annotation.persistentName : nil
            }
        }
        // On a page without ink and no text box on top, the first stroke goes over every object.
        XCTAssertEqual(layerNames(), [pictureName, box.name, shape.name, "ink"])
        XCTAssertEqual(session.possibleInkArrangements(on: page), [.sendToBack])

        try await step(in: session) { try session.arrangeInk(on: page, .sendToBack) }
        XCTAssertEqual(layerNames(), ["ink", pictureName, box.name, shape.name])
        XCTAssertEqual(session.undoAvailability.undoActionName, "Ink to Back")
        XCTAssertEqual(session.possibleInkArrangements(on: page), [.bringToFront])
        try await step(in: session) { try session.arrangeInk(on: page, .bringToFront) }
        XCTAssertEqual(layerNames(), [pictureName, box.name, shape.name, "ink"])

        session.undoAvailability.undo()
        XCTAssertEqual(layerNames(), ["ink", pictureName, box.name, shape.name])
        session.undoAvailability.undo()
        XCTAssertEqual(layerNames(), [pictureName, box.name, shape.name, "ink"])
        session.undoAvailability.redo()
        try await session.save()
        let saved = try XCTUnwrap(PDFDocument(url: location)?.page(at: 0))
        XCTAssertNotNil(saved.annotations.first?.value(forAnnotationKey: PDFPageManager.groupKey), "The saved file has the ink under every object.")
    }

    func testSeveralObjectsArrangedTogetherAreOneStepThatUndoTakesBack() async throws {
        let (session, location) = try await openSession()
        let (page, pictureName, box, shape) = try await pageWithThreeObjects(in: session)
        let pictureAnnotation = try XCTUnwrap(page.annotations.first { annotation in annotation.persistentName == pictureName })
        let boxAnnotation = try XCTUnwrap(page.annotations.first { annotation in annotation.persistentName == box.name })
        let otherApplicationsNote = PDFAnnotation(bounds: CGRect(x: 10, y: 10, width: 20, height: 20), forType: .text, withProperties: nil)
        page.addAnnotation(otherApplicationsNote)
        let selection = [boxAnnotation, otherApplicationsNote, pictureAnnotation]
        XCTAssertEqual(session.possibleArrangements(of: selection, on: page), [.bringToFront, .bringForward],
                       "Under the shape, the two can only go up; the note is not an object and is left out.")

        try await step(in: session) { try session.arrange(selection, on: page, .bringToFront) }
        XCTAssertEqual(names(on: page), [shape.name, pictureName, box.name], "Both over the shape, the picture still under the box.")
        XCTAssertEqual(session.undoAvailability.undoActionName, "Bring Items to Front")
        XCTAssertEqual(session.possibleArrangements(of: selection, on: page), [.sendBackward, .sendToBack])
        // Nothing would move: no step.
        try session.arrange(selection, on: page, .bringForward)
        XCTAssertEqual(session.undoAvailability.undoActionName, "Bring Items to Front")

        session.undoAvailability.undo()
        XCTAssertEqual(names(on: page), [pictureName, box.name, shape.name], "One Undo puts both back.")
        XCTAssertEqual(session.undoAvailability.undoActionName, "Add Oval")
        session.undoAvailability.redo()
        XCTAssertEqual(names(on: page), [shape.name, pictureName, box.name])
        XCTAssertTrue(page.annotations.contains { annotation in annotation === otherApplicationsNote }, "The note stays on the page.")

        try await session.save()
        XCTAssertEqual(names(on: try XCTUnwrap(PDFDocument(url: location)?.page(at: 0))), [shape.name, pictureName, box.name])
    }

    func testTheMenusNameWhatTheyArrange() {
        XCTAssertEqual(PDFArrangement.menuArrangements.map { arrangement in arrangement.title(of: .image) },
                       ["Bring Image to Front", "Bring Image Forward", "Send Image Backward", "Send Image to Back"])
        XCTAssertEqual(PDFArrangement.menuArrangements.map { arrangement in arrangement.title(of: .item) },
                       ["Bring Item to Front", "Bring Item Forward", "Send Item Backward", "Send Item to Back"])
        XCTAssertEqual(PDFArrangement.menuArrangements.map(\.itemsTitle),
                       ["Bring Items to Front", "Bring Items Forward", "Send Items Backward", "Send Items to Back"])
        // A selection is named for what is in it.
        XCTAssertEqual(PDFArrangement.Objects.naming(pictureCount: 1, otherObjectCount: 0), .image)
        XCTAssertEqual(PDFArrangement.Objects.naming(pictureCount: 0, otherObjectCount: 1), .item)
        XCTAssertEqual(PDFArrangement.Objects.naming(pictureCount: 2, otherObjectCount: 0), .items)
        XCTAssertEqual(PDFArrangement.Objects.naming(pictureCount: 1, otherObjectCount: 1), .items)
    }
}
