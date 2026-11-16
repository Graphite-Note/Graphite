/**
 * File: WebAddressMenuTests.swift
 * -------------------------------
 * Layer: Tests
 * Description: The editor's menu on a bare web address offers Use Page Title, and Show Preview on a YouTube address,
 *              before Obsidian's link items; elsewhere it does not.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 16/11/2026
 */

import XCTest
import GraphiteCore
@testable import GraphiteUI

@MainActor
final class WebAddressMenuTests: XCTestCase {
    private func firstGroupTitles(text: String, cursor: Int) -> [String] {
        let actions = EditorContextMenuActions(
            run: { _ in }, noteState: { (text as NSString, NSRange(location: cursor, length: 0)) }, apply: { _ in }, insertBlock: { _ in },
            colors: nil, insertColor: { _, _ in }, linkToNote: {}, template: nil)
        guard case .group(let entries)? = EditorContextMenuContent.entries(actions: actions, editorActions: EditorActions()).first?.content else { return [] }
        return entries.map(\.title)
    }

    func testABareYouTubeAddressOffersATitleAndAPreview() {
        let text = "https://www.youtube.com/playlist?list=PLcQYzfBAwuFs"
        XCTAssertEqual(firstGroupTitles(text: text, cursor: 10), ["Use Page Title", "Show Preview"])
    }

    func testAnotherPageOffersOnlyItsTitle() {
        let text = "See https://safari.ethz.ch/projects_and_seminars/fall2026/doku.php?id=modern_ssds"
        XCTAssertEqual(firstGroupTitles(text: text, cursor: 12), ["Use Page Title"])
    }

    func testOutsideAnAddressTheMenuStartsWithObsidiansLinkItems() {
        XCTAssertEqual(firstGroupTitles(text: "See https://example.com here", cursor: 1), ["Add Link", "Add External Link"])
        XCTAssertEqual(firstGroupTitles(text: "[site](https://example.com)", cursor: 10), ["Add Link", "Add External Link"],
                       "A Markdown link's address is not bare.")
    }
}
