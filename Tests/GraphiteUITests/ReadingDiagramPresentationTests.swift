/**
 * File: ReadingDiagramPresentationTests.swift
 * -------------------------------------------
 * Layer: Tests
 * Description: Checks when a diagram is fitted to the reading column and when it scrolls sideways instead.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 01/11/2026
 */

import XCTest
@testable import GraphiteUI

/// HUNT-223: a wide diagram was shrunk to the column's width however wide it was, so its text became unreadable on an iPhone
/// and an iPad in portrait, and there was no way to scroll or zoom.
final class ReadingDiagramPresentationTests: XCTestCase {
    func testADiagramThatFitsTheColumnIsShownAtItsOwnSize() {
        XCTAssertEqual(ReadingDiagramPresentation.presentation(naturalWidth: 400, scaleAtNaturalWidth: 1, columnWidth: 700), .fitted(scale: 1))
    }

    func testADiagramALittleWiderThanTheColumnIsScaledDownToIt() throws {
        guard case .fitted(let scale) = ReadingDiagramPresentation.presentation(naturalWidth: 800, scaleAtNaturalWidth: 1, columnWidth: 600) else {
            return XCTFail("Fitted")
        }
        XCTAssertEqual(scale, 0.75, accuracy: 0.0001)
    }

    func testADiagramThatWouldShrinkBelowTheReadableScaleKeepsThatScaleAndScrolls() {
        XCTAssertEqual(ReadingDiagramPresentation.presentation(naturalWidth: 1_600, scaleAtNaturalWidth: 1, columnWidth: 390),
                       .scrolling(scale: ReadingDiagramPresentation.smallestReadableScale))
        // Exactly at the smallest scale it is still fitted.
        guard case .fitted = ReadingDiagramPresentation.presentation(naturalWidth: 1_000, scaleAtNaturalWidth: 1, columnWidth: 600) else {
            return XCTFail("At the smallest scale the diagram is fitted")
        }
    }

    func testTheReadableScaleFollowsTheTextSizeTheDiagramIsShownAt() {
        // The text is 20 % larger now than when the diagram was laid out: it is shown 20 % larger, and no smaller than 60 % of that.
        XCTAssertEqual(ReadingDiagramPresentation.presentation(naturalWidth: 1_200, scaleAtNaturalWidth: 1.2, columnWidth: 300),
                       .scrolling(scale: 1.2 * ReadingDiagramPresentation.smallestReadableScale))
    }

    func testAColumnNotMeasuredYetShowsTheDiagramFitted() {
        XCTAssertEqual(ReadingDiagramPresentation.presentation(naturalWidth: 1_600, scaleAtNaturalWidth: 1, columnWidth: 0), .fitted(scale: 1))
    }
}
