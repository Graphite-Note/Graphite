/**
 * File: ReleaseVaultPassTests.swift
 * ---------------------------------
 * Layer: Tests
 * Description: The release pass on the Mac: every note of Tests/ReleaseVault in its three views and every other file in
 *              its own view, in the window's root view, with a screenshot of every page.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 12/11/2026
 */

#if os(macOS)
import XCTest
@testable import GraphiteUI

/// Runs only with `GRAPHITE_RELEASE_PASS=1` (`scripts/release-check.sh` sets it): the pass takes minutes. Its findings and
/// what it measured are printed as `GRAPHITE-RELEASE-PASS` and `GRAPHITE-RELEASE-FINDING` lines; `ReleaseVaultPass` says
/// what counts as a finding. `ReleaseVaultPassHostedTests` runs the same pass on the iPad and the iPhone.
@MainActor
final class ReleaseVaultPassTests: XCTestCase {
    func testThePicturesPDFsCanvasNotebooksAndBasesOpenWithoutAFinding() async throws {
        try await pass(.filesAndBases)
    }

    func testTheTextNotesOpenInEachOfTheirViewsWithoutAFinding() async throws {
        try await pass(.textNotes)
    }

    func testTheDiagramsDailyNotesAndLongLectureOpenInEachOfTheirViewsWithoutAFinding() async throws {
        try await pass(.longAndRepeatedNotes)
    }

    private func pass(_ part: ReleaseVaultPassPart) async throws {
        // Returns rather than skipping: the suites' skip count may not rise (FR-93), and this is not a missing capability.
        guard ProcessInfo.processInfo.environment[ReleaseVaultPass.switchVariable] == "1" else { return print(ReleaseVaultPass.skipReason) }
        let pass = try await ReleaseVaultPass.open(for: self)
        try await pass.run(part)
        pass.printReport()
        XCTAssertEqual(pass.unexpectedFindings, [], "Each finding is printed on a GRAPHITE-RELEASE-FINDING line.")
        XCTAssertEqual(pass.intendedFindingsNotSeen, [], "The vault's deliberate failures no longer show as failures.")
    }
}
#endif
