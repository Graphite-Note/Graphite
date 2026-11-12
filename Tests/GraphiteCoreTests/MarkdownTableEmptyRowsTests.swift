/**
 * File: MarkdownTableEmptyRowsTests.swift
 * ---------------------------------------
 * Layer: Tests
 * Description: A table row of empty cells keeps a no-break space for drawing, and nothing else of a note changes.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 12/11/2026
 */

import XCTest
@testable import GraphiteCore

final class MarkdownTableEmptyRowsTests: XCTestCase {
    private let noBreakSpace = "\u{00A0}"

    /// HUNT-329: the row the "+" strip adds, `|  |  |`, gets one no-break space in its first cell.
    func testARowOfEmptyCellsKeepsANoBreakSpaceInItsFirstCell() {
        let table = "| Left | Right |\n| --- | --- |\n| a | b |\n|  |  |\n"
        let kept = MarkdownTableEmptyRows.keepingEmptyRows(in: table)
        XCTAssertEqual(kept, "| Left | Right |\n| --- | --- |\n| a | b |\n|" + noBreakSpace + " |  |\n")
        XCTAssertEqual(kept.utf16.count, table.utf16.count, "Every offset stays where the source has it.")
    }

    func testRowsWithTextAndTextOutsideTablesAreLeftAlone() {
        let note = "Text |  | not a table\n\n| A | B |\n| --- | --- |\n| x |  |\n\n|  |  |\n"
        XCTAssertEqual(MarkdownTableEmptyRows.keepingEmptyRows(in: note), note)
    }

    func testTablesInCalloutsAndWithoutOuterPipesKeepTheirEmptyRows() {
        let callout = "> [!note] Table\n> | A | B |\n> | --- | --- |\n> |  |  |\n"
        XCTAssertEqual(MarkdownTableEmptyRows.keepingEmptyRows(in: callout), "> [!note] Table\n> | A | B |\n> | --- | --- |\n> |" + noBreakSpace + " |  |\n")
        let withoutPipes = "A | B\n--- | ---\nx | y\n  |  \n"
        XCTAssertEqual(MarkdownTableEmptyRows.keepingEmptyRows(in: withoutPipes), "A | B\n--- | ---\nx | y\n  |" + noBreakSpace + " \n")
    }
}
