/**
 * File: MarkdownSessionDrafts.swift
 * ---------------------------------
 * Layer: UI
 * Description: A note's autosave that tries again, and its text kept in a draft outside the vault while it
 *              cannot reach the file.
 *
 * Authors: Bahey Shalash
 * Version: 0.3
 * Date: 02/11/2026
 */

import Foundation
import GraphiteCore

extension MarkdownSession {
    /// What is about to replace a note's saved text.
    enum SavedTextReplacement {
        /// The person's own typing, which File recovery copies at its interval.
        case bySave
        /// Another app's or device's version, or one the person chose: the text it replaces
        /// may be in no other place, so it is copied whatever the interval.
        case byOtherVersion
    }

    /// Saves once typing has paused for `pause`. A failed save is tried again, waiting longer
    /// each time, so the text reaches the file without waiting for another edit. A conflict
    /// waits for the person's choice. Cancelling, as the next keystroke does, ends the tries.
    func autosave(after pause: Duration, sleeping sleep: (Duration) async throws -> Void) async {
        var delay = pause
        var consecutiveFailures = 0
        while true {
            do {
                try await sleep(delay)
                try await save()
                return
            } catch is CancellationError {
                return
            } catch {
                errorMessage = error.localizedDescription
                guard !hasExternalConflict, hasUnsavedChanges else { return }
                consecutiveFailures += 1
                delay = AutosaveRetryPolicy.delay(afterConsecutiveFailures: consecutiveFailures)
            }
        }
    }

    // MARK: Text that cannot be saved

    /// Writes the text the file does not have to the draft outside the vault, where it
    /// outlives the app. Nothing is written twice for one edit, and a note with nothing
    /// unsaved writes nothing.
    /// - Returns: Whether the text is safe: saved in the file or in the draft.
    @discardableResult
    func keepUnsavedTextInDraft() async -> Bool {
        // A move let go of this session; its text is in a copy.
        guard !wasLeftBehindByMove else { return true }
        flushPendingInsertions()
        guard hasUnsavedChanges else { return true }
        guard draftEditVersion != editVersion else { return true }
        guard let draftKeeper else { return false }
        let versionToKeep = editVersion
        let contents = NoteTextEncoding.encode(text, hasByteOrderMark: hasByteOrderMark)
        guard await draftKeeper.keep(contents, madeOver: revision) else { return false }
        draftEditVersion = versionToKeep
        return true
    }

    /// Shows the text an ended app could not save, with `snapshot`'s text as what the file
    /// holds. When the file is still the version the text was made over, the text simply
    /// goes on to be saved. Otherwise the file is newer and this is a conflict, with the
    /// meaning it has for a note left open: the session keeps expecting the old version, so
    /// nothing is written over the newer file until the person chooses.
    /// - Returns: Whether the note now shows the draft's text.
    func restore(_ draft: UnsavedDocumentDraft) -> Bool {
        // Another window on the note has its text, which is at least as new.
        guard siblings.isEmpty, !hasUnsavedChanges else { return false }
        guard let decoded = NoteTextEncoding.decode(draft.contents) else { return false }
        guard decoded.text != savedText else {
            draftKeeper?.remove()
            return false
        }
        text = decoded.text
        draftEditVersion = editVersion
        guard draft.baseRevision != revision else { return true }
        expectRevision(draft.baseRevision)
        showConflict()
        return true
    }

    /// Lets go of the draft, for this session and any other window's on the note: the text
    /// reached the file, or the person chose another version.
    func discardDraft() {
        let sessions = [self] + siblings
        guard sessions.contains(where: { session in session.draftEditVersion != nil }) else { return }
        draftKeeper?.remove()
        for session in sessions { session.draftEditVersion = nil }
    }

    static let grownTooLargeMessage = "This note is over 8 MB, the most Graphite opens for editing. It stays open here; once it is closed it opens read-only until it is smaller."
}
