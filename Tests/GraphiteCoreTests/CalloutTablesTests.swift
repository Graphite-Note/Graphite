/**
 * File: CalloutTablesTests.swift
 * ------------------------------
 * Layer: Tests
 * Description: The tables of a callout's body are found as they are drawn, and every table edit keeps the quote markers
 *              of their lines and the callout's own header, nested, lazy, escaped and with Windows line endings.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 13/11/2026
 */

import XCTest
@testable import GraphiteCore

final class CalloutTablesTests: XCTestCase {
    /// A callout's lines as Live Preview's block holds them for an edit: whole lines, the last line's break included.
    private static let callout = "> [!note] Rates\n> Before the table.\n>\n> | Year | Rate |\n> | --- | --- |\n> | 2024 | 2.0 |\n"

    private func edited(_ source: String, table tableIndex: Int = 0, _ edit: (String) -> String?) -> String? {
        CalloutTables.editingTable(at: tableIndex, inCallout: source, using: edit)
    }

    // MARK: Finding the tables

    func testTheTableSourceIsItsLinesWithoutTheirMarkers() throws {
        XCTAssertEqual(CalloutTables.tableSource(at: 0, inCallout: Self.callout), "| Year | Rate |\n| --- | --- |\n| 2024 | 2.0 |")
        XCTAssertNil(CalloutTables.tableSource(at: 1, inCallout: Self.callout))
        let callout = try XCTUnwrap(CalloutTables.callout(in: Self.callout))
        let tables = CalloutTables.tables(in: callout)
        XCTAssertEqual(tables.count, 1)
        let headerStart = (Self.callout as NSString).range(of: "| Year").location
        XCTAssertEqual(tables.first?.lineStartOffsets.first, headerStart, "Where the header's text starts, past `> `.")
    }

    func testARunIsCutBeforeAndAfterEachTableAndFencedCodeHoldsNone() {
        let lines = ["Text", "| A | B |", "| - | - |", "| 1 | 2 |", "Between", "", "```", "| C | D |", "| - | - |", "```",
                     "  | E | F |", "  | - | - |", "x | y", "--|--", "1 | 2", "After"]
        let pieces = CalloutTables.pieces(ofRunLines: lines)
        XCTAssertEqual(pieces.map(\.lineRange), [0..<1, 1..<4, 4..<12, 12..<15, 15..<16])
        XCTAssertEqual(pieces.map(\.isTable), [false, true, false, true, false],
                       "The fenced table is code, the indented one stays in its text; outer pipes may be left out.")
        XCTAssertEqual(CalloutTables.pieces(ofRunLines: ["Only text", "more"]).map(\.isTable), [false])
    }

    func testTablesOfNestedCalloutsComeInTheOrderTheyAreDrawn() throws {
        let source = "> [!note] Outer\n> | A | B |\n> | - | - |\n> | 1 | 2 |\n>\n> > [!tip] Inner\n> > | C | D |\n> > | - | - |\n> > | 3 | 4 |\n>\n> | E |\n> | - |\n"
        XCTAssertEqual(CalloutTables.tableSource(at: 0, inCallout: source), "| A | B |\n| - | - |\n| 1 | 2 |")
        XCTAssertEqual(CalloutTables.tableSource(at: 1, inCallout: source), "| C | D |\n| - | - |\n| 3 | 4 |")
        XCTAssertEqual(CalloutTables.tableSource(at: 2, inCallout: source), "| E |\n| - |")
    }

    // MARK: Edits keep the markers

    func testACellEditKeepsTheMarkersAndTheHeader() {
        XCTAssertEqual(edited(Self.callout) { table in MarkdownTableEditing.replacingCell(row: 1, column: 1, with: "2.1", in: table) },
                       Self.callout.replacingOccurrences(of: "| 2024 | 2.0 |", with: "| 2024 | 2.1 |"))
        XCTAssertNil(edited(Self.callout) { table in MarkdownTableEditing.replacingCell(row: 0, column: 0, with: "Year", in: table) },
                     "An edit that changes nothing is no edit.")
    }

    func testAddingARowAndAColumnPutsTheMarkersOnTheNewLines() {
        XCTAssertEqual(edited(Self.callout) { table in MarkdownTableEditing.insertingRow(atBodyIndex: 1, in: table) },
                       Self.callout + "> |  |  |\n")
        XCTAssertEqual(edited(Self.callout) { table in MarkdownTableEditing.insertingRow(atBodyIndex: 0, in: table) },
                       Self.callout.replacingOccurrences(of: "> | 2024", with: "> |  |  |\n> | 2024"))
        XCTAssertEqual(edited(Self.callout) { table in MarkdownTableEditing.insertingColumn(at: 2, in: table) },
                       "> [!note] Rates\n> Before the table.\n>\n> | Year | Rate |  |\n> | --- | --- | --- |\n> | 2024 | 2.0 |  |\n")
    }

    func testRemovingMovingDuplicatingAndSortingKeepEveryLinesMarkers() {
        let source = "> [!note] Rates\n> | Year | Rate |\n> | --- | --- |\n> | 2025 | 1.8 |\n> | 2024 | 2.0 |\n"
        XCTAssertEqual(edited(source) { table in MarkdownTableEditing.removingRow(atBodyIndex: 0, in: table) },
                       "> [!note] Rates\n> | Year | Rate |\n> | --- | --- |\n> | 2024 | 2.0 |\n")
        XCTAssertEqual(edited(source) { table in MarkdownTableEditing.movingRow(atBodyIndex: 0, by: 1, in: table) },
                       "> [!note] Rates\n> | Year | Rate |\n> | --- | --- |\n> | 2024 | 2.0 |\n> | 2025 | 1.8 |\n")
        XCTAssertEqual(edited(source) { table in MarkdownTableEditing.duplicatingRow(2, in: table) },
                       source + "> | 2024 | 2.0 |\n")
        XCTAssertEqual(edited(source) { table in MarkdownTableEditing.sortingRows(byColumn: 0, .ascending, in: table, locale: Locale(identifier: "en_US")) },
                       "> [!note] Rates\n> | Year | Rate |\n> | --- | --- |\n> | 2024 | 2.0 |\n> | 2025 | 1.8 |\n")
    }

    func testNestedCalloutsKeepBothMarkers() {
        let source = "> [!note] Outer\n> Text\n>\n> > [!tip] Inner\n> > | A | B |\n> > | - | - |\n> > | 1 | 2 |\n"
        XCTAssertEqual(edited(source) { table in MarkdownTableEditing.replacingCell(row: 1, column: 0, with: "one", in: table) },
                       source.replacingOccurrences(of: "| 1 | 2 |", with: "| one | 2 |"))
        XCTAssertEqual(edited(source) { table in MarkdownTableEditing.insertingRow(atBodyIndex: 1, in: table) }, source + "> > |  |  |\n")
        XCTAssertEqual(edited(source) { table in MarkdownTableEditing.insertingColumn(at: 0, in: table) },
                       "> [!note] Outer\n> Text\n>\n> > [!tip] Inner\n> > |  | A | B |\n> > | --- | - | - |\n> > |  | 1 | 2 |\n")
        let written = ">> [!tip] Tight\n>> | A |\n>> | - |\n"
        XCTAssertEqual(CalloutTables.tableSource(at: 0, inCallout: "> [!note] O\n" + written), "| A |\n| - |", "Markers may be written without spaces.")
        XCTAssertEqual(edited("> [!note] O\n" + written) { table in MarkdownTableEditing.insertingRow(atBodyIndex: 0, in: table) },
                       "> [!note] O\n" + written + ">> |  |\n")
    }

    /// A line without a marker continues the paragraph above it, a row of a table without outer
    /// pipes too: it keeps having none, and a row added after it takes the marked line's markers.
    func testALazyContinuationLineKeepsHavingNoMarker() {
        let beforeTable = "> [!note] Lazy\n> Some text\ncontinued lazily\n> | A | B |\n> | - | - |\n> | 1 | 2 |\n"
        XCTAssertEqual(CalloutTables.tableSource(at: 0, inCallout: beforeTable), "| A | B |\n| - | - |\n| 1 | 2 |")
        XCTAssertEqual(edited(beforeTable) { table in MarkdownTableEditing.insertingRow(atBodyIndex: 1, in: table) }, beforeTable + "> |  |  |\n")
        let inTable = "> [!note] Lazy\n> A | B\n> --|--\n1 | 2\n"
        XCTAssertEqual(CalloutTables.tableSource(at: 0, inCallout: inTable), "A | B\n--|--\n1 | 2")
        XCTAssertEqual(edited(inTable) { table in MarkdownTableEditing.replacingCell(row: 1, column: 1, with: "two", in: table) },
                       "> [!note] Lazy\n> A | B\n> --|--\n1 | two\n")
        XCTAssertEqual(edited(inTable) { table in MarkdownTableEditing.insertingRow(atBodyIndex: 1, in: table) },
                       "> [!note] Lazy\n> A | B\n> --|--\n1 | 2\n>  | \n")
    }

    func testEscapedPipesStayInTheirCells() {
        let source = "> [!note] Pipes\n> | Name | Value |\n> | --- | --- |\n> | a \\| b | 2 |\n"
        XCTAssertEqual(CalloutTables.tableSource(at: 0, inCallout: source), "| Name | Value |\n| --- | --- |\n| a \\| b | 2 |")
        XCTAssertEqual(edited(source) { table in MarkdownTableEditing.replacingCell(row: 1, column: 1, with: "3", in: table) },
                       source.replacingOccurrences(of: "| 2 |", with: "| 3 |"))
        XCTAssertEqual(edited(source) { table in MarkdownTableEditing.replacingCell(row: 1, column: 1, with: "x | y", in: table) },
                       source.replacingOccurrences(of: "| 2 |", with: "| x \\| y |"), "A pipe typed in a cell is escaped.")
        XCTAssertEqual(edited(source) { table in MarkdownTableEditing.insertingColumn(at: 1, in: table) },
                       "> [!note] Pipes\n> | Name |  | Value |\n> | --- | --- | --- |\n> | a \\| b |  | 2 |\n")
    }

    func testWindowsLineEndingsStayOnEveryLineNewOnesIncluded() {
        let source = "> [!note] Windows\r\n> | A | B |\r\n> | - | - |\r\n> | 1 | 2 |\r\n"
        XCTAssertEqual(CalloutTables.tableSource(at: 0, inCallout: source), "| A | B |\r\n| - | - |\r\n| 1 | 2 |")
        XCTAssertEqual(edited(source) { table in MarkdownTableEditing.replacingCell(row: 1, column: 1, with: "3", in: table) },
                       "> [!note] Windows\r\n> | A | B |\r\n> | - | - |\r\n> | 1 | 3 |\r\n")
        XCTAssertEqual(edited(source) { table in MarkdownTableEditing.insertingRow(atBodyIndex: 1, in: table) }, source + "> |  |  |\r\n")
        XCTAssertEqual(edited(source) { table in MarkdownTableEditing.insertingRow(atBodyIndex: 0, in: table) },
                       "> [!note] Windows\r\n> | A | B |\r\n> | - | - |\r\n> |  |  |\r\n> | 1 | 2 |\r\n")
        XCTAssertEqual(edited(source) { table in MarkdownTableEditing.removingRow(atBodyIndex: 0, in: table) },
                       "> [!note] Windows\r\n> | A | B |\r\n> | - | - |\r\n")
    }

    func testACalloutInAListItemKeepsItsIndentation() {
        let source = "  > [!note] In an item\n  > | A | B |\n  > | - | - |\n  > | 1 | 2 |\n"
        XCTAssertEqual(CalloutTables.tableSource(at: 0, inCallout: source), "| A | B |\n| - | - |\n| 1 | 2 |")
        XCTAssertEqual(edited(source) { table in MarkdownTableEditing.insertingRow(atBodyIndex: 1, in: table) }, source + "  > |  |  |\n")
    }

    func testATableInAListItemInACalloutIsEditedWithTheItemsIndentationKept() {
        let source = "> [!note] Steps\n> - First\n>   | A | B |\n>   | - | - |\n>   | 1 | 2 |\n> - Second\n"
        let lines = ["- First", "  | A | B |", "  | - | - |", "  | 1 | 2 |", "- Second"]
        XCTAssertEqual(CalloutTables.pieces(ofRunLines: lines), [
            CalloutTables.RunPiece(lineRange: 0..<1, isTable: false),
            CalloutTables.RunPiece(lineRange: 1..<4, isTable: true, indentationLength: 2),
            CalloutTables.RunPiece(lineRange: 4..<5, isTable: false),
        ])
        XCTAssertEqual(CalloutTables.tableSource(at: 0, inCallout: source), "| A | B |\n| - | - |\n| 1 | 2 |")
        XCTAssertEqual(edited(source) { table in MarkdownTableEditing.replacingCell(row: 1, column: 1, with: "two", in: table) },
                       source.replacingOccurrences(of: "| 2 |", with: "| two |"))
        XCTAssertEqual(edited(source) { table in MarkdownTableEditing.insertingRow(atBodyIndex: 1, in: table) },
                       source.replacingOccurrences(of: ">   | 1 | 2 |\n", with: ">   | 1 | 2 |\n>   |  |  |\n"),
                       "A new row takes the quote marker and the item's indentation.")
        let tabbed = "> [!note] Steps\n> 1. First\n> \t| A |\n> \t| - |\n"
        XCTAssertEqual(CalloutTables.tableSource(at: 0, inCallout: tabbed), "| A |\n| - |", "A tab indents the table as well.")
    }

    func testAnIndentedTableOutsideAListItemStaysText() {
        XCTAssertEqual(CalloutTables.pieces(ofRunLines: ["Some text", "", "    | A |", "    | - |"]),
                       [CalloutTables.RunPiece(lineRange: 0..<4, isTable: false)], "Indented code, not a table.")
        XCTAssertEqual(CalloutTables.pieces(ofRunLines: ["- Item", "  | A |", "| - |"]),
                       [CalloutTables.RunPiece(lineRange: 0..<3, isTable: false)], "Its rows must keep the item's indentation.")
    }

    func testEditsReachOnlyTheirOwnTable() {
        let source = "> [!note] Two\n> | A |\n> | - |\n> | 1 |\n>\n> | B |\n> | - |\n> | 2 |\n"
        XCTAssertEqual(edited(source, table: 1) { table in MarkdownTableEditing.replacingCell(row: 1, column: 0, with: "two", in: table) },
                       source.replacingOccurrences(of: "| 2 |", with: "| two |"))
        XCTAssertEqual(edited(source, table: 0) { table in MarkdownTableEditing.insertingRow(atBodyIndex: 1, in: table) },
                       source.replacingOccurrences(of: "> | 1 |\n", with: "> | 1 |\n> |  |\n"))
        XCTAssertNil(edited(source, table: 2) { table in table + "x" }, "No such table.")
        XCTAssertNil(edited("> Just a quote\n> | A |\n> | - |\n") { table in table + "x" }, "Not a callout.")
    }

    func testLinePrefixesFollowTheLinesThatStay() {
        let prefixes = ["> ", "> ", ""]
        XCTAssertEqual(CalloutTables.linePrefixes(for: ["a", "b", "c"], editing: ["a", "x", "c"], prefixedWith: prefixes), prefixes)
        XCTAssertEqual(CalloutTables.linePrefixes(for: ["a", "b", "new", "c"], editing: ["a", "b", "c"], prefixedWith: prefixes),
                       ["> ", "> ", "> ", ""], "A line added before the lazy one takes the marked line's markers above it.")
        XCTAssertEqual(CalloutTables.linePrefixes(for: ["a", "c"], editing: ["a", "b", "c"], prefixedWith: prefixes), ["> ", ""])
    }
}
