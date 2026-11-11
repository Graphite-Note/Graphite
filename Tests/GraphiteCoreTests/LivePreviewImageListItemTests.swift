/**
 * File: LivePreviewImageListItemTests.swift
 * -----------------------------------------
 * Layer: Tests
 * Description: A list item that embeds images is one Live Preview block of its marker, text and pictures, as a
 *              paragraph line of images is; tasks, quoted items and indented code keep their text, and the
 *              Markdown embeds of a table or callout are found with their sizes (issue #102).
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 11/11/2026
 */

import XCTest
@testable import GraphiteCore

final class LivePreviewImageListItemTests: XCTestCase {
    private func pieces(ofOnlyBlockIn text: String) throws -> [ImageLinePiece] {
        let blocks = LivePreviewBlockScanner.blocks(in: text as NSString)
        let block = try XCTUnwrap(blocks.first, "No block in \(text)")
        XCTAssertEqual(blocks.count, 1, text)
        guard case .imageLine(let pieces) = block.kind else {
            XCTFail("\(text) is no line of images: \(block.kind)")
            return []
        }
        return pieces
    }

    private func images(in pieces: [ImageLinePiece]) -> [EmbedReference] {
        pieces.compactMap { piece in if case .image(let embed) = piece { embed } else { nil } }
    }

    // MARK: List items

    func testABulletItemOfTwoPhotosIsItsMarkerThenThePhotosAtTheirSizes() throws {
        let line = "- ![[IMG_3599.jpg|300]] ![[IMG_3598.PNG|200]]"
        let pieces = try pieces(ofOnlyBlockIn: line)
        XCTAssertEqual(pieces.first, .listMarker(ImageLineListMarker(indentation: "", marker: "-", spacing: " ")))
        let embeds = images(in: pieces)
        XCTAssertEqual(embeds.map(\.target), ["IMG_3599.jpg", "IMG_3598.PNG"])
        XCTAssertEqual(embeds.map(\.displayWidth), [300, 200])
        // The embeds keep their places in the line, the marker counted.
        XCTAssertEqual(embeds.map(\.range), [NSRange(location: 2, length: 21), NSRange(location: 24, length: 21)])
        XCTAssertEqual(pieces.count, 3, "Nothing but the marker and the two pictures: \(pieces)")
    }

    func testANumberedItemWithACaptionAndAMarkdownImageKeepsItsNumberAndText() throws {
        let pieces = try pieces(ofOnlyBlockIn: "12. Before ![photo|120](Photos/a.JPG) after")
        XCTAssertEqual(pieces, [
            .listMarker(ImageLineListMarker(indentation: "", marker: "12.", spacing: " ")),
            .text("Before"),
            .image(EmbedReference(target: "Photos/a.JPG", isWiki: false, displaySize: EmbedDisplaySize(width: 120, height: nil),
                                  range: NSRange(location: 11, length: 26))),
            .text("after"),
        ])
    }

    func testANestedItemKeepsItsIndentationEvenPastFourColumns() throws {
        let text = "- Photos\n    - ![[a.png|100]] ![[b.png|100]]\n"
        let blocks = LivePreviewBlockScanner.blocks(in: text as NSString)
        XCTAssertEqual(blocks.count, 1)
        guard case .imageLine(let pieces)? = blocks.first?.kind else { return XCTFail("The nested item is a line of images: \(blocks)") }
        XCTAssertEqual(pieces.first, .listMarker(ImageLineListMarker(indentation: "    ", marker: "-", spacing: " ")))
        XCTAssertEqual(blocks.first?.range, NSRange(location: 9, length: 36))
    }

    func testAnItemOfOneImageIsALineOfThatImageBesideItsBullet() throws {
        let pieces = try pieces(ofOnlyBlockIn: "* ![[a.png|200]]")
        XCTAssertEqual(pieces.count, 2)
        XCTAssertEqual(images(in: pieces).map(\.target), ["a.png"])
    }

    func testTasksQuotedItemsIndentedCodeAndItemsWithoutImagesKeepTheirText() {
        for text in ["- [ ] ![[a.png|100]] ![[b.png|100]]", "- [x] ![[a.png]]", "> - ![[a.png|100]] ![[b.png|100]]",
                     "    - ![[a.png|100]] ![[b.png|100]]", "- `![[a.png]]` in code", "- ![[Other note]] ![[Second note]]",
                     "- ![](https://example.com/a.png)", "- [[a link]] and text"] {
            let blocks = LivePreviewBlockScanner.blocks(in: text as NSString)
            XCTAssertFalse(blocks.contains { block in if case .imageLine = block.kind { true } else { false } }, text)
        }
        // An item that embeds a note alone is that note's block, without its bullet, as before.
        guard case .embed(let embed)? = LivePreviewBlockScanner.blocks(in: "- ![[Other note]]" as NSString).first?.kind else {
            return XCTFail("An embedded note alone in an item is an embed block.")
        }
        XCTAssertEqual(embed.target, "Other note")
    }

    // MARK: Markdown embeds in rendered blocks

    func testTheMarkdownEmbedsOfATableAreFoundOutsideCodeWithTheirSizes() {
        let table = "| Photo | Note |\n| --- | --- |\n| ![a\\|200](Photos/a.png) | `![](b.png)` |\n| ![](<c d.jpg> \"Title\") | ![](https://example.com/e.png) |\n"
        let embeds = EmbedLocator.markdownEmbeds(in: table)
        XCTAssertEqual(embeds.map(\.target), ["Photos/a.png", "c d.jpg"])
        XCTAssertEqual(embeds.map(\.displayWidth), [200, nil])
        XCTAssertTrue(embeds.allSatisfy { embed in !embed.isWiki })
        let source = table as NSString
        XCTAssertEqual(embeds.map { embed in source.substring(with: embed.range) }, ["![a\\|200](Photos/a.png)", "![](<c d.jpg> \"Title\")"])
        XCTAssertEqual(EmbedLocator.markdownEmbeds(in: "No images, [[a link]] and ![[a wiki embed.png]]"), [])
    }
}
