/**
 * File: WorkspaceFolderReveal.swift
 * ---------------------------------
 * Layer: UI
 * Description: Showing a folder in the sidebar's file tree, as a folder search result and the file tree's filter ask,
 *              and asking for the Files panel's filter field.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 11/11/2026
 */

import Foundation
import GraphiteCore

extension WorkspaceModel {
    /// Shows a folder in the sidebar's file tree, wherever this is asked from: the Files panel in place of a search, a
    /// plugin's view or the filter, the folder and every folder above it expanded, the folder marked, and a request that
    /// shows the sidebar and scrolls the tree to it (`fileRevealRequest`, as for "Reveal current file").
    func revealFolder(_ folder: VaultPath) {
        showFileTree()
        fileTreeContents.filter.clear()
        var expandedFolder = folder
        while !expandedFolder.rawValue.isEmpty {
            expandedFolders.insert(expandedFolder)
            expandedFolder = expandedFolder.parent
        }
        fileTreeContents.revealedFolder = folder
        fileRevealRequest = FileRevealRequest(path: folder)
    }

    /// Puts the cursor in the Files panel's filter field: the panel shows in place of a search or a plugin's view, and
    /// the root view shows the sidebar (`FileTreeFilter.focusRequest`).
    func requestFileTreeFilter() {
        showFileTree()
        fileTreeContents.filter.requestFocus()
    }

    /// The Files panel in front in the sidebar, in place of search results and a plugin's view.
    private func showFileTree() {
        deviceDefaults.set(SidebarPanel.files.rawValue, forKey: SidebarPanelSettingKey.panel)
        searchQuery = ""
        communityPlugins.shownSidebarViewIdentifier = nil
    }
}
