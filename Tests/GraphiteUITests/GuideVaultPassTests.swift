/**
 * File: GuideVaultPassTests.swift
 * -------------------------------
 * Layer: Tests
 * Description: The release pass over the Graphite Guide vault on the Mac: every note in its three views and every other
 *              file in its own, with a screenshot of every page and no finding.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 16/11/2026
 */

#if os(macOS)
import XCTest
import GraphiteCore
#if canImport(GraphiteFixtures)
import GraphiteFixtures
#endif
@testable import GraphiteUI

/// Runs only with `GRAPHITE_RELEASE_PASS=1`, as `ReleaseVaultPassTests` does, over `Guide/Graphite Guide` in two halves.
/// The guide shows what works, so it has no deliberate failure: every finding fails the test.
@MainActor
final class GuideVaultPassTests: XCTestCase {
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

/// The guide's top-level folders and files in two halves, one test each, so each stays within the hosted tests' time.
enum GuideVaultPassHalf {
    static let firstHalf: Set<String> = ["Start here.md", "1 New to files", "2 Coming from Obsidian", "3 Handwriting and PDFs", "4 Making notes look good"]
    static let secondHalf: Set<String> = ["5 Connecting notes", "6 Everyday examples", "7 Making it yours", "Templates", "Attachments"]
}
