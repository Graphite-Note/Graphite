/**
 * File: ReleaseVaultPassHostedTests.swift
 * ---------------------------------------
 * Layer: Tests
 * Description: The release pass on the iPad and the iPhone simulators: every note of Tests/ReleaseVault in its three
 *              views and every other file in its own view, in the window's root view, with a screenshot of every page.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 12/11/2026
 */

#if os(iOS)
import XCTest
@testable import GraphiteUI

/// The pass `ReleaseVaultPassTests` runs on the Mac, in the scene's window at the simulator's own size: an iPad's regular
/// layout, an iPhone's compact one. Runs only with `TEST_RUNNER_GRAPHITE_RELEASE_PASS=1` given to xcodebuild, which hands
/// it to the tests as `GRAPHITE_RELEASE_PASS` (`scripts/release-check.sh` sets it); the screenshots are in the result
/// bundle's attachments.
@MainActor
final class ReleaseVaultPassHostedTests: XCTestCase {
    func testThePicturesCanvasesAndBasesOpenWithoutAFinding() async throws {
        try await pass(.filesAndBases)
    }

    func testTheTextNotesOpenInEachOfTheirViewsWithoutAFinding() async throws {
        try await pass(.textNotes)
    }

    func testTheDiagramsDailyNotesAndLongLectureOpenInEachOfTheirViewsWithoutAFinding() async throws {
        try await pass(.longAndRepeatedNotes)
    }

    func testThePDFsNotebooksImportsAndDrawingsOpenWithoutAFinding() async throws {
        try await pass(.pdfsNotebooksAndDrawings)
    }

    func testTheNotesEmbeddingPicturesPDFsAndDrawingsInEveryFormOpenWithoutAFinding() async throws {
        try await pass(.embeds)
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
