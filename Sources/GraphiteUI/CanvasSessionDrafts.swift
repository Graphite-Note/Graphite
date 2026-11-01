/**
 * File: CanvasSessionDrafts.swift
 * -------------------------------
 * Layer: UI
 * Description: A canvas's edits kept in a draft outside the vault while they cannot reach the file.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 01/11/2026
 */

import Foundation
import GraphiteCore

extension CanvasSession {
    /// Writes the canvas as edited to the draft outside the vault, as a note does.
    /// - Returns: Whether the edits are safe: saved in the file or in the draft.
    @discardableResult
    func keepUnsavedEditsInDraft() async -> Bool {
        commitTextEdit()
        guard hasUnsavedChanges else { return true }
        guard draftChangeVersion != changeVersion else { return true }
        guard let draftKeeper else { return false }
        let versionToKeep = changeVersion
        guard await draftKeeper.keep(file.data, madeOver: revision) else { return false }
        draftChangeVersion = versionToKeep
        return true
    }

    /// Shows the edits an ended app could not save, as `MarkdownSession.restore` does.
    /// - Returns: Whether the canvas now shows the draft's edits.
    func restore(_ draft: UnsavedDocumentDraft) -> Bool {
        guard !hasUnsavedChanges, let draftFile = try? CanvasFile(data: draft.contents) /* A damaged draft restores nothing and stays on disk. */ else { return false }
        guard draft.contents != savedData else {
            draftKeeper?.remove()
            return false
        }
        let isFileNewer = draft.baseRevision != revision
        takeDraft(draftFile, madeOver: draft.baseRevision)
        draftChangeVersion = changeVersion
        if isFileNewer { showConflict() } else { scheduleAutosave() }
        return true
    }

    func discardDraft() {
        guard draftChangeVersion != nil else { return }
        draftKeeper?.remove()
        draftChangeVersion = nil
    }
}
