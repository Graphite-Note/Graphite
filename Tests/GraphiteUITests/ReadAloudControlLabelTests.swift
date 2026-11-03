/**
 * File: ReadAloudControlLabelTests.swift
 * --------------------------------------
 * Layer: Tests
 * Description: Checks the name of Read Aloud's play button in each state and the speeds its menus offer.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 01/11/2026
 */

import XCTest
import GraphiteApple
@testable import GraphiteUI

/// Plain values only: nothing here speaks.
@MainActor
final class ReadAloudControlLabelTests: XCTestCase {
    /// HUNT-234: the button was named Resume Reading even when nothing had started or the note was finished and Play
    /// starts again at the top.
    func testThePlayButtonIsNamedForWhatItDoes() {
        XCTAssertEqual(ReadAloudPlayPauseButton.title(for: .speaking), "Pause Reading")
        XCTAssertEqual(ReadAloudPlayPauseButton.title(for: .paused), "Resume Reading")
        XCTAssertEqual(ReadAloudPlayPauseButton.title(for: .idle), "Play Reading")
        XCTAssertEqual(ReadAloudPlayPauseButton.title(for: .finished), "Start Over")
    }

    /// HUNT-235: the menus started at 0.75× although the session allows and restores 0.5×, so a saved 0.5× showed nothing selected.
    func testEverySpeedTheSessionAllowsInQuarterStepsIsInTheMenus() {
        let speeds = ReadAloudVoiceSettings.speeds
        XCTAssertEqual(speeds.first, 0.5)
        XCTAssertEqual(speeds.last, 3)
        XCTAssertEqual(speeds.count, 11)
        XCTAssertTrue(speeds.allSatisfy { speed in ReadAloudSession.speedRange.contains(speed) })
        XCTAssertTrue(speeds.contains(1), "Normal speed is offered.")
    }
}
