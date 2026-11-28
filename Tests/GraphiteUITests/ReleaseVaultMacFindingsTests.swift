/**
 * File: ReleaseVaultMacFindingsTests.swift
 * ----------------------------------------
 * Layer: Tests
 * Description: The defects the Mac release pass over Tests/ReleaseVault found on 2026-11-12 (Docs/Bug-hunt-todo.md
 *              section 15): where the reading view starts after Live Preview, and an embedded PDF's page in a callout.
 *
 * Authors: Bahey Shalash
 * Version: 0.4
 * Date: 28/11/2026
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
        try await waitUntil("the reading view laid out its blocks", timeoutSeconds: 20 * SharedRunner.waitScale) { session.readingPosition.hasLaidOutBlocks }
        try await settle(root, seconds: 2)
        XCTAssertLessThan(session.readingPosition.topLocation() ?? 0, 200, "The reading view starts at the note's top")
        XCTAssertLessThan(session.readingPosition.visibleTop, 50, "The reading view is scrolled to its top")
    }

    /// HUNT-349 again, on 2026-11-13: the long picture note's reading view left at its top, after the switch from Live
    /// Preview, starts at its top again when the note is reopened in its tab and when the tab comes back by Back.
    func testThePictureNotesReadingViewStartsAtItsTopWhenReopenedAndWhenItsTabComesBack() async throws {
        let pass = try await ReleaseVaultPass.open(for: self)
        let path = try VaultPath("Embeds/Pictures in every form.md")
        _ = await pass.workspace.open(path, placement: .currentTab)
        let root = try XCTUnwrap(pass.window.contentView)
        try await waitUntil("the note's editor is shown") { ReleaseVaultViews.noteTextView(in: root) != nil }
        try await settle(root, seconds: 1)
        try XCTUnwrap(pass.workspace.markdownSession).viewMode = .reading
        try await assertReadingViewAtItsTop(pass, root, "after the switch from Live Preview")

        _ = await pass.workspace.open(try VaultPath("Start here.md"), placement: .currentTab)
        try await settle(root, seconds: 1)
        await pass.workspace.goBack()
        try await waitUntil("the picture note is back") { pass.workspace.markdownSession?.path == path }
        try await assertReadingViewAtItsTop(pass, root, "when its tab comes back by Back")

        _ = await pass.workspace.open(try VaultPath("Start here.md"), placement: .currentTab)
        try await settle(root, seconds: 1)
        _ = await pass.workspace.open(path, placement: .currentTab)
        try await waitUntil("the picture note is reopened") { pass.workspace.markdownSession?.path == path }
        try await assertReadingViewAtItsTop(pass, root, "when it is reopened")
    }

    private func assertReadingViewAtItsTop(_ pass: ReleaseVaultPass, _ root: NSView, _ when: String,
                                           file: StaticString = #filePath, line: UInt = #line) async throws {
        let session = try XCTUnwrap(pass.workspace.markdownSession, file: file, line: line)
        if session.viewMode != .reading { session.viewMode = .reading }
        try await waitUntil("the reading view laid out its blocks \(when)", timeoutSeconds: 20 * SharedRunner.waitScale) { session.readingPosition.hasLaidOutBlocks }
        try await settle(root, seconds: 2)
        XCTAssertLessThan(session.readingPosition.topLocation() ?? 0, 200, "The reading view starts at the note's top \(when)", file: file, line: line)
        XCTAssertLessThan(session.readingPosition.visibleTop, 50, "The reading view is scrolled to its top \(when)", file: file, line: line)
    }

    /// HUNT-350: in the pass's screenshot, `![[Lecture slides.pdf#page=4&height=240]]` in a callout showed the foot of
    /// page 3, with its "Slide 3" label, over its toolbar. The embed shows page 4 at its top; the screenshot drew the PDF
    /// view's pages over a `visibleRect` that reaches past the view, over the toolbar above it.
    func testTheCalloutsPDFShowsItsPageAtItsTopAndTheScreenshotDrawsPagesOnlyOverTheView() async throws {
        let pass = try await ReleaseVaultPass.open(for: self)
        _ = await pass.workspace.open(try VaultPath("Embeds/PDFs in every form.md"), placement: .currentTab)
        let root = try XCTUnwrap(pass.window.contentView)
        try await waitUntil("the note's editor is shown") { ReleaseVaultViews.noteTextView(in: root) != nil }
        let textView = try XCTUnwrap(ReleaseVaultViews.noteTextView(in: root))
        let callout = (textView.string as NSString).range(of: "> [!info] A PDF page in a callout\n> ![[Lecture slides.pdf#page=4&height=240]]")
        XCTAssertNotEqual(callout.location, NSNotFound, "The note holds the callout")
        // The callout is scrolled to, again at each look, as the embeds above it are laid out at their heights and move it,
        // until its embed shows a page. Stepping a screen at a time with a fixed wait at each step, as the pass does, ran
        // past it on GitHub's runners, where the PDF had not loaded within the wait.
        var calloutPDF: GraphiteMacPDFView?
        try await waitUntil("the callout's embed shows a page", timeoutSeconds: 20 * SharedRunner.waitScale) {
            textView.scrollRangeToVisible(callout)
            root.layoutSubtreeIfNeeded()
            // The PDF inside the view Live Preview draws over the callout's lines (its text is hidden under it), not another
            // PDF of the note on the same screen.
            let calloutText = textView.windowFrames(ofCharacters: callout).reduce(CGRect.null) { area, frame in area.union(frame) }
            let calloutView = ReleaseVaultViews.renderedBlockViews(in: textView).first { blockView in
                blockView.convert(blockView.bounds, to: nil).intersects(calloutText)
            }
            calloutPDF = calloutView.flatMap { blockView in
                ReleaseVaultViews.descendants(of: blockView, ofType: GraphiteMacPDFView.self).first(where: ReleaseVaultViews.isShown)
            }
            return calloutPDF?.pagePlace != nil
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

    /// Lays the window out for `seconds`, longer on a shared CI runner, where the embeds load several times slower.
    private func settle(_ root: NSView, seconds: Double) async throws {
        let end = Date.now.addingTimeInterval(seconds * SharedRunner.waitScale)
        try await waitUntil("the window settled") {
            root.layoutSubtreeIfNeeded()
            return Date.now >= end
        }
    }
}
#endif
