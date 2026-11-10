/**
 * File: ReadingViewStartingPlaceTests.swift
 * -----------------------------------------
 * Layer: Tests
 * Description: The reading view of a long note starts at the line the editor was at when the note switched to reading.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 10/11/2026
 */

#if os(macOS)
import AppKit
import SwiftUI
import XCTest
import GraphiteCore
import GraphiteIndex
@testable import GraphiteUI
import GraphiteTestSupport

/// Switching a long note from writing to reading left the reading view somewhere else than
/// the editor was (the owner, 2026-11-10: "switching between views teleports us"): the lazy
/// stack puts a row it has not built by its estimate of the rows before it, and revises the
/// estimate as they are built, so one scroll to the row does not end at the row.
@MainActor
final class ReadingViewStartingPlaceTests: XCTestCase {
    private var windows: [NSWindow] = []
    private static let windowSize = CGSize(width: 834, height: 1_210)

    override func tearDown() async throws {
        for window in windows {
            window.orderOut(nil)
            window.contentView = nil
        }
        windows = []
        try await super.tearDown()
    }

    private struct SettledPlace {
        /// The frame of the block holding the character, in the view's coordinates; nil when the lazy stack does not hold it.
        let blockFrame: CGRect?
        let visibleTop: CGFloat
        /// How far down its block the character is, from 0 to 1, as the view places it.
        let fractionDown: Double
        /// The character the view says is at its top, which the editor starts at on the way back.
        let topLocation: Int
    }

    /// Shows the note's reading view starting at a character, and returns where it is once
    /// the view has settled.
    private func settledPlace(of noteLocation: Int, in note: String, vault: URL) async throws -> SettledPlace {
        let index = try VaultIndex(databaseURL: vault.appendingPathComponent("index-\(noteLocation).sqlite"))
        let position = ReadingPosition()
        var startingLocation: Int? = noteLocation
        let preview = MarkdownPreview(source: note, path: try VaultPath("Note.md"), root: vault, index: index, configuration: ReadingConfiguration(),
                                      headingScrollRequest: .constant(nil), handledScrollToken: .constant(nil),
                                      navigate: { _, _ in }, openPDF: { _, _ in }, updateProperties: nil, savedPosition: position,
                                      takeStartingLocation: {
                                          defer { startingLocation = nil }
                                          return startingLocation
                                      })
        let hosting = NSHostingView(rootView: preview.frame(width: Self.windowSize.width, height: Self.windowSize.height))
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: Self.windowSize), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        windows.append(window)
        window.contentView = hosting
        window.showInvisibly()
        try await waitUntil("the reading view took its starting place") {
            window.contentView?.layoutSubtreeIfNeeded()
            return startingLocation == nil && position.hasLaidOutBlocks
        }
        // The view settles: the rows above the place are built and measured, and the scroll follows.
        let settlingEnd = Date.now.addingTimeInterval(2)
        try await waitUntil("the reading view settled") {
            window.contentView?.layoutSubtreeIfNeeded()
            return Date.now >= settlingEnd
        }
        let block = try XCTUnwrap(position.block(containing: noteLocation))
        return SettledPlace(blockFrame: position.frame(ofBlock: block.identifier), visibleTop: position.visibleTop,
                            fractionDown: block.fractionDown, topLocation: position.topLocation() ?? 0)
    }

    func testALongNoteSwitchedToReadingStartsAtTheLineTheEditorWasAt() async throws {
        let vault = try TemporaryVault.make(prefix: "ReadingStart", for: self).root
        let note = PerformanceBenchmarkTests.longLectureNote(sectionCount: 40)
        try Data(note.utf8).write(to: vault.appendingPathComponent("Note.md"))
        let source = note as NSString
        for fraction in [0.25, 0.5, 0.75, 0.95] {
            // The start of a line that far down the note.
            let lineStart = source.lineRange(for: NSRange(location: Int(Double(source.length) * fraction), length: 0)).location
            let place = try await settledPlace(of: lineStart, in: note, vault: vault)
            let blockFrame = try XCTUnwrap(place.blockFrame, "\(fraction): the block holding the line is laid out, so it is on or near the screen")
            XCTAssertEqual(blockFrame.minY, place.visibleTop - place.fractionDown * blockFrame.height, accuracy: 2,
                           "\(fraction): the line is at the top of the view: its block starts as far above the top as the line is down the block")
            // What the view says is at its top is where the editor starts when the note switches back.
            let between = source.substring(with: NSRange(location: min(place.topLocation, lineStart), length: abs(place.topLocation - lineStart)))
            XCTAssertLessThanOrEqual(between.filter { character in character == "\n" }.count, 1, "\(fraction): the view tells the editor the same line, within one")
        }
    }

    func testTheAnchorPutsAPointDownARowAtTheTopOfTheView() throws {
        // A row 300 high in a view 1,000 high, a third of the way down the row at the top: the
        // row's top is 100 above the view's. An anchor at y lines up row.minY + 300y with 1,000y.
        let anchor = try XCTUnwrap(MarkdownPreview.anchor(showingAtTop: 1.0 / 3, ofRowWithHeight: 300, inViewWithHeight: 1_000))
        let rowTop = anchor.y * 1_000 - anchor.y * 300
        XCTAssertEqual(rowTop, -100, accuracy: 0.001)
        XCTAssertNil(MarkdownPreview.anchor(showingAtTop: 0.5, ofRowWithHeight: 1_000, inViewWithHeight: 1_000), "No anchor moves a row as tall as the view.")
        XCTAssertNil(MarkdownPreview.anchor(showingAtTop: 0.5, ofRowWithHeight: 300, inViewWithHeight: 0), "Before the view has a height.")
    }
}
#endif
