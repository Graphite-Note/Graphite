/**
 * File: InkLassoSelectionThresholdsTests.swift
 * --------------------------------------------
 * Layer: Tests
 * Description: The rules behind Graphite's lasso: the loop closed from its last point to its first, a
 *              partly circled stroke or picture taken, a grazed one not, and how small a loop is a slip.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 04/11/2026
 */
import XCTest
import CoreGraphics
@testable import GraphiteUI

/// The numbers behind Graphite's lasso: how much of a stroke or picture must lie inside the
/// closed loop, how small a loop is a slip, and how far a tap reaches. The UIKit selection
/// controller applies them to PencilKit's strokes (`InkSelectionControllerTests`, and the
/// hosted `LassoClosingHostedTests` through the lasso's own recognizer).
final class InkLassoSelectionThresholdsTests: XCTestCase {
    private let square = [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0), CGPoint(x: 100, y: 100), CGPoint(x: 0, y: 100)]

    /// Points along a polyline as the controller tests a stroke: evenly spaced, by the lasso's
    /// spacing for a path that long.
    private func strokeSamples(along polyline: [CGPoint]) -> [CGPoint] {
        let spacing = InkLasso.strokeSampleSpacing(forPathLength: InkLasso.length(of: polyline))
        var samples = polyline.isEmpty ? [] : [polyline[0]]
        var distanceToNextSample = spacing
        for (start, end) in zip(polyline, polyline.dropFirst()) {
            let segmentLength = hypot(end.x - start.x, end.y - start.y)
            var travelled: CGFloat = 0
            while segmentLength - travelled >= distanceToNextSample {
                travelled += distanceToNextSample
                let fraction = travelled / segmentLength
                samples.append(CGPoint(x: start.x + (end.x - start.x) * fraction, y: start.y + (end.y - start.y) * fraction))
                distanceToNextSample = spacing
            }
            distanceToNextSample -= segmentLength - travelled
        }
        return samples
    }

    private func line(from start: CGPoint, to end: CGPoint) -> [CGPoint] { [start, end] }

    /// An arc of a circle drawn by hand from one angle to another, in degrees clockwise on
    /// screen from the positive x axis, not returning to where it began.
    private func arc(center: CGPoint, radius: CGFloat, fromDegrees startDegrees: CGFloat, toDegrees endDegrees: CGFloat) -> [CGPoint] {
        stride(from: startDegrees, through: endDegrees, by: 5).map { degrees in
            let radians = degrees * .pi / 180
            return CGPoint(x: center.x + radius * cos(radians), y: center.y + radius * sin(radians))
        }
    }

    func testTheThresholdsAreAThirdOfAStrokeThirtyPercentOfAPictureAndTheSlipAndTapSizes() {
        XCTAssertEqual(InkLasso.minimumEnclosedStrokeFraction, 0.35)
        XCTAssertEqual(InkLasso.minimumEnclosedPictureFraction, 0.3)
        XCTAssertEqual(InkLasso.minimumLoopLength, 24)
        XCTAssertEqual(InkLasso.minimumLoopArea, 64)
        XCTAssertEqual(InkLasso.tapReach, 14)
        XCTAssertEqual(InkLasso.pictureSamplesPerSide, 6)
        XCTAssertEqual(InkLasso.strokeSampleSpacing, 4)
        XCTAssertEqual(InkLasso.minimumStrokeSampleCount, 16)
    }

    func testTheLoopIsClosedFromItsLastPointBackToItsFirst() {
        let openLoop = [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0), CGPoint(x: 100, y: 100)]
        XCTAssertEqual(InkLasso.closed(openLoop), openLoop + [CGPoint(x: 0, y: 0)])
        XCTAssertEqual(InkLasso.closed(InkLasso.closed(openLoop)), openLoop + [CGPoint(x: 0, y: 0)], "A closed loop stays as it is.")
        XCTAssertEqual(InkLasso.closed([]), [])
        XCTAssertEqual(InkLasso.closed([CGPoint(x: 3, y: 4)]), [CGPoint(x: 3, y: 4)])
    }

    func testACircleAroundHalfAWordTakesTheStrokesItCutsThroughAndNotTheNextWord() {
        // A word written as a wavy stroke from x 0 to 200, a tall letter at x 40 and a crossbar from 60 to 140;
        // the next word from 260 to 360.
        let wordBody = stride(from: CGFloat(0), through: 200, by: 5).map { x in CGPoint(x: x, y: 50 + 8 * sin(x / 10)) }
        let tallLetter = line(from: CGPoint(x: 40, y: 15), to: CGPoint(x: 40, y: 60))
        let crossbar = line(from: CGPoint(x: 60, y: 30), to: CGPoint(x: 140, y: 30))
        let nextWord = line(from: CGPoint(x: 260, y: 50), to: CGPoint(x: 360, y: 50))
        // A circle around the word's left half, x from about -10 to 110, the hand lifting before it closes.
        let openCircle = arc(center: CGPoint(x: 50, y: 40), radius: 60, fromDegrees: 200, toDegrees: 510)
        XCTAssertNotEqual(openCircle.first, openCircle.last)
        let loop = InkLasso.closed(openCircle)
        for (name, stroke) in [("the word's body", wordBody), ("the tall letter", tallLetter), ("the crossbar", crossbar)] {
            let samples = strokeSamples(along: stroke)
            XCTAssertTrue(InkLasso.takesStroke(sampledAt: samples, inLoop: loop),
                          "\(name): \(InkLasso.enclosedFraction(of: samples, inLoop: loop)) inside is taken.")
        }
        XCTAssertLessThan(InkLasso.enclosedFraction(of: strokeSamples(along: wordBody), inLoop: loop), 0.6, "Under the old rule of 60 % the body was left.")
        XCTAssertFalse(InkLasso.takesStroke(sampledAt: strokeSamples(along: nextWord), inLoop: loop))
    }

    func testALoopTouchingAStrokesEndByAHairDoesNotTakeIt() {
        // The square reaches 3 points past x = 100, where a stroke 100 long begins, and where one only 12 long begins.
        let loop = [CGPoint(x: 0, y: 0), CGPoint(x: 103, y: 0), CGPoint(x: 103, y: 100), CGPoint(x: 0, y: 100)]
        let longStroke = strokeSamples(along: line(from: CGPoint(x: 100, y: 50), to: CGPoint(x: 200, y: 50)))
        let shortStroke = strokeSamples(along: line(from: CGPoint(x: 100, y: 60), to: CGPoint(x: 112, y: 60)))
        XCTAssertGreaterThanOrEqual(shortStroke.count, InkLasso.minimumStrokeSampleCount, "A short stroke is measured as finely as a long one.")
        for samples in [longStroke, shortStroke] {
            XCTAssertGreaterThan(InkLasso.enclosedFraction(of: samples, inLoop: loop), 0, "The loop does touch it.")
            XCTAssertFalse(InkLasso.takesStroke(sampledAt: samples, inLoop: loop), "\(InkLasso.enclosedFraction(of: samples, inLoop: loop)) inside is a graze.")
        }
    }

    func testAnUnclosedCShapedLoopAroundAStrokeTakesItOnceClosed() {
        // A C open to the right: the hand stops a quarter turn short of where it began.
        let cShape = arc(center: CGPoint(x: 50, y: 50), radius: 40, fromDegrees: 45, toDegrees: 315)
        let stroke = strokeSamples(along: line(from: CGPoint(x: 35, y: 50), to: CGPoint(x: 70, y: 50)))
        let closedLoop = InkLasso.closed(cShape)
        XCTAssertEqual(closedLoop.last, cShape.first, "The loop goes back to where the hand came down.")
        XCTAssertTrue(InkLasso.takesStroke(sampledAt: stroke, inLoop: closedLoop))
        XCTAssertEqual(InkLasso.enclosedFraction(of: stroke, inLoop: closedLoop), 1, "Even its right end, in the C's opening, is inside the closed loop.")
    }

    func testAShareOfAStrokeFromAThirdIsTakenAndUnderItIsNot() {
        // 26 samples along x from 0 to 100; the square covers x from 0 to 100.
        func stroke(startingAt startX: CGFloat) -> [CGPoint] { strokeSamples(along: line(from: CGPoint(x: startX, y: 50), to: CGPoint(x: startX + 100, y: 50))) }
        XCTAssertTrue(InkLasso.takesStroke(sampledAt: stroke(startingAt: 60), inLoop: square), "40 % inside")
        XCTAssertFalse(InkLasso.takesStroke(sampledAt: stroke(startingAt: 70), inLoop: square), "30 % inside")
    }

    func testAPictureHalfInsideIsTakenAndOneWithACornerInsideIsNot() {
        XCTAssertTrue(InkLasso.takesPicture(framed: CGRect(x: 50, y: 20, width: 100, height: 60), turnedBy: 0, inLoop: square), "Half inside")
        XCTAssertTrue(InkLasso.takesPicture(framed: CGRect(x: 70, y: 20, width: 100, height: 60), turnedBy: 0, inLoop: square), "A third inside")
        let cornerInside = CGRect(x: 80, y: 80, width: 100, height: 60)
        XCTAssertGreaterThan(InkLasso.enclosedFraction(of: InkLasso.samplePoints(ofRectangle: cornerInside, turnedBy: 0), inLoop: square), 0)
        XCTAssertFalse(InkLasso.takesPicture(framed: cornerInside, turnedBy: 0, inLoop: square), "A corner inside")
        // Turned a quarter, a long thin picture through the square's middle is mostly inside.
        let longAndThin = CGRect(x: -20, y: 40, width: 140, height: 20)
        let narrowBand = [CGPoint(x: 35, y: -30), CGPoint(x: 65, y: -30), CGPoint(x: 65, y: 130), CGPoint(x: 35, y: 130)]
        XCTAssertTrue(InkLasso.takesPicture(framed: longAndThin, turnedBy: .pi / 2, inLoop: narrowBand))
    }

    func testALoopAcrossAPicturesMiddleTakesItAndASmallLoopDrawnOnItDoesNot() {
        let picture = CGRect(x: 0, y: 0, width: 120, height: 60)
        // A band across the middle column holds one column of six: under 30 %, but the middle, and it reaches past the edge.
        let band = [CGPoint(x: 45, y: -10), CGPoint(x: 65, y: -10), CGPoint(x: 65, y: 70), CGPoint(x: 45, y: 70)]
        XCTAssertLessThan(InkLasso.enclosedFraction(of: InkLasso.samplePoints(ofRectangle: picture, turnedBy: 0), inLoop: band), InkLasso.minimumEnclosedPictureFraction)
        XCTAssertTrue(InkLasso.takesPicture(framed: picture, turnedBy: 0, inLoop: band))
        // A small loop around writing on the picture's middle, wholly on the picture, leaves the picture.
        let onThePicture = [CGPoint(x: 50, y: 20), CGPoint(x: 70, y: 20), CGPoint(x: 70, y: 40), CGPoint(x: 50, y: 40)]
        XCTAssertFalse(InkLasso.takesPicture(framed: picture, turnedBy: 0, inLoop: onThePicture))
    }

    func testAShortScribbleOrALoopUnderAnEightPointSquareIsASlip() {
        XCTAssertFalse(InkLasso.isFreehandLoopLargeEnough([CGPoint(x: 0, y: 0), CGPoint(x: 200, y: 0)], screenPointsPerLoopPoint: 1), "Two points enclose nothing.")
        let scribble = [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 1), CGPoint(x: 0, y: 2), CGPoint(x: 100, y: 3)]
        XCTAssertGreaterThan(InkLasso.length(of: scribble), InkLasso.minimumLoopLength)
        XCTAssertFalse(InkLasso.isFreehandLoopLargeEnough(scribble, screenPointsPerLoopPoint: 1), "Back and forth along a line, it encloses almost nothing.")
        func squareLoop(side: CGFloat) -> [CGPoint] { [CGPoint(x: 0, y: 0), CGPoint(x: side, y: 0), CGPoint(x: side, y: side), CGPoint(x: 0, y: side)] }
        XCTAssertTrue(InkLasso.isFreehandLoopLargeEnough(squareLoop(side: 8), screenPointsPerLoopPoint: 1), "64 square points is a loop.")
        XCTAssertFalse(InkLasso.isFreehandLoopLargeEnough(squareLoop(side: 7), screenPointsPerLoopPoint: 1), "49 is a slip.")
        XCTAssertTrue(InkLasso.isFreehandLoopLargeEnough(squareLoop(side: 4), screenPointsPerLoopPoint: 2), "Measured on screen: zoomed in twice, 4 points of the page are 8 on screen.")
        XCTAssertEqual(InkLasso.enclosedArea(of: squareLoop(side: 10)), 100)
        XCTAssertTrue(InkLasso.isRectangleLoopLargeEnough(InkLasso.rectangleLoop(from: .zero, to: CGPoint(x: 100, y: 14)), screenPointsPerLoopPoint: 1))
        XCTAssertFalse(InkLasso.isRectangleLoopLargeEnough(InkLasso.rectangleLoop(from: .zero, to: CGPoint(x: 100, y: 13)), screenPointsPerLoopPoint: 1))
    }

    func testAStrokeIsTestedEveryFourPointsOrAtSixteenPointsWhenShort() {
        XCTAssertEqual(InkLasso.strokeSampleSpacing(forPathLength: 400), 4)
        XCTAssertEqual(InkLasso.strokeSampleSpacing(forPathLength: 20), 1.25)
        XCTAssertEqual(InkLasso.strokeSampleSpacing(forPathLength: 0), 4, "A dot is its own point.")
    }
}
