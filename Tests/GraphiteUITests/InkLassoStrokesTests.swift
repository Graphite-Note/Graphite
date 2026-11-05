/**
 * File: InkLassoStrokesTests.swift
 * --------------------------------
 * Layer: Tests
 * Description: HUNT-007: the lasso tests a PencilKit stroke where it runs on the page, whatever zoom drew
 *              it, however its points and transform store it, and whatever zoom the loop is drawn at.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 05/11/2026
 */
import XCTest
import CoreGraphics
import PencilKit
@testable import GraphiteUI

/// HUNT-007: a stroke written while a PDF page is zoomed in, lassoed at another zoom. The lasso's
/// selection turns the loop's touches into the drawing's coordinates (the page's points at any
/// zoom and any part of the page the canvas covers) and tests each stroke with
/// `InkLasso.takesStroke(_:inLoop:)`; these tests give it strokes stored every way a canvas at
/// zoom 1, 3.3 and 8 could store them: points in the page's points, points at the canvas's scale
/// under a transform that shrinks them back, points of the part of the page an 8 times canvas
/// covers under a transform that moves them there, and the same read back from a saved drawing.
/// The canvas's own strokes at those zooms, and loops through the lasso's recognizer, are
/// `LassoAtZoomHostedTests` on the iPad.
final class InkLassoStrokesTests: XCTestCase {
    private let fourA = CGSize(width: 595, height: 842)
    private let drawnZooms: [CGFloat] = [1, 3.3, 8]
    private let loopZooms: [CGFloat] = [0.91, 1, 3.3, 8]

    /// A written word in the page's points: a wave 60 points long and 16 high, its middle at
    /// (300, 400), as a hand writes it.
    private var writtenWord: [CGPoint] {
        stride(from: CGFloat(0), through: 60, by: 1.5).map { travelled in
            CGPoint(x: 270 + travelled, y: 400 + 8 * sin(travelled / 5))
        }
    }

    /// The part of an A4 page a canvas covers at zoom 8 on a 2x screen while the word is in the
    /// middle of the screen (`PDFCanvasShownRegion`), so its origin is where a canvas scrolled
    /// to that part puts it.
    private var regionAtZoomEight: CGRect {
        let visibleSize = CGSize(width: 834 / 8, height: 1194 / 8)
        let visible = CGRect(x: 300 - visibleSize.width / 2, y: 400 - visibleSize.height / 2, width: visibleSize.width, height: visibleSize.height)
        return PDFCanvasShownRegion.region(pageSize: fourA, visibleRegion: visible, currentRegion: nil, scale: 8, screenScale: 2,
                                           pixelBudget: PDFCanvasShownRegion.maximumCanvasPixelCount)
    }

    /// The transforms a stroke drawn at a zoom may be stored under, each carrying its stored
    /// points to the page: none; the canvas's scale undone; the covered part's corner; both.
    private func storedTransforms(drawnAtZoom zoom: CGFloat) -> [(name: String, transform: CGAffineTransform)] {
        let origin = regionAtZoomEight.origin
        return [
            ("in the page's points", .identity),
            ("at the canvas's scale \(zoom)", CGAffineTransform(scaleX: 1 / zoom, y: 1 / zoom)),
            ("in the covered part from \(origin)", CGAffineTransform(translationX: origin.x, y: origin.y)),
            ("at the canvas's scale \(zoom) in the covered part", CGAffineTransform(scaleX: 1 / zoom, y: 1 / zoom)
                .concatenating(CGAffineTransform(translationX: origin.x, y: origin.y))),
        ]
    }

    /// A pen stroke through points of the page, `width` wide on the page, stored under a
    /// transform: its points and sizes are those the transform carries to the page's.
    private func stroke(through pagePoints: [CGPoint], width: CGFloat = 2.8, storedUnder transform: CGAffineTransform) -> PKStroke {
        let toStored = transform.inverted()
        let storedWidth = width * InkLasso.enlargement(of: toStored)
        let points = pagePoints.enumerated().map { pointIndex, pagePoint in
            PKStrokePoint(location: pagePoint.applying(toStored), timeOffset: Double(pointIndex) / 120, size: CGSize(width: storedWidth, height: storedWidth),
                          opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }
        return PKStroke(ink: PKInk(.pen, color: .black), path: PKStrokePath(controlPoints: points, creationDate: Date()), transform: transform, mask: nil)
    }

    /// The stroke as a saved drawing gives it back.
    private func readBack(_ stroke: PKStroke) throws -> PKStroke {
        try XCTUnwrap(PKDrawing(data: PKDrawing(strokes: [stroke]).dataRepresentation()).strokes.first)
    }

    /// A loop drawn by hand at a zoom, in the drawing's coordinates as the lasso takes it: a
    /// circle `clearance` screen points clear of `area`, with a point every 6 screen points.
    private func loop(around area: CGRect, clearance: CGFloat = 12, drawnAtZoom zoom: CGFloat) -> [CGPoint] {
        let radius = hypot(area.width, area.height) / 2 + clearance / zoom
        let pointCount = max(Int((2 * .pi * radius * zoom / 6).rounded(.up)), 12)
        return (0..<pointCount).map { pointIndex in
            let angle = 2 * CGFloat.pi * CGFloat(pointIndex) / CGFloat(pointCount)
            return CGPoint(x: area.midX + radius * cos(angle), y: area.midY + radius * sin(angle))
        }
    }

    func testAWordWrittenAtAnyZoomIsTakenByALoopAroundItDrawnAtAnyOtherHoweverItIsStored() throws {
        let wordBounds = InkLasso.bounds(of: writtenWord)
        XCTAssertNotEqual(regionAtZoomEight.size, fourA, "At zoom 8 the canvas covers only part of the page")
        XCTAssertGreaterThan(regionAtZoomEight.minX + regionAtZoomEight.minY, 0, "and that part is not at the page's corner")
        for drawnZoom in drawnZooms {
            for (storageName, transform) in storedTransforms(drawnAtZoom: drawnZoom) {
                let stored = stroke(through: writtenWord, storedUnder: transform)
                for (version, word) in [("drawn", stored), ("read back", try readBack(stored))] {
                    for loopZoom in loopZooms {
                        let around = loop(around: wordBounds, drawnAtZoom: loopZoom)
                        XCTAssertTrue(InkLasso.takesStroke(word, inLoop: around),
                                      "A word written at zoom \(drawnZoom), stored \(storageName), \(version), lassoed at zoom \(loopZoom)")
                        let beside = around.map { point in CGPoint(x: point.x + wordBounds.width + 40, y: point.y) }
                        XCTAssertFalse(InkLasso.takesStroke(word, inLoop: beside),
                                       "A loop beside it, written at zoom \(drawnZoom), stored \(storageName), \(version), at zoom \(loopZoom)")
                    }
                }
            }
        }
    }

    func testTheShareOfAStrokeInsideALoopIsMeasuredOnThePageHoweverTheStrokeIsStored() throws {
        let plain = stroke(through: writtenWord, storedUnder: .identity)
        let leftPart = CGRect(x: 250, y: 370, width: 50, height: 60)
        let halfLoop = InkLasso.rectangleLoop(from: leftPart.origin, to: CGPoint(x: leftPart.maxX, y: leftPart.maxY))
        let plainShare = InkLasso.enclosedFraction(of: InkLasso.pageSamplePoints(of: plain), inLoop: halfLoop)
        XCTAssertEqual(plainShare, 0.5, accuracy: 0.05)
        for drawnZoom in drawnZooms {
            for (storageName, transform) in storedTransforms(drawnAtZoom: drawnZoom) {
                let stored = stroke(through: writtenWord, storedUnder: transform)
                let samples = InkLasso.pageSamplePoints(of: stored)
                XCTAssertEqual(InkLasso.enclosedFraction(of: samples, inLoop: halfLoop), plainShare, accuracy: 0.03,
                               "Half a word written at zoom \(drawnZoom), stored \(storageName)")
                XCTAssertTrue(InkLasso.takesStroke(stored, inLoop: halfLoop), "A loop around half of it takes it (HUNT-318)")
                // As many points on the page as for the plain stroke: the spacing is the page's.
                XCTAssertEqual(Double(samples.count), Double(InkLasso.pageSamplePoints(of: plain).count), accuracy: 2,
                               "Points tested along it, stored \(storageName)")
            }
        }
    }

    /// Before 2026-11-05 a tap measured how far the ink reaches by the stored size of its points,
    /// in the stroke's own coordinates: a stroke stored at zoom 8's scale reached 8 times as far.
    func testATapReachesTheInkByItsWidthOnThePageHoweverTheStrokeIsStored() {
        let line = (0...20).map { pointIndex in CGPoint(x: 100 + CGFloat(pointIndex) * 5, y: 300) }
        for drawnZoom in drawnZooms {
            for (storageName, transform) in storedTransforms(drawnAtZoom: drawnZoom) {
                let stored = stroke(through: line, width: 4, storedUnder: transform)
                XCTAssertTrue(InkLasso.stroke(stored, passesWithin: InkLasso.tapReach, of: CGPoint(x: 150, y: 315.5)),
                              "Within the reach of its 4 points wide ink, stored \(storageName)")
                XCTAssertFalse(InkLasso.stroke(stored, passesWithin: InkLasso.tapReach, of: CGPoint(x: 150, y: 317)),
                               "Beside it, stored \(storageName)")
            }
        }
    }

    func testADotIsTakenByALoopAroundItAndATapOnIt() {
        let dotPoint = PKStrokePoint(location: CGPoint(x: 80, y: 90), timeOffset: 0, size: CGSize(width: 24, height: 24),
                                     opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        let dot = PKStroke(ink: PKInk(.pen, color: .black), path: PKStrokePath(controlPoints: [dotPoint], creationDate: Date()),
                           transform: CGAffineTransform(scaleX: 1 / 8, y: 1 / 8), mask: nil)
        let dotBounds = CGRect(x: 9, y: 10.25, width: 2, height: 2)
        XCTAssertTrue(InkLasso.takesStroke(dot, inLoop: loop(around: dotBounds, drawnAtZoom: 1)))
        XCTAssertTrue(InkLasso.stroke(dot, passesWithin: InkLasso.tapReach, of: CGPoint(x: 10, y: 11.25)))
    }

    func testAnEnlargementIsTheTransformsScaleByArea() {
        XCTAssertEqual(InkLasso.enlargement(of: .identity), 1)
        XCTAssertEqual(InkLasso.enlargement(of: CGAffineTransform(scaleX: 1 / 8, y: 1 / 8)), 0.125, accuracy: 0.0001)
        XCTAssertEqual(InkLasso.enlargement(of: CGAffineTransform(rotationAngle: 0.7).scaledBy(x: 3, y: 3)), 3, accuracy: 0.0001)
        XCTAssertEqual(InkLasso.enlargement(of: CGAffineTransform(scaleX: 0, y: 2)), 1, "A transform that flattens is taken as none")
    }
}
