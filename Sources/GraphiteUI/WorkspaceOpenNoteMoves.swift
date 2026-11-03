/**
 * File: WorkspaceOpenNoteMoves.swift
 * ----------------------------------
 * Layer: UI
 * Description: What a move of a file or folder does to the notes open inside it: their saves wait, and their
 *              live sessions go on at the new place with text, cursor, editor and undo history.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 02/11/2026
 */

import Foundation
import GraphiteCore

/// The saves of open notes, in every window, held from just before their files move until the
/// move is over. A save then cannot aim at the old path, and typing goes on: it is saved at the
/// new place, or at the old one when the move failed.
@MainActor
final class SavesHeldDuringMove {
    /// A task that ends with the hold, which shows as a save running in the sessions it holds.
    let gate: Task<Void, Error>
    private let sessions: [MarkdownSession]
    private let gateOpening: AsyncStream<Void>.Continuation
    private var savesInFlight: [Task<Void, Error>] = []
    private let clock: any ApplicationClock
    private let startTime: Duration
    private var isReleased = false
    /// Saves waiting for the release, each with the timer that ends its wait.
    private var waitingSaves: [UUID: (answer: CheckedContinuation<Bool, Never>, timer: Task<Void, Never>)] = [:]

    init(sessions: [MarkdownSession], clock: any ApplicationClock) {
        let (gateOpened, gateOpening) = AsyncStream.makeStream(of: Void.self)
        gate = Task<Void, Error> { for await _ in gateOpened {} }
        self.sessions = sessions
        self.clock = clock
        startTime = clock.now
        self.gateOpening = gateOpening
        savesInFlight = sessions.compactMap { session in session.holdSaves(by: self) }
    }

    /// Waits for saves that started before the hold, so the file moves with them in it.
    func waitForSavesInFlight() async {
        for save in savesInFlight { _ = try? await save.value } // A failed save reports to whoever started it, and its text stays in the session.
    }

    /// Waits for the release until `limit` after the hold began, however many saves have waited.
    /// - Returns: Whether the hold is over.
    func waitForRelease(within limit: Duration) async -> Bool {
        guard !isReleased else { return true }
        let timeLeft = startTime + limit - clock.now
        guard timeLeft > .zero else { return false }
        let waitIdentifier = UUID()
        return await withCheckedContinuation { answer in
            let timer = Task { [weak self, clock] in
                do { try await clock.sleep(for: timeLeft) } catch { return } // The hold ended first.
                self?.waitingSaves.removeValue(forKey: waitIdentifier)?.answer.resume(returning: false)
            }
            waitingSaves[waitIdentifier] = (answer, timer)
        }
    }

    func release() {
        isReleased = true
        gateOpening.finish()
        for session in sessions { session.releaseSaves(heldBy: self) }
        for waitingSave in waitingSaves.values {
            waitingSave.timer.cancel()
            waitingSave.answer.resume(returning: true)
        }
        waitingSaves.removeAll()
    }
}

extension WorkspaceModel {
    func holdSavesOfOpenNotes(inside path: VaultPath) -> SavesHeldDuringMove {
        let sessions = tabDocuments.values.compactMap(\.markdownSession).filter { session in session.path.isInside(path) }
        var sessionsAndSiblings: [ObjectIdentifier: MarkdownSession] = [:]
        for session in sessions.flatMap({ session in [session] + session.siblings }) { sessionsAndSiblings[ObjectIdentifier(session)] = session }
        return SavesHeldDuringMove(sessions: Array(sessionsAndSiblings.values), clock: clock)
    }

    /// Moves the open notes inside `oldPath` to their places under `newPath`, those `canFollow`
    /// allows, with the sessions of the same note in other windows and tabs.
    /// - Returns: The notes that went on at the new place.
    func followMoveInOpenNotes(from oldPath: VaultPath, to newPath: VaultPath,
                               canFollow: (MarkdownSession, VaultPath) -> Bool) -> [MarkdownSession] {
        var notesFollowing: [MarkdownSession] = []
        for session in tabDocuments.values.compactMap(\.markdownSession) where session.path.isInside(oldPath) {
            guard let newNotePath = try? session.path.replacingPrefix(oldPath, with: newPath) else { continue } // Left behind: its tab loads the file again.
            // The tab of a note left behind opens the file at that place too.
            session.clearWayForFile(at: newNotePath)
            guard canFollow(session, newNotePath), (try? session.followFile(to: newNotePath)) != nil else { // Left behind: its tab loads the file again.
                // The tab must not find this draft there: the text goes to a copy (`EditDuringMove`).
                session.parkDraft(beside: newNotePath)
                continue
            }
            notesFollowing.append(session)
        }
        return notesFollowing
    }

    /// Another note's move took the path of `session`. Its tab goes on with the note's text in the
    /// copy made for it. With nothing to keep it shows the moved note, or goes when a tab already does.
    func noteLostItsFile(_ session: MarkdownSession, keptIn copyPath: VaultPath?) {
        guard let (tabID, document) = tabDocuments.first(where: { _, document in document.markdownSession === session }) else { return }
        guard let copyPath else {
            let path = session.path
            document.unload()
            if layout.allTabs.contains(where: { tab in tab.id != tabID && tab.path == path }) {
                changingTabsForFileManagement {
                    layout.closeTab(tabID)
                    removeTabDocuments([tabID])
                }
            }
            return
        }
        let lostName = document.loadedPath?.name ?? ""
        document.loadedPath = copyPath
        changingTabsForFileManagement { layout.show(copyPath, inTab: tabID, recordsHistory: true) }
        errorMessage = "Another note was moved to “\(lostName)”, so the text not saved in the tab that showed it was kept as “\(copyPath.name)”."
        Task { await refreshDirectory() }
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
