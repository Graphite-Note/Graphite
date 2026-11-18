/**
 * File: TableCellMacFieldEditorTests.swift
 * ----------------------------------------
 * Layer: Tests
 * Description: A Live Preview table cell's field on the Mac: its own field editor sends the Edit menu's Copy, Cut and Paste to the
 *              selected cells, a fourth click selects the table, and its undo manager undoes the note's history.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 18/11/2026
 */

#if os(macOS)
import AppKit
import XCTest
@testable import GraphiteUI

@MainActor
final class TableCellMacFieldEditorTests: XCTestCase {
    func testTheFieldEditsWithTheTablesFieldEditor() throws {
        let field = TableCellMacTextField(string: "0.433")
        let cell = try XCTUnwrap(field.cell as? TableCellMacTextFieldCell, "The field's cell is the table's own.")
        let editor = try XCTUnwrap(cell.fieldEditor(for: field) as? TableCellFieldEditor)
        XCTAssertTrue(editor.isFieldEditor)
        XCTAssertTrue(editor.tableField === field)
    }

    func testTheEditMenusClipboardItemsGoToTheSelectedCells() throws {
        let field = TableCellMacTextField(string: "0.433")
        var copies: [Bool] = []
        var pastes = 0
        var hasSelection = true
        field.actions = TableCellFieldActions(hasCellSelection: { hasSelection },
                                              copyCells: { cut in copies.append(cut); return true },
                                              pasteCells: { pastes += 1; return true })
        let editor = try XCTUnwrap(field.cell?.fieldEditor(for: field) as? TableCellFieldEditor)
        XCTAssertTrue(editor.validateUserInterfaceItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "")),
                      "Copy stays enabled with cells selected and no text selected.")
        editor.copy(nil)
        editor.cut(nil)
        editor.paste(nil)
        XCTAssertEqual(copies, [false, true])
        XCTAssertEqual(pastes, 1)
        hasSelection = false
        XCTAssertFalse(editor.validateUserInterfaceItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "")),
                       "Without cells selected and no text selected, Copy is the text's, dimmed.")
    }

    func testUndoInACellUndoesTheNotesHistory() {
        let field = TableCellMacTextField(string: "0.433")
        var keys: [TableCellKey] = []
        field.handleKey = { key in keys.append(key); return true }
        XCTAssertTrue(field.cellUndoManager.canUndo, "Edit › Undo stays enabled, for the note's earlier steps.")
        field.cellUndoManager.undo()
        field.cellUndoManager.redo()
        XCTAssertEqual(keys, [.undo, .redo])
    }

    func testAFourthClickOnTheEditedCellSelectsTheTable() throws {
        let field = TableCellMacTextField(string: "0.433")
        var selectedAll = 0
        field.actions = TableCellFieldActions(selectAllCells: { selectedAll += 1 })
        let editor = try XCTUnwrap(field.cell?.fieldEditor(for: field) as? TableCellFieldEditor)
        let fourthClick = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
                                                           context: nil, eventNumber: 0, clickCount: 4, pressure: 1))
        editor.mouseDown(with: fourthClick)
        XCTAssertEqual(selectedAll, 1)
    }
}
#endif
