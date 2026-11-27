/**
 * File: NotionImportWorkspaceTests.swift
 * --------------------------------------
 * Layer: Tests
 * Description: Import from Notion in the workspace: its sheet only while its core plugin is on, an import whose files
 *              reach the index, one import at a time, and the vault kept while it runs.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 27/11/2026
 */

import XCTest
import GraphiteCore
import GraphiteIndex
import GraphiteApple
import GraphiteTestSupport
@testable import GraphiteUI

/// Import from Notion as the New menu, the sidebar and the Mac's File menu reach it, on a workspace with a temporary
/// vault and index: the sheet opens for a folder while the Notion Import core plugin is on and not while it is off, the
/// import runs into a new folder whose notes the index then finds, a second import waits for the first, Pause holds it,
/// and leaving the vault is refused until it ends.
@MainActor
final class NotionImportWorkspaceTests: XCTestCase {
    private func makeWorkspace() async throws -> (WorkspaceModel, URL) {
        let vault = try TemporaryVault.make(prefix: "NotionImportWorkspace", files: ["Courses/Existing.md": "x"], for: self).root
        let indexFolder = try TemporaryVault.make(prefix: "NotionImportWorkspaceIndex", for: self).root
        let index = try VaultIndex(databaseURL: indexFolder.appendingPathComponent("index.sqlite"))
        _ = try await index.reconcile(root: vault)
        let workspace = WorkspaceModel()
        workspace.folderAccess = FolderAccess(root: vault)
        workspace.store = VaultStore(root: vault)
        workspace.index = index
        workspace.hasCompletedIndexScan = true
        return (workspace, vault)
    }

    func testTheSheetOpensForAFolderOnlyWhileThePluginIsOn() async throws {
        let (workspace, _) = try await makeWorkspace()
        workspace.chooseNotionExport(into: try VaultPath("Courses"))
        XCTAssertEqual(workspace.notionImportChoice?.directory.rawValue, "Courses")
        XCTAssertNotNil(workspace.notionImportOpener)
        workspace.notionImportChoice = nil
        workspace.preferences.setEnabled(.notionImport, false)
        workspace.chooseNotionExport(into: try VaultPath("Courses"))
        XCTAssertNil(workspace.notionImportChoice)
        XCTAssertNil(workspace.notionImportOpener)
        XCTAssertFalse(CreatableItem.offered(firstKind: .note, isEnabled: workspace.preferences.isEnabled, canScanDocuments: false, canTakePhoto: false)
            .others.contains(.importFromNotion))
        workspace.preferences.setEnabled(.notionImport, true)
    }

    func testAnImportWritesIntoTheFolderAndTheIndexFindsItsNotes() async throws {
        let (workspace, vault) = try await makeWorkspace()
        let export = try NotionImportRunTests.writeExport(in: try TemporaryVault.make(prefix: "NotionExport", for: self))
        XCTAssertTrue(workspace.importNotionExport([export], into: try VaultPath("Courses")))
        try await waitUntil("the Notion import has ended") { if case .finished = workspace.notionImport?.state { true } else { false } }
        guard case .finished(let summary)? = workspace.notionImport?.state else { return XCTFail("The import did not end.") }
        XCTAssertEqual(summary.folder?.rawValue, "Courses/Notion")
        XCTAssertEqual(summary.noteCount, 3)
        XCTAssertTrue(FileManager.default.fileExists(atPath: vault.appendingPathComponent("Courses/Notion/Course.md").path))
        let index = try XCTUnwrap(workspace.index)
        try await waitUntil("the index has the imported notes") {
            (try? await index.resolve("Week 1", from: try VaultPath("Courses/Existing.md")))?.first?.rawValue == "Courses/Notion/Course/Week 1.md"
        }
        workspace.endNotionImport()
        XCTAssertNil(workspace.notionImport)
    }

    func testASecondImportWaitsAndTheVaultIsKeptWhileOneRuns() async throws {
        let (workspace, vault) = try await makeWorkspace()
        let export = try NotionImportRunTests.writeExport(in: try TemporaryVault.make(prefix: "NotionExport", for: self))
        XCTAssertTrue(workspace.importNotionExport([export], into: .root))
        let session = try XCTUnwrap(workspace.notionImport)
        session.pauseImport()
        XCTAssertFalse(workspace.importNotionExport([export], into: .root))
        XCTAssertEqual(workspace.errorMessage, "A Notion export is already being imported. Import this one when that import has finished.")
        let otherVaults = try TemporaryVault.make(prefix: "NotionImportOtherVaults", for: self).root
        do {
            try await workspace.createVault(named: "Second", in: otherVaults)
            XCTFail("A Notion import runs, so the vault is kept.")
        } catch {
            XCTAssertEqual(error as? VaultSwitchRefusal, .notionImportIsRunning)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: otherVaults.appendingPathComponent("Second").path))
        XCTAssertEqual(workspace.folderAccess?.root, vault)
        session.resumeImport()
        try await waitUntil("the Notion import has ended") { if case .finished = workspace.notionImport?.state { true } else { false } }
        workspace.endNotionImport()
    }
}
