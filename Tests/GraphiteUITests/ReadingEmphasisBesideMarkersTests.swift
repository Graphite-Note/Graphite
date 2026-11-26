/**
 * File: ReadingEmphasisBesideMarkersTests.swift
 * ---------------------------------------------
 * Layer: Tests
 * Description: HUNT-374: bold and italic text that begins or ends with inline math, inside a colour, a highlight,
 *              an underline or before a line break, read as bold and italic with no asterisks, as in Obsidian;
 *              and the PDF outline's words of such a heading.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 23/11/2026
 */

import XCTest
import SwiftUI
import GraphiteCore
@testable import GraphiteUI

@MainActor
final class ReadingEmphasisBesideMarkersTests: XCTestCase {
    private static let frame = Character(ReadingMarkerPunctuation.frame)

    /// The reported line (2026-11-20) and the same shape beside each marker the reading view
    /// writes: each read as a `**` or `*` that stayed in the text before.
    func testBoldAndItalicBesideAFormulaInsideMarkersReadWithoutAsterisks() throws {
        let lines: [(markdown: String, emphasized: InlinePresentationIntent, isColored: Bool)] = [
            (#"~={#d29922}**If $C_{GS} \gg (1 + g_mR_D)C_{GD}$**=~"#, .stronglyEmphasized, true),
            (#"~={#3fb950}**$x$ is small**=~"#, .stronglyEmphasized, true),
            (#"~={#d29922}*If $x$*=~"#, .emphasized, true),
            (#"~={#d29922}_If $x$_=~"#, .emphasized, true),
            (#"==**If $x$**=="#, .stronglyEmphasized, false),
            (#"<mark>**If $x$**</mark>"#, .stronglyEmphasized, false),
            (#"<u>**If $x$**</u>"#, .stronglyEmphasized, false),
            (#"**If $x$**<br>next"#, .stronglyEmphasized, false),
        ]
        for line in lines {
            let read = try reading(line.markdown)
            let words = String(read.characters)
            XCTAssertFalse(words.contains("*") || words.hasPrefix("_"), "\(line.markdown) read as \(words)")
            XCTAssertFalse(words.contains(Self.frame), line.markdown)
            let ifRun = try XCTUnwrap(read.runs.first { run in String(read[run.range].characters).contains(line.markdown.contains("If") ? "If" : "is small") },
                                      line.markdown)
            XCTAssertTrue(ifRun.inlinePresentationIntent?.contains(line.emphasized) == true, "\(line.markdown): \(String(describing: ifRun.inlinePresentationIntent))")
            if line.isColored { XCTAssertNotNil(ifRun.foregroundColor, line.markdown) }
        }
    }

    /// Text around the markers reads as before, and a note's own frame character stays,
    /// even next to a colour.
    func testFramesLeaveTheTextAsWritten() throws {
        XCTAssertEqual(String(try reading("a~={#ff0000}b=~c").characters), "abc")
        XCTAssertEqual(String(try reading("~={#ff0000}plain **bold** text=~").characters), "plain bold text")
        XCTAssertEqual(String(try reading("x\u{2E31}~={#ff0000}y=~\u{2E31}z").characters), "x\u{2E31}y\u{2E31}z")
        XCTAssertEqual(String(try reading("a\u{2E31}b").characters), "a\u{2E31}b")
    }

    /// The PDF's outline names such a heading by its words, without asterisks or the colour's hex.
    func testThePDFOutlineNamesAColoredBoldHeadingByItsWords() async throws {
        let prepared = ObsidianInlineMarkup.preparedForReading("~={#d29922}**If $x$ is small**=~", colorsEnabled: true, paletteHexByName: [:])
        let words = await NotePDFTextScan.plainText(of: prepared, root: URL(fileURLWithPath: "/vault", isDirectory: true)) // Nothing is read from the root.
        XCTAssertEqual(words.replacingOccurrences(of: "\\", with: ""), "If $x$ is small")
    }

    private func reading(_ markdown: String) throws -> AttributedString {
        let prepared = ObsidianInlineMarkup.preparedForReading(markdown, colorsEnabled: true, paletteHexByName: [:])
        return try ObsidianMarkdownParser(baseURL: nil, textSize: 17).attributedString(for: prepared)
    }
}
