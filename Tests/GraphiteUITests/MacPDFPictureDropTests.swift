/**
 * File: MacPDFPictureDropTests.swift
 * ----------------------------------
 * Layer: Tests
 * Description: Pictures dropped onto a Mac PDF view: the page point under the drop agrees with PDFKit at every quarter
 *              turn and zoom; image data and a Finder file are placed where they landed, selected, one step each; a
 *              PDF file and a protected PDF take no drop; a dragged PDF file shows no "+" and its drop says why;
 *              a PDF embedded in a note leaves dropped files to the note.
 *
 * Authors: Bahey Shalash
 * Version: 0.3
 * Date: 28/11/2026
 */

#if os(macOS)
import XCTest
import AppKit
import SwiftUI
import PDFKit
import GraphiteCore
import GraphiteApple
@testable import GraphiteUI
import GraphiteTestSupport

@MainActor
final class MacPDFPictureDropTests: XCTestCase {
    private var openedHarness: MacPDFPageToolHarness?

    override func setUp() async throws {
        try await super.setUp()
        openedHarness = try await MacPDFPageToolHarness.open(for: self, prefix: "MacPDFPictureDrop")
    }

    /// A PNG of `width` by `height` pixels that states no resolution, so it is placed at half its pixels in points.
    static func pngData(width: Int = 200, height: Int = 100) throws -> Data {
        let colorSpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(srgbRed: 0.1, green: 0.5, blue: 0.9, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try ImageEncoding.pngData(from: try XCTUnwrap(context.makeImage()))
    }

    private func pasteboard(_ write: (NSPasteboard) -> Void) -> NSPasteboard {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("PDFPictureDrop-\(UUID().uuidString)"))
        pasteboard.clearContents()
        write(pasteboard)
        addTeardownBlock { pasteboard.releaseGlobally() }
        return pasteboard
    }

    private func pictures(_ fixture: MacPDFPageToolHarness) -> [PDFPicture] {
        fixture.session.pictures(on: fixture.page)
    }

    private func assertPoint(_ actual: CGPoint?, _ expected: CGPoint, accuracy: CGFloat = 0.5, file: StaticString = #filePath, line: UInt = #line) {
        guard let actual else { return XCTFail("No point.", file: file, line: line) }
        XCTAssertEqual(actual.x, expected.x, accuracy: accuracy, "\(actual) is not \(expected)", file: file, line: line)
        XCTAssertEqual(actual.y, expected.y, accuracy: accuracy, "\(actual) is not \(expected)", file: file, line: line)
    }

    func testTheDropsPagePointAgreesWithPDFKitAtEveryTurnAndZoom() throws {
        let fixture = try XCTUnwrap(openedHarness)
        fixture.view.autoScales = false
        for rotation in [0, 90, 180, 270] {
            fixture.page.rotation = rotation
            for scale in [0.5, 1.0, 1.75] {
                fixture.view.scaleFactor = scale
                fixture.view.layoutDocumentView()
                fixture.view.go(to: fixture.page)
                for pagePoint in [CGPoint(x: 120, y: 430), CGPoint(x: 310, y: 40)] {
                    let viewPoint = fixture.view.convert(pagePoint, from: fixture.page)
                    let location = try XCTUnwrap(fixture.view.dropLocation(atViewPoint: viewPoint))
                    XCTAssertEqual(location.pageIndex, 0)
                    assertPoint(location.pagePoint, pagePoint)
                }
            }
        }
    }

    func testDroppedImageDataIsPlacedWhereItLandedAtItsOwnSizeSelectedAsOneStep() async throws {
        let fixture = try XCTUnwrap(openedHarness)
        let target = MacPDFPictureDropTarget(session: fixture.session, view: fixture.view)
        var placedReports = 0
        target.picturesWerePlaced = { placedReports += 1 }
        let imageData = try Self.pngData()
        let carried = pasteboard { pasteboard in pasteboard.setData(imageData, forType: .png) }
        XCTAssertEqual(MacPDFPictureDropTarget.kinds(on: carried), [.picture])
        XCTAssertTrue(target.takesDrop(from: carried))

        let location = try XCTUnwrap(fixture.view.dropLocation(atViewPoint: fixture.view.convert(CGPoint(x: 140, y: 420), from: fixture.page)))
        fixture.session.undoManager.beginUndoGrouping()
        let placedCount = await target.placePictures(from: carried, imageOnPasteboard: imageData, at: location)
        fixture.session.undoManager.endUndoGrouping()

        XCTAssertEqual(placedCount, 1)
        XCTAssertEqual(placedReports, 1)
        let picture = try XCTUnwrap(pictures(fixture).first)
        XCTAssertEqual(pictures(fixture).count, 1)
        assertPoint(CGPoint(x: picture.bounds.midX, y: picture.bounds.midY), CGPoint(x: 140, y: 420), accuracy: 1)
        // 200 pixels with no resolution stated: 100 points, well under 60 % of the page.
        XCTAssertEqual(picture.bounds.width, 100, accuracy: 1)
        XCTAssertEqual(fixture.session.selectedPicture?.pictureName, picture.name)
        XCTAssertEqual(fixture.session.undoManager.undoActionName, "Add Image")
        fixture.session.undoManager.undo()
        XCTAssertTrue(pictures(fixture).isEmpty, "The drop is one step of the history.")
    }

    func testSeveralDroppedFilesCascadeFromTheDropPointEachAStep() async throws {
        let fixture = try XCTUnwrap(openedHarness)
        let target = MacPDFPictureDropTarget(session: fixture.session, view: fixture.view)
        let folder = try TemporaryVault.make(prefix: "MacPDFPictureDropFiles", for: self).root
        let first = folder.appendingPathComponent("Diagram one.png"), second = folder.appendingPathComponent("Diagram two.png")
        try Self.pngData().write(to: first)
        try Self.pngData(width: 100, height: 100).write(to: second)
        let carried = pasteboard { pasteboard in pasteboard.writeObjects([first as NSURL, second as NSURL]) }
        XCTAssertEqual(MacPDFPictureDropTarget.kinds(on: carried), [.picture, .picture])

        let location = try XCTUnwrap(fixture.view.dropLocation(atViewPoint: fixture.view.convert(CGPoint(x: 200, y: 300), from: fixture.page)))
        fixture.session.undoManager.beginUndoGrouping()
        let placedCount = await target.placePictures(from: carried, imageOnPasteboard: nil, at: location)
        fixture.session.undoManager.endUndoGrouping()

        XCTAssertEqual(placedCount, 2)
        let placed = pictures(fixture)
        XCTAssertEqual(placed.count, 2)
        assertPoint(placed.first.map { picture in CGPoint(x: picture.bounds.midX, y: picture.bounds.midY) }, CGPoint(x: 200, y: 300), accuracy: 1)
        let step = PDFPictureDropPlan.cascadeStepPoints
        assertPoint(placed.last.map { picture in CGPoint(x: picture.bounds.midX, y: picture.bounds.midY) }, CGPoint(x: 200 + step, y: 300 - step), accuracy: 1)
        XCTAssertEqual(fixture.session.selectedPicture?.pictureName, placed.last?.name)
        XCTAssertTrue(FileManager.default.fileExists(atPath: first.path), "A Finder file is read where it is, never moved.")
    }

    func testAPDFFileIsRefusedAndSaysWhy() async throws {
        let fixture = try XCTUnwrap(openedHarness)
        let target = MacPDFPictureDropTarget(session: fixture.session, view: fixture.view)
        let carried = pasteboard { pasteboard in pasteboard.writeObjects([fixture.location as NSURL]) }
        XCTAssertEqual(MacPDFPictureDropTarget.kinds(on: carried), [.pdfDocument])
        XCTAssertFalse(target.takesDrop(from: carried))
        let location = try XCTUnwrap(fixture.view.dropLocation(atViewPoint: fixture.view.convert(CGPoint(x: 200, y: 300), from: fixture.page)))
        let placedCount = await target.placePictures(from: carried, imageOnPasteboard: nil, at: location)
        XCTAssertEqual(placedCount, 0)
        XCTAssertTrue(pictures(fixture).isEmpty)
        XCTAssertEqual(fixture.session.errorMessage, "A PDF can't be placed on a page as an image. Drop a picture, such as a PNG or JPEG.")
    }

    /// The view's dragging methods as AppKit calls them: a drop goes to `performDragOperation` only after an answer that
    /// is not none, so a PDF file gets the plain pointer of a generic operation, and its drop says why in the banner.
    func testAPDFFileDraggedOverThePageShowsNoPlusAndItsDropSaysWhy() throws {
        let fixture = try XCTUnwrap(openedHarness)
        let target = MacPDFPictureDropTarget(session: fixture.session, view: fixture.view)
        fixture.view.pictureDrops = target
        fixture.view.registerForDraggedTypes(MacPDFPictureDropTarget.pasteboardTypes)
        let carried = pasteboard { pasteboard in pasteboard.writeObjects([fixture.location as NSURL]) }
        let pagePoint = fixture.view.convert(fixture.view.convert(CGPoint(x: 200, y: 300), from: fixture.page), to: nil)
        let outcome = PasteboardDrag(pasteboard: carried, window: fixture.window).move(through: [pagePoint, pagePoint])
        XCTAssertTrue(outcome.destinations.allSatisfy { destination in destination === fixture.view }, "\(outcome.destinations)")
        XCTAssertEqual(outcome.operations, [.generic, .generic], "no + on the pointer")
        XCTAssertTrue(outcome.wasHandedOver, "the drop reaches the view, which says why it is refused")
        XCTAssertFalse(outcome.wasTaken)
        XCTAssertTrue(pictures(fixture).isEmpty)
        XCTAssertEqual(fixture.session.errorMessage, "A PDF can't be placed on a page as an image. Drop a picture, such as a PNG or JPEG.")
    }

    func testTextDraggedOverThePageIsNotHandedOver() throws {
        let fixture = try XCTUnwrap(openedHarness)
        fixture.view.pictureDrops = MacPDFPictureDropTarget(session: fixture.session, view: fixture.view)
        fixture.view.registerForDraggedTypes(MacPDFPictureDropTarget.pasteboardTypes + [.string])
        let carried = pasteboard { pasteboard in pasteboard.setString("Some words", forType: .string) }
        let pagePoint = fixture.view.convert(fixture.view.convert(CGPoint(x: 200, y: 300), from: fixture.page), to: nil)
        let outcome = PasteboardDrag(pasteboard: carried, window: fixture.window).move(through: [pagePoint])
        XCTAssertEqual(outcome.operations, [[]])
        XCTAssertFalse(outcome.wasHandedOver)
        XCTAssertNil(fixture.session.errorMessage)
    }

    func testTextAloneIsNotTaken() throws {
        let fixture = try XCTUnwrap(openedHarness)
        let target = MacPDFPictureDropTarget(session: fixture.session, view: fixture.view)
        let carried = pasteboard { pasteboard in pasteboard.setString("Some words", forType: .string) }
        XCTAssertEqual(MacPDFPictureDropTarget.kinds(on: carried), [])
        XCTAssertFalse(target.takesDrop(from: carried))
    }

    func testAPasswordProtectedPDFTakesNoDrop() async throws {
        let directory = try TemporaryVault.make(prefix: "MacPDFPictureDropProtected", for: self).root
        let location = directory.appendingPathComponent("Encrypted.pdf")
        var mediaBox = CGRect(x: 0, y: 0, width: 400, height: 600)
        let auxiliaryInfo = [kCGPDFContextOwnerPassword: "owner", kCGPDFContextUserPassword: ""] as CFDictionary
        let context = try XCTUnwrap(CGContext(location as CFURL, mediaBox: &mediaBox, auxiliaryInfo))
        context.beginPDFPage(nil)
        context.endPDFPage()
        context.closePDF()
        let session = try await PDFSession.open(location)
        XCTAssertTrue(session.isProtected)
        let view = GraphiteMacPDFView(frame: CGRect(x: 0, y: 0, width: 400, height: 600))
        view.document = session.document
        let target = MacPDFPictureDropTarget(session: session, view: view)
        let imageData = try Self.pngData()
        let carried = pasteboard { pasteboard in pasteboard.setData(imageData, forType: .png) }
        XCTAssertFalse(target.takesDrop(from: carried))
    }

    /// HUNT-394: PDFKit registers its view for the Finder's files even while it takes none, so files dropped on the page of
    /// a PDF embedded in a note were refused before the note's own drop saw them. An embed registers for no dragged type at
    /// all, inside or out; the PDF viewer keeps its picture drops.
    func testAPDFEmbeddedInANoteLeavesDroppedFilesToTheNote() async throws {
        let fixture = try XCTUnwrap(openedHarness)
        let input = PDFAnnotationInput(isEnabled: false, drawsWithFinger: false, showsToolPicker: false)
        for isEmbedded in [true, false] {
            let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 600, height: 800), styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            addTeardownBlock { window.close() }
            fixture.session.pdfView = nil
            window.contentView = NSHostingView(rootView: GraphitePDFView(session: fixture.session, input: input, isEmbedded: isEmbedded))
            window.contentView?.layoutSubtreeIfNeeded()
            try await waitUntil("the PDF view is laid out") { (fixture.session.pdfView?.frame.height ?? 0) > 0 }
            let pdfView = try XCTUnwrap(fixture.session.pdfView as? GraphiteMacPDFView)
            let registeredTypes = Self.registeredDraggedTypes(in: pdfView)
            if isEmbedded {
                XCTAssertEqual(registeredTypes, [], "No view of an embedded PDF takes a drag the note would take.")
                pdfView.registerForDraggedTypes([.fileURL, NSPasteboard.PasteboardType("NSFilenamesPboardType")])
                XCTAssertEqual(pdfView.registeredDraggedTypes, [], "PDFKit registering again changes nothing.")
            } else {
                XCTAssertTrue(registeredTypes.isSuperset(of: Set(MacPDFPictureDropTarget.pasteboardTypes)), "The PDF viewer still takes pictures.")
            }
        }
    }

    private static func registeredDraggedTypes(in view: NSView) -> Set<NSPasteboard.PasteboardType> {
        view.subviews.reduce(Set(view.registeredDraggedTypes)) { types, subview in types.union(registeredDraggedTypes(in: subview)) }
    }
}
#endif
