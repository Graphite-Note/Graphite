/**
 * File: ReadAloudFollowingResumptionTests.swift
 * ---------------------------------------------
 * Layer: Tests
 * Description: Checks that Read Aloud goes back to following the reading after the person scrolled away while it was paused.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 01/11/2026
 */

import XCTest
import GraphiteCore
import GraphiteApple
@testable import GraphiteUI
import GraphiteTestSupport

/// A speech engine that makes no sound: it only records what it is asked to say.
@MainActor
private final class SilentSpeech: ReadAloudSpeaking {
    var eventHandler: (@MainActor (ReadAloudSpeechEvent) -> Void)?
    let voices = [ReadAloudVoice(id: "test", name: "Test", language: "en-US", quality: 3)]
    var requestIdentifiers: [UUID] = []
    func speak(_ text: String, voiceIdentifier: String, speed: Double, requestIdentifier: UUID) throws { requestIdentifiers.append(requestIdentifier) }
    func pause() -> Bool { true }
    func resume() -> Bool { true }
    func stop() {}
}

@MainActor
final class ReadAloudFollowingResumptionTests: XCTestCase {
    /// HUNT-225: the timer that brings following back used to do nothing while the reading was paused, and Play did not
    /// bring it back, so the highlight stayed where the person had scrolled until Back to Reading was tapped.
    func testPlayAfterScrollingAwayWhilePausedFollowsTheReadingAgain() async throws {
        let speech = SilentSpeech()
        let preferences = try IsolatedDeviceState.make(prefix: "ReadAloudFollowingResumption", for: self).preferences
        let session = ReadAloudSession(speech: speech, preferences: preferences)
        session.chooseVoice("test")
        let reader = ReadAloudController(session: session, preferences: preferences)
        reader.followResumptionDelay = .milliseconds(20)
        let path = try VaultPath("Following.md")
        reader.readMarkdown("First sentence.\n\nSecond sentence.", path: path)
        try await waitUntil("the note to be prepared") { !reader.isPreparing }
        session.play()
        XCTAssertTrue(reader.shouldFollow(path))

        session.pause()
        reader.suspendFollowing()
        XCTAssertFalse(reader.followsReading)
        try await waitUntil("following to come back") { reader.followsReading }
        XCTAssertTrue(reader.followsReading, "The resumption must not wait for the speech to be playing.")

        session.play()
        XCTAssertTrue(reader.shouldFollow(path), "Play after the pause follows the reading again.")
        reader.clear()
    }

    func testFollowingStaysOffUntilTheDelayEnds() async throws {
        let speech = SilentSpeech()
        let preferences = try IsolatedDeviceState.make(prefix: "ReadAloudFollowingDelay", for: self).preferences
        let session = ReadAloudSession(speech: speech, preferences: preferences)
        session.chooseVoice("test")
        let reader = ReadAloudController(session: session, preferences: preferences)
        reader.followResumptionDelay = .seconds(60)
        let path = try VaultPath("Following.md")
        reader.readMarkdown("First sentence.", path: path)
        try await waitUntil("the note to be prepared") { !reader.isPreparing }
        session.play()
        reader.suspendFollowing()
        XCTAssertFalse(reader.followsReading, "Scrolling away turns following off, and the long delay has not ended")
        XCTAssertFalse(reader.shouldFollow(path))
        reader.clear()
    }
}
