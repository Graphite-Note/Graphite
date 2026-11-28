/**
 * File: HTMLColorSpansTests.swift
 * -------------------------------
 * Layer: Tests
 * Description: Inline HTML colour spans, as the Notion importer writes Notion's colours, are found, marked for the reading
 *              view, recoloured and removed, and spans in code stay text.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 28/11/2026
 */

import XCTest
@testable import GraphiteCore

final class HTMLColorSpansTests: XCTestCase {
    private func applying(_ edit: MarkdownTextEdit?, to text: String) -> String {
        guard let edit else { return text }
        return (text as NSString).replacingCharacters(in: edit.range, with: edit.replacement)
    }

    func testColourAndBackgroundSpansAreFoundWithTheirText() {
        let text = "A <span style=\"color:#E03E3E\">red</span> and <span style='background-color: #FBF3DB; font-weight:600'>pale</span> word." as NSString
        let spans = HTMLColorSpans.spans(in: text)
        XCTAssertEqual(spans.count, 2)
        XCTAssertEqual(spans[0].textHex, "#e03e3e")
        XCTAssertNil(spans[0].backgroundHex)
        XCTAssertEqual(text.substring(with: spans[0].contentRange), "red")
        XCTAssertEqual(spans[1].backgroundHex, "#fbf3db")
        XCTAssertEqual(text.substring(with: spans[1].contentRange), "pale")
    }

    func testCSSColourFormsAreRead() {
        XCTAssertEqual(HTMLColorSpans.hex(ofCSSColor: "#0b6"), "#00bb66")
        XCTAssertEqual(HTMLColorSpans.hex(ofCSSColor: "rgb(224, 62, 62)"), "#e03e3e")
        XCTAssertEqual(HTMLColorSpans.hex(ofCSSColor: "rgba(224, 62, 62, 0.5)"), "#e03e3e80")
        XCTAssertEqual(HTMLColorSpans.hex(ofCSSColor: "#E03E3E !important"), "#e03e3e")
        XCTAssertNil(HTMLColorSpans.hex(ofCSSColor: "red"), "Named colours are not read.")
        XCTAssertNil(HTMLColorSpans.hex(ofCSSColor: "rgb(300, 0, 0)"))
    }

    func testNestedSpansCodeAndUnclosedSpans() {
        let nested = "<span style=\"color:#111111\">a <span style=\"color:#222222\">b</span> c</span>" as NSString
        let spans = HTMLColorSpans.spans(in: nested)
        XCTAssertEqual(spans.map(\.textHex), ["#111111", "#222222"])
        XCTAssertEqual(spans.map(\.depth), [0, 1], "The inner span is deeper and wins.")
        XCTAssertTrue(HTMLColorSpans.spans(in: "`<span style=\"color:#e03e3e\">x</span>`" as NSString).isEmpty, "A span in code is text.")
        XCTAssertTrue(HTMLColorSpans.spans(in: "<span style=\"color:#e03e3e\">never closed" as NSString).isEmpty)
        XCTAssertTrue(HTMLColorSpans.spans(in: "<span class=\"x\">no colour</span>" as NSString).isEmpty)
    }

    func testTheReadingViewGetsColourAndBackgroundMarkers() {
        let marked = ReadingInlineHTML.markingColorSpans(in: "<span style=\"color:#e03e3e;background-color:#fbf3db\">both</span>!")
        let expected = String(ReadingMarkers.colorStartMarker) + "#e03e3e" + String(ReadingMarkers.colorHexEndMarker)
            + String(ReadingMarkers.backgroundStartMarker) + "#fbf3db" + String(ReadingMarkers.colorHexEndMarker) + "both"
            + String(ReadingMarkers.backgroundEndMarker) + String(ReadingMarkers.colorEndMarker) + "!"
        XCTAssertEqual(marked, expected)
    }

    func testANotesOwnBackgroundMarkerCharacterIsEscaped() {
        let own = "icon \u{E00E} glyph"
        XCTAssertFalse(ReadingMarkers.escaping(own).contains(ReadingMarkers.backgroundEndMarker))
    }

    func testTheColourCommandRecoloursASpanKeepingItsOtherStyle() {
        let note = "See <span style=\"color:#e03e3e; font-weight:600\">this</span> now."
        let cursor = NSRange(location: (note as NSString).range(of: "this").location + 1, length: 0)
        let recolored = applying(HTMLColorSpans.recoloring(in: note as NSString, selection: cursor, hex: "#0B6E99"), to: note)
        XCTAssertEqual(recolored, "See <span style=\"font-weight:600;color:#0b6e99\">this</span> now.")
        XCTAssertNil(HTMLColorSpans.recoloring(in: note as NSString, selection: NSRange(location: 0, length: 0), hex: "#0b6e99"), "Outside a span.")
    }

    func testRemoveTakesTheColoursOutAndTheSpanWhenNothingElseIsLeft() {
        let note = "See <span style=\"color:#e03e3e\">this</span> now."
        let cursor = NSRange(location: (note as NSString).range(of: "this").location + 2, length: 0)
        let edit = HTMLColorSpans.removingColor(in: note as NSString, selection: cursor)
        XCTAssertEqual(applying(edit, to: note), "See this now.")
        XCTAssertEqual(edit?.selectionAfter, NSRange(location: 6, length: 0), "The cursor stays in the word.")
        let styled = "<span style=\"color:#e03e3e;font-style:italic\">x</span>"
        XCTAssertEqual(applying(HTMLColorSpans.removingColor(in: styled as NSString, selection: NSRange(location: 47, length: 0)), to: styled),
                       "<span style=\"font-style:italic\">x</span>")
    }
}
