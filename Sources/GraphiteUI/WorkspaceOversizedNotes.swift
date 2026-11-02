/**
 * File: WorkspaceOversizedNotes.swift
 * -----------------------------------
 * Layer: UI
 * Description: Notes too large to edit in a window's tabs: opened read-only, loaded for editing when the person
 *              asks, and opened again as their files change.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 02/11/2026
 */

import Foundation
import GraphiteCore

extension WorkspaceModel {
    /// The note's bytes, or nil when it is larger than `maximumBytes` and stays unread.
    func snapshotUnlessTooLarge(_ path: VaultPath, maximumBytes: Int, in store: VaultStore) async throws -> FileSnapshot? {
        do { return try await store.read(path, maximumBytes: maximumBytes) }
        catch GraphiteError.oversized { return nil } // The caller opens it read-only.
    }

    /// Edit Anyway: loads the note the tab shows read-only into the normal editor, so a note
    /// that grew by a paste can be trimmed. The note says it is over the limit while it is open;
    /// the next time it opens, it is read-only again unless it is smaller.
    func editOversizedNoteAnyway(inTab tabID: UUID) async {
        guard let note = document(for: tabID).oversizedNote, note.canEditAnyway else { return }
        await load(note.path, into: tabID, pdfPageIndex: nil, recordsHistory: false, editsOversizedNote: true)
    }

    /// Opens again what changed size for the editor: a read-only note whose file changed, which
    /// is then edited normally if it is now small enough, and a note in an editor, with nothing
    /// unsaved, whose file another app took past what the editor reads.
    /// - Parameter changedPaths: The files known to have changed; nil checks every tab.
    func openAgainNotesThatChangedSize(limitedTo changedPaths: Set<VaultPath>?) async {
        for (tabID, document) in Array(tabDocuments) {
            guard let path = document.loadedPath, changedPaths?.contains(path) != false else { continue }
            if let note = document.oversizedNote {
                guard await note.fileHasChanged(), document.oversizedNote === note else { continue }
                let didOpen = await load(path, into: tabID, pdfPageIndex: nil, recordsHistory: false, reportsFailure: false)
                // A file that is gone says so in the tab, rather than showing pages it no longer has.
                if !didOpen { document.unload() }
            } else if let session = document.markdownSession, session.fileOutgrewEditor, !session.hasUnsavedChanges {
                await load(path, into: tabID, pdfPageIndex: nil, recordsHistory: false, reportsFailure: false)
            }
        }
    }
}
