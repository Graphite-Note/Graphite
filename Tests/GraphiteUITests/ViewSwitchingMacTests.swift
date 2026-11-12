/**
 * File: ViewSwitchingMacTests.swift
 * ---------------------------------
 * Layer: Tests
 * Description: Switching the Mac's whole window between Library and List keeps the file tree as it was, builds no Tags
 *              view behind the library, and leaves the main thread free.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 12/11/2026
 */

#if os(macOS)
import AppKit
import XCTest
import GraphiteCore
@testable import GraphiteUI
import GraphiteTestSupport

/// Library mode folds the sidebar out of the window. It used to swap the file tree for the Tags view there, out of sight:
/// List → Library laid out every tag of the vault (in the owner's 3,000-tag vault the main thread froze for 4.5 s, before
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
        // Measured 2026-11-12 on a Debug build: 100 to 230 ms each way at this size; the budget leaves room for a loaded
        // machine and still catches a freeze such as the Tags view's 4.5 s.
        for measurement in [firstList, toLibrary, backToList] {
            XCTAssertLessThan(measurement.busy, .milliseconds(2_000), "A switch kept the main thread busy \(measurement.busy).")
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
