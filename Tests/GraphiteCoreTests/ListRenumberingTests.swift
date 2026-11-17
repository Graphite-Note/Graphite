/**
 * File: ListRenumberingTests.swift
 * --------------------------------
 * Layer: Tests
 * Description: Numbered lists counted again after Tab, Shift-Tab, moved lines, deleted items and pasted lines, in the same edit, as Obsidian's smart lists do.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 17/11/2026
 */

import Foundation
import XCTest
@testable import GraphiteCore

final class ListRenumberingTests: XCTestCase {
    private func applying(_ edit: MarkdownTextEdit?, to text: String) -> String? {
        edit.map { edit in (text as NSString).replacingCharacters(in: edit.range, with: edit.replacement) }
    }

    private func location(of fragment: String, in text: String) -> NSRange {
        NSRange(location: (text as NSString).range(of: fragment).location, length: 0)
    }

    func testTabOnAnItemStartsANestedListAtOneAndTheItemsAfterCountOn() {
        let list = "1. a\n2. b\n3. c\n4. d"
        let indented = MarkdownEditing.indenting(in: list as NSString, selection: location(of: "b", in: list), indentUnit: "\t")
        XCTAssertEqual(applying(indented, to: list), "1. a\n\t1. b\n2. c\n3. d")
        XCTAssertEqual(indented.selectionAfter, NSRange(location: 9, length: 0), "The cursor stays before b.")
        let outdented = MarkdownEditing.outdenting(in: "1. a\n\t1. b\n2. c\n3. d" as NSString, selection: NSRange(location: 9, length: 0), indentUnit: "\t")
        XCTAssertEqual(applying(outdented, to: "1. a\n\t1. b\n2. c\n3. d"), list, "Shift-Tab gives the numbers back.")
    }

    func testAnItemJoiningANestedListTakesTheNextNumberThere() {
        let list = "1. a\n\t1. x\n2. b\n3. c"
        XCTAssertEqual(applying(MarkdownEditing.indenting(in: list as NSString, selection: location(of: "b", in: list), indentUnit: "\t"), to: list),
                       "1. a\n\t1. x\n\t2. b\n2. c")
    }

    func testMovedLinesTakeTheirPlacesNumbers() {
        let list = "1. a\n2. b\n3. c"
        XCTAssertEqual(applying(MarkdownEditing.movingLines(up: true, in: list as NSString, selection: location(of: "c", in: list)), to: list),
                       "1. a\n2. c\n3. b")
        XCTAssertEqual(applying(MarkdownEditing.movingLines(up: false, in: list as NSString, selection: location(of: "a", in: list)), to: list),
                       "1. b\n2. a\n3. c")
        let fromFive = "5. a\n6. b"
        XCTAssertEqual(applying(MarkdownEditing.movingLines(up: true, in: fromFive as NSString, selection: location(of: "b", in: fromFive)), to: fromFive),
                       "5. b\n6. a", "A list starting at 5 still starts at 5.")
    }

    func testListsNumberedAlikeOrWithBulletsAreLeftAsWritten() {
        let alike = "1. a\n1. b\n1. c"
        XCTAssertEqual(applying(MarkdownEditing.movingLines(up: true, in: alike as NSString, selection: location(of: "c", in: alike)), to: alike),
                       "1. a\n1. c\n1. b")
        let bullets = "- a\n- b"
        XCTAssertEqual(applying(MarkdownEditing.indenting(in: bullets as NSString, selection: location(of: "b", in: bullets), indentUnit: "\t"), to: bullets),
                       "- a\n\t- b")
        let quoted = "> 1. a\n> 2. b\n> 3. c"
        XCTAssertEqual(applying(MarkdownEditing.indenting(in: quoted as NSString, selection: location(of: "b", in: quoted), indentUnit: "\t"), to: quoted),
                       "> 1. a\n> \t1. b\n> 2. c")
    }

    func testANumberThatGetsLongerMovesTheCursorWithIt() {
        let list = (1...10).map { number in "\(number). item \(number)" }.joined(separator: "\n")
        let edit = MarkdownEditing.movingLines(up: false, in: list as NSString, selection: location(of: "item 9", in: list))
        let moved = try? XCTUnwrap(applying(edit, to: list))
        XCTAssertTrue(moved?.hasSuffix("9. item 10\n10. item 9") == true, moved ?? "")
        let cursor = edit?.selectionAfter.location ?? 0
        XCTAssertEqual(((moved ?? "") as NSString).substring(from: cursor), "item 9", "The cursor stays before the moved line's text.")
    }

    private func renumbered(replacing fragment: String, with replacement: String, in text: String) -> String? {
        let range = (text as NSString).range(of: fragment)
        return applying(MarkdownEditing.renumberingLists(replacing: range, with: replacement, in: text as NSString, tabSize: 4), to: text)
    }

    func testDeletingAnItemMovesTheItemsAfterItUpANumber() {
        XCTAssertEqual(renumbered(replacing: "2. b\n", with: "", in: "1. a\n2. b\n3. c\n4. d"), "1. a\n2. c\n3. d")
        XCTAssertEqual(renumbered(replacing: "\n2. b", with: "", in: "1. a\n2. b\n3. c"), "1. a\n2. c", "Backspace from the end of the line above.")
        XCTAssertEqual(renumbered(replacing: "\n\t1. x", with: "", in: "1. a\n\t1. x\n\t2. y\n2. b"), "1. a\n\t1. y\n2. b",
                       "A nested list counts from 1 again.")
    }

    func testPastedItemsTakeTheNumbersOfTheirPlace() {
        let list = "1. a\n2. b\n3. c"
        let range = NSRange(location: (list as NSString).range(of: "2. b").location, length: 0)
        let edit = MarkdownEditing.renumberingLists(replacing: range, with: "1. x\n2. y\n", in: list as NSString, tabSize: 4)
        XCTAssertEqual(applying(edit, to: list), "1. a\n2. x\n3. y\n4. b\n5. c")
        XCTAssertEqual(edit?.selectionAfter, NSRange(location: 15, length: 0), "The cursor stays after the pasted lines.")
    }

    func testEditsThatLeaveTheNumbersAloneAreLeftToTheTextView() {
        XCTAssertNil(renumbered(replacing: "b", with: "", in: "1. a\n2. b\n3. c"), "No line break added or removed.")
        XCTAssertNil(renumbered(replacing: "3. c\n", with: "", in: "1. a\n2. b\n3. c\n"), "The last item: nothing after it to count.")
        XCTAssertNil(renumbered(replacing: "two\n", with: "", in: "one\ntwo\nthree"), "No list.")
        XCTAssertNil(renumbered(replacing: "1. b\n", with: "", in: "1. a\n1. b\n1. c\n1. d"), "Numbered alike on purpose.")
        XCTAssertNil(renumbered(replacing: "1. a\n2. b\n", with: "", in: "1. a\n2. b\n3. c\n4. d"),
                     "The list's first items deleted: what is left keeps its numbers, as a list may start anywhere.")
        XCTAssertNil(renumbered(replacing: "- b\n", with: "", in: "- a\n- b\n- c"))
    }
}
