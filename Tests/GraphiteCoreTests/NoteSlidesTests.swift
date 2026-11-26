/**
 * File: NoteSlidesTests.swift
 * ---------------------------
 * Layer: Tests
 * Description: A note split into slides by the rule of Obsidian's Slides core plugin: the separators that count,
 *              those that do not, the frontmatter, empty slides and reference links across slides.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

import XCTest
@testable import GraphiteCore

final class NoteSlidesTests: XCTestCase {
    private func slideTexts(_ note: String) -> [String] {
        NoteSlides.slides(in: note).map { slide in slide.markdown.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    func testANoteWithoutSeparatorsIsOneSlide() {
        XCTAssertEqual(slideTexts("# Title\n\nSome text.\n"), ["# Title\n\nSome text."])
    }

    func testEveryThematicBreakFormSeparatesSlides() {
        let note = "One\n\n---\n\nTwo\n\n***\n\nThree\n\n___\n\nFour\n\n- - -\n\nFive\n\n  ---  \n\nSix\n"
        XCTAssertEqual(slideTexts(note), ["One", "Two", "Three", "Four", "Five", "Six"])
    }

    func testADashLineUnderAParagraphUnderlinesAHeadingAndSeparatesNothing() {
        XCTAssertEqual(slideTexts("Heading\n---\nText\n"), ["Heading\n---\nText"])
        // After a heading, a list or a blank line, the same line separates.
        XCTAssertEqual(slideTexts("# Heading\n---\nText\n"), ["# Heading", "Text"])
        XCTAssertEqual(slideTexts("- item\n---\nText\n"), ["- item", "Text"])
    }

    func testSeparatorsInCodeMathQuotesCalloutsAndCommentsAreText() {
        let code = "```\n---\n```"
        let math = "$$\nx\n---\ny\n$$"
        let quote = "> quoted\n> ---\n> more"
        let callout = "> [!note] Title\n> ---\n> body"
        let comment = "%%\n---\n%%\nAfter"
        for block in [code, math, quote, callout, comment] {
            XCTAssertEqual(NoteSlides.slides(in: block + "\n").count, 1, block)
        }
    }

    func testASeparatorIndentedInAListItemBelongsToTheItem() {
        XCTAssertEqual(NoteSlides.slides(in: "- item\n\n  ---\n\n  still the item\n").count, 1)
        XCTAssertEqual(NoteSlides.slides(in: "1. item\n\n   ***\n").count, 1)
        // Not indented as far as the item's text, it ends the list.
        XCTAssertEqual(slideTexts("1. item\n\n  ---\n\nAfter\n"), ["1. item", "After"])
    }

    func testFourSpacesMakeCodeNotASeparator() {
        XCTAssertEqual(NoteSlides.slides(in: "Text\n\n    ---\n").count, 1)
    }

    func testTheFrontmatterIsLeftOutAndAnEmptySlideIsSkipped() {
        let note = "---\ntitle: Talk\n---\n\n---\n\nFirst\n\n---\n\n---\n\n%% only a comment %%\n\n---\n\nLast\n"
        XCTAssertEqual(slideTexts(note), ["First", "Last"])
    }

    func testANoteWithNothingToDrawHasNoSlides() {
        XCTAssertEqual(NoteSlides.slides(in: "---\ntags: [a]\n---\n").count, 0)
        XCTAssertEqual(NoteSlides.slides(in: "\n\n---\n\n").count, 0)
    }

    func testEachSlideKeepsItsRangeInTheNote() throws {
        let note = "---\na: 1\n---\nOne\n\n---\n\nTwo\n"
        let slides = NoteSlides.slides(in: note)
        XCTAssertEqual(slides.count, 2)
        let text = note as NSString
        XCTAssertEqual(text.substring(with: slides[0].noteRange), "One\n\n")
        XCTAssertEqual(text.substring(with: slides[1].noteRange), "\nTwo\n")
        XCTAssertEqual(slides[0].noteRange.location, ("---\na: 1\n---\n" as NSString).length)
    }

    func testWindowsLineEndingsSeparateTheSame() {
        XCTAssertEqual(slideTexts("One\r\n\r\n---\r\n\r\nTwo\r\n"), ["One", "Two"])
    }

    func testAReferenceLinkFindsItsDefinitionOnAnotherSlide() {
        let note = "See [the paper][ref].\n\n---\n\nSources\n\n[ref]: https://example.org/paper\n"
        let slides = NoteSlides.slides(in: note)
        XCTAssertEqual(slides.count, 2)
        XCTAssertTrue(slides[0].markdown.hasSuffix("[ref]: https://example.org/paper"), slides[0].markdown)
        // The slide that defines it is not given it twice.
        XCTAssertEqual(slides[1].markdown.components(separatedBy: "[ref]:").count, 2)
    }
}
