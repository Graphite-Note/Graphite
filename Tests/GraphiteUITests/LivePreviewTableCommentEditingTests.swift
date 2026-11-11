/**
 * File: LivePreviewTableCommentEditingTests.swift
 * -----------------------------------------------
 * Layer: Tests
 * Description: Editing a rendered table's cells, rows and columns leaves the `%%` comments in its source alone and reaches the cell drawn.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 02/11/2026
 */

import XCTest
import GraphiteCore
@testable import GraphiteUI

@MainActor
final class LivePreviewTableCommentEditingTests: XCTestCase {
    /// A table in a note, its editor given what the editor of the note gives it.
    @MainActor
    private final class EditedTable {
        var note: String
        let editor = LivePreviewTableEditor()

        init(note: String) throws {
            self.note = note
            _ = try XCTUnwrap(tableBlock)
            viewUpdates()
        }

        private var tableBlock: LivePreviewBlock? {
            LivePreviewBlockScanner.blocks(in: note as NSString).first { block in block.kind == .table }
        }

        /// What the table's view gives its editor as it updates, as the note's editor gives it:
        /// a table a comment cuts is left to source editing.
        func viewUpdates() {
            guard let block = tableBlock else { return }
            editor.update(source: block.sourceLines, textSize: 16, sourceEditing: block.isCutByComment ? nil : RenderedBlockSourceEditing(replaceSource: { [unowned self] _, transform in
                guard let block = self.tableBlock else { return }
                let source = self.note as NSString
                guard let replacement = transform(source.substring(with: block.range)) else { return }
                self.note = source.replacingCharacters(in: block.range, with: replacement)
            }, setIsEditingInView: { _, _ in }))
        }

        func menuCommand(_ group: String, _ title: String) throws -> () -> Void {
            let items = editor.menuItems(at: .zero)
            let command = items.first { item in item.title == group }?.children.first { item in item.title == title }
            return try XCTUnwrap(command?.action, title)
        }
    }

    func testAnEditOfACellHoldingACommentKeepsTheComment() throws {
        let table = try EditedTable(note: "| a %%note%% | b |\n| - | - |\n| 1 | 2 |\n\nAfter\n")
        table.editor.beginEditing(TableCellPosition(row: 0, column: 0))
        XCTAssertEqual(table.editor.draftText, "a %%note%%", "The editor holds the cell's Markdown.")
        table.editor.draftText = "A %%note%%"
        table.editor.endEditing()
        XCTAssertEqual(table.note, "| A %%note%% | b |\n| - | - |\n| 1 | 2 |\n\nAfter\n")
    }

    func testAnEditOfTheCellDrawnAfterACommentWithAPipeChangesThatCell() throws {
        let table = try EditedTable(note: "| a %% x | y %% | b |\n| - | - |\n| 1 | 2 |\n")
        table.editor.beginEditing(TableCellPosition(row: 0, column: 1))
        XCTAssertEqual(table.editor.draftText, "b")
        table.editor.draftText = "B"
        table.editor.endEditing()
        XCTAssertEqual(table.note, "| a %% x | y %% | B |\n| - | - |\n| 1 | 2 |\n")
    }

    func testTheMenusCommandsReachTheColumnDrawn() throws {
        let table = try EditedTable(note: "| a %% x | y %% | b |\n| - | - |\n| 1 | 2 |\n")
        table.editor.beginEditing(TableCellPosition(row: 1, column: 1))
        try table.menuCommand("Column", "Delete column")()
        XCTAssertEqual(table.note, "| a %% x | y %% |\n| - |\n| 1 |\n")
    }

    func testTheMenusRowCommandsKeepARowsComment() throws {
        let table = try EditedTable(note: "| a |\n| - |\n| 1 %%why%% |\n| 2 |\n")
        table.editor.beginEditing(TableCellPosition(row: 1, column: 0))
        try table.menuCommand("Row", "Move row down")()
        XCTAssertEqual(table.note, "| a |\n| - |\n| 2 |\n| 1 %%why%% |\n")
    }

    func testAChangeOfACommentAloneGivesTheTableANewKey() throws {
        func key(_ note: String) throws -> LivePreviewBlockKey {
            let blocks = LivePreviewBlockScanner.blocks(in: note as NSString)
            return try XCTUnwrap(LivePreviewBlockKey.keys(for: blocks).first)
        }
        // A view kept under the old key would write the old comment back with its next edit.
        XCTAssertNotEqual(try key("| a %%old%% |\n| - |\n"), try key("| a %%new%% |\n| - |\n"))
    }

    // MARK: A `%%` that pairs with a marker in another cell

    /// The first pause writes `c%%`, which pairs with `5%%` and hides the pipe between them:
    /// column 1 is now `d`. A key after it must not be written over `d`.
    func testATypedMarkerThatPairsAcrossCellsClosesTheEditorBeforeANeighbourIsOverwritten() async throws {
        let table = try EditedTable(note: "| h | i | j |\n| - | - | - |\n| 5%% | c | d |\n")
        table.editor.beginEditing(TableCellPosition(row: 1, column: 1))
        table.editor.draftText = "c%%"
        table.editor.commitDraft()
        table.viewUpdates()
        await Task.yield()
        table.editor.draftText = "c%%x"
        table.editor.commitDraft()
        XCTAssertEqual(table.note, "| h | i | j |\n| - | - | - |\n| 5%% | c%% | d |\n")
        XCTAssertNil(table.editor.editingCell)
    }

    func testATypedMarkerThatPairsAcrossRowsClosesTheEditor() async throws {
        let table = try EditedTable(note: "| a | b |\n| - | - |\n| p | q |\n| r%% | s |\n")
        table.editor.beginEditing(TableCellPosition(row: 1, column: 1))
        table.editor.draftText = "q%%"
        table.editor.commitDraft()
        table.viewUpdates()
        await Task.yield()
        table.editor.draftText = "q%%x"
        table.editor.commitDraft()
        XCTAssertEqual(table.note, "| a | b |\n| - | - |\n| p | q%% |\n| r%% | s |\n")
        XCTAssertNil(table.editor.editingCell)
    }

    /// Tab was going to the cell at the next index, which holds other text once the draft is written.
    func testMovingOnFromAMarkerThatPairsAcrossCellsDoesNotOpenTheNextCell() throws {
        let table = try EditedTable(note: "| h | i | j |\n| - | - | - |\n| 5%% | c | d |\n")
        table.editor.beginEditing(TableCellPosition(row: 1, column: 1))
        table.editor.draftText = "c%%"
        XCTAssertTrue(table.editor.handle(.tab))
        XCTAssertEqual(table.note, "| h | i | j |\n| - | - | - |\n| 5%% | c%% | d |\n")
        XCTAssertNil(table.editor.editingCell)
    }

    /// The menu's command names cells by where they were before the draft moved them.
    func testAMenuCommandDoesNotRunOnCellsTheDraftMoved() throws {
        let table = try EditedTable(note: "| h | i | j |\n| - | - | - |\n| 5%% | c | d |\n")
        table.editor.beginEditing(TableCellPosition(row: 1, column: 1))
        table.editor.draftText = "c%%"
        try table.menuCommand("Column", "Delete column")()
        XCTAssertEqual(table.note, "| h | i | j |\n| - | - | - |\n| 5%% | c%% | d |\n")
    }

    /// A comment being typed where every marker pairs in the cell keeps the editor, as it always has.
    func testTypingACommentThatStaysInItsCellKeepsTheEditor() throws {
        let table = try EditedTable(note: "| a %%x%% | b |\n| - | - |\n")
        table.editor.beginEditing(TableCellPosition(row: 0, column: 1))
        table.editor.draftText = "b%%"
        table.editor.commitDraft()
        table.viewUpdates()
        XCTAssertEqual(table.editor.editingCell, TableCellPosition(row: 0, column: 1))
        table.editor.draftText = "b%%n | m%%"
        table.editor.commitDraft()
        XCTAssertEqual(table.note, "| a %%x%% | b%%n | m%% |\n| - | - |\n")
        XCTAssertEqual(table.editor.editingCell, TableCellPosition(row: 0, column: 1))
    }
}
