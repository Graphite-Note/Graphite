/**
 * File: WorkspaceOversizedNotes.swift
 * -----------------------------------
 * Layer: UI
 * Description: Opening a note in a window's tab: its session, or, for a note too large to edit, read-only, loaded
 *              for editing when the person asks, and opened again as its file changes.
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

    /// The session of a note that was just read, with its draft, view, folds and place.
    func openNoteSession(at path: VaultPath, snapshot: FileSnapshot, store: VaultStore, maximumBytesRead: Int) async throws -> MarkdownSession {
        let session = try MarkdownSession(path: path, snapshot: snapshot, store: store, openNotes: processServices.openNotes) { [weak self] savedPath in
            self?.refreshIndex(for: [savedPath])
        }
        // An edit while the note is read: reading goes on at the same sentence.
        session.textDidChange = { [weak self, weak session] in
            guard let self, let session else { return }
            readAloud?.noteTextDidChange(path: session.path, text: session.text,
                hiddenRanges: ReadAloudFolding.hiddenRanges(in: session.text, foldedKeys: session.foldedKeys,
                                                            calloutExpansion: calloutFolds.expansion(for: session.path.rawValue)))
        }
        await restoreUnsavedDraft(into: session)
        restoreViewMode(of: session); restoreFolds(of: session)
        returnToRememberedPlace(of: session); watchForRecovery(session)
        session.maximumBytesRead = maximumBytesRead
        if snapshot.data.count > MarkdownSession.maximumEditableBytes { session.errorMessage = MarkdownSession.grownTooLargeMessage }
        return session
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
