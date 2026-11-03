/**
 * File: WorkspaceSettingsProblemReportingTests.swift
 * --------------------------------------------------
 * Layer: Tests
 * Description: A vault settings file that cannot be read is reported once, not at every return to the window.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 01/11/2026
 */

import XCTest
import GraphiteCore
@testable import GraphiteUI

/// HUNT-184: reading the settings again, as coming back to the window does when a settings
/// file changed, showed the alert for the same unreadable file each time.
@MainActor
final class WorkspaceSettingsProblemReportingTests: XCTestCase {
    private let testBed = WorkspaceModelTestBed()

    override func tearDown() async throws {
        testBed.tearDown()
    }

    /// Larger than the 1 MiB an Obsidian settings file may hold, so it cannot be read.
    private static let oversizedSettingsFile = #"{"folder": ""# + String(repeating: "x", count: 1_100_000) + #""}"#

    func testAnUnreadableSettingsFileIsReportedOnceWhileTheSettingsAreReadAgain() async throws {
        let (workspace, _) = try await testBed.openedWorkspace(files: [".obsidian/templates.json": Self.oversizedSettingsFile, "Welcome.md": "Welcome\n"])
        XCTAssertNotNil(workspace.errorMessage, "The first reading tells the person.")

        workspace.errorMessage = nil
        await workspace.reloadVaultSettings()
        await workspace.reloadVaultSettings()

        XCTAssertNil(workspace.errorMessage, "The same problem is not shown again after the person dismissed it.")
    }

    func testAFileThatReadsFineAndFailsAgainIsReportedAgain() async throws {
        let (workspace, vault) = try await testBed.openedWorkspace(files: [".obsidian/templates.json": Self.oversizedSettingsFile, "Welcome.md": "Welcome\n"])
        let settingsFile = vault.appendingPathComponent(".obsidian/templates.json")
        try #"{"folder": "Templates"}"#.write(to: settingsFile, atomically: true, encoding: .utf8)
        workspace.errorMessage = nil
        await workspace.reloadVaultSettings()
        XCTAssertNil(workspace.errorMessage)

        try Self.oversizedSettingsFile.write(to: settingsFile, atomically: true, encoding: .utf8)
        await workspace.reloadVaultSettings()

        XCTAssertNotNil(workspace.errorMessage, "A new failure is news.")
    }

    func testAnotherVaultWithTheSameProblemIsReported() async throws {
        let (workspace, _) = try await testBed.openedWorkspace(files: [".obsidian/templates.json": Self.oversizedSettingsFile, "Welcome.md": "Welcome\n"])
        workspace.errorMessage = nil

        try await workspace.openFolderAsVault(try testBed.makeVault(files: [".obsidian/templates.json": Self.oversizedSettingsFile, "Welcome.md": "Welcome\n"]))

        XCTAssertNotNil(workspace.errorMessage)
    }
}
