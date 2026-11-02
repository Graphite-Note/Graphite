/**
 * File: LivePreviewTableCommentEditingTests.swift
 * -----------------------------------------------
 * Layer: Tests
 * Description: Editing a rendered table's cells, rows and columns leaves the `%%` comments in its source alone and reaches the cell drawn.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
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
            let block = try XCTUnwrap(LivePreviewBlockScanner.blocks(in: note as NSString).first { block in block.kind == .table })
            editor.update(source: block.sourceLines, textSize: 16, sourceEditing: RenderedBlockSourceEditing(replaceSource: { [unowned self] _, transform in
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
        try table.menuCommand("Column", "Delete Column")()
        XCTAssertEqual(table.note, "| a %% x | y %% |\n| - |\n| 1 |\n")
    }

    func testTheMenusRowCommandsKeepARowsComment() throws {
        let table = try EditedTable(note: "| a |\n| - |\n| 1 %%why%% |\n| 2 |\n")
        table.editor.beginEditing(TableCellPosition(row: 1, column: 0))
        try table.menuCommand("Row", "Move Row Down")()
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
}
