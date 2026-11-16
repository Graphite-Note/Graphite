/**
 * File: BareWebAddressTests.swift
 * -------------------------------
 * Layer: Tests
 * Description: Bare web addresses in note text are found, styled and followed as links, as the reading view links them.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 16/11/2026
 */

import XCTest
@testable import GraphiteCore

final class BareWebAddressTests: XCTestCase {
    private func addresses(in line: String) -> [String] {
        WebAddressSyntax.addresses(in: line).map { address in (line as NSString).substring(with: address.range) }
    }

    private func linkText(in line: String) -> [String] {
        let source = line as NSString
        return MarkdownStyleScanner.spans(in: source, range: NSRange(location: 0, length: source.length))
            .filter { span in span.style == .link }.map { span in source.substring(with: span.range) }
    }

    func testTheRequestsPlaylistAddressesAreFoundWhole() throws {
        let playlist = "https://www.youtube.com/playlist?list=PL5Q2soXY2Zi9OtbGJyUVHp1Gp3c_0Dymh"
        XCTAssertEqual(addresses(in: playlist), [playlist], "An address alone on its line, its `_` included.")
        let course = "https://safari.ethz.ch/projects_and_seminars/fall2026/doku.php?id=modern_ssds"
        XCTAssertEqual(try XCTUnwrap(WebAddressSyntax.addresses(in: course).first).location, URL(string: course))
    }

    func testAnAddressEndsWhereGFMEndsIt() {
        XCTAssertEqual(addresses(in: "See https://example.com/page."), ["https://example.com/page"], "A full stop ends the sentence.")
        XCTAssertEqual(addresses(in: "Is it https://example.com?"), ["https://example.com"])
        XCTAssertEqual(addresses(in: "(see https://example.com/a)"), ["https://example.com/a"], "An unbalanced parenthesis is not the address's.")
        XCTAssertEqual(addresses(in: "https://en.wikipedia.org/wiki/Bit_(unit)"), ["https://en.wikipedia.org/wiki/Bit_(unit)"],
                       "A balanced parenthesis is.")
        XCTAssertEqual(addresses(in: "Two: https://a.ch and www.b.ch, then <https://c.ch>"), ["https://a.ch", "www.b.ch", "https://c.ch"])
        XCTAssertEqual(addresses(in: "Just https:// or www. typed"), [], "A scheme or `www.` alone is not an address yet.")
        XCTAssertEqual(addresses(in: "mail me at someone@www.example.com, file:///tmp"), [], "Only http, https and www. addresses.")
    }

    func testAWWWAddressOpensOverHTTPS() throws {
        XCTAssertEqual(try XCTUnwrap(WebAddressSyntax.addresses(in: "www.example.com/x").first).location, URL(string: "https://www.example.com/x"))
    }

    func testTheEditorStylesABareAddressAsALinkAndNotItsUnderscoresOrHash() {
        let line = "Watch https://example.com/a_b_c#part_two and *this*"
        XCTAssertEqual(linkText(in: line), ["https://example.com/a_b_c#part_two"])
        let source = line as NSString
        let spans = MarkdownStyleScanner.spans(in: source, range: NSRange(location: 0, length: source.length))
        XCTAssertFalse(spans.contains { span in span.style == .tag || span.style == .emphasis && source.substring(with: span.range).contains("b") },
                       "The address's `#` and `_` are not a tag or emphasis.")
        XCTAssertTrue(spans.contains { span in span.style == .emphasis && source.substring(with: span.range) == "this" })
    }

    func testAnAddressInCodeOrInALinkIsNotALinkOfItsOwn() {
        XCTAssertEqual(linkText(in: "Run `curl https://example.com` now"), [])
        XCTAssertEqual(linkText(in: "[the site](https://example.com) here"), ["the site"])
    }

    func testATapOnABareAddressFollowsIt() throws {
        let line = "Lectures: https://www.youtube.com/playlist?list=PLcQYzfBAwuFs."
        let source = line as NSString
        let start = source.range(of: "https").location
        let located = try XCTUnwrap(LinkLocator.locatedLink(in: line, at: start + 10, includesEnd: false))
        XCTAssertEqual(located.link, .web(try XCTUnwrap(URL(string: "https://www.youtube.com/playlist?list=PLcQYzfBAwuFs"))))
        XCTAssertEqual(source.substring(with: located.range), "https://www.youtube.com/playlist?list=PLcQYzfBAwuFs")
        XCTAssertNil(LinkLocator.link(in: line, at: source.length - 1, includesEnd: false), "The full stop is not the address's.")
        XCTAssertNotNil(LinkLocator.link(in: line, at: NSMaxRange(located.range), includesEnd: true), "The cursor right after it counts when asked.")
    }

    func testAnAddressInsideAnEmbedOrALinkIsNotFollowedOnItsOwn() throws {
        let embed = "![](https://www.youtube.com/watch?v=abc)"
        XCTAssertNil(LinkLocator.link(in: embed, at: 10, includesEnd: false), "An embed is not a link to follow.")
        let markdownLink = "[https://example.com](https://example.org)"
        XCTAssertEqual(LinkLocator.link(in: markdownLink, at: 5, includesEnd: false), .web(try XCTUnwrap(URL(string: "https://example.org"))),
                       "A link's text that reads as an address follows the link's destination.")
    }
}
