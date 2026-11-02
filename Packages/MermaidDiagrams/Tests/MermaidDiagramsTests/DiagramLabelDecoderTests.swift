/**
 * File: DiagramLabelDecoderTests.swift
 * ------------------------------------
 * Layer: Tests
 * Description: How the text written for a node, an edge or a group becomes the lines drawn.
 *
 * Authors: Félix Chevalier
 * Version: 0.3
 * Date: 01/11/2026
 */

import XCTest
@testable import MermaidDiagrams

final class DiagramLabelDecoderTests: XCTestCase {
    private func lines(_ text: String, form: DiagramLabelDecoder.Form = .plain) -> [String] {
        DiagramLabelDecoder.label(from: text, form: form).lines
    }

    func testEveryLineBreakTagAndLineBreakEndsALine() {
        XCTAssertEqual(lines("one<br>two<BR/>three<br />four\nfive"), ["one", "two", "three", "four", "five"])
    }

    func testALineBreakTagWithExtraSpacesOrAttributesEndsALineToo() {
        XCTAssertEqual(lines("first<br  />second<BR\t/>third<br class=\"x\">fourth<br/ >fifth"), ["first", "second", "third", "fourth", "fifth"])
        XCTAssertEqual(lines("<brand>kept as a tag</brand> word<br"), ["kept as a tag word<br"])
    }

    func testOtherTagsAreDroppedAndALessThanSignThatStartsNoTagStays() {
        XCTAssertEqual(lines("<b>bold</b> and <span style=\"x\">styled</span>"), ["bold and styled"])
        XCTAssertEqual(lines("a < b and c<5"), ["a < b and c<5"])
    }

    func testMermaidAndHTMLEntityCodesBecomeTheirCharacters() {
        XCTAssertEqual(lines("#quot;quoted#quot; #9829; #35;"), ["\"quoted\" ♥ #"])
        XCTAssertEqual(lines("&lt;tag&gt; &amp; &#65;&#x42;"), ["<tag> & AB"])
    }

    func testAnUnknownEntityOrOneThatIsNoCharacterStaysAsWritten() {
        XCTAssertEqual(lines("#unknown; &nothing; #1114112;"), ["#unknown; &nothing; #1114112;"])
    }

    func testAnEntityCodeIsDecodedAfterTagsAreDroppedSoItsTextStays() {
        XCTAssertEqual(lines("#lt;b#gt;not bold#lt;/b#gt;"), ["<b>not bold</b>"])
    }

    func testAMarkdownStringLosesItsEmphasisMarkersAndKeepsUnderscoresBetweenLetters() {
        XCTAssertEqual(lines("**Bold** and *italic* in snake_case\n__strong__ _Markdown_", form: .markdown),
                       ["Bold and italic in snake_case", "strong Markdown"])
    }

    func testRunsOfSpacesBecomeOneAndLinesAreTrimmed() {
        XCTAssertEqual(lines("  wide \t  gap  "), ["wide gap"])
    }

    func testLiteralTextKeepsItsTagsAndStillBreaksAtBreakTags() {
        XCTAssertEqual(lines("<b>kept</b> &amp; <i>as written</i><br/>next  line", form: .literal), ["<b>kept</b> & <i>as written</i>", "next line"])
        XCTAssertEqual(lines("plain", form: .literal), ["plain"])
    }
}
