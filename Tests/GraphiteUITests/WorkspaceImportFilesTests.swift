import XCTest
import GraphiteCore
import GraphiteIndex
import GraphiteApple
import GraphiteFixtures
@testable import GraphiteUI
import GraphiteTestSupport

/// Import and drops from other apps: copies into a folder, never moves the source.
@MainActor
final class WorkspaceImportFilesTests: XCTestCase {
    private func makeWorkspace(files: [String: String]) async throws -> (WorkspaceModel, URL) {
        let vault = try TemporaryVault.make(prefix: "ImportFiles", files: files, for: self).root
        let indexFolder = try TemporaryVault.make(prefix: "ImportFilesIndex", for: self).root
        let index = try VaultIndex(databaseURL: indexFolder.appendingPathComponent("index.sqlite"))
        _ = try await index.reconcile(root: vault)
        let workspace = WorkspaceModel()
        workspace.folderAccess = FolderAccess(root: vault)
        workspace.store = VaultStore(root: vault)
        workspace.index = index
        workspace.hasCompletedIndexScan = true
        return (workspace, vault)
    }

    private func outsideFile(named name: String, contents: String) throws -> URL {
        let folder = try TemporaryVault.make(prefix: "ImportSources", for: self).root
        let location = folder.appendingPathComponent(name)
        try Data(contents.utf8).write(to: location)
        return location
    }

    func testAPdfAndAnImageAreCopiedIntoTheFolderAndTheSourcesStay() async throws {
        let (workspace, vault) = try await makeWorkspace(files: ["Course/Existing.md": "x"])
        let pdf = try outsideFile(named: "Slides.pdf", contents: "pdf")
        let image = try outsideFile(named: "Board.png", contents: "png")
        await workspace.importFiles(from: [pdf, image], into: try VaultPath("Course"))
        XCTAssertNil(workspace.errorMessage)
        XCTAssertTrue(FileManager.default.fileExists(atPath: vault.appendingPathComponent("Course/Slides.pdf").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: vault.appendingPathComponent("Course/Board.png").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: pdf.path), "The source is copied, never moved.")
        XCTAssertTrue(FileManager.default.fileExists(atPath: image.path))
    }

    func testATextFileBecomesANoteUnderAFreeName() async throws {
        let (workspace, vault) = try await makeWorkspace(files: ["Notes.md": "existing"])
        await workspace.importFiles(from: [try outsideFile(named: "Notes.txt", contents: "from text")], into: .root)
        XCTAssertNil(workspace.errorMessage)
        XCTAssertEqual(try String(contentsOf: vault.appendingPathComponent("Notes.md"), encoding: .utf8), "existing")
        XCTAssertEqual(try String(contentsOf: vault.appendingPathComponent("Notes 1.md"), encoding: .utf8), "from text")
    }

    // MARK: Notebooks dragged in from another app

    private func waitForNotebookImportToEnd(_ workspace: WorkspaceModel) async throws -> NotebookImportSummary {
        try await waitUntil("the notebook import has ended", timeoutSeconds: 30) {
            if case .finished = workspace.notebookImport?.state { true } else { false }
        }
        guard case .finished(let summary)? = workspace.notebookImport?.state else { throw GraphiteError.unavailable("The import did not end.") }
        return summary
    }

    func testANotebookDroppedFromFilesIsConvertedBeforeItsTemporaryCopyIsRemoved() async throws {
        let (workspace, vault) = try await makeWorkspace(files: ["Courses/Existing.md": "x"])
        let notebook = FixtureFolders.syntheticNotebooks.appendingPathComponent("Synthetic note.note")
        let provider = try XCTUnwrap(NSItemProvider(contentsOf: notebook))
        XCTAssertTrue(workspace.receiveDrop([provider], into: try VaultPath("Courses")))
        let summary = try await waitForNotebookImportToEnd(workspace)
        XCTAssertEqual(summary.importedCount, 1, "The conversion read the copy the drop made, so the copy was still there.")
        XCTAssertTrue(FileManager.default.fileExists(atPath: vault.appendingPathComponent("Courses/Synthetic note.pdf").path))
    }

    func testTheTemporaryCopiesStayUntilTheNotebookImportEndsAndGoThen() async throws {
        let (workspace, _) = try await makeWorkspace(files: [:])
        let notebook = FixtureFolders.syntheticNotebooks.appendingPathComponent("Synthetic note.note")
        let staged = try DroppedFileStaging.stage(notebook)
        let batch = DroppedFileBatch(files: [DroppedFile(location: staged.copy, stagingFolder: staged.folder)])
        await workspace.importFiles(from: batch.locations, into: .root, stagedCopies: batch)
        _ = try await waitForNotebookImportToEnd(workspace)
        try await waitUntil("the temporary copies are removed") { !FileManager.default.fileExists(atPath: staged.folder.path) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: staged.folder.path), "Nothing of the drop is kept once the conversion has ended.")
    }

    func testTheTemporaryCopiesOfOrdinaryFilesGoAsSoonAsTheyAreCopiedIn() async throws {
        let (workspace, vault) = try await makeWorkspace(files: [:])
        let original = try outsideFile(named: "Slides.pdf", contents: "pdf")
        let staged = try DroppedFileStaging.stage(original)
        let batch = DroppedFileBatch(files: [DroppedFile(location: staged.copy, stagingFolder: staged.folder)])
        await workspace.importFiles(from: batch.locations, into: .root, stagedCopies: batch)
        XCTAssertTrue(FileManager.default.fileExists(atPath: vault.appendingPathComponent("Slides.pdf").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: staged.folder.path))
    }
}
