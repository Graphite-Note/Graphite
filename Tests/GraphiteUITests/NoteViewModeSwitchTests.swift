/**
 * File: NoteViewModeSwitchTests.swift
 * -----------------------------------
 * Layer: Tests
 * Description: A note's switch of view mode: what it changed, and the places its views start at, each taken once.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 13/11/2026
 */

import XCTest
@testable import GraphiteUI

final class NoteViewModeSwitchTests: XCTestCase {
    func testASwitchSaysWhatItChangedAndEachStartingPlaceIsTakenOnce() {
        var viewModeSwitch = NoteViewModeSwitch()
        var topLocationAsks = 0
        func readingTop() -> Int? {
            topLocationAsks += 1
            return 1_200
        }
        XCTAssertEqual(viewModeSwitch.switchMode(to: .livePreview, readingTopLocation: readingTop), .unchanged)
        XCTAssertEqual(viewModeSwitch.switchMode(to: .source, readingTopLocation: readingTop), .changedWhileWriting)
        XCTAssertFalse(viewModeSwitch.takeReadingStartsWhereEditorWas(), "No switch to reading yet")
        XCTAssertEqual(viewModeSwitch.switchMode(to: .reading, readingTopLocation: readingTop), .enteredReading)
        XCTAssertEqual(viewModeSwitch.mode, .reading)
        XCTAssertTrue(viewModeSwitch.takeReadingStartsWhereEditorWas())
        XCTAssertFalse(viewModeSwitch.takeReadingStartsWhereEditorWas(), "Taken once")
        XCTAssertEqual(topLocationAsks, 0, "The reading view's top is asked only on leaving it")
        XCTAssertEqual(viewModeSwitch.switchMode(to: .source, readingTopLocation: readingTop), .leftReading(topLocation: 1_200))
        XCTAssertEqual(viewModeSwitch.takeEditingStartLocation(), 1_200)
        XCTAssertNil(viewModeSwitch.takeEditingStartLocation(), "Taken once")
    }

    func testLeavingTheReadingViewAtItsTopStartsTheEditorAtTheNotesStart() {
        var viewModeSwitch = NoteViewModeSwitch()
        _ = viewModeSwitch.switchMode(to: .reading) { nil }
        XCTAssertEqual(viewModeSwitch.switchMode(to: .livePreview) { nil }, .leftReading(topLocation: nil))
        XCTAssertEqual(viewModeSwitch.takeEditingStartLocation(), 0)
    }
}
