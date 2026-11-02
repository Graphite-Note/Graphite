/**
 * File: WorkspaceOpenNoteMoves.swift
 * ----------------------------------
 * Layer: UI
 * Description: What a move of a file or folder does to the notes open inside it: their saves wait, and their
 *              live sessions go on at the new place with text, cursor, editor and undo history.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 02/11/2026
 */

import Foundation
import GraphiteCore

/// The saves of open notes, in every window, held from just before their files move until the
/// move is over. A save then cannot aim at the old path, and typing goes on: it is saved at the
/// new place, or at the old one when the move failed.
@MainActor
final class SavesHeldDuringMove {
    private let sessions: [MarkdownSession]
    private let gate: Task<Void, Error>
    private let gateOpening: AsyncStream<Void>.Continuation
    private let savesInFlight: [Task<Void, Error>]

    init(sessions: [MarkdownSession]) {
        let (gateOpened, gateOpening) = AsyncStream.makeStream(of: Void.self)
        let gate = Task<Void, Error> { for await _ in gateOpened {} }
        self.sessions = sessions
        self.gate = gate
        self.gateOpening = gateOpening
        savesInFlight = sessions.compactMap { session in session.holdSaves(until: gate) }
    }

    /// Waits for saves that started before the hold, so the file moves with them in it.
    func waitForSavesInFlight() async {
        for save in savesInFlight { _ = try? await save.value } // A failed save reports to whoever started it, and its text stays in the session.
    }

    func release() {
        gateOpening.finish()
        for session in sessions { session.releaseSaves(heldBy: gate) }
    }
}

extension WorkspaceModel {
    func holdSavesOfOpenNotes(inside path: VaultPath) -> SavesHeldDuringMove {
        let sessions = tabDocuments.values.compactMap(\.markdownSession).filter { session in session.path.isInside(path) }
        var sessionsAndSiblings: [ObjectIdentifier: MarkdownSession] = [:]
        for session in sessions.flatMap({ session in [session] + session.siblings }) { sessionsAndSiblings[ObjectIdentifier(session)] = session }
        return SavesHeldDuringMove(sessions: Array(sessionsAndSiblings.values))
    }

    /// Moves the open notes inside `oldPath` to their places under `newPath`, those `canFollow`
    /// allows, with the sessions of the same note in other windows and tabs.
    /// - Returns: The notes that went on at the new place.
    func followMoveInOpenNotes(from oldPath: VaultPath, to newPath: VaultPath,
                               canFollow: (MarkdownSession, VaultPath) -> Bool) -> [MarkdownSession] {
        var notesFollowing: [MarkdownSession] = []
        for session in tabDocuments.values.compactMap(\.markdownSession) where session.path.isInside(oldPath) {
            guard let newNotePath = try? session.path.replacingPrefix(oldPath, with: newPath), // Left behind: its tab loads the file again.
                  canFollow(session, newNotePath),
                  (try? session.followFile(to: newNotePath)) != nil else { continue } // Left behind: its tab loads the file again.
            notesFollowing.append(session)
        }
        return notesFollowing
    }

    /// The tabs of a moved file or folder. A note that followed the file stays as it is shown.
    /// Any other document goes, and its tab loads the file again from the new place; as every
    /// other way a session goes, it reopens at the line and cursor it left, which
    /// `followMoveInPlaces` carries to the new path.
    func followMoveInOpenDocuments(from oldPath: VaultPath, to newPath: VaultPath) {
        calloutFolds.followMove(from: oldPath, to: newPath)
        let movedDocuments = layout.allTabs.filter { tab in tab.path?.isInside(oldPath) == true }.compactMap { tab in tabDocuments[tab.id] }
        var documentsLeftBehind: [TabDocument] = []
        for document in movedDocuments {
            if let session = document.markdownSession, let loadedPath = document.loadedPath,
               let movedPath = try? loadedPath.replacingPrefix(oldPath, with: newPath), session.path == movedPath { // Cannot be named there: left behind.
                document.loadedPath = movedPath
            } else {
                documentsLeftBehind.append(document)
            }
        }
        rememberPlaces(of: documentsLeftBehind)
        for document in documentsLeftBehind {
            document.markdownSession?.letGoAfterMove()
            document.unload()
        }
        if let currentVaultIdentifier, let lastOpenedDocument = vaultLibrary.vault(withIdentifier: currentVaultIdentifier)?.lastOpenedDocument,
           lastOpenedDocument.isInside(oldPath),
           let movedPath = try? lastOpenedDocument.replacingPrefix(oldPath, with: newPath) { // Cannot be named there: left for the check at launch.
            vaultLibrary.setLastOpenedDocument(movedPath, inVault: currentVaultIdentifier)
        }
    }

    /// Saves what the notes that followed a move have not saved yet.
    func saveTextOfNotes(_ notes: [MarkdownSession]) async {
        for note in notes where note.hasUnsavedChanges { try? await note.save() } // A failure shows in the note's banner, and its draft keeps the text.
    }

    /// The revisions at the new place of the files of the notes open inside `oldPath`.
    func revisionsOfOpenNotes(inside oldPath: VaultPath, movedTo newPath: VaultPath) async -> [VaultPath: FileRevision] {
        guard let store else { return [:] }
        var revisions: [VaultPath: FileRevision] = [:]
        for session in tabDocuments.values.compactMap(\.markdownSession) where session.path.isInside(oldPath) {
            // No revision, here or below: text not saved goes beside the file.
            guard let newNotePath = try? session.path.replacingPrefix(oldPath, with: newPath) else { continue } // see above
            revisions[newNotePath] = try? await store.revision(of: newNotePath) // see above
        }
        return revisions
    }
}
