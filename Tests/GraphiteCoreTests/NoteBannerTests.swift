/**
 * File: NoteBannerTests.swift
 * ---------------------------
 * Layer: Tests
 * Description: A note's `banner` property is read in every form the Banners and Pixel Banner plugins write it, with
 *              their vertical positions, and forms Graphite cannot show give no banner.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

import XCTest
@testable import GraphiteCore

final class NoteBannerTests: XCTestCase {
    private func banner(_ yaml: String) -> NoteBanner? {
        NoteBanner(properties: NoteProperties.parse(yaml) ?? [])
    }

    func testWikiLinksAndEmbedsNameAVaultFile() {
        XCTAssertEqual(banner("banner: \"[[Covers/lecture.jpg]]\"")?.source, .vaultFile(linkTarget: "Covers/lecture.jpg"))
        XCTAssertEqual(banner("banner: \"![[lecture.jpg]]\"")?.source, .vaultFile(linkTarget: "lecture.jpg"))
        XCTAssertEqual(banner("banner: \"[[lecture.jpg|Cover]]\"")?.source, .vaultFile(linkTarget: "lecture.jpg"))
    }

    func testAnUnquotedWikiLinkThatYAMLReadsAsAListStillNamesTheFile() {
        XCTAssertEqual(banner("banner: [[lecture.jpg]]")?.source, .vaultFile(linkTarget: "lecture.jpg"))
    }

    func testMarkdownLinksAndPlainPathsNameAVaultFile() {
        XCTAssertEqual(banner("banner: \"![](Covers/My%20Cover.png)\"")?.source, .vaultFile(linkTarget: "Covers/My Cover.png"))
        XCTAssertEqual(banner("banner: \"[title](cover.webp)\"")?.source, .vaultFile(linkTarget: "cover.webp"))
        XCTAssertEqual(banner("banner: Covers/cover.jpg")?.source, .vaultFile(linkTarget: "Covers/cover.jpg"))
    }

    func testAWebAddressIsAPictureOnTheWeb() throws {
        let address = try XCTUnwrap(URL(string: "https://example.com/image.jpg"))
        XCTAssertEqual(banner("banner: https://example.com/image.jpg")?.source, .webAddress(address))
    }

    func testFormsGraphiteCannotShowGiveNoBanner() {
        XCTAssertNil(banner("banner: sunset beach"), "Pixel Banner's search words need its online service.")
        XCTAssertNil(banner("banner: file:///Users/someone/Pictures/banner.jpg"), "A file outside the vault.")
        XCTAssertNil(banner("banner: notes.md"), "Not a picture.")
        XCTAssertNil(banner("banner: \"\""))
        XCTAssertNil(banner("title: Lecture"))
    }

    func testBannersAndPixelBannersVerticalPositionsAreFractions() {
        XCTAssertEqual(banner("banner: a.jpg\nbanner_y: 0.2")?.verticalFocus, 0.2)
        XCTAssertEqual(banner("banner: a.jpg\nbanner-y: 30")?.verticalFocus ?? 0, 0.3, accuracy: 0.0001)
        XCTAssertEqual(banner("banner: a.jpg\nbanner_y: 4")?.verticalFocus, 1, "Kept inside the picture.")
        XCTAssertEqual(banner("banner: a.jpg")?.verticalFocus, NoteBanner.defaultVerticalFocus)
    }
}
