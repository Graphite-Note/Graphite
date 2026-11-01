/**
 * File: WorkspaceMovesAndDrops.swift
 * ----------------------------------
 * Layer: UI
 * Description: Moves another app or window made, followed by this window's tabs; edits made during a move;
 *              and what a drop of dragged items on a folder does.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 01/11/2026
 */

import Foundation
import GraphiteCore
import GraphiteIndex

extension WorkspaceModel {
    /// What a drop of dragged items on `folder` does: items of this vault move there, those it
    /// `accepts`, and items dragged from another window's vault are copied in as files from
    /// outside are, since their paths mean nothing here and could name another file.
    /// - Returns: Whether the drop did anything.
    func takeDroppedItems(_ items: [VaultItemTransfer], into folder: VaultPath, accepts: (VaultPath) -> Bool = { _ in true }) -> Bool {
        let root = folderAccess?.root
        let paths = items.compactMap { item in item.path(inVaultAt: root) }.filter(accepts)
        let foreignLocations = items.filter { item in item.isFromAnotherVault(than: root) }.compactMap(\.sourceLocation)
        guard !paths.isEmpty || !foreignLocations.isEmpty else { return false }
        Task {
            for path in paths { await move(path, into: folder) }
            if !foreignLocations.isEmpty { await importFiles(from: foreignLocations, into: folder) }
        }
        return true
    }

    /// Ink and page changes made on an open PDF while it moved go to a copy beside the moved
    /// file: the session holding them, kept alive here, still points at the old place.
    func savePDFEditsMadeDuringMove(_ sessions: [PDFSession], from path: VaultPath, to destination: VaultPath) async
        -> (writtenPaths: [VaultPath], problems: [String]) {
        guard let root = folderAccess?.root else { return ([], []) }
        var writtenPaths: [VaultPath] = []
        var problems: [String] = []
        for session in sessions {
            let name = session.location.lastPathComponent
            do {
                guard let oldPath = vaultPath(for: session.location) else { throw GraphiteError.outsideVault }
                let newPath = try oldPath.replacingPrefix(path, with: destination)
                let copyLocation = try await session.saveSeparateCopy(inFolder: try newPath.parent.url(in: root))
                if let copyPath = vaultPath(for: copyLocation) { writtenPaths.append(copyPath) }
                problems.append("“\(newPath.name)” changed while it moved, so the changes made meanwhile were saved separately as "
                    + "“\(copyLocation.lastPathComponent)”.")
            } catch {
                problems.append("The changes made to “\(name)” while it moved could not be saved. " + error.localizedDescription)
            }
        }
        return (writtenPaths, problems)
    }

    /// Another app or window moved a file or folder: tabs follow it, and so does everything
    /// remembered about it. Text not saved yet goes to the new place when the file there is
    /// still the version it was made over, and beside it otherwise, as for edits during a
    /// move of Graphite's own. A file that left the vault is not followed: its tab says it is
    /// gone, with its text kept (`Save a Copy`).
    func followExternalMove(from oldLocation: URL, to newLocation: URL) async {
        guard let oldPath = vaultPath(for: oldLocation), let newPath = vaultPath(for: newLocation), oldPath != newPath,
              !oldPath.isHidden, !newPath.isHidden, let store,
              // A file put in the old place again is a save by replacing it, not a move.
              (try? await store.fileExists(newPath)) == true, // Cannot be checked: not followed.
              (try? await store.fileExists(oldPath)) == false else { return } // Cannot be checked: not followed.
        // Read before the tabs let go of their sessions, with no suspension in between.
        let revisions = Dictionary(tabDocuments.values.compactMap(\.markdownSession).map { session in (session.path, session.baseRevision) }
            + tabDocuments.values.compactMap(\.canvasSession).map { session in (session.path, session.baseRevision) }) { firstRevision, _ in firstRevision }
        let edits = unsavedEdits(inside: oldPath, movedTo: newPath, revisionsBeforeMove: revisions)
        let pdfsWithEdits = tabDocuments.values.compactMap(\.pdfSession).filter { session in
            session.hasUnsavedChanges && vaultPath(for: session.location)?.isInside(oldPath) == true
        }
        expandedFolders = Set(expandedFolders.map { folder in (try? folder.replacingPrefix(oldPath, with: newPath)) ?? folder }) // Outside it: unchanged.
        followMoveInNavigation(from: oldPath, to: newPath)
        moveDrafts(from: oldPath, to: newPath)
        let (keptEditPaths, editProblems) = await saveEditsMadeDuringMove(edits)
        let (keptPDFPaths, pdfProblems) = await savePDFEditsMadeDuringMove(pdfsWithEdits, from: oldPath, to: newPath)
        refreshIndexFollowingMove([oldPath, newPath] + keptEditPaths + keptPDFPaths)
        await refreshDirectory()
        let problems = editProblems + pdfProblems
        if !problems.isEmpty { errorMessage = problems.joined(separator: "\n\n") }
    }

    /// Open notes and canvases inside the moved item with changes not yet saved, made while it moved.
    func unsavedEdits(inside path: VaultPath, movedTo destination: VaultPath, revisionsBeforeMove: [VaultPath: FileRevision]) -> [EditDuringMove] {
        let noteEdits = tabDocuments.values.compactMap(\.markdownSession).compactMap { session -> EditDuringMove? in
            guard session.path.isInside(path), session.hasUnsavedChanges,
                  let newPath = try? session.path.replacingPrefix(path, with: destination) else { return nil }
            return EditDuringMove(newPath: newPath, data: NoteTextEncoding.encode(session.text, hasByteOrderMark: session.hasByteOrderMark),
                                  copyExtension: "md", revisionBeforeMove: revisionsBeforeMove[session.path])
        }
        let canvasEdits = tabDocuments.values.compactMap(\.canvasSession).compactMap { session -> EditDuringMove? in
            guard session.path.isInside(path), let newPath = try? session.path.replacingPrefix(path, with: destination) else { return nil }
            // Text typed into a card is part of the file only once committed.
            session.commitTextEdit()
            guard session.hasUnsavedChanges else { return nil }
            return EditDuringMove(newPath: newPath, data: session.file.data, copyExtension: "canvas", revisionBeforeMove: revisionsBeforeMove[session.path])
        }
        return noteEdits + canvasEdits
    }

    /// Writes changes made during a move into the note or canvas at its new place. A file
    /// that the move itself changed (a note's own links were rewritten) keeps that version,
    /// and the changes are saved beside it as a separate copy, so neither is lost.
    /// - Returns: The files written, and a message for each edit saved as a copy or not saved.
    func saveEditsMadeDuringMove(_ edits: [EditDuringMove]) async -> (writtenPaths: [VaultPath], problems: [String]) {
        guard let store else { return ([], []) }
        var writtenPaths: [VaultPath] = []
        var problems: [String] = []
        for edit in edits {
            let data = edit.data
            do {
                guard let revisionBeforeMove = edit.revisionBeforeMove else { throw GraphiteError.conflict }
                _ = try await store.save(data, at: edit.newPath, expecting: .revision(revisionBeforeMove))
                writtenPaths.append(edit.newPath)
            } catch {
                do {
                    let copyPath = try await store.separateCopyPath(of: edit.newPath, fileExtension: edit.copyExtension)
                    _ = try await store.save(data, at: copyPath, expecting: .absent)
                    writtenPaths.append(copyPath)
                    problems.append("“\(edit.newPath.name)” changed while it moved, so the changes made meanwhile were saved separately as “\(copyPath.name)”.")
                } catch {
                    problems.append("The changes made to “\(edit.newPath.name)” while it moved could not be saved. " + error.localizedDescription)
                }
            }
        }
        return (writtenPaths, problems)
    }
}
