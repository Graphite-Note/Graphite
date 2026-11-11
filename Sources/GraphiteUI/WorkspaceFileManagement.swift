/**
 * File: WorkspaceFileManagement.swift
 * -----------------------------------
 * Layer: UI
 * Description: File explorer actions: new folders, moves with link updates, moves made elsewhere, copies and deletion.
 *
 * Authors: Bahey Shalash
 * Version: 0.26
 * Date: 11/11/2026
 */

import Foundation
import GraphiteCore
import GraphiteIndex

/// A request to show a file in the sidebar's file list, drained by the sidebar. Each request
/// is new, so revealing the same file twice scrolls to it twice.
struct FileRevealRequest: Equatable {
    let path: VaultPath
    let token = UUID()
}

/// A move that changes links, waiting for the person to choose whether to update them.
struct PendingMove: Identifiable {
    let id = UUID()
    let path: VaultPath
    let destination: VaultPath
    let plan: LinkUpdatePlan
    /// The vault the move was planned in, where its answer must act.
    let fileOperations: VaultFileOperations
    /// Moves asked for while this question is open, such as the other items of a
    /// multi-item drop. They run in order once it is answered.
    let queuedMoves = QueuedMoves()
}

/// What a request to move or rename an item came to.
enum FileMoveOutcome: Equatable {
    /// The item is at its new place.
    case moved
    case refused(FileMoveRefusal)
    /// The person is asked whether to update links; the answer completes the move.
    case awaitingAnswer
    /// Another move's question is open; this move runs once it is answered.
    case queued
}

/// Why a move did not happen.
enum FileMoveRefusal: Equatable {
    case noVaultOpen
    case alreadyMoving
    case destinationTaken(VaultPath)
    case vaultStillBeingRead(movedName: String)
    /// Another vault opened in the window before the item moved.
    case vaultClosed(movedName: String)
    /// The person dismissed the "Update links?" question without answering it.
    case cancelled(movedName: String)
    /// Notes name the item in Wikilinks, which cannot hold `newName`.
    case nameBreaksWikilinks(newName: String, movedName: String)
    case failed(message: String)

    var message: String {
        switch self {
        case .noVaultOpen: "No vault is open."
        case .alreadyMoving: "The item is already being moved."
        case .destinationTaken(let destination): "“\(destination.rawValue)” already exists."
        case .vaultStillBeingRead(let movedName): "Graphite is still reading the vault, so the links to “\(movedName)” cannot be updated yet. Try again when reading has finished."
        case .vaultClosed(let movedName): "“\(movedName)” was not moved, because its vault is no longer open here."
        case .cancelled(let movedName): "“\(movedName)” was not renamed."
        case .nameBreaksWikilinks(let newName, let movedName):
            "“\(newName)” cannot be used, because notes link to “\(movedName)” with Wikilinks, and a Wikilink cannot hold # ^ [ ] or |. Nothing was moved."
        case .failed(let message): message
        }
    }
}

/// Shared by every copy of a `PendingMove`: the dialog answers with the copy it was
/// shown with, which may predate the moves queued behind it.
final class QueuedMoves {
    private(set) var requests: [(path: VaultPath, destination: VaultPath)] = []

    func append(_ path: VaultPath, to destination: VaultPath) {
        guard !requests.contains(where: { request in request.path == path && request.destination == destination }) else { return }
        requests.append((path, destination))
    }

    func removeAll() -> [(path: VaultPath, destination: VaultPath)] {
        defer { requests.removeAll() }
        return requests
    }
}

/// Changes made to an open note or canvas while its file was moving, for its new place.
struct EditDuringMove {
    let newPath: VaultPath
    /// The whole file as the open document would save it.
    let data: Data
    /// The extension of the copy kept beside the moved file when it changed during the move.
    let copyExtension: String
    /// The file as it was just before the move, which the changes were made over;
    /// nil when it could not be read then.
    let revisionBeforeMove: FileRevision?
    /// The draft of the text, which goes once the text is in a file.
    var draftKeeper: DocumentDraftKeeper?
}

/// File explorer actions: new folders, renaming and moving with link updates, copies,
/// and deletion, following the vault's Obsidian settings.
extension WorkspaceModel {
    var fileOperations: VaultFileOperations? {
        guard let store, let index else { return nil }
        return VaultFileOperations(store: store, index: index)
    }

    func createFolder(named name: String, in directory: VaultPath) async {
        guard let store else { return }
        do {
            let folder = try await store.createFolder(named: name, in: directory)
            if !directory.rawValue.isEmpty { expandedFolders.insert(directory) }
            expandedFolders.insert(folder)
            await refreshDirectory()
        } catch { errorMessage = error.localizedDescription }
    }

    /// Renames a file (keeping its extension) or a folder.
    func rename(_ path: VaultPath, to newName: String) async {
        let isFolder = isDirectory(path)
        let trimmedName = newName.trimmingCharacters(in: .whitespaces)
        if let problem = FileNameRules.problem(with: trimmedName, isNote: !isFolder && DocumentKind(path: path) == .markdown) {
            errorMessage = problem
            return
        }
        let fileExtension = (path.name as NSString).pathExtension
        let fileName = isFolder || fileExtension.isEmpty ? trimmedName : trimmedName + "." + fileExtension
        guard fileName != path.name else { return }
        do { await move(path, to: try path.parent.appending(fileName)) }
        catch { errorMessage = error.localizedDescription }
    }

    /// Moves a file or folder into `folder`, keeping its name.
    func move(_ path: VaultPath, into folder: VaultPath) async {
        guard !folder.isInside(path), folder != path.parent else { return }
        do { await move(path, to: try folder.appending(path.name)) }
        catch { errorMessage = error.localizedDescription }
    }

    /// Plans the link updates; asks first unless "Automatically update internal links" is on.
    @discardableResult
    func move(_ path: VaultPath, to destination: VaultPath) async -> FileMoveOutcome {
        guard let fileOperations else { return .refused(.noVaultOpen) }
        guard !pathsBeingMoved.contains(path) else {
            notice = FileMoveRefusal.alreadyMoving.message
            return .refused(.alreadyMoving)
        }
        // A drop of several items asks one question at a time; the rest wait for its answer,
        // and their links are planned only once the earlier moves are done.
        if let pendingMove {
            if pendingMove.path == path { return .awaitingAnswer }
            pendingMove.queuedMoves.append(path, to: destination)
            return .queued
        }
        if isTakenByAnotherItem(destination, movingFrom: path) {
            let refusal = FileMoveRefusal.destinationTaken(destination)
            errorMessage = refusal.message
            return .refused(refusal)
        }
        // Notes linking to the item are found through the index. Before a scan this launch
        // finishes, some would be missed and their links silently left broken. An index
        // complete from an earlier launch is checked in moments, so that is waited for.
        guard await isIndexCompleteAfterRunningScan() else {
            let refusal = FileMoveRefusal.vaultStillBeingRead(movedName: path.name)
            errorMessage = refusal.message
            return .refused(refusal)
        }
        pathsBeingMoved.insert(path)
        let stopShowingProgress = startShowingMoveProgress(of: path)
        defer {
            pathsBeingMoved.remove(path)
            stopShowingProgress()
        }
        return await planAndCompleteMove(of: path, to: destination, through: fileOperations)
    }

    /// Whether the window still has the vault `fileOperations` acts on. Paths mean nothing in
    /// another one, where the same path can name another file.
    private func isVaultOpen(_ fileOperations: VaultFileOperations) -> Bool {
        store === fileOperations.store
    }

    private func refuseMoveInClosedVault(of path: VaultPath) -> FileMoveOutcome {
        let refusal = FileMoveRefusal.vaultClosed(movedName: path.name)
        errorMessage = refusal.message
        return .refused(refusal)
    }

    private func completeMove(_ path: VaultPath, to destination: VaultPath, plan: LinkUpdatePlan, updatesLinks: Bool,
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

    private func planAndCompleteMove(of path: VaultPath, to destination: VaultPath, through fileOperations: VaultFileOperations) async -> FileMoveOutcome {
        do {
            let editedNotePaths = tabDocuments.values.compactMap(\.markdownSession).filter(\.hasUnsavedChanges).map(\.path)
                + tabDocuments.values.compactMap(\.canvasSession).filter(\.hasUnsavedChanges).map(\.path)
            try await saveOpenDocuments()
            guard isVaultOpen(fileOperations) else { return refuseMoveInClosedVault(of: path) }
            // Links just typed into those notes are planned only once the index has read them.
            if let index, let root = folderAccess?.root, !editedNotePaths.isEmpty { try await index.refresh(paths: editedNotePaths, root: root) }
            // The index must know where the last move put things, or the notes it moved would
            // be looked for at their old paths and their links silently left broken.
            await indexRefreshFollowingMoves?.value
            let plan = try await fileOperations.linkUpdates(forMoving: path, to: destination)
            if plan.hasNameThatBreaksWikilinks {
                // Nothing has moved yet, so no link is broken.
                let refusal = FileMoveRefusal.nameBreaksWikilinks(newName: destination.name, movedName: path.name)
                errorMessage = refusal.message
                return .refused(refusal)
            }
            guard isVaultOpen(fileOperations) else { return refuseMoveInClosedVault(of: path) }
            if let pendingMove {
                // Another move asked its question while this one was being planned.
                pendingMove.queuedMoves.append(path, to: destination)
                return .queued
            } else if plan.changedLinkCount > 0 && !vaultSettings.updatesLinksAutomatically {
                pendingMove = PendingMove(path: path, destination: destination, plan: plan, fileOperations: fileOperations)
                return .awaitingAnswer
            } else {
                return await completeMove(path, to: destination, plan: plan, updatesLinks: true, through: fileOperations)
            }
        } catch {
            errorMessage = error.localizedDescription
            return .refused(.failed(message: error.localizedDescription))
        }
    }

    /// The person's answer to "Update links?". The move is passed in: the dialog clears
    /// `pendingMove` as it closes, before its button's action runs. Dismissing the question
    /// without an answer cancels the moves queued behind it too.
    func resolve(_ pendingMove: PendingMove, updatesLinks: Bool, alwaysUpdates: Bool = false) async {
        if self.pendingMove?.id == pendingMove.id { self.pendingMove = nil }
        // Marked before the first suspension, so whoever waits for one of these moves never
        // sees it neither asked about nor moving while the answer is carried out.
        let answeredPaths = Set([pendingMove.path] + pendingMove.queuedMoves.requests.map { request in request.path })
        pathsMovingAfterAnswer.formUnion(answeredPaths)
        defer { pathsMovingAfterAnswer.subtract(answeredPaths) }
        if alwaysUpdates {
            var settings = vaultSettings
            settings.updatesLinksAutomatically = true
            await updateVaultSettings(settings)
        }
        answeredMoveOutcomes[pendingMove.path] = await completeMove(pendingMove.path, to: pendingMove.destination, plan: pendingMove.plan,
                                                                    updatesLinks: updatesLinks, through: pendingMove.fileOperations)
        guard isVaultOpen(pendingMove.fileOperations) else { return } // The moves queued behind it name paths of that vault.
        // A queued move that needs its own question asks it, and the rest queue behind that one.
        for request in pendingMove.queuedMoves.removeAll() {
            let outcome = await move(request.path, to: request.destination)
            // A move that asks its own question is answered by a later `resolve`.
            if outcome != .awaitingAnswer && outcome != .queued { answeredMoveOutcomes[request.path] = outcome }
        }
    }

    /// How long a move runs before it says so. A big folder's links are planned and rewritten
    /// before the file tree changes, which otherwise looks as if nothing is happening.
    private static let moveProgressDelay = Duration.seconds(1)

    /// Says that `path` is being moved, once that has taken a moment.
    /// - Returns: What to call as the move ends; another message by then stays.
    func startShowingMoveProgress(of path: VaultPath) -> () -> Void {
        let message = "Moving “\(path.name)”…"
        let showing = Task { [weak self, clock] in
            do { try await clock.sleep(for: Self.moveProgressDelay) } catch { return }
            self?.notice = message
        }
        return { [weak self] in
            showing.cancel()
            if self?.notice == message { self?.notice = nil }
        }
    }

    /// Whether another file or folder already has `destination`'s name. A change of
    /// capitals alone names the same item on a case-insensitive volume, and is allowed.
    private func isTakenByAnotherItem(_ destination: VaultPath, movingFrom path: VaultPath) -> Bool {
        guard let root = folderAccess?.root, let destinationLocation = try? destination.url(in: root),
              FileManager.default.fileExists(atPath: destinationLocation.path) else { return false }
        guard let sourceLocation = try? path.url(in: root),
              let sourceIdentifier = try? sourceLocation.resourceValues(forKeys: [.fileResourceIdentifierKey]).fileResourceIdentifier,
              let destinationIdentifier = try? destinationLocation.resourceValues(forKeys: [.fileResourceIdentifierKey]).fileResourceIdentifier
        else { return true }
        return !sourceIdentifier.isEqual(destinationIdentifier)
    }

    /// The notes shown by name in the message; a folder move can leave many more.
    private static let maximumListedNotesNotUpdated = 20

    /// Which notes kept their old links, each with the reason `VaultFileOperations` gave.
    static func describeNotesNotUpdated(_ failures: [VaultPath: LinkUpdateFailure], movedItemName: String) -> String {
        let notes = failures.keys.sorted()
        var listedNotes = notes.prefix(maximumListedNotesNotUpdated).map { note in
            "“\(note.name)” (\(failures[note]?.explanation ?? "it could not be updated"))"
        }
        if notes.count > maximumListedNotesNotUpdated { listedNotes.append("\(notes.count - maximumListedNotesNotUpdated) more") }
        let noteCount = notes.count == 1 ? "1 note" : "\(notes.count) notes"
        return "“\(movedItemName)” was moved, but the links to it in \(noteCount) were not updated: " + listedNotes.joined(separator: "; ") + "."
    }

    /// Notes in the cloud could not be looked at. A notice, not an alert: a vault with
    /// many such notes would otherwise stop the work at every rename.
    static func describeNotesNotChecked(_ notes: [VaultPath], movedItemName: String) -> String {
        let noteCount = notes.count == 1 ? "1 note is" : "\(notes.count.formatted()) notes are"
        return "\(noteCount) in the cloud and not on this device, so links to “\(movedItemName)” in them could not be updated. "
            + "They may still name it as it was."
    }

    func duplicate(_ path: VaultPath) async {
        guard let store else { return }
        do {
            try await saveOpenDocuments()
            let filesInFolder = isDirectory(path) ? (try await index?.paths(inside: path) ?? []) : []
            let copy = try await store.duplicate(path)
            // A copied folder's files are indexed one by one; the folder itself has no row.
            let copiedFiles = filesInFolder.isEmpty ? [copy] : filesInFolder.compactMap { file in try? file.replacingPrefix(path, with: copy) }
            refreshIndexAfterFileChanges(copiedFiles)
            if !isDirectory(copy) { await open(copy) }
            await showInListings(copy)
        } catch { errorMessage = error.localizedDescription }
    }

    /// Makes a copy of each item beside it, as Make a Copy does for one, without opening any of
    /// the copies. An item whose copy fails is named in the message; the others are still copied.
    func duplicate(_ paths: [VaultPath]) async {
        guard let store, !paths.isEmpty else { return }
        do { try await saveOpenDocuments() } catch {
            errorMessage = "Open documents could not be saved before copying, so nothing was copied."
            return
        }
        var copiedFiles: [VaultPath] = []
        var failedNames: [String] = []
        for path in paths {
            do {
                let filesInFolder = isDirectory(path) ? (try await index?.paths(inside: path) ?? []) : []
                let copy = try await store.duplicate(path)
                // A copied file's path is always valid.
                let copiedInside = filesInFolder.compactMap { file in try? file.replacingPrefix(path, with: copy) } // Not valid: not indexed here.
                copiedFiles += filesInFolder.isEmpty ? [copy] : copiedInside
            } catch {
                failedNames.append("“\(path.name)”")
            }
        }
        refreshIndexAfterFileChanges(copiedFiles)
        await refreshDirectory()
        if !failedNames.isEmpty { errorMessage = "Could not make a copy of " + failedNames.joined(separator: ", ") + "." }
    }

    /// Deletes at once, or asks first when "Confirm file deletion" is on.
    func requestDeletion(of path: VaultPath) async {
        if vaultSettings.confirmsDeletion { pendingDeletion = path } else { await delete(path) }
    }

    func delete(_ path: VaultPath) async {
        guard let store else { return }
        do {
            // Edits still waiting for autosave are saved first: the copy in the trash is then
            // complete, and a deletion that fails loses nothing. The tabs close only once the
            // deletion succeeds (`forgetInNavigation`); a save attempted after that finds the
            // file gone and fails rather than bringing it back.
            try await saveDocuments(inside: path)
            let removedFiles = isDirectory(path) ? (try await index?.paths(inside: path) ?? []) : [path]
            // Copies first, with any unsaved edits: the vault's settings may delete permanently.
            let notesWithoutCopy = await snapshotBeforeDeleting(removedFiles)
            let outcome = try await store.delete(path, method: vaultSettings.deletionMethod)
            await forgetDrafts(inside: path)
            expandedFolders = expandedFolders.filter { folder in !folder.isInside(path) }
            forgetInNavigation(path)
            refreshIndexAfterFileChanges(removedFiles)
            await showInListings(path)
            if case .movedToVaultTrash = outcome, vaultSettings.deletionMethod == .systemTrash {
                notice = "This storage has no system trash, so “\(path.name)” was moved to the vault's .trash folder instead."
            }
            if notesWithoutCopy > 0 {
                notice = "File recovery kept copies of \(Self.maximumNotesCopiedBeforeDeletion) of the notes in “\(path.name)”, the most it copies at once; "
                    + "\(notesWithoutCopy.formatted()) more have none."
            }
        } catch { errorMessage = error.localizedDescription }
    }

    /// Shows the current file in the sidebar's file list, wherever this is asked from: the
    /// Files panel in place of a search or a plugin's view, every folder above the file open,
    /// and a request that shows the sidebar and scrolls the list to the file.
    func revealCurrentFile() {
        guard let path = selection else { return }
        deviceDefaults.set(SidebarPanel.files.rawValue, forKey: SidebarPanelSettingKey.panel)
        searchQuery = ""
        communityPlugins.shownSidebarViewIdentifier = nil
        // The file shows in the tree as it is, not among a filter's matches.
        fileTreeContents.filter.clear()
        fileTreeContents.revealedFolder = nil
        var folder = path.parent
        while !folder.rawValue.isEmpty {
            expandedFolders.insert(folder)
            folder = folder.parent
        }
        fileRevealRequest = FileRevealRequest(path: path)
    }

    func collapseAllFolders() {
        expandedFolders.removeAll()
    }

    func isDirectory(_ path: VaultPath) -> Bool {
        guard let root = folderAccess?.root, let location = try? path.url(in: root) else { return false }
        return (try? location.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }

    /// Saves the open notes and PDFs of `path` or of files inside it.
    private func saveDocuments(inside path: VaultPath) async throws {
        for document in tabDocuments.values where document.loadedPath?.isInside(path) == true { try await document.save() }
    }

    /// Refreshes the index rows of moved files, with the next move waiting for it. A scan would
    /// leave no way to wait short of the whole vault, and it reads these same files.
    func refreshIndexFollowingMove(_ paths: [VaultPath]) {
        guard let index, let root = folderAccess?.root else { return }
        let uniquePaths = Array(Set(paths))
        let previousRefresh = indexRefreshFollowingMoves
        indexRefreshFollowingMoves = Task(priority: .userInitiated) { [weak self] in
            await previousRefresh?.value
            do { try await index.refresh(paths: uniquePaths, root: root) } catch { self?.indexingMessage = "Index needs attention" }
            self?.recordIndexChange(paths: nil)
        }
    }

    /// Refreshes the index rows of changed files; beyond a few hundred, one scan is cheaper.
    /// A scan already running may have passed these files, and starting another does
    /// nothing until it ends, so the rows are then refreshed one by one instead.
    private func refreshIndexAfterFileChanges(_ paths: [VaultPath]) {
        let uniquePaths = Array(Set(paths))
        if uniquePaths.count > Self.maximumIncrementalRefreshCount, !isIndexing { startIndexing() } else { refreshIndex(for: uniquePaths) }
    }
}
