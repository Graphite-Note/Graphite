/**
 * File: DraggedTextMoveTests.swift
 * --------------------------------
 * Layer: Tests
 * Description: Text dragged within a note moves as one edit, later or earlier in the note, and nothing moves when it
 *              is let go on itself.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

import XCTest
@testable import GraphiteCore

/// Text dragged within a note and let go elsewhere in it (HUNT-377).
final class DraggedTextMoveTests: XCTestCase {
    private func applying(_ edit: MarkdownTextEdit, to text: String) -> String {
        (text as NSString).replacingCharacters(in: edit.range, with: edit.replacement)
    }

    func testTextMovedLaterInTheNoteIsOneEditWithTheMovedTextSelected() throws {
        let text = "## Second law\n\n- Heat flows from hot to cold.\n"
        let dragged = (text as NSString).range(of: "Second ")
        let edit = try XCTUnwrap(DraggedTextMove.edit(moving: dragged, to: (text as NSString).length, in: text as NSString))
        let moved = applying(edit, to: text)
        XCTAssertEqual(moved, "## law\n\n- Heat flows from hot to cold.\nSecond ")
        XCTAssertEqual((moved as NSString).substring(with: edit.selectionAfter), "Second ")
        // Only the span from the dragged text to the place it was let go changes.
        XCTAssertEqual(edit.range.location, dragged.location)
    }

    func testTextMovedEarlierInTheNoteGoesWhereItWasLetGo() throws {
        let text = "Alpha beta gamma."
        let dragged = (text as NSString).range(of: "gamma")
        let edit = try XCTUnwrap(DraggedTextMove.edit(moving: dragged, to: 0, in: text as NSString))
        let moved = applying(edit, to: text)
        XCTAssertEqual(moved, "gammaAlpha beta .")
        XCTAssertEqual(edit.selectionAfter, NSRange(location: 0, length: 5))
    }

    func testNothingMovesWhenTheTextIsLetGoOnItselfOrTheRangeIsWrong() {
        let text = "Alpha beta gamma." as NSString
        let dragged = text.range(of: "beta")
        XCTAssertNil(DraggedTextMove.edit(moving: dragged, to: dragged.location, in: text))
        XCTAssertNil(DraggedTextMove.edit(moving: dragged, to: dragged.location + 2, in: text))
        XCTAssertNil(DraggedTextMove.edit(moving: dragged, to: NSMaxRange(dragged), in: text))
        XCTAssertNil(DraggedTextMove.edit(moving: NSRange(location: 3, length: 0), to: 10, in: text))
        XCTAssertNil(DraggedTextMove.edit(moving: NSRange(location: 15, length: 5), to: 0, in: text))
        XCTAssertNil(DraggedTextMove.edit(moving: dragged, to: text.length + 1, in: text))
    }

    func testTextOutsideTheBasicPlaneMovesWhole() throws {
        let text = "One 🧪 two" as NSString
        let dragged = text.range(of: "🧪 ")
        let edit = try XCTUnwrap(DraggedTextMove.edit(moving: dragged, to: text.length, in: text))
        XCTAssertEqual(applying(edit, to: text as String), "One two🧪 ")
    }
}
