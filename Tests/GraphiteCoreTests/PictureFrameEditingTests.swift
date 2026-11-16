/**
 * File: PictureFrameEditingTests.swift
 * ------------------------------------
 * Layer: Tests
 * Description: Resizing a picture's frame by a corner with plain values: the opposite corner stays, the proportions
 *              are kept, the narrowest side is kept to, also for a picture turned by any angle.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 16/11/2026
 */

import XCTest
import CoreGraphics
@testable import GraphiteCore

final class PictureFrameEditingTests: XCTestCase {
    private let frame = CGRect(x: 100, y: 200, width: 100, height: 50)

    private func assertRectangle(_ actual: CGRect, _ expected: CGRect, file: StaticString = #filePath, line: UInt = #line) {
        for (got, wanted) in [(actual.minX, expected.minX), (actual.minY, expected.minY), (actual.width, expected.width), (actual.height, expected.height)] {
            XCTAssertEqual(got, wanted, accuracy: 0.001, "\(actual) is not \(expected)", file: file, line: line)
        }
    }

    private func assertPoint(_ actual: CGPoint, _ expected: CGPoint, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual.x, expected.x, accuracy: 0.001, "\(actual) is not \(expected)", file: file, line: line)
        XCTAssertEqual(actual.y, expected.y, accuracy: 0.001, "\(actual) is not \(expected)", file: file, line: line)
    }

    func testDraggingACornerKeepsTheOppositeCornerAndTheProportions() {
        let larger = PictureFrameEditing.resized(frame, turnedBy: 0, draggingCorner: .maximumXMaximumY, to: CGPoint(x: 300, y: 300), narrowestSide: 12)
        assertRectangle(larger, CGRect(x: 100, y: 200, width: 200, height: 100))
        // The larger of the two stretches wins, so the corner is never inside the picture.
        let wider = PictureFrameEditing.resized(frame, turnedBy: 0, draggingCorner: .maximumXMaximumY, to: CGPoint(x: 400, y: 260), narrowestSide: 12)
        assertRectangle(wider, CGRect(x: 100, y: 200, width: 300, height: 150))
        let fromTheOtherCorner = PictureFrameEditing.resized(frame, turnedBy: 0, draggingCorner: .minimumXMinimumY, to: CGPoint(x: 150, y: 225), narrowestSide: 12)
        assertRectangle(fromTheOtherCorner, CGRect(x: 150, y: 225, width: 50, height: 25))
    }

    func testAPictureIsNeverMadeNarrowerThanTheNarrowestSide() {
        let smallest = PictureFrameEditing.resized(frame, turnedBy: 0, draggingCorner: .maximumXMinimumY, to: CGPoint(x: 0, y: 900), narrowestSide: 12)
        assertRectangle(smallest, CGRect(x: 100, y: 238, width: 24, height: 12))
    }

    func testATurnedPictureKeepsItsOppositeCornerWhereItIsShown() {
        for radians in [Double.pi / 2, Double.pi / 6, -2.4, Double.pi] {
            for corner in PictureFrameCorner.allCases {
                let anchor = corner.opposite.point(of: frame, turnedBy: radians)
                let draggedTo = CGPoint(x: anchor.x + 170, y: anchor.y - 40)
                let resized = PictureFrameEditing.resized(frame, turnedBy: radians, draggingCorner: corner, to: draggedTo, narrowestSide: 12)
                assertPoint(corner.opposite.point(of: resized, turnedBy: radians), anchor)
                XCTAssertEqual(resized.width / resized.height, 2, accuracy: 0.0001)
                XCTAssertGreaterThanOrEqual(resized.height, 12 - 0.0001)
            }
        }
    }

    func testDraggingACornerToWhereItIsLeavesTheFrame() {
        for radians in [0, Double.pi / 3, -1.1] {
            for corner in PictureFrameCorner.allCases {
                let resized = PictureFrameEditing.resized(frame, turnedBy: radians, draggingCorner: corner,
                                                          to: corner.point(of: frame, turnedBy: radians), narrowestSide: 12)
                assertRectangle(resized, frame)
            }
        }
    }

    func testAQuarterTurnedPictureGrowsAlongItsOwnEdges() {
        // Turned a quarter counterclockwise about (150, 225), the frame covers x 125...175, y 175...275 on the page.
        let resized = PictureFrameEditing.resized(frame, turnedBy: .pi / 2, draggingCorner: .maximumXMaximumY, to: CGPoint(x: 75, y: 375), narrowestSide: 12)
        XCTAssertEqual(resized.width, 200, accuracy: 0.001)
        XCTAssertEqual(resized.height, 100, accuracy: 0.001)
        assertPoint(PictureFrameCorner.minimumXMinimumY.point(of: resized, turnedBy: .pi / 2), CGPoint(x: 175, y: 175))
    }

    func testMovingOffsetsTheFrame() {
        assertRectangle(PictureFrameEditing.moved(frame, by: CGVector(dx: -10, dy: 4)), CGRect(x: 90, y: 204, width: 100, height: 50))
    }
}
