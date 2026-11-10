/**
 * File: TagsViewLayoutMacTests.swift
 * ----------------------------------
 * Layer: Tests
 * Description: The Tags view of a vault with thousands of nested tags appears without freezing
 *              the Mac's main thread.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 10/11/2026
 */

#if os(macOS)
import AppKit
import SwiftUI
import XCTest
@testable import GraphiteIndex
@testable import GraphiteUI
import GraphiteTestSupport

/// Switching the Mac to Library mode shows the Tags view in the sidebar. With the owner's 3,000
/// tags, SwiftUI's outline list took about 4 s of the main thread to lay out the disclosure group
/// of each tag with nested tags (sampled 2026-11-10), and both the library and the tags showed
/// spinners meanwhile. The view now lists one flat row per tag shown.
@MainActor
final class TagsViewLayoutMacTests: XCTestCase {
    private var windows: [NSWindow] = []

    override func tearDown() async throws {
        for window in windows { window.close() }
        windows = []
        try await super.tearDown()
    }

    func testThousandsOfNestedTagsAreLaidOutQuickly() throws {
        let overview = VaultOverviewModel()
        // 3,000 tags at the top, each with a tag nested under it, as `course` and `course/math`.
        overview.tagCounts = (0..<3_000).flatMap { index in
            [TagCount(tag: "topic-\(index)", fileCount: 2), TagCount(tag: "topic-\(index)/part", fileCount: 1)]
        }
        overview.hasLoadedTags = true
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "TagsViewLayoutMacTests-\(UUID().uuidString)"))
        let list = List { VaultTagsList(workspace: WorkspaceModel(), overview: overview) }
            .listStyle(.sidebar)
            .defaultAppStorage(defaults)

        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 800), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        windows.append(window)
        let start = ContinuousClock.now
        window.contentView = NSHostingView(rootView: list)
        window.showInvisibly()
        window.contentView?.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        let elapsed = ContinuousClock.now - start

        XCTAssertNotNil(Self.firstOutlineView(in: window.contentView), "The tags are in the sidebar's outline list.")
        // Measured 2026-11-10 on the owner's Mac: 10.5 s with a disclosure group per tag, 0.3 s with flat rows.
        XCTAssertLessThan(elapsed, .milliseconds(1_500), "Laying out the Tags view took \(elapsed).")
    }

    private static func firstOutlineView(in view: NSView?) -> NSOutlineView? {
        guard let view else { return nil }
        if let outlineView = view as? NSOutlineView { return outlineView }
        for subview in view.subviews { if let found = firstOutlineView(in: subview) { return found } }
        return nil
    }
}
#endif
