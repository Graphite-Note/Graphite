/**
 * File: MarkdownSessionMoves.swift
 * --------------------------------
 * Layer: UI
 * Description: A note's session as its file moves: saves held meanwhile with the text in a draft, every session of
 *              the note going on at the new place, and a session whose path another note's move took.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 02/11/2026
 */

import Foundation
import GraphiteCore

extension MarkdownSession {
    /// While a move holds the note, its text waits in the draft, on disk whatever ends the app.
    /// A move that outlasts `longestWaitForMove` is said and the save given up, so the app goes
    /// on. The hold stays: the old path is never written, and the text is saved when the move ends.
    func waitForMove(holding moveHold: SavesHeldDuringMove) async throws {
        await keepUnsavedTextInDraft()
        guard await moveHold.waitForRelease(within: longestWaitForMove) else {
            errorMessage = Self.stillMovingMessage
            throw GraphiteError.unavailable(Self.stillMovingMessage)
        }
    }

    // MARK: A move of the note's file

    static let stillMovingMessage = "This note is still being moved, so it cannot be saved yet. "
        + "What you typed is kept, and is saved once the move ends."

    /// The session goes away as the move ends, with its text already in a copy (`EditDuringMove`).
    func letGoAfterMove() {
        wasLeftBehindByMove = true
    }

    /// Makes every save of this note wait for `moveHold`, which a move of its file holds until
    /// the file has its new place, so no save can aim at the old path meanwhile.
    /// - Returns: The save already running, which the move waits for before it starts.
    func holdSaves(by moveHold: SavesHeldDuringMove) -> Task<Void, Error>? {
        let saveInFlight = activeSave
        activeSave = moveHold.gate
        self.moveHold = moveHold
        return saveInFlight
    }

    func releaseSaves(heldBy moveHold: SavesHeldDuringMove) {
        if activeSave == moveHold.gate { activeSave = nil }
        guard self.moveHold === moveHold else { return }
        self.moveHold = nil
        if errorMessage == Self.stillMovingMessage { errorMessage = nil }
    }

    /// The note's file is now at `newPath`: every session of it, in every window, goes on there
    /// with its text, cursor, editor, undo history and unsaved state. A session whose vault
    /// does not hold the new place stays as it is, and finds its file gone.
    func followFile(to newPath: VaultPath) throws {
        let newLocation = try newPath.url(in: store.root)
        let newFileKey = OpenNoteFiles.key(for: newLocation)
        clearWayForFile(at: newPath)
        for session in [self] + siblings { session.takeMovedFile(at: newLocation, fileKey: newFileKey) }
    }

    private func takeMovedFile(at newLocation: URL, fileKey newFileKey: String) {
        guard let newPath = WorkspaceModel.vaultPath(for: newLocation, root: store.root) else { return }
        openNotes?.moveSession(self, fromFile: fileKey, toFile: newFileKey)
        fileKey = newFileKey
        if draftEditVersion != nil { draftKeeper?.moveDraft(to: newPath) }
        draftKeeper = draftKeeper?.following(to: newPath)
        path = newPath
    }

    // MARK: Another note moved to this note's path

    /// Sessions already open at `newPath`, where the file of this note is about to arrive, hold
    /// another version of a file that was gone. They stop being sessions of that path now, in one
    /// turn, so no text or draft of theirs reaches the moved note's, or the other way round.
    func clearWayForFile(at newPath: VaultPath) {
        guard let openNotes, let newLocation = try? newPath.url(in: store.root) else { return } // Cannot be named: nothing is there.
        let movingSessions = [self] + siblings
        let sessionsInTheWay = openNotes.sessions(ofFile: OpenNoteFiles.key(for: newLocation)).filter { session in
            !movingSessions.contains { movingSession in movingSession === session }
        }
        guard let firstSession = sessionsInTheWay.first else { return }
        let keyOfTheirOwn = "lost file " + UUID().uuidString
        firstSession.parkDraft(beside: newPath)
        for session in sessionsInTheWay {
            session.draftKeeper = firstSession.draftKeeper
            session.loseFile(toKey: keyOfTheirOwn)
        }
        // On the next turn, once the move has changed the tabs. A failure shows in the note's
        // banner and its draft keeps the text; the next save tries again.
        Task { try? await firstSession.save() } // See above.
    }

    private func loseFile(toKey keyOfTheirOwn: String) {
        openNotes?.moveSession(self, fromFile: fileKey, toFile: keyOfTheirOwn)
        fileKey = keyOfTheirOwn
        hasLostFileToMove = true
        hasExternalConflict = false
    }

    /// Moves the draft to a name no file has, so it cannot meet the draft of the note that has its
    /// path now. If the app ends before the text reaches its copy, the next launch makes one from it.
    func parkDraft(beside otherPath: VaultPath) {
        let parkedName = "\(otherPath.stem) unsaved \(UUID().uuidString.prefix(8)).md"
        guard let draftKeeper, let parkedPath = try? otherPath.parent.appending(parkedName) else { return } // Cannot be named there: it stays.
        draftKeeper.moveDraft(to: parkedPath)
        self.draftKeeper = draftKeeper.following(to: parkedPath)
    }

    func goOnInCopy(at copyPath: VaultPath) throws {
        let sessions = [self] + siblings
        for session in sessions { session.hasLostFileToMove = false }
        try followFile(to: copyPath)
        for session in sessions { session.didLoseFileToMove?(session, copyPath) }
    }

    func letGoOfLostFile() {
        guard hasLostFileToMove else { return }
        let sessions = [self] + siblings
        for session in sessions {
            session.hasLostFileToMove = false
            session.wasLeftBehindByMove = true
            session.didLoseFileToMove?(session, nil)
        }
    }

    static let lostFileMessage = "Another note was moved to this name, and your text could not be saved beside it. It is kept, and saving tries again."
}
