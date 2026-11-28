/**
 * File: HiddenSidebarToolbarMacTests.swift
 * ----------------------------------------
 * Layer: Tests
 * Description: Hiding the Mac's sidebar sends none of the window's toolbar items into the overflow menu (»): the
 *              sidebar's Graph View and New Note move beside Back and Forward, and its Files Options leaves the bar.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 28/11/2026
 */

#if os(macOS)
import AppKit
import XCTest
import GraphiteCore
@testable import GraphiteUI
import GraphiteTestSupport

/// Seen 2026-11-28 in a window about 1,000 points wide: with the sidebar hidden, the toolbar showed the Graph View button
/// beside the window's buttons and put New Note, Files Options and the sidebar's own toggle (Show Sidebar) in the
/// overflow menu (»), with half the bar empty. A hidden sidebar's part of the toolbar keeps its items, and AppKit
/// squeezes that part beside the window's buttons whatever the width of the window.
@MainActor
final class HiddenSidebarToolbarMacTests: XCTestCase {
    func testHidingTheSidebarSendsNoToolbarItemIntoTheOverflowMenu() async throws {
        let vault = try TemporaryVault.make(prefix: "HiddenSidebarToolbar", for: self).root
        try Data("# Note\n".utf8).write(to: vault.appendingPathComponent("Note.md"))
        let device = try IsolatedWorkspaceDevice.make(for: self)
        let workspace = device.makeWorkspace()
        workspace.preferences.library.presentation = .list
        try await workspace.openFolderAsVault(vault)
        await workspace.open(try VaultPath("Note.md"), placement: .currentTab)
        let window = try ReleaseVaultWindow.show(GraphiteRootView(workspace: workspace), for: self)
        try await waitUntil("the sidebar's buttons are in the toolbar") {
            window.layoutIfNeeded()
            return Self.labels(in: window).contains("Files Options")
        }
        XCTAssertLessThan(try Self.index(of: "New Note", in: window), try Self.separatorIndex(in: window),
                          "Beside the sidebar, New Note is over it: \(Self.labels(in: window))")

        try Self.toggleSidebar(in: window)
        try await waitUntil("the hidden sidebar's buttons leave its part of the toolbar") {
            window.layoutIfNeeded()
            return !Self.labels(in: window).contains("Files Options")
        }
        // The test window's toolbar has no sidebar toggle, so with the sidebar's part empty it has no separator either.
        let separator = window.toolbar?.items.firstIndex { item in item.itemIdentifier.rawValue.contains("splitViewSeparator") } ?? -1
        let graph = try Self.index(of: "Graph View", in: window)
        let newNote = try Self.index(of: "New Note", in: window)
        let back = try Self.index(of: "Back", in: window)
        XCTAssertTrue(separator < graph && graph < newNote && newNote < back,
                      "Graph View and New Note come after the sidebar's part, before Back: \(Self.labels(in: window))")
        // An item in the overflow menu has no view in the window, and the menu's button is there only while items overflow.
        try await waitUntil("Graph View and New Note are in the bar, not in the overflow menu") {
            window.layoutIfNeeded()
            return ["Graph View", "New Note"].allSatisfy { label in window.toolbar?.items.first { item in item.label == label }?.view?.window === window }
        }
        XCTAssertNil(Self.overflowButton(in: window), "No item overflows a toolbar with room to spare: \(Self.labels(in: window))")

        try Self.toggleSidebar(in: window)
        try await waitUntil("the shown sidebar's buttons are back over it") {
            window.layoutIfNeeded()
            return Self.labels(in: window).contains("Files Options")
        }
        XCTAssertEqual(Self.labels(in: window).filter { label in label == "New Note" }.count, 1, "One New Note: \(Self.labels(in: window))")
        XCTAssertLessThan(try Self.index(of: "New Note", in: window), try Self.separatorIndex(in: window))
    }

    private static func labels(in window: NSWindow) -> [String] {
        (window.toolbar?.items ?? []).map { item in item.label.isEmpty ? item.itemIdentifier.rawValue : item.label }
    }

    private static func index(of label: String, in window: NSWindow) throws -> Int {
        try XCTUnwrap(window.toolbar?.items.firstIndex { item in item.label == label }, "\(label) is in the toolbar: \(labels(in: window))")
    }

    /// The item after which the toolbar follows the documents' column instead of the sidebar's.
    private static func separatorIndex(in window: NSWindow) throws -> Int {
        try XCTUnwrap(window.toolbar?.items.firstIndex { item in item.itemIdentifier.rawValue.contains("splitViewSeparator") },
                      "The toolbar follows the split view: \(labels(in: window))")
    }

    /// As the sidebar's toggle does, which a test window, hosted without the app's scene, has not in its toolbar.
    private static func toggleSidebar(in window: NSWindow) throws {
        try XCTUnwrap(splitViewController(in: window), "The window shows a split view.").toggleSidebar(nil)
    }

    private static func splitViewController(in window: NSWindow) -> NSSplitViewController? {
        var views = [window.contentView].compactMap { $0 }
        while let view = views.popLast() {
            if let splitView = view as? NSSplitView, let controller = splitView.delegate as? NSSplitViewController { return controller }
            views.append(contentsOf: view.subviews)
        }
        return nil
    }

    /// AppKit's » button, which it adds to the toolbar's view while items do not fit.
    private static func overflowButton(in window: NSWindow) -> NSView? {
        var views = [window.contentView?.superview].compactMap { $0 }
        while let view = views.popLast() {
            if String(describing: type(of: view)).contains("ClippedItemsIndicator"), !view.isHiddenOrHasHiddenAncestor { return view }
            views.append(contentsOf: view.subviews)
        }
        return nil
    }
}
#endif
