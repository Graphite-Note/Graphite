/**
 * File: ArchiveImportByFileTypeTests.swift
 * ----------------------------------------
 * Layer: Tests
 * Description: A ZIP archive chosen with Import or dropped on the library is unpacked as an opened one is: its folders
 *              kept, its files copied and its notebooks converted, and nothing of the ZIP left in the vault.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 13/11/2026
 */

import XCTest
import PDFKit
import GraphiteCore
import GraphiteApple
import GraphiteFixtures
@testable import GraphiteUI
import GraphiteTestSupport

/// The owner, 2026-11-12: "import goodnotes ziped folders or files, same with notability". Import, a drop on the library
/// or the file list, and a file opened from another app all reach `importFiles(from:into:)`, whose importers by file type
/// send a `.zip` to its unpacking (`archiveFileImporter`). The archives are made with `StoredZipArchive` from the
/// synthetic notebooks of `Tests/SyntheticNotebooks`.
@MainActor
final class ArchiveImportByFileTypeTests: XCTestCase {
    private var device: IsolatedWorkspaceDevice!

    override func setUp() async throws {
        device = try IsolatedWorkspaceDevice.make(for: self)
    }

    /// A workspace on preferences of its own, so turning a core plugin off touches nothing of the device.
    private func makeWorkspace() throws -> (WorkspaceModel, URL) {
        let vault = try TemporaryVault.make(prefix: "ArchiveImportByFileType", files: ["Courses/Existing.md": "x"], for: self).root
        let workspace = device.makeWorkspace()
        workspace.folderAccess = FolderAccess(root: vault)
        workspace.store = VaultStore(root: vault)
        return (workspace, vault)
    }

    private func notebookBytes(_ name: String) throws -> Data {
        try Data(contentsOf: FixtureFolders.syntheticNotebooks.appendingPathComponent(name))
    }

    /// A Goodnotes export of two notebooks, one of them in a folder, as a file outside the vault.
    private func exportOfTwoNotebooks(named name: String = "Goodnotes Export.zip") throws -> URL {
        let folder = try TemporaryVault.make(prefix: "ArchiveImportSources", for: self).root
        let location = folder.appendingPathComponent(name)
        try StoredZipArchive.write([
            ("Synthetic lecture.goodnotes", try notebookBytes("Synthetic lecture.goodnotes")),
            ("Typed/Synthetic typed note.note", try notebookBytes("Synthetic typed note.note")),
        ], to: location)
        return location
    }

    private func importedPDFsOnceTheNotebookImportEnds(in workspace: WorkspaceModel) async throws -> [String] {
        try await waitUntil("the notebook import has ended", timeoutSeconds: 60) {
            if case .finished = workspace.notebookImport?.state { true } else { false }
        }
        var pdfs: [String] = []
        if case .finished(let summary)? = workspace.notebookImport?.state { pdfs = summary.outcomes.compactMap(\.importedNotebook?.pdf.rawValue) }
        workspace.endNotebookImport()
        return pdfs.sorted()
    }

    private func exists(_ path: String, in vault: URL) -> Bool {
        FileManager.default.fileExists(atPath: vault.appendingPathComponent(path).path)
    }

    func testAZipChosenWithImportIsUnpackedAndItsTwoNotebooksConverted() async throws {
        let (workspace, vault) = try makeWorkspace()
        let archive = try exportOfTwoNotebooks()

        let copiedPaths = await workspace.importFiles(from: [archive], into: try VaultPath("Courses"))
        let pdfs = try await importedPDFsOnceTheNotebookImportEnds(in: workspace)

        XCTAssertEqual(pdfs, ["Courses/Goodnotes Export/Synthetic lecture.pdf", "Courses/Goodnotes Export/Typed/Synthetic typed note.pdf"])
        XCTAssertEqual(PDFDocument(url: vault.appendingPathComponent(pdfs[0]))?.pageCount, 3)
        XCTAssertEqual(PDFDocument(url: vault.appendingPathComponent(pdfs[1]))?.pageCount, 2)
        XCTAssertEqual(copiedPaths, [], "The ZIP is not copied as the file it is.")
        XCTAssertFalse(exists("Courses/Goodnotes Export.zip", in: vault))
        XCTAssertTrue(FileManager.default.fileExists(atPath: archive.path), "The chosen archive is only read.")
        XCTAssertNil(workspace.errorMessage)
    }

    func testAZipDroppedOnTheLibraryIsUnpackedIntoTheFolderItLandsIn() async throws {
        let (workspace, vault) = try makeWorkspace()
        let provider = try XCTUnwrap(NSItemProvider(contentsOf: try exportOfTwoNotebooks(named: "Notability Export.zip")))

        XCTAssertTrue(workspace.receiveDrop([provider], into: try VaultPath("Courses")))
        let pdfs = try await importedPDFsOnceTheNotebookImportEnds(in: workspace)

        XCTAssertEqual(pdfs, ["Courses/Notability Export/Synthetic lecture.pdf", "Courses/Notability Export/Typed/Synthetic typed note.pdf"])
        XCTAssertFalse(exists("Courses/Notability Export.zip", in: vault))
        XCTAssertNil(workspace.errorMessage)
    }

    /// A ZIP with a ZIP inside: the inner one is copied as the file it is, so an archive that holds itself ends.
    func testAZipInsideAnArchiveOfOneFileIsCopiedNotUnpackedAgain() async throws {
        let (workspace, vault) = try makeWorkspace()
        let folder = try TemporaryVault.make(prefix: "ArchiveImportNested", for: self).root
        let inner = StoredZipArchive.bytes(of: [("Inner.md", Data("inner".utf8))])
        let outer = folder.appendingPathComponent("Outer.zip")
        try StoredZipArchive.write([("Inner.zip", inner)], to: outer)

        await workspace.importFiles(from: [outer], into: .root)

        XCTAssertEqual(try Data(contentsOf: vault.appendingPathComponent("Inner.zip")), inner)
        XCTAssertFalse(exists("Inner.md", in: vault))
        XCTAssertFalse(exists("Inner", in: vault))
    }

    /// With the Notebook Import core plugin off, an archive is still unpacked; its notebooks are copied as the files they are.
    func testWithNotebookImportOffAnImportedZipIsStillUnpacked() async throws {
        let (workspace, vault) = try makeWorkspace()
        workspace.preferences.setEnabled(.notebookImport, false)

        await workspace.importFiles(from: [try exportOfTwoNotebooks()], into: .root)

        XCTAssertNil(workspace.notebookImport)
        XCTAssertEqual(try Data(contentsOf: vault.appendingPathComponent("Goodnotes Export/Synthetic lecture.goodnotes")),
                       try notebookBytes("Synthetic lecture.goodnotes"))
        XCTAssertTrue(exists("Goodnotes Export/Typed/Synthetic typed note.note", in: vault))
    }

    func testArchivesGoToTheirUnpackingAndOtherFilesToThePlainCopy() throws {
        let (workspace, _) = try makeWorkspace()
        let sources = [URL(fileURLWithPath: "/tmp/Export.ZIP"), URL(fileURLWithPath: "/tmp/Slides.pdf")]
        let routing = DroppedFileImporters.route(sources, through: [workspace.archiveFileImporter])
        XCTAssertEqual(routing.routed.map(\.files), [[sources[0]]], "Extensions are compared lowercased.")
        XCTAssertEqual(routing.remaining, [sources[1]])
    }
}
