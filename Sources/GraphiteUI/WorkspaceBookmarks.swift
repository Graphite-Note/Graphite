/**
 * File: WorkspaceBookmarks.swift
 * ------------------------------
 * Layer: UI
 * Description: Bookmarks of the workspace: reading, changing and opening them.
 *
 * Authors: Bahey Shalash
 * Version: 0.4
 * Date: 01/11/2026
 */

import Foundation
import GraphiteCore

/// Obsidian's Bookmarks core plugin, kept in the vault's `.obsidian/bookmarks.json` so the
/// same bookmarks show in Obsidian.
extension WorkspaceModel {
    func reloadBookmarks() async {
        guard let store else { bookmarks = BookmarkList(); return }
        do { bookmarks = try await store.bookmarks() }
        catch { errorMessage = error.localizedDescription }
    }

    /// Changes the bookmarks as they are in the file now, then shows the result.
    func updateBookmarks(_ change: @escaping @Sendable (inout BookmarkList) -> Void) async {
        guard let store else { return }
        do { bookmarks = try await store.updateBookmarks(change) }
        catch { errorMessage = error.localizedDescription }
    }

    /// Whether a file or folder is bookmarked. Only the bookmarks are asked: a path is a file
    /// or a folder, never both, so the file system need not say which. Every library tile and
    /// file row asks at each drawing; asking whether the path was a folder resolved it on disk
    /// one component at a time, which made switching to the library take up to two seconds.
    func isBookmarked(_ path: VaultPath) -> Bool {
        bookmarks.fileBookmark(for: path) != nil || bookmarks.folderBookmark(for: path) != nil
    }

    /// Bookmarks a file or folder, or removes its bookmark, as Obsidian's "Bookmark" does.
    func toggleBookmark(_ path: VaultPath) async {
        let isFolder = isDirectory(path)
        if let existing = isFolder ? bookmarks.folderBookmark(for: path) : bookmarks.fileBookmark(for: path) {
            let id = existing.id
            await updateBookmarks { bookmarks in bookmarks.remove(id: id) }
        } else {
            let bookmark = isFolder ? Bookmark.folder(path) : Bookmark.file(path)
            await updateBookmarks { bookmarks in bookmarks.add(bookmark) }
        }
    }

    /// Obsidian's "Bookmark current search".
    func bookmarkSearch(_ query: String) async {
        let trimmedQuery = query.trimmingCharacters(in: .whitespaces)
        guard !trimmedQuery.isEmpty, bookmarks.searchBookmark(for: trimmedQuery) == nil else { return }
        await updateBookmarks { bookmarks in bookmarks.add(.search(trimmedQuery)) }
    }

    func removeBookmark(_ bookmark: Bookmark) async {
        let id = bookmark.id
        await updateBookmarks { bookmarks in bookmarks.remove(id: id) }
    }

    func renameBookmark(_ bookmark: Bookmark, to title: String) async {
        let id = bookmark.id
        await updateBookmarks { bookmarks in bookmarks.rename(id: id, to: title) }
    }

    func addBookmarkGroup(named title: String) async {
        let trimmedTitle = title.trimmingCharacters(in: .whitespaces)
        guard !trimmedTitle.isEmpty else { errorMessage = "A group needs a name."; return }
        await updateBookmarks { bookmarks in bookmarks.add(.group(trimmedTitle)) }
    }

    /// Opens what a bookmark points to: a note at its heading or block, a folder in the
    /// file list, or a search in the sidebar.
    func open(_ bookmark: Bookmark, placement: TabPlacement = .currentTab) async {
        switch bookmark.type {
        case "file":
            guard let path = bookmark.vaultPath else { return }
            guard isInVault(path) else { errorMessage = "“\(bookmark.displayTitle)” is no longer in this vault."; return }
            guard let tabID = await open(path, placement: placement, takesFocus: true) else { return }
            guard let subpath = bookmark.subpath, let target = subpath.split(separator: "#").last.map(String.init) else { return }
            if target.hasPrefix("^") { showBlock(String(target.dropFirst()), inTab: tabID) }
            else { document(for: tabID).headingScrollRequest = HeadingScrollRequest(anchor: NotePreviewDocument.anchor(forHeading: target)) }
        case "folder":
            guard let path = bookmark.vaultPath else { return }
            guard isInVault(path) else { errorMessage = "The folder “\(bookmark.displayTitle)” is no longer in this vault."; return }
            reveal(folder: path)
        case "search":
            searchQuery = bookmark.query ?? ""
        case "graph":
            showGraph()
        default:
            break
        }
    }

    /// Shows a folder, open, in the sidebar's file list.
    func reveal(folder: VaultPath) {
        deviceDefaults.set(SidebarPanel.files.rawValue, forKey: SidebarPanelSettingKey.panel)
        searchQuery = ""
        var folderToOpen = folder
        while !folderToOpen.rawValue.isEmpty {
            expandedFolders.insert(folderToOpen)
            folderToOpen = folderToOpen.parent
        }
    }

    /// Bookmarks on renamed or moved files and folders follow them, as in Obsidian.
    func followMoveInBookmarks(from oldPath: VaultPath, to newPath: VaultPath) {
        Task { await updateBookmarksFollowingMove(from: oldPath, to: newPath) }
    }

    /// The file's own bookmarks are changed, not the copy in memory, which is stale until the Bookmarks
    /// panel has been shown: Obsidian may have added a bookmark to the moved file since the vault opened.
    /// A file with nothing to change is left as it is.
    func updateBookmarksFollowingMove(from oldPath: VaultPath, to newPath: VaultPath) async {
        await updateBookmarks { bookmarks in bookmarks.followMove(from: oldPath, to: newPath) }
    }
}
