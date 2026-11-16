/**
 * File: PDFShownPageGeometryTests.swift
 * -------------------------------------
 * Layer: Tests
 * Description: The point of a PDF page under a point of the view that shows it, with plain values: the page's size
 *              and crop box, its quarter turns, the zoom (the shown frame's size), and a flipped or upward view.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 16/11/2026
 */

import XCTest
import CoreGraphics
@testable import GraphiteCore

final class PDFShownPageGeometryTests: XCTestCase {
    private let cropBox = CGRect(x: 0, y: 0, width: 400, height: 600)

    private func assertPoint(_ actual: CGPoint, _ expected: CGPoint, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual.x, expected.x, accuracy: 0.001, "\(actual) is not \(expected)", file: file, line: line)
        XCTAssertEqual(actual.y, expected.y, accuracy: 0.001, "\(actual) is not \(expected)", file: file, line: line)
    }

    func testAnUprightPageAtTwiceItsSizeGivesThePointUnderTheDrop() {
        // Zoomed to 200 %, scrolled so the page starts at (100, 50) of a view whose y runs down.
        let page = PDFShownPage(cropBox: cropBox, rotationDegrees: 0, frameInView: CGRect(x: 100, y: 50, width: 800, height: 1200), viewIsFlipped: true)
        assertPoint(page.pagePoint(ofViewPoint: CGPoint(x: 500, y: 650)), CGPoint(x: 200, y: 300))
        assertPoint(page.pagePoint(ofViewPoint: CGPoint(x: 100, y: 50)), CGPoint(x: 0, y: 600))
        assertPoint(page.pagePoint(ofViewPoint: CGPoint(x: 300, y: 1250)), CGPoint(x: 100, y: 0))
    }

    func testAViewWhoseVerticalAxisRunsUpCountsFromTheFramesTop() {
        let page = PDFShownPage(cropBox: cropBox, rotationDegrees: 0, frameInView: CGRect(x: 0, y: 0, width: 200, height: 300), viewIsFlipped: false)
        assertPoint(page.pagePoint(ofViewPoint: CGPoint(x: 50, y: 300)), CGPoint(x: 100, y: 600))
        assertPoint(page.pagePoint(ofViewPoint: CGPoint(x: 50, y: 75)), CGPoint(x: 100, y: 150))
    }

    func testEachQuarterTurnMapsTheShownCornersToTheBoxsCorners() {
        // A page turned a quarter is shown as wide as its box is tall.
        let sideways = CGRect(x: 0, y: 0, width: 600, height: 400)
        let upright = CGRect(x: 0, y: 0, width: 400, height: 600)
        let cases: [(degrees: Int, frame: CGRect, topLeft: CGPoint, topRight: CGPoint, bottomLeft: CGPoint)] = [
            (0, upright, CGPoint(x: 0, y: 600), CGPoint(x: 400, y: 600), CGPoint(x: 0, y: 0)),
            (90, sideways, CGPoint(x: 0, y: 0), CGPoint(x: 0, y: 600), CGPoint(x: 400, y: 0)),
            (180, upright, CGPoint(x: 400, y: 0), CGPoint(x: 0, y: 0), CGPoint(x: 400, y: 600)),
            (270, sideways, CGPoint(x: 400, y: 600), CGPoint(x: 400, y: 0), CGPoint(x: 0, y: 600)),
            (-90, sideways, CGPoint(x: 400, y: 600), CGPoint(x: 400, y: 0), CGPoint(x: 0, y: 600)),
        ]
        for testCase in cases {
            let page = PDFShownPage(cropBox: cropBox, rotationDegrees: testCase.degrees, frameInView: testCase.frame, viewIsFlipped: true)
            assertPoint(page.pagePoint(ofViewPoint: CGPoint(x: testCase.frame.minX, y: testCase.frame.minY)), testCase.topLeft)
            assertPoint(page.pagePoint(ofViewPoint: CGPoint(x: testCase.frame.maxX, y: testCase.frame.minY)), testCase.topRight)
            assertPoint(page.pagePoint(ofViewPoint: CGPoint(x: testCase.frame.minX, y: testCase.frame.maxY)), testCase.bottomLeft)
            assertPoint(page.pagePoint(ofViewPoint: CGPoint(x: testCase.frame.midX, y: testCase.frame.midY)), CGPoint(x: 200, y: 300))
        }
    }

    func testACropBoxAwayFromTheOriginKeepsItsOwnCoordinates() {
        let box = CGRect(x: 36, y: 72, width: 400, height: 600)
        let page = PDFShownPage(cropBox: box, rotationDegrees: 90, frameInView: CGRect(x: 0, y: 0, width: 300, height: 200), viewIsFlipped: true)
        assertPoint(page.pagePoint(ofViewPoint: CGPoint(x: 0, y: 0)), CGPoint(x: 36, y: 72))
        assertPoint(page.pagePoint(ofViewPoint: CGPoint(x: 150, y: 50)), CGPoint(x: 136, y: 372))
    }

    func testADropBesideThePageLandsAtItsNearestEdge() {
        let page = PDFShownPage(cropBox: cropBox, rotationDegrees: 0, frameInView: CGRect(x: 100, y: 100, width: 400, height: 600), viewIsFlipped: true)
        assertPoint(page.pagePoint(ofViewPoint: CGPoint(x: 20, y: 400)), CGPoint(x: 0, y: 300))
        assertPoint(page.pagePoint(ofViewPoint: CGPoint(x: 300, y: 760)), CGPoint(x: 200, y: 0))
    }

    func testAPageWithNoShownSizeGivesItsMiddle() {
        let page = PDFShownPage(cropBox: cropBox, rotationDegrees: 0, frameInView: .zero, viewIsFlipped: true)
        assertPoint(page.pagePoint(ofViewPoint: CGPoint(x: 5, y: 5)), CGPoint(x: 200, y: 300))
    }

    func testAMoveAsShownIsTheSameMoveOnTheTurnedPage() {
        XCTAssertEqual(PDFShownPage.pageVector(rightward: 3, downward: 5, quarterTurnsClockwise: 0), CGVector(dx: 3, dy: -5))
        XCTAssertEqual(PDFShownPage.pageVector(rightward: 3, downward: 5, quarterTurnsClockwise: 1), CGVector(dx: 5, dy: 3))
        XCTAssertEqual(PDFShownPage.pageVector(rightward: 3, downward: 5, quarterTurnsClockwise: 2), CGVector(dx: -3, dy: 5))
        XCTAssertEqual(PDFShownPage.pageVector(rightward: 3, downward: 5, quarterTurnsClockwise: 3), CGVector(dx: -5, dy: -3))
        XCTAssertEqual(PDFShownPage.pageVector(rightward: 3, downward: 5, quarterTurnsClockwise: -1), CGVector(dx: -5, dy: -3))
    }

    /// The vector agrees with the point mapping: moving the view point moves the page point by it, at a zoom of 1.
    func testThePageVectorAgreesWithThePointMappingAtEveryTurn() {
        for degrees in [0, 90, 180, 270] {
            let isSideways = degrees % 180 != 0
            let frame = CGRect(x: 0, y: 0, width: isSideways ? 600 : 400, height: isSideways ? 400 : 600)
            let page = PDFShownPage(cropBox: cropBox, rotationDegrees: degrees, frameInView: frame, viewIsFlipped: true)
            let start = page.pagePoint(ofViewPoint: CGPoint(x: 100, y: 100))
            let end = page.pagePoint(ofViewPoint: CGPoint(x: 107, y: 111))
            let vector = PDFShownPage.pageVector(rightward: 7, downward: 11, quarterTurnsClockwise: page.quarterTurnsClockwise)
            assertPoint(CGPoint(x: start.x + vector.dx, y: start.y + vector.dy), end)
        }
    }
}
