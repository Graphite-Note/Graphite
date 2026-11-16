/**
 * File: OpenedFileImportHostedTests.swift
 * ---------------------------------------
 * Layer: Tests
 * Description: On the iPad, a Goodnotes notebook and a ZIP archive of two notebooks opened in Graphite from another app
 *              end as converted PDFs in the vault.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 13/11/2026
 */
#if os(iOS)
import XCTest
import PDFKit
import GraphiteCore
import GraphiteApple
@testable import GraphiteUI

/// A file another app opens in Graphite (the share sheet's Open in, Files, AirDrop) reaches the scene's `onOpenURL` as a
/// file URL, which the root view hands to `WorkspaceModel.handle(_:)` once the window's vault has reopened; these tests
/// start there, on the iPad, with the synthetic notebooks of `Tests/SyntheticNotebooks` (built from the documented
/// formats, nothing from a real notebook).
@MainActor
final class OpenedFileImportHostedTests: XCTestCase {
    private static let syntheticNotebooks = FixtureFolders.syntheticNotebooks

    private func makeWorkspace() throws -> (WorkspaceModel, URL) {
        let vault = try TemporaryVault.make(prefix: "OpenedFileImportHosted", for: self)
        let workspace = WorkspaceModel()
        workspace.folderAccess = FolderAccess(root: vault.root)
        workspace.store = VaultStore(root: vault.root)
        return (workspace, vault.root)
    }

    /// A file as another app hands it over: somewhere outside the vault.
    private func handedOver(_ name: String, contents: Data) throws -> URL {
        let folder = try TemporaryVault.make(prefix: "OpenedFileHandedOver", for: self).root
        let location = folder.appendingPathComponent(name)
        try contents.write(to: location)
        return location
    }

    private func notebookBytes(_ name: String) throws -> Data {
        try Data(contentsOf: Self.syntheticNotebooks.appendingPathComponent(name))
    }

    private func importedPDFs(afterOpening file: URL, in workspace: WorkspaceModel) async throws -> [String] {
        await workspace.handle(file)
        try await waitUntil("the notebook import has ended", timeoutSeconds: 90) {
            if case .finished = workspace.notebookImport?.state { true } else { false }
        }
        var pdfs: [String] = []
        if case .finished(let summary)? = workspace.notebookImport?.state { pdfs = summary.outcomes.compactMap(\.importedNotebook?.pdf.rawValue) }
        workspace.endNotebookImport()
        return pdfs.sorted()
    }

    private func pageCount(of path: String, in vault: URL) throws -> Int {
        try XCTUnwrap(PDFDocument(url: vault.appendingPathComponent(path)), path).pageCount
    }

    func testAnOpenedGoodnotesNotebookBecomesAPDFInTheVault() async throws {
        let (workspace, vault) = try makeWorkspace()
        let opened = try handedOver("Synthetic lecture.goodnotes", contents: try notebookBytes("Synthetic lecture.goodnotes"))

        let pdfs = try await importedPDFs(afterOpening: opened, in: workspace)

        XCTAssertEqual(pdfs, ["Synthetic lecture.pdf"])
        // Four source pages, one of them without paper, which the import leaves out.
        XCTAssertEqual(try pageCount(of: "Synthetic lecture.pdf", in: vault), 3)
        XCTAssertTrue(FileManager.default.fileExists(atPath: opened.path), "The handed-over file is only read.")
    }

    func testAnOpenedZipOfTwoNotebooksBecomesTwoPDFsInAFolderNamedAfterIt() async throws {
        let (workspace, vault) = try makeWorkspace()
        let archive = StoredZipArchive.bytes(of: [
            ("Synthetic lecture.goodnotes", try notebookBytes("Synthetic lecture.goodnotes")),
            ("Typed/Synthetic typed note.note", try notebookBytes("Synthetic typed note.note")),
        ])
        let opened = try handedOver("Goodnotes Export.zip", contents: archive)

        let pdfs = try await importedPDFs(afterOpening: opened, in: workspace)

        XCTAssertEqual(pdfs, ["Goodnotes Export/Synthetic lecture.pdf", "Goodnotes Export/Typed/Synthetic typed note.pdf"])
        XCTAssertEqual(try pageCount(of: "Goodnotes Export/Synthetic lecture.pdf", in: vault), 3)
        XCTAssertEqual(try pageCount(of: "Goodnotes Export/Typed/Synthetic typed note.pdf", in: vault), 2)
        XCTAssertNil(workspace.errorMessage)
    }
}
#endif
