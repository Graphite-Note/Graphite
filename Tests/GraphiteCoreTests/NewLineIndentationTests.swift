/**
 * File: NewLineIndentationTests.swift
 * -----------------------------------
 * Layer: Tests
 * Description: Return keeps the line's indentation, in quoted code the quote markers that hold the code, and at an item with children
 *              starts its first child.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 17/11/2026
 */

import Foundation
import XCTest
@testable import GraphiteCore

final class NewLineIndentationTests: XCTestCase {
    private func pressingReturn(in text: String, at location: Int, length: Int = 0) -> String? {
        let edit = MarkdownEditing.newLineKeepingIndentation(in: text as NSString, selection: NSRange(location: location, length: length))
        return edit.map { edit in (text as NSString).replacingCharacters(in: edit.range, with: edit.replacement) }
    }

    func testReturnInIndentedCodeKeepsTheIndentation() {
        let code = "```swift\nfunc run() {\n    let value = 1\n}\n```"
        let endOfValueLine = (code as NSString).range(of: "= 1").location + 3
        XCTAssertEqual(pressingReturn(in: code, at: endOfValueLine), "```swift\nfunc run() {\n    let value = 1\n    \n}\n```")
        XCTAssertEqual(pressingReturn(in: "```\n\tindented\n```", at: 13), "```\n\tindented\n\t\n```")
        let edit = MarkdownEditing.newLineKeepingIndentation(in: code as NSString, selection: NSRange(location: endOfValueLine, length: 0))
        XCTAssertEqual(edit?.selectionAfter.location, endOfValueLine + 5, "The cursor goes after the kept indentation.")
    }

    func testReturnInCodeInACalloutKeepsTheQuoteMarkersButNotCodeThatLooksLikeThem() {
        let callout = "> [!example]\n> ```python\n>     x = 1\n> ```"
        let endOfCode = (callout as NSString).range(of: "x = 1").location + 5
        XCTAssertEqual(pressingReturn(in: callout, at: endOfCode), "> [!example]\n> ```python\n>     x = 1\n>     \n> ```")
        let doctest = "```\n>>> print(1)\n```"
        XCTAssertNil(pressingReturn(in: doctest, at: 15), "`>>>` in code is code, not a quote.")
    }

    func testIndentedTextOutsideCodeKeepsItsIndentationToo() {
        XCTAssertEqual(pressingReturn(in: "- item\n  more text", at: 18), "- item\n  more text\n  ")
        XCTAssertEqual(pressingReturn(in: "---\ntags:\n  - one\n---\n", at: 17), "---\ntags:\n  - one\n  \n---\n")
    }

    func testNothingToKeepOrACursorInsideTheIndentationGivesNoEdit() {
        XCTAssertNil(pressingReturn(in: "plain", at: 5))
        XCTAssertNil(pressingReturn(in: "    code", at: 2), "Return inside the indentation is an ordinary line break.")
        XCTAssertNil(pressingReturn(in: "> quoted", at: 8), "Quotes outside code continue as lists do, not here.")
    }

    func testASelectionIsReplacedAndACrlfNoteStaysCrlf() {
        XCTAssertEqual(pressingReturn(in: "  one two\r\n", at: 5, length: 4), "  one\r\n  \r\n")
    }

    private func pressingShiftReturn(in text: String, at location: Int) -> (text: String, cursor: Int) {
        let edit = MarkdownEditing.breakingLineWithinItem(in: text as NSString, selection: NSRange(location: location, length: 0))
        return ((text as NSString).replacingCharacters(in: edit.range, with: edit.replacement), edit.selectionAfter.location)
    }

    func testShiftReturnInAListItemStartsTheItemsNextLineWithoutAMarker() {
        XCTAssertEqual(pressingShiftReturn(in: "- item", at: 6).text, "- item\n  ")
        XCTAssertEqual(pressingShiftReturn(in: "- item", at: 6).cursor, 9)
        XCTAssertEqual(pressingShiftReturn(in: "\t10. item", at: 9).text, "\t10. item\n\t    ")
        XCTAssertEqual(pressingShiftReturn(in: "- [ ] task", at: 10).text, "- [ ] task\n  ")
        XCTAssertEqual(pressingShiftReturn(in: "> - quoted", at: 10).text, "> - quoted\n>   ")
    }

    func testShiftReturnKeepsAQuoteAndIsAPlainLineBreakElsewhere() {
        XCTAssertEqual(pressingShiftReturn(in: "> [!note]\n> text", at: 16).text, "> [!note]\n> text\n> ")
        XCTAssertEqual(pressingShiftReturn(in: "plain", at: 5).text, "plain\n")
        XCTAssertEqual(pressingShiftReturn(in: "```\n  code\n```", at: 10).text, "```\n  code\n  \n```")
        XCTAssertFalse(pressingShiftReturn(in: "plain", at: 5).text.contains("\u{2028}"))
    }

    private func pressingBackspace(in text: String, at location: Int, indentUnit: String = "    ") -> String? {
        let edit = MarkdownEditing.deletingIndentation(in: text as NSString, selection: NSRange(location: location, length: 0), indentUnit: indentUnit)
        return edit.map { edit in (text as NSString).replacingCharacters(in: edit.range, with: edit.replacement) }
    }

    func testBackspaceInLeadingSpacesRemovesALevel() {
        XCTAssertEqual(pressingBackspace(in: "        - item", at: 8), "    - item")
        XCTAssertEqual(pressingBackspace(in: "      code", at: 6), "    code", "Six spaces go back to four, the level below.")
        XCTAssertEqual(pressingBackspace(in: "a\n    b", at: 4), "a\n  b", "Two spaces into the line, the two go.")
        XCTAssertNil(pressingBackspace(in: "word    ", at: 8), "After text, Backspace deletes one space.")
        XCTAssertNil(pressingBackspace(in: "\t\tcode", at: 2, indentUnit: "\t"), "A vault indenting with tabs deletes one tab.")
        XCTAssertNil(pressingBackspace(in: "line", at: 0))
    }

    private func continuingList(_ text: String, atEndOf fragment: String) -> (text: String, cursor: Int)? {
        let location = NSMaxRange((text as NSString).range(of: fragment))
        let edit = MarkdownEditing.continuingList(in: text as NSString, selection: NSRange(location: location, length: 0), indentUnit: "\t")
        return edit.map { edit in ((text as NSString).replacingCharacters(in: edit.range, with: edit.replacement), edit.selectionAfter.location) }
    }

    func testReturnAtTheEndOfAnItemWithChildrenStartsItsFirstChild() {
        let bullets = continuingList("- parent\n\t- child\n- next", atEndOf: "parent")
        XCTAssertEqual(bullets?.text, "- parent\n\t- \n\t- child\n- next", "The children stay under their item.")
        XCTAssertEqual(bullets?.cursor, 12)
        XCTAssertEqual(continuingList("1. a\n\t1. x\n\t2. y\n2. b", atEndOf: "a")?.text, "1. a\n\t1. \n\t2. x\n\t3. y\n2. b",
                       "The children count on after the new first child.")
        XCTAssertEqual(continuingList("- [x] plan\n    - [x] step", atEndOf: "plan")?.text, "- [x] plan\n    - [ ] \n    - [x] step",
                       "A task's child is a new open task, with the child's spaces.")
        XCTAssertEqual(continuingList("> - a\n> \t* b", atEndOf: "a")?.text, "> - a\n> \t* \n> \t* b")
        XCTAssertEqual(continuingList("- parent\n\t- child", atEndOf: "par")?.text, "- par\n- ent\n\t- child",
                       "Inside the item's text, Return splits it as before.")
        XCTAssertEqual(continuingList("- a\n- b", atEndOf: "a")?.text, "- a\n- \n- b", "No child: a sibling as before.")
        XCTAssertEqual(continuingList("- a\n\n\tindented paragraph", atEndOf: "a")?.text, "- a\n- \n\n\tindented paragraph")
    }

    func testReturnInsideAnItemDropsTheSpacesAfterTheCursor() {
        let split = continuingList("- foo bar", atEndOf: "foo")
        XCTAssertEqual(split?.text, "- foo\n- bar", "Not \"-  bar\", as Obsidian drops them too.")
        XCTAssertEqual(split?.cursor, 8)
        XCTAssertEqual(continuingList("1. foo   bar\n2. next", atEndOf: "foo")?.text, "1. foo\n2. bar\n3. next")
        XCTAssertEqual(continuingList("- [ ] foo \tbar", atEndOf: "foo")?.text, "- [ ] foo\n- [ ] bar")
    }
}
