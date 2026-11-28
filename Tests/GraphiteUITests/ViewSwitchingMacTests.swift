/**
 * File: ViewSwitchingMacTests.swift
 * ---------------------------------
 * Layer: Tests
 * Description: Switching the Mac's whole window between Library and List keeps the file tree as it was, builds no Tags
 *              view behind the library, and leaves the main thread free; the right sidebar and the reading view
 *              come and go without the toolbar's items being made again.
 *
 * Authors: Bahey Shalash
 * Version: 0.3
 * Date: 28/11/2026
 */

#if os(macOS)
import AppKit
import XCTest
import GraphiteCore
@testable import GraphiteUI
import GraphiteTestSupport

/// Library mode folds the sidebar out of the window. It used to swap the file tree for the Tags view there, out of sight:
/// List → Library laid out every tag of the vault (in the real 3,000-tag vault the main thread froze for 4.5 s, before
/// the Tags view's rows were made flat), and Library → List built the tree again, whose open folders then listed their
/// files again from the disk. `Docs/View-switching-speed-todo.md` section 3 has the times before and after.
@MainActor
final class ViewSwitchingMacTests: XCTestCase {
    func testTheFileTreeIsKeptAcrossLibraryModeAndNoTagsViewIsBuiltBehindTheLibrary() async throws {
        let (workspace, window) = try await ViewSwitchingWindow.open(.small, for: self)
        let quietWatch = MainThreadQuietWatch(window: window)
        let firstList = try await quietWatch.measure({ workspace.preferences.library.presentation = .list }, until: { Self.fileTree(in: window) != nil })
        let fileTree = try XCTUnwrap(Self.fileTree(in: window))
        try await waitUntil("the open folders are listed") { fileTree.numberOfRows > 1_000 }
        let rowsWithOpenFolders = fileTree.numberOfRows

        let toLibrary = try await quietWatch.measure { workspace.preferences.library.presentation = .library }
        XCTAssertTrue(Self.fileTree(in: window) === fileTree, "The folded sidebar keeps the file tree.")
        XCTAssertEqual(Self.outlineViews(in: window).count, 1, "No list but the file tree behind the library, as the Tags view was.")

        let backToList = try await quietWatch.measure { workspace.preferences.library.presentation = .list }
        XCTAssertTrue(Self.fileTree(in: window) === fileTree, "List shows the same file tree again.")
        XCTAssertEqual(fileTree.numberOfRows, rowsWithOpenFolders, "Its open folders are open at once, not listed again.")
        // Measured 2026-11-12 on a Debug build: 100 to 230 ms each way at this size; the 3 s budget leaves room for a loaded
        // machine and still catches a freeze such as the Tags view's 4.5 s.
        for measurement in [firstList, toLibrary, backToList] {
            SharedRunner.assertWithinTimingBudget(measurement.busy, isLessThan: .milliseconds(3_000), "A switch kept the main thread busy \(measurement.busy).")
        }
    }

    /// In a window of 1,440 points the right sidebar left the documents area 840 points wide, under the 1,100 at which
    /// Write left the toolbar for the tab bar; SwiftUI then made the toolbar's items and their menus again at each
    /// opening and closing, about a third of the main thread's work (`Docs/View-switching-speed-todo.md` section 2).
    func testTheRightSidebarOpensAndClosesWithoutTheToolbarsItemsBeingMadeAgain() async throws {
        let (workspace, window) = try await ViewSwitchingWindow.open(.small, for: self)
        let quietWatch = MainThreadQuietWatch(window: window)
        _ = try await quietWatch.measure { workspace.preferences.library.presentation = .list }
        let itemsBefore = window.toolbar?.items ?? []
        XCTAssertTrue(itemsBefore.contains { item in item.label == "Write" }, "Write is in the toolbar: \(itemsBefore.map(\.label))")

        _ = try await quietWatch.measure({ try? ViewSwitchingWindow.pressToolbarButton(labelled: "Sidebar", in: window) },
                                         until: { ViewSwitchingWindow.showsRightSidebar(window) })
        let itemsShown = window.toolbar?.items ?? []
        _ = try await quietWatch.measure({ try? ViewSwitchingWindow.pressToolbarButton(labelled: "Sidebar", in: window) },
                                         until: { !ViewSwitchingWindow.showsRightSidebar(window) })
        let itemsHidden = window.toolbar?.items ?? []
        for (moment, items) in [("with the right sidebar", itemsShown), ("after it closed", itemsHidden)] {
            XCTAssertEqual(items.map(\.label), itemsBefore.map(\.label), "The same toolbar \(moment).")
            XCTAssertTrue(zip(items, itemsBefore).allSatisfy { item, itemBefore in item === itemBefore }, "The toolbar's own items \(moment), not new ones.")
        }
    }

    /// Format and Insert show only while the note is written. In the same toolbar group as Write, More and Sidebar,
    /// their going and coming made SwiftUI make those three items and the menus' items again at each switch between
    /// Live Preview and the reading view, about a third of its work (`Docs/View-switching-speed-todo.md` section 2).
    func testTheReadingViewKeepsTheToolbarsWriteMoreAndSidebarItems() async throws {
        let (workspace, window) = try await ViewSwitchingWindow.open(.small, for: self)
        let quietWatch = MainThreadQuietWatch(window: window)
        _ = try await quietWatch.measure { workspace.preferences.library.presentation = .list }
        let session = try XCTUnwrap(workspace.markdownSession)
        func documentItems() -> [NSToolbarItem] {
            (window.toolbar?.items ?? []).filter { item in ["Write", "More", "Sidebar"].contains(item.label) }
        }
        func labels() -> [String] { (window.toolbar?.items ?? []).map(\.label) }
        let itemsWhileWriting = documentItems()
        XCTAssertEqual(itemsWhileWriting.map(\.label), ["Write", "More", "Sidebar"], "\(labels())")
        XCTAssertTrue(labels().contains("Format") && labels().contains("Insert"), "\(labels())")

        _ = try await quietWatch.measure { session.viewMode = .reading }
        XCTAssertFalse(labels().contains("Format") || labels().contains("Insert"), "The reading view has no Format or Insert: \(labels())")
        let itemsWhileReading = documentItems()
        _ = try await quietWatch.measure { session.viewMode = .livePreview }
        XCTAssertTrue(labels().contains("Format") && labels().contains("Insert"), "\(labels())")
        for (moment, items) in [("in the reading view", itemsWhileReading), ("back in Live Preview", documentItems())] {
            XCTAssertEqual(items.map(\.label), ["Write", "More", "Sidebar"], moment)
            XCTAssertTrue(zip(items, itemsWhileWriting).allSatisfy { item, itemBefore in item === itemBefore }, "The toolbar's own items \(moment), not new ones.")
        }
    }

    private static func allViews(in window: NSWindow) -> [NSView] {
        func descendants(of view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        return window.contentView.map(descendants) ?? []
    }

    private static func outlineViews(in window: NSWindow) -> [NSOutlineView] { allViews(in: window).compactMap { view in view as? NSOutlineView } }

    private static func fileTree(in window: NSWindow) -> FileTreeOutlineView? {
        allViews(in: window).lazy.compactMap { view in view as? FileTreeOutlineView }.first
    }
}
#endif
