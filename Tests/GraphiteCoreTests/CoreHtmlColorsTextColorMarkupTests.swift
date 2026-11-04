/**
 * File: CoreHtmlColorsTextColorMarkupTests.swift
 * ----------------------------------------------
 * Layer: Tests
 * Description: Regression tests for colors that ran past their block or were hidden by code and math.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 04/11/2026
 */

import XCTest
@testable import GraphiteCore
import GraphiteTestSupport

/// Regression tests for colors that ran past their block or were hidden by code and math.
final class CoreHtmlColorsTextColorMarkupTests: XCTestCase {
    private func coloredTexts(_ source: String) -> [String] {
        let text = source as NSString
        return TextColorMarkup.sections(in: text).map { section in text.substring(with: section.contentRange) }
    }

    func testColorEndsWithAQuotedListItemOrHeading() {
        XCTAssertEqual(coloredTexts("> - ~={#ff0000}first\n> - second"), ["first"])
        XCTAssertEqual(coloredTexts("> ## ~={#ff0000}Heading\n> Body"), ["Heading"])
        XCTAssertEqual(coloredTexts("> ~={#ff0000}quoted\n>\n> next paragraph"), ["quoted"], "A quoted blank line ends the paragraph.")
        XCTAssertEqual(coloredTexts("> ~={#ff0000}lazy\ncontinuation"), ["lazy\ncontinuation"], "A lazy continuation line stays in the quote's paragraph.")
    }

    func testQuoteAfterAParagraphIsABlockOfItsOwn() {
        XCTAssertEqual(coloredTexts("~={#ff0000}para\n> quote"), ["para"])
        XCTAssertEqual(coloredTexts("> ~={#ff0000}outer\n> > inner"), ["outer"])
    }

    func testFenceInterruptingAParagraphEndsTheColor() {
        XCTAssertEqual(coloredTexts("~={#ff0000}text\n```\ncode\n```\nmore=~"), ["text"])
        XCTAssertEqual(coloredTexts("~={#ff0000}text\n$$\nx\n$$\nmore=~"), ["text"])
    }

    func testTableWithoutOuterPipesSplitsIntoCells() {
        XCTAssertEqual(coloredTexts("a | ~={#ff0000}b | c\n--- | --- | ---"), ["b"])
        XCTAssertEqual(coloredTexts("a | b\n--- | ---\n~={#ff0000}c | d"), ["c"])
        XCTAssertEqual(coloredTexts("| a | b |\n--- | ---\n~={#ff0000}c | d"), ["c"])
        XCTAssertEqual(coloredTexts("Intro ~={#ff0000}text\na | b\n--- | ---"), ["text"], "The paragraph before the header row stays a paragraph.")
        XCTAssertEqual(coloredTexts("~={#ff0000}a | b\nnot a delimiter"), ["a | b\nnot a delimiter"], "Without a delimiter row, a pipe is text.")
    }

    func testHeadingAfterAByteOrderMark() {
        XCTAssertEqual(coloredTexts("\u{FEFF}# ~={#ff0000}Heading\nBody"), ["Heading"])
    }

    func testSetextHeadingAndThematicBreakEndTheColor() {
        XCTAssertEqual(coloredTexts("~={#ff0000}Title\n===\nBody"), ["Title"])
        XCTAssertEqual(coloredTexts("~={#ff0000}above\n\n***\nbelow"), ["above"])
    }

    func testDollarSignsInCodeSpansDoNotPairAsMath() {
        XCTAssertEqual(coloredTexts("`$HOME` ~={#ff0000}red=~ `$PATH`"), ["red"])
        XCTAssertEqual(coloredTexts("`$a` $x$ ~={#ff0000}$y$=~ `$b`"), ["$y$"], "Math between code spans is still math.")
        XCTAssertTrue(coloredTexts("`$a` $~={#ff0000}x=~$ `$b`").isEmpty, "Markers inside math between code spans are not markup.")
    }

    func testBacktickLineWithABacktickInItsInfoStringIsNotAFence() {
        XCTAssertEqual(coloredTexts("```inline```\n~={#ff0000}red=~"), ["red"])
        XCTAssertTrue(coloredTexts("~~~ info with ` backtick\n~={#ff0000}code=~\n~~~").isEmpty, "A tilde fence may have backticks in its info string.")
    }

    func testPaletteNameWinsOverHexLetters() {
        let text = "~={ace}named=~ ~={#ace}hex=~ ~={bad}unnamed=~" as NSString
        let colors = TextColorMarkup.sections(in: text, paletteHexByName: ["ace": "#123456"]).map(\.hexColor)
        XCTAssertEqual(colors, ["#123456", "#aaccee", "#bbaadd"])
    }

    func testCodeInsideQuotesAndIndentedCodeIsNotColored() {
        XCTAssertTrue(coloredTexts("> ```\n> ~={#ff0000}code=~\n> ```").isEmpty)
        XCTAssertTrue(coloredTexts("    ~={#ff0000}indented code=~").isEmpty)
        XCTAssertTrue(coloredTexts("Text\n\n\t~={#ff0000}tab indented=~").isEmpty)
        XCTAssertTrue(coloredTexts(">     ~={#ff0000}quoted indented=~").isEmpty)
        XCTAssertEqual(coloredTexts("Text\n    ~={#ff0000}continuation=~"), ["continuation"], "Indented code cannot interrupt a paragraph.")
        XCTAssertEqual(coloredTexts("- item\n\n    ~={#ff0000}item text=~"), ["item text"], "Indented lines in a list item are its text.")
        XCTAssertEqual(coloredTexts("    code\n~={#ff0000}after=~"), ["after"])
        XCTAssertEqual(coloredTexts("> ```\n> code\n\n~={#ff0000}after=~"), ["after"], "A fence in a quote ends with the quote.")
        XCTAssertTrue(coloredTexts("```\n> ```\n~={#ff0000}x=~\n```").isEmpty, "A quoted fence line does not close an unquoted fence.")
        XCTAssertEqual(coloredTexts("> para\n    ~={#ff0000}lazy=~"), ["lazy"], "An indented line after a quoted paragraph continues it.")
        XCTAssertTrue(coloredTexts("> para\n>\n    ~={#ff0000}code=~").isEmpty, "After the quote's blank line it is code.")
    }

    func testDisplayMathFollowedByTextOnItsLineIsClosed() {
        XCTAssertEqual(coloredTexts("$$E=mc^2$$ is famous\n\n~={#ff0000}red=~"), ["red"])
    }

    func testDenseColorsParseQuickly() {
        let line = "Line with `code $x$` and $y+1$ with ~={#ff0000}red=~ and ~={#00ff00}green=~ text.\n"
        let text = String(repeating: line, count: 8_000) as NSString
        XCTAssertEqual(TextColorMarkup.sections(in: text).count, 16_000)
        // Every marker scanned every code span and formula in the note: this took about five seconds, some 2,500 times a
        // plain pass that reads the same text line by line, as the parse does. The parse is about 40 times that pass in a
        // debug build. It is timed against the pass, made on the same machine a moment before, and not as a ratio of two
        // sizes: GitHub's loaded runners put that ratio anywhere from 4.3 to 8.1 for the same linear code (2026-11-03 and
        // 04), against a limit of 8.
        ScalingChecks.assertNoSlowerThan(factor: 250, reference: {
            var lineStart = 0, lineCount = 0
            while lineStart < text.length {
                let lineRange = text.lineRange(for: NSRange(location: lineStart, length: 0))
                if text.substring(with: lineRange).hasPrefix("Line") { lineCount += 1 }
                lineStart = NSMaxRange(lineRange)
            }
            XCTAssertEqual(lineCount, 8_000)
        }, "dense colors, 8,000 lines", work: { _ = TextColorMarkup.sections(in: text) })
    }
}
