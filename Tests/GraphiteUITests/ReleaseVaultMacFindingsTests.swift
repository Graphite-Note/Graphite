/**
 * File: ReleaseVaultMacFindingsTests.swift
 * ----------------------------------------
 * Layer: Tests
 * Description: The defects the Mac release pass over Tests/ReleaseVault found on 2026-11-12 (Docs/Bug-hunt-todo.md
 *              section 15): where the reading view starts after Live Preview, and an embedded PDF's page in a callout.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 13/11/2026
 */

#if os(macOS)
import AppKit
import PDFKit
import SwiftUI
import XCTest
import GraphiteCore
import GraphiteFixtures
@testable import GraphiteUI
import GraphiteTestSupport

/// Section 15 of the bug hunt, the Mac's findings.
@MainActor
final class ReleaseVaultMacFindingsTests: XCTestCase {
    private var windows: [NSWindow] = []

    override func tearDown() async throws {
        for window in windows {
            window.orderOut(nil)
            window.contentView = nil
        }
        windows = []
        try await super.tearDown()
    }

    /// HUNT-349: `Embeds/Pictures in every form.md`, paged through in Live Preview and scrolled back to its top, opened
    /// its reading view at its end, the embedded base's cards, instead of its top.
    func testAPictureNoteScrolledBackToItsTopInLivePreviewStartsItsReadingViewAtItsTop() async throws {
        let pass = try await ReleaseVaultPass.open(for: self)
        let path = try VaultPath("Embeds/Pictures in every form.md")
        _ = await pass.workspace.open(path, placement: .currentTab)
        let session = try XCTUnwrap(pass.workspace.markdownSession)
        let root = try XCTUnwrap(pass.window.contentView)
        try await waitUntil("the note's editor is shown") { ReleaseVaultViews.noteTextView(in: root) != nil }
        try await settle(root, seconds: 1)
        for _ in 1...ReleaseVaultPass.maximumPagesPerView {
            guard let scroller = ReleaseVaultScrolling.pageScroller(in: root), let nextOffset = ReleaseVaultScrolling.nextPageOffset(of: scroller) else { break }
            ReleaseVaultScrolling.scroll(scroller, to: nextOffset)
            try await settle(root, seconds: 0.5)
        }
        let scroller = try XCTUnwrap(ReleaseVaultScrolling.pageScroller(in: root))
        ReleaseVaultScrolling.scroll(scroller, to: ReleaseVaultScrolling.topOffset(of: scroller))
        session.viewMode = .reading
        try await waitUntil("the reading view laid out its blocks") { session.readingPosition.hasLaidOutBlocks }
        try await settle(root, seconds: 2)
        XCTAssertLessThan(session.readingPosition.topLocation() ?? 0, 200, "The reading view starts at the note's top")
        XCTAssertLessThan(session.readingPosition.visibleTop, 50, "The reading view is scrolled to its top")
    }

    /// HUNT-350: in the pass's screenshot, `![[Lecture slides.pdf#page=4&height=240]]` in a callout showed the foot of
    /// page 3, with its "Slide 3" label, over its toolbar. The embed shows page 4 at its top; the screenshot drew the PDF
    /// view's pages over a `visibleRect` that reaches past the view, over the toolbar above it.
    func testTheCalloutsPDFShowsItsPageAtItsTopAndTheScreenshotDrawsPagesOnlyOverTheView() async throws {
        let pass = try await ReleaseVaultPass.open(for: self)
        _ = await pass.workspace.open(try VaultPath("Embeds/PDFs in every form.md"), placement: .currentTab)
        let root = try XCTUnwrap(pass.window.contentView)
        try await waitUntil("the note's editor is shown") { ReleaseVaultViews.noteTextView(in: root) != nil }
        try await settle(root, seconds: 1)
        var calloutPDF: GraphiteMacPDFView?
        for _ in 1...ReleaseVaultPass.maximumPagesPerView {
            calloutPDF = ReleaseVaultViews.descendants(of: root, ofType: GraphiteMacPDFView.self).first { pdfView in
                ReleaseVaultViews.isShown(pdfView) && pdfView.pagePlace?.pageIndex == 3
            }
            if calloutPDF != nil { break }
            guard let scroller = ReleaseVaultScrolling.pageScroller(in: root), let nextOffset = ReleaseVaultScrolling.nextPageOffset(of: scroller) else { break }
            ReleaseVaultScrolling.scroll(scroller, to: nextOffset)
            try await settle(root, seconds: 0.8)
        }
        let pdfView = try XCTUnwrap(calloutPDF, "The callout's embed of page 4 is shown")
        try await settle(root, seconds: 1)
        let place = try XCTUnwrap(pdfView.pagePlace)
        XCTAssertEqual(place.pageIndex, 3, "Page 4 is at the embed's top")
        XCTAssertLessThan(place.fractionFromTop, 0.02, "The page's top is at the embed's top, not the foot of page 3: \(place)")
        let frame = pdfView.convert(pdfView.bounds, to: root)
        let shownArea = ReleaseVaultWindow.shownArea(of: pdfView, in: root)
        XCTAssertTrue(frame.insetBy(dx: -0.5, dy: -0.5).contains(shownArea), "The screenshot draws pages only over the view: \(shownArea) in \(frame)")
    }

    private func settle(_ root: NSView, seconds: Double) async throws {
        let end = Date.now.addingTimeInterval(seconds)
        try await waitUntil("the window settled") {
            root.layoutSubtreeIfNeeded()
            return Date.now >= end
        }
    }
}
#endif
