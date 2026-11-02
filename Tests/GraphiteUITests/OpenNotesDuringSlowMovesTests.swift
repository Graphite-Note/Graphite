/**
 * File: OpenNotesDuringSlowMovesTests.swift
 * -----------------------------------------
 * Layer: Tests
 * Description: What a move that takes long, or never ends, does to open notes: typing is on disk meanwhile, nothing
 *              waits without limit, another note's unsaved text at the new path is kept apart, and a vault opened
 *              meanwhile is left alone (HUNT-093).
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 02/11/2026
 */

import XCTest
import GraphiteCore
@testable import GraphiteUI
import GraphiteTestSupport

/// Holds a coordinated move of a file until told to let go, as a file provider that does not answer does.
/// The lock synchronizes the presenter's queue with the test.
private final class FileHoldingPresenter: NSObject, NSFilePresenter, @unchecked Sendable {
    let presentedItemURL: URL?
    let presentedItemOperationQueue = OperationQueue()
    private let lock = NSLock()
    private var writer: (@Sendable ((@Sendable () -> Void)?) -> Void)?
    private var hasLetGo = false

    init(holding location: URL) {
        presentedItemURL = location.resolvingSymlinksInPath()
        super.init()
        presentedItemOperationQueue.maxConcurrentOperationCount = 1
        NSFileCoordinator.addFilePresenter(self)
    }

    var isHoldingAWriter: Bool {
        lock.withLock { writer != nil }
    }

    func relinquishPresentedItem(toWriter writer: @escaping @Sendable ((@Sendable () -> Void)?) -> Void) {
        let letGoAlready = lock.withLock {
            if !hasLetGo { self.writer = writer }
            return hasLetGo
        }
        if letGoAlready { writer(nil) }
        // A test that goes wrong fails rather than waiting for ever.
        DispatchQueue.global().asyncAfter(deadline: .now() + 60) { self.letGo() }
    }

    func letGo() {
        let (isFirstTime, waitingWriter) = lock.withLock {
            defer {
                hasLetGo = true
                writer = nil
            }
            return (!hasLetGo, writer)
        }
        waitingWriter?(nil)
        if isFirstTime { NSFileCoordinator.removeFilePresenter(self) }
    }
}

@MainActor
final class OpenNotesDuringSlowMovesTests: XCTestCase {
    private var device: IsolatedWorkspaceDevice!
    private var processServices: ProcessServices!

    override func setUp() async throws {
        device = try IsolatedWorkspaceDevice.make(for: self)
        processServices = device.makeServices()
    }

    // MARK: Typing during a slow move

    /// The text is on disk while the move runs, so a crash or a power cut loses nothing.
    func testTextASaveWaitsWithIsInADraftWhileTheMoveRuns() async throws {
        let (workspace, vault) = try await makeWindowAndVault(files: ["Lecture.md": "saved", "Other.md": ""])
        let note = try await open("Lecture.md", in: workspace)
        let vaultIdentifier = try XCTUnwrap(workspace.currentVaultIdentifier)
        let presenter = FileHoldingPresenter(holding: vault.appendingPathComponent("Lecture.md"))
        defer { presenter.letGo() }
        let move = Task { @MainActor in await workspace.rename(try VaultPath("Lecture.md"), to: "Renamed") }
        try await waitUntil("the move to reach the file") { presenter.isHoldingAWriter }

        note.text = "typed during the move"
        let autosave = Task { @MainActor in try await note.save() }

        try await waitUntil("the draft to reach the disk") {
            await self.processServices.unsavedDrafts.drafts(inVault: vaultIdentifier).map(\.contents) == [Data("typed during the move".utf8)]
        }
        XCTAssertEqual(try text(of: "Lecture.md", in: vault), "saved", "The file is not written while it moves.")

        presenter.letGo()
        try await move.value
        try await autosave.value
        XCTAssertEqual(note.path, try VaultPath("Renamed.md"))
        XCTAssertEqual(try text(of: "Renamed.md", in: vault), "typed during the move")
        XCTAssertFalse(exists("Lecture.md", in: vault))
        let draftsAfterTheMove = await processServices.unsavedDrafts.drafts(inVault: vaultIdentifier)
        XCTAssertTrue(draftsAfterTheMove.isEmpty, "The text reached the file, so the draft goes.")
    }

    /// A move that does not end: the save gives up with a message and the text in its draft, and
    /// the old path is not written. Once the move does end, the note goes on at the new place.
    func testASaveGivesUpOnAMoveThatDoesNotEndAndNeverWritesTheOldPath() async throws {
        let (workspace, vault) = try await makeWindowAndVault(files: ["Lecture.md": "saved", "Other.md": ""])
        let note = try await open("Lecture.md", in: workspace)
        note.longestWaitForMove = .milliseconds(50)
        let vaultIdentifier = try XCTUnwrap(workspace.currentVaultIdentifier)
        let presenter = FileHoldingPresenter(holding: vault.appendingPathComponent("Lecture.md"))
        defer { presenter.letGo() }
        let move = Task { @MainActor in await workspace.rename(try VaultPath("Lecture.md"), to: "Renamed") }
        try await waitUntil("the move to reach the file") { presenter.isHoldingAWriter }
        note.text = "typed during the move"

        do {
            try await note.save()
            XCTFail("The save does not go on waiting.")
        } catch {
            XCTAssertEqual(note.errorMessage, MarkdownSession.stillMovingMessage)
            XCTAssertEqual(error as? GraphiteError, .unavailable(MarkdownSession.stillMovingMessage))
        }
        XCTAssertEqual(try text(of: "Lecture.md", in: vault), "saved")
        var drafts = await processServices.unsavedDrafts.drafts(inVault: vaultIdentifier)
        XCTAssertEqual(drafts.map(\.contents), [Data("typed during the move".utf8)])
        XCTAssertTrue(note.isSaving, "The hold stays, so no later save aims at the old path.")

        // A later try does not wait the limit again, whatever the limit is by then.
        note.longestWaitForMove = .zero
        do {
            try await note.save()
            XCTFail("The move still runs.")
        } catch { XCTAssertEqual(error as? GraphiteError, .unavailable(MarkdownSession.stillMovingMessage)) }

        presenter.letGo()
        try await move.value
        XCTAssertEqual(note.path, try VaultPath("Renamed.md"))
        XCTAssertEqual(try text(of: "Renamed.md", in: vault), "typed during the move")
        XCTAssertFalse(exists("Lecture.md", in: vault))
        XCTAssertNil(note.errorMessage, "The message goes with the hold.")
        drafts = await processServices.unsavedDrafts.drafts(inVault: vaultIdentifier)
        XCTAssertTrue(drafts.isEmpty)
    }

    /// With nothing to write, nothing waits: another note opens in the tab and the app goes on.
    func testOpeningAnotherNoteDoesNotWaitWithNothingUnsaved() async throws {
        let (workspace, vault) = try await makeWindowAndVault(files: ["Lecture.md": "saved", "Other.md": "other"])
        _ = try await open("Lecture.md", in: workspace)
        let presenter = FileHoldingPresenter(holding: vault.appendingPathComponent("Lecture.md"))
        defer { presenter.letGo() }
        let move = Task { @MainActor in await workspace.rename(try VaultPath("Lecture.md"), to: "Renamed") }
        try await waitUntil("the move to reach the file") { presenter.isHoldingAWriter }

        let other = try await open("Other.md", in: workspace)

        XCTAssertEqual(other.text, "other")
        XCTAssertTrue(presenter.isHoldingAWriter, "It opened while the move was still waiting.")
        presenter.letGo()
        try await move.value
        XCTAssertTrue(exists("Renamed.md", in: vault))
    }

    /// Leaving the vault with text a stuck move holds is refused with the reason, and the text is safe.
    func testAVaultSwitchIsRefusedWithAMessageWhileUnsavedTextWaitsForAMove() async throws {
        let (workspace, vault) = try await makeWindowAndVault(files: ["Lecture.md": "saved", "Other.md": ""])
        let otherVault = try makeVault(files: ["Other vault note.md": "x"])
        let note = try await open("Lecture.md", in: workspace)
        note.longestWaitForMove = .milliseconds(50)
        let vaultIdentifier = try XCTUnwrap(workspace.currentVaultIdentifier)
        let presenter = FileHoldingPresenter(holding: vault.appendingPathComponent("Lecture.md"))
        defer { presenter.letGo() }
        let move = Task { @MainActor in await workspace.rename(try VaultPath("Lecture.md"), to: "Renamed") }
        try await waitUntil("the move to reach the file") { presenter.isHoldingAWriter }
        note.text = "typed during the move"

        do {
            try await workspace.openFolderAsVault(otherVault)
            XCTFail("The vault with the text stays open.")
        } catch { XCTAssertEqual(error as? GraphiteError, .unavailable(MarkdownSession.stillMovingMessage)) }

        XCTAssertEqual(workspace.currentVaultIdentifier, vaultIdentifier)
        let drafts = await processServices.unsavedDrafts.drafts(inVault: vaultIdentifier)
        XCTAssertEqual(drafts.map(\.contents), [Data("typed during the move".utf8)])
        presenter.letGo()
        try await move.value
        XCTAssertEqual(try text(of: "Renamed.md", in: vault), "typed during the move")
    }

    /// Text typed over a file the move itself rewrote goes to a copy: its draft goes too, and is
    /// not found when the tab opens the rewritten file, which would show the text a second time.
    func testADraftOfTextThatWentToACopyDoesNotComeBackInTheNote() async throws {
        let (workspace, vault) = try await makeWindowAndVault(files: ["Lecture.md": "[other](Other.md)", "Other.md": "", "Sub/Existing.md": ""])
        workspace.vaultSettings.updatesLinksAutomatically = true
        let note = try await open("Lecture.md", in: workspace)
        let vaultIdentifier = try XCTUnwrap(workspace.currentVaultIdentifier)
        let presenter = FileHoldingPresenter(holding: vault.appendingPathComponent("Lecture.md"))
        defer { presenter.letGo() }
        let move = Task { @MainActor in await workspace.move(try VaultPath("Lecture.md"), into: try VaultPath("Sub")) }
        try await waitUntil("the move to reach the file") { presenter.isHoldingAWriter }
        note.text = "[other](Other.md) typed"
        let autosave = Task { @MainActor in try await note.save() }
        try await waitUntil("the draft to reach the disk") {
            await !self.processServices.unsavedDrafts.drafts(inVault: vaultIdentifier).isEmpty
        }

        presenter.letGo()
        try await move.value
        try await autosave.value

        XCTAssertEqual(try text(of: "Sub/Lecture.md", in: vault), "[other](../Other.md)")
        XCTAssertEqual(try text(of: "Sub/Lecture Graphite edits.md", in: vault), "[other](Other.md) typed")
        let drafts = await processServices.unsavedDrafts.drafts(inVault: vaultIdentifier)
        XCTAssertTrue(drafts.isEmpty, "Left: \(drafts.map(\.path))")
        await workspace.loadDocumentIfNeeded(for: workspace.layout.activeTab.id)
        XCTAssertEqual(workspace.markdownSession?.text, "[other](../Other.md)")
        XCTAssertEqual(workspace.markdownSession?.hasExternalConflict, false)
    }

    // MARK: A note moved to the path of another open note

    /// A tab holds text of a file another app deleted, and another app renames a second note to
    /// that name. The two were made one text, so each overwrote the other, and a save lost a draft.
    func testANoteMovedToThePathOfAnOpenNoteStaysApartFromIt() async throws {
        let (workspace, vault) = try await makeWindowAndVault(files: ["A.md": "a saved", "B.md": "b saved"])
        let moved = try await open("A.md", in: workspace)
        let stale = try await open("B.md", in: workspace, placement: .newTab)
        let vaultIdentifier = try XCTUnwrap(workspace.currentVaultIdentifier)
        stale.text = "b typed"
        let isKept = await stale.keepUnsavedTextInDraft()
        XCTAssertTrue(isKept)
        try FileManager.default.removeItem(at: vault.appendingPathComponent("B.md"))
        try FileManager.default.moveItem(at: vault.appendingPathComponent("A.md"), to: vault.appendingPathComponent("B.md"))

        await workspace.followExternalMove(from: vault.appendingPathComponent("A.md"), to: vault.appendingPathComponent("B.md"))

        XCTAssertTrue(moved.siblings.isEmpty, "The moved note is not one text with the other.")
        XCTAssertEqual(moved.path, try VaultPath("B.md"))
        try await waitUntil("the other note's text to reach its copy") { self.exists("B Graphite edits.md", in: vault) }
        XCTAssertEqual(try text(of: "B Graphite edits.md", in: vault), "b typed")
        XCTAssertEqual(stale.path, try VaultPath("B Graphite edits.md"), "Its tab goes on with the copy, with its undo history.")
        XCTAssertEqual(workspace.tabDocuments.values.first { document in document.markdownSession === stale }?.loadedPath, stale.path)
        XCTAssertTrue(workspace.layout.allTabs.contains { tab in tab.path == stale.path })
        XCTAssertTrue(workspace.errorMessage?.contains("B Graphite edits.md") == true, workspace.errorMessage ?? "")

        moved.text = "a typed"
        XCTAssertEqual(stale.text, "b typed", "Typing in one does not reach the other.")
        stale.text = "b typed more"
        XCTAssertEqual(moved.text, "a typed")
        try await moved.save()
        try await stale.save()
        XCTAssertEqual(try text(of: "B.md", in: vault), "a typed")
        XCTAssertEqual(try text(of: "B Graphite edits.md", in: vault), "b typed more")
        try await waitUntil("no draft to be left") {
            await self.processServices.unsavedDrafts.drafts(inVault: vaultIdentifier).isEmpty
        }
    }

    /// Graphite's own rename saves every open note first, so with that tab's text unsaved it is refused and nothing merges.
    func testARenameToTheNameOfAGoneNoteWithUnsavedTextIsRefused() async throws {
        let (workspace, vault) = try await makeWindowAndVault(files: ["A.md": "a saved", "B.md": "b saved"])
        let moved = try await open("A.md", in: workspace)
        let stale = try await open("B.md", in: workspace, placement: .newTab)
        stale.text = "b typed"
        try FileManager.default.removeItem(at: vault.appendingPathComponent("B.md"))

        await workspace.rename(try VaultPath("A.md"), to: "B")

        XCTAssertNotNil(workspace.errorMessage)
        XCTAssertEqual(moved.path, try VaultPath("A.md"))
        XCTAssertEqual(try text(of: "A.md", in: vault), "a saved")
        XCTAssertEqual(stale.text, "b typed")
        XCTAssertTrue(moved.siblings.isEmpty)
    }

    /// With nothing unsaved in that tab, Graphite's own rename goes ahead, and the tab shows the moved note.
    func testARenameToTheNameOfAGoneNoteTakesItsTabWithNothingToKeep() async throws {
        let (workspace, vault) = try await makeWindowAndVault(files: ["A.md": "a saved", "B.md": "b saved"])
        let moved = try await open("A.md", in: workspace)
        let stale = try await open("B.md", in: workspace, placement: .newTab)
        try FileManager.default.removeItem(at: vault.appendingPathComponent("B.md"))

        await workspace.rename(try VaultPath("A.md"), to: "B")
        try await waitUntil("the other tab to go") { !workspace.tabDocuments.values.contains { document in document.markdownSession === stale } }

        XCTAssertTrue(moved.siblings.isEmpty)
        XCTAssertEqual(moved.text, "a saved")
        XCTAssertEqual(try text(of: "B.md", in: vault), "a saved")
    }

    /// A draft of each note: neither replaces the other, however the move's own draft goes.
    func testTheDraftsOfBothNotesSurvive() async throws {
        let (workspace, vault) = try await makeWindowAndVault(files: ["Folder/A.md": "a saved", "Folder/B.md": "b saved"])
        let folder = vault.appendingPathComponent("Folder")
        addTeardownBlock { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path) }
        let moved = try await open("Folder/A.md", in: workspace)
        let stale = try await open("Folder/B.md", in: workspace, placement: .newTab)
        let vaultIdentifier = try XCTUnwrap(workspace.currentVaultIdentifier)
        moved.text = "a typed"
        stale.text = "b typed"
        var isKept = await moved.keepUnsavedTextInDraft()
        XCTAssertTrue(isKept)
        isKept = await stale.keepUnsavedTextInDraft()
        XCTAssertTrue(isKept)
        try FileManager.default.removeItem(at: folder.appendingPathComponent("B.md"))
        try FileManager.default.moveItem(at: folder.appendingPathComponent("A.md"), to: folder.appendingPathComponent("B.md"))
        // A folder that takes no new file: neither the copy nor the moved note's save can be written.
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: folder.path)

        await workspace.followExternalMove(from: folder.appendingPathComponent("A.md"), to: folder.appendingPathComponent("B.md"))
        try await waitUntil("the failure to show in the note's banner") { stale.errorMessage != nil }

        XCTAssertEqual(stale.errorMessage, MarkdownSession.lostFileMessage)
        let drafts = await processServices.unsavedDrafts.drafts(inVault: vaultIdentifier)
        XCTAssertEqual(Set(drafts.map(\.contents)), [Data("a typed".utf8), Data("b typed".utf8)])
        XCTAssertEqual(try text(of: "Folder/B.md", in: vault), "a saved", "Nothing the other note holds reaches the file.")

        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path)
        try await stale.save()
        XCTAssertEqual(try text(of: "Folder/B Graphite edits.md", in: vault), "b typed")
        try await moved.save()
        XCTAssertEqual(try text(of: "Folder/B.md", in: vault), "a typed")
        try await waitUntil("no draft to be left") {
            await self.processServices.unsavedDrafts.drafts(inVault: vaultIdentifier).isEmpty
        }
    }

    /// A tab at that path with nothing of its own to keep shows the moved note.
    func testATabWithNothingToKeepShowsTheMovedNote() async throws {
        let (workspace, vault) = try await makeWindowAndVault(files: ["A.md": "a saved", "B.md": "b saved"])
        let moved = try await open("A.md", in: workspace)
        let stale = try await open("B.md", in: workspace, placement: .newTab)
        moved.text = "a typed"
        try FileManager.default.removeItem(at: vault.appendingPathComponent("B.md"))
        try FileManager.default.moveItem(at: vault.appendingPathComponent("A.md"), to: vault.appendingPathComponent("B.md"))

        await workspace.followExternalMove(from: vault.appendingPathComponent("A.md"), to: vault.appendingPathComponent("B.md"))
        try await waitUntil("the other tab to go") { !workspace.tabDocuments.values.contains { document in document.markdownSession === stale } }

        XCTAssertEqual(stale.text, "b saved", "It took none of the moved note's text.")
        XCTAssertEqual(workspace.layout.allTabs.filter { tab in tab.path == moved.path }.count, 1)
        XCTAssertFalse(exists("B Graphite edits.md", in: vault))
        XCTAssertEqual(try text(of: "B.md", in: vault), "a typed")
    }

    // MARK: Another vault opened during a move

    /// The question was asked in one vault and answered in another, where the same path names another file.
    func testAnAnswerGivenAfterAVaultSwitchMovesNothingInTheNewVault() async throws {
        let (workspace, firstVault) = try await makeWindowAndVault(files: ["Lecture.md": "first", "Linker.md": "[[Lecture]]"])
        let secondVault = try makeVault(files: ["Lecture.md": "second"])
        let outcome = await workspace.move(try VaultPath("Lecture.md"), to: try VaultPath("Renamed.md"))
        XCTAssertEqual(outcome, .awaitingAnswer)
        let pendingMove = try XCTUnwrap(workspace.pendingMove)
        try await workspace.openFolderAsVault(secondVault)

        await workspace.resolve(pendingMove, updatesLinks: true)

        XCTAssertEqual(try text(of: "Lecture.md", in: secondVault), "second", "The file of the same name in the other vault stays.")
        XCTAssertFalse(exists("Renamed.md", in: secondVault))
        XCTAssertEqual(try text(of: "Lecture.md", in: firstVault), "first")
        XCTAssertFalse(exists("Renamed.md", in: firstVault))
        XCTAssertEqual(workspace.errorMessage, FileMoveRefusal.vaultClosed(movedName: "Lecture.md").message)
    }

    /// A move that ends after the switch has moved its own vault's file, and touches nothing of the vault open now.
    func testAMoveThatEndsAfterAVaultSwitchLeavesTheNewVaultsTabsAlone() async throws {
        let (workspace, firstVault) = try await makeWindowAndVault(files: ["Lecture.md": "first", "Other.md": ""])
        let secondVault = try makeVault(files: ["Lecture.md": "second", "Other.md": ""])
        let presenter = FileHoldingPresenter(holding: firstVault.appendingPathComponent("Lecture.md"))
        defer { presenter.letGo() }
        let move = Task { @MainActor in await workspace.rename(try VaultPath("Lecture.md"), to: "Renamed") }
        try await waitUntil("the move to reach the file") { presenter.isHoldingAWriter }
        try await workspace.openFolderAsVault(secondVault)
        let note = try await open("Lecture.md", in: workspace)
        note.text = "second typed"

        presenter.letGo()
        try await move.value

        XCTAssertTrue(exists("Renamed.md", in: firstVault), "Its own vault's file moved.")
        XCTAssertFalse(exists("Lecture.md", in: firstVault))
        XCTAssertEqual(note.path, try VaultPath("Lecture.md"), "The session of the same path here stays.")
        XCTAssertEqual(workspace.layout.activeTab.path, try VaultPath("Lecture.md"))
        XCTAssertEqual(workspace.tabDocuments[workspace.layout.activeTab.id]?.loadedPath, try VaultPath("Lecture.md"))
        XCTAssertFalse(exists("Renamed.md", in: secondVault))
        try await note.save()
        XCTAssertEqual(try text(of: "Lecture.md", in: secondVault), "second typed")
    }

    // MARK: Helpers

    private func makeVault(files: [String: String]) throws -> URL {
        let vault = try TemporaryVault.make(prefix: "SlowMoveVault", for: self).root.resolvingSymlinksInPath()
        for (relativePath, contents) in files {
            let location = vault.appendingPathComponent(relativePath)
            try FileManager.default.createDirectory(at: location.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(contents.utf8).write(to: location)
        }
        return vault
    }

    private func makeWindowAndVault(files: [String: String]) async throws -> (WorkspaceModel, URL) {
        let vault = try makeVault(files: files)
        let window = WorkspaceModel(processServices: processServices, clock: LiveApplicationClock())
        try await window.openFolderAsVault(vault)
        try await waitUntil { window.hasCompletedIndexScan }
        return (window, vault)
    }

    private func open(_ relativePath: String, in window: WorkspaceModel, placement: TabPlacement = .currentTab) async throws -> MarkdownSession {
        let path = try VaultPath(relativePath)
        await window.open(path, placement: placement)
        return try XCTUnwrap(window.openMarkdownSession(at: path))
    }

    private func text(of relativePath: String, in vault: URL) throws -> String {
        try String(contentsOf: vault.appendingPathComponent(relativePath), encoding: .utf8)
    }

    private func exists(_ relativePath: String, in vault: URL) -> Bool {
        FileManager.default.fileExists(atPath: vault.appendingPathComponent(relativePath).path)
    }
}
