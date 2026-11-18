/**
 * File: PictureTwoFingerTransformTests.swift
 * ------------------------------------------
 * Layer: Tests
 * Description: A picture turned, pinched and moved by two fingers, with plain values: the point under the fingers
 *              stays under them, the size keeps its proportion and limits, and the angle snaps near quarter turns.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 17/11/2026
 */

import XCTest
import CoreGraphics
@testable import GraphiteCore

final class PictureTwoFingerTransformTests: XCTestCase {
    private let start = PictureTwoFingerTransform(frame: CGRect(x: 100, y: 100, width: 200, height: 100), rotationRadians: 0)

    private func transformed(_ start: PictureTwoFingerTransform? = nil, from fingersAtStart: CGPoint = CGPoint(x: 200, y: 150),
                             to fingers: CGPoint = CGPoint(x: 200, y: 150), scale: CGFloat = 1, turn: Double = 0,
                             limits: CGRect = .infinite) -> PictureTwoFingerTransform {
        PictureTwoFingerTransform.transformed(start ?? self.start, fingersMiddleAtStart: fingersAtStart, fingersMiddle: fingers, scale: scale,
                                              turn: turn, minimumSideLength: 32, maximumSideLength: 1000, centerLimits: limits)
    }

    private func assertRectangle(_ actual: CGRect, _ expected: CGRect, file: StaticString = #filePath, line: UInt = #line) {
        for (actualValue, expectedValue) in [(actual.minX, expected.minX), (actual.minY, expected.minY), (actual.width, expected.width), (actual.height, expected.height)] {
            XCTAssertEqual(actualValue, expectedValue, accuracy: 0.001, "\(actual) is not \(expected)", file: file, line: line)
        }
    }

    func testFingersThatDoNotMoveLeaveThePictureWhereItIs() {
        XCTAssertEqual(transformed(), start)
    }

    func testFingersMovedTogetherMoveThePictureAsFar() {
        assertRectangle(transformed(to: CGPoint(x: 230, y: 110)).frame, CGRect(x: 130, y: 60, width: 200, height: 100))
    }

    func testAPinchAboutThePicturesMiddleResizesItInProportionThere() {
        assertRectangle(transformed(scale: 1.5).frame, CGRect(x: 50, y: 75, width: 300, height: 150))
    }

    func testAPinchAwayFromTheMiddleKeepsThePointUnderTheFingers() {
        // Fingers at the picture's left edge: the left edge stays, the picture grows to the right.
        let pinched = transformed(from: CGPoint(x: 100, y: 150), to: CGPoint(x: 100, y: 150), scale: 2)
        assertRectangle(pinched.frame, CGRect(x: 100, y: 50, width: 400, height: 200))
    }

    func testATwistTurnsThePictureAboutTheFingers() {
        // A quarter turn clockwise with the fingers at the left edge's middle: the middle swings below them.
        let twisted = transformed(from: CGPoint(x: 100, y: 150), to: CGPoint(x: 100, y: 150), turn: .pi / 2)
        XCTAssertEqual(twisted.rotationRadians, .pi / 2, accuracy: 0.000_001)
        XCTAssertEqual(twisted.frame.midX, 100, accuracy: 0.001)
        XCTAssertEqual(twisted.frame.midY, 250, accuracy: 0.001)
        XCTAssertEqual(twisted.frame.size, start.frame.size, "a turn keeps the unturned frame's size")
    }

    func testATwistCloseToAQuarterTurnIsHeldThere() {
        XCTAssertEqual(transformed(turn: .pi / 2 - 0.05).rotationRadians, .pi / 2, accuracy: 0.000_001)
        XCTAssertEqual(transformed(turn: 0.04).rotationRadians, 0)
        XCTAssertEqual(transformed(turn: 0.3).rotationRadians, 0.3, accuracy: 0.000_001)
        // A picture already turned is turned further from its own angle.
        let turned = PictureTwoFingerTransform(frame: start.frame, rotationRadians: 0.5)
        XCTAssertEqual(transformed(turned, turn: 0.2).rotationRadians, 0.7, accuracy: 0.000_001)
    }

    func testThePinchStopsAtTheSmallestAndLargestSides() {
        assertRectangle(transformed(scale: 0.01).frame, CGRect(x: 168, y: 134, width: 64, height: 32))
        assertRectangle(transformed(scale: 100).frame, CGRect(x: -300, y: -100, width: 1000, height: 500))
        // A picture already smaller than the smallest side is not made larger by a pinch inward.
        let tiny = PictureTwoFingerTransform(frame: CGRect(x: 0, y: 0, width: 20, height: 10), rotationRadians: 0)
        XCTAssertEqual(transformed(tiny, from: CGPoint(x: 10, y: 5), to: CGPoint(x: 10, y: 5), scale: 0.5).frame.size, tiny.frame.size)
    }

    func testThePicturesMiddleStaysInsideItsLimits() {
        let limits = CGRect(x: 0, y: 0, width: 400, height: 400)
        let moved = transformed(to: CGPoint(x: 900, y: -300), limits: limits)
        XCTAssertEqual(moved.frame.midX, 400)
        XCTAssertEqual(moved.frame.midY, 0)
    }

    func testANumberThatIsNotOneLeavesThePictureAsItWas() {
        XCTAssertEqual(transformed(scale: .nan), start)
        XCTAssertEqual(transformed(scale: 0), start)
        XCTAssertEqual(transformed(turn: .infinity), start)
    }
}
