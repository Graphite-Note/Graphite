/**
 * File: CompletionPopupPlacementTests.swift
 * -----------------------------------------
 * Layer: Tests
 * Description: Where the suggestions list goes beside the cursor's line, and how tall it is, so it never covers the
 *              line being typed.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 27/11/2026
 */

import XCTest
@testable import GraphiteUI

final class CompletionPopupPlacementTests: XCTestCase {
    private let caretHeight: CGFloat = 22

    private func caret(atHeight y: CGFloat) -> CGRect { CGRect(x: 40, y: y, width: 2, height: caretHeight) }

    func testTheListGoesBelowTheLineWhenItFits() {
        let placement = CompletionPopupPlacement(caret: caret(atHeight: 100), paneSize: CGSize(width: 834, height: 1_000), itemCount: 20)
        XCTAssertEqual(placement.frame.minY, 128)
        XCTAssertEqual(placement.frame.height, CompletionPopup.maximumHeight)
    }

    func testAShortListIsAsTallAsItsRows() {
        let placement = CompletionPopupPlacement(caret: caret(atHeight: 100), paneSize: CGSize(width: 834, height: 1_000), itemCount: 2)
        XCTAssertEqual(placement.frame.height, 2 * 48 + 8)
    }

    func testTheListGoesAboveTheLineWhenOnlyThatFits() {
        let line = caret(atHeight: 600)
        let placement = CompletionPopupPlacement(caret: line, paneSize: CGSize(width: 834, height: 700), itemCount: 20)
        XCTAssertEqual(placement.frame.maxY, line.minY - 6)
        XCTAssertEqual(placement.frame.height, CompletionPopup.maximumHeight)
    }

    /// Found by real typing on an iPhone simulator: with the keyboard up, the list fitted on neither side and was pinned
    /// to the top of the pane, over the line being typed.
    func testWhenItFitsNeitherSideItTakesTheRoomierOneShorterAndLeavesTheLineVisible() {
        let line = caret(atHeight: 180)
        let pane = CGSize(width: 402, height: 330)
        let placement = CompletionPopupPlacement(caret: line, paneSize: pane, itemCount: 20)
        XCTAssertFalse(placement.frame.intersects(line), "The line being typed shows: \(placement.frame) against \(line)")
        XCTAssertLessThan(placement.frame.height, CompletionPopup.maximumHeight)
        XCTAssertGreaterThanOrEqual(placement.frame.minY, 8)
        XCTAssertEqual(placement.frame.maxY, line.minY - 6, "Above, where there is more room.")
        let lowLine = caret(atHeight: 60)
        let below = CompletionPopupPlacement(caret: lowLine, paneSize: pane, itemCount: 20)
        XCTAssertEqual(below.frame.minY, lowLine.maxY + 6, "Below, where there is more room.")
        XCTAssertLessThanOrEqual(below.frame.maxY, pane.height - 8)
    }

    func testTheListStaysInsideThePanesWidth() {
        let placement = CompletionPopupPlacement(caret: CGRect(x: 380, y: 50, width: 2, height: 22), paneSize: CGSize(width: 402, height: 800), itemCount: 5)
        XCTAssertLessThanOrEqual(placement.frame.maxX, 402)
        XCTAssertGreaterThanOrEqual(placement.frame.minX, 8)
    }
}
