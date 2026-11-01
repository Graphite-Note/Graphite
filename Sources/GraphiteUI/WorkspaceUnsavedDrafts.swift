/**
 * File: WorkspaceUnsavedDrafts.swift
 * ----------------------------------
 * Layer: UI
 * Description: Connects a window's notes and canvases to the drafts of text that could not reach their
 *              files: gives each its draft back when it opens, keeps them before the app may end, and
 *              tells what an ended app left.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 01/11/2026
 */

import Foundation
import GraphiteCore

extension WorkspaceModel {
    private func draftKeeper(for path: VaultPath) -> DocumentDraftKeeper? {
        currentVaultIdentifier.map { vaultIdentifier in
            DocumentDraftKeeper(store: processServices.unsavedDrafts, vaultIdentifier: vaultIdentifier, path: path)
        }
    }

    /// Gives a note that just opened its draft, and the text an ended app could not save.
    func restoreUnsavedDraft(into session: MarkdownSession) async {
        guard let keeper = draftKeeper(for: session.path) else { return }
        session.draftKeeper = keeper
        guard let draft = await keeper.storedDraft(), session.restore(draft) else { return }
        errorMessage = Self.restoredDraftMessage(name: session.path.name, isConflict: session.hasExternalConflict)
    }

    /// Gives a canvas that just opened its draft, as for a note.
    func restoreUnsavedDraft(into session: CanvasSession) async {
        guard let keeper = draftKeeper(for: session.path) else { return }
        session.draftKeeper = keeper
        guard let draft = await keeper.storedDraft(), session.restore(draft) else { return }
        errorMessage = Self.restoredDraftMessage(name: session.path.name, isConflict: session.hasExternalConflict)
    }

    /// An alert rather than a notice: a notice goes as soon as the document it came with shows.
    private static func restoredDraftMessage(name: String, isConflict: Bool) -> String {
        isConflict
            ? "What you last typed in “\(name)” could not be saved, and the file has changed since. Your text is back here, for you to choose what to keep."
            : "What you last typed in “\(name)” could not be saved then. It is back and is being saved."
    }

    /// Writes what the open notes and canvases have not saved to their drafts.
    /// - Returns: Whether all of it is safe: in its file or in its draft.
    func keepUnsavedTextInDrafts() async -> Bool {
        var isEverythingSafe = true
        for document in Array(tabDocuments.values) {
            if let note = document.markdownSession, await !note.keepUnsavedTextInDraft() { isEverythingSafe = false }
            if let canvas = document.canvasSession, await !canvas.keepUnsavedEditsInDraft() { isEverythingSafe = false }
        }
        return isEverythingSafe
    }

    /// Whether quitting can go ahead with what could not be saved. Notes and canvases go to
    /// their drafts. A PDF is too large for one, so its edits go to a copy beside it, when the
    /// caller allows that write.
    func keepUnsavedDocumentsBeforeQuitting(writesPDFCopies: Bool) async -> Bool {
        var isEverythingSafe = await keepUnsavedTextInDrafts()
        for pdf in tabDocuments.values.compactMap(\.pdfSession) where pdf.hasUnsavedChanges {
            guard writesPDFCopies, (try? await pdf.saveSeparateCopy()) != nil else { // Counted as not safe, which holds quitting.
                isEverythingSafe = false
                continue
            }
        }
        return isEverythingSafe
    }

    /// Tells, once per vault as it opens, about the drafts an ended app left. A draft whose
    /// file is gone has nothing to open with, so it becomes a copy where the file was. Any
    /// other comes back when its file opens; one with a tab does so by itself.
    func recoverDraftsLeftBehind() async {
        guard let vaultIdentifier = currentVaultIdentifier, let store,
              processServices.unsavedDrafts.takeTurnToTellAboutDrafts(inVault: vaultIdentifier) else { return }
        let drafts = await processServices.unsavedDrafts.drafts(inVault: vaultIdentifier)
        var waitingNames: [String] = []
        var copiedNames: [String] = []
        for draft in drafts.sorted(by: { leftDraft, rightDraft in leftDraft.path < rightDraft.path }) where layout.tabID(showing: draft.path) == nil {
            if (try? await store.fileExists(draft.path)) != false { // Cannot be checked: treated as there, so nothing is written.
                // The file has the text after all, as when the save finished as the app ended.
                if (try? await store.read(draft.path))?.data == draft.contents { // Unreadable: the draft stays.
                    processServices.unsavedDrafts.remove(draft.path, inVault: vaultIdentifier)
                } else {
                    waitingNames.append(draft.path.name)
                }
                continue
            }
            do {
                let copyPath = try await store.separateCopyPath(of: draft.path, fileExtension: draft.path.fileExtension)
                _ = try await store.save(draft.contents, at: copyPath, expecting: .absent)
                processServices.unsavedDrafts.remove(draft.path, inVault: vaultIdentifier)
                copiedNames.append(copyPath.name)
                refreshIndex(for: [copyPath])
            } catch {
                // It stays a draft, and this is said again when the vault next opens.
                waitingNames.append(draft.path.name)
            }
        }
        if !copiedNames.isEmpty { await refreshDirectory() }
        var sentences: [String] = []
        if !copiedNames.isEmpty {
            sentences.append("Text that could not be saved before Graphite last closed is in " + Self.quotedList(copiedNames)
                + ", since the files it belonged to are gone.")
        }
        if !waitingNames.isEmpty {
            sentences.append("Graphite is keeping text that could not be saved in " + Self.quotedList(waitingNames) + ". Open the file to get it back.")
        }
        if !sentences.isEmpty { errorMessage = sentences.joined(separator: " ") }
    }

    private static func quotedList(_ names: [String]) -> String {
        names.map { name in "“\(name)”" }.joined(separator: ", ")
    }

    /// The drafts of a moved file or folder follow it.
    func moveDrafts(from path: VaultPath, to destination: VaultPath) {
        guard let currentVaultIdentifier else { return }
        processServices.unsavedDrafts.moveDrafts(from: path, to: destination, inVault: currentVaultIdentifier)
    }

    /// The person deleted these files, so their drafts must not come back as copies. What
    /// they hold goes to File recovery, as the files' own text does.
    func forgetDrafts(inside path: VaultPath) async {
        guard let currentVaultIdentifier else { return }
        for draft in await processServices.unsavedDrafts.drafts(inVault: currentVaultIdentifier) where draft.path.isInside(path) {
            if preferences.isEnabled(.fileRecovery), let fileRecovery, DocumentKind(path: draft.path) == .markdown,
               let decoded = NoteTextEncoding.decode(draft.contents) {
                _ = try? fileRecovery.takeSnapshot(of: decoded.text, for: draft.path, minimumInterval: 0) // Best effort: the person deleted the file.
            }
            processServices.unsavedDrafts.remove(draft.path, inVault: currentVaultIdentifier)
        }
    }
}
