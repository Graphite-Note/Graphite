/**
 * File: UnsavedDocumentDraftTests.swift
 * -------------------------------------
 * Layer: Tests
 * Description: Text that cannot reach its file outlives the app in a draft outside the vault, against
 *              real temporary folders: restored on reopen, cleared by a save, never written over a
 *              newer file, and quitting is not refused for good.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 01/11/2026
 */

import XCTest
import GraphiteCore
@testable import GraphiteUI
import GraphiteTestSupport

@MainActor
final class UnsavedDocumentDraftTests: XCTestCase {
    private var device: IsolatedWorkspaceDevice!
    private var processServices: ProcessServices!

    override func setUp() async throws {
        device = try IsolatedWorkspaceDevice.make(for: self)
        processServices = device.makeServices()
    }

    // MARK: A note that cannot be saved

    /// The hunt's case: a conflict while typing, then the app ends. The later launch shows
    /// the text with the conflict still open, and the newer file is not touched.
    func testConflictedTextComesBackAfterTheAppEndsAndNeverOverwritesTheNewerFile() async throws {
        let vault = try makeVault(["Lecture.md": "saved"])
        let (window, note) = try await window(showing: "Lecture.md", in: vault)
        note.text = "typed on the iPad"
        try Data("from another device".utf8).write(to: vault.appendingPathComponent("Lecture.md"))
        await note.checkExternalChange()
        XCTAssertTrue(note.hasExternalConflict)
        let vaultIdentifier = try XCTUnwrap(window.currentVaultIdentifier)
        let draftsBeforeEnding = await processServices.unsavedDrafts.drafts(inVault: vaultIdentifier)
        XCTAssertEqual(draftsBeforeEnding.map(\.contents), [Data("typed on the iPad".utf8)], "The conflict alone keeps the text.")

        let (laterLaunch, laterNote) = try await laterLaunchWindow(showing: "Lecture.md", vaultIdentifier: vaultIdentifier)
        XCTAssertEqual(laterNote.text, "typed on the iPad")
        XCTAssertTrue(laterNote.hasExternalConflict, "The file is newer than the text, so this is the same conflict.")
        XCTAssertNotNil(laterLaunch.errorMessage)
        do {
            try await laterNote.save()
            XCTFail("A newer file is never overwritten.")
        } catch { XCTAssertEqual(error as? GraphiteError, .conflict) }
        await laterNote.checkExternalChange()
        XCTAssertTrue(laterNote.hasExternalConflict, "Checking the file again does not end the conflict.")
        XCTAssertEqual(try text(of: "Lecture.md", in: vault), "from another device")
    }

    /// Saving failed for another reason (here the folder is read-only) and the file is
    /// still the version the text was made over: the text goes on to be saved.
    func testTextOfAFailedSaveComesBackAndIsSavedWhenTheFileIsStillTheSameVersion() async throws {
        let vault = try makeVault(["Folder/Lecture.md": "saved"])
        let folder = vault.appendingPathComponent("Folder")
        addTeardownBlock { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path) }
        let (window, note) = try await window(showing: "Folder/Lecture.md", in: vault)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: folder.path)
        note.text = "typed"
        do {
            try await note.save()
            throw XCTSkip("This file system lets a read-only folder be written.")
        } catch let skip as XCTSkip { throw skip } catch {}
        let vaultIdentifier = try XCTUnwrap(window.currentVaultIdentifier)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path)

        let (_, laterNote) = try await laterLaunchWindow(showing: "Folder/Lecture.md", vaultIdentifier: vaultIdentifier)
        XCTAssertEqual(laterNote.text, "typed")
        XCTAssertFalse(laterNote.hasExternalConflict)
        try await laterNote.save()
        XCTAssertEqual(try text(of: "Folder/Lecture.md", in: vault), "typed")
        let draftsAfterSaving = await processServices.unsavedDrafts.drafts(inVault: vaultIdentifier)
        XCTAssertEqual(draftsAfterSaving, [], "A successful save clears the draft.")
    }

    func testChoosingTheOtherVersionClearsTheDraft() async throws {
        let vault = try makeVault(["Lecture.md": "saved"])
        let (window, note) = try await window(showing: "Lecture.md", in: vault)
        note.text = "typed"
        try Data("other".utf8).write(to: vault.appendingPathComponent("Lecture.md"))
        await note.checkExternalChange()
        try await note.reload()
        let vaultIdentifier = try XCTUnwrap(window.currentVaultIdentifier)
        let drafts = await processServices.unsavedDrafts.drafts(inVault: vaultIdentifier)
        XCTAssertEqual(drafts, [])
    }

    func testSaveACopyEndsTheConflictAndClearsTheDraft() async throws {
        let vault = try makeVault(["Lecture.md": "saved"])
        let (window, note) = try await window(showing: "Lecture.md", in: vault)
        note.text = "typed"
        try Data("other".utf8).write(to: vault.appendingPathComponent("Lecture.md"))
        await note.checkExternalChange()
        _ = try await note.saveSeparateCopy()
        XCTAssertEqual(note.text, "other")
        XCTAssertEqual(try text(of: "Lecture Graphite edits.md", in: vault), "typed")
        let vaultIdentifier = try XCTUnwrap(window.currentVaultIdentifier)
        let drafts = await processServices.unsavedDrafts.drafts(inVault: vaultIdentifier)
        XCTAssertEqual(drafts, [])
    }

    /// Saves that succeed never touch the drafts folder: no draft, not even the folder.
    func testNormalSavesWriteNoDraft() async throws {
        let vault = try makeVault(["Lecture.md": "saved"])
        let (_, note) = try await window(showing: "Lecture.md", in: vault)
        note.text = "typed"
        try await note.save()
        XCTAssertFalse(FileManager.default.fileExists(atPath: processServices.unsavedDrafts.directory.path))
    }

    /// Leaving the screen writes the draft before the save, which may be slow; the save
    /// that then succeeds clears it. A note undone back to the file needs no draft either.
    func testADraftKeptBeforeASuccessfulSaveIsClearedByIt() async throws {
        let vault = try makeVault(["Lecture.md": "saved"])
        let (window, note) = try await window(showing: "Lecture.md", in: vault)
        let vaultIdentifier = try XCTUnwrap(window.currentVaultIdentifier)
        note.text = "typed"
        let isSafe = await window.keepUnsavedTextInDrafts()
        XCTAssertTrue(isSafe)
        let keptDrafts = await processServices.unsavedDrafts.drafts(inVault: vaultIdentifier)
        XCTAssertEqual(keptDrafts.count, 1)
        try await note.save()
        let draftsAfterSave = await processServices.unsavedDrafts.drafts(inVault: vaultIdentifier)
        XCTAssertEqual(draftsAfterSave, [])

        note.text = "typed more"
        _ = await window.keepUnsavedTextInDrafts()
        note.text = "typed"
        try await note.save()
        let draftsAfterUndo = await processServices.unsavedDrafts.drafts(inVault: vaultIdentifier)
        XCTAssertEqual(draftsAfterUndo, [])
    }

    /// A draft whose text is what the file holds has nothing to bring back and goes.
    func testADraftEqualToTheFileIsRemovedOnReopen() async throws {
        let vault = try makeVault(["Lecture.md": "saved"])
        let (window, note) = try await window(showing: "Lecture.md", in: vault)
        let vaultIdentifier = try XCTUnwrap(window.currentVaultIdentifier)
        note.text = "typed"
        _ = await window.keepUnsavedTextInDrafts()
        try Data("typed".utf8).write(to: vault.appendingPathComponent("Lecture.md"))

        let (laterLaunch, laterNote) = try await laterLaunchWindow(showing: "Lecture.md", vaultIdentifier: vaultIdentifier)
        XCTAssertEqual(laterNote.text, "typed")
        XCTAssertFalse(laterNote.hasUnsavedChanges)
        XCTAssertNil(laterLaunch.errorMessage)
        let drafts = await processServices.unsavedDrafts.drafts(inVault: vaultIdentifier)
        XCTAssertEqual(drafts, [])
    }

    /// The byte-order mark stays what the file has, whichever version wins.
    func testRestoredTextKeepsTheFilesByteOrderMarkWhenSaved() async throws {
        let vault = try makeVault([:])
        let bytes = Data([0xEF, 0xBB, 0xBF]) + Data("saved".utf8)
        try bytes.write(to: vault.appendingPathComponent("Lecture.md"))
        let (window, note) = try await window(showing: "Lecture.md", in: vault)
        let vaultIdentifier = try XCTUnwrap(window.currentVaultIdentifier)
        note.text = "typed"
        _ = await window.keepUnsavedTextInDrafts()

        let (_, laterNote) = try await laterLaunchWindow(showing: "Lecture.md", vaultIdentifier: vaultIdentifier)
        try await laterNote.save()
        XCTAssertEqual(try Data(contentsOf: vault.appendingPathComponent("Lecture.md")), Data([0xEF, 0xBB, 0xBF]) + Data("typed".utf8))
    }

    // MARK: A canvas

    func testCanvasEditsInConflictComeBackAfterTheAppEnds() async throws {
        let original = #"{"nodes":[],"edges":[]}"#
        let vault = try makeVault(["Board.canvas": original])
        let window = try await openWindow(on: vault)
        await window.open(try VaultPath("Board.canvas"))
        let canvas = try XCTUnwrap(window.tabDocuments.values.compactMap(\.canvasSession).first)
        canvas.isWriting = true
        XCTAssertNotNil(canvas.addTextCard())
        let other = #"{"nodes":[],"edges":[]} "#
        try Data(other.utf8).write(to: vault.appendingPathComponent("Board.canvas"))
        await canvas.checkExternalChange()
        XCTAssertTrue(canvas.hasExternalConflict)
        let editedBytes = canvas.file.data
        try? await canvas.save()
        let vaultIdentifier = try XCTUnwrap(window.currentVaultIdentifier)

        let laterLaunch = WorkspaceModel(processServices: processServices, clock: LiveApplicationClock())
        await laterLaunch.openVaultOfWindow(vaultIdentifier, tabs: .none, showing: nil)
        await laterLaunch.open(try VaultPath("Board.canvas"))
        let laterCanvas = try XCTUnwrap(laterLaunch.tabDocuments.values.compactMap(\.canvasSession).first)
        XCTAssertEqual(laterCanvas.file.data, editedBytes)
        XCTAssertTrue(laterCanvas.hasExternalConflict)
        XCTAssertEqual(try text(of: "Board.canvas", in: vault), other, "The newer file is not touched.")
    }

    // MARK: Files that moved or went

    /// The note is gone when the app comes back: the draft becomes a copy where it was, with
    /// its folder made again, and the person is told.
    func testADraftOfAGoneNoteBecomesACopyInItsFolder() async throws {
        let vault = try makeVault(["Course/Lecture.md": "saved", "Other.md": ""])
        let (window, note) = try await window(showing: "Course/Lecture.md", in: vault)
        note.text = "typed"
        _ = await window.keepUnsavedTextInDrafts()
        let vaultIdentifier = try XCTUnwrap(window.currentVaultIdentifier)
        try FileManager.default.removeItem(at: vault.appendingPathComponent("Course"))
        processServices = device.makeServices() // A new process has told nobody yet.

        let laterLaunch = WorkspaceModel(processServices: processServices, clock: LiveApplicationClock())
        await laterLaunch.openVaultOfWindow(vaultIdentifier, tabs: .none, showing: nil)
        XCTAssertEqual(try text(of: "Course/Lecture Graphite edits.md", in: vault), "typed")
        XCTAssertTrue(laterLaunch.errorMessage?.contains("Lecture Graphite edits.md") == true)
        let drafts = await processServices.unsavedDrafts.drafts(inVault: vaultIdentifier)
        XCTAssertEqual(drafts, [])
    }

    /// A note with a draft but no open tab is named when the vault opens.
    func testADraftOfANoteWithoutATabIsNamedWhenTheVaultOpens() async throws {
        let vault = try makeVault(["Lecture.md": "saved"])
        let (window, note) = try await window(showing: "Lecture.md", in: vault)
        note.text = "typed"
        _ = await window.keepUnsavedTextInDrafts()
        let vaultIdentifier = try XCTUnwrap(window.currentVaultIdentifier)
        processServices = device.makeServices()

        let laterLaunch = WorkspaceModel(processServices: processServices, clock: LiveApplicationClock())
        await laterLaunch.openVaultOfWindow(vaultIdentifier, tabs: .none, showing: nil)
        XCTAssertTrue(laterLaunch.errorMessage?.contains("Lecture.md") == true)
        XCTAssertEqual(try text(of: "Lecture.md", in: vault), "saved")
    }

    func testADraftFollowsItsNoteWhenItIsRenamed() async throws {
        let vault = try makeVault(["Lecture.md": "saved", "Other.md": ""])
        let (window, note) = try await window(showing: "Lecture.md", in: vault)
        note.text = "typed"
        _ = await window.keepUnsavedTextInDrafts()
        let vaultIdentifier = try XCTUnwrap(window.currentVaultIdentifier)
        window.moveDrafts(following: [try VaultPath("Lecture.md"): try VaultPath("Renamed.md")])
        let drafts = await processServices.unsavedDrafts.drafts(inVault: vaultIdentifier)
        XCTAssertEqual(drafts.map(\.path), [try VaultPath("Renamed.md")])
        XCTAssertEqual(drafts.first?.contents, Data("typed".utf8))
    }

    func testDeletingANoteForgetsItsDraftAndKeepsItsTextInFileRecovery() async throws {
        let vault = try makeVault(["Lecture.md": "saved", "Other.md": ""])
        let (window, note) = try await window(showing: "Lecture.md", in: vault)
        window.preferences.setEnabled(.fileRecovery, true)
        note.text = "typed"
        _ = await window.keepUnsavedTextInDrafts()
        let vaultIdentifier = try XCTUnwrap(window.currentVaultIdentifier)
        let path = try VaultPath("Lecture.md")
        await window.forgetDrafts(inside: path)
        let drafts = await processServices.unsavedDrafts.drafts(inVault: vaultIdentifier)
        XCTAssertEqual(drafts, [])
        let fileRecovery = try XCTUnwrap(window.fileRecovery)
        XCTAssertEqual(try fileRecovery.snapshots(for: path).map { snapshot in try fileRecovery.text(of: snapshot) }, ["typed"])
    }

    // MARK: Quitting (HUNT-081)

    /// The hunt's case: the note's folder was renamed elsewhere, so nothing can ever save it.
    /// Before, Save a Copy failed too and the Mac refused to quit, for good.
    func testSaveACopyWorksWhenTheNotesFolderIsGoneAndNothingThenHoldsQuitting() async throws {
        let vault = try makeVault(["Course/Week 1/Lecture.md": "saved", "Other.md": ""])
        let (window, note) = try await window(showing: "Course/Week 1/Lecture.md", in: vault)
        note.text = "typed"
        try FileManager.default.moveItem(at: vault.appendingPathComponent("Course"), to: vault.appendingPathComponent("Renamed"))
        do { try await note.save(); XCTFail("The file is gone.") } catch {}

        let copyPath = try await note.saveSeparateCopy()

        XCTAssertEqual(copyPath, try VaultPath("Course/Week 1/Lecture Graphite edits.md"))
        XCTAssertEqual(try text(of: copyPath.rawValue, in: vault), "typed")
        XCTAssertFalse(note.hasUnsavedChanges)
        XCTAssertFalse(note.hasExternalConflict)
        try await window.saveOpenDocuments()
    }

    func testACanvasCopyWorksWhenItsFolderIsGone() async throws {
        let vault = try makeVault(["Course/Board.canvas": #"{"nodes":[],"edges":[]}"#, "Other.md": ""])
        let window = try await openWindow(on: vault)
        await window.open(try VaultPath("Course/Board.canvas"))
        let canvas = try XCTUnwrap(window.tabDocuments.values.compactMap(\.canvasSession).first)
        canvas.isWriting = true
        XCTAssertNotNil(canvas.addTextCard())
        try FileManager.default.removeItem(at: vault.appendingPathComponent("Course"))
        let copyPath = try await canvas.saveSeparateCopy()
        XCTAssertEqual(copyPath, try VaultPath("Course/Board Graphite edits.canvas"))
        XCTAssertFalse(canvas.hasUnsavedChanges)
    }

    /// A vault's own folder is not made again: it would come back empty beside the real one.
    /// The draft has the text, so quitting can still go ahead.
    func testWhenTheVaultsOwnFolderIsGoneTheCopyFailsAndTheDraftKeepsTheText() async throws {
        let vault = try makeVault(["Lecture.md": "saved"])
        let (window, note) = try await window(showing: "Lecture.md", in: vault)
        let movedVault = vault.deletingLastPathComponent().appendingPathComponent(vault.lastPathComponent + " moved")
        addTeardownBlock { try? FileManager.default.removeItem(at: movedVault) }
        note.text = "typed"
        try FileManager.default.moveItem(at: vault, to: movedVault)

        do { _ = try await note.saveSeparateCopy(); XCTFail("There is nowhere to write it.") } catch {}
        XCTAssertFalse(FileManager.default.fileExists(atPath: vault.path), "The old folder is not made again.")
        do { try await window.saveOpenDocuments(); XCTFail("The file is gone.") } catch {}
        let isSafe = await window.keepUnsavedDocumentsBeforeQuitting(writesPDFCopies: true)
        XCTAssertTrue(isSafe)
        XCTAssertEqual(QuitSaveDecision(outcome: .keptInDrafts).allowsTermination, true)
        let vaultIdentifier = try XCTUnwrap(window.currentVaultIdentifier)
        let drafts = await processServices.unsavedDrafts.drafts(inVault: vaultIdentifier)
        XCTAssertEqual(drafts.map(\.contents), [Data("typed".utf8)])
    }

    /// Long names: the copy's name must fit, or the conflict has no way out (HUNT-098).
    func testSaveACopyOfANoteWithTheLongestNameAllowed() async throws {
        let longestStem = String(repeating: "日", count: 79) // 237 of the 239 bytes a typed name may have.
        XCTAssertNil(FileNameRules.problem(with: longestStem, isNote: true))
        let vault = try makeVault([longestStem + ".md": "saved"])
        let (_, note) = try await window(showing: longestStem + ".md", in: vault)
        note.text = "typed"
        try Data("other".utf8).write(to: vault.appendingPathComponent(longestStem + ".md"))
        await note.checkExternalChange()
        let copyPath = try await note.saveSeparateCopy()
        XCTAssertEqual(try text(of: copyPath.rawValue, in: vault), "typed")
        XCTAssertLessThanOrEqual(copyPath.name.utf8.count, 255)
        XCTAssertTrue(copyPath.name.hasSuffix(" Graphite edits.md"))
    }

    // MARK: Autosave trying again (HUNT-087)

    /// A failed autosave is tried again, waiting longer, without another keystroke; before,
    /// the text waited for one. It stops at a conflict.
    func testAFailedAutosaveIsTriedAgainUntilItReachesTheFile() async throws {
        let vault = try makeVault(["Folder/Lecture.md": "saved"])
        let folder = vault.appendingPathComponent("Folder")
        addTeardownBlock { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path) }
        let store = VaultStore(root: vault)
        let path = try VaultPath("Folder/Lecture.md")
        let note = try MarkdownSession(path: path, snapshot: try await store.read(path), store: store, didSave: { _ in })
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: folder.path)
        note.text = "typed"
        do { try await note.save(); throw XCTSkip("This file system lets a read-only folder be written.") } catch let skip as XCTSkip { throw skip } catch {}

        var delays: [Duration] = []
        await note.autosave(after: .milliseconds(900)) { delay in
            delays.append(delay)
            // The disk is writable again from the third try.
            if delays.count == 3 { try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path) }
        }

        XCTAssertEqual(delays, [.milliseconds(900), .seconds(2), .seconds(4)])
        XCTAssertFalse(note.hasUnsavedChanges)
        XCTAssertEqual(try text(of: "Folder/Lecture.md", in: vault), "typed")
    }

    func testAnAutosaveInConflictWaitsForThePersonsChoice() async throws {
        let vault = try makeVault(["Lecture.md": "saved"])
        let store = VaultStore(root: vault)
        let path = try VaultPath("Lecture.md")
        let note = try MarkdownSession(path: path, snapshot: try await store.read(path), store: store, didSave: { _ in })
        note.text = "typed"
        try Data("other".utf8).write(to: vault.appendingPathComponent("Lecture.md"))
        var sleepCount = 0
        await note.autosave(after: .milliseconds(900)) { _ in sleepCount += 1 }
        XCTAssertEqual(sleepCount, 1)
        XCTAssertTrue(note.hasExternalConflict)
    }

    func testRetryDelaysDoubleUpToTheirLimit() {
        let delays = (1...8).map { failureCount in AutosaveRetryPolicy.delay(afterConsecutiveFailures: failureCount) }
        XCTAssertEqual(delays, [.seconds(2), .seconds(4), .seconds(8), .seconds(16), .seconds(32), .seconds(60), .seconds(60), .seconds(60)])
    }

    /// A canvas tries again too: before it stopped at the first failure (`try?`).
    func testAFailedCanvasAutosaveIsTriedAgain() async throws {
        let clock = ManualClock()
        let vault = try makeVault(["Folder/Board.canvas": #"{"nodes":[],"edges":[]}"#])
        let folder = vault.appendingPathComponent("Folder")
        addTeardownBlock { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path) }
        let store = VaultStore(root: vault)
        let path = try VaultPath("Folder/Board.canvas")
        let canvas = try CanvasSession(path: path, snapshot: try await store.read(path), store: store, clock: clock, deviceDefaults: device.defaults, didSave: { _ in })
        canvas.isWriting = true
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: folder.path)
        XCTAssertNotNil(canvas.addTextCard())
        // The first autosave fails and a second waits on the clock, with no further edit.
        try await clock.awaitPendingSleepers()
        clock.advance(by: CanvasSession.autosaveDelay)
        for _ in 0..<400 where canvas.errorMessage == nil { try await Task.sleep(for: .milliseconds(5)) }
        try XCTSkipIf(canvas.errorMessage == nil, "This file system lets a read-only folder be written.")
        XCTAssertTrue(canvas.hasUnsavedChanges)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path)
        try await clock.awaitPendingSleepers()
        clock.advance(by: AutosaveRetryPolicy.delay(afterConsecutiveFailures: 1))
        for _ in 0..<400 where canvas.hasUnsavedChanges { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertFalse(canvas.hasUnsavedChanges, "The second try reached the file.")
    }

    // MARK: Conflict ending by itself (HUNT-097)

    func testTheConflictEndsAndTheTextIsSavedWhenTheFileGoesBackToItsVersion() async throws {
        let vault = try makeVault(["Lecture.md": "saved"])
        let (_, note) = try await window(showing: "Lecture.md", in: vault)
        note.text = "typed"
        try Data("other".utf8).write(to: vault.appendingPathComponent("Lecture.md"))
        await note.checkExternalChange()
        XCTAssertTrue(note.hasExternalConflict)
        try Data("saved".utf8).write(to: vault.appendingPathComponent("Lecture.md"))
        await note.checkExternalChange()
        XCTAssertFalse(note.hasExternalConflict)
        XCTAssertNil(note.errorMessage)
        XCTAssertEqual(try text(of: "Lecture.md", in: vault), "typed")
    }

    // MARK: File recovery (HUNT-088)

    /// Another app's change replaces the last saved text: that text is copied even when a
    /// copy was taken a moment ago.
    func testAVersionReplacedByAnotherAppIsCopiedWhateverTheInterval() async throws {
        let vault = try makeVault(["Lecture.md": "first"])
        let (window, note) = try await window(showing: "Lecture.md", in: vault)
        window.preferences.setEnabled(.fileRecovery, true)
        let fileRecovery = try XCTUnwrap(window.fileRecovery)
        note.text = "second"
        try await note.save()
        note.text = "third"
        try await note.save() // Copies "second" only if the interval allows; "third" is in the file alone.
        try Data("from elsewhere".utf8).write(to: vault.appendingPathComponent("Lecture.md"))
        await note.checkExternalChange()
        XCTAssertEqual(note.text, "from elsewhere")
        let path = try VaultPath("Lecture.md")
        for _ in 0..<200 {
            let snapshots = try fileRecovery.snapshots(for: path)
            if try snapshots.contains(where: { snapshot in try fileRecovery.text(of: snapshot) == "third" }) { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("The replaced version was not kept.")
    }

    // MARK: Helpers

    private func makeVault(_ files: [String: String]) throws -> URL {
        let vault = try TemporaryVault.make(prefix: "DraftVault", for: self).root.resolvingSymlinksInPath()
        for (relativePath, contents) in files {
            let location = vault.appendingPathComponent(relativePath)
            try FileManager.default.createDirectory(at: location.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(contents.utf8).write(to: location)
        }
        return vault
    }

    private func openWindow(on vault: URL) async throws -> WorkspaceModel {
        let window = WorkspaceModel(processServices: processServices, clock: LiveApplicationClock())
        try await window.openFolderAsVault(vault)
        return window
    }

    private func window(showing relativePath: String, in vault: URL) async throws -> (WorkspaceModel, MarkdownSession) {
        let window = try await openWindow(on: vault)
        await window.open(try VaultPath(relativePath))
        return (window, try XCTUnwrap(window.tabDocuments.values.compactMap(\.markdownSession).first))
    }

    /// The same device after the app ended: a new process's services and a window on the vault.
    private func laterLaunchWindow(showing relativePath: String, vaultIdentifier: UUID) async throws -> (WorkspaceModel, MarkdownSession) {
        processServices = device.makeServices()
        let window = WorkspaceModel(processServices: processServices, clock: LiveApplicationClock())
        await window.openVaultOfWindow(vaultIdentifier, tabs: .none, showing: nil)
        await window.open(try VaultPath(relativePath))
        return (window, try XCTUnwrap(window.tabDocuments.values.compactMap(\.markdownSession).first))
    }

    private func text(of relativePath: String, in vault: URL) throws -> String {
        try String(contentsOf: vault.appendingPathComponent(relativePath), encoding: .utf8)
    }
}
