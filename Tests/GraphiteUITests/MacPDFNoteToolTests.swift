/**
 * File: MacPDFNoteToolTests.swift
 * -------------------------------
 * Layer: Tests
 * Description: The Mac's Note tool through AppKit's mouse and key events on a PDF view: a click places a note and opens it
 *              to type, a click on a note opens it to edit, a drag moves it, its menu recolours and deletes it, Delete
 *              removes it, each one step undone and redone; a note's icon clicked with Text Selection opens it too.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 17/11/2026
 */

#if os(macOS)
import XCTest
import AppKit
import PDFKit
@testable import GraphiteUI
@testable import GraphiteApple
import GraphiteCore

@MainActor
final class MacPDFNoteToolTests: XCTestCase {
    override func setUp() async throws {
        // A note opens in a popover, which needs the application: a package test has none until it is asked for.
        _ = NSApplication.shared
    }

    private func notes(_ harness: MacPDFPageToolHarness) -> [PDFNote] {
        harness.page.annotations.compactMap(PDFNote.init(annotation:))
    }

    private func assertPlace(of note: PDFNote, is origin: CGPoint, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(note.iconBounds.minX, origin.x, accuracy: 0.01, message, file: file, line: line)
        XCTAssertEqual(note.iconBounds.minY, origin.y, accuracy: 0.01, message, file: file, line: line)
        XCTAssertEqual(note.iconBounds.size, PDFNote.iconSize, file: file, line: line)
    }

    private func editor(_ harness: MacPDFPageToolHarness) throws -> MacPDFNoteEditor {
        try XCTUnwrap(harness.interaction.openNoteEditor, "a note is open")
    }

    /// Types `text` in the open note, as its text view takes typing, and closes it, as one step.
    private func type(_ text: String, andCloseIn harness: MacPDFPageToolHarness) throws {
        let editor = try editor(harness)
        let textView = try XCTUnwrap(editor.textView)
        textView.insertText(text, replacementRange: NSRange(location: textView.string.utf16.count, length: 0))
        harness.step { editor.close() }
    }

    func testAClickPlacesANoteThatIsKeptWithWhatIsTypedAsOneStep() async throws {
        let harness = try await MacPDFPageToolHarness.open(for: self, prefix: "MacPDFNoteTool")
        harness.choose(.note)
        try harness.drag(through: [CGPoint(x: 100, y: 500)])
        XCTAssertTrue(try editor(harness).isOpen, "The new note opens to type in.")
        XCTAssertTrue(notes(harness).isEmpty, "Nothing is placed before anything is typed.")
        try type("Check the units", andCloseIn: harness)

        let placed = try XCTUnwrap(notes(harness).first)
        XCTAssertEqual(placed.contents, "Check the units")
        assertPlace(of: placed, is: CGPoint(x: 100, y: 476), "Its icon's corner where the page was clicked.")
        XCTAssertEqual(harness.page.annotations.filter(PDFNote.isNote).count, 1)
        XCTAssertEqual(harness.session.undoManager.undoActionName, "Add Note")
        harness.session.undoManager.undo()
        XCTAssertTrue(harness.page.annotations.isEmpty, "Undo takes the note away.")
        harness.session.undoManager.redo()
        XCTAssertEqual(notes(harness).map(\.contents), ["Check the units"])
    }

    func testANoteLeftEmptyIsNotPlaced() async throws {
        let harness = try await MacPDFPageToolHarness.open(for: self, prefix: "MacPDFNoteTool")
        harness.choose(.note)
        try harness.drag(through: [CGPoint(x: 100, y: 500)])
        try type("  \n", andCloseIn: harness)
        XCTAssertTrue(harness.page.annotations.isEmpty)
        XCTAssertNotEqual(harness.session.undoManager.undoActionName, "Add Note", "No step places an empty note.")
    }

    func testAClickOnANoteOpensItToEditAndADragMovesIt() async throws {
        let harness = try await MacPDFPageToolHarness.open(for: self, prefix: "MacPDFNoteTool")
        harness.choose(.note)
        try harness.drag(through: [CGPoint(x: 100, y: 500)])
        try type("First thought", andCloseIn: harness)

        try harness.drag(through: [CGPoint(x: 110, y: 490)])
        XCTAssertEqual(try editor(harness).textView?.string, "First thought", "A click on the icon opens the note.")
        try type(", and a second", andCloseIn: harness)
        XCTAssertEqual(notes(harness).map(\.contents), ["First thought, and a second"])
        XCTAssertEqual(harness.session.undoManager.undoActionName, "Edit Note")

        try harness.drag(through: [CGPoint(x: 110, y: 490), CGPoint(x: 160, y: 440), CGPoint(x: 210, y: 390)])
        assertPlace(of: try XCTUnwrap(notes(harness).first), is: CGPoint(x: 200, y: 376), "Moved with the pointer.")
        XCTAssertEqual(harness.session.undoManager.undoActionName, "Move Note")
        XCTAssertNil(harness.interaction.openNoteEditor.flatMap { editor in editor.isOpen ? editor : nil }, "A drag does not open the note.")
        harness.session.undoManager.undo()
        assertPlace(of: try XCTUnwrap(notes(harness).first), is: CGPoint(x: 100, y: 476))
        harness.session.undoManager.undo()
        XCTAssertEqual(notes(harness).map(\.contents), ["First thought"])
    }

    func testTheMenuRecoloursAndDeletesANoteAndDeleteRemovesTheSelectedOne() async throws {
        let harness = try await MacPDFPageToolHarness.open(for: self, prefix: "MacPDFNoteTool")
        harness.choose(.note)
        try harness.drag(through: [CGPoint(x: 100, y: 500)])
        try type("Recolour me", andCloseIn: harness)

        let menu = try XCTUnwrap(harness.tools?.menu(for: try harness.event(.rightMouseDown, at: CGPoint(x: 110, y: 490))))
        XCTAssertEqual(menu.items.map { item in item.isSeparatorItem ? "-" : item.title },
                       ["Open Note", "-", "Yellow", "Green", "Blue", "Pink", "Purple", "-", "Delete Note"])
        XCTAssertEqual(menu.items.first { item in item.title == "Yellow" }?.state, .on, "A new note is yellow.")
        let green = try XCTUnwrap(menu.items.first { item in item.title == "Green" })
        harness.step { menu.performActionForItem(at: menu.index(of: green)) }
        XCTAssertEqual(notes(harness).first?.color, PDFNote.colors[1].color)
        XCTAssertEqual(harness.session.undoManager.undoActionName, "Recolor Note")

        try harness.drag(through: [CGPoint(x: 110, y: 490)])
        try editor(harness).close()
        var deleted = false
        try harness.step { deleted = try harness.pressDelete() }
        XCTAssertTrue(deleted)
        XCTAssertTrue(harness.page.annotations.isEmpty, "Delete removed the selected note.")
        XCTAssertEqual(harness.session.undoManager.undoActionName, "Delete Note")
        harness.session.undoManager.undo()
        XCTAssertEqual(notes(harness).map(\.contents), ["Recolour me"])
    }

    func testANoteClickedWithTextSelectionOpensAndItsMenuIsOffered() async throws {
        let harness = try await MacPDFPageToolHarness.open(for: self, prefix: "MacPDFNoteTool")
        try harness.step {
            try harness.session.addNote(PDFNote(contents: "Made elsewhere", iconBounds: CGRect(x: 100, y: 476, width: 24, height: 24)), on: harness.page)
        }
        harness.choose(.textSelection)
        XCTAssertTrue(harness.interaction.handleMouseDown(try harness.event(.leftMouseDown, at: CGPoint(x: 110, y: 490))))
        XCTAssertEqual(try editor(harness).textView?.string, "Made elsewhere")
        let menu = harness.interaction.menu(for: try harness.event(.rightMouseDown, at: CGPoint(x: 110, y: 490)), defaultMenu: nil)
        XCTAssertEqual(menu?.items.last?.title, "Delete Note")
        XCTAssertFalse(harness.interaction.handleMouseDown(try harness.event(.leftMouseDown, at: CGPoint(x: 300, y: 100))), "Beside it PDFKit takes the click.")
    }
}
#endif
