/**
 * File: FilesAndSavedDataTests.swift
 * ----------------------------------
 * Layer: Tests
 * Description: The section "Files and saved data" of the bug hunt, through `WorkspaceModel` against real
 *              temporary vault folders: renames and moves, windows on two vaults, versions, recovery.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 04/11/2026
 */

import XCTest
import PDFKit
import GraphiteCore
import GraphiteIndex
@testable import GraphiteUI
import GraphiteTestSupport

@MainActor
final class FilesAndSavedDataTests: XCTestCase {
    private var device: IsolatedWorkspaceDevice!
    private var processServices: ProcessServices!

    override func setUp() async throws {
        device = try IsolatedWorkspaceDevice.make(for: self)
        processServices = device.makeServices()
    }

    // MARK: HUNT-083: names a Wikilink cannot hold

    func testRenamingAnImageToANameAWikilinkCannotHoldIsRefusedAndNothingMoves() async throws {
        let (workspace, vault) = try await makeWorkspace(files: ["photo.png": "image", "Note.md": "![[photo.png]]"])
        await workspace.rename(try VaultPath("photo.png"), to: "photo #2")
        XCTAssertTrue(workspace.errorMessage?.contains("Wikilink") == true)
        XCTAssertEqual(try text(of: "Note.md", in: vault), "![[photo.png]]")
        XCTAssertTrue(FileManager.default.fileExists(atPath: vault.appendingPathComponent("photo.png").path))
    }

    func testAFolderNameAWikilinkCannotHoldIsRefusedOnlyWhenALinkMustSpellIt() async throws {
        let (workspace, vault) = try await makeWorkspace(files: ["CS/Note.md": "body", "Linker.md": "[[CS/Note]]"])
        await workspace.rename(try VaultPath("CS"), to: "C#")
        XCTAssertNotNil(workspace.errorMessage)
        XCTAssertEqual(try text(of: "Linker.md", in: vault), "[[CS/Note]]")

        let (otherWorkspace, otherVault) = try await makeWorkspace(files: ["CS/Note.md": "body", "Linker.md": "[[Note]]"])
        await otherWorkspace.rename(try VaultPath("CS"), to: "C#")
        XCTAssertNil(otherWorkspace.errorMessage, "A link by name does not spell the folder.")
        XCTAssertEqual(try text(of: "Linker.md", in: otherVault), "[[Note]]")
        XCTAssertTrue(FileManager.default.fileExists(atPath: otherVault.appendingPathComponent("C#/Note.md").path))
    }

    func testAMarkdownLinkHoldsSuchANameEncoded() async throws {
        let (workspace, vault) = try await makeWorkspace(files: ["photo.png": "image", "Note.md": "![a](photo.png) ![b](<photo.png>)"])
        await renameAnsweringUpdateLinks(try VaultPath("photo.png"), to: "photo #2", in: workspace)
        XCTAssertNil(workspace.errorMessage)
        XCTAssertEqual(try text(of: "Note.md", in: vault), "![a](photo%20%232.png) ![b](<photo %232.png>)")
    }

    // MARK: HUNT-084: a rename right after a big move

    func testARenameRightAfterMovingAFolderUpdatesTheMovedNotes() async throws {
        var files = ["Target.md": "target"]
        for number in 0..<120 { files["Big/Note \(number).md"] = "[[Target]]" }
        let (workspace, vault) = try await makeWorkspace(files: files)
        await renameAnsweringUpdateLinks(try VaultPath("Big"), to: "Moved", in: workspace)
        await renameAnsweringUpdateLinks(try VaultPath("Target.md"), to: "Renamed", in: workspace)
        XCTAssertNil(workspace.errorMessage)
        for number in 0..<120 { XCTAssertEqual(try text(of: "Moved/Note \(number).md", in: vault), "[[Renamed]]") }
    }

    // MARK: HUNT-085: a rename that only changes capitals

    func testARenameThatOnlyChangesCapitalsLeavesOneIndexRow() async throws {
        // On a case-sensitive volume the old spelling is simply gone; the outcome is the same.
        let (workspace, _) = try await makeWorkspace(files: ["notes/idea.md": "body", "Other/Linker.md": "[[idea]]"])
        await renameAnsweringUpdateLinks(try VaultPath("notes/idea.md"), to: "Idea", in: workspace)
        await workspace.indexRefreshFollowingMoves?.value
        let index = try XCTUnwrap(workspace.index)
        let paths = try await index.paths(inside: try VaultPath("notes"))
        XCTAssertEqual(paths.map(\.rawValue), ["notes/Idea.md"])
        let resolution = try await index.resolve("idea", from: try VaultPath("Other/Linker.md"))
        XCTAssertEqual(resolution.map(\.rawValue), ["notes/Idea.md"])
    }

    // MARK: HUNT-089: windows on two vaults

    /// Both vaults have the path. The drop used to move the receiving vault's own file.
    func testADropFromAnotherVaultCopiesTheFileAndLeavesThisVaultsOwnFileAlone() async throws {
        let (receiving, receivingVault) = try await makeWorkspace(files: ["Daily.md": "receiving vault", "Folder/Keep.md": ""])
        let sendingVault = try makeVault(files: ["Daily.md": "sending vault"])
        let item = VaultItemTransfer(path: "Daily.md", vaultRoot: sendingVault)

        XCTAssertTrue(receiving.takeDroppedItems([item], into: try VaultPath("Folder")))
        try await waitUntil { FileManager.default.fileExists(atPath: receivingVault.appendingPathComponent("Folder/Daily.md").path) }

        XCTAssertEqual(try text(of: "Daily.md", in: receivingVault), "receiving vault")
        XCTAssertEqual(try text(of: "Folder/Daily.md", in: receivingVault), "sending vault")
        XCTAssertEqual(try text(of: "Daily.md", in: sendingVault), "sending vault", "The original stays.")
    }

    func testADropFromThisVaultMovesTheFile() async throws {
        let (workspace, vault) = try await makeWorkspace(files: ["Daily.md": "text", "Folder/Keep.md": ""])
        let item = VaultItemTransfer(path: "Daily.md", vaultRoot: vault)
        XCTAssertTrue(workspace.takeDroppedItems([item], into: try VaultPath("Folder")))
        try await waitUntil { FileManager.default.fileExists(atPath: vault.appendingPathComponent("Folder/Daily.md").path) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: vault.appendingPathComponent("Daily.md").path))
    }

    func testATransferSaysWhichVaultItCameFromAndAnOldOneCountsAsThisVaults() throws {
        let vault = URL(fileURLWithPath: "/tmp/Vault A")
        let item = VaultItemTransfer(path: "Note.md", vaultRoot: vault)
        let decoded = try JSONDecoder().decode(VaultItemTransfer.self, from: JSONEncoder().encode(item))
        XCTAssertEqual(decoded.path(inVaultAt: vault), try VaultPath("Note.md"))
        XCTAssertNil(decoded.path(inVaultAt: URL(fileURLWithPath: "/tmp/Vault B")))
        XCTAssertTrue(decoded.isFromAnotherVault(than: URL(fileURLWithPath: "/tmp/Vault B")))
        let withoutVault = try JSONDecoder().decode(VaultItemTransfer.self, from: Data(#"{"path":"Note.md"}"#.utf8))
        XCTAssertEqual(withoutVault.path(inVaultAt: vault), try VaultPath("Note.md"))
    }

    // MARK: HUNT-091: moved by another app or window

    /// A real coordinated move, as Files or another window makes, reported to the open window.
    func testANoteMovedElsewhereFollowsInTheTabWithItsUnsavedText() async throws {
        let (workspace, vault) = try await makeWorkspace(files: ["Lecture.md": "saved", "Other.md": ""])
        await workspace.open(try VaultPath("Lecture.md"))
        let note = try XCTUnwrap(workspace.markdownSession)
        note.text = "saved and typed"

        try coordinatedMove(from: vault.appendingPathComponent("Lecture.md"), to: vault.appendingPathComponent("Renamed.md"))

        let renamed = try VaultPath("Renamed.md")
        try await waitUntil { workspace.selection == renamed }
        try await waitUntil { (try? self.text(of: "Renamed.md", in: vault)) == "saved and typed" }
        XCTAssertNil(workspace.errorMessage)
        XCTAssertFalse(FileManager.default.fileExists(atPath: vault.appendingPathComponent("Lecture.md").path))
    }

    /// The file changed as it moved: the text goes beside it, so neither is lost.
    func testUnsavedTextGoesBesideAFileThatAlsoChanged() async throws {
        let (workspace, vault) = try await makeWorkspace(files: ["Lecture.md": "saved", "Other.md": ""])
        await workspace.open(try VaultPath("Lecture.md"))
        let note = try XCTUnwrap(workspace.markdownSession)
        note.text = "typed"
        try Data("changed elsewhere".utf8).write(to: vault.appendingPathComponent("Lecture.md"))
        try FileManager.default.moveItem(at: vault.appendingPathComponent("Lecture.md"), to: vault.appendingPathComponent("Renamed.md"))

        await workspace.followExternalMove(from: vault.appendingPathComponent("Lecture.md"), to: vault.appendingPathComponent("Renamed.md"))

        XCTAssertEqual(try text(of: "Renamed.md", in: vault), "changed elsewhere")
        XCTAssertEqual(try text(of: "Renamed Graphite edits.md", in: vault), "typed")
    }

    /// A file saved by moving a new one over its name has not moved.
    func testASaveByReplacingIsNotAMove() async throws {
        let (workspace, vault) = try await makeWorkspace(files: ["Lecture.md": "saved", "Backup.md": "older"])
        await workspace.open(try VaultPath("Lecture.md"))
        await workspace.followExternalMove(from: vault.appendingPathComponent("Lecture.md"), to: vault.appendingPathComponent("Backup.md"))
        XCTAssertEqual(workspace.selection, try VaultPath("Lecture.md"))
    }

    func testAFolderMovedElsewhereTakesItsTabsAlong() async throws {
        let (workspace, vault) = try await makeWorkspace(files: ["Course/Week/Lecture.md": "saved", "Other.md": ""])
        await workspace.open(try VaultPath("Course/Week/Lecture.md"))
        try coordinatedMove(from: vault.appendingPathComponent("Course"), to: vault.appendingPathComponent("Moved"))
        let moved = try VaultPath("Moved/Week/Lecture.md")
        try await waitUntil { workspace.selection == moved }
    }

    // MARK: HUNT-093: a rename keeps the place

    func testRenamingTheOpenNoteKeepsItsPlace() async throws {
        let body = String(repeating: "A line of the lecture.\n", count: 200)
        let (workspace, _) = try await makeWorkspace(files: ["Lecture.md": body, "Other.md": ""])
        await workspace.open(try VaultPath("Lecture.md"))
        let note = try XCTUnwrap(workspace.markdownSession)
        note.returnTo(NotePlace(topLocation: 2_000, selectionLocation: 2_100, selectionLength: 0))

        await workspace.rename(try VaultPath("Lecture.md"), to: "Renamed")
        let renamed = try VaultPath("Renamed.md")
        try await waitUntil { workspace.selection == renamed }
        await workspace.open(renamed)

        let reopened = try XCTUnwrap(workspace.markdownSession)
        XCTAssertEqual(reopened.path, renamed)
        XCTAssertEqual(reopened.selection.location, 2_100, "The cursor stays where it was.")
        XCTAssertEqual(reopened.savedScrollLocation, 2_000, "The note shows the line it showed.")
    }

    // MARK: HUNT-094: copies off the store

    /// A save does not wait for a folder copy, which used to run on the store's actor.
    func testASaveDoesNotWaitForAFolderCopy() async throws {
        let vault = try makeVault(files: ["Note.md": "text"])
        let folder = vault.appendingPathComponent("Large")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let fileCount = 4_000
        for number in 0..<fileCount { try Data("file".utf8).write(to: folder.appendingPathComponent("File \(number).txt")) }
        let store = VaultStore(root: vault)
        let path = try VaultPath("Note.md")
        let revision = try await store.read(path).revision

        let copying = Task { try await store.duplicate(try VaultPath("Large")) }
        let copyFolder = vault.appendingPathComponent("Large 1")
        try await waitUntil { FileManager.default.fileExists(atPath: copyFolder.path) }
        _ = try await store.save(Data("saved during the copy".utf8), at: path, expecting: .revision(revision))
        let copiedWhenSaved = (try? FileManager.default.contentsOfDirectory(atPath: copyFolder.path).count) ?? 0
        _ = try await copying.value

        XCTAssertLessThan(copiedWhenSaved, fileCount, "The save finished before the copy did.")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: copyFolder.path).count, fileCount)
    }

    // MARK: HUNT-090: choosing a version while in conflict

    func testChoosingAVersionOfANoteInConflictKeepsTheUnsavedTextAndWorks() async throws {
        let (workspace, vault) = try await makeWorkspace(files: ["Lecture.md": "saved", "Other.md": ""])
        let lecture = try VaultPath("Lecture.md")
        let conflictVersions = try FakeConflictVersionStore()
        workspace.conflictVersionStore = conflictVersions
        let location = vault.appendingPathComponent("Lecture.md")
        let version = try conflictVersions.addVersion(of: location, contents: Data("kept version".utf8), deviceName: "Mac", modified: .now)
        await workspace.open(lecture)
        let note = try XCTUnwrap(workspace.markdownSession)
        note.text = "typed"
        try Data("other device".utf8).write(to: location)
        await note.checkExternalChange()
        XCTAssertTrue(note.hasExternalConflict)

        let listing = try await workspace.conflictVersionListing(of: lecture)
        try await workspace.replaceCurrentVersion(of: lecture, with: version, listedIn: listing)

        XCTAssertEqual(try text(of: "Lecture.md", in: vault), "kept version")
        XCTAssertEqual(try text(of: "Lecture Graphite edits.md", in: vault), "typed", "The unsaved text is not lost.")
        XCTAssertFalse(note.hasExternalConflict)
        XCTAssertEqual(note.text, "kept version")
    }

    // MARK: HUNT-099: ink on a PDF that is moving

    func testEditsOfAnOpenPDFMadeWhileItMovedGoToACopyBesideIt() async throws {
        let (workspace, vault) = try await makeWorkspace(files: ["Other.md": ""])
        let location = vault.appendingPathComponent("Handout.pdf")
        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        let context = try XCTUnwrap(CGContext(location as CFURL, mediaBox: &mediaBox, nil))
        context.beginPDFPage(nil)
        context.endPDFPage()
        context.closePDF()
        await workspace.open(try VaultPath("Handout.pdf"))
        let pdf = try XCTUnwrap(workspace.tabDocuments.values.compactMap(\.pdfSession).first)
        try await pdf.importPages(from: location, at: 1)
        XCTAssertTrue(pdf.hasUnsavedChanges)
        // The first save happens before the move; the edit below is one made during it.
        let copyLocation = try await pdf.saveSeparateCopy(inFolder: vault.appendingPathComponent("Moved Folder"))
        XCTAssertEqual(copyLocation.deletingLastPathComponent().lastPathComponent, "Moved Folder")
        XCTAssertTrue(FileManager.default.fileExists(atPath: copyLocation.path))
    }

    /// A real rename of the PDF's folder, long enough to edit the PDF during it: 2,000 notes
    /// link to the PDF, so the move rewrites them before the tab follows. The edit made while
    /// the move ran used to go with the session the tab let go of.
    func testAnEditOfAnOpenPDFMadeWhileItsFolderIsRenamedIsKeptInACopyBesideIt() async throws {
        var files = ["Other.md": ""]
        for number in 0..<2_000 { files["Notes/Note \(number).md"] = "[[Course/Handout.pdf]]" }
        let vault = try makeVault(files: files)
        let course = vault.appendingPathComponent("Course")
        try FileManager.default.createDirectory(at: course, withIntermediateDirectories: true)
        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        let context = try XCTUnwrap(CGContext(course.appendingPathComponent("Handout.pdf") as CFURL, mediaBox: &mediaBox, nil))
        context.beginPDFPage(nil)
        context.endPDFPage()
        context.closePDF()
        let workspace = WorkspaceModel(processServices: processServices, clock: LiveApplicationClock())
        try await workspace.openFolderAsVault(vault)
        try await waitUntil { workspace.hasCompletedIndexScan }
        await workspace.open(try VaultPath("Course/Handout.pdf"))
        let pdf = try XCTUnwrap(workspace.tabDocuments.values.compactMap(\.pdfSession).first)

        await workspace.rename(try VaultPath("Course"), to: "Course 2026")
        let question = try XCTUnwrap(workspace.pendingMove, "Graphite asks whether to update the 2,000 links")
        // Made while the question is open: saved before anything moves.
        try pdf.rotatePages([0], clockwise: true)
        var hasMoveEnded = false
        let answering = Task {
            await workspace.resolve(question, updatesLinks: true)
            hasMoveEnded = true
        }
        try await waitUntil("the edit made before the move is saved") { !pdf.hasUnsavedChanges }
        XCTAssertFalse(hasMoveEnded, "The move is still rewriting links")
        XCTAssertTrue(workspace.tabDocuments.values.contains { document in document.pdfSession === pdf }, "The tab still has the session")
        // Made while the move runs.
        try pdf.rotatePages([0], clockwise: true)
        await answering.value

        let movedFolder = vault.appendingPathComponent("Course 2026")
        let movedHandout = try XCTUnwrap(PDFDocument(url: movedFolder.appendingPathComponent("Handout.pdf")))
        XCTAssertEqual(movedHandout.page(at: 0)?.rotation, 90, "The edit saved before the move went with the file")
        let pdfsBeside = try FileManager.default.contentsOfDirectory(at: movedFolder, includingPropertiesForKeys: nil).filter { location in location.pathExtension == "pdf" }
        let rotations = pdfsBeside.compactMap { location in PDFDocument(url: location)?.page(at: 0)?.rotation }
        XCTAssertTrue(rotations.contains(180), "The edit made during the move is kept: \(pdfsBeside.map(\.lastPathComponent)) turned \(rotations)")
        XCTAssertTrue(workspace.errorMessage?.contains("saved separately") == true, "The message names the copy: \(workspace.errorMessage ?? "none")")
        XCTAssertEqual(try text(of: "Notes/Note 1999.md", in: vault), "[[Course 2026/Handout.pdf]]")
    }

    // MARK: HUNT-100: a move that takes a while

    func testAskingToMoveAnItemAlreadyMovingSaysSo() async throws {
        let (workspace, _) = try await makeWorkspace(files: ["Lecture.md": "text", "Other.md": ""])
        let path = try VaultPath("Lecture.md")
        workspace.pathsBeingMoved.insert(path)
        let outcome = await workspace.move(path, to: try VaultPath("Renamed.md"))
        XCTAssertEqual(outcome, .refused(.alreadyMoving))
        XCTAssertEqual(workspace.notice, FileMoveRefusal.alreadyMoving.message)
    }

    func testAMoveThatTakesAWhileSaysSoUntilItEnds() async throws {
        let clock = ManualClock()
        let vault = try makeVault(files: ["Lecture.md": "text", "Other.md": ""])
        let workspace = WorkspaceModel(processServices: processServices, clock: clock)
        try await workspace.openFolderAsVault(vault)
        try await waitUntil { workspace.hasCompletedIndexScan }
        let stopShowing = workspace.startShowingMoveProgress(of: try VaultPath("Lecture.md"))
        XCTAssertNil(workspace.notice, "A quick move says nothing.")
        try await waitUntil { clock.pendingSleepDurations.contains(.seconds(1)) }
        clock.advance(by: .seconds(1))
        try await waitUntil { workspace.notice == "Moving “Lecture.md”…" }
        stopShowing()
        XCTAssertNil(workspace.notice)
    }

    // MARK: HUNT-101: copies before deleting

    /// Pictures used to take up the limit of 500, leaving notes without a copy.
    func testDeletingAFolderCopiesItsNotesWhateverElseIsInIt() async throws {
        var files: [String: String] = [:]
        for number in 0..<600 { files["Course/picture \(number).png"] = "image" }
        files["Course/Lecture.md"] = "the only note"
        let (workspace, _) = try await makeWorkspace(files: files)
        workspace.preferences.setEnabled(.fileRecovery, true)
        let paths = try files.keys.map(VaultPath.init)
        await workspace.snapshotBeforeDeleting(paths)
        let fileRecovery = try XCTUnwrap(workspace.fileRecovery)
        XCTAssertEqual(try fileRecovery.snapshots(for: try VaultPath("Course/Lecture.md")).count, 1)
    }

    func testTheNotesLeftWithoutACopyAreCounted() async throws {
        let (workspace, _) = try await makeWorkspace(files: ["Other.md": "text"])
        workspace.preferences.setEnabled(.fileRecovery, true)
        // Paths with no file: the count is what is checked, not the copies.
        let paths = try (0..<(WorkspaceModel.maximumNotesCopiedBeforeDeletion + 3)).map { number in try VaultPath("Gone/Note \(number).md") }
        let notesWithoutCopy = await workspace.snapshotBeforeDeleting(paths)
        XCTAssertEqual(notesWithoutCopy, 3)
    }

    // MARK: HUNT-102: a note grown past the limit

    func testANoteGrownPastTheLimitIsSavedAndSaysSo() async throws {
        let (workspace, vault) = try await makeWorkspace(files: ["Lecture.md": "saved"])
        await workspace.open(try VaultPath("Lecture.md"))
        let note = try XCTUnwrap(workspace.markdownSession)
        note.text = String(repeating: "x", count: MarkdownSession.maximumEditableBytes + 1)
        try await note.save()
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: vault.appendingPathComponent("Lecture.md").path)[.size] as? Int, MarkdownSession.maximumEditableBytes + 1)
        XCTAssertTrue(note.errorMessage?.contains("8 MB") == true)
    }

    // MARK: Helpers

    private func makeVault(files: [String: String]) throws -> URL {
        let vault = try TemporaryVault.make(prefix: "SavedDataVault", for: self).root.resolvingSymlinksInPath()
        for (relativePath, contents) in files {
            let location = vault.appendingPathComponent(relativePath)
            try FileManager.default.createDirectory(at: location.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(contents.utf8).write(to: location)
        }
        return vault
    }

    private func makeWorkspace(files: [String: String]) async throws -> (WorkspaceModel, URL) {
        let vault = try makeVault(files: files)
        let workspace = WorkspaceModel(processServices: processServices, clock: LiveApplicationClock())
        try await workspace.openFolderAsVault(vault)
        try await waitUntil { workspace.hasCompletedIndexScan }
        return (workspace, vault)
    }

    /// A rename, with "Update Links" chosen when Graphite asks.
    private func renameAnsweringUpdateLinks(_ path: VaultPath, to name: String, in workspace: WorkspaceModel) async {
        await workspace.rename(path, to: name)
        if let question = workspace.pendingMove { await workspace.resolve(question, updatesLinks: true) }
    }

    private func coordinatedMove(from oldLocation: URL, to newLocation: URL) throws {
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        var moveError: Error?
        coordinator.coordinate(writingItemAt: oldLocation, options: .forMoving, writingItemAt: newLocation, options: .forReplacing, error: &coordinationError) { coordinatedOld, coordinatedNew in
            do {
                coordinator.item(at: coordinatedOld, willMoveTo: coordinatedNew)
                try FileManager.default.moveItem(at: coordinatedOld, to: coordinatedNew)
                coordinator.item(at: coordinatedOld, didMoveTo: coordinatedNew)
            } catch { moveError = error }
        }
        if let coordinationError { throw coordinationError }
        if let moveError { throw moveError }
    }

    private func text(of relativePath: String, in vault: URL) throws -> String {
        try String(contentsOf: vault.appendingPathComponent(relativePath), encoding: .utf8)
    }
}
