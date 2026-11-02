/**
 * File: WorkspaceOpenNoteMoves.swift
 * ----------------------------------
 * Layer: UI
 * Description: Carrying out a move of a file or folder, and what it does to the notes open inside it: their saves
 *              wait, and their live sessions go on at the new place with text, cursor, editor and undo history.
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
    /// Whether the window still has the vault `fileOperations` acts on. Paths mean nothing in
    /// another one, where the same path can name another file.
    func isVaultOpen(_ fileOperations: VaultFileOperations) -> Bool {
        store === fileOperations.store
    }

    func refuseMoveInClosedVault(of path: VaultPath) -> FileMoveOutcome {
        let refusal = FileMoveRefusal.vaultClosed(movedName: path.name)
        errorMessage = refusal.message
        return .refused(refusal)
    }

    func completeMove(_ path: VaultPath, to destination: VaultPath, plan: LinkUpdatePlan, updatesLinks: Bool,
                      through fileOperations: VaultFileOperations) async -> FileMoveOutcome {
        guard isVaultOpen(fileOperations) else { return refuseMoveInClosedVault(of: path) }
        let vaultIdentifier = currentVaultIdentifier
        let stopShowingProgress = startShowingMoveProgress(of: path)
        defer { stopShowingProgress() }
        do {
            // Changes made while the question was open are saved before anything moves.
            try await saveOpenDocuments()
            guard isVaultOpen(fileOperations) else { return refuseMoveInClosedVault(of: path) }
            // Before anything can suspend: from here until the file has its new place, no save
            // aims at the old path. Typing goes on, and is saved once the move is over.
            let heldSaves = holdSavesOfOpenNotes(inside: path)
            defer { heldSaves.release() }
            await heldSaves.waitForSavesInFlight()
            let revisionsBeforeMove = await revisionsOfOpenDocuments(inside: path)
            let report = try await fileOperations.move(path, to: destination, applying: updatesLinks ? plan : nil)
            guard isVaultOpen(fileOperations) else {
                return finishMoveInClosedVault(vaultIdentifier, report, from: path, to: destination, updatesLinks: updatesLinks)
            }
            // A note goes on at the new place in its own session, undo history included; one
            // whose file the move itself rewrote under typing is left behind, below.
            let notesFollowing = followMoveInOpenNotes(from: path, to: destination) { session, newPath in
                !session.hasUnsavedChanges || !report.updatedNotes.contains(newPath)
            }
            // After those notes put aside the drafts that must not reach the new place.
            moveDrafts(from: path, to: destination)
            // Read before the tabs let go of their sessions, with no suspension in between,
            // so every keystroke made during the move is kept.
            let editsDuringMove = unsavedEdits(inside: path, movedTo: destination, revisionsBeforeMove: revisionsBeforeMove)
            let pdfsEditedDuringMove = pdfSessionsWithEdits(inside: path)
            expandedFolders = Set(expandedFolders.map { folder in (try? folder.replacingPrefix(path, with: destination)) ?? folder })
            // Tabs whose session could not follow load their files again from the new place.
            followMoveInNavigation(from: path, to: destination)
            heldSaves.release()
            await saveTextOfNotes(notesFollowing)
            let (keptEditPaths, editProblems) = await saveEditsMadeDuringMove(editsDuringMove, in: fileOperations.store)
            let (keptPDFPaths, pdfProblems) = await savePDFEditsMadeDuringMove(pdfsEditedDuringMove, from: path, to: destination, in: fileOperations.store)
            // Without link updates the report lists only the moved item itself; the plan
            // lists every indexed file inside a moved folder.
            let movedFiles = report.moves.merging(plan.moves) { reportedDestination, _ in reportedDestination }
            refreshIndexFollowingMove(Array(movedFiles.keys) + Array(movedFiles.values) + report.updatedNotes + keptEditPaths + keptPDFPaths)
            await checkOpenDocuments(changedByMove: Set(report.updatedNotes + keptEditPaths))
            await refreshDirectory()
            tellAbout(report, problems: editProblems + pdfProblems, movedItemName: destination.name, updatesLinks: updatesLinks)
            return .moved
        } catch {
            errorMessage = error.localizedDescription
            return .refused(.failed(message: error.localizedDescription))
        }
    }

    /// Another vault opened as this one's file moved. Its paths mean nothing to the tabs and
    /// sessions here now, so only the drafts of the vault it left follow.
    private func finishMoveInClosedVault(_ vaultIdentifier: UUID?, _ report: MoveReport, from path: VaultPath, to destination: VaultPath,
                                         updatesLinks: Bool) -> FileMoveOutcome {
        if let vaultIdentifier { processServices.unsavedDrafts.moveDrafts(from: path, to: destination, inVault: vaultIdentifier) }
        tellAbout(report, problems: [], movedItemName: destination.name, updatesLinks: updatesLinks)
        return .moved
    }

    func pdfSessionsWithEdits(inside path: VaultPath) -> [PDFSession] {
        tabDocuments.values.compactMap(\.pdfSession).filter { session in
            session.hasUnsavedChanges && vaultPath(for: session.location)?.isInside(path) == true
        }
    }

    /// Open documents whose files the move wrote read them again.
    private func checkOpenDocuments(changedByMove changedNotes: Set<VaultPath>) async {
        for document in tabDocuments.values {
            if let session = document.markdownSession, changedNotes.contains(session.path) { await session.checkExternalChange() }
            if let session = document.canvasSession, changedNotes.contains(session.path) { await session.checkExternalChange() }
        }
    }

    private func tellAbout(_ report: MoveReport, problems: [String], movedItemName: String, updatesLinks: Bool) {
        var problems = problems
        if !report.failures.isEmpty { problems.append(Self.describeNotesNotUpdated(report.failures, movedItemName: movedItemName)) }
        if !problems.isEmpty { errorMessage = problems.joined(separator: "\n\n") }
        if !report.notesNotChecked.isEmpty, updatesLinks {
            notice = Self.describeNotesNotChecked(report.notesNotChecked, movedItemName: movedItemName)
        }
    }

    /// The file revisions of open notes and canvases inside `path`, just before it moves.
    private func revisionsOfOpenDocuments(inside path: VaultPath) async -> [VaultPath: FileRevision] {
        guard let store else { return [:] }
        var revisions: [VaultPath: FileRevision] = [:]
        for session in tabDocuments.values.compactMap(\.markdownSession) where session.path.isInside(path) {
            // A note that cannot be read now has no revision to write over; text typed into
            // it during the move is kept as a separate copy instead.
            revisions[session.path] = try? await store.read(session.path, maximumBytes: MarkdownSession.maximumEditableBytes).revision
        }
        for session in tabDocuments.values.compactMap(\.canvasSession) where session.path.isInside(path) {
            // As for a note: a canvas that cannot be read now is kept as a separate copy.
            revisions[session.path] = try? await store.read(session.path, maximumBytes: CanvasFile.maximumSourceBytes).revision
        }
        return revisions
    }

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
