/**
 * File: LivePreviewTableKeysAndSelectionTests.swift
 * -------------------------------------------------
 * Layer: Tests
 * Description: A Live Preview table's keys as in Obsidian (edges, Tab, Shift-Tab, undo), its selected cells (Shift-arrows, delete,
 *              copy and paste), the header row's commands, the grips' places and where the caret goes beside a table.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 17/11/2026
 */

import XCTest
import GraphiteCore
@testable import GraphiteUI

@MainActor
final class LivePreviewTableKeysAndSelectionTests: XCTestCase {
    /// A table in a note, its editor given what the note's editor gives it, recording where the
    /// note's caret was sent and the undos asked for.
    @MainActor
    private final class EditedTable {
        var note: String
        let editor = LivePreviewTableEditor()
        var caretSides: [RenderedBlockSide] = []
        var undos: [Bool] = []

        init(note: String) {
            self.note = note
            // A pasteboard of the test's own, so the person's clipboard is left alone.
            editor.pasteboard = TablePasteboard(name: "LivePreviewTableKeysAndSelectionTests-\(UUID().uuidString)")
            viewUpdates()
        }

        private var tableBlock: LivePreviewBlock? {
            LivePreviewBlockScanner.blocks(in: note as NSString).first { block in block.kind == .table }
        }

        func viewUpdates() {
            guard let block = tableBlock else { return }
            editor.update(source: block.sourceLines, textSize: 16, sourceEditing: RenderedBlockSourceEditing(replaceSource: { [unowned self] _, transform in
                guard let block = self.tableBlock else { return }
                let source = self.note as NSString
                guard let replacement = transform(source.substring(with: block.range)) else { return }
                self.note = source.replacingCharacters(in: block.range, with: replacement)
                self.viewUpdates()
            }, setIsEditingInView: { _, _ in }, placeCaretBesideBlock: { [unowned self] _, side in self.caretSides.append(side) },
               undoInNote: { [unowned self] isRedo in self.undos.append(isRedo) }))
        }
    }

    private static let note = "Intro\n\n| Name | Value |\n| ---- | :---: |\n| a | 1 |\n| b | 2 |\n\nAfter\n"

    // MARK: Keys

    func testTabSelectsTheNextCellsTextAndTheArrowsLeaveACellAtItsEdges() {
        let table = EditedTable(note: Self.note)
        table.editor.beginEditing(TableCellPosition(row: 1, column: 0))
        XCTAssertTrue(table.editor.handle(.tab))
        XCTAssertEqual(table.editor.editingCell, TableCellPosition(row: 1, column: 1))
        XCTAssertEqual(table.editor.caret, .all)
        XCTAssertTrue(table.editor.handle(.leave(.forward)))
        XCTAssertEqual(table.editor.editingCell, TableCellPosition(row: 2, column: 0), "Right at a row's last cell goes to the next row's first.")
        XCTAssertEqual(table.editor.caret, .start)
        XCTAssertTrue(table.editor.handle(.leave(.backward)))
        XCTAssertEqual(table.editor.editingCell, TableCellPosition(row: 1, column: 1))
        XCTAssertEqual(table.editor.caret, .end)
        XCTAssertTrue(table.editor.handle(.leave(.up)))
        XCTAssertEqual(table.editor.editingCell, TableCellPosition(row: 0, column: 1))
        XCTAssertEqual(table.editor.caret, .lastLineStart)
    }

    func testTheArrowsLeaveTheTableAtItsEdgesForTheNotesLines() {
        let table = EditedTable(note: Self.note)
        table.editor.beginEditing(TableCellPosition(row: 0, column: 1))
        XCTAssertTrue(table.editor.handle(.leave(.up)))
        XCTAssertEqual(table.caretSides, [.before])
        XCTAssertNil(table.editor.editingCell)
        table.editor.beginEditing(TableCellPosition(row: 2, column: 1))
        XCTAssertTrue(table.editor.handle(.leave(.forward)))
        XCTAssertEqual(table.caretSides, [.before, .after])
        table.editor.beginEditing(TableCellPosition(row: 0, column: 0))
        XCTAssertTrue(table.editor.handle(.leave(.backward)))
        XCTAssertEqual(table.caretSides, [.before, .after, .before])
    }

    func testShiftTabInTheFirstCellAddsARowAboveTheHeader() {
        let table = EditedTable(note: Self.note)
        table.editor.beginEditing(TableCellPosition(row: 0, column: 0))
        XCTAssertTrue(table.editor.handle(.backtab))
        XCTAssertEqual(table.note, "Intro\n\n|  |  |\n| ---- | :---: |\n| Name | Value |\n| a | 1 |\n| b | 2 |\n\nAfter\n")
        XCTAssertEqual(table.editor.editingCell, TableCellPosition(row: 0, column: 1))
    }

    func testUndoInACellWritesItsTypingThenUndoesTheNote() {
        let table = EditedTable(note: Self.note)
        table.editor.beginEditing(TableCellPosition(row: 1, column: 0))
        table.editor.draftText = "typed"
        XCTAssertTrue(table.editor.handle(.undo))
        XCTAssertTrue(table.note.contains("| typed | 1 |"), "The typing is written before the note's undo, so the undo takes it back.")
        XCTAssertTrue(table.editor.handle(.redo))
        XCTAssertEqual(table.undos, [false, true])
    }

    // MARK: Selected cells

    func testShiftArrowsSelectARectangleAndBackspaceEmptiesIt() throws {
        let table = EditedTable(note: Self.note)
        table.editor.beginEditing(TableCellPosition(row: 1, column: 0))
        XCTAssertTrue(table.editor.handle(.extendSelection(.down)))
        XCTAssertEqual(table.editor.selectedRange, MarkdownTableCellRange(rows: 1...2, columns: 0...0))
        XCTAssertTrue(table.editor.handle(.deleteSelection))
        let cells = try XCTUnwrap(MarkdownTable.parse(table.editor.tableSource ?? "")).rows.map { $0.map(\.source) }
        XCTAssertEqual(cells, [["Name", "Value"], ["", "1"], ["", "2"]])
        XCTAssertFalse(table.editor.hasCellSelection)
    }

    func testDeletingWholeRowsRemovesThemAndAnArrowEndsASelectionAtItsCorner() {
        let table = EditedTable(note: Self.note)
        table.editor.selectRow(1)
        XCTAssertTrue(table.editor.handle(.deleteSelection))
        XCTAssertEqual(table.note, "Intro\n\n| Name | Value |\n| ---- | :---: |\n| b | 2 |\n\nAfter\n")
        table.editor.selectCells(from: TableCellPosition(row: 0, column: 0), to: TableCellPosition(row: 1, column: 1))
        XCTAssertTrue(table.editor.handle(.leave(.down)))
        XCTAssertFalse(table.editor.hasCellSelection)
        XCTAssertEqual(table.editor.editingCell, TableCellPosition(row: 1, column: 1))
    }

    func testCopiedCellsPasteAsAGridThatGrowsTheTable() throws {
        let table = EditedTable(note: Self.note)
        table.editor.selectCells(from: TableCellPosition(row: 1, column: 0), to: TableCellPosition(row: 2, column: 1))
        XCTAssertTrue(table.editor.copySelectedCells(cut: false))
        table.editor.clearSelection()
        table.editor.beginEditing(TableCellPosition(row: 2, column: 1))
        XCTAssertTrue(table.editor.pasteCells())
        let cells = try XCTUnwrap(MarkdownTable.parse(table.editor.tableSource ?? "")).rows.map { $0.map(\.source) }
        XCTAssertEqual(cells, [["Name", "Value", ""], ["a", "1", ""], ["b", "a", "1"], ["", "b", "2"]])
    }

    func testTheSelectionsMenuHasTheClipboardAlignmentAndClearAndDeleteCells() {
        let table = EditedTable(note: Self.note)
        table.editor.selectCells(from: TableCellPosition(row: 1, column: 0), to: TableCellPosition(row: 2, column: 1))
        let items = table.editor.selectionMenuItems(MarkdownTableCellRange(rows: 1...2, columns: 0...1))
        XCTAssertEqual(items.map(\.title), ["Cut", "Copy", "Paste", "Align left", "Align center", "Align right", "Clear cells", "Delete cells"])
    }

    // MARK: Commands as in Obsidian

    func testTheHeaderRowTakesTheRowCommandsAndACellStaysEdited() throws {
        let table = EditedTable(note: Self.note)
        table.editor.perform(.deleteRow, at: TableCellPosition(row: 0, column: 0))
        XCTAssertEqual(table.note, "Intro\n\n| a | 1 |\n| ---- | :---: |\n| b | 2 |\n\nAfter\n", "The first body row becomes the header.")
        XCTAssertEqual(table.editor.editingCell, TableCellPosition(row: 0, column: 0))
        table.editor.perform(.addColumnToTheRight, at: TableCellPosition(row: 1, column: 1))
        XCTAssertEqual(MarkdownTable.parse(table.editor.tableSource ?? "")?.alignments, [.none, .center, .center],
                       "A new column takes the alignment of the one it is added beside.")
        XCTAssertEqual(table.editor.editingCell, TableCellPosition(row: 1, column: 2))
    }

    // MARK: Geometry

    func testTheCaretGoesToTheLineBesideTheTableAddingOneAtTheNotesEdges() {
        let note = "Intro\n| A |\n| - |\nAfter" as NSString
        let tableRange = note.range(of: "| A |\n| - |")
        XCTAssertEqual(RenderedBlockCaretPlacement(beside: tableRange, side: .before, in: note), RenderedBlockCaretPlacement(lineBreakLocation: nil, caretLocation: 0))
        XCTAssertEqual(RenderedBlockCaretPlacement(beside: tableRange, side: .after, in: note).caretLocation, note.range(of: "After").location)
        let tableOnly = "| A |\n| - |" as NSString
        let wholeRange = NSRange(location: 0, length: tableOnly.length)
        XCTAssertEqual(RenderedBlockCaretPlacement(beside: wholeRange, side: .before, in: tableOnly), RenderedBlockCaretPlacement(lineBreakLocation: 0, caretLocation: 0))
        XCTAssertEqual(RenderedBlockCaretPlacement(beside: wholeRange, side: .after, in: tableOnly),
                       RenderedBlockCaretPlacement(lineBreakLocation: tableOnly.length, caretLocation: tableOnly.length + 1))
    }

    func testGripsGoOutsideTheTableWhereTheBlockHasRoomAndOverThePaddingWhereNot() {
        let table = CGRect(x: 0, y: 20, width: 200, height: 100)
        let roomy = TableGripsGeometry(tableBounds: table, blockBounds: CGRect(x: -30, y: 0, width: 300, height: 150))
        XCTAssertEqual(roomy.columnGrip(for: CGRect(x: 0, y: 20, width: 80, height: 100)).maxY, table.minY - TableGripsGeometry.gap)
        XCTAssertEqual(roomy.rowGrip(for: CGRect(x: 0, y: 20, width: 200, height: 30)).maxX, table.minX - TableGripsGeometry.gap)
        let tight = TableGripsGeometry(tableBounds: table, blockBounds: CGRect(x: 0, y: 15, width: 200, height: 120))
        XCTAssertEqual(tight.rowGrip(for: CGRect(x: 0, y: 20, width: 200, height: 30)).minX, 0, "No room on the left: over the first cell's padding.")
        XCTAssertEqual(tight.columnGrip(for: CGRect(x: 0, y: 20, width: 80, height: 100)).minY, 15)
    }
}
