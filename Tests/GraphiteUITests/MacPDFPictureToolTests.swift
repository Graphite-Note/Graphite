/**
 * File: MacPDFPictureToolTests.swift
 * ----------------------------------
 * Layer: Tests
 * Description: The Mac's Images tool in a PDF view: a click selects a picture, a drag moves it, a corner resizes it
 *              keeping its proportions, the arrow keys nudge it, Delete and the right-click menu remove it, each one
 *              step of the history, and the row's Add Image places a file's picture selected.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 16/11/2026
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
final class MacPDFPictureToolTests: XCTestCase {
    /// Opened before each test, whose body runs synchronously as AppKit's events do (see `MacPDFPageToolsTests`).
    private var openedHarness: MacPDFPageToolHarness?

    override func setUp() async throws {
        try await super.setUp()
        openedHarness = try await MacPDFPageToolHarness.open(for: self, prefix: "MacPDFPictureTool")
    }

    /// The harness with a 100 by 50 point picture whose middle is at (200, 300), and the Images tool chosen.
    private func makeFixture() async throws -> MacPDFPageToolHarness {
        let fixture = try XCTUnwrap(openedHarness)
        fixture.session.undoManager.beginUndoGrouping()
        try await fixture.session.addPicture(imageData: try MacPDFPictureDropTests.pngData(), placement: (0, CGPoint(x: 200, y: 300)), preferredWidth: 100)
        fixture.session.undoManager.endUndoGrouping()
        fixture.session.selectedPicture = nil
        fixture.choose(.pictures)
        return fixture
    }

    private func picture(_ fixture: MacPDFPageToolHarness) throws -> PDFPicture {
        try XCTUnwrap(fixture.session.pictures(on: fixture.page).first)
    }

    private func assertRectangle(_ actual: CGRect, _ expected: CGRect, file: StaticString = #filePath, line: UInt = #line) {
        for (got, wanted) in [(actual.minX, expected.minX), (actual.minY, expected.minY), (actual.width, expected.width), (actual.height, expected.height)] {
            XCTAssertEqual(got, wanted, accuracy: 0.6, "\(actual) is not \(expected)", file: file, line: line)
        }
    }

    private func arrowKey(_ functionKey: Int, keyCode: UInt16, shift: Bool = false) throws -> NSEvent {
        let fixture = try XCTUnwrap(openedHarness)
        let characters = String(try XCTUnwrap(UnicodeScalar(UInt32(functionKey))))
        return try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: shift ? [.shift] : [], timestamp: 0,
                                              windowNumber: fixture.window.windowNumber, context: nil, characters: characters,
                                              charactersIgnoringModifiers: characters, isARepeat: false, keyCode: keyCode))
    }

    func testAClickSelectsAPictureAndAClickBesideItEndsArrangingIt() async throws {
        let fixture = try await makeFixture()
        XCTAssertTrue(try XCTUnwrap(fixture.tools).takesPress(atViewPoint: fixture.view.convert(CGPoint(x: 50, y: 50), from: fixture.page)))
        try fixture.drag(through: [CGPoint(x: 200, y: 300)])
        XCTAssertEqual(fixture.session.selectedPicture?.pictureName, try picture(fixture).name)
        try fixture.drag(through: [CGPoint(x: 50, y: 50)])
        XCTAssertNil(fixture.session.selectedPicture)
        assertRectangle(try picture(fixture).bounds, CGRect(x: 150, y: 275, width: 100, height: 50))
        XCTAssertFalse(fixture.session.hasUnsavedChanges && fixture.session.undoManager.undoActionName == "Move Image", "A click moves nothing.")
    }

    func testADragMovesThePictureAsOneStep() async throws {
        let fixture = try await makeFixture()
        try fixture.drag(through: [CGPoint(x: 200, y: 300), CGPoint(x: 215, y: 290), CGPoint(x: 230, y: 280)])
        assertRectangle(try picture(fixture).bounds, CGRect(x: 180, y: 255, width: 100, height: 50))
        XCTAssertEqual(fixture.session.undoManager.undoActionName, "Move Image")
        fixture.session.undoManager.undo()
        assertRectangle(try picture(fixture).bounds, CGRect(x: 150, y: 275, width: 100, height: 50))
    }

    func testACornerResizesThePictureKeepingItsProportionsAndTheOppositeCorner() async throws {
        let fixture = try await makeFixture()
        try fixture.drag(through: [CGPoint(x: 200, y: 300)])
        // The corner at the picture's right and top on the page, (250, 325), dragged out.
        try fixture.drag(through: [CGPoint(x: 250, y: 325), CGPoint(x: 280, y: 340), CGPoint(x: 300, y: 350)])
        assertRectangle(try picture(fixture).bounds, CGRect(x: 150, y: 275, width: 150, height: 75))
        fixture.session.undoManager.undo()
        assertRectangle(try picture(fixture).bounds, CGRect(x: 150, y: 275, width: 100, height: 50))
    }

    func testATurnedPictureIsResizedAlongItsOwnEdges() async throws {
        let fixture = try await makeFixture()
        let selection = PDFPictureSelection(pictureName: try picture(fixture).name, page: fixture.session.historyPage(for: fixture.page))
        try fixture.step { try fixture.session.rotatePicture(selection, to: .pi / 2) }
        fixture.session.selectedPicture = selection
        // Turned a quarter clockwise as shown, the frame's corner at (250, 325) is shown at (225, 250), the corner at
        // (150, 275) at (175, 350). Dragging the first by (50, -100) doubles the picture along its own edges.
        let turnedCorner = PictureFrameCorner.maximumXMaximumY.point(of: try picture(fixture).bounds, turnedBy: -.pi / 2)
        let anchor = PictureFrameCorner.minimumXMinimumY.point(of: try picture(fixture).bounds, turnedBy: -.pi / 2)
        try fixture.drag(through: [turnedCorner, CGPoint(x: turnedCorner.x + 50, y: turnedCorner.y - 100)])
        let resized = try picture(fixture)
        XCTAssertEqual(resized.bounds.width, 200, accuracy: 0.6)
        XCTAssertEqual(resized.bounds.height, 100, accuracy: 0.6)
        let anchorAfter = PictureFrameCorner.minimumXMinimumY.point(of: resized.bounds, turnedBy: -.pi / 2)
        XCTAssertEqual(anchorAfter.x, anchor.x, accuracy: 0.6)
        XCTAssertEqual(anchorAfter.y, anchor.y, accuracy: 0.6)
    }

    func testArrowKeysNudgeThePictureAsShownAndDeleteRemovesIt() async throws {
        let fixture = try await makeFixture()
        try fixture.drag(through: [CGPoint(x: 200, y: 300)])
        let tools = try XCTUnwrap(fixture.tools)
        try fixture.step { XCTAssertTrue(tools.handleKeyDown(try arrowKey(NSRightArrowFunctionKey, keyCode: 124))) }
        assertRectangle(try picture(fixture).bounds, CGRect(x: 151, y: 275, width: 100, height: 50))
        try fixture.step { XCTAssertTrue(tools.handleKeyDown(try arrowKey(NSDownArrowFunctionKey, keyCode: 125, shift: true))) }
        assertRectangle(try picture(fixture).bounds, CGRect(x: 151, y: 265, width: 100, height: 50))

        try fixture.step { XCTAssertTrue(try fixture.pressDelete()) }
        XCTAssertTrue(fixture.session.pictures(on: fixture.page).isEmpty)
        XCTAssertNil(fixture.session.selectedPicture)
        XCTAssertEqual(fixture.session.undoManager.undoActionName, "Delete Image")
        fixture.session.undoManager.undo()
        XCTAssertEqual(fixture.session.pictures(on: fixture.page).count, 1)
    }

    func testTheRightClickMenuSelectsThePictureAndDeletesIt() async throws {
        let fixture = try await makeFixture()
        let menu = try XCTUnwrap(fixture.tools?.menu(for: try fixture.event(.rightMouseDown, at: CGPoint(x: 210, y: 290))))
        XCTAssertNotNil(fixture.session.selectedPicture)
        let deleteItem = try XCTUnwrap(menu.items.first { item in item.title == "Delete Image" })
        fixture.step { menu.performActionForItem(at: menu.index(of: deleteItem)) }
        XCTAssertTrue(fixture.session.pictures(on: fixture.page).isEmpty)
        XCTAssertNil(fixture.tools?.menu(for: try fixture.event(.rightMouseDown, at: CGPoint(x: 210, y: 290))), "No picture, no menu.")
    }

    func testPuttingTheToolDownEndsArranging() async throws {
        let fixture = try await makeFixture()
        try fixture.drag(through: [CGPoint(x: 200, y: 300)])
        XCTAssertNotNil(fixture.session.selectedPicture)
        fixture.choose(.draw)
        XCTAssertNil(fixture.session.selectedPicture)
    }

    func testAddImageInTheRowPlacesTheFilesPictureInThePageInViewSelected() async throws {
        let fixture = try await makeFixture()
        fixture.session.visiblePageCenter = { [weak view = fixture.view] in view?.visiblePageCenter() }
        let location = try TemporaryVault.make(prefix: "MacPDFPictureToolAdd", for: self).root.appendingPathComponent("Figure.png")
        try MacPDFPictureDropTests.pngData(width: 120, height: 120).write(to: location)
        fixture.session.undoManager.groupsByEvent = true
        fixture.toolbar.addPicture(fromFileAt: location)
        try await waitUntil("the picture is placed") { fixture.session.pictures(on: fixture.page).count == 2 }
        let added = try XCTUnwrap(fixture.session.pictures(on: fixture.page).last)
        XCTAssertEqual(fixture.toolbar.tool, .pictures)
        XCTAssertEqual(fixture.session.selectedPicture?.pictureName, added.name)
        XCTAssertEqual(added.bounds.width, 60, accuracy: 1)
        XCTAssertEqual(added.bounds.midX, 200, accuracy: 1)
        XCTAssertEqual(added.bounds.midY, 300, accuracy: 1)
    }
}
#endif
