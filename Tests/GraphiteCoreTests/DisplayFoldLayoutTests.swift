/**
 * File: DisplayFoldLayoutTests.swift
 * ----------------------------------
 * Layer: Tests
 * Description: Placing content around the fold of a partly folded display: the region left beside a fold, the
 *              divider held on it (down a split side by side, across one above the other), and even columns over it.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 21/11/2026
 */

import XCTest
import CoreGraphics
@testable import GraphiteCore

/// Placing content around the fold of a partly folded display (iPhone Duo's inner display).
final class DisplayFoldLayoutTests: XCTestCase {
    /// The inner display held like a book: 951 by 669 points, folded down the middle.
    private let bookContainer = CGRect(x: 0, y: 0, width: 951, height: 669)
    private let bookFold = CGRect(x: 455, y: 0, width: 40, height: 669)

    func testWithoutAFoldTheWholeContainerIsUsed() {
        XCTAssertEqual(DisplayFoldLayout.largestUndividedRegion(of: bookContainer, divisions: []), bookContainer)
    }

    func testAFoldDownTheMiddleLeavesTheLargerSide() {
        let offCentreFold = CGRect(x: 300, y: 0, width: 40, height: 669)
        XCTAssertEqual(DisplayFoldLayout.largestUndividedRegion(of: bookContainer, divisions: [offCentreFold]),
                       CGRect(x: 340, y: 0, width: 611, height: 669))
    }

    func testEqualSidesGiveTheLeadingOne() {
        let container = CGRect(x: 0, y: 0, width: 940, height: 600)
        let centredFold = CGRect(x: 450, y: 0, width: 40, height: 600)
        XCTAssertEqual(DisplayFoldLayout.largestUndividedRegion(of: container, divisions: [centredFold]),
                       CGRect(x: 0, y: 0, width: 450, height: 600))
    }

    func testAFoldAcrossTheDisplayLeavesTheTopOrBottom() {
        let portrait = CGRect(x: 0, y: 0, width: 669, height: 951)
        let foldAcross = CGRect(x: 0, y: 500, width: 669, height: 40)
        XCTAssertEqual(DisplayFoldLayout.largestUndividedRegion(of: portrait, divisions: [foldAcross]),
                       CGRect(x: 0, y: 0, width: 669, height: 500))
    }

    func testAFoldOutsideTheContainerChangesNothing() {
        let leadingHalf = CGRect(x: 0, y: 0, width: 400, height: 669)
        XCTAssertEqual(DisplayFoldLayout.largestUndividedRegion(of: leadingHalf, divisions: [bookFold]), leadingHalf)
    }

    func testTheDividerIsCentredOnTheFold() throws {
        let fraction = try XCTUnwrap(DisplayFoldLayout.splitFraction(dividingAt: [bookFold], splitLengthPoints: 951, dividerThicknessPoints: 11,
                                                                     direction: .sideBySide, allowedRange: 0.25...0.75))
        let dividerCentre = (951 - 11) * fraction + 11 / 2
        XCTAssertEqual(dividerCentre, Double(bookFold.midX), accuracy: 0.0001)
    }

    func testAFoldTooCloseToAnEdgeLeavesTheSplitAsItIs() {
        // With the sidebar shown, the fold falls near the start of the documents area.
        let foldNearTheStart = CGRect(x: 100, y: 0, width: 40, height: 669)
        XCTAssertNil(DisplayFoldLayout.splitFraction(dividingAt: [foldNearTheStart], splitLengthPoints: 631, dividerThicknessPoints: 11,
                                                     direction: .sideBySide, allowedRange: 0.25...0.75))
    }

    func testAFoldAcrossTheDisplayDoesNotMoveTheDivider() {
        let foldAcross = CGRect(x: 0, y: 300, width: 951, height: 40)
        XCTAssertNil(DisplayFoldLayout.splitFraction(dividingAt: [foldAcross], splitLengthPoints: 951, dividerThicknessPoints: 11,
                                                     direction: .sideBySide, allowedRange: 0.25...0.75))
    }

    func testASplitAboveAndBelowPutsItsDividerOnAFoldAcross() throws {
        let portrait = CGRect(x: 0, y: 0, width: 669, height: 951)
        let foldAcross = CGRect(x: 0, y: 455, width: portrait.width, height: 40)
        let fraction = try XCTUnwrap(DisplayFoldLayout.splitFraction(dividingAt: [foldAcross], splitLengthPoints: portrait.height,
                                                                     dividerThicknessPoints: 11, direction: .aboveAndBelow,
                                                                     allowedRange: 0.25...0.75))
        let dividerCentre = (portrait.height - 11) * fraction + 11 / 2
        XCTAssertEqual(dividerCentre, Double(foldAcross.midY), accuracy: 0.0001)
        XCTAssertNil(DisplayFoldLayout.splitFraction(dividingAt: [bookFold], splitLengthPoints: portrait.height, dividerThicknessPoints: 11,
                                                     direction: .aboveAndBelow, allowedRange: 0.25...0.75),
                     "A fold down the middle does not separate sides one above the other.")
    }

    func testColumnsOverAFoldAreEven() {
        // Five columns of 140 points 20 apart fit in 800 points; over a fold, four.
        XCTAssertEqual(DisplayFoldLayout.columnCount(availableWidthPoints: 800, minimumColumnWidthPoints: 140, spacingPoints: 20,
                                                     isDividedByFold: false), 5)
        XCTAssertEqual(DisplayFoldLayout.columnCount(availableWidthPoints: 800, minimumColumnWidthPoints: 140, spacingPoints: 20,
                                                     isDividedByFold: true), 4)
        XCTAssertEqual(DisplayFoldLayout.columnCount(availableWidthPoints: 100, minimumColumnWidthPoints: 140, spacingPoints: 20,
                                                     isDividedByFold: true), 1)
    }

    func testOnlyAFoldDownTheMiddleWithinTheWidthCounts() {
        XCTAssertTrue(DisplayFoldLayout.hasFoldDownTheMiddle([bookFold], widthPoints: 951))
        XCTAssertFalse(DisplayFoldLayout.hasFoldDownTheMiddle([bookFold], widthPoints: 400))
        XCTAssertFalse(DisplayFoldLayout.hasFoldDownTheMiddle([CGRect(x: 0, y: 300, width: 951, height: 40)], widthPoints: 951))
    }
}
