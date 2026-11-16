/**
 * File: LivePreviewTableCommandsTests.swift
 * -----------------------------------------
 * Layer: Tests
 * Description: A Live Preview table's cell menu in Obsidian's words and order, its commands from the palette and the
 *              Edit menu, and the "+" strips that add a last column and a last row.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 11/11/2026
 */

import XCTest
import GraphiteCore
@testable import GraphiteUI

@MainActor
final class LivePreviewTableCommandsTests: XCTestCase {
    /// A table in a note, its editor given what the note's editor gives it.
    @MainActor
    private final class EditedTable {
        var note: String
        let editor = LivePreviewTableEditor()
        var offeredTargets: [TableCellCommandTarget] = []

        init(note: String) {
            self.note = note
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
                // The block's view is given its new source as the note is restyled.
                self.viewUpdates()
            }, setIsEditingInView: { _, _ in }, offerCellCommands: { [unowned self] target in self.offeredTargets.append(target) }))
        }

        func menu(at cell: TableCellPosition) -> [RenderedBlockMenuItem] {
            editor.beginEditing(cell)
            return editor.menuItems(at: CGPoint(x: -1_000, y: -1_000))
        }

        func run(_ group: String?, _ title: String, at cell: TableCellPosition) throws {
            let items = menu(at: cell)
            let siblings = group.map { group in items.first { item in item.title == group }?.children ?? [] } ?? items
            let action = siblings.first { item in item.title == title }?.action
            try XCTUnwrap(action, title)()
        }
    }

    private static let note = "Intro\n\n| Name | Value |\n| ---- | :---: |\n| row 10 | b |\n| row 2 | a |\n\nAfter\n"

    // MARK: The cell menu

    func testTheCellMenuHasObsidiansItemsInItsOrderAndWords() {
        let table = EditedTable(note: Self.note)
        let items = table.menu(at: TableCellPosition(row: 1, column: 0))
        XCTAssertEqual(items.map(\.title), ["Row", "Column", "Sort by column (A to Z)", "Sort by column (Z to A)"])
        XCTAssertEqual(items[0].children.map(\.title), ["Add row above", "Add row below", "Move row up", "Move row down", "Duplicate row", "Delete row"])
        XCTAssertEqual(items[1].children.map(\.title), ["Add column to the left", "Add column to the right", "Move column left", "Move column right",
                                                        "Align left", "Align center", "Align right", "Duplicate column", "Delete column"])
    }

    func testCommandsThatCannotApplyAreDimmed() {
        let table = EditedTable(note: Self.note)
        func enabledTitles(at cell: TableCellPosition) -> [String] {
            let items = table.menu(at: cell)
            return (items[0].children + items[1].children + items.dropFirst(2)).filter(\.isEnabled).map(\.title)
        }
        let header = enabledTitles(at: TableCellPosition(row: 0, column: 0))
        XCTAssertFalse(header.contains("Add row above"))
        XCTAssertFalse(header.contains("Delete row"))
        XCTAssertFalse(header.contains("Move row up"))
        XCTAssertFalse(header.contains("Move column left"))
        XCTAssertTrue(header.contains("Duplicate row"))
        let lastRow = enabledTitles(at: TableCellPosition(row: 2, column: 1))
        XCTAssertTrue(lastRow.contains("Move row up"))
        XCTAssertFalse(lastRow.contains("Move row down"))
        XCTAssertFalse(lastRow.contains("Move column right"))
        let oneColumn = EditedTable(note: "| A |\n| - |\n| 1 |\n")
        let items = oneColumn.menu(at: TableCellPosition(row: 1, column: 0))
        XCTAssertFalse(items[1].children.first { item in item.title == "Delete column" }?.isEnabled ?? true)
        XCTAssertFalse(items[2].isEnabled, "One body row has nothing to sort.")
    }

    func testTheColumnsAlignmentIsMarkedAndChoosingItAgainClearsIt() throws {
        let table = EditedTable(note: Self.note)
        let alignments = table.menu(at: TableCellPosition(row: 1, column: 1))[1].children.filter { item in item.title.hasPrefix("Align") }
        XCTAssertEqual(alignments.map(\.isChosen), [false, true, false])
        try table.run("Column", "Align center", at: TableCellPosition(row: 1, column: 1))
        XCTAssertEqual(table.note, Self.note.replacingOccurrences(of: "| :---: |", with: "| ----- |"))
        try table.run("Column", "Align right", at: TableCellPosition(row: 1, column: 1))
        XCTAssertEqual(table.note, Self.note.replacingOccurrences(of: "| :---: |", with: "| ----: |"))
    }

    func testSortByColumnAToZReordersTheRowsByWhatTheyShow() throws {
        let table = EditedTable(note: Self.note)
        try table.run(nil, "Sort by column (A to Z)", at: TableCellPosition(row: 1, column: 0))
        XCTAssertEqual(table.note, "Intro\n\n| Name | Value |\n| ---- | :---: |\n| row 2 | a |\n| row 10 | b |\n\nAfter\n")
        try table.run(nil, "Sort by column (Z to A)", at: TableCellPosition(row: 1, column: 1))
        XCTAssertEqual(table.note, Self.note)
        XCTAssertNil(table.editor.editingCell, "A change of rows closes the cell's editor, as the other row commands do.")
    }

    func testDuplicateRowAndDuplicateColumn() throws {
        let table = EditedTable(note: Self.note)
        try table.run("Row", "Duplicate row", at: TableCellPosition(row: 2, column: 0))
        XCTAssertEqual(table.note, Self.note.replacingOccurrences(of: "| row 2 | a |\n", with: "| row 2 | a |\n| row 2 | a |\n"))
        try table.run("Column", "Duplicate column", at: TableCellPosition(row: 1, column: 1))
        XCTAssertEqual(table.note, "Intro\n\n| Name | Value | Value |\n| ---- | :---: | :---: |\n| row 10 | b | b |\n| row 2 | a | a |\n| row 2 | a | a |\n\nAfter\n")
    }

    // MARK: The palette's and the Edit menu's commands

    func testTheCellBeingEditedOffersItsCommandsWhichStayWithItOnceItsEditorCloses() throws {
        let table = EditedTable(note: Self.note)
        table.editor.beginEditing(TableCellPosition(row: 1, column: 0))
        let target = try XCTUnwrap(table.offeredTargets.last)
        XCTAssertTrue(target.editor === table.editor)
        XCTAssertFalse(target.isAvailable(.moveRowUp), "The first body row cannot move up.")
        XCTAssertTrue(target.isAvailable(.moveRowDown))
        // The palette takes the keyboard, which closes the cell's editor.
        table.editor.focusDidLeave()
        target.perform(.moveRowDown)
        XCTAssertEqual(table.note, "Intro\n\n| Name | Value |\n| ---- | :---: |\n| row 2 | a |\n| row 10 | b |\n\nAfter\n")
    }

    func testEveryCellCommandIsAGraphiteCommandOfTheEditMenuWithoutADefaultShortcut() {
        let graphiteCommands = TableCellCommand.allCases.map(\.graphiteCommand)
        XCTAssertEqual(Set(graphiteCommands).count, TableCellCommand.allCases.count)
        for command in TableCellCommand.allCases {
            let graphiteCommand = command.graphiteCommand
            XCTAssertEqual(graphiteCommand.title, command.title)
            XCTAssertEqual(graphiteCommand.tableCellCommand, command)
            XCTAssertEqual(graphiteCommand.macMenuTitles, [command.title])
            XCTAssertEqual(graphiteCommand.group, .editor)
            XCTAssertTrue(graphiteCommand.defaults.defaultCombinations.isEmpty, graphiteCommand.identifier)
            XCTAssertTrue(graphiteCommand.isAvailable(on: .macOS) && graphiteCommand.isAvailable(on: .iPadOS))
        }
        XCTAssertEqual(GraphiteCommand.tableAddRowBelow.identifier, "editor:table-row-after")
        XCTAssertEqual(GraphiteCommand.tableSortAscending.identifier, "graphite:table-sort-ascending")
    }

    // MARK: The "+" strips

    func testTheRightStripAddsAnEmptyLastColumnAndEditsItsHeader() {
        let table = EditedTable(note: Self.note)
        table.editor.addColumnAtTheEnd()
        XCTAssertEqual(table.note, "Intro\n\n| Name | Value |  |\n| ---- | :---: | --- |\n| row 10 | b |  |\n| row 2 | a |  |\n\nAfter\n")
        XCTAssertEqual(table.editor.editingCell, TableCellPosition(row: 0, column: 2))
        table.editor.draftText = "Unit"
        table.editor.endEditing()
        XCTAssertEqual(table.note, "Intro\n\n| Name | Value | Unit |\n| ---- | :---: | --- |\n| row 10 | b |  |\n| row 2 | a |  |\n\nAfter\n")
    }

    func testTheBottomStripAddsAnEmptyLastRowAndEditsItsFirstCell() {
        let table = EditedTable(note: Self.note)
        table.editor.beginEditing(TableCellPosition(row: 1, column: 1))
        table.editor.draftText = "c"
        table.editor.addRowAtTheEnd()
        XCTAssertEqual(table.note, "Intro\n\n| Name | Value |\n| ---- | :---: |\n| row 10 | c |\n| row 2 | a |\n|  |  |\n\nAfter\n",
                       "The cell being typed in is written first.")
        XCTAssertEqual(table.editor.editingCell, TableCellPosition(row: 3, column: 0))
        XCTAssertEqual(table.editor.draftText, "")
    }

    func testTheStripsGoOutsideTheTableWhereTheBlockHasRoomAndNeverPastTheBlock() {
        let tableBounds = CGRect(x: 0, y: 0, width: 300, height: 120)
        let roomy = TableAddStripsGeometry(tableBounds: tableBounds, blockBounds: CGRect(x: -10, y: -10, width: 500, height: 160))
        XCTAssertEqual(roomy.columnStrip, CGRect(x: 302, y: 0, width: 14, height: 120))
        XCTAssertEqual(roomy.rowStrip, CGRect(x: 0, y: 122, width: 300, height: 14))
        // The table fills the block's width, with 5 points below it.
        let tight = TableAddStripsGeometry(tableBounds: tableBounds, blockBounds: CGRect(x: -1, y: -5, width: 302, height: 130))
        XCTAssertEqual(tight.columnStrip.maxX, 301)
        XCTAssertEqual(tight.rowStrip.maxY, 125)
        // A table wider than its block, scrolled: the strip is never more than its width inside the table.
        let scrolled = TableAddStripsGeometry(tableBounds: tableBounds, blockBounds: CGRect(x: 0, y: 0, width: 200, height: 130))
        XCTAssertEqual(scrolled.columnStrip.minX, 286)
    }
}
