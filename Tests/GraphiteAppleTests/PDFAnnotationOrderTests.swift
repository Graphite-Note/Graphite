/**
 * File: PDFAnnotationOrderTests.swift
 * -----------------------------------
 * Layer: Apple tests
 * Description: The stacking order of a page's annotations in the saved file (invariant M-15): pictures, text boxes
 *              and shapes arranged in any order, the ink as one layer, objects kept in place when changed, and
 *              another application's annotations left where they are.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 16/11/2026
 */
import XCTest
import PDFKit
import CoreGraphics
import GraphiteCore
@testable import GraphiteApple

/// The stacking order of a page's annotations in the saved file, which every reader (Preview,
/// Acrobat, Files) draws in that order: Graphite's ink stays over the pictures arranged among
/// themselves, objects go over or under each other in any order, and nothing of another
/// application moves.
final class PDFAnnotationOrderTests: XCTestCase {
    private typealias Documents = PDFTextBoxTestDocuments

    private func pictureData() throws -> Data {
        let context = try XCTUnwrap(CGContext(data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB)), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        return try ImageEncoding.pngData(from: try XCTUnwrap(context.makeImage()))
    }

    private func picture(_ name: String, x: Double = 20) throws -> PDFPicture {
        PDFPicture(name: name, imageData: try pictureData(), bounds: CGRect(x: x, y: 150, width: 100, height: 50), quarterTurns: 0)
    }

    private func stroke(named name: String, atHeight height: Double) -> PortableInkStroke {
        PortableInkStroke(name: name, segments: [[CGPoint(x: 20, y: height), CGPoint(x: 120, y: height)]], width: 2, red: 0, green: 0, blue: 0, alpha: 1, outline: nil)
    }

    private func addingStroke(_ name: String) -> PDFEdit {
        .updateInk(PDFInkUpdate(pageIndex: 0, group: PDFInkGroups.defaultGroup, removal: .strokes([]), addedStrokes: [stroke(named: name, atHeight: 100)],
                                editableRecord: nil, defersEditableRecord: true))
    }

    private let shape = PDFShape(name: "shape-1", kind: .rectangle, start: CGPoint(x: 30, y: 140), end: CGPoint(x: 90, y: 220),
                                 borderColor: PDFTextColor(red: 1, green: 0, blue: 0), lineWidth: 2)

    private func shapeReference(_ shape: PDFShape) -> PDFAnnotationReference {
        PDFAnnotationReference(pageIndex: 0, name: shape.name, annotationType: shape.kind.annotationTypeName, bounds: shape.bounds)
    }

    /// A page with, in this order: Graphite's ink A and B, another application's stamp, and
    /// another application's link.
    private func pageWithInkAndForeignAnnotations() throws -> PDFDocument {
        let document = try XCTUnwrap(PDFDocument(data: PDFTemplateGenerator.documentData(paper: PaperSpecification(template: .blank))))
        let update = PDFInkUpdate(pageIndex: 0, group: PDFInkGroups.defaultGroup, removal: .strokes([]),
                                  addedStrokes: [stroke(named: "ink-A", atHeight: 100), stroke(named: "ink-B", atHeight: 200)], editableRecord: nil)
        try PDFPageManager.apply(.updateInk(update), to: document)
        let page = try XCTUnwrap(document.page(at: 0))
        let foreignStamp = PDFAnnotation(bounds: CGRect(x: 300, y: 300, width: 40, height: 40), forType: .stamp, withProperties: nil)
        foreignStamp.setValue("foreign-stamp", forAnnotationKey: .name)
        page.addAnnotation(foreignStamp)
        let foreignLink = PDFAnnotation(bounds: CGRect(x: 300, y: 400, width: 40, height: 40), forType: .link, withProperties: nil)
        foreignLink.setValue("foreign-link", forAnnotationKey: .name)
        page.addAnnotation(foreignLink)
        return document
    }

    private func names(of page: PDFPage) -> [String] {
        page.annotations.map { annotation in annotation.persistentName ?? "(\(annotation.type ?? "?"))" }
    }

    private func savedOrder(of document: PDFDocument, edits: [PDFEdit]) throws -> [String] {
        try PDFPageManager.replay(edits, on: document)
        return names(of: try XCTUnwrap(PDFDocument(data: XCTUnwrap(document.dataRepresentation()))?.page(at: 0)))
    }

    /// The order of the file saving writes from these edits, as another reader opens it.
    private func savedOrder(applying edits: [PDFEdit]) throws -> [String] {
        names(of: try XCTUnwrap(PDFDocument(data: Documents.savedData(applying: edits))?.page(at: 0)))
    }

    func testAPictureIsPlacedBelowTheInkAndBesideTheForeignAnnotationsInTheSavedFile() throws {
        let order = try savedOrder(of: pageWithInkAndForeignAnnotations(), edits: [.addPicture(page: 0, picture: picture("picture-1"))])
        XCTAssertEqual(order, ["foreign-stamp", "foreign-link", "picture-1", "ink-A", "ink-B"])
    }

    func testPicturesArrangedAmongThemselvesStayUnderTheInkAndForeignAnnotationsStay() throws {
        let first = try picture("picture-1"), second = try picture("picture-2", x: 60)
        let document = try pageWithInkAndForeignAnnotations()
        let edits: [PDFEdit] = [.addPicture(page: 0, picture: first), .addPicture(page: 0, picture: second), .arrange(first.reference(onPageAt: 0), .bringToFront)]
        XCTAssertEqual(try savedOrder(of: document, edits: edits), ["foreign-stamp", "foreign-link", "picture-2", "picture-1", "ink-A", "ink-B"])
        let reopened = try XCTUnwrap(PDFDocument(data: XCTUnwrap(document.dataRepresentation())))
        XCTAssertEqual(try savedOrder(of: reopened, edits: [.arrange(first.reference(onPageAt: 0), .sendToBack)]),
                       ["foreign-stamp", "foreign-link", "picture-1", "picture-2", "ink-A", "ink-B"])
    }

    func testEveryArrangementOfAPictureATextBoxAndAShapeIsTheSavedAnnotationOrder() throws {
        let picture = try picture("picture-1")
        let box = Documents.sampleBox(name: "box-1", link: URL(string: "https://example.com"))
        let placed: [PDFEdit] = [.addPicture(page: 0, picture: picture), addingStroke("ink-A"), .addTextBox(page: 0, textBox: box), .addShape(page: 0, shape: shape)]
        XCTAssertEqual(try savedOrder(applying: placed), ["picture-1", "ink-A", "box-1", "box-1-link-1", "shape-1"])

        // The picture passes the box, over the ink.
        let forward = placed + [.arrange(picture.reference(onPageAt: 0), .bringForward)]
        XCTAssertEqual(try savedOrder(applying: forward), ["ink-A", "box-1", "box-1-link-1", "picture-1", "shape-1"])
        // The shape goes under the lowest object, the box: still over the ink.
        let back = forward + [.arrange(shapeReference(shape), .sendToBack)]
        XCTAssertEqual(try savedOrder(applying: back), ["ink-A", "shape-1", "box-1", "box-1-link-1", "picture-1"])
        let front = back + [.arrange(box.reference(onPageAt: 0), .bringToFront)]
        XCTAssertEqual(try savedOrder(applying: front), ["ink-A", "shape-1", "picture-1", "box-1", "box-1-link-1"])
        let backward = front + [.arrange(box.reference(onPageAt: 0), .sendBackward)]
        XCTAssertEqual(try savedOrder(applying: backward), ["ink-A", "shape-1", "box-1", "box-1-link-1", "picture-1"])
        // Put back where it was, as Undo does.
        let putBack = backward + [.arrange(picture.reference(onPageAt: 0), .position(0))]
        XCTAssertEqual(try savedOrder(applying: putBack), ["picture-1", "ink-A", "shape-1", "box-1", "box-1-link-1"])
    }

    func testTheSavedOrderIsTheShownOrderAfterReopening() throws {
        let picture = try picture("picture-1")
        let box = Documents.sampleBox(name: "box-1")
        let saved = try Documents.savedData(applying: [.addPicture(page: 0, picture: picture), addingStroke("ink-A"), .addTextBox(page: 0, textBox: box),
                                                       .arrange(picture.reference(onPageAt: 0), .bringToFront)])
        let reopened = try Documents.shownDocument(from: saved)
        let page = try XCTUnwrap(reopened.page(at: 0))
        XCTAssertEqual(names(of: page), ["ink-A", "box-1", "picture-1"])
        XCTAssertEqual(PDFPageManager.objectAnnotationsTopmostFirst(on: page).map(\.persistentName), ["picture-1", "box-1"])
        // Reopened, the picture is arranged again from where the file put it: under the box,
        // the lowest object, and so still over the ink, which it passes only to pass an object.
        try PDFPageManager.apply(.arrange(picture.reference(onPageAt: 0), .sendToBack), to: reopened)
        XCTAssertEqual(names(of: page), ["ink-A", "picture-1", "box-1"])
    }

    func testMovingOrChangingAnObjectKeepsItsPlace() throws {
        let first = try picture("picture-1"), second = try picture("picture-2", x: 60)
        let box = Documents.sampleBox(name: "box-1")
        var movedBox = box
        movedBox.origin = CGPoint(x: box.origin.x + 30, y: box.origin.y - 20)
        let reshaped = shape.moved(by: CGVector(dx: 15, dy: 15))
        let edits: [PDFEdit] = [
            .addPicture(page: 0, picture: first), .addPicture(page: 0, picture: second), addingStroke("ink-A"), .addTextBox(page: 0, textBox: box),
            .addShape(page: 0, shape: shape), .arrange(shapeReference(shape), .sendToBack),
            .movePicture(first.reference(onPageAt: 0), to: CGRect(x: 200, y: 300, width: 80, height: 40)),
            .replaceTextBox(box.reference(onPageAt: 0), with: movedBox),
            .replaceShape(shapeReference(shape), with: reshaped),
        ]
        XCTAssertEqual(try savedOrder(applying: edits), ["shape-1", "picture-1", "picture-2", "ink-A", "box-1"],
                       "Moving the lower picture, the box or the shape leaves each where it was in the stack.")
    }

    func testNewStrokesGoUnderTheObjectsOverTheInk() throws {
        let picture = try picture("picture-1")
        let box = Documents.sampleBox(name: "box-1")
        let edits: [PDFEdit] = [.addPicture(page: 0, picture: picture), addingStroke("ink-A"), .addTextBox(page: 0, textBox: box),
                                .arrange(picture.reference(onPageAt: 0), .bringToFront), addingStroke("ink-B")]
        XCTAssertEqual(try savedOrder(applying: edits), ["ink-A", "ink-B", "box-1", "picture-1"])
        // A group written again, as erasing part of a stroke does, keeps its place under them.
        let rewritten = PDFEdit.updateInk(PDFInkUpdate(pageIndex: 0, group: PDFInkGroups.defaultGroup, removal: .entireGroup,
                                                       addedStrokes: [stroke(named: "ink-C", atHeight: 120)], editableRecord: nil))
        XCTAssertEqual(try savedOrder(applying: edits + [rewritten]), ["ink-C", "box-1", "picture-1"])
    }

    func testTheInkMovesAsOneLayerOverOrUnderEveryObject() throws {
        let picture = try picture("picture-1")
        let box = Documents.sampleBox(name: "box-1")
        let placed: [PDFEdit] = [addingStroke("ink-A"), .addPicture(page: 0, picture: picture), addingStroke("ink-B"), .addTextBox(page: 0, textBox: box)]
        XCTAssertEqual(try savedOrder(applying: placed + [.arrangeInk(page: 0, .bringToFront)]), ["picture-1", "box-1", "ink-A", "ink-B"])
        XCTAssertEqual(try savedOrder(applying: placed + [.arrangeInk(page: 0, .sendToBack)]), ["ink-A", "ink-B", "picture-1", "box-1"])
    }

    func testAnotherApplicationsAnnotationsAreNeverTakenOffTheirPage() throws {
        let document = try pageWithInkAndForeignAnnotations()
        let page = try XCTUnwrap(document.page(at: 0))
        let foreignAnnotations = page.annotations.filter { annotation in annotation.persistentName?.hasPrefix("foreign") == true }
        let first = try picture("picture-1"), second = try picture("picture-2", x: 60)
        let box = Documents.sampleBox(name: "box-1")
        try PDFPageManager.replay([.addPicture(page: 0, picture: first), .addTextBox(page: 0, textBox: box), .addPicture(page: 0, picture: second),
                                   .arrange(first.reference(onPageAt: 0), .bringToFront), .arrange(box.reference(onPageAt: 0), .sendToBack)], on: document)
        let kept = page.annotations.filter { annotation in annotation.persistentName?.hasPrefix("foreign") == true }
        XCTAssertEqual(kept.count, 2)
        XCTAssertTrue(zip(kept, foreignAnnotations).allSatisfy { keptAnnotation, foreignAnnotation in keptAnnotation === foreignAnnotation },
                      "The same annotations, in the same order: never taken off and added again.")
        XCTAssertEqual(names(of: page), ["foreign-stamp", "foreign-link", "box-1", "picture-2", "ink-A", "ink-B", "picture-1"])
    }

    func testAnObjectThatIsGoneCannotBeArranged() throws {
        let document = try pageWithInkAndForeignAnnotations()
        XCTAssertThrowsError(try PDFPageManager.apply(.arrange(PDFAnnotationReference(pageIndex: 0, name: "gone", annotationType: "Stamp", bounds: .zero),
                                                               .bringToFront), to: document))
        // Another application's stamp is not one of the objects Graphite arranges.
        XCTAssertThrowsError(try PDFPageManager.apply(.arrange(PDFAnnotationReference(pageIndex: 0, name: "foreign-stamp", annotationType: "Stamp",
                                                                                     bounds: CGRect(x: 300, y: 300, width: 40, height: 40)),
                                                               .bringToFront), to: document))
    }
}
