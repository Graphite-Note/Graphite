/**
 * File: OpenedFileImportTests.swift
 * ---------------------------------
 * Layer: Tests
 * Description: Files opened in Graphite from another app, as the scene's open-URL handler hands them over: copied and
 *              converted into the open vault, ZIP archives unpacked with their folders, and the vault opened or
 *              asked for when none is open.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 13/11/2026
 */

import XCTest
import GraphiteCore
import GraphiteApple
import GraphiteFixtures
@testable import GraphiteUI
import GraphiteTestSupport

/// A file another app opens in Graphite (the share sheet's Open in, Files, AirDrop, the Finder's Open With, a drop on
/// the Dock icon) reaches the scene's `onOpenURL` as a file URL, which hands it to `WorkspaceModel.handle(_:)` as it
/// hands a `graphite://` link; these tests start there.
@MainActor
final class OpenedFileImportTests: XCTestCase {
    private var device: IsolatedWorkspaceDevice!
    private var outside: URL!
    private var vaultsFolder: URL!

    override func setUp() async throws {
        device = try IsolatedWorkspaceDevice.make(for: self)
        outside = try TemporaryVault.make(prefix: "OpenedFileSources", for: self).root
        vaultsFolder = try TemporaryVault.make(prefix: "OpenedFileVaults", for: self).root
    }

    private func makeVault(named name: String, files: [String: String] = [:]) throws -> URL {
        let vault = vaultsFolder.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        for (path, contents) in files { try Data(contents.utf8).write(to: vault.appendingPathComponent(path)) }
        return vault
    }

    private func workspace(openOn vault: URL) async throws -> WorkspaceModel {
        let workspace = device.makeWorkspace()
        try await workspace.openFolderAsVault(vault)
        return workspace
    }

    private func outsideFile(_ name: String, contents: String) throws -> URL {
        let location = outside.appendingPathComponent(name)
        try Data(contents.utf8).write(to: location)
        return location
    }

    private func notebookBytes(_ name: String = "Synthetic lecture.goodnotes") throws -> Data {
        try Data(contentsOf: FixtureFolders.syntheticNotebooks.appendingPathComponent(name))
    }

    private func archive(_ name: String, _ entries: [(name: String, contents: Data)]) throws -> URL {
        let location = outside.appendingPathComponent(name)
        try StoredZipArchive.write(entries, to: location)
        return location
    }

    private func waitForNotebookImport(in workspace: WorkspaceModel) async throws -> NotebookImportSummary {
        try await waitUntil("the notebook import has ended", timeoutSeconds: 60) {
            if case .finished = workspace.notebookImport?.state { true } else { false }
        }
        var summary: NotebookImportSummary?
        if case .finished(let finished)? = workspace.notebookImport?.state { summary = finished }
        workspace.endNotebookImport()
        return try XCTUnwrap(summary, "The import ended with its summary.")
    }

    private func exists(_ path: String, in vault: URL) -> Bool {
        FileManager.default.fileExists(atPath: vault.appendingPathComponent(path).path)
    }

    // MARK: Into the open vault

    func testAnOpenedMarkdownFileIsCopiedIntoTheVaultAndOpenedAndTheOriginalIsKept() async throws {
        let vault = try makeVault(named: "Physics", files: ["Existing.md": "x"])
        let workspace = try await workspace(openOn: vault)
        let opened = try outsideFile("Waves.md", contents: "# Waves")

        await workspace.handle(opened)

        XCTAssertEqual(try String(contentsOf: vault.appendingPathComponent("Waves.md"), encoding: .utf8), "# Waves")
        XCTAssertEqual(workspace.selection?.rawValue, "Waves.md", "A single file copied is shown.")
        XCTAssertEqual(try String(contentsOf: opened, encoding: .utf8), "# Waves", "The original is only read.")
        XCTAssertNil(workspace.errorMessage)
    }

    func testAnOpenedTextFileBecomesANoteAndANameTakenGetsAFreeOne() async throws {
        let vault = try makeVault(named: "Physics", files: ["Lab.md": "existing"])
        let workspace = try await workspace(openOn: vault)

        await workspace.handle(try outsideFile("Lab.txt", contents: "measured"))

        XCTAssertEqual(try String(contentsOf: vault.appendingPathComponent("Lab 1.md"), encoding: .utf8), "measured")
        XCTAssertEqual(try String(contentsOf: vault.appendingPathComponent("Lab.md"), encoding: .utf8), "existing")
    }

    func testAnOpenedGoodnotesNotebookIsConvertedIntoAPDF() async throws {
        let vault = try makeVault(named: "Physics")
        let workspace = try await workspace(openOn: vault)
        let notebook = outside.appendingPathComponent("Synthetic lecture.goodnotes")
        try notebookBytes().write(to: notebook)

        await workspace.handle(notebook)
        let summary = try await waitForNotebookImport(in: workspace)

        XCTAssertEqual(summary.outcomes.compactMap(\.importedNotebook?.pdf.rawValue), ["Synthetic lecture.pdf"])
        XCTAssertTrue(exists("Synthetic lecture.pdf", in: vault))
        XCTAssertFalse(exists("Synthetic lecture.goodnotes", in: vault), "The notebook is converted, not copied.")
    }

    func testAFileAlreadyInTheOpenVaultIsShownNotCopiedAgain() async throws {
        let vault = try makeVault(named: "Physics", files: ["Inside.md": "x"])
        let workspace = try await workspace(openOn: vault)

        await workspace.handle(vault.appendingPathComponent("Inside.md"))

        XCTAssertEqual(workspace.selection?.rawValue, "Inside.md")
        XCTAssertFalse(exists("Inside 1.md", in: vault))
    }

    func testGraphiteLinksStillOpenNotes() async throws {
        let vault = try makeVault(named: "Physics", files: ["Note.md": "x"])
        let workspace = try await workspace(openOn: vault)
        await workspace.handle(try XCTUnwrap(URL(string: "graphite://open?vault=Physics&file=Note")))
        XCTAssertEqual(workspace.selection?.rawValue, "Note.md")
    }

    // MARK: ZIP archives

    func testAZippedFolderOfNotebooksAndFilesKeepsItsFoldersAndConvertsItsNotebooks() async throws {
        let vault = try makeVault(named: "Physics")
        let workspace = try await workspace(openOn: vault)
        let opened = try archive("Course.zip", [
            ("Course/", Data()),
            ("Course/Week 1/Synthetic lecture.goodnotes", try notebookBytes()),
            ("Course/Week 1/Slides.pdf", Data("%PDF-1.4 stand-in".utf8)),
            ("Course/Week 2/Synthetic note.note", try notebookBytes("Synthetic note.note")),
            ("Course/Readme.txt", Data("Read me".utf8)),
            ("__MACOSX/Course/._Readme.txt", Data("fork".utf8)),
        ])

        await workspace.handle(opened)
        let summary = try await waitForNotebookImport(in: workspace)

        XCTAssertEqual(Set(summary.outcomes.compactMap(\.importedNotebook?.pdf.rawValue)), ["Course/Week 1/Synthetic lecture.pdf", "Course/Week 2/Synthetic note.pdf"])
        XCTAssertEqual(summary.otherFileCount, 0, "The archive's other files are copied, not left behind.")
        XCTAssertTrue(exists("Course/Week 1/Slides.pdf", in: vault))
        XCTAssertEqual(try String(contentsOf: vault.appendingPathComponent("Course/Readme.md"), encoding: .utf8), "Read me")
        XCTAssertFalse(exists("__MACOSX", in: vault))
        XCTAssertFalse(exists("Course 1", in: vault), "The notebooks go into the folder the files went into.")
        XCTAssertNil(workspace.errorMessage)
    }

    func testAnArchiveOfLooseFilesGoesIntoAFolderNamedAfterItBesideAFolderOfThatName() async throws {
        let vault = try makeVault(named: "Physics")
        try FileManager.default.createDirectory(at: vault.appendingPathComponent("Export"), withIntermediateDirectories: true)
        let workspace = try await workspace(openOn: vault)
        let opened = try archive("Export.zip", [("A.md", Data("a".utf8)), ("B.txt", Data("b".utf8))])

        await workspace.handle(opened)

        XCTAssertTrue(exists("Export 1/A.md", in: vault))
        XCTAssertTrue(exists("Export 1/B.md", in: vault))
        XCTAssertNil(workspace.notebookImport, "No notebook, no notebook import.")
    }

    func testAnArchiveOfOneFileImportsThatFileWhereTheArchiveWasOpened() async throws {
        let vault = try makeVault(named: "Physics")
        let workspace = try await workspace(openOn: vault)
        let opened = try archive("Shared.zip", [("Synthetic lecture.goodnotes", try notebookBytes())])

        await workspace.handle(opened)
        let summary = try await waitForNotebookImport(in: workspace)

        XCTAssertEqual(summary.outcomes.compactMap(\.importedNotebook?.pdf.rawValue), ["Synthetic lecture.pdf"])
        XCTAssertFalse(exists("Shared", in: vault))
    }

    func testWithNotebookImportOffANotebookInAnArchiveIsCopiedAsTheFileItIs() async throws {
        let vault = try makeVault(named: "Physics")
        let workspace = try await workspace(openOn: vault)
        workspace.preferences.setEnabled(.notebookImport, false)
        let opened = try archive("Course.zip", [("Course/Synthetic lecture.goodnotes", try notebookBytes()), ("Course/Notes.md", Data("n".utf8))])

        await workspace.handle(opened)

        XCTAssertNil(workspace.notebookImport)
        XCTAssertEqual(try Data(contentsOf: vault.appendingPathComponent("Course/Synthetic lecture.goodnotes")), try notebookBytes())
        XCTAssertTrue(exists("Course/Notes.md", in: vault))
    }

    func testAnArchiveThatCannotBeReadSaysSoAndLeavesNothing() async throws {
        let vault = try makeVault(named: "Physics")
        let workspace = try await workspace(openOn: vault)

        await workspace.handle(try outsideFile("Broken.zip", contents: "not an archive"))

        XCTAssertEqual(workspace.errorMessage, "Graphite could not import “Broken.zip”: it is not a ZIP archive, or its end is missing.")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: vault.path).filter { name in !name.hasPrefix(".") }, [])
    }

    func testEntriesLeftOutOfAnArchiveAreNamedAndTheRestIsImported() async throws {
        let vault = try makeVault(named: "Physics")
        let workspace = try await workspace(openOn: vault)
        let opened = try archive("Mixed.zip", [("../../Escape.md", Data("x".utf8)), ("Notes/Kept.md", Data("kept".utf8)),
                                               ("Notes/Other.md", Data("other".utf8))])

        await workspace.handle(opened)

        XCTAssertTrue(exists("Notes/Kept.md", in: vault))
        XCTAssertFalse(exists("Escape.md", in: vault))
        XCTAssertFalse(FileManager.default.fileExists(atPath: vaultsFolder.deletingLastPathComponent().appendingPathComponent("Escape.md").path))
        XCTAssertEqual(workspace.errorMessage, "Some files of “Mixed.zip” were not imported: “../../Escape.md” (its name leads outside the archive).")
    }

    // MARK: No vault open

    func testWithNoVaultOpenTheOnlyKnownVaultOpensAndTakesTheFile() async throws {
        let vault = try makeVault(named: "Physics")
        _ = try await workspace(openOn: vault)
        let later = device.makeWorkspace()
        XCTAssertNil(later.store)

        await later.handle(try outsideFile("Waves.md", contents: "# Waves"))

        XCTAssertEqual(later.folderAccess?.root.resolvingSymlinksInPath(), vault.resolvingSymlinksInPath())
        XCTAssertTrue(exists("Waves.md", in: vault))
    }

    func testWithNoVaultOpenAndSeveralKnownTheFileWaitsForTheChosenVault() async throws {
        let physics = try makeVault(named: "Physics")
        let chemistry = try makeVault(named: "Chemistry")
        let first = try await workspace(openOn: physics)
        try await first.openFolderAsVault(chemistry)
        let later = device.makeWorkspace()

        await later.handle(try outsideFile("Waves.md", contents: "# Waves"))
        let waiting = try XCTUnwrap(later.openedFilesAwaitingVault)
        XCTAssertEqual(waiting.description, "“Waves.md”")
        XCTAssertNil(later.store, "Nothing opens before the person answers.")

        let chosen = try XCTUnwrap(later.vaultLibrary.vaults.first { vault in vault.name == "Physics" })
        await later.importOpenedFiles(waiting, into: chosen)

        XCTAssertNil(later.openedFilesAwaitingVault)
        XCTAssertTrue(exists("Waves.md", in: physics))
        XCTAssertFalse(exists("Waves.md", in: chemistry))
    }

    func testAFileOpenedWhileTheQuestionIsShownJoinsItAndTheQuestionIsAnsweredOnce() async throws {
        let physics = try makeVault(named: "Physics")
        let chemistry = try makeVault(named: "Chemistry")
        let first = try await workspace(openOn: physics)
        try await first.openFolderAsVault(chemistry)
        let later = device.makeWorkspace()

        await later.handle(try outsideFile("Waves.md", contents: "# Waves"))
        let shownQuestion = try XCTUnwrap(later.openedFilesAwaitingVault)
        await later.handle(try outsideFile("Optics.md", contents: "# Optics"))
        XCTAssertTrue(later.openedFilesAwaitingVault === shownQuestion)
        XCTAssertEqual(shownQuestion.description, "2 files")

        let chosen = try XCTUnwrap(later.vaultLibrary.vaults.first { vault in vault.name == "Chemistry" })
        await later.importOpenedFiles(shownQuestion, into: chosen)
        // The dialog's Cancel after its button, as a dismissal can send: already answered, so nothing is removed.
        await later.importOpenedFiles(shownQuestion, into: nil)

        XCTAssertTrue(exists("Waves.md", in: chemistry))
        XCTAssertTrue(exists("Optics.md", in: chemistry))
    }

    func testCancellingTheVaultChoiceRemovesTheCopyAndImportsNothing() async throws {
        let physics = try makeVault(named: "Physics")
        let chemistry = try makeVault(named: "Chemistry")
        let first = try await workspace(openOn: physics)
        try await first.openFolderAsVault(chemistry)
        let later = device.makeWorkspace()

        await later.handle(try outsideFile("Waves.md", contents: "# Waves"))
        let waiting = try XCTUnwrap(later.openedFilesAwaitingVault)
        let stagedCopy = try XCTUnwrap(waiting.files.files.first?.location)
        XCTAssertTrue(FileManager.default.fileExists(atPath: stagedCopy.path), "The file is copied at once, before any vault opens.")
        await later.importOpenedFiles(waiting, into: nil)

        XCTAssertFalse(FileManager.default.fileExists(atPath: stagedCopy.path))
        XCTAssertNil(later.store)
        XCTAssertFalse(exists("Waves.md", in: physics))
    }

    func testWithNoVaultKnownTheFileIsNotImportedAndThePersonIsTold() async throws {
        let workspace = device.makeWorkspace()
        await workspace.handle(try outsideFile("Waves.md", contents: "# Waves"))
        XCTAssertEqual(workspace.errorMessage, "Open or create a vault, then open “Waves.md” in Graphite again.")
    }

    // MARK: Wording

    func testTheWordingOfFailuresAndLeftOutEntries() {
        XCTAssertEqual(ArchiveImportWording.failure(.needsZip64, archiveName: "Big.zip"),
                       "Graphite could not import “Big.zip”: it is larger than 4 GB or holds more than 65,535 files, which Graphite does not unpack.")
        let entries = (1...7).map { number in UnpackedArchive.LeftOutEntry(name: "\(number).md", reason: .encrypted) }
        XCTAssertEqual(ArchiveImportWording.leftOut(entries, notCopied: [], archiveName: "Locked.zip"),
                       "Some files of “Locked.zip” were not imported: “1.md” (it is encrypted), “2.md” (it is encrypted), “3.md” (it is encrypted), "
                       + "“4.md” (it is encrypted), “5.md” (it is encrypted) and 2 more.")
        XCTAssertNil(ArchiveImportWording.leftOut([], notCopied: [], archiveName: "Fine.zip"))
    }
}
