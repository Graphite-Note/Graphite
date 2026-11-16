/**
 * File: EmbedWidthEditingTests.swift
 * ----------------------------------
 * Layer: Core tests
 * Description: Checks the width a dragged image corner writes into an embed's source.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 16/11/2026
 */

import XCTest
@testable import GraphiteCore

/// Dragging an image's corner writes its width as Obsidian does, and nothing else.
final class EmbedWidthEditingTests: XCTestCase {
    func testAWikiEmbedWithoutASizeGetsOne() {
        XCTAssertEqual(EmbedWidthEditing.settingWidth(320, ofEmbedOf: "photo.png", in: "![[photo.png]]"), "![[photo.png|320]]")
    }

    func testAWikiEmbedsSizeIsReplacedHeightAndAll() {
        XCTAssertEqual(EmbedWidthEditing.settingWidth(320, ofEmbedOf: "photo.png", in: "![[photo.png|500]]"), "![[photo.png|320]]")
        XCTAssertEqual(EmbedWidthEditing.settingWidth(320, ofEmbedOf: "photo.png", in: "![[photo.png|500x200]]"), "![[photo.png|320]]")
    }

    func testAWikiEmbedsCaptionIsKeptBeforeTheSize() {
        XCTAssertEqual(EmbedWidthEditing.settingWidth(320, ofEmbedOf: "photo.png", in: "![[photo.png|A cat]]"), "![[photo.png|A cat|320]]")
        XCTAssertEqual(EmbedWidthEditing.settingWidth(320, ofEmbedOf: "photo.png", in: "![[photo.png|A cat|500]]"), "![[photo.png|A cat|320]]")
    }

    func testAMarkdownEmbedGetsItsWidthInItsLabel() {
        XCTAssertEqual(EmbedWidthEditing.settingWidth(320, ofEmbedOf: "photo.png", in: "![](photo.png)"), "![320](photo.png)")
        XCTAssertEqual(EmbedWidthEditing.settingWidth(320, ofEmbedOf: "photo.png", in: "![A cat](photo.png)"), "![A cat|320](photo.png)")
        XCTAssertEqual(EmbedWidthEditing.settingWidth(320, ofEmbedOf: "photo.png", in: "![A cat|500](photo.png \"Title\")"),
                       "![A cat|320](photo.png \"Title\")")
    }

    func testWhatSurroundsTheEmbedIsKept() {
        XCTAssertEqual(EmbedWidthEditing.settingWidth(320, ofEmbedOf: "Folder/photo.png", in: "  ![[Folder/photo.png|500]]  \n"),
                       "  ![[Folder/photo.png|320]]  \n")
        XCTAssertEqual(EmbedWidthEditing.settingWidth(320, ofEmbedOf: "photo.png", in: "- ![[photo.png]]"), "- ![[photo.png|320]]")
    }

    func testAnotherEmbedOrAWidthThatIsNoSizeLeavesTheSourceAlone() {
        XCTAssertNil(EmbedWidthEditing.settingWidth(320, ofEmbedOf: "photo.png", in: "![[other.png]]"), "The note changed under the drag.")
        XCTAssertNil(EmbedWidthEditing.settingWidth(320, ofEmbedOf: "photo.png", in: "No embed here"))
        XCTAssertNil(EmbedWidthEditing.settingWidth(0, ofEmbedOf: "photo.png", in: "![[photo.png]]"))
        XCTAssertNil(EmbedWidthEditing.settingWidth(10_001, ofEmbedOf: "photo.png", in: "![[photo.png]]"))
    }

    func testTheWrittenWidthIsReadBack() throws {
        for source in ["![[photo.png]]", "![[photo.png|A cat|500x200]]", "![](photo.png)", "![A cat](photo.png)"] {
            let written = try XCTUnwrap(EmbedWidthEditing.settingWidth(275, ofEmbedOf: "photo.png", in: source))
            let embed = try XCTUnwrap(EmbedLocator.embed(at: 2, in: written as NSString))
            XCTAssertEqual(embed.displaySize, EmbedDisplaySize(width: 275, height: nil), source)
            XCTAssertEqual(embed.target, "photo.png", source)
        }
    }
}
