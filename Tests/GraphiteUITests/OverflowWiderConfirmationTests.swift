/**
 * File: OverflowWiderConfirmationTests.swift
 * ------------------------------------------
 * Layer: Tests
 * Description: Textual's Overflow with scrollsOnlyWhenWider, in a Mac window: content measured wider for a moment stays in
 *              place, and content still wider after the confirmation delay moves into the horizontal scroll view. A table
 *              drawn again after a menu command measured wider for one pass and stayed in the scroll view, which clipped
 *              its "+" strips and grips.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 28/11/2026
 */
#if os(macOS)
import AppKit
import SwiftUI
import XCTest
import Textual
import GraphiteTestSupport

@MainActor
@Observable
private final class OverflowContentWidth {
    var width: CGFloat = 200
}

private struct OverflowProbe: View {
    let contentWidth: OverflowContentWidth

    var body: some View {
        Overflow(scrollsOnlyWhenWider: true) { _ in
            Color.clear.frame(width: contentWidth.width, height: 20)
        }
        .frame(width: 300, alignment: .topLeading)
    }
}

@MainActor
final class OverflowWiderConfirmationTests: XCTestCase {
    private var window: NSWindow?

    override func tearDown() async throws {
        window?.orderOut(nil)
        window?.contentView = nil
        window = nil
        try await super.tearDown()
    }

    private func show(_ contentWidth: OverflowContentWidth) {
        let host = NSHostingView(rootView: OverflowProbe(contentWidth: contentWidth))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 100), styleMask: [.titled], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        window.contentView = host
        self.window = window
        layOut()
    }

    private func layOut() {
        window?.contentView?.layoutSubtreeIfNeeded()
        window?.displayIfNeeded()
    }

    private var showsScrollView: Bool {
        guard let root = window?.contentView else { return false }
        var views: [NSView] = [root]
        while let view = views.popLast() {
            if view is NSScrollView { return true }
            views.append(contentsOf: view.subviews)
        }
        return false
    }

    /// Lays the window out every 20 ms for the given time, as frames would.
    private func keepLayingOut(for duration: Duration) async throws {
        let end = ContinuousClock.now + duration
        try await waitUntil("the window was laid out for \(duration)", timeoutSeconds: 5) {
            self.layOut()
            return ContinuousClock.now >= end
        }
    }

    func testContentWiderForAMomentStaysOutOfTheScrollView() async throws {
        let contentWidth = OverflowContentWidth()
        show(contentWidth)
        XCTAssertFalse(showsScrollView, "content that fits is drawn in place")

        contentWidth.width = 500
        try await keepLayingOut(for: .milliseconds(60))
        contentWidth.width = 200
        try await keepLayingOut(for: .milliseconds(600))

        XCTAssertFalse(showsScrollView, "content wider for one moment stays in place")
    }

    func testContentStillWiderAfterTheDelayMovesIntoTheScrollView() async throws {
        let contentWidth = OverflowContentWidth()
        show(contentWidth)

        contentWidth.width = 500
        try await keepLayingOut(for: .milliseconds(60))
        XCTAssertFalse(showsScrollView, "content just found wider waits before it moves")

        try await waitUntil("content still wider moves into the scroll view", timeoutSeconds: 5) {
            self.layOut()
            return self.showsScrollView
        }
    }
}
#endif
