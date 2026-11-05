/**
 * File: PixelEraserPassTests.swift
 * --------------------------------
 * Layer: Tests
 * Description: Graphite's own pixel eraser (HUNT-319): the gap it cuts at the chosen width at every zoom, the strokes
 *              it leaves as PencilKit's eraser leaves them, one erase as one step, and how long a move takes on a
 *              full page.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 04/11/2026
 */
import XCTest
import PencilKit
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif
@testable import GraphiteApple

/// The owner's report of 2026-11-04: "eraser needs to go much much smaller, more granularity". PencilKit's
/// eraser is never narrower than 16.4 points of the screen; Graphite's cuts the width chosen, measured
/// here in the drawing PencilKit draws (`PKDrawing.image`, which draws as on the iPad).
@MainActor
final class PixelEraserPassTests: XCTestCase {
    private static let pixelsPerPoint: CGFloat = 16

    private func line(from start: CGPoint, to end: CGPoint, pointCount: Int = 21, size: CGFloat = 3,
                      ink: PKInk.InkType = .monoline, transform: CGAffineTransform = .identity) -> PKStroke {
        let controlPoints = (0..<pointCount).map { pointIndex in
            let fraction = CGFloat(pointIndex) / CGFloat(pointCount - 1)
            return PKStrokePoint(location: CGPoint(x: start.x + (end.x - start.x) * fraction, y: start.y + (end.y - start.y) * fraction),
                                 timeOffset: TimeInterval(pointIndex) / 60, size: CGSize(width: size, height: size), opacity: 1, force: 1,
                                 azimuth: 0, altitude: .pi / 2)
        }
        return PKStroke(ink: PKInk(ink, color: .black), path: PKStrokePath(controlPoints: controlPoints, creationDate: Date(timeIntervalSince1970: 1_000)),
                        transform: transform, mask: nil)
    }

    /// The opacity of each pixel along a row of the drawing, at `pixelsPerPoint`.
    private func opacities(of drawing: PKDrawing, in area: CGRect, alongRowAt rowPosition: CGFloat) throws -> [UInt8] {
        #if canImport(UIKit)
        let picture = try XCTUnwrap(drawing.image(from: area, scale: Self.pixelsPerPoint).cgImage)
        #else
        let image = drawing.image(from: area, scale: Self.pixelsPerPoint)
        var proposedArea = CGRect(origin: .zero, size: image.size)
        let picture = try XCTUnwrap(image.cgImage(forProposedRect: &proposedArea, context: nil, hints: nil))
        #endif
        var bytes = [UInt8](repeating: 0, count: picture.width * picture.height * 4)
        let context = try XCTUnwrap(CGContext(data: &bytes, width: picture.width, height: picture.height, bitsPerComponent: 8, bytesPerRow: picture.width * 4,
                                              space: XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB)), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(picture, in: CGRect(x: 0, y: 0, width: picture.width, height: picture.height))
        let row = min(max(Int((rowPosition - area.minY) / area.height * CGFloat(picture.height)), 0), picture.height - 1)
        return (0..<picture.width).map { column in bytes[(row * picture.width + column) * 4 + 3] }
    }

    /// The width of the clear run between the first and last ink along a row, in points.
    private func gap(in drawing: PKDrawing, area: CGRect, rowPosition: CGFloat) throws -> Double {
        let row = try opacities(of: drawing, in: area, alongRowAt: rowPosition)
        let firstInk = try XCTUnwrap(row.firstIndex { opacity in opacity >= 128 }), lastInk = try XCTUnwrap(row.lastIndex { opacity in opacity >= 128 })
        return Double(row[firstInk...lastInk].filter { opacity in opacity < 128 }.count) / Double(Self.pixelsPerPoint)
    }

    /// A touch across the canvas as UIKit reports it: canvas points, a few coalesced in each move,
    /// turned into the drawing's points as the canvas turns them (`PixelEraserController`).
    private func erase(_ drawing: PKDrawing, width: CGFloat, zoom: CGFloat, fromCanvasPoint start: CGPoint, to end: CGPoint) -> (PixelEraserTouch, moveCount: Int) {
        var touch = PixelEraserTouch(drawing: drawing, width: width, shownBounds: CGRect(x: -1_000, y: -1_000, width: 3_000, height: 3_000))
        let stepCount = 40
        for moveIndex in 0..<(stepCount / 2) {
            let canvasPoints = (0..<2).map { coalescedIndex in
                let fraction = CGFloat(moveIndex * 2 + coalescedIndex) / CGFloat(stepCount - 1)
                return CGPoint(x: start.x + (end.x - start.x) * fraction, y: start.y + (end.y - start.y) * fraction)
            }
            touch.move(through: canvasPoints.map { point in CGPoint(x: point.x / zoom, y: point.y / zoom) }, predicted: [])
        }
        touch.move(through: [CGPoint(x: end.x / zoom, y: end.y / zoom)], predicted: [])
        return (touch, stepCount / 2 + 1)
    }

    func testAOnePointCutThroughALineLeavesAOnePointGapAtEveryZoom() throws {
        let original = line(from: CGPoint(x: 0, y: 50), to: CGPoint(x: 100, y: 50))
        let area = CGRect(x: -10, y: 30, width: 140, height: 40)
        for zoom in [0.5, 1, 4] as [CGFloat] {
            // Across the line at x = 50 of the drawing, wherever that is on the canvas.
            let (touch, _) = erase(PKDrawing(strokes: [original]), width: 1, zoom: zoom,
                                   fromCanvasPoint: CGPoint(x: 50 * zoom, y: 20 * zoom), to: CGPoint(x: 50 * zoom, y: 80 * zoom))
            let erased = try XCTUnwrap(touch.erasedDrawing(), "Zoom \(zoom) cut the line")
            XCTAssertEqual(erased.strokes.count, 2, "The line is two pieces at zoom \(zoom), as PencilKit's eraser leaves it.")
            for piece in erased.strokes {
                XCTAssertNotNil(piece.mask, "A piece is the stroke with a mask.")
                XCTAssertEqual(piece.path.map(\.location), original.path.map(\.location), "PencilKit's eraser keeps the path.")
                XCTAssertEqual(piece.randomSeed, original.randomSeed)
            }
            for rowPosition in [49.5, 50.0, 50.5] as [CGFloat] {
                let measuredGap = try gap(in: erased, area: area, rowPosition: rowPosition)
                print("FINE-ERASER zoom \(zoom) row \(rowPosition): gap \(measuredGap) points")
                XCTAssertEqual(measuredGap, 1, accuracy: 0.3, "Zoom \(zoom), row \(rowPosition)")
            }
        }
    }

    func testEveryWidthCutsItsOwnGap() throws {
        let original = line(from: CGPoint(x: 0, y: 50), to: CGPoint(x: 100, y: 50))
        for width in [0.5, 2, 6, 14] as [CGFloat] {
            let erased = PixelEraserPass.erasing(PKDrawing(strokes: [original]), along: [CGPoint(x: 50, y: 20), CGPoint(x: 50, y: 80)], width: width)
            let measuredGap = try gap(in: erased, area: CGRect(x: -10, y: 30, width: 140, height: 40), rowPosition: 50)
            print("FINE-ERASER width \(width): gap \(measuredGap) points")
            XCTAssertEqual(measuredGap, Double(width), accuracy: 0.3)
        }
    }

    func testAStrokeTheEraserDoesNotReachIsUntouched() throws {
        let crossed = line(from: CGPoint(x: 0, y: 50), to: CGPoint(x: 100, y: 50))
        let besideIt = line(from: CGPoint(x: 0, y: 56), to: CGPoint(x: 100, y: 56))
        // Its bounds meet the touch's, its ink does not: the touch runs a point above the line's ink.
        let grazed = line(from: CGPoint(x: 0, y: 30), to: CGPoint(x: 60, y: 30))
        var pass = PixelEraserPass(drawing: PKDrawing(strokes: [crossed, besideIt, grazed]), width: 1)
        // Along the grazed line first, a point above its ink, then round its end and down across the first line.
        pass.sweep(through: [CGPoint(x: 40, y: 27.8), CGPoint(x: 58, y: 27.8)])
        XCTAssertTrue(pass.cutStrokeIndices.isEmpty, "Within the grazed line's bounds, not its ink")
        pass.sweep(through: [CGPoint(x: 80, y: 20), CGPoint(x: 80, y: 40), CGPoint(x: 50, y: 40), CGPoint(x: 50, y: 53)])
        XCTAssertEqual(pass.cutStrokeIndices, [0])
        let erased = pass.erasedDrawing()
        XCTAssertEqual(erased.strokes.count, 4)
        for (untouched, original) in [(erased.strokes[2], besideIt), (erased.strokes[3], grazed)] {
            XCTAssertNil(untouched.mask)
            XCTAssertEqual(untouched.path.map(\.location), original.path.map(\.location))
            XCTAssertEqual(untouched.path.creationDate, original.path.creationDate)
            XCTAssertEqual(untouched.randomSeed, original.randomSeed)
        }
        XCTAssertNil(PixelEraserTouch(drawing: PKDrawing(strokes: [besideIt]), width: 1, shownBounds: .infinite).erasedDrawing(), "Nothing cut, nothing to record.")
    }

    func testAStrokeErasedEntirelyIsGoneAndPiecesKeepTheirPlace() throws {
        let first = line(from: CGPoint(x: 0, y: 20), to: CGPoint(x: 100, y: 20))
        let short = line(from: CGPoint(x: 40, y: 50), to: CGPoint(x: 44, y: 50), pointCount: 3)
        let last = line(from: CGPoint(x: 0, y: 80), to: CGPoint(x: 100, y: 80))
        var pass = PixelEraserPass(drawing: PKDrawing(strokes: [first, short, last]), width: 10)
        pass.sweep(through: [CGPoint(x: 42, y: 45), CGPoint(x: 42, y: 90)])
        let erased = pass.erasedDrawing()
        XCTAssertEqual(erased.strokes.count, 3, "The short stroke is gone, the last one in two pieces.")
        XCTAssertNil(erased.strokes[0].mask)
        XCTAssertEqual(erased.strokes[1].path.map(\.location), last.path.map(\.location))
        XCTAssertLessThan(try XCTUnwrap(erased.strokes[1].mask).bounds.maxX, 40, "The first piece is the left one.")
        XCTAssertGreaterThan(try XCTUnwrap(erased.strokes[2].mask).bounds.minX, 44)
    }

    /// Each piece shows its own run alone: a translucent highlighter and a pencil's grain are drawn
    /// exactly as before outside the cut.
    func testPiecesDrawExactlyAsTheStrokeDidOutsideTheCut() throws {
        let area = CGRect(x: -10, y: 30, width: 140, height: 40)
        for (ink, size) in [(PKInk.InkType.marker, CGFloat(12)), (.pencil, 4), (.pen, 3), (.fountainPen, 4)] {
            let original = line(from: CGPoint(x: 0, y: 50), to: CGPoint(x: 100, y: 52), pointCount: 40, size: size, ink: ink)
            let erased = PixelEraserPass.erasing(PKDrawing(strokes: [original]), along: [CGPoint(x: 50, y: 20), CGPoint(x: 50, y: 80)], width: 1)
            XCTAssertEqual(erased.strokes.count, 2, "\(ink.rawValue)")
            let before = try opacities(of: PKDrawing(strokes: [original]), in: area, alongRowAt: 51)
            let after = try opacities(of: erased, in: area, alongRowAt: 51)
            let changedOutsideTheCut = before.indices.filter { column in
                abs(area.minX + CGFloat(column) / Self.pixelsPerPoint - 50) > 1 && before[column] != after[column]
            }
            XCTAssertEqual(changedOutsideTheCut.count, 0, "\(ink.rawValue) drawn differently outside the cut")
        }
    }

    func testAMovedOrScaledStrokeIsCutWhereItIsShown() throws {
        let moved = line(from: CGPoint(x: 0, y: 25), to: CGPoint(x: 50, y: 25), transform: CGAffineTransform(scaleX: 2, y: 2))
        let erased = PixelEraserPass.erasing(PKDrawing(strokes: [moved]), along: [CGPoint(x: 50, y: 20), CGPoint(x: 50, y: 80)], width: 1)
        XCTAssertEqual(erased.strokes.count, 2)
        XCTAssertEqual(try gap(in: erased, area: CGRect(x: -10, y: 30, width: 140, height: 40), rowPosition: 50), 1, accuracy: 0.3,
                       "One point of the drawing, the stroke drawn twice its size.")
    }

    /// The cut strokes are ordinary PencilKit strokes with masks: a saved drawing reads back the same,
    /// and the PDF's ink (`PencilStrokeSampler`) keeps the gap.
    func testTheErasedDrawingReadsBackAndItsPiecesAreSavedApart() throws {
        let original = line(from: CGPoint(x: 0, y: 50), to: CGPoint(x: 100, y: 50))
        let erased = PixelEraserPass.erasing(PKDrawing(strokes: [original]), along: [CGPoint(x: 50, y: 20), CGPoint(x: 50, y: 80)], width: 1)
        let readBack = try PKDrawing(data: erased.dataRepresentation())
        XCTAssertEqual(readBack.strokes.count, 2)
        XCTAssertEqual(try gap(in: readBack, area: CGRect(x: -10, y: 30, width: 140, height: 40), rowPosition: 50), 1, accuracy: 0.3)
        for piece in readBack.strokes {
            let segments = PencilStrokeSampler.visibleSegments(of: piece)
            XCTAssertEqual(segments.count, 1, "Each piece is one run of ink.")
            XCTAssertFalse(segments.flatMap { segment in segment }.contains { sample in abs(sample.point.x - 50) < 0.4 }, "Nothing inside the gap.")
        }
    }

    /// The canvas shows the ink outside `shownArea` while the touch moves; the drawing it records
    /// comes once, at the lift, and undoing that one step gives back the stroke as it was.
    func testOneTouchIsOneStepOfTheHistory() throws {
        let original = line(from: CGPoint(x: 0, y: 50), to: CGPoint(x: 100, y: 50))
        let drawingBefore = PKDrawing(strokes: [original])
        let (touch, moveCount) = erase(drawingBefore, width: 1, zoom: 1, fromCanvasPoint: CGPoint(x: 50, y: 20), to: CGPoint(x: 50, y: 80))
        XCTAssertGreaterThan(moveCount, 10)
        XCTAssertFalse(touch.shownArea.contains(CGPoint(x: 50, y: 50)), "The ink under the tip is hidden during the touch.")
        XCTAssertTrue(touch.shownArea.contains(CGPoint(x: 52, y: 50)))
        let shown = ShownDrawing(drawingBefore)
        let history = UndoManager()
        history.groupsByEvent = false
        // What the canvas's owner does with the drawing the canvas reports once (`canvasViewDrawingDidChange`).
        let erasedDrawing = try XCTUnwrap(touch.erasedDrawing())
        history.beginUndoGrouping()
        history.registerUndo(withTarget: shown) { shown in shown.drawing = drawingBefore }
        history.endUndoGrouping()
        shown.drawing = erasedDrawing
        XCTAssertEqual(shown.drawing.strokes.count, 2)
        history.undo()
        XCTAssertFalse(history.canUndo, "One touch, one step.")
        XCTAssertEqual(shown.drawing.strokes.count, 1)
        XCTAssertNil(shown.drawing.strokes[0].mask)
        XCTAssertEqual(shown.drawing.strokes[0].path.map(\.location), original.path.map(\.location))
    }

    func testPredictedPointsAreHiddenOnlyUntilTheNextMove() {
        var touch = PixelEraserTouch(drawing: PKDrawing(strokes: [line(from: CGPoint(x: 0, y: 50), to: CGPoint(x: 100, y: 50))]), width: 1,
                                     shownBounds: CGRect(x: -100, y: -100, width: 400, height: 400))
        touch.move(through: [CGPoint(x: 50, y: 20), CGPoint(x: 50, y: 40)], predicted: [CGPoint(x: 50, y: 60)])
        XCTAssertFalse(touch.shownArea.contains(CGPoint(x: 50, y: 50)), "Hidden where the tip is about to be.")
        XCTAssertTrue(touch.keptArea.contains(CGPoint(x: 50, y: 50)), "Not erased.")
        touch.move(through: [CGPoint(x: 60, y: 40)], predicted: [])
        XCTAssertTrue(touch.shownArea.contains(CGPoint(x: 50, y: 50)), "Shown again when the touch went elsewhere.")
        XCTAssertNil(touch.erasedDrawing(), "The line was never reached.")
    }

    func testATouchOverADrawingReplacedMeanwhileErasesTheNewOne() throws {
        let (touch, _) = erase(PKDrawing(strokes: [line(from: CGPoint(x: 0, y: 50), to: CGPoint(x: 100, y: 50))]), width: 1, zoom: 1,
                               fromCanvasPoint: CGPoint(x: 50, y: 20), to: CGPoint(x: 50, y: 80))
        let replacement = PKDrawing(strokes: [line(from: CGPoint(x: 0, y: 60), to: CGPoint(x: 100, y: 60)), line(from: CGPoint(x: 0, y: 90), to: CGPoint(x: 100, y: 90))])
        let erased = try XCTUnwrap(touch.erasedDrawing(replacing: replacement))
        XCTAssertEqual(erased.strokes.count, 3, "The line the touch crossed is cut, the one below it is not.")
        XCTAssertNil(erased.strokes[2].mask)
    }

    /// A page of 2,000 strokes, as the canvas has drawn it, which gives each stroke its bounds.
    private func pageOfTwoThousandStrokes() -> PKDrawing {
        var strokes: [PKStroke] = []
        for strokeIndex in 0..<2_000 {
            let row = CGFloat(strokeIndex / 20), column = CGFloat(strokeIndex % 20)
            let start = CGPoint(x: 10 + column * 29, y: 10 + row * 8)
            strokes.append(line(from: start, to: CGPoint(x: start.x + 24, y: start.y + 3), pointCount: 30, size: 2.4, ink: .pen))
        }
        let page = PKDrawing(strokes: strokes)
        _ = page.strokes.map(\.renderBounds)
        return page
    }

    /// Two seconds of scribbling across the page at 120 moves a second, or half a second across one
    /// word, each move with two coalesced points and one predicted.
    private func touchMoves(acrossTheWholePage: Bool) -> [(points: [CGPoint], predicted: [CGPoint])] {
        (0..<(acrossTheWholePage ? 240 : 60)).map { moveIndex in
            let position = CGFloat(moveIndex)
            let place = { (step: CGFloat) -> CGPoint in
                acrossTheWholePage ? CGPoint(x: 40 + step * 2, y: 300 + 120 * sin(step / 9))
                    : CGPoint(x: 100 + step * 1.5, y: 252 + 6 * sin(step / 2))
            }
            return ([place(position), place(position + 0.5)], [place(position + 1.5)])
        }
    }

    private struct EraseTiming {
        let slowestMoveMilliseconds: Double
        let medianMoveMilliseconds: Double
        let liftMilliseconds: Double
        let cutStrokeCount: Int
        let erasedDrawing: PKDrawing
    }

    private func timeErase(on page: PKDrawing, acrossTheWholePage: Bool, pieceSecondsPerMove: Double) throws -> EraseTiming {
        var touch = PixelEraserTouch(drawing: page, width: 2, shownBounds: CGRect(x: -100, y: -100, width: 800, height: 1_000),
                                     pieceSecondsPerMove: pieceSecondsPerMove)
        var moveMilliseconds: [Double] = []
        for move in touchMoves(acrossTheWholePage: acrossTheWholePage) {
            let moveStart = DispatchTime.now().uptimeNanoseconds
            touch.move(through: move.points, predicted: move.predicted)
            moveMilliseconds.append(Double(DispatchTime.now().uptimeNanoseconds - moveStart) / 1_000_000)
        }
        let liftStart = DispatchTime.now().uptimeNanoseconds
        let erasedDrawing = try XCTUnwrap(touch.erasedDrawing())
        let liftMilliseconds = Double(DispatchTime.now().uptimeNanoseconds - liftStart) / 1_000_000
        let sortedMoves = moveMilliseconds.sorted()
        return EraseTiming(slowestMoveMilliseconds: sortedMoves.last ?? 0, medianMoveMilliseconds: sortedMoves[sortedMoves.count / 2],
                           liftMilliseconds: liftMilliseconds, cutStrokeCount: touch.pass.cutStrokeIndices.count, erasedDrawing: erasedDrawing)
    }

    /// On a page of 2,000 strokes a move of the eraser, with the ink it hides, costs under 4 ms: the
    /// strokes are found by their bounds, and only those the touch reaches are cut. The pieces of the
    /// strokes the touch has left are made during the moves, so the lift takes under 8 ms, across one
    /// word as after scribbling over the whole page, and leaves the same drawing as making them all at the lift.
    func testAMoveTakesUnderFourMillisecondsAndTheLiftUnderEightOnAPageOfTwoThousandStrokes() throws {
        let page = pageOfTwoThousandStrokes()
        for acrossTheWholePage in [false, true] {
            let name = acrossTheWholePage ? "a scribble across the page" : "an erase across one word"
            let allAtTheLift = try timeErase(on: page, acrossTheWholePage: acrossTheWholePage, pieceSecondsPerMove: 0)
            let duringTheMoves = try timeErase(on: page, acrossTheWholePage: acrossTheWholePage, pieceSecondsPerMove: PixelEraserTouch.defaultPieceSecondsPerMove)
            print("FINE-ERASER 2000 strokes, \(name): \(duringTheMoves.cutStrokeCount) strokes cut; "
                  + "pieces at the lift: lift \(allAtTheLift.liftMilliseconds) ms, slowest move \(allAtTheLift.slowestMoveMilliseconds) ms; "
                  + "pieces during the moves: lift \(duringTheMoves.liftMilliseconds) ms, move median \(duringTheMoves.medianMoveMilliseconds) ms, "
                  + "slowest \(duringTheMoves.slowestMoveMilliseconds) ms")
            XCTAssertLessThan(duringTheMoves.slowestMoveMilliseconds, 4, "The slowest move, \(name)")
            XCTAssertLessThan(duringTheMoves.liftMilliseconds, 8, "The lift, \(name)")
            XCTAssertGreaterThan(duringTheMoves.cutStrokeCount, acrossTheWholePage ? 100 : 2)
            let expectedStrokes = allAtTheLift.erasedDrawing.strokes, madeStrokes = duringTheMoves.erasedDrawing.strokes
            XCTAssertEqual(madeStrokes.count, expectedStrokes.count, "The same pieces, \(name)")
            XCTAssertEqual(madeStrokes.map { stroke in stroke.mask?.bounds ?? .null }, expectedStrokes.map { stroke in stroke.mask?.bounds ?? .null })
        }
    }

}

/// The drawing a canvas shows, for the history to change.
@MainActor
private final class ShownDrawing {
    var drawing: PKDrawing

    init(_ drawing: PKDrawing) {
        self.drawing = drawing
    }
}
