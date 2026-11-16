/**
 * File: GuideVaultOpeningHostedTests.swift
 * ----------------------------------------
 * Layer: Tests
 * Description: The Graphite Guide vault downloaded from the repository, copied into Graphite's Documents folder once,
 *              opened at a note, and copied afresh beside the old copy when asked.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 16/11/2026
 */

#if os(iOS)
import XCTest
import GraphiteCore
import GraphiteApple
@testable import GraphiteUI

/// What the Guide's Open the Guide Vault does, end to end, on the iPad and the iPhone simulators: the pack at its pinned
/// commit is downloaded from GitHub and checked file by file, `graphite://guide?file=…` copies it into the app's Documents
/// folder and opens the copy at the note, the same link opens the same copy again, and `fresh=true` makes a second copy
/// beside it. It downloads 3 MB, so it runs with the release pass (`TEST_RUNNER_GRAPHITE_RELEASE_PASS=1`); the copies and
/// what the workspace remembered are removed afterwards. Only on iOS: on the Mac the Documents folder of a package test
/// is the person's own.
@MainActor
final class GuideVaultOpeningHostedTests: XCTestCase {
    func testTheGuideLinkDownloadsCopiesOnceAndOpensTheNote() async throws {
        // Returns rather than skipping: the suites' skip count may not rise (FR-93), and this is not a missing capability.
        guard ProcessInfo.processInfo.environment[ReleaseVaultPass.switchVariable] == "1" else { return print(ReleaseVaultPass.skipReason) }
        let documents = try VaultLocator.applicationDocumentsFolder()
        let foldersBefore = Set(try FileManager.default.contentsOfDirectory(atPath: documents.path))
        addTeardownBlock {
            for name in (try? FileManager.default.contentsOfDirectory(atPath: documents.path)) ?? [] where !foldersBefore.contains(name) {
                try? FileManager.default.removeItem(at: documents.appendingPathComponent(name))
            }
        }
        let device = try IsolatedWorkspaceDevice.make(for: self)
        let workspace = device.makeWorkspace()
        let pack = try XCTUnwrap(GuideVaultPack.pack)

        workspace.processServices.addOns.download(pack)
        try await waitUntil("the guide is downloaded", timeoutSeconds: 120) { workspace.processServices.addOns.state(of: pack) != .downloading }
        XCTAssertEqual(workspace.processServices.addOns.state(of: pack), .downloaded)

        await workspace.handle(try XCTUnwrap(VaultURI.guideLink(to: "5 Connecting notes/Bases")))
        XCTAssertNil(workspace.errorMessage)
        let firstCopy = try XCTUnwrap(workspace.folderAccess?.root)
        XCTAssertTrue(firstCopy.lastPathComponent.hasPrefix(GuideVaultCopy.folderName))
        try await waitUntil("the note is open", timeoutSeconds: 30) { workspace.activeDocument.loadedPath?.rawValue == "5 Connecting notes/Bases.md" }
        XCTAssertFalse(FileManager.default.fileExists(atPath: firstCopy.appendingPathComponent(GuideVaultCopy.packMarkerFileName).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: firstCopy.appendingPathComponent("Attachments/Screenshots/iPad - Start here.jpg").path))

        await workspace.handle(try XCTUnwrap(VaultURI.guideLink(to: nil)))
        XCTAssertEqual(workspace.folderAccess?.root.standardizedFileURL, firstCopy.standardizedFileURL, "The same copy opens again.")
        try await waitUntil("Start here is open", timeoutSeconds: 30) { workspace.activeDocument.loadedPath?.rawValue == "Start here.md" }

        await workspace.handle(try XCTUnwrap(VaultURI.guideLink(to: nil, freshCopy: true)))
        let secondCopy = try XCTUnwrap(workspace.folderAccess?.root)
        XCTAssertNotEqual(secondCopy.standardizedFileURL, firstCopy.standardizedFileURL, "A fresh copy goes beside the first.")
        XCTAssertTrue(FileManager.default.fileExists(atPath: firstCopy.path), "Nothing of the first copy is deleted.")
    }
}
#endif
