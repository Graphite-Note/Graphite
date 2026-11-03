/**
 * File: WorkspaceFileManagementSelection.swift
 * --------------------------------------------
 * Layer: UI
 * Description: Telling a change of the selection made by file management from opening a file.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 01/11/2026
 */

import Foundation
import GraphiteCore

/// On a phone, opening a file shows the document over the file list. A rename, a move or a
/// deletion in the list can change the selection too (the open file's new path, or the tab
/// that comes forward), and the list stays in front then.
extension WorkspaceModel {
    /// Runs a change that file management makes to the tabs. When it changes `selection`, a
    /// phone does not slide the document over the file list (`GraphiteRootView`).
    func changingTabsForFileManagement(_ change: () -> Void) {
        let selectionBefore = selection
        change()
        if selection != selectionBefore { selectionChangeIsFromFileManagement = true }
    }

    /// Whether the last change of `selection` came from a rename, a move or a deletion rather
    /// than from opening a file; asking clears the answer, so the next change counts afresh.
    func takeSelectionChangeFromFileManagement() -> Bool {
        defer { selectionChangeIsFromFileManagement = false }
        return selectionChangeIsFromFileManagement
    }

    /// Keeps the passwords of unlocked PDFs with their files when a file or folder moves, so a
    /// PDF unlocked before a rename opens at its new place without asking again.
    func movePDFPasswords(from oldPath: VaultPath, to newPath: VaultPath) {
        // A path that cannot be rebuilt under the new place keeps its old one.
        pdfPasswords = Dictionary(pdfPasswords.map { path, password in ((try? path.replacingPrefix(oldPath, with: newPath)) ?? path, password) },
                                  uniquingKeysWith: { movedPassword, _ in movedPassword })
    }
}
