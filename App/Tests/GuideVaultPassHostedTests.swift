/**
 * File: GuideVaultPassHostedTests.swift
 * -------------------------------------
 * Layer: Tests
 * Description: The release pass over the Graphite Guide vault on the iPad and the iPhone simulators.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 16/11/2026
 */

#if os(iOS)
import XCTest
@testable import GraphiteUI

/// The pass `GuideVaultPassTests` runs on the Mac, in the scene's window at the simulator's own size. Runs only with
/// `TEST_RUNNER_GRAPHITE_RELEASE_PASS=1` given to xcodebuild, as `ReleaseVaultPassHostedTests` does; the screenshots are in
/// the result bundle's attachments, and in `TEST_RUNNER_GRAPHITE_RELEASE_PASS_SCREENSHOTS` when it names a folder.
@MainActor
final class GuideVaultPassHostedTests: XCTestCase {
    func testTheStartTheTwoPathsAndTheFeatureNotesOpenWithoutAFinding() async throws {
        try await pass(GuideVaultPassHalf.firstHalf)
    }

    func testTheConnectingNotesExamplesAndSettingsOpenWithoutAFinding() async throws {
        try await pass(GuideVaultPassHalf.secondHalf)
    }

    private func pass(_ topLevelNames: Set<String>) async throws {
        // Returns rather than skipping: the suites' skip count may not rise (FR-93), and this is not a missing capability.
        guard ProcessInfo.processInfo.environment[ReleaseVaultPass.switchVariable] == "1" else { return print(ReleaseVaultPass.skipReason) }
        let pass = try await ReleaseVaultPass.open(for: self, vault: FixtureFolders.guideVault)
        try await pass.runFiles(inTopLevel: topLevelNames)
        pass.printReport()
        XCTAssertGreaterThan(pass.openedFileCount, 20, "The pass found the guide's files.")
        XCTAssertEqual(pass.findings, [], "Each finding is printed on a GRAPHITE-RELEASE-FINDING line.")
    }
}
#endif
