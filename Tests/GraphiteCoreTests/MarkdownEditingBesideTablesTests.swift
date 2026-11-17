/**
 * File: MarkdownEditingBesideTablesTests.swift
 * --------------------------------------------
 * Layer: Tests
 * Description: Typing on the line right after a table: text kept off the table's last row, and Backspace selecting the table.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 17/11/2026
 */

import XCTest
@testable import GraphiteCore

final class MarkdownEditingBesideTablesTests: XCTestCase {
    private let note = "Intro\n| A | B |\n| - | - |\n| 1 | 2 |\n" as NSString

    func testACharacterTypedRightAfterATableGoesOnALineOfItsOwn() throws {
        let edit = try XCTUnwrap(MarkdownEditing.editBesideTable(typed: "x", replacing: NSRange(location: note.length, length: 0), in: note))
        XCTAssertEqual(edit.replacement, "\nx")
        XCTAssertEqual(edit.selectionAfter, NSRange(location: note.length + 2, length: 0))
    }

    func testBackspaceRightAfterATableSelectsTheTable() throws {
        let edit = try XCTUnwrap(MarkdownEditing.editBesideTable(typed: "", replacing: NSRange(location: note.length - 1, length: 1), in: note))
        XCTAssertEqual(edit.range.length, 0)
        XCTAssertEqual(note.substring(with: edit.selectionAfter), "| A | B |\n| - | - |\n| 1 | 2 |")
    }

    func testNothingChangesAwayFromATable() {
        let separated = "| A |\n| - |\n\n" as NSString
        XCTAssertNil(MarkdownEditing.editBesideTable(typed: "x", replacing: NSRange(location: separated.length, length: 0), in: separated))
        let paragraph = "Just text\n" as NSString
        XCTAssertNil(MarkdownEditing.editBesideTable(typed: "x", replacing: NSRange(location: paragraph.length, length: 0), in: paragraph))
        XCTAssertNil(MarkdownEditing.editBesideTable(typed: "\n", replacing: NSRange(location: note.length, length: 0), in: note))
        let midTable = "| A |\n| - |\n| 1 |\nx" as NSString
        XCTAssertNil(MarkdownEditing.editBesideTable(typed: "y", replacing: NSRange(location: midTable.length, length: 0), in: midTable),
                     "Not at the start of an empty line.")
    }
}
