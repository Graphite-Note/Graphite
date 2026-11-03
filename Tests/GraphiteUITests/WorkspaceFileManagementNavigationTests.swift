/**
 * File: WorkspaceFileManagementNavigationTests.swift
 * --------------------------------------------------
 * Layer: Tests
 * Description: What renaming, moving and deleting files does to the tabs, selection and unlocked PDFs.
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
final class WorkspaceFileManagementNavigationTests: XCTestCase {
    private let testBed = WorkspaceModelTestBed()

    override func tearDown() async throws {
        testBed.tearDown()
    }

    /// HUNT-183: renaming the open file changed the selection like opening a file does, and a
    /// phone slid the document over the file list the person was working in.
    func testRenamingTheOpenFileIsNotTakenForOpeningAFile() async throws {
        let (workspace, _) = try await testBed.openedWorkspace(files: ["Old.md": "Old.", "Other.md": "Other."])
        try await waitUntil { workspace.hasCompletedIndexScan }
        try await testBed.open("Old.md", in: workspace)
        XCTAssertFalse(workspace.takeSelectionChangeFromFileManagement(), "Opening a file is not file management.")

        await workspace.rename(try VaultPath("Old.md"), to: "New")

        XCTAssertEqual(workspace.selection?.rawValue, "New.md")
        XCTAssertTrue(workspace.takeSelectionChangeFromFileManagement())
        XCTAssertFalse(workspace.takeSelectionChangeFromFileManagement(), "Asking once answers once.")
    }

    func testDeletingTheOpenFileWhileAnotherTabIsOpenIsNotTakenForOpeningAFile() async throws {
        let (workspace, _) = try await testBed.openedWorkspace(files: ["First.md": "First.", "Second.md": "Second."])
        try await testBed.open("First.md", in: workspace)
        try await testBed.open("Second.md", in: workspace, placement: .newTab)
        _ = workspace.takeSelectionChangeFromFileManagement()

        workspace.forgetInNavigation(try VaultPath("Second.md"))

        XCTAssertEqual(workspace.selection?.rawValue, "First.md")
        XCTAssertTrue(workspace.takeSelectionChangeFromFileManagement())
    }

    func testMovingAFileThatIsNotOpenChangesNoSelection() async throws {
        let (workspace, _) = try await testBed.openedWorkspace(files: ["Open.md": "Open.", "Elsewhere.md": "Elsewhere."])
        try await testBed.open("Open.md", in: workspace)

        workspace.followMoveInNavigation(from: try VaultPath("Elsewhere.md"), to: try VaultPath("Moved.md"))

        XCTAssertFalse(workspace.takeSelectionChangeFromFileManagement(), "Nothing changed, so a later change of selection is not mistaken for this one.")
    }

    func testOpeningAFileAfterARenameCountsAsOpeningAgain() async throws {
        let (workspace, _) = try await testBed.openedWorkspace(files: ["Old.md": "Old.", "Other.md": "Other."])
        try await waitUntil { workspace.hasCompletedIndexScan }
        try await testBed.open("Old.md", in: workspace)
        await workspace.rename(try VaultPath("Old.md"), to: "New")
        _ = workspace.takeSelectionChangeFromFileManagement()

        try await testBed.open("Other.md", in: workspace)

        XCTAssertFalse(workspace.takeSelectionChangeFromFileManagement())
    }

    /// HUNT-193: the password of an unlocked PDF was kept under its old path.
    func testAnUnlockedPDFsPasswordFollowsItWhenItIsRenamedOrItsFolderMoves() async throws {
        let (workspace, _) = try await testBed.openedWorkspace(files: ["Course/Slides.pdf": "not read", "Other.pdf": "not read"])
        workspace.pdfPasswords[try VaultPath("Course/Slides.pdf")] = "secret"
        workspace.pdfPasswords[try VaultPath("Other.pdf")] = "kept"

        workspace.followMoveInNavigation(from: try VaultPath("Course"), to: try VaultPath("Archive/Course"))
        workspace.followMoveInNavigation(from: try VaultPath("Archive/Course/Slides.pdf"), to: try VaultPath("Archive/Course/Lecture.pdf"))

        XCTAssertEqual(workspace.pdfPasswords[try VaultPath("Archive/Course/Lecture.pdf")], "secret")
        XCTAssertNil(workspace.pdfPasswords[try VaultPath("Course/Slides.pdf")])
        XCTAssertEqual(workspace.pdfPasswords[try VaultPath("Other.pdf")], "kept", "A file that did not move keeps its password under its own path.")
        XCTAssertEqual(workspace.pdfPasswords.count, 2)
    }

    /// HUNT-198: a closed tab's file deleted in another app was popped and failed with an
    /// alert, and the entry was gone; the closed tab before it is reopened.
    func testReopenClosedTabSkipsAFileDeletedInAnotherApp() async throws {
        let (workspace, vault) = try await testBed.openedWorkspace(files: ["Kept.md": "Kept.", "Gone.md": "Gone.", "Staying.md": "Staying."])
        try await testBed.open("Staying.md", in: workspace)
        let keptTab = try await testBed.open("Kept.md", in: workspace, placement: .newTab)
        let goneTab = try await testBed.open("Gone.md", in: workspace, placement: .newTab)
        await workspace.closeTab(keptTab)
        await workspace.closeTab(goneTab)
        try FileManager.default.removeItem(at: vault.appendingPathComponent("Gone.md"))
        workspace.errorMessage = nil

        await workspace.reopenClosedTab()

        XCTAssertNil(workspace.errorMessage, "No alert for the file that is gone.")
        XCTAssertEqual(workspace.selection?.rawValue, "Kept.md")
        XCTAssertFalse(workspace.layout.canReopenClosedTab, "Gone.md is dropped from the closed tabs, not kept for another try.")
    }
}
