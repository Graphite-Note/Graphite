/**
 * File: RenamingAnOpenNoteTests.swift
 * -----------------------------------
 * Layer: Tests
 * Description: A rename or move of a note that is open keeps its live session: its text, cursor, undo history and
 *              unsaved state, with every write at the new place and none at the old one (HUNT-093).
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 02/11/2026
 */

import XCTest
import GraphiteCore
@testable import GraphiteUI
import GraphiteTestSupport

@MainActor
final class RenamingAnOpenNoteTests: XCTestCase {
    private var device: IsolatedWorkspaceDevice!
    private var processServices: ProcessServices!

    override func setUp() async throws {
        device = try IsolatedWorkspaceDevice.make(for: self)
        processServices = device.makeServices()
    }

    // MARK: Typing

    func testTypingJustBeforeARenameEndsUpInTheRenamedFile() async throws {
        let (workspace, vault) = try await makeWindowAndVault(files: ["Lecture.md": "saved", "Other.md": ""])
        let note = try await open("Lecture.md", in: workspace)
        note.selection = NSRange(location: 3, length: 0)
        note.text = "saved and typed"

        await workspace.rename(try VaultPath("Lecture.md"), to: "Renamed")

        XCTAssertTrue(workspace.openMarkdownSession(at: try VaultPath("Renamed.md")) === note, "The note goes on in the session that was open.")
        XCTAssertEqual(note.path, try VaultPath("Renamed.md"))
        XCTAssertEqual(note.selection.location, 3, "The cursor stays.")
        XCTAssertEqual(try text(of: "Renamed.md", in: vault), "saved and typed")
        XCTAssertFalse(exists("Lecture.md", in: vault))
        XCTAssertFalse(note.hasUnsavedChanges)
        XCTAssertNil(workspace.errorMessage)
    }

    /// Typing and an autosave while the move runs: the save waits for the new place, so the
    /// old path is never written or made again, and no conflict is reported.
    func testTypingAndSavingDuringARenameEndUpInTheRenamedFile() async throws {
        var files = ["Lecture.md": "saved", "Other.md": ""]
        for linkerNumber in 1...40 { files["Linker \(linkerNumber).md"] = "[lecture](Lecture.md)" }
        let (workspace, vault) = try await makeWindowAndVault(files: files)
        workspace.vaultSettings.updatesLinksAutomatically = true
        let note = try await open("Lecture.md", in: workspace)
        let vaultIdentifier = try XCTUnwrap(workspace.currentVaultIdentifier)

        let move = Task { @MainActor in await workspace.rename(try VaultPath("Lecture.md"), to: "Renamed") }
        try await waitForSavesToBeHeld(of: note)
        note.text = "typed during the move"
        let autosave = Task { @MainActor in try await note.save() }
        try await move.value
        try await autosave.value

        XCTAssertTrue(workspace.openMarkdownSession(at: try VaultPath("Renamed.md")) === note)
        XCTAssertEqual(try text(of: "Renamed.md", in: vault), "typed during the move")
        XCTAssertFalse(exists("Lecture.md", in: vault), "Nothing makes the old path again.")
        XCTAssertFalse(note.isSaving, "The hold ends with the move.")
        XCTAssertFalse(note.hasExternalConflict)
        XCTAssertNil(note.errorMessage)
        XCTAssertNil(workspace.errorMessage)
        let drafts = await processServices.unsavedDrafts.drafts(inVault: vaultIdentifier)
        XCTAssertTrue(drafts.isEmpty, "The text reached the file, so nothing waits in a draft.")
    }

    /// The moment the existing test of typing during a move watches for: the file has left the
    /// old place and the links elsewhere are still being rewritten.
    func testTextTypedAfterTheFileLeftItsOldPlaceGoesOnInTheSameSession() async throws {
        var files = ["Lecture.md": "saved", "Sub/Existing.md": ""]
        for linkerNumber in 1...40 { files["Linker \(linkerNumber).md"] = "[lecture](Lecture.md)" }
        let (workspace, vault) = try await makeWindowAndVault(files: files)
        workspace.vaultSettings.updatesLinksAutomatically = true
        let note = try await open("Lecture.md", in: workspace)
        let move = Task { @MainActor in await workspace.move(try VaultPath("Lecture.md"), into: try VaultPath("Sub")) }
        let oldLocation = vault.appendingPathComponent("Lecture.md")
        try await waitUntil("the file left its old place", pollingIntervalSeconds: 0.001) { !FileManager.default.fileExists(atPath: oldLocation.path) }
        try XCTSkipIf(note.path != (try VaultPath("Lecture.md")), "The move finished before the test could type into the note.")
        note.text = "typed after it left"
        try await move.value

        XCTAssertEqual(note.path, try VaultPath("Sub/Lecture.md"))
        XCTAssertEqual(try text(of: "Sub/Lecture.md", in: vault), "typed after it left")
        XCTAssertFalse(exists("Lecture.md", in: vault))
        XCTAssertFalse(exists("Sub/Lecture Graphite edits.md", in: vault), "The file is still the version the text was made over, so no copy is needed.")
    }

    // MARK: Undo

    #if os(macOS)
    func testUndoAfterARenameRestoresTheTextAndKeepsWritingToTheNewPath() async throws {
        let (workspace, vault) = try await makeWindowAndVault(files: ["Lecture.md": "First line.", "Other.md": ""])
        let note = try await open("Lecture.md", in: workspace)
        let editor = try MacMarkdownEditorFixture(showing: note)
        defer { editor.tearDown() }
        let undoManager = editor.coordinator.noteUndoManager
        editor.textView.insertText(" Typed.", replacementRange: NSRange(location: 11, length: 0))
        XCTAssertEqual(note.text, "First line. Typed.")
        XCTAssertTrue(undoManager.canUndo)

        await workspace.rename(try VaultPath("Lecture.md"), to: "Renamed")
        XCTAssertEqual(try text(of: "Renamed.md", in: vault), "First line. Typed.")
        XCTAssertTrue(workspace.openMarkdownSession(at: try VaultPath("Renamed.md")) === note, "The editor's note is the one the tab shows.")
        XCTAssertTrue(undoManager.canUndo, "The history stays with the editor.")

        undoManager.undo()

        // The text view tells the session on the next turn of the run loop.
        try await waitUntil("the session to take the undone text") { note.text == "First line." }
        try await note.save()
        XCTAssertEqual(try text(of: "Renamed.md", in: vault), "First line.")
        XCTAssertFalse(exists("Lecture.md", in: vault))
        undoManager.redo()
        try await waitUntil("the session to take the redone text") { note.text == "First line. Typed." }
        try await note.save()
        XCTAssertEqual(try text(of: "Renamed.md", in: vault), "First line. Typed.")
    }
    #endif

    // MARK: Drafts

    /// A draft made while the file moves goes with it, and the save that follows clears it.
    func testADraftMadeDuringARenameFollowsAndGoesOnceTheTextIsSaved() async throws {
        var files = ["Lecture.md": "saved", "Other.md": ""]
        for linkerNumber in 1...40 { files["Linker \(linkerNumber).md"] = "[lecture](Lecture.md)" }
        let (workspace, vault) = try await makeWindowAndVault(files: files)
        workspace.vaultSettings.updatesLinksAutomatically = true
        let note = try await open("Lecture.md", in: workspace)
        let vaultIdentifier = try XCTUnwrap(workspace.currentVaultIdentifier)
        let move = Task { @MainActor in await workspace.rename(try VaultPath("Lecture.md"), to: "Renamed") }
        try await waitForSavesToBeHeld(of: note)
        note.text = "typed before quitting"
        let isKept = await note.keepUnsavedTextInDraft()
        XCTAssertTrue(isKept)
        try await move.value

        XCTAssertEqual(try text(of: "Renamed.md", in: vault), "typed before quitting")
        let drafts = await processServices.unsavedDrafts.drafts(inVault: vaultIdentifier)
        XCTAssertTrue(drafts.isEmpty, "No draft is left at either path: \(drafts.map(\.path))")
    }

    /// Text that cannot be saved yet: its draft is at the new path, where it is kept from now on
    /// and found the next time the note opens.
    func testADraftOfTextThatCannotBeSavedFollowsTheNote() async throws {
        let (workspace, vault) = try await makeWindowAndVault(files: ["Folder/Lecture.md": "saved", "Other.md": ""])
        let folder = vault.appendingPathComponent("Folder")
        addTeardownBlock { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path) }
        let note = try await open("Folder/Lecture.md", in: workspace)
        let vaultIdentifier = try XCTUnwrap(workspace.currentVaultIdentifier)
        note.text = "typed"
        let isKept = await note.keepUnsavedTextInDraft()
        XCTAssertTrue(isKept)
        try FileManager.default.moveItem(at: folder.appendingPathComponent("Lecture.md"), to: folder.appendingPathComponent("Renamed.md"))
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: folder.path)

        await workspace.followExternalMove(from: folder.appendingPathComponent("Lecture.md"), to: folder.appendingPathComponent("Renamed.md"))

        XCTAssertEqual(note.path, try VaultPath("Folder/Renamed.md"))
        XCTAssertTrue(note.hasUnsavedChanges, "A read-only folder takes no save, and the text stays open.")
        let drafts = await processServices.unsavedDrafts.drafts(inVault: vaultIdentifier)
        XCTAssertEqual(drafts.map(\.path), [try VaultPath("Folder/Renamed.md")])
        XCTAssertEqual(drafts.map(\.contents), [Data("typed".utf8)])
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path)
        try await note.save()
        let draftsAfterSaving = await processServices.unsavedDrafts.drafts(inVault: vaultIdentifier)
        XCTAssertTrue(draftsAfterSaving.isEmpty, "The session's keeper names the new path, so the draft goes with the save.")
    }

    // MARK: Other windows

    func testTheSameNoteInASecondWindowFollows() async throws {
        let (firstWindow, vault) = try await makeWindowAndVault(files: ["Lecture.md": "saved", "Other.md": ""])
        let secondWindow = try await makeWindow(on: vault)
        let firstNote = try await open("Lecture.md", in: firstWindow)
        let secondNote = try await open("Lecture.md", in: secondWindow)
        let newPath = try VaultPath("Renamed.md")
        firstNote.text = "typed in the first window"
        XCTAssertEqual(secondNote.text, "typed in the first window")

        await firstWindow.rename(try VaultPath("Lecture.md"), to: "Renamed")

        XCTAssertEqual(secondNote.path, newPath, "The second window's session goes on at the new place at once.")
        // Its tab follows when its file presenter reports the move, as the system does.
        await secondWindow.followExternalMove(from: vault.appendingPathComponent("Lecture.md"), to: vault.appendingPathComponent("Renamed.md"))
        XCTAssertTrue(secondWindow.openMarkdownSession(at: newPath) === secondNote)
        XCTAssertEqual(secondWindow.layout.activeTab.path, newPath)
        XCTAssertEqual(secondWindow.tabDocuments[secondWindow.layout.activeTab.id]?.loadedPath, newPath)
        secondNote.text = "typed in the second window"
        XCTAssertEqual(firstNote.text, "typed in the second window", "They are still one text.")
        try await secondNote.save()
        XCTAssertEqual(try text(of: "Renamed.md", in: vault), "typed in the second window")
        XCTAssertFalse(firstNote.hasUnsavedChanges, "A save in one window is the saved state of both.")
        try await firstNote.save()
        XCTAssertFalse(exists("Lecture.md", in: vault))
        XCTAssertFalse(firstNote.hasExternalConflict || secondNote.hasExternalConflict)
    }

    // MARK: A rename that fails

    func testARenameThatFailsLeavesTheNoteOnItsOldPathWithItsText() async throws {
        let (workspace, vault) = try await makeWindowAndVault(files: ["Lecture.md": "saved", "Locked/Existing.md": ""])
        let locked = vault.appendingPathComponent("Locked")
        addTeardownBlock { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path) }
        let note = try await open("Lecture.md", in: workspace)
        note.text = "typed first"
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: locked.path)

        await workspace.move(try VaultPath("Lecture.md"), into: try VaultPath("Locked"))

        XCTAssertNotNil(workspace.errorMessage, "The person is told.")
        XCTAssertEqual(note.path, try VaultPath("Lecture.md"))
        XCTAssertTrue(workspace.openMarkdownSession(at: try VaultPath("Lecture.md")) === note)
        XCTAssertEqual(note.text, "typed first")
        XCTAssertFalse(note.isSaving, "The hold ended with the failure.")
        note.text = "typed after it failed"
        try await note.save()
        XCTAssertEqual(try text(of: "Lecture.md", in: vault), "typed after it failed")
        XCTAssertFalse(exists("Locked/Lecture.md", in: vault))
    }

    // MARK: External changes

    func testExternalChangeDetectionDoesNotReportTheRenamedFile() async throws {
        let (workspace, vault) = try await makeWindowAndVault(files: ["Lecture.md": "saved", "Other.md": ""])
        let note = try await open("Lecture.md", in: workspace)
        await workspace.rename(try VaultPath("Lecture.md"), to: "Renamed")

        await workspace.checkOpenDocumentsForExternalChanges()
        XCTAssertNil(note.errorMessage)
        XCTAssertFalse(note.hasExternalConflict)
        XCTAssertEqual(note.text, "saved")

        note.text = "typed after the rename"
        await workspace.checkOpenDocumentsForExternalChanges()
        XCTAssertFalse(note.hasExternalConflict, "The file is the version the text was made over.")
        XCTAssertNil(note.errorMessage)

        // A real change at the new place is still seen.
        try await note.save()
        try Data("from another app".utf8).write(to: vault.appendingPathComponent("Renamed.md"))
        await workspace.checkOpenDocumentsForExternalChanges()
        XCTAssertEqual(note.text, "from another app")
    }

    /// Another app's rename, with text not saved yet: the same session saves it at the new place.
    func testANoteMovedByAnotherAppKeepsItsSessionAndItsUnsavedText() async throws {
        let (workspace, vault) = try await makeWindowAndVault(files: ["Lecture.md": "saved", "Other.md": ""])
        let note = try await open("Lecture.md", in: workspace)
        note.text = "typed"
        try FileManager.default.moveItem(at: vault.appendingPathComponent("Lecture.md"), to: vault.appendingPathComponent("Renamed.md"))

        await workspace.followExternalMove(from: vault.appendingPathComponent("Lecture.md"), to: vault.appendingPathComponent("Renamed.md"))

        XCTAssertTrue(workspace.openMarkdownSession(at: try VaultPath("Renamed.md")) === note)
        XCTAssertEqual(try text(of: "Renamed.md", in: vault), "typed")
        XCTAssertFalse(exists("Lecture.md", in: vault))
        XCTAssertNil(note.errorMessage)
    }

    // MARK: Folders

    func testAFolderMoveTakesTheNotesOpenInsideItAlong() async throws {
        let (workspace, vault) = try await makeWindowAndVault(files: ["Course/Week/Lecture.md": "lecture", "Course/Summary.md": "summary", "Archive/Existing.md": ""])
        let lecture = try await open("Course/Week/Lecture.md", in: workspace)
        let summary = try await open("Course/Summary.md", in: workspace, placement: .newTab)
        lecture.text = "lecture typed"

        await workspace.move(try VaultPath("Course"), into: try VaultPath("Archive"))

        XCTAssertTrue(workspace.openMarkdownSession(at: try VaultPath("Archive/Course/Week/Lecture.md")) === lecture)
        XCTAssertTrue(workspace.openMarkdownSession(at: try VaultPath("Archive/Course/Summary.md")) === summary)
        XCTAssertEqual(try text(of: "Archive/Course/Week/Lecture.md", in: vault), "lecture typed")
        summary.text = "summary typed"
        try await summary.save()
        XCTAssertEqual(try text(of: "Archive/Course/Summary.md", in: vault), "summary typed")
        XCTAssertFalse(exists("Course", in: vault), "Nothing makes the old folder again.")
        XCTAssertNil(workspace.errorMessage)
    }

    // MARK: When the move rewrites the note itself

    /// With nothing unsaved, the rewritten text comes in through the same session.
    func testANoteWhoseOwnLinksTheMoveRewroteShowsThemInTheSameSession() async throws {
        let (workspace, vault) = try await makeWindowAndVault(files: ["Lecture.md": "[other](Other.md)", "Other.md": "", "Sub/Existing.md": ""])
        workspace.vaultSettings.updatesLinksAutomatically = true
        let note = try await open("Lecture.md", in: workspace)

        await workspace.move(try VaultPath("Lecture.md"), into: try VaultPath("Sub"))

        XCTAssertTrue(workspace.openMarkdownSession(at: try VaultPath("Sub/Lecture.md")) === note)
        XCTAssertEqual(note.text, "[other](../Other.md)")
        XCTAssertEqual(try text(of: "Sub/Lecture.md", in: vault), "[other](../Other.md)")
        XCTAssertFalse(note.hasUnsavedChanges)
    }

    /// The fallback: text typed over a file the move rewrote goes to a copy, the session that
    /// held it never writes again, and the tab loads the rewritten file.
    func testASessionLeftBehindByTheMoveNeverWritesAgain() async throws {
        var files = ["Lecture.md": "[other](Other.md)", "Other.md": "", "Sub/Existing.md": ""]
        for linkerNumber in 1...40 { files["Linker \(linkerNumber).md"] = "[lecture](Lecture.md)" }
        let (workspace, vault) = try await makeWindowAndVault(files: files)
        workspace.vaultSettings.updatesLinksAutomatically = true
        let note = try await open("Lecture.md", in: workspace)
        let vaultIdentifier = try XCTUnwrap(workspace.currentVaultIdentifier)
        let move = Task { @MainActor in await workspace.move(try VaultPath("Lecture.md"), into: try VaultPath("Sub")) }
        try await waitForSavesToBeHeld(of: note)
        note.text = "[other](Other.md) typed"
        let autosave = Task { @MainActor in try await note.save() }
        try await move.value
        try await autosave.value

        XCTAssertEqual(try text(of: "Sub/Lecture.md", in: vault), "[other](../Other.md)")
        XCTAssertEqual(try text(of: "Sub/Lecture Graphite edits.md", in: vault), "[other](Other.md) typed")
        XCTAssertFalse(exists("Lecture.md", in: vault))
        XCTAssertNil(workspace.openMarkdownSession(at: try VaultPath("Lecture.md")))
        let drafts = await processServices.unsavedDrafts.drafts(inVault: vaultIdentifier)
        XCTAssertTrue(drafts.isEmpty, "The waiting save made no draft of text already in the copy.")
    }

    // MARK: What is remembered about the note

    func testFoldsViewsAndRecoveryCopiesAfterARenameGoToTheNewPath() async throws {
        let (workspace, _) = try await makeWindowAndVault(files: ["Lecture.md": "saved", "Other.md": ""])
        let note = try await open("Lecture.md", in: workspace)
        let vaultIdentifier = try XCTUnwrap(workspace.currentVaultIdentifier)
        workspace.calloutFolds.setExpanded(true, notePath: "Lecture.md", key: "note|")
        await workspace.rename(try VaultPath("Lecture.md"), to: "Renamed")
        XCTAssertEqual(workspace.calloutFolds.expansion(for: "Renamed.md"), ["note|": true])

        note.foldedKeys = ["heading"]
        note.viewMode = note.viewMode == .reading ? .source : .reading
        note.text = "typed"
        try await note.save()

        let folds = workspace.deviceDefaults.dictionary(forKey: WorkspaceModel.foldsKey(for: vaultIdentifier)) as? [String: [String]]
        XCTAssertEqual(folds, ["Renamed.md": ["heading"]])
        let views = workspace.deviceDefaults.dictionary(forKey: WorkspaceModel.noteViewsKey(for: vaultIdentifier)) as? [String: String]
        XCTAssertEqual(views?.keys.sorted(), ["Renamed.md"])
        let recovery = try XCTUnwrap(workspace.fileRecovery)
        try await waitUntil("the recovery copy") { try !recovery.snapshots(for: try VaultPath("Renamed.md")).isEmpty }
        XCTAssertTrue(try recovery.snapshots(for: try VaultPath("Lecture.md")).isEmpty)
    }

    // MARK: Helpers

    private func makeWindow(on vault: URL) async throws -> WorkspaceModel {
        let window = WorkspaceModel(processServices: processServices, clock: LiveApplicationClock())
        try await window.openFolderAsVault(vault)
        try await waitUntil { window.hasCompletedIndexScan }
        return window
    }

    private func makeWindowAndVault(files: [String: String]) async throws -> (WorkspaceModel, URL) {
        let vault = try TemporaryVault.make(prefix: "RenamedNoteVault", for: self).root.resolvingSymlinksInPath()
        for (relativePath, contents) in files {
            let location = vault.appendingPathComponent(relativePath)
            try FileManager.default.createDirectory(at: location.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(contents.utf8).write(to: location)
        }
        return (try await makeWindow(on: vault), vault)
    }

    private func open(_ relativePath: String, in window: WorkspaceModel, placement: TabPlacement = .currentTab) async throws -> MarkdownSession {
        let path = try VaultPath(relativePath)
        await window.open(path, placement: placement)
        return try XCTUnwrap(window.openMarkdownSession(at: path))
    }

    /// A move holds a note's saves, which shows as a save running, before it touches the file.
    private func waitForSavesToBeHeld(of note: MarkdownSession) async throws {
        try await waitUntil("the move to hold the note's saves", pollingIntervalSeconds: 0.001) { note.isSaving }
    }

    private func text(of relativePath: String, in vault: URL) throws -> String {
        try String(contentsOf: vault.appendingPathComponent(relativePath), encoding: .utf8)
    }

    private func exists(_ relativePath: String, in vault: URL) -> Bool {
        FileManager.default.fileExists(atPath: vault.appendingPathComponent(relativePath).path)
    }
}
