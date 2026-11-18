/**
 * File: NotionImportedVaultPassHostedTests.swift
 * ----------------------------------------------
 * Layer: Tests
 * Description: Notion import, 6.2, on the iPad and iPhone simulators: every note Obsidian's Importer wrote from made-up
 *              Notion material opens in its three views without a finding, and its base draws.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 17/11/2026
 */

#if os(iOS)
import XCTest
@testable import GraphiteUI

/// The pass `NotionImportedVaultPassTests` runs on the Mac, in the scene's window at the simulator's own size.
@MainActor
final class NotionImportedVaultPassHostedTests: XCTestCase {
    func testEveryImportedNoteOpensInItsThreeViewsAndTheBaseDrawsWithoutAFinding() async throws {
        let pass = try await ReleaseVaultPass.open(for: self, vault: FixtureFolders.notionImportedVault)
        try await pass.runFiles(inTopLevel: NotionImportedVaultPass.topLevelNames)
        pass.printReport()
        XCTAssertEqual(pass.openedFileCount, NotionImportedVaultPass.fileCount, "Every imported file was opened.")
        XCTAssertEqual(pass.findings, [], "Each finding is printed on a GRAPHITE-RELEASE-FINDING line.")
    }
}
#endif
