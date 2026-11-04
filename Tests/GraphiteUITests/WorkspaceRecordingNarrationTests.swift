/**
 * File: WorkspaceRecordingNarrationTests.swift
 * --------------------------------------------
 * Layer: Tests
 * Description: Checks when starting a recording stops Read Aloud: once the recording runs, not when it is refused.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 01/11/2026
 */

import XCTest
import CoreMedia
import GraphiteCore
@testable import GraphiteApple
@testable import GraphiteUI
import GraphiteTestSupport

/// A camera and microphone that start without delivering anything, or are refused; no hardware is touched and nothing sounds.
private final class SilentCaptureSource: VideoCaptureSource, @unchecked Sendable {
    let refusal: CaptureAccessProblem?
    init(refusal: CaptureAccessProblem?) { self.refusal = refusal }

    func start(camera: CameraPosition, deliveringOn deliveryQueue: DispatchQueue,
               samples: @escaping @Sendable (CMSampleBuffer, CaptureMediaKind) -> Void,
               events: @escaping @Sendable (VideoCaptureEvent) -> Void) async throws {
        if let refusal { throw refusal }
    }
    func availableCameras() async -> [CameraPosition] { [.back] }
    func switchCamera(to camera: CameraPosition) async throws {}
    func resumeAfterInterruption() async throws {}
    func stop() async {}
}

/// HUNT-226: starting a recording stopped Read Aloud in every window first, so a recording that then failed (microphone
/// denied) left the listening session cleared and nothing recorded.
@MainActor
final class WorkspaceRecordingNarrationTests: XCTestCase {
    private var device: IsolatedWorkspaceDevice!
    private var processServices: ProcessServices!

    override func setUp() async throws {
        device = try IsolatedWorkspaceDevice.make(for: self)
        processServices = device.makeServices()
        processServices.preferences.setEnabled(.readAloud, true)
    }

    private func makeWindow(refusal: CaptureAccessProblem?) async throws -> WorkspaceModel {
        let vault = try TemporaryVault.make(prefix: "RecordingNarrationVault", for: self).root.resolvingSymlinksInPath()
        try Data("A note to read.".utf8).write(to: vault.appendingPathComponent("Note.md"))
        let window = WorkspaceModel(processServices: processServices, clock: LiveApplicationClock())
        try await window.openFolderAsVault(vault)
        let recoveryFolder = try TemporaryVault.make(prefix: "RecordingNarrationRecovery", for: self).root
        window.recording.recoveryFolderLocation = { recoveryFolder }
        window.recording.makeVideoCaptureSource = { SilentCaptureSource(refusal: refusal) }
        return window
    }

    func testARefusedRecordingLeavesReadAloudWhereItWas() async throws {
        let readingWindow = try await makeWindow(refusal: nil)
        let recordingWindow = try await makeWindow(refusal: .microphoneDenied)
        let reader = try XCTUnwrap(readingWindow.readAloud)
        reader.readMarkdown("A note to read.", path: try VaultPath("Note.md"))
        XCTAssertTrue(reader.isReading)
        let stopIdentifierBefore = reader.stopIdentifier

        await recordingWindow.startRecording(.video)

        XCTAssertEqual(recordingWindow.recording.state, .failed)
        XCTAssertEqual(reader.stopIdentifier, stopIdentifierBefore, "A recording that did not start must not stop the narration.")
        XCTAssertTrue(reader.isReading, "A recording that did not start must not end the listening session.")
        XCTAssertNil(reader.errorMessage)
        reader.clear()
    }

    func testARecordingThatRunsStopsReadAloudInTheOtherWindows() async throws {
        let readingWindow = try await makeWindow(refusal: nil)
        let recordingWindow = try await makeWindow(refusal: nil)
        let reader = try XCTUnwrap(readingWindow.readAloud)
        reader.readMarkdown("A note to read.", path: try VaultPath("Note.md"))
        XCTAssertTrue(reader.isReading)
        let stopIdentifierBefore = reader.stopIdentifier

        await recordingWindow.startRecording(.video)

        XCTAssertEqual(recordingWindow.recording.state, .recording)
        XCTAssertNotEqual(reader.stopIdentifier, stopIdentifierBefore, "The microphone and audio output go to the recording: the narration stopped.")
        recordingWindow.recording.stop()
        try await waitUntil("the recording to finish") {
            recordingWindow.recording.state != .recording && recordingWindow.recording.state != .finalizing
        }
        reader.clear()
    }
}
