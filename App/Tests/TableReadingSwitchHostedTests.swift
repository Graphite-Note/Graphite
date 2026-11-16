/**
 * File: TableReadingSwitchHostedTests.swift
 * -----------------------------------------
 * Layer: Tests
 * Description: A note whose table holds a picture beside a wrapping formula switches from Live Preview, scrolled to its
 *              end, to the reading view without the main thread stopping (HUNT-360).
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 16/11/2026
 */

#if os(iOS)
import XCTest
import GraphiteCore
@testable import GraphiteUI

/// HUNT-360: the Graphite Guide's `Tables.md`, paged through in Live Preview to its end and switched to the reading view,
/// kept the iPad's main thread busy for good. Its table's picture cell was fitted to a width that came from the picture
/// itself, 80 points one layout pass and 79 the next, so the row's height and the blocks below it moved half a point at
/// every pass. The release pass opens the note in its three views, as `GuideVaultPassHostedTests` does, and a step that
/// does not settle within the pass's freeze budget is a finding.
@MainActor
final class TableReadingSwitchHostedTests: XCTestCase {
    func testTheGuideTablesNoteSwitchesToTheReadingViewWithoutAFinding() async throws {
        let pass = try await ReleaseVaultPass.open(for: self, vault: FixtureFolders.guideVault)
        try await pass.runNotes([try VaultPath("4 Making notes look good/Tables.md")])
        pass.printReport()
        XCTAssertEqual(pass.findings, [], "Each finding is printed on a GRAPHITE-RELEASE-FINDING line.")
    }
}
#endif
