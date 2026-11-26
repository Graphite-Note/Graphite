/**
 * File: SlidePositionTests.swift
 * ------------------------------
 * Layer: Tests
 * Description: The slide shown in a presentation and the moves between slides, at the ends and without slides.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

import XCTest
@testable import GraphiteCore

final class SlidePositionTests: XCTestCase {
    func testMovesStopAtTheEnds() {
        var position = SlidePosition(slideCount: 3)
        XCTAssertFalse(position.apply(.previous))
        XCTAssertTrue(position.apply(.next))
        XCTAssertTrue(position.apply(.next))
        XCTAssertEqual(position.index, 2)
        XCTAssertNil(position.nextIndex)
        XCTAssertFalse(position.apply(.next))
        XCTAssertTrue(position.apply(.first))
        XCTAssertEqual(position.index, 0)
        XCTAssertEqual(position.nextIndex, 1)
        XCTAssertTrue(position.apply(.last))
        XCTAssertEqual(position.index, 2)
        XCTAssertFalse(position.apply(.last))
    }

    func testAPresentationWithoutSlidesNeverMoves() {
        var position = SlidePosition(slideCount: 0)
        for move in [SlideMove.next, .previous, .first, .last] { XCTAssertFalse(position.apply(move)) }
        XCTAssertEqual(position.index, 0)
        XCTAssertNil(position.nextIndex)
    }

    func testAStartingIndexOutsideTheSlidesIsKeptInside() {
        XCTAssertEqual(SlidePosition(slideCount: 4, index: 9).index, 3)
        XCTAssertEqual(SlidePosition(slideCount: 4, index: -2).index, 0)
    }
}
