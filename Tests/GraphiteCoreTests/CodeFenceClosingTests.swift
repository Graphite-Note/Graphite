/**
 * File: CodeFenceClosingTests.swift
 * ---------------------------------
 * Layer: Tests
 * Description: Typing a code block's opening fence puts its closing fence below, once, and never for a fence that closes another.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 16/11/2026
 */

import Foundation
import XCTest
@testable import GraphiteCore

final class CodeFenceClosingTests: XCTestCase {
    /// The note after typing a backtick at `location`, and where the cursor goes; nil when the
    /// backtick is typed alone.
    private func typingBacktick(in text: String, at location: Int) -> (text: String, cursor: Int)? {
        guard let edit = MarkdownEditing.closingCodeFence(typed: "`", in: text as NSString, selection: NSRange(location: location, length: 0)) else {
            return nil
        }
        return ((text as NSString).replacingCharacters(in: edit.range, with: edit.replacement), edit.selectionAfter.location)
    }

    func testTheThirdBacktickAtALineStartPutsTheClosingFenceBelow() throws {
        let typed = try XCTUnwrap(typingBacktick(in: "``", at: 2))
        XCTAssertEqual(typed.text, "```\n```")
        XCTAssertEqual(typed.cursor, 3, "The cursor waits after the opening fence, where the language goes.")
        let betweenParagraphs = try XCTUnwrap(typingBacktick(in: "Intro\n``\nOutro", at: 8))
        XCTAssertEqual(betweenParagraphs.text, "Intro\n```\n```\nOutro")
    }

    func testAFenceInAQuoteOrIndentedKeepsItsMarkersOnTheClosingLine() throws {
        XCTAssertEqual(try XCTUnwrap(typingBacktick(in: "> ``", at: 4)).text, "> ```\n> ```")
        XCTAssertEqual(try XCTUnwrap(typingBacktick(in: "> [!note]\n> ``", at: 14)).text, "> [!note]\n> ```\n> ```")
        XCTAssertEqual(try XCTUnwrap(typingBacktick(in: "  ``", at: 4)).text, "  ```\n  ```")
    }

    func testACrlfNoteGetsACrlfClosingLine() throws {
        XCTAssertEqual(try XCTUnwrap(typingBacktick(in: "Intro\r\n``\r\nOutro", at: 9)).text, "Intro\r\n```\r\n```\r\nOutro")
    }

    func testAFenceThatClosesAnOpenBlockIsTypedAlone() {
        XCTAssertNil(typingBacktick(in: "```swift\nlet value = 1\n``", at: 25))
        XCTAssertNil(typingBacktick(in: "> ```\n> code\n> ``", at: 17))
    }

    func testAnUnmatchedFenceBelowIsTakenAsTheClosingOne() {
        XCTAssertNil(typingBacktick(in: "``\nlet value = 1\n```\n\nAfter", at: 2), "Retyping a deleted opening fence must not add a second closing one.")
    }

    func testAWholeBlockBelowDoesNotStopTheClosingFence() throws {
        let text = "``\n\n```js\nlet value = 1\n```"
        XCTAssertEqual(try XCTUnwrap(typingBacktick(in: text, at: 2)).text, "```\n```\n\n```js\nlet value = 1\n```")
    }

    func testOnlyTheThirdBacktickOfABareLineStartCompletesAFence() {
        XCTAssertNil(typingBacktick(in: "`", at: 1), "Two backticks are an inline code span in the making.")
        XCTAssertNil(typingBacktick(in: "Use ``", at: 6), "Backticks after text are inline code.")
        XCTAssertNil(typingBacktick(in: "- ``", at: 4))
        XCTAssertNil(typingBacktick(in: "``text", at: 2), "Text after the cursor stays as it is.")
        XCTAssertNil(MarkdownEditing.closingCodeFence(typed: "~", in: "~~" as NSString, selection: NSRange(location: 2, length: 0)),
                     "Obsidian does not complete a tilde fence.")
        XCTAssertNil(MarkdownEditing.closingCodeFence(typed: "`", in: "``x" as NSString, selection: NSRange(location: 2, length: 1)))
    }

    func testPropertiesAreNotCode() {
        XCTAssertNil(typingBacktick(in: "---\n``\n---\n", at: 6))
        XCTAssertNotNil(typingBacktick(in: "---\ntitle: A\n---\n``", at: 19))
    }
}
