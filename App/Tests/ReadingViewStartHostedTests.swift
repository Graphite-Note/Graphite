/**
 * File: ReadingViewStartHostedTests.swift
 * ---------------------------------------
 * Layer: Tests
 * Description: HUNT-349 on the iPad: the release vault's long picture note, paged through in Live Preview and back at
 *              its top, starts its reading view at its top after the switch, when it is reopened and when its tab
 *              comes back by Back.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 13/11/2026
 */
#if os(iOS)
import XCTest
import SwiftUI
import GraphiteCore
@testable import GraphiteUI

@MainActor
final class ReadingViewStartHostedTests: XCTestCase {
    func testThePictureNotesReadingViewStartsAtItsTopAfterLivePreviewWhenReopenedAndWhenItsTabComesBack() async throws {
        let pass = try await ReleaseVaultPass.open(for: self)
        let path = try VaultPath("Embeds/Pictures in every form.md")
        _ = await pass.workspace.open(path, placement: .currentTab)
        let root: UIView = pass.window
        try await waitUntil("the note's editor is shown") { ReleaseVaultViews.noteTextView(in: root) != nil }
        try await settle(root, seconds: 1)
        for _ in 1...ReleaseVaultPass.maximumPagesPerView {
            guard let scroller = ReleaseVaultScrolling.pageScroller(in: root), let nextOffset = ReleaseVaultScrolling.nextPageOffset(of: scroller) else { break }
            ReleaseVaultScrolling.scroll(scroller, to: nextOffset)
            try await settle(root, seconds: 0.5)
        }
        let scroller = try XCTUnwrap(ReleaseVaultScrolling.pageScroller(in: root))
        ReleaseVaultScrolling.scroll(scroller, to: ReleaseVaultScrolling.topOffset(of: scroller))
        try XCTUnwrap(pass.workspace.markdownSession).viewMode = .reading
        try await assertReadingViewAtItsTop(pass, root, "after the switch from Live Preview at its top")

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

    private func assertReadingViewAtItsTop(_ pass: ReleaseVaultPass, _ root: UIView, _ when: String,
                                           file: StaticString = #filePath, line: UInt = #line) async throws {
        let session = try XCTUnwrap(pass.workspace.markdownSession, file: file, line: line)
        if session.viewMode != .reading { session.viewMode = .reading }
        try await waitUntil("the reading view laid out its blocks \(when)") { session.readingPosition.hasLaidOutBlocks }
        try await settle(root, seconds: 2)
        XCTAssertLessThan(session.readingPosition.topLocation() ?? 0, 200, "The reading view starts at the note's top \(when)", file: file, line: line)
        XCTAssertLessThan(session.readingPosition.visibleTop, 50, "The reading view is scrolled to its top \(when)", file: file, line: line)
    }

    private func settle(_ root: UIView, seconds: Double) async throws {
        let end = Date.now.addingTimeInterval(seconds)
        try await waitUntil("the window settled") {
            root.layoutIfNeeded()
            return Date.now >= end
        }
    }
}
#endif
