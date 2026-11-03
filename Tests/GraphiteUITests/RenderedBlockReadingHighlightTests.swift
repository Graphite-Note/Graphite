/**
 * File: RenderedBlockReadingHighlightTests.swift
 * ----------------------------------------------
 * Layer: Tests
 * Description: Read Aloud's highlight in a rendered Live Preview block follows the block after typing above
 *              it and counts through the block's lines as a Windows note has them (HUNT-306). Nothing is spoken.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 02/11/2026
 */

import XCTest
import GraphiteCore
@testable import GraphiteUI

final class RenderedBlockReadingHighlightTests: XCTestCase {
    private func firstBlock(of note: String) throws -> LivePreviewBlock {
        try XCTUnwrap(LivePreviewBlockScanner.blocks(in: note as NSString).first { block in block.kind == .callout })
    }

    /// The highlight of `word` in `text`, as the Read Aloud controller gives it: a range of the note.
    private func highlight(of word: String, in text: String) -> NSRange {
        (text as NSString).range(of: word)
    }

    func testTheHighlightIsOfTheWordSpokenInTheBlock() throws {
        let note = "Before\n\n> [!note]\n> first line\n> second line\n\nAfter\n"
        let block = try firstBlock(of: note)
        let range = try XCTUnwrap(block.readingRange(ofNoteRange: highlight(of: "second", in: note), blockStart: block.range.location))
        XCTAssertEqual((block.markdown as NSString).substring(with: range), "second")
    }

    /// The block's view stays while typing above moves the block, so its stored range is where it was found.
    func testTheHighlightFollowsABlockThatMovedAfterTypingAboveIt() throws {
        let note = "Before\n\n> [!note]\n> first line\n> second line\n\nAfter\n"
        let block = try firstBlock(of: note)
        let noteAfterTyping = "A new first paragraph.\n\n" + note
        let blockStartNow = block.range.location + ("A new first paragraph.\n\n" as NSString).length
        let range = try XCTUnwrap(block.readingRange(ofNoteRange: highlight(of: "second line", in: noteAfterTyping), blockStart: blockStartNow))
        XCTAssertEqual((block.markdown as NSString).substring(with: range), "second line")
        XCTAssertNil(block.readingRange(ofNoteRange: highlight(of: "After", in: noteAfterTyping), blockStart: blockStartNow),
                     "Text after the block is not in it, though the old place of the block reaches it.")
    }

    func testTheHighlightOfAWindowsNoteIsCountedThroughItsLineBreaks() throws {
        let note = "Before\r\n\r\n> [!note]\r\n> first line\r\n> second line\r\n> third line\r\n\r\nAfter\r\n"
        let block = try firstBlock(of: note)
        XCTAssertNotEqual(block.markdown.utf16.count, block.sourceLines.utf16.count, "The Markdown of a Windows note's block has line feeds only.")
        for word in ["note", "first", "second line", "third", "line\r\n> third"] {
            let range = try XCTUnwrap(block.readingRange(ofNoteRange: highlight(of: word, in: note), blockStart: block.range.location), word)
            XCTAssertEqual((block.markdown as NSString).substring(with: range), word.replacingOccurrences(of: "\r\n", with: "\n"), word)
        }
    }

    func testAHighlightReachingIntoTheBlockFromAboveIsCutAtItsStart() throws {
        let note = "Before\n\n> [!note]\n> first line\n"
        let block = try firstBlock(of: note)
        let range = try XCTUnwrap(block.readingRange(ofNoteRange: NSRange(location: block.range.location - 3, length: 3 + 9), blockStart: block.range.location))
        XCTAssertEqual((block.markdown as NSString).substring(with: range), "> [!note]")
    }
}
