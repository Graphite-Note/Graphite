/**
 * File: WorkspaceBookmarkLookupTests.swift
 * ----------------------------------------
 * Layer: Tests
 * Description: Whether a file or folder is bookmarked is read from the bookmarks alone, never from the disk.
 *
 * Authors: Bahey Shalash
 * Version: 0.8
 * Date: 09/11/2026
 */

import XCTest
import GraphiteCore
import GraphiteApple
@testable import GraphiteUI
import GraphiteTestSupport

/// Every library tile and file row asks whether its item is bookmarked at each drawing. The
/// answer used to ask the disk whether the path was a folder, resolving it one component at a
/// time, which made switching to the library take up to two seconds on the iPad.
@MainActor
final class WorkspaceBookmarkLookupTests: XCTestCase {
    /// The paths named here are not on disk: the answer can only come from the bookmarks.
    func testAFileOrFolderIsBookmarkedByItsBookmarkAlone() async throws {
        let vault = try TemporaryVault.make(prefix: "BookmarkLookup", for: self).root
        try FileManager.default.createDirectory(at: vault.appendingPathComponent(".obsidian"), withIntermediateDirectories: true)
        let bookmarksJSON = """
        {"items":[{"type":"folder","ctime":1,"path":"Courses/Signals"},{"type":"file","ctime":2,"path":"Courses/Week 1.md"}]}
        """
        try Data(bookmarksJSON.utf8).write(to: vault.appendingPathComponent(".obsidian/bookmarks.json"))
        let workspace = WorkspaceModel()
        workspace.folderAccess = FolderAccess(root: vault)
        workspace.store = VaultStore(root: vault)
        await workspace.reloadBookmarks()
        XCTAssertNil(workspace.errorMessage)

        XCTAssertTrue(workspace.isBookmarked(try VaultPath("Courses/Signals")), "A folder's bookmark, with no folder on disk to ask.")
        XCTAssertTrue(workspace.isBookmarked(try VaultPath("Courses/Week 1.md")))
        XCTAssertFalse(workspace.isBookmarked(try VaultPath("Courses")))
        XCTAssertFalse(workspace.isBookmarked(try VaultPath("Courses/Week 2.md")))
    }
}
