/**
 * File: MacPDFPageToolsTests.swift
 * --------------------------------
 * Layer: Tests
 * Description: The Mac markup row's page tools in a PDF view: Draw writing the iPad's editable ink, the stroke eraser,
 *              and the Text Box tool placing, typing, moving, formatting, duplicating and deleting boxes, each one
 *              step of the PDF's history.
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
final class MacPDFPageToolsTests: XCTestCase {
    private static let pageSize = CGSize(width: 400, height: 600)

    @MainActor private struct Fixture {
        let location: URL
        let session: PDFSession
        let view: GraphiteMacPDFView
        let window: NSWindow
        let interaction: MacPDFMarkupInteraction
        let toolbar: PDFMarkupToolbar
        let page: PDFPage
        /// Made by the first page tool chosen, as every test chooses one.
        var tools: MacPDFPageTools? { interaction.pageTools }
    }

    /// Opened before each test: the tests themselves run synchronously, as AppKit's events
    /// and text views do, which an asynchronous test body crashed under (Swift's task allocator).
    private var openedFixture: Fixture?

    override func setUp() async throws {
        try await super.setUp()
        openedFixture = try await openFixture()
    }

    private func makeFixture(tool: PDFMarkupTool) throws -> Fixture {
        let fixture = try XCTUnwrap(openedFixture)
        fixture.interaction.input.markupTool = tool
        return fixture
    }

    private func openFixture() async throws -> Fixture {
        let directory = try TemporaryVault.make(prefix: "MacPDFPageTools", for: self).root
        let location = directory.appendingPathComponent("Worksheet.pdf")
        var mediaBox = CGRect(origin: .zero, size: Self.pageSize)
        let context = try XCTUnwrap(CGContext(location as CFURL, mediaBox: &mediaBox, nil))
        context.beginPDFPage(nil)
        context.endPDFPage()
        context.closePDF()

        let session = try await PDFSession.open(location)
        session.undoManager.groupsByEvent = false
        let view = GraphiteMacPDFView(frame: CGRect(origin: .zero, size: Self.pageSize))
        view.documentUndoManager = session.undoManager
        view.document = session.document
        view.autoScales = true
        let window = NSWindow(contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: true)
        window.contentView = view
        window.showInvisibly()
        view.layoutSubtreeIfNeeded()
        session.pdfView = view
        let toolbar = PDFMarkupToolbar()
        let interaction = MacPDFMarkupInteraction(session: session, view: view)
        let suiteName = "MacPDFPageToolsTests-\(UUID().uuidString)"
        interaction.pageToolPreferences = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        addTeardownBlock { UserDefaults().removePersistentDomain(forName: suiteName) }
        interaction.toolbar = toolbar
        view.markupInteraction = interaction
        interaction.input = PDFAnnotationInput(isEnabled: true, drawsWithFinger: false, showsToolPicker: false)
        addTeardownBlock {
            interaction.stopObservingSelection()
            window.orderOut(nil)
        }
        return Fixture(location: location, session: session, view: view, window: window, interaction: interaction, toolbar: toolbar,
                       page: try XCTUnwrap(session.document.page(at: 0)))
    }

    private func event(_ type: NSEvent.EventType, at pagePoint: CGPoint, in fixture: Fixture, clickCount: Int = 1, time: TimeInterval = 0) throws -> NSEvent {
        let viewPoint = fixture.view.convert(pagePoint, from: fixture.page)
        return try XCTUnwrap(NSEvent.mouseEvent(with: type, location: fixture.view.convert(viewPoint, to: nil), modifierFlags: [], timestamp: time,
                                                windowNumber: fixture.window.windowNumber, context: nil, eventNumber: 0, clickCount: clickCount, pressure: 1))
    }

    private func key(_ characters: String, keyCode: UInt16, modifiers: NSEvent.ModifierFlags = [], in fixture: Fixture) throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0, windowNumber: fixture.window.windowNumber,
                                       context: nil, characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: keyCode))
    }

    /// A press, drag and release through the points, as one user action closing its undo group.
    private func drag(through pagePoints: [CGPoint], in fixture: Fixture, clickCount: Int = 1) throws {
        guard let first = pagePoints.first, let last = pagePoints.last else { return }
        fixture.session.undoManager.beginUndoGrouping()
        fixture.tools?.mouseDown(try event(.leftMouseDown, at: first, in: fixture, clickCount: clickCount))
        for (index, point) in pagePoints.dropFirst().enumerated() {
            fixture.tools?.mouseDragged(try event(.leftMouseDragged, at: point, in: fixture, time: Double(index + 1) / 60))
        }
        fixture.tools?.mouseUp(try event(.leftMouseUp, at: last, in: fixture, time: Double(pagePoints.count) / 60))
        fixture.session.undoManager.endUndoGrouping()
    }

    private func step(in session: PDFSession, _ operation: () -> Void) {
        session.undoManager.beginUndoGrouping()
        operation()
        session.undoManager.endUndoGrouping()
    }

    private func inkAnnotations(on page: PDFPage) -> [PDFAnnotation] {
        page.annotations.filter { annotation in annotation.type == "Ink" }
    }

    private func storedStrokeCount(on page: PDFPage) throws -> Int {
        guard let group = PDFInkGroups.editableGroup(on: page) else { return 0 }
        return try PKDrawing(data: group.record.drawingData).strokes.count
    }

    // MARK: Draw and erase

    func testAPageToolPutsTheSurfaceOverTheViewAndTextSelectionTakesItAway() throws {
        let fixture = try makeFixture(tool: .draw)
        let middle = fixture.view.convert(CGPoint(x: 200, y: 300), from: fixture.page)
        XCTAssertTrue(fixture.view.hitTest(middle) is MacPDFToolSurface, "With Draw chosen, a press on the page is the tool's.")
        fixture.interaction.input.markupTool = .textSelection
        XCTAssertFalse(fixture.view.hitTest(middle) is MacPDFToolSurface, "With text selection, PDFKit takes the press again.")
        XCTAssertFalse(fixture.view.subviews.contains { subview in subview is MacPDFToolSurface })
    }

    func testAStrokeDrawnWithTheMouseIsTheIPadsEditableInkAndOneUndoStep() throws {
        let fixture = try makeFixture(tool: .draw)
        fixture.toolbar.useInkStyle(PDFMarkupInkStyle(color: PDFTextColor(red: 0, green: 0, blue: 1), width: .bold))
        try drag(through: [CGPoint(x: 60, y: 300), CGPoint(x: 120, y: 330), CGPoint(x: 200, y: 310)], in: fixture)

        XCTAssertEqual(inkAnnotations(on: fixture.page).count, 1)
        let strokeCount = try storedStrokeCount(on: fixture.page)
        XCTAssertEqual(strokeCount, 1, "The page keeps the PencilKit drawing the iPad edits.")
        let group = try XCTUnwrap(PDFInkGroups.editableGroup(on: fixture.page))
        let drawing = try PKDrawing(data: group.record.drawingData)
        XCTAssertNotNil(PDFPageInkTracker.restoring(group), "The iPad's canvas can restore the group.")
        XCTAssertEqual(drawing.strokes.first?.path.first?.size.width ?? 0, 5, accuracy: 0.001)
        let annotation = try XCTUnwrap(inkAnnotations(on: fixture.page).first)
        XCTAssertTrue(annotation.bounds.contains(CGPoint(x: 120, y: 330)) || annotation.bounds.insetBy(dx: -4, dy: -4).contains(CGPoint(x: 120, y: 330)))
        XCTAssertEqual(fixture.session.undoAvailability.undoActionName, "Drawing")

        fixture.session.undoAvailability.undo()
        XCTAssertEqual(inkAnnotations(on: fixture.page).count, 0, "One undo takes the whole stroke away.")
        fixture.session.undoAvailability.redo()
        XCTAssertEqual(inkAnnotations(on: fixture.page).count, 1)

        try drag(through: [CGPoint(x: 60, y: 200), CGPoint(x: 200, y: 200)], in: fixture)
        let strokeCountAfterRedo = try storedStrokeCount(on: fixture.page)
        XCTAssertEqual(strokeCountAfterRedo, 2, "A stroke after an undo and redo joins the same group.")
    }

    func testTheEraserRemovesWholeStrokesItPassesAsOneStep() throws {
        let fixture = try makeFixture(tool: .draw)
        try drag(through: [CGPoint(x: 50, y: 400), CGPoint(x: 350, y: 400)], in: fixture)
        try drag(through: [CGPoint(x: 50, y: 300), CGPoint(x: 350, y: 300)], in: fixture)
        try drag(through: [CGPoint(x: 50, y: 100), CGPoint(x: 350, y: 100)], in: fixture)
        XCTAssertEqual(inkAnnotations(on: fixture.page).count, 3)

        fixture.interaction.input.markupTool = .eraseInk
        try drag(through: [CGPoint(x: 200, y: 450), CGPoint(x: 200, y: 350), CGPoint(x: 200, y: 250)], in: fixture)
        XCTAssertEqual(inkAnnotations(on: fixture.page).count, 1, "The two strokes the eraser crossed are gone, whole.")
        let remainingStrokeCount = try storedStrokeCount(on: fixture.page)
        XCTAssertEqual(remainingStrokeCount, 1)

        fixture.session.undoAvailability.undo()
        XCTAssertEqual(inkAnnotations(on: fixture.page).count, 3, "One undo puts back both strokes of the pass.")
    }

    func testInkDrawnOnTheMacIsSavedAsEditableInk() async throws {
        let fixture = try makeFixture(tool: .draw)
        try drag(through: [CGPoint(x: 60, y: 300), CGPoint(x: 200, y: 310)], in: fixture)
        try await fixture.session.save()

        let reopened = try XCTUnwrap(PDFDocument(url: fixture.location)?.page(at: 0))
        XCTAssertEqual(inkAnnotations(on: reopened).count, 1)
        let reopenedStrokeCount = try storedStrokeCount(on: reopened)
        XCTAssertEqual(reopenedStrokeCount, 1, "Another device reads the stroke back as PencilKit ink.")
    }

    // MARK: Text boxes

    private func typeInEditor(_ text: String, in fixture: Fixture) {
        guard let textView = fixture.window.firstResponder as? NSTextView else { return XCTFail("Typing has the keyboard.") }
        textView.insertText(text, replacementRange: textView.selectedRange())
    }

    private func boxes(_ fixture: Fixture) -> [PDFTextBox] { fixture.session.textBoxes(on: fixture.page) }

    func testAClickPlacesABoxToTypeInAndAClickAwayCommitsItAsOneStep() throws {
        let fixture = try makeFixture(tool: .textBox)
        try drag(through: [CGPoint(x: 80, y: 500)], in: fixture)
        XCTAssertTrue(fixture.session.textBoxActivity.isEditing)
        typeInEditor("Gain stage", in: fixture)
        XCTAssertNotNil(fixture.session.textBoxFormat, "The row's text controls show the box's format while typing.")

        try drag(through: [CGPoint(x: 300, y: 100)], in: fixture)
        XCTAssertEqual(fixture.session.textBoxActivity, .idle)
        XCTAssertEqual(boxes(fixture).map(\.plainText), ["Gain stage"])
        XCTAssertEqual(boxes(fixture).first?.origin.x ?? 0, 80, accuracy: 0.5)
        XCTAssertEqual(fixture.session.undoAvailability.undoActionName, "Add Text Box")
        fixture.session.undoAvailability.undo()
        XCTAssertEqual(boxes(fixture), [])
    }

    func testABoxIsSelectedMovedFormattedDuplicatedAndDeleted() throws {
        let fixture = try makeFixture(tool: .textBox)
        try drag(through: [CGPoint(x: 80, y: 500)], in: fixture)
        typeInEditor("Bandwidth", in: fixture)
        try drag(through: [CGPoint(x: 300, y: 100)], in: fixture)
        guard let placed = boxes(fixture).first else { return XCTFail("The typed box is on the page.") }
        let inside = CGPoint(x: placed.middle.x, y: placed.middle.y)

        try drag(through: [inside, CGPoint(x: inside.x + 15, y: inside.y - 10), CGPoint(x: inside.x + 30, y: inside.y - 20)], in: fixture)
        guard let moved = boxes(fixture).first else { return XCTFail("The moved box is on the page.") }
        XCTAssertEqual(moved.origin.x, placed.origin.x + 30, accuracy: 0.5)
        XCTAssertEqual(moved.origin.y, placed.origin.y - 20, accuracy: 0.5)
        XCTAssertEqual(fixture.session.undoAvailability.undoActionName, "Move Text Box")
        XCTAssertEqual(fixture.session.textBoxActivity.selection?.boxName, placed.name)

        guard let applyFormat = fixture.session.applyTextBoxFormat else { return XCTFail("The tool formats the selected box.") }
        step(in: fixture.session) { applyFormat(.bold(true)) }
        XCTAssertEqual(boxes(fixture).first?.leadingAttributes.isBold, true, "The row's Bold acts on the selected box.")

        let duplicateKey = try key("d", keyCode: 2, modifiers: .command, in: fixture)
        step(in: fixture.session) { XCTAssertTrue(fixture.interaction.handleKeyDown(duplicateKey)) }
        XCTAssertEqual(boxes(fixture).count, 2)
        XCTAssertEqual(fixture.session.undoAvailability.undoActionName, "Duplicate Text Box")

        let deleteKey = try key("\u{7F}", keyCode: 51, in: fixture)
        step(in: fixture.session) { XCTAssertTrue(fixture.interaction.handleKeyDown(deleteKey)) }
        XCTAssertEqual(boxes(fixture).count, 1, "Delete removes the selected box, the duplicate.")
        XCTAssertEqual(fixture.session.textBoxActivity, .idle)
        XCTAssertFalse(fixture.interaction.handleKeyDown(deleteKey), "With no box selected, Delete goes on.")

        fixture.session.undoAvailability.undo()
        XCTAssertEqual(boxes(fixture).count, 2)
    }

    func testADoubleClickTypesInABoxAndEscapeLeavesItSelected() throws {
        let fixture = try makeFixture(tool: .textBox)
        try drag(through: [CGPoint(x: 80, y: 500)], in: fixture)
        typeInEditor("Pole", in: fixture)
        try drag(through: [CGPoint(x: 300, y: 100)], in: fixture)
        let placed = try XCTUnwrap(boxes(fixture).first)

        try drag(through: [placed.middle], in: fixture, clickCount: 2)
        XCTAssertTrue(fixture.session.textBoxActivity.isEditing)
        let textView = try XCTUnwrap(fixture.window.firstResponder as? NSTextView)
        textView.setSelectedRange(NSRange(location: textView.string.utf16.count, length: 0))
        textView.insertText(" zero", replacementRange: textView.selectedRange())
        step(in: fixture.session) { textView.doCommand(by: #selector(NSResponder.cancelOperation(_:))) }

        XCTAssertEqual(boxes(fixture).map(\.plainText), ["Pole zero"])
        XCTAssertEqual(fixture.session.textBoxActivity.selection?.boxName, placed.name)
        XCTAssertFalse(fixture.session.textBoxActivity.isEditing)
        XCTAssertEqual(fixture.session.undoAvailability.undoActionName, "Edit Text")
    }

    func testChoosingAnotherToolEndsTypingAndLetsTheBoxGo() throws {
        let fixture = try makeFixture(tool: .textBox)
        try drag(through: [CGPoint(x: 80, y: 500)], in: fixture)
        typeInEditor("Note", in: fixture)
        step(in: fixture.session) { fixture.interaction.input.markupTool = .draw }
        XCTAssertEqual(boxes(fixture).map(\.plainText), ["Note"])
        XCTAssertEqual(fixture.session.textBoxActivity, .idle)
        XCTAssertNil(fixture.session.textBoxFormat)
    }
}
#endif
