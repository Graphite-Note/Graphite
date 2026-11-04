/**
 * File: WorkspaceRecordingRecoveryFailureTests.swift
 * --------------------------------------------------
 * Layer: Tests
 * Description: Checks that an unfinished recording that could not be saved is not offered again at once.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 01/11/2026
 */

import XCTest
import GraphiteCore
@testable import GraphiteIndex
@testable import GraphiteApple
@testable import GraphiteUI
import GraphiteTestSupport

/// HUNT-229: converting an unfinished recording failed, and the Unfinished Recording alert came straight back, offering the
/// same recording again together with the error. The files here are bytes that are no audio: nothing is played or recorded.
@MainActor
final class WorkspaceRecordingRecoveryFailureTests: XCTestCase {
    private func makeFolder(_ prefix: String) throws -> URL {
        try TemporaryVault.make(prefix: prefix, for: self).root.resolvingSymlinksInPath()
    }

    private func makeWorkspace(_ vault: URL, recoveryFolder: URL) async throws -> WorkspaceModel {
        let workspace = WorkspaceModel()
        workspace.folderAccess = FolderAccess(root: vault)
        let store = VaultStore(root: vault)
        workspace.store = store
        workspace.vaultSettings = try await store.settings()
        workspace.index = try VaultIndex(databaseURL: try makeFolder("RecoveryFailureIndex").appendingPathComponent("index.sqlite"))
        workspace.recording.recoveryFolderLocation = { recoveryFolder }
        return workspace
    }

    private func makeBrokenRecording(named name: String, in folder: URL) throws -> URL {
        let location = folder.appendingPathComponent(name)
        try Data(repeating: 0x2A, count: 200_000).write(to: location)
        return location
    }

    func testARecordingThatFailedToSaveIsNotOfferedAgainWhileTheAppRuns() async throws {
        let vault = try makeFolder("RecoveryFailureVault")
        let recoveryFolder = try makeFolder("RecoveryFailureFolder")
        let broken = try makeBrokenRecording(named: "broken.caf", in: recoveryFolder)
        let workspace = try await makeWorkspace(vault, recoveryFolder: recoveryFolder)

        workspace.checkForUnfinishedRecordings()
        let offer = try XCTUnwrap(workspace.recordingRecoveryOffer)
        XCTAssertEqual(offer.mediaLocation.lastPathComponent, "broken.caf")

        await workspace.recover(offer)

        XCTAssertNotNil(workspace.errorMessage, "The failure is reported.")
        XCTAssertNil(workspace.recordingRecoveryOffer, "The recording that just failed is not offered again beside its error.")
        XCTAssertTrue(FileManager.default.fileExists(atPath: broken.path), "It stays on disk for the next launch.")
    }

    func testAnotherUnfinishedRecordingIsStillOfferedAfterOneFailed() async throws {
        let vault = try makeFolder("RecoveryFailureVault")
        let recoveryFolder = try makeFolder("RecoveryFailureFolder")
        _ = try makeBrokenRecording(named: "broken.caf", in: recoveryFolder)
        _ = try makeBrokenRecording(named: "other.caf", in: recoveryFolder)
        let workspace = try await makeWorkspace(vault, recoveryFolder: recoveryFolder)

        workspace.checkForUnfinishedRecordings()
        let first = try XCTUnwrap(workspace.recordingRecoveryOffer)
        await workspace.recover(first)

        let second = try XCTUnwrap(workspace.recordingRecoveryOffer, "The other recording is offered next.")
        XCTAssertNotEqual(second.mediaLocation, first.mediaLocation)
    }
}
