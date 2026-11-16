/**
 * File: UiEditorMacRoomBelowTextTests.swift
 * -----------------------------------------
 * Layer: Tests
 * Description: The Mac note editor scrolls the end of a note up to the middle of its height.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 16/11/2026
 */

#if os(macOS)
import AppKit
import XCTest
@testable import GraphiteUI

@MainActor
final class UiEditorMacRoomBelowTextTests: XCTestCase {
    private let longNote = (1...120).map { number in "Line \(number) of a note longer than the editor." }.joined(separator: "\n")

    /// The bottom of the last line, in the text view's coordinates.
    private func lastLineBottom(of textView: MarkdownMacTextView) throws -> CGFloat {
        let textLayoutManager = try XCTUnwrap(textView.textLayoutManager)
        return textView.textContainerOrigin.y + textLayoutManager.usageBoundsForTextContainer.maxY
    }

    /// Lays the whole note out with real line heights, as scrolling to its end does, and lets TextKit size the view to it.
    private func layOutWholeNote(of textView: MarkdownMacTextView) throws {
        let textLayoutManager = try XCTUnwrap(textView.textLayoutManager)
        textLayoutManager.ensureLayout(for: textLayoutManager.documentRange)
        textView.textLayoutManager?.textViewportLayoutController.layoutViewport()
    }

    /// Scrolled to the end, the last line sits half the editor's height above its bottom edge, not at it.
    func testTheEndOfALongNoteScrollsUpToTheMiddleOfTheEditor() async throws {
        let fixture = try await MacMarkdownEditorFixture(text: longNote)
        defer { fixture.tearDown() }
        fixture.textView.textContainerInset = CGSize(width: 32, height: 32)
        try layOutWholeNote(of: fixture.textView)
        let visibleHeight = fixture.scrollView.contentView.bounds.height
        fixture.textView.scroll(NSPoint(x: 0, y: fixture.textView.frame.height - visibleHeight))

        let visibleBottom = fixture.scrollView.contentView.bounds.maxY
        let roomBelowLastLine = visibleBottom - (try lastLineBottom(of: fixture.textView))
        XCTAssertEqual(roomBelowLastLine, visibleHeight / 2 + fixture.textView.textContainerInset.height, accuracy: 1)
    }

    /// A taller editor leaves more room, so the end still reaches its middle.
    func testTheRoomFollowsTheEditorsHeight() async throws {
        let fixture = try await MacMarkdownEditorFixture(text: longNote)
        defer { fixture.tearDown() }
        fixture.textView.textContainerInset = CGSize(width: 32, height: 32)
        try layOutWholeNote(of: fixture.textView)
        XCTAssertEqual(fixture.textView.appliedRoomBelowText, 200, accuracy: 1)

        fixture.window.setContentSize(NSSize(width: 600, height: 800))
        fixture.scrollView.frame = NSRect(x: 0, y: 0, width: 600, height: 800)
        fixture.scrollView.layoutSubtreeIfNeeded()

        XCTAssertEqual(fixture.textView.appliedRoomBelowText, 400, accuracy: 1)
        XCTAssertEqual(fixture.textView.frame.height, try lastLineBottom(of: fixture.textView) + fixture.textView.textContainerInset.height + 400, accuracy: 1)
    }

    /// AppKit passes the view's height, room included, back through its sizing: the room is added once.
    func testSizingAgainDoesNotAddTheRoomTwice() async throws {
        let fixture = try await MacMarkdownEditorFixture(text: longNote)
        defer { fixture.tearDown() }
        fixture.textView.textContainerInset = CGSize(width: 32, height: 32)
        try layOutWholeNote(of: fixture.textView)
        let height = fixture.textView.frame.height

        fixture.textView.sizeToFit()
        fixture.textView.setConstrainedFrameSize(fixture.textView.frame.size)

        XCTAssertEqual(fixture.textView.frame.height, height, accuracy: 0.5)
        XCTAssertEqual(height, try lastLineBottom(of: fixture.textView) + 32 + 200, accuracy: 1)
    }
}
#endif
