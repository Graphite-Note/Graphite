/**
 * File: FrontmatterCompletionTests.swift
 * --------------------------------------
 * Layer: Tests
 * Description: What is being typed in a note's frontmatter: a name at a line's start, a value after `name: `, list items
 *              and inline lists, quoted values, links in values, and the body just after the closing `---`.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 16/11/2026
 */

import XCTest
import GraphiteCore

final class FrontmatterCompletionTests: XCTestCase {
    /// The context with the cursor where `|` is written in `marked`.
    private func context(_ marked: String) -> CompletionContext? {
        let cursor = (marked as NSString).range(of: "|").location
        let text = (marked as NSString).replacingCharacters(in: NSRange(location: cursor, length: 1), with: "")
        return LinkCompletion.context(in: text as NSString, cursor: cursor)
    }

    func testANameTypedAtTheStartOfALineSuggestsNamesAndLeavesOutTheNotesOthers() {
        XCTAssertEqual(context("---\ntitle: Notes\ncou|\n---\nBody"),
                       .propertyName(query: "cou", replacementRange: NSRange(location: 17, length: 3), writtenNames: ["title"]))
        // The rest of the name and its `: ` are replaced too, so a suggestion does not double the colon.
        XCTAssertEqual(context("---\ncou|rse: VLSI\n---\n"),
                       .propertyName(query: "cou", replacementRange: NSRange(location: 4, length: 8), writtenNames: []))
    }

    func testAValueAfterTheNameSuggestsThatPropertysValues() {
        XCTAssertEqual(context("---\ncourse: VL|\n---\n"),
                       .propertyValue(name: "course", query: "VL", replacementRange: NSRange(location: 12, length: 2), writtenValues: []))
        XCTAssertEqual(context("---\ncourse: \"VL|\"\n---\n"),
                       .propertyValue(name: "course", query: "VL", replacementRange: NSRange(location: 13, length: 2), writtenValues: []),
                       "An opening quote is not part of the value, and the closing one stays.")
        XCTAssertEqual(context("---\ncourse: |\n---\n"),
                       .propertyValue(name: "course", query: "", replacementRange: NSRange(location: 12, length: 0), writtenValues: []))
    }

    func testListItemsUnderANameSuggestItsValuesAndLeaveOutTheOtherItems() {
        XCTAssertEqual(context("---\ntags:\n  - exam\n  - cou|\n---\n"),
                       .propertyValue(name: "tags", query: "cou", replacementRange: NSRange(location: 23, length: 3), writtenValues: ["exam"]))
        XCTAssertEqual(context("---\ntags:\n- |\n- later\n---\n"),
                       .propertyValue(name: "tags", query: "", replacementRange: NSRange(location: 12, length: 0), writtenValues: ["later"]))
    }

    func testAnInlineListSuggestsForTheItemBeingTyped() {
        XCTAssertEqual(context("---\ntags: [exam, cou|]\n---\n"),
                       .propertyValue(name: "tags", query: "cou", replacementRange: NSRange(location: 17, length: 3), writtenValues: ["exam"]))
        XCTAssertNil(context("---\ntags: [exam, course]|\n---\n"), "After the closing bracket nothing is being typed.")
    }

    func testALinkInAValueIsStillALinkAndACommentIsNothing() {
        guard case .link(let query) = context("---\nrelated: \"[[Lec|\"\n---\n") else { return XCTFail("A link in a value suggests notes.") }
        XCTAssertEqual(query.text, "Lec")
        XCTAssertNil(context("---\ncourse: VLSI # a no|\n---\n"))
        XCTAssertNil(context("---\n# a comment wi|\n---\n"))
    }

    func testTheBodyAndAnUnclosedBlockAreNotTheFrontmatter() {
        XCTAssertEqual(context("---\ncourse: VLSI\n---\n#ex|"), .tag(query: "ex", replacementRange: NSRange(location: 22, length: 2)),
                       "Just after the closing fence is the body, where `#` starts a tag.")
        XCTAssertNil(context("---\ncou|"), "A block that is not closed is not the frontmatter yet.")
        XCTAssertNil(context("Intro\n---\ncou|\n---\n"), "Frontmatter opens on the note's first line only.")
    }
}
