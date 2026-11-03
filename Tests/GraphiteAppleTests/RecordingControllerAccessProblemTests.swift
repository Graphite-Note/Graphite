/**
 * File: RecordingControllerAccessProblemTests.swift
 * -------------------------------------------------
 * Layer: Tests
 * Description: Checks what Record Audio tells the person when the microphone is refused or the recording could not be saved.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 01/11/2026
 */

import XCTest
import GraphiteCore
@testable import GraphiteApple
import GraphiteTestSupport

/// Neither test records: the permission answer is a stand-in, and the recording that cannot be saved is bytes that are no audio.
@MainActor
final class RecordingControllerAccessProblemTests: XCTestCase {
    private func manifest() -> RecordingRecoveryManifest {
        RecordingRecoveryManifest(vaultIdentifier: nil, destinationPath: "Lecture.m4a", notePath: nil, startedAt: .now)
    }

    /// HUNT-231: Record Audio said to enable the microphone in privacy settings, but offered no Open Settings button as
    /// video does, because only the video path set `accessProblem`.
    func testARefusedMicrophoneSetsTheProblemTheControlsOfferSettingsFor() async throws {
        let folder = try TemporaryVault.make(prefix: "AccessProblem", for: self).root
        let controller = RecordingController()
        controller.requestMicrophoneAccess = { false }
        controller.isMicrophoneRestricted = { false }

        await controller.start(destination: folder.appendingPathComponent("Lecture.m4a"), manifest: manifest())

        XCTAssertEqual(controller.state, .failed)
        XCTAssertEqual(controller.accessProblem, .microphoneDenied)
        XCTAssertEqual(controller.accessProblem?.canBeChangedInSettings, true)
        XCTAssertEqual(controller.message, "Microphone access is required. Enable it in system privacy settings.")
    }

    func testAMicrophoneRestrictedByTheDeviceIsToldApart() async throws {
        let folder = try TemporaryVault.make(prefix: "AccessProblem", for: self).root
        let controller = RecordingController()
        controller.requestMicrophoneAccess = { false }
        controller.isMicrophoneRestricted = { true }

        await controller.start(destination: folder.appendingPathComponent("Lecture.m4a"), manifest: manifest())

        XCTAssertEqual(controller.accessProblem, .microphoneRestricted)
    }

    /// HUNT-232: the failure message gave the path of Graphite's private recovery folder, which no one can open.
    func testARecordingThatCannotBeSavedIsKeptWithoutNamingAFolderNoOneCanReach() async throws {
        let folder = try TemporaryVault.make(prefix: "AccessProblemSave", for: self).root
        let recovery = folder.appendingPathComponent("recording.caf")
        try Data(repeating: 0x2A, count: 10_000).write(to: recovery)
        let controller = RecordingController()
        controller.adoptRecording(at: recovery, destination: folder.appendingPathComponent("Lecture.m4a"), state: .failed, message: nil)

        await controller.retryPublication()

        XCTAssertEqual(controller.state, .failed)
        let message = try XCTUnwrap(controller.message)
        XCTAssertTrue(message.hasSuffix("The recording is kept on this device until it is saved or discarded."), message)
        XCTAssertFalse(message.contains(folder.path), "The private recovery path is not shown.")
        XCTAssertTrue(FileManager.default.fileExists(atPath: recovery.path))
    }
}
