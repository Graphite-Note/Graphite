/**
 * File: NotionImportedVaultPassTests.swift
 * ----------------------------------------
 * Layer: Tests
 * Description: Notion import, 6.2, on the Mac: every note Obsidian's Importer wrote from made-up Notion material opens in
 *              reading view, Live Preview and source mode without a finding, and its base draws.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 17/11/2026
 */

#if os(macOS)
import XCTest
import GraphiteCore
#if canImport(GraphiteFixtures)
import GraphiteFixtures
#endif
@testable import GraphiteUI

/// The release pass (`ReleaseVaultPass`) over `Tests/NotionImportedVault`, which the runtime's Notion tests keep equal to
/// what Importer writes. Small enough to run in every suite: 21 notes, a base, a picture and a PDF.
@MainActor
final class NotionImportedVaultPassTests: XCTestCase {
    func testEveryImportedNoteOpensInItsThreeViewsAndTheBaseDrawsWithoutAFinding() async throws {
        let pass = try await ReleaseVaultPass.open(for: self, vault: FixtureFolders.notionImportedVault)
        try await pass.runFiles(inTopLevel: NotionImportedVaultPass.topLevelNames)
        pass.printReport()
        XCTAssertEqual(pass.openedFileCount, NotionImportedVaultPass.fileCount, "Every imported file was opened.")
        XCTAssertEqual(pass.findings, [], "Each finding is printed on a GRAPHITE-RELEASE-FINDING line.")
    }
}
#endif

/// What the pass opens of `Tests/NotionImportedVault`: both imports and the export's two attachments, not its README.
enum NotionImportedVaultPass {
    static let topLevelNames: Set<String> = ["Notion", "spectrum plot.png", "Problem set 1.pdf"]
    /// 17 notes of the HTML export and 2 attachments, 3 notes and a base of the API import.
    static let fileCount = 23
}
