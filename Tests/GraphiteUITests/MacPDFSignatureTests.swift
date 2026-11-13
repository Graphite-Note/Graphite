/**
 * File: MacPDFSignatureTests.swift
 * --------------------------------
 * Layer: Tests
 * Description: Signatures on the Mac: kept on the device and deleted, drawn in the sheet's canvas, placed on a page as
 *              the iPad's editable ink, and moved, resized and deleted by the Sign tool, each one step of the history.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 13/11/2026
 */

#if os(macOS)
import XCTest
import AppKit
import PDFKit
import PencilKit
import GraphiteCore
import GraphiteApple
@testable import GraphiteUI
import GraphiteTestSupport

@MainActor
final class MacPDFSignatureTests: XCTestCase {
    /// Opened before each test, whose body runs synchronously as AppKit's events do (see `MacPDFPageToolsTests`).
    private var openedHarness: MacPDFPageToolHarness?
    private var clockSeconds: TimeInterval = 1_000_000

    override func setUp() async throws {
        try await super.setUp()
        openedHarness = try await MacPDFPageToolHarness.open(for: self, prefix: "MacPDFSignature") { [unowned self] in
            clockSeconds += 1
            return Date(timeIntervalSince1970: clockSeconds)
        }
    }

    private func makeStore() throws -> PDFSignatureStore {
        PDFSignatureStore(directory: try TemporaryVault.make(prefix: "MacPDFSignatureStore", for: self).root.appendingPathComponent("Signatures"))
    }

    /// A signature of two strokes, 200 by 50 points, drawn somewhere in a canvas.
    private func signatureDrawing() throws -> PKDrawing {
        var signature = MacSignatureDrawing()
        signature.strokes = [
            (0...20).map { index in PDFPointerInkSample(pagePoint: CGPoint(x: 40 + Double(index) * 10, y: 60 + Double(index % 2) * 50), timeSeconds: Double(index) / 60) },
            [PDFPointerInkSample(pagePoint: CGPoint(x: 60, y: 40), timeSeconds: 0), PDFPointerInkSample(pagePoint: CGPoint(x: 220, y: 40), timeSeconds: 0.2)],
        ]
        return try XCTUnwrap(signature.drawing(inCanvasOf: MacPDFSignatureSheet.canvasSize, creationDate: Date(timeIntervalSince1970: 5)))
    }

    private func pageDrawing(of fixture: MacPDFPageToolHarness) throws -> PKDrawing {
        try XCTUnwrap(PDFSession.editableInk(on: fixture.page).drawing)
    }

    /// Places a saved signature through the row, as choosing it in the Sign menu does.
    private func placeSignature(in fixture: MacPDFPageToolHarness) throws -> CGRect {
        let saved = try makeStore().save(try signatureDrawing(), madeAt: Date())
        fixture.step {
            fixture.toolbar.placeSignature(saved)
            fixture.choose(fixture.toolbar.tool)
        }
        return try XCTUnwrap(fixture.tools?.signatures?.selectedFrame)
    }

    /// A page point from a point of the page's drawing space, whose vertical axis runs down.
    private func pagePoint(_ drawingPoint: CGPoint) -> CGPoint {
        CGPoint(x: drawingPoint.x, y: MacPDFPageToolHarness.pageSize.height - drawingPoint.y)
    }

    // MARK: Keeping signatures

    func testSignaturesAreKeptInTheirOrderOutsideTheVaultReadAgainAndDeleted() throws {
        let store = try makeStore()
        let first = try store.save(try signatureDrawing(), madeAt: Date(timeIntervalSince1970: 100))
        let second = try store.save(try signatureDrawing(), madeAt: Date(timeIntervalSince1970: 200))
        XCTAssertEqual(first.drawing.bounds.origin.x, 0, accuracy: 0.01, "A kept signature starts at its top-left corner.")
        XCTAssertEqual(first.drawing.bounds.origin.y, 0, accuracy: 0.01)
        try Data("not a drawing".utf8).write(to: store.directory.appendingPathComponent("0000-stray.signature"))

        let reopened = PDFSignatureStore(directory: store.directory)
        XCTAssertTrue(reopened.signatures.isEmpty, "Nothing is read before the Sign menu shows.")
        reopened.loadIfNeeded()
        XCTAssertEqual(reopened.signatures.map(\.id), [first.id, second.id], "In the order they were made; a file that is not a drawing is left out.")
        XCTAssertEqual(reopened.signatures.first?.drawing.strokes.count, 2)

        try reopened.delete(first)
        XCTAssertEqual(reopened.signatures.map(\.id), [second.id])
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.directory.appendingPathComponent(first.id).path))
        XCTAssertTrue(PDFSignatureStore.directory(in: ApplicationFolders(cachesFolder: nil, applicationSupportFolder: store.directory)).path.hasSuffix("/Signatures"))
    }

    func testTheSheetsCanvasDrawsFromItsTopLeftCornerAsPencilKitDoes() throws {
        let drawing = try signatureDrawing()
        // Drawn from 40 to 60 points above the canvas's bottom edge: 100 to 120 points below its top.
        XCTAssertEqual(drawing.strokes[1].renderBounds.midY, MacPDFSignatureSheet.canvasSize.height - 40, accuracy: 2)
        XCTAssertNil(MacSignatureDrawing().drawing(inCanvasOf: MacPDFSignatureSheet.canvasSize, creationDate: Date()), "Nothing drawn, nothing to keep.")
    }

    // MARK: The placement's frame

    func testASignatureIsPlacedAtItsWidthInsideThePageAndResizedKeepingItsProportions() {
        let frame = PDFSignatureInk.placedFrame(forSignatureOf: CGSize(width: 200, height: 50), centeredAt: CGPoint(x: 200, y: 300),
                                                pageSize: CGSize(width: 400, height: 600))
        XCTAssertEqual(frame, CGRect(x: 120, y: 280, width: 160, height: 40))
        let atTheEdge = PDFSignatureInk.placedFrame(forSignatureOf: CGSize(width: 200, height: 50), centeredAt: CGPoint(x: 395, y: 5),
                                                    pageSize: CGSize(width: 400, height: 600))
        XCTAssertEqual(atTheEdge, CGRect(x: 240, y: 0, width: 160, height: 40), "Kept inside the page.")
        let onANarrowPage = PDFSignatureInk.placedFrame(forSignatureOf: CGSize(width: 200, height: 50), centeredAt: CGPoint(x: 50, y: 50),
                                                        pageSize: CGSize(width: 100, height: 100))
        XCTAssertEqual(onANarrowPage.width, 100, accuracy: 0.01, "No wider than the page.")

        let resized = PDFSignatureInk.resized(frame, draggingCorner: .bottomRight, to: CGPoint(x: 440, y: 300))
        XCTAssertEqual(resized, CGRect(x: 120, y: 280, width: 320, height: 80), "The top-left corner stays; twice as wide is twice as tall.")
        let fromTheTopLeft = PDFSignatureInk.resized(frame, draggingCorner: .topLeft, to: CGPoint(x: 200, y: 310))
        XCTAssertEqual(fromTheTopLeft.maxX, frame.maxX, accuracy: 0.01)
        XCTAssertEqual(fromTheTopLeft.maxY, frame.maxY, accuracy: 0.01)
        XCTAssertEqual(fromTheTopLeft.width / fromTheTopLeft.height, 4, accuracy: 0.01)
        XCTAssertEqual(PDFSignatureInk.resized(frame, draggingCorner: .bottomRight, to: CGPoint(x: 121, y: 281)).width,
                       PDFSignatureInk.narrowestWidthPoints, accuracy: 0.01)
    }

    // MARK: The Sign tool

    func testAChosenSignatureIsPlacedAsTheIPadsEditableInkInOneStep() throws {
        let fixture = try XCTUnwrap(openedHarness)
        let frame = try placeSignature(in: fixture)
        XCTAssertEqual(fixture.tools?.tool, .sign)
        XCTAssertEqual(frame.width, PDFSignatureInk.placedWidthPoints, accuracy: 1)
        XCTAssertEqual(frame.midX, MacPDFPageToolHarness.pageSize.width / 2, accuracy: 2, "In the middle of the page in view.")
        let drawing = try pageDrawing(of: fixture)
        XCTAssertEqual(drawing.strokes.count, 2)
        XCTAssertEqual(Set(drawing.strokes.map(\.path.creationDate)).count, 1, "The placement's strokes share one date.")
        XCTAssertFalse(fixture.page.annotations.filter { annotation in annotation.type == "Ink" }.isEmpty, "Written as /Ink annotations.")
        XCTAssertNotNil(PDFPageInkTracker.restoring(try XCTUnwrap(PDFInkGroups.editableGroup(on: fixture.page))),
                        "The group restores as the iPad's canvas restores it.")
        XCTAssertEqual(fixture.session.undoManager.undoActionName, "Add Signature")
        // Placed smaller than it was drawn, its lines are drawn thinner, not thinner than PencilKit draws at all, as a
        // point size scaled with the frame was: it vanished on the iPad (seen 2026-11-13).
        for stroke in drawing.strokes {
            XCTAssertGreaterThan(PencilStrokeSampler.drawnWidth(ofPointSize: stroke.path[0].size.width, inkType: .pen), 0.5)
        }
        fixture.session.undoManager.undo()
        XCTAssertTrue(try pageDrawing(of: fixture).strokes.isEmpty)
    }

    func testAPlacedSignatureIsMovedAndResizedByItsCornerEachAsOneStep() throws {
        let fixture = try XCTUnwrap(openedHarness)
        let frame = try placeSignature(in: fixture)
        let middle = CGPoint(x: frame.midX, y: frame.midY)
        try fixture.drag(through: [pagePoint(middle), pagePoint(CGPoint(x: middle.x - 40, y: middle.y + 100))])
        let moved = try XCTUnwrap(fixture.tools?.signatures?.selectedFrame)
        XCTAssertEqual(moved.minX, frame.minX - 40, accuracy: 1)
        XCTAssertEqual(moved.minY, frame.minY + 100, accuracy: 1)
        XCTAssertEqual(fixture.session.undoManager.undoActionName, "Move Signature")

        let corner = CGPoint(x: moved.maxX, y: moved.maxY)
        try fixture.drag(through: [pagePoint(corner), pagePoint(CGPoint(x: corner.x + moved.width, y: corner.y))])
        let resized = try XCTUnwrap(fixture.tools?.signatures?.selectedFrame)
        XCTAssertEqual(resized.width, moved.width * 2, accuracy: 2)
        // The strokes are scaled alike both ways; their frame, PencilKit's render bounds, grows a little less than linearly.
        XCTAssertEqual(resized.width / resized.height, moved.width / moved.height, accuracy: moved.width / moved.height * 0.05, "It keeps its proportions.")
        XCTAssertEqual(resized.minX, moved.minX, accuracy: 1, "The opposite corner stays.")
        XCTAssertEqual(fixture.session.undoManager.undoActionName, "Resize Signature")

        fixture.session.undoManager.undo()
        XCTAssertEqual(try XCTUnwrap(fixture.tools?.signatures?.selectedFrame).width, moved.width, accuracy: 1)
        fixture.session.undoManager.undo()
        XCTAssertEqual(try XCTUnwrap(fixture.tools?.signatures?.selectedFrame).minX, frame.minX, accuracy: 1)
    }

    func testDeleteRemovesTheSelectedSignatureAndAPressOnItSelectsItAgain() throws {
        let fixture = try XCTUnwrap(openedHarness)
        let frame = try placeSignature(in: fixture)
        let otherInk = PKStroke(ink: PKInk(.pen, color: .black), path: PKStrokePath(controlPoints: [
            PKStrokePoint(location: CGPoint(x: 20, y: 20), timeOffset: 0, size: CGSize(width: 2, height: 2), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2),
            PKStrokePoint(location: CGPoint(x: 60, y: 20), timeOffset: 0.1, size: CGSize(width: 2, height: 2), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2),
        ], creationDate: Date(timeIntervalSince1970: 1)))
        try fixture.step {
            let ink = try fixture.session.pointerInk(on: fixture.page, cached: nil)
            _ = try fixture.session.addPointerStroke(otherInk, on: fixture.page, to: ink)
        }
        // Escape leaves it, a press on its ink selects it again.
        XCTAssertTrue(try XCTUnwrap(fixture.tools).handleKeyDown(try fixture.key("\u{1B}", keyCode: 53)))
        XCTAssertNil(fixture.tools?.signatures?.selectedFrame)
        let onItsInk = try XCTUnwrap(try pageDrawing(of: fixture).strokes.first?.path.first?.location)
        try fixture.drag(through: [pagePoint(onItsInk)])
        XCTAssertEqual(try XCTUnwrap(fixture.tools?.signatures?.selectedFrame).minX, frame.minX, accuracy: 1)

        try fixture.step { XCTAssertTrue(try fixture.pressDelete()) }
        XCTAssertEqual(fixture.session.undoManager.undoActionName, "Delete Signature")
        XCTAssertEqual(try pageDrawing(of: fixture).strokes.count, 1, "The other ink stays.")
        fixture.session.undoManager.undo()
        XCTAssertEqual(try pageDrawing(of: fixture).strokes.count, 3)
    }

    func testASignatureIsSavedAsEditableInk() async throws {
        let fixture = try XCTUnwrap(openedHarness)
        _ = try placeSignature(in: fixture)
        try await fixture.session.save()
        let saved = try XCTUnwrap(PDFDocument(url: fixture.location)?.page(at: 0))
        let group = try XCTUnwrap(PDFInkGroups.editableGroup(on: saved))
        XCTAssertEqual(try PKDrawing(data: group.record.drawingData).strokes.count, 2, "The file holds the strokes the iPad edits.")
    }
}
#endif
