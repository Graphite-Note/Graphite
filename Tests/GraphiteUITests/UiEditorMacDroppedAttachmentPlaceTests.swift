/**
 * File: UiEditorMacDroppedAttachmentPlaceTests.swift
 * --------------------------------------------------
 * Layer: Tests
 * Description: A file dropped or pasted into a long note on the Mac leaves the note where it was scrolled.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

#if os(macOS)
import AppKit
import XCTest
@testable import GraphiteUI

@MainActor
final class UiEditorMacDroppedAttachmentPlaceTests: XCTestCase {
    /// A long note with headings, as lecture notes are, so its layout below the screen is only estimated.
    private let longNote = (1...400).map { number in
        number % 20 == 0 ? "## Section \(number / 20)\n\nLine \(number) of a note longer than the editor." : "Line \(number) of a note longer than the editor."
    }.joined(separator: "\n")

    /// The embed of a dropped file goes in where it was dropped, and the note stays on the lines it showed.
    func testAnEmbedInsertedDeepInTheNoteKeepsTheScrollPlace() async throws {
        let fixture = try await MacMarkdownEditorFixture(text: longNote)
        defer { fixture.tearDown() }
        let source = longNote as NSString
        let shownLine = source.range(of: "Line 250 of").location
        fixture.scrollToTop(ofCharacter: shownLine)
        let topBefore = try XCTUnwrap(fixture.coordinator.topCharacter(of: fixture.textView))
        let visibleTopBefore = fixture.textView.visibleRect.minY
        XCTAssertGreaterThan(visibleTopBefore, 1000)

        // As the pane does once the dropped file is saved: a line below the top of the view.
        let dropLocation = NSMaxRange(source.lineRange(for: NSRange(location: source.range(of: "Line 255 of").location, length: 0)))
        fixture.session.isEditorAttached = true
        fixture.session.insertBlock("![[Picture.png]]", at: NSRange(location: dropLocation, length: 0))
        fixture.coordinator.apply(try XCTUnwrap(fixture.session.pendingInsertion), to: fixture.textView)
        fixture.scrollView.layoutSubtreeIfNeeded()
        fixture.textView.layoutSubtreeIfNeeded()

        let embedRange = (fixture.textView.string as NSString).range(of: "![[Picture.png]]")
        XCTAssertGreaterThan(embedRange.location, shownLine)
        XCTAssertEqual(fixture.coordinator.topCharacter(of: fixture.textView), topBefore,
                       "visible top \(visibleTopBefore) → \(fixture.textView.visibleRect.minY)")
        XCTAssertEqual(fixture.textView.visibleRect.minY, visibleTopBefore, accuracy: 1)
        // The cursor, which stayed at the note's start, follows the embed, as on the iPad.
        XCTAssertGreaterThanOrEqual(fixture.textView.selectedRange().location, NSMaxRange(embedRange))
    }

    /// An insertion above the lines shown, at a cursor out of sight, still brings the inserted text into view.
    func testAnInsertionAtACursorOutOfSightShowsTheInsertedText() async throws {
        let fixture = try await MacMarkdownEditorFixture(text: longNote)
        defer { fixture.tearDown() }
        let source = longNote as NSString
        fixture.scrollToTop(ofCharacter: source.range(of: "Line 250 of").location)
        let cursor = NSMaxRange(source.lineRange(for: NSRange(location: source.range(of: "Line 10 of").location, length: 0)))
        fixture.textView.setSelectedRange(NSRange(location: cursor, length: 0))

        fixture.session.isEditorAttached = true
        fixture.session.insertBlock("![[Picture.png]]")
        fixture.coordinator.apply(try XCTUnwrap(fixture.session.pendingInsertion), to: fixture.textView)
        fixture.scrollView.layoutSubtreeIfNeeded()

        let embedRange = (fixture.textView.string as NSString).range(of: "![[Picture.png]]")
        XCTAssertEqual(embedRange.location, cursor)
        let textLayoutManager = try XCTUnwrap(fixture.textView.textLayoutManager)
        let contentManager = try XCTUnwrap(textLayoutManager.textContentManager)
        let embedLocation = try XCTUnwrap(contentManager.location(contentManager.documentRange.location, offsetBy: embedRange.location))
        let embedFrame = try XCTUnwrap(textLayoutManager.textLayoutFragment(for: embedLocation)).layoutFragmentFrame
            .offsetBy(dx: 0, dy: fixture.textView.textContainerOrigin.y)
        XCTAssertTrue(fixture.textView.visibleRect.intersects(embedFrame), "embed \(embedFrame), visible \(fixture.textView.visibleRect)")
    }
}
#endif
