/**
 * File: BlockHandleEditingTests.swift
 * -----------------------------------
 * Layer: Tests
 * Description: The block a handle acts on at each kind of line, and the Markdown a move, a copy, a deletion and a
 *              callout make of it.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

import XCTest
@testable import GraphiteCore

final class BlockHandleEditingTests: XCTestCase {
    private let lecture = """
    ---
    course: Signals
    ---
    # Sampling

    The theorem says enough samples rebuild a signal.

    - first item
      - nested item
    - second item

    ## Aliasing

    > [!note] Folding
    > High frequencies fold back.

    | f | alias |
    | --- | --- |
    | 3 | 1 |

    ---

    # Filters

    > A plain quote.
    """

    private func block(at marker: String, in text: String) throws -> HandleBlock {
        let source = text as NSString
        let location = source.range(of: marker).location
        XCTAssertNotEqual(location, NSNotFound, marker)
        return try XCTUnwrap(BlockHandleEditing.block(at: location, in: BlockHandleEditing.blocks(in: text)), marker)
    }

    private func text(of block: HandleBlock, in text: String) -> String {
        (text as NSString).substring(with: block.range)
    }

    private func applying(_ edit: MarkdownTextEdit?, to text: String) throws -> String {
        let edit = try XCTUnwrap(edit)
        return (text as NSString).replacingCharacters(in: edit.range, with: edit.replacement)
    }

    // MARK: Blocks

    func testEachKindOfLineHasItsBlock() throws {
        XCTAssertEqual(try block(at: "The theorem", in: lecture).kind, .paragraph)
        let item = try block(at: "first item", in: lecture)
        XCTAssertEqual(item.kind, .listItem)
        XCTAssertEqual(text(of: item, in: lecture), "- first item\n  - nested item", "A list item takes its nested items.")
        XCTAssertEqual(text(of: try block(at: "nested item", in: lecture), in: lecture), "  - nested item", "A nested item is its own block.")
        XCTAssertEqual(try block(at: "[!note]", in: lecture).kind, .callout)
        XCTAssertEqual(try block(at: "A plain quote", in: lecture).kind, .quote)
        XCTAssertEqual(try block(at: "| 3 |", in: lecture).kind, .table)
        XCTAssertEqual(try block(at: "---\n\n# Filters", in: lecture).kind, .rule)
        XCTAssertNil(BlockHandleEditing.block(at: 5, in: BlockHandleEditing.blocks(in: lecture)), "The frontmatter is no block.")
    }

    func testAHeadingTakesItsSectionUpToTheNextHeadingOfItsLevel() throws {
        let sampling = try block(at: "# Sampling", in: lecture)
        XCTAssertEqual(sampling.kind, .heading(level: 1))
        XCTAssertTrue(text(of: sampling, in: lecture).hasSuffix("---"), "The first heading's section runs to the next first-level heading.")
        XCTAssertFalse(text(of: sampling, in: lecture).contains("# Filters"))
        let aliasing = try block(at: "## Aliasing", in: lecture)
        XCTAssertEqual(aliasing.kind, .heading(level: 2))
        XCTAssertTrue(text(of: aliasing, in: lecture).hasPrefix("## Aliasing\n\n> [!note]"))
        XCTAssertEqual(text(of: try block(at: "# Filters", in: lecture), in: lecture), "# Filters\n\n> A plain quote.")
    }

    func testCodeAndMathAreBlocksAndAHeadingInCodeIsNot() throws {
        let note = "Intro\n\n```\n# not a heading\n```\n\n$$\nx\n$$\n"
        XCTAssertEqual(try block(at: "not a heading", in: note).kind, .code)
        XCTAssertEqual(try block(at: "x\n$$", in: note).kind, .math)
        XCTAssertFalse(BlockHandleEditing.blocks(in: note).contains { block in if case .heading = block.kind { true } else { false } })
    }

    // MARK: Moving

    func testParagraphsMoveWithTheirBlankLines() throws {
        let note = "A\n\nB\n\nC"
        let blocks = BlockHandleEditing.blocks(in: note)
        let first = try XCTUnwrap(blocks.first), last = try XCTUnwrap(blocks.last)
        XCTAssertEqual(try applying(BlockHandleEditing.moving(last, to: 0, in: note as NSString), to: note), "C\n\nA\n\nB")
        XCTAssertEqual(try applying(BlockHandleEditing.moving(first, to: (note as NSString).length, in: note as NSString), to: note), "B\n\nC\n\nA")
        XCTAssertEqual(try applying(BlockHandleEditing.moving(first, to: 6, in: note as NSString), to: note), "B\n\nA\n\nC")
        XCTAssertEqual(try applying(BlockHandleEditing.moving(last, to: 0, in: "A\n\nB\n\nC\n"), to: "A\n\nB\n\nC\n"), "C\n\nA\n\nB\n", "The note keeps its last line break.")
    }

    func testListItemsMoveWithoutBlankLines() throws {
        let note = "- a\n- b\n- c"
        let blocks = BlockHandleEditing.blocks(in: note)
        XCTAssertEqual(try applying(BlockHandleEditing.moving(blocks[2], to: 0, in: note as NSString), to: note), "- c\n- a\n- b")
        XCTAssertEqual(try applying(BlockHandleEditing.moving(blocks[0], to: (note as NSString).length, in: note as NSString), to: note), "- b\n- c\n- a")
        let nested = "- a\n  - a1\n- b\n"
        let nestedBlocks = BlockHandleEditing.blocks(in: nested)
        let itemA = try XCTUnwrap(nestedBlocks.first { block in block.range.location == 0 && block.kind == .listItem })
        XCTAssertEqual(try applying(BlockHandleEditing.moving(itemA, to: (nested as NSString).length, in: nested as NSString), to: nested), "- b\n- a\n  - a1\n",
                       "An item moves with its nested items.")
    }

    func testAHeadingMovesWithItsSection() throws {
        let note = "# One\n\nText one.\n\n# Two\n\nText two.\n"
        let one = try block(at: "# One", in: note)
        let edit = try XCTUnwrap(BlockHandleEditing.moving(one, to: (note as NSString).length, in: note as NSString))
        XCTAssertEqual(try applying(edit, to: note), "# Two\n\nText two.\n\n# One\n\nText one.\n")
        let moved = try applying(edit, to: note) as NSString
        XCTAssertEqual(moved.substring(from: edit.selectionAfter.location).prefix(5), "# One", "The cursor goes to the moved block.")
    }

    func testAMoveOntoItselfOrIntoItselfChangesNothing() throws {
        let note = "# One\n\nText one.\n\n# Two"
        let one = try block(at: "# One", in: note)
        XCTAssertNil(BlockHandleEditing.moving(one, to: 0, in: note as NSString))
        XCTAssertNil(BlockHandleEditing.moving(one, to: (note as NSString).range(of: "Text one").location, in: note as NSString))
        XCTAssertNil(BlockHandleEditing.moving(one, to: (note as NSString).range(of: "# Two").location, in: note as NSString), "Just after itself.")
        let destinations = BlockHandleEditing.destinations(for: one, in: BlockHandleEditing.blocks(in: note), textLength: (note as NSString).length)
        XCTAssertEqual(destinations, [(note as NSString).range(of: "# Two").location, (note as NSString).length])
    }

    func testAMoveKeepsWindowsLineBreaks() throws {
        let note = "A\r\n\r\nB"
        let blocks = BlockHandleEditing.blocks(in: note)
        XCTAssertEqual(try applying(BlockHandleEditing.moving(try XCTUnwrap(blocks.last), to: 0, in: note as NSString), to: note), "B\r\n\r\nA")
    }

    // MARK: Duplicating, deleting, callouts

    func testDuplicatingAndDeletingKeepTheSeparation() throws {
        let note = "A\n\nB\n\nC"
        let middle = try block(at: "B", in: note)
        XCTAssertEqual(try applying(BlockHandleEditing.duplicating(middle, in: note as NSString), to: note), "A\n\nB\n\nB\n\nC")
        XCTAssertEqual(try applying(BlockHandleEditing.deleting(middle, in: note as NSString), to: note), "A\n\nC")
        let list = "- a\n- b"
        XCTAssertEqual(try applying(BlockHandleEditing.duplicating(try block(at: "- a", in: list), in: list as NSString), to: list), "- a\n- a\n- b")
    }

    func testAParagraphBecomesANoteCallout() throws {
        let note = "Intro\n\nTwo lines\nof text.\n"
        let paragraph = try block(at: "Two lines", in: note)
        XCTAssertEqual(try applying(BlockHandleEditing.turningIntoCallout(paragraph, in: note as NSString), to: note),
                       "Intro\n\n> [!note]\n> Two lines\n> of text.\n")
    }
}
