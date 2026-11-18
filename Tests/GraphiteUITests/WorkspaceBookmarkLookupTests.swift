/**
 * File: WorkspaceBookmarkLookupTests.swift
 * ----------------------------------------
 * Layer: Tests
 * Description: Whether a file or folder is bookmarked is read from the bookmarks alone, never from the disk.
 *
 * Authors: Bahey Shalash
 * Version: 0.9
 * Date: 18/11/2026
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

    /// A library tile's star is a bookmark of Obsidian's: bookmarking a notebook writes it into `.obsidian/bookmarks.json`, as a
    /// file bookmark Obsidian reads, and the tile then shows it; removing the bookmark takes it out of the file and off the tile.
    func testBookmarkingANotebookWritesObsidiansBookmarkAndTheTileShowsIt() async throws {
        let vault = try TemporaryVault.make(prefix: "BookmarkNotebook", files: ["Courses/Week 1.pdf": "x"], for: self).root
        let workspace = WorkspaceModel()
        workspace.folderAccess = FolderAccess(root: vault)
        workspace.store = VaultStore(root: vault)
        await workspace.reloadBookmarks()
        let notebook = try VaultPath("Courses/Week 1.pdf")
        let bookmarksFile = vault.appendingPathComponent(".obsidian/bookmarks.json")

        await workspace.toggleBookmark(notebook)
        XCTAssertNil(workspace.errorMessage)
        XCTAssertTrue(workspace.isBookmarked(notebook))
        let written = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(contentsOf: bookmarksFile)) as? [String: Any])
        let items = try XCTUnwrap(written["items"] as? [[String: Any]])
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?["type"] as? String, "file")
        XCTAssertEqual(items.first?["path"] as? String, "Courses/Week 1.pdf")

        await workspace.toggleBookmark(notebook)
        XCTAssertFalse(workspace.isBookmarked(notebook))
        let emptied = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(contentsOf: bookmarksFile)) as? [String: Any])
        XCTAssertEqual((emptied["items"] as? [Any])?.count, 0)
    }
}
