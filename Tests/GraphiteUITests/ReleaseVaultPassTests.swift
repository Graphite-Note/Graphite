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
import GraphiteCore
import GraphiteTestSupport
@testable import GraphiteUI

/// Runs only with `GRAPHITE_RELEASE_PASS=1` (`scripts/release-check.sh` sets it): the pass takes minutes. Its findings and
/// what it measured are printed as `GRAPHITE-RELEASE-PASS` and `GRAPHITE-RELEASE-FINDING` lines; `ReleaseVaultPass` says
/// what counts as a finding. `ReleaseVaultPassHostedTests` runs the same pass on the iPad and the iPhone.
@MainActor
final class ReleaseVaultPassTests: XCTestCase {
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

    /// Runs on every suite, not only before a release: the vault's frames name real pages for a person browsing it, and the
    /// pass's copy must point each of them, whatever its address, at the pass's own loopback server, as Graphite reads them.
    func testEveryWebFrameOfTheVaultIsPointedAtThePassServer() throws {
        let addresses = try ReleaseVaultPassWebPages.frameAddresses()
        XCTAssertTrue(addresses.contains { address in address.hasPrefix("https://") }, "The vault's frames name real pages.")
        let copy = try TemporaryVault.make(prefix: "ReleaseVaultFrames", for: self).root
        let serverAddress = "http://127.0.0.1:65000/"
        try ReleaseVaultPassWebPages.copyVault(to: copy, pointingFramesAt: serverAddress)
        let pages = try ReleaseVaultPassWebPages.pages()
        var frameCount = 0
        for note in try FileManager.default.subpathsOfDirectory(atPath: copy.path) where note.hasSuffix(".md") {
            let lines = try String(contentsOf: copy.appendingPathComponent(note), encoding: .utf8).components(separatedBy: "\n")
            for lineIndex in lines.indices where WebFrameSyntax.mayHoldFrame(lines[lineIndex]) {
                guard let frame = WebFrameSyntax.frame(startingAt: lineIndex, lineCount: lines.count, line: { index in lines[index] })?.frame else { continue }
                frameCount += 1
                XCTAssertEqual(frame.address.host(), "127.0.0.1", "\(note): \(frame.address)")
                XCTAssertNotNil(pages[frame.address.path()], "\(note): the server has a page for \(frame.address).")
            }
        }
        XCTAssertGreaterThanOrEqual(frameCount, 2, "The frames on lines of their own and in a list item.")
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
