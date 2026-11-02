/**
 * File: MacMarkdownEditorWidthChangeTests.swift
 * ---------------------------------------------
 * Layer: Tests
 * Description: The Mac note editor keeps the line at its top when its width changes.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 02/11/2026
 */

#if os(macOS)
import AppKit
import XCTest
@testable import GraphiteUI
import GraphiteTestSupport

@MainActor
final class MacMarkdownEditorWidthChangeTests: XCTestCase {
    private var fixture: MacMarkdownEditorFixture?

    override func tearDown() async throws {
        fixture?.tearDown()
        fixture = nil
        try await super.tearDown()
    }

    /// Long enough to wrap, so a new width really moves every line.
    private static let text = (0..<300).map { index in
        "Paragraph \(index) of ordinary words, long enough to wrap over several lines at the widths these tests give the editor."
    }.joined(separator: "\n")

    private func location(ofParagraph index: Int) -> Int {
        (Self.text as NSString).range(of: "Paragraph \(index) ").location
    }

    private func editorScrolledToParagraph200() async throws -> MacMarkdownEditorFixture {
        let fixture = try await MacMarkdownEditorFixture(text: Self.text)
        self.fixture = fixture
        fixture.coordinator.resume(fixture.scrollView)
        fixture.scrollToTop(ofCharacter: location(ofParagraph: 200))
        XCTAssertEqual(fixture.coordinator.topCharacter(of: fixture.textView), location(ofParagraph: 200))
        return fixture
    }

    private func setWidth(_ width: CGFloat, of fixture: MacMarkdownEditorFixture) {
        fixture.scrollView.frame.size.width = width
        fixture.scrollView.layoutSubtreeIfNeeded()
    }

    /// Waits until the editor has stopped waiting for the width to settle.
    private func waitUntilTheWidthHasSettled(_ fixture: MacMarkdownEditorFixture) async throws {
        try await waitUntil("the width settles", timeoutSeconds: 10) { fixture.coordinator.topLineHold.heldLocation == nil }
    }

    func testANewWidthKeepsTheLineAtTheTop() async throws {
        let fixture = try await editorScrolledToParagraph200()

        setWidth(420, of: fixture)
        // TextKit has re-estimated the note, so the view shows another passage until the width settles.
        XCTAssertNotEqual(fixture.coordinator.topCharacter(of: fixture.textView), location(ofParagraph: 200))
        try await waitUntilTheWidthHasSettled(fixture)

        XCTAssertEqual(fixture.coordinator.topCharacter(of: fixture.textView), location(ofParagraph: 200))
    }

    /// A window drag or the sidebar's animation is many changes: the first says what the line was.
    func testARunOfWidthsKeepsTheLineFromBeforeTheFirst() async throws {
        let fixture = try await editorScrolledToParagraph200()

        for width: CGFloat in [560, 520, 480, 440] { setWidth(width, of: fixture) }
        try await waitUntilTheWidthHasSettled(fixture)

        XCTAssertEqual(fixture.coordinator.topCharacter(of: fixture.textView), location(ofParagraph: 200))
    }

    func testTheTopOfTheNoteStaysTheTop() async throws {
        let fixture = try await MacMarkdownEditorFixture(text: Self.text)
        self.fixture = fixture

        setWidth(420, of: fixture)

        XCTAssertNil(fixture.coordinator.topLineHold.heldLocation)
        XCTAssertEqual(fixture.textView.visibleRect.minY, 0, accuracy: 1)
    }

    /// Closing the tab while the view still shows another passage remembers the line it held.
    func testThePlaceToRememberWhileTheWidthSettlesIsTheLineHeld() async throws {
        let fixture = try await editorScrolledToParagraph200()
        fixture.coordinator.reportPlace(of: fixture.textView)

        setWidth(420, of: fixture)

        XCTAssertEqual(fixture.session.placeToRemember().topLocation, location(ofParagraph: 200))
    }

    func testScrollingWhileTheWidthSettlesIsNotUndone() async throws {
        let fixture = try await editorScrolledToParagraph200()

        setWidth(420, of: fixture)
        let wheel = try XCTUnwrap(CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: -40, wheel2: 0, wheel3: 0).flatMap(NSEvent.init(cgEvent:)))
        fixture.textView.scrollWheel(with: wheel)
        fixture.scrollToTop(ofCharacter: location(ofParagraph: 60))

        // Released, so nothing is left to bring the view back.
        XCTAssertNil(fixture.coordinator.topLineHold.heldLocation)
        XCTAssertEqual(fixture.coordinator.topCharacter(of: fixture.textView), location(ofParagraph: 60))
    }

    func testAJumpWhileTheWidthSettlesIsNotUndone() async throws {
        let fixture = try await editorScrolledToParagraph200()

        setWidth(420, of: fixture)
        fixture.coordinator.pendingJump = .topOfCharacter(location(ofParagraph: 60))
        fixture.coordinator.performPendingJumpIfReady(in: fixture.textView)

        XCTAssertNil(fixture.coordinator.topLineHold.heldLocation)
        XCTAssertEqual(fixture.coordinator.topCharacter(of: fixture.textView), location(ofParagraph: 60))
    }

    func testTextEditedWhileTheWidthSettlesKeepsItsOwnPlace() async throws {
        let fixture = try await editorScrolledToParagraph200()

        setWidth(420, of: fixture)
        fixture.textView.textStorage?.replaceCharacters(in: NSRange(location: 0, length: 0), with: "New words. ")
        fixture.scrollToTop(ofCharacter: location(ofParagraph: 60))
        try await waitUntilTheWidthHasSettled(fixture)

        XCTAssertLessThan(try XCTUnwrap(fixture.coordinator.topCharacter(of: fixture.textView)), location(ofParagraph: 100))
    }

    /// The window or a split was resized while another note was shown here.
    func testAKeptEditorShownAgainAtAnotherWidthGoesBackToItsLine() async throws {
        let fixture = try await editorScrolledToParagraph200()
        fixture.coordinator.suspend(fixture.scrollView)
        fixture.scrollView.frame.size.width = 420

        fixture.window.contentView = fixture.scrollView
        fixture.scrollView.frame = NSRect(x: 0, y: 0, width: 420, height: 400)
        fixture.scrollView.layoutSubtreeIfNeeded()
        fixture.coordinator.resume(fixture.scrollView)
        try await waitUntil("the editor goes back to its line", timeoutSeconds: 10) {
            fixture.coordinator.topCharacter(of: fixture.textView) == self.location(ofParagraph: 200)
        }
    }

    /// Opening a split takes the editor out of the window and gives it width 0, then its new width.
    func testAnEditorMovedOutOfTheWindowAndBackAtAnotherWidthGoesBackToItsLine() async throws {
        let fixture = try await editorScrolledToParagraph200()

        fixture.scrollView.removeFromSuperview()
        fixture.scrollView.frame.size.width = 0
        fixture.scrollView.frame.size.width = 420
        fixture.window.contentView = fixture.scrollView
        fixture.scrollView.frame = NSRect(x: 0, y: 0, width: 420, height: 400)
        fixture.scrollView.layoutSubtreeIfNeeded()

        try await waitUntil("the editor goes back to its line", timeoutSeconds: 10) {
            fixture.coordinator.topCharacter(of: fixture.textView) == self.location(ofParagraph: 200)
        }
    }

    /// Scroll bars appearing after a jump narrow the view, which took the jump away (2026-11-02, CI).
    func testAScrollBarAppearingAfterAJumpKeepsTheLine() async throws {
        let fixture = try await editorScrolledToParagraph200()

        setWidth(583, of: fixture)
        try await waitUntilTheWidthHasSettled(fixture)

        XCTAssertEqual(fixture.coordinator.topCharacter(of: fixture.textView), location(ofParagraph: 200))
    }
}
#endif
