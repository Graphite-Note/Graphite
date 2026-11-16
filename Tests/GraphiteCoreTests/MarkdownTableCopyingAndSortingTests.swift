/**
 * File: MarkdownTableCopyingAndSortingTests.swift
 * -----------------------------------------------
 * Layer: Tests
 * Description: Duplicating a table's row or column and sorting its rows by a column, every other character left as written.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 11/11/2026
 */

import XCTest
@testable import GraphiteCore

final class MarkdownTableCopyingAndSortingTests: XCTestCase {
    private let english = Locale(identifier: "en_US")

    private func sorted(_ source: String, byColumn column: Int, _ order: MarkdownTableSortOrder) -> String? {
        MarkdownTableEditing.sortingRows(byColumn: column, order, in: source, locale: english)
    }

    // MARK: Duplicate row

    func testDuplicatingABodyRowPutsItsLineAsWrittenBelowIt() {
        let source = "| Name | Value |\n| ---- | ----- |\n|  a   |   1   |\n| b | 2 |\n"
        XCTAssertEqual(MarkdownTableEditing.duplicatingRow(1, in: source),
                       "| Name | Value |\n| ---- | ----- |\n|  a   |   1   |\n|  a   |   1   |\n| b | 2 |\n")
    }

    func testDuplicatingTheHeaderMakesItsCopyTheFirstBodyRow() {
        let source = "| A | B |\n| - | - |\n| 1 | 2 |\n"
        XCTAssertEqual(MarkdownTableEditing.duplicatingRow(0, in: source), "| A | B |\n| - | - |\n| A | B |\n| 1 | 2 |\n")
    }

    func testDuplicatingTheLastLineWithoutABreakKeepsTheSourceEndingWithoutOne() {
        let source = "| A |\n| - |\n| 1 |"
        XCTAssertEqual(MarkdownTableEditing.duplicatingRow(1, in: source), "| A |\n| - |\n| 1 |\n| 1 |")
    }

    func testDuplicatingARowKeepsWindowsLineEndingsIndentationAndARaggedRow() {
        let source = "  A | B\r\n  --|--\r\n  1\r\n  2 | 3\r\n"
        XCTAssertEqual(MarkdownTableEditing.duplicatingRow(1, in: source), "  A | B\r\n  --|--\r\n  1\r\n  1\r\n  2 | 3\r\n")
    }

    func testDuplicatingARowKeepsItsComment() {
        let source = "| A |\n| - |\n| 1 %%why%% |\n"
        XCTAssertEqual(MarkdownTableEditing.duplicatingRow(1, in: source), "| A |\n| - |\n| 1 %%why%% |\n| 1 %%why%% |\n")
    }

    func testDuplicatingARowThatIsNotThereChangesNothing() {
        XCTAssertNil(MarkdownTableEditing.duplicatingRow(2, in: "| A |\n| - |\n| 1 |\n"))
        XCTAssertNil(MarkdownTableEditing.duplicatingRow(-1, in: "| A |\n| - |\n| 1 |\n"))
        XCTAssertNil(MarkdownTableEditing.duplicatingRow(0, in: "Not a table\n"))
    }

    // MARK: Duplicate column

    func testDuplicatingAColumnCopiesItsHeaderAlignmentAndCellsToItsRight() {
        let source = "| Name | Value | Unit |\n| :--- | ----: | ---- |\n| a | 1 | m |\n| b | 2 | s |\n"
        XCTAssertEqual(MarkdownTableEditing.duplicatingColumn(at: 1, in: source),
                       "| Name | Value | Value | Unit |\n| :--- | ----: | ----: | ---- |\n| a | 1 | 1 | m |\n| b | 2 | 2 | s |\n")
    }

    func testDuplicatingTheLastColumnWithAndWithoutOuterPipes() {
        XCTAssertEqual(MarkdownTableEditing.duplicatingColumn(at: 1, in: "| A | B |\n| - | :-: |\n| 1 | 2 |\n"),
                       "| A | B | B |\n| - | :-: | :-: |\n| 1 | 2 | 2 |\n")
        XCTAssertEqual(MarkdownTableEditing.duplicatingColumn(at: 1, in: "A | B\n--|--\n1 | 2\n"), "A | B | B\n--|-- | --\n1 | 2 | 2\n")
    }

    func testDuplicatingAColumnLeavesARowTooShortToReachItAndKeepsWindowsLineEndings() {
        let source = "| A | B |\r\n| - | - |\r\n| 1 |\r\n| 2 | 3 |\r\n"
        XCTAssertEqual(MarkdownTableEditing.duplicatingColumn(at: 1, in: source), "| A | B | B |\r\n| - | - | - |\r\n| 1 |\r\n| 2 | 3 | 3 |\r\n")
    }

    func testDuplicatingAColumnWithAnEmptyCellKeepsItAColumn() {
        let source = "| A | B |\n| - | - |\n|  | 3 |\n"
        let duplicated = MarkdownTableEditing.duplicatingColumn(at: 0, in: source)
        XCTAssertEqual(duplicated, "| A | A | B |\n| - | - | - |\n|  |  | 3 |\n")
        XCTAssertEqual(duplicated.flatMap(MarkdownTable.parse)?.rows.map { row in row.map(\.source) }, [["A", "A", "B"], ["", "", "3"]])
    }

    func testDuplicatingAColumnThatIsNotThereChangesNothing() {
        XCTAssertNil(MarkdownTableEditing.duplicatingColumn(at: 2, in: "| A | B |\n| - | - |\n"))
    }

    // MARK: Sort by column

    func testSortingKeepsTheHeaderFirstAndOrdersNumbersByValue() {
        let source = "| Row | n |\n| --- | - |\n| row 10 | a |\n| row 2 | b |\n| Row 1 | c |\n"
        XCTAssertEqual(sorted(source, byColumn: 0, .ascending), "| Row | n |\n| --- | - |\n| Row 1 | c |\n| row 2 | b |\n| row 10 | a |\n")
        XCTAssertEqual(sorted(source, byColumn: 0, .descending), "| Row | n |\n| --- | - |\n| row 10 | a |\n| row 2 | b |\n| Row 1 | c |\n")
    }

    func testSortingIgnoresCaseAndAccents() {
        let source = "| Word |\n| - |\n| zebra |\n| Éclair |\n| apple |\n| eclipse |\n"
        XCTAssertEqual(sorted(source, byColumn: 0, .ascending), "| Word |\n| - |\n| apple |\n| Éclair |\n| eclipse |\n| zebra |\n")
    }

    func testEmptyCellsGoLastInBothOrdersAndTiesKeepTheirOrder() {
        let source = "| Key | Id |\n| - | - |\n|  | 1 |\n| b | 2 |\n| B | 3 |\n| a | 4 |\n| 5 | 5 |\n"
        XCTAssertEqual(sorted(source, byColumn: 0, .ascending), "| Key | Id |\n| - | - |\n| 5 | 5 |\n| a | 4 |\n| b | 2 |\n| B | 3 |\n|  | 1 |\n")
        // Row w has no Id cell at all and sorts with the empty ones.
        let byId = "| Key | Id |\n| - | - |\n| x | 2 |\n| y |  |\n| z | 1 |\n| w |\n"
        XCTAssertEqual(sorted(byId, byColumn: 1, .descending), "| Key | Id |\n| - | - |\n| x | 2 |\n| z | 1 |\n| y |  |\n| w |\n")
        XCTAssertEqual(sorted("| K |\n| - |\n| b |\n| B |\n", byColumn: 0, .descending), "| K |\n| - |\n| b |\n| B |\n", "Equal cells keep their order")
    }

    func testSortingComparesWhatTheCellShowsNotItsMarkdown() {
        let source = "| Item |\n| - |\n| **zeta** |\n| [[Notes/beta\\|alpha]] |\n| [[gamma]] |\n| $C_{GD}$ |\n| [delta](https://example.com) |\n"
        XCTAssertEqual(sorted(source, byColumn: 0, .ascending),
                       "| Item |\n| - |\n| [[Notes/beta\\|alpha]] |\n| $C_{GD}$ |\n| [delta](https://example.com) |\n| [[gamma]] |\n| **zeta** |\n")
        XCTAssertEqual(MarkdownTableEditing.visibleSortText(ofCellSource: "a %%hidden%% <br> ==b== `c`"), "a b c")
        XCTAssertEqual(MarkdownTableEditing.visibleSortText(ofCellSource: "[[target#Heading|shown]]"), "shown")
    }

    func testSortingMovesEachRowWithItsPaddingAndLeavesTheLineBreaksInPlace() {
        let source = "  | K |\r\n  | - |\r\n  |   b   |\r\n  | a |"
        XCTAssertEqual(sorted(source, byColumn: 0, .ascending), "  | K |\r\n  | - |\r\n  | a |\r\n  |   b   |")
    }

    func testSortingASortedTableOrAnUnknownColumnChangesNothing() {
        let source = "| K |\n| - |\n| a |\n| b |\n"
        XCTAssertEqual(sorted(source, byColumn: 0, .ascending), source)
        XCTAssertNil(sorted(source, byColumn: 1, .ascending))
    }
}
