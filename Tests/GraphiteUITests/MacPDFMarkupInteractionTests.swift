/**
 * File: MacPDFMarkupInteractionTests.swift
 * ----------------------------------------
 * Layer: Tests
 * Description: Text markup with the Mac's pointer and keyboard: the highlighter marking a selection, the right-click
 *              menus of selected text and of a mark, and Delete removing a selected mark, each one undo step.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 11/11/2026
 */

#if os(macOS)
import XCTest
import AppKit
import PDFKit
import GraphiteApple
@testable import GraphiteUI
import GraphiteTestSupport

@MainActor
final class MacPDFMarkupInteractionTests: XCTestCase {
    private static let pageText = "The gain sets the bandwidth of the stage."
    private static let pageSize = CGSize(width: 400, height: 600)

    private struct Fixture {
        let session: PDFSession
        let view: GraphiteMacPDFView
        let window: NSWindow
        let interaction: MacPDFMarkupInteraction
        let page: PDFPage
    }

    private func makeFixture(tool: PDFMarkupTool = .textSelection, style: PDFMarkupStyle = .default) async throws -> Fixture {
        let directory = try TemporaryVault.make(prefix: "MacPDFMarkupInteraction", for: self).root
        let location = directory.appendingPathComponent("Lecture.pdf")
        var mediaBox = CGRect(origin: .zero, size: Self.pageSize)
        let context = try XCTUnwrap(CGContext(location as CFURL, mediaBox: &mediaBox, nil))
        context.beginPDFPage(nil)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        NSAttributedString(string: Self.pageText, attributes: [.font: NSFont.systemFont(ofSize: 18)]).draw(at: CGPoint(x: 40, y: 500))
        NSGraphicsContext.restoreGraphicsState()
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
        view.layoutSubtreeIfNeeded()
        let interaction = MacPDFMarkupInteraction(session: session, view: view)
        interaction.input = PDFAnnotationInput(isEnabled: true, drawsWithFinger: false, showsToolPicker: false, markupTool: tool, markupStyle: style)
        view.markupInteraction = interaction
        addTeardownBlock { interaction.stopObservingSelection() }
        return Fixture(session: session, view: view, window: window, interaction: interaction, page: try XCTUnwrap(session.document.page(at: 0)))
    }

    private func select(_ word: String, in fixture: Fixture) throws {
        let range = (Self.pageText as NSString).range(of: word)
        fixture.view.currentSelection = try XCTUnwrap(fixture.page.selection(for: range))
    }

    private func marks(on page: PDFPage) -> [PDFMarkup] {
        page.annotations.compactMap(PDFMarkup.init(annotation:))
    }

    /// A step as one user action makes it, closing its undo group.
    private func step(in session: PDFSession, _ operation: () -> Void) {
        session.undoManager.beginUndoGrouping()
        operation()
        session.undoManager.endUndoGrouping()
    }

    /// A mouse event at the middle of `word` on the page, in window coordinates.
    private func mouseEvent(_ type: NSEvent.EventType, on word: String, in fixture: Fixture) throws -> NSEvent {
        let range = (Self.pageText as NSString).range(of: word)
        let wordBounds = try XCTUnwrap(fixture.page.selection(for: range)).bounds(for: fixture.page)
        let viewPoint = fixture.view.convert(CGPoint(x: wordBounds.midX, y: wordBounds.midY), from: fixture.page)
        return try XCTUnwrap(NSEvent.mouseEvent(with: type, location: fixture.view.convert(viewPoint, to: nil), modifierFlags: [], timestamp: 0,
                                                windowNumber: fixture.window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
    }

    func testTheHighlighterMarksTheSelectionWhenTheMouseIsLetGo() async throws {
        let fixture = try await makeFixture(tool: .highlight, style: .highlight(.green))
        try select("bandwidth", in: fixture)

        step(in: fixture.session) { fixture.interaction.mouseUpFinished() }

        XCTAssertEqual(marks(on: fixture.page).map(\.kind), [.highlight])
        XCTAssertEqual(marks(on: fixture.page).map(\.color), [.green])
        XCTAssertNil(fixture.view.currentSelection, "The marked text is no longer selected.")
        XCTAssertEqual(fixture.session.undoAvailability.undoActionName, "Highlight")
        fixture.session.undoAvailability.undo()
        XCTAssertEqual(marks(on: fixture.page), [], "One undo step takes the mark away.")
    }

    func testTextSelectionLeavesTheSelectionUnmarked() async throws {
        let fixture = try await makeFixture(tool: .textSelection)
        try select("bandwidth", in: fixture)
        fixture.interaction.mouseUpFinished()
        XCTAssertEqual(marks(on: fixture.page), [])
        XCTAssertNotNil(fixture.view.currentSelection)
    }

    func testAProtectedPDFTakesNoMarks() async throws {
        let fixture = try await makeFixture(tool: .highlight)
        fixture.interaction.input.isEnabled = false
        try select("bandwidth", in: fixture)
        fixture.interaction.mouseUpFinished()
        XCTAssertEqual(marks(on: fixture.page), [])
        let defaultMenu = NSMenu()
        XCTAssertTrue(fixture.interaction.menu(for: try mouseEvent(.rightMouseDown, on: "bandwidth", in: fixture), defaultMenu: defaultMenu) === defaultMenu)
    }

    func testRightClickingSelectedTextOffersTheMarksAndLinksBeforePDFKitsItems() async throws {
        let fixture = try await makeFixture()
        var copiedLinkPage: Int?
        fixture.interaction.linkActions = PDFLinkActions(copyLink: { pageIndex in copiedLinkPage = pageIndex }, copyQuote: { _, _ in },
                                                         quoteInNote: nil, noteName: nil)
        try select("bandwidth", in: fixture)
        let defaultMenu = NSMenu()
        defaultMenu.addItem(withTitle: "Copy", action: nil, keyEquivalent: "")

        let menu = try XCTUnwrap(fixture.interaction.menu(for: try mouseEvent(.rightMouseDown, on: "bandwidth", in: fixture), defaultMenu: defaultMenu))

        let titles = menu.items.map { item in item.isSeparatorItem ? "-" : item.title }
        XCTAssertEqual(titles, ["Highlight Yellow", "Highlight Green", "Highlight Blue", "Highlight Pink", "Highlight Purple", "Underline", "Strikethrough",
                                "-", "Copy Link to Page", "Copy as Quote", "-", "Copy"])
        let underlineIndex = try XCTUnwrap(titles.firstIndex(of: "Underline"))
        step(in: fixture.session) { menu.performActionForItem(at: underlineIndex) }
        XCTAssertEqual(marks(on: fixture.page).map(\.kind), [.underline])
        XCTAssertEqual(marks(on: fixture.page).map(\.color), [.red])

        try select("gain", in: fixture)
        let secondMenu = try XCTUnwrap(fixture.interaction.menu(for: try mouseEvent(.rightMouseDown, on: "gain", in: fixture), defaultMenu: NSMenu()))
        secondMenu.performActionForItem(at: try XCTUnwrap(secondMenu.items.firstIndex { item in item.title == "Copy Link to Page" }))
        XCTAssertEqual(copiedLinkPage, 0)
    }

    func testRightClickingAMarkRecoloursOrRemovesIt() async throws {
        let fixture = try await makeFixture()
        try select("bandwidth", in: fixture)
        step(in: fixture.session) { PDFSelectionMarking.markSelection(of: fixture.view, in: fixture.session, as: .highlight(.yellow)) }

        let menu = try XCTUnwrap(fixture.interaction.menu(for: try mouseEvent(.rightMouseDown, on: "bandwidth", in: fixture), defaultMenu: NSMenu()))
        let titles = menu.items.map { item in item.isSeparatorItem ? "-" : item.title }
        XCTAssertEqual(titles, ["Yellow", "Green", "Blue", "Pink", "Purple", "-", "Remove Highlight"])
        XCTAssertEqual(menu.items.first?.state, .on, "The mark's colour is ticked.")

        step(in: fixture.session) { menu.performActionForItem(at: 2) }
        XCTAssertEqual(marks(on: fixture.page).map(\.color), [.blue])

        let secondMenu = try XCTUnwrap(fixture.interaction.menu(for: try mouseEvent(.rightMouseDown, on: "bandwidth", in: fixture), defaultMenu: NSMenu()))
        step(in: fixture.session) { secondMenu.performActionForItem(at: secondMenu.items.count - 1) }
        XCTAssertEqual(marks(on: fixture.page), [])
    }

    func testAClickSelectsAMarkAndDeleteRemovesIt() async throws {
        let fixture = try await makeFixture(tool: .highlight)
        try select("bandwidth", in: fixture)
        step(in: fixture.session) { PDFSelectionMarking.markSelection(of: fixture.view, in: fixture.session, as: .highlight(.pink)) }

        fixture.window.makeFirstResponder(nil)
        fixture.view.mouseDown(with: try mouseEvent(.leftMouseDown, on: "bandwidth", in: fixture))
        XCTAssertTrue(fixture.window.firstResponder === fixture.view, "A click on a mark gives the PDF the keyboard, for Delete.")
        XCTAssertEqual(fixture.view.currentSelection?.string?.trimmingCharacters(in: .whitespaces), "bandwidth", "The mark shows as its text selected.")
        fixture.interaction.mouseUpFinished()
        XCTAssertEqual(marks(on: fixture.page).count, 1, "Letting go after choosing a mark does not mark it again.")

        let delete = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: fixture.window.windowNumber,
                                                    context: nil, characters: "\u{7F}", charactersIgnoringModifiers: "\u{7F}", isARepeat: false, keyCode: 51))
        step(in: fixture.session) { XCTAssertTrue(fixture.interaction.handleKeyDown(delete)) }
        XCTAssertEqual(marks(on: fixture.page), [])
        XCTAssertFalse(fixture.interaction.handleKeyDown(delete), "With no mark selected, Delete goes on to PDFKit.")

        fixture.session.undoAvailability.undo()
        XCTAssertEqual(marks(on: fixture.page).map(\.color), [.pink], "Undo puts the removed mark back.")
    }

    func testEditUndoAndRedoReachThePDFsHistory() async throws {
        let fixture = try await makeFixture()
        XCTAssertTrue(fixture.view.undoManager === fixture.session.undoManager)
        fixture.view.undo(nil)
        XCTAssertNil(fixture.session.errorMessage, "With nothing to undo, Undo does nothing.")
        try select("bandwidth", in: fixture)
        step(in: fixture.session) { PDFSelectionMarking.markSelection(of: fixture.view, in: fixture.session, as: .highlight(.yellow)) }

        fixture.view.undo(nil)
        XCTAssertEqual(marks(on: fixture.page), [], "Edit › Undo and ⌘Z undo the PDF's own steps.")
        fixture.view.redo(nil)
        XCTAssertEqual(marks(on: fixture.page).map(\.kind), [.highlight])
    }

    func testAClickBesideTheMarksGoesOnToPDFKit() async throws {
        let fixture = try await makeFixture()
        XCTAssertFalse(fixture.interaction.handleMouseDown(try mouseEvent(.leftMouseDown, on: "gain", in: fixture)))
    }
}
#endif
