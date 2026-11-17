/**
 * File: MarkdownTableRangeEditingTests.swift
 * ------------------------------------------
 * Layer: Tests
 * Description: Tests of a row above the header, moving any row, and clearing, deleting, copying and pasting a table's cells.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 17/11/2026
 */

import XCTest
@testable import GraphiteCore

final class MarkdownTableRangeEditingTests: XCTestCase {
    private let table = """
    | Name | Size |
    | :--- | ---: |
    | b    | 10   |
    | a    | 2    |
    """

    func testRowAboveTheHeaderBecomesTheHeader() {
        XCTAssertEqual(MarkdownTableEditing.insertingRowAboveHeader(in: table), """
        |  |  |
        | :--- | ---: |
        | Name | Size |
        | b    | 10   |
        | a    | 2    |
        """)
    }

    func testMovingTheHeaderIntoTheBody() {
        XCTAssertEqual(MarkdownTableEditing.movingRow(0, to: 2, in: table), """
        | b    | 10   |
        | :--- | ---: |
        | a    | 2    |
        | Name | Size |
        """)
        XCTAssertEqual(MarkdownTableEditing.movingRow(1, to: 1, in: table), table)
        XCTAssertNil(MarkdownTableEditing.movingRow(1, to: 3, in: table))
    }

    func testNewColumnTakesTheGivenAlignment() {
        XCTAssertEqual(MarkdownTableEditing.insertingColumn(at: 2, alignment: .right, in: table).flatMap(MarkdownTable.parse)?.alignments, [.left, .right, .right])
    }

    func testClearingARangeEmptiesOnlyItsCells() {
        let range = MarkdownTableCellRange(anchorRow: 2, anchorColumn: 1, headRow: 1, headColumn: 1)
        let cleared = MarkdownTableEditing.clearingCells(in: range, in: table).flatMap(MarkdownTable.parse)
        XCTAssertEqual(cleared?.rows.map { $0.map(\.source) }, [["Name", "Size"], ["b", ""], ["a", ""]])
    }

    func testDeletingWholeRowsColumnsOrPartOfTheTable() {
        let rows = MarkdownTableEditing.deletingCells(in: MarkdownTableCellRange(rows: 1...1, columns: 0...1), in: table).flatMap(MarkdownTable.parse)
        XCTAssertEqual(rows?.rows.map { $0.map(\.source) }, [["Name", "Size"], ["a", "2"]])
        let columns = MarkdownTableEditing.deletingCells(in: MarkdownTableCellRange(rows: 0...2, columns: 0...0), in: table).flatMap(MarkdownTable.parse)
        XCTAssertEqual(columns?.rows.map { $0.map(\.source) }, [["Size"], ["10"], ["2"]])
        let part = MarkdownTableEditing.deletingCells(in: MarkdownTableCellRange(rows: 0...1, columns: 0...0), in: table).flatMap(MarkdownTable.parse)
        XCTAssertEqual(part?.rows.map { $0.map(\.source) }, [["", "Size"], ["", "10"], ["a", "2"]])
        XCTAssertNil(MarkdownTableEditing.deletingCells(in: MarkdownTableCellRange(rows: 0...2, columns: 0...1), in: table))
    }

    func testCopiedCellsMakeAnAlignedMarkdownTableAndHTML() throws {
        let grid = try XCTUnwrap(MarkdownTableEditing.grid(of: MarkdownTableCellRange(rows: 0...1, columns: 0...1), in: table))
        XCTAssertEqual(grid.markdownTable, """
        | Name | Size |
        | :--- | ---: |
        | b    |   10 |
        """)
        XCTAssertEqual(grid.htmlTable, "<table><thead><tr><th>Name</th><th>Size</th></tr></thead><tbody><tr><td>b</td><td>10</td></tr></tbody></table>")
        XCTAssertEqual(MarkdownTableGrid(markdownTable: grid.markdownTable), grid)
    }

    func testPastingGrowsTheTableAndKeepsEscapes() throws {
        let grid = MarkdownTableGrid(rows: [["x \\| y", "z"], ["p", "q"]], alignments: [.center, .right])
        let pasted = try XCTUnwrap(MarkdownTableEditing.pasting(grid, atRow: 2, column: 1, in: table).flatMap(MarkdownTable.parse))
        XCTAssertEqual(pasted.rows.map { $0.map(\.source) }, [["Name", "Size", ""], ["b", "10", ""], ["a", "x \\| y", "z"], ["", "p", "q"]])
        XCTAssertEqual(pasted.alignments, [.left, .right, .right], "only the added column takes the copied alignment")
        let onHeader = try XCTUnwrap(MarkdownTableEditing.pasting(grid, atRow: 0, column: 0, in: table).flatMap(MarkdownTable.parse))
        XCTAssertEqual(onHeader.alignments, [.center, .right])
    }
}
