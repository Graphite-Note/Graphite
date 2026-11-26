/**
 * File: CalloutColumnArrangementTests.swift
 * -----------------------------------------
 * Layer: Tests
 * Description: The blocks of a `[!multi-column]` callout share the width as Modular CSS Layout's flex rules share it,
 *              wrap when a column would be narrower than 200 points, and stack one per row on a phone.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

import XCTest
@testable import GraphiteCore

final class CalloutColumnArrangementTests: XCTestCase {
    private func widths(_ arrangement: CalloutColumnArrangement) -> [[CGFloat]] {
        arrangement.rows.map { row in row.map(\.width) }
    }

    func testTwoColumnsShareAWideNoteEqually() {
        let arrangement = CalloutColumnArrangement(weights: [1, 1], availableWidth: 716)
        XCTAssertEqual(widths(arrangement), [[350, 350]], "716 points less one 16-point gap, halved.")
        XCTAssertFalse(arrangement.isStacked)
    }

    func testAWideBlockGrowsByItsWeight() {
        let arrangement = CalloutColumnArrangement(weights: [2, 1], availableWidth: 716)
        XCTAssertEqual(widths(arrangement), [[400, 300]], "300 points left over beyond the minimums: 200 to the wide-2 block, 100 to the other.")
    }

    func testColumnsWrapWhenTheyWouldBeNarrowerThanTheMinimum() {
        let arrangement = CalloutColumnArrangement(weights: [1, 1, 1], availableWidth: 500)
        XCTAssertEqual(arrangement.rows.map { row in row.map(\.blockIndex) }, [[0, 1], [2]])
        XCTAssertEqual(widths(arrangement), [[242, 242], [500]], "The third block takes a row of its own, the whole width.")
    }

    func testAPhoneWidthStacksEveryBlock() {
        let arrangement = CalloutColumnArrangement(weights: [1, 1, 1], availableWidth: 361)
        XCTAssertTrue(arrangement.isStacked)
        XCTAssertEqual(widths(arrangement), [[361], [361], [361]])
    }

    func testANoteNarrowerThanTheMinimumGivesItsWholeWidth() {
        XCTAssertEqual(widths(CalloutColumnArrangement(weights: [1], availableWidth: 150)), [[150]])
        XCTAssertEqual(CalloutColumnArrangement(weights: [], availableWidth: 700).rows, [])
    }

    func testTheLayoutComesFromTheTypeAsTheSnippetMatchesIt() {
        XCTAssertEqual(CalloutLayout(type: "multi-column"), .columns)
        XCTAssertEqual(CalloutLayout(type: "blank"), .contentOnly)
        XCTAssertEqual(CalloutLayout(type: "blank-container"), .contentOnly)
        XCTAssertEqual(CalloutLayout(type: "note"), .box)
        XCTAssertEqual(CalloutLayout(type: "multi-columns"), .box, "Only the snippet's own name.")
    }
}
