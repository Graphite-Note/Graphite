/**
 * File: FinePixelEraserTests.swift
 * --------------------------------
 * Layer: Tests
 * Description: Graphite's own pixel eraser on real canvases (HUNT-319): the gap a one-point eraser cuts on a PDF page
 *              at the fitted zoom and at four times, in a drawing, the ink hidden under the tip while it moves, one
 *              erase as one step of the PDF's history, and what PencilKit's own eraser leaves to compare with.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 04/11/2026
 */
#if os(iOS)
import XCTest
import SwiftUI
import PencilKit
import PDFKit
import GraphiteCore
import GraphiteApple
@testable import GraphiteUI

/// The owner's report of 2026-11-04: "eraser needs to go much much smaller, more granularity". PencilKit's
/// eraser is never narrower than 16.4 points of the screen, about 12 points of a page at the fitted zoom;
/// Graphite's cuts the chosen width. Each test prints its measures with `FINE-ERASER`.
@MainActor
final class FinePixelEraserTests: XCTestCase {
    private var temporaryLocations: [URL] = []

    override func tearDown() async throws {
        for location in temporaryLocations { try? FileManager.default.removeItem(at: location) } // A file left in the temporary folder harms nothing.
        temporaryLocations = []
    }

    private func pen(width: Double) -> PencilToolSelection {
        var preset = InkPreset(ink: .monoline)
        preset.width = width
        return PencilToolSelection(kind: .ink, preset: preset, erasesWholeStrokes: true, eraserWidth: 6, isRulerActive: false)
    }

    private func pixelEraser(width: Double) -> PencilToolSelection {
        PencilToolSelection(kind: .eraser, preset: InkPreset(ink: .monoline), erasesWholeStrokes: false, eraserWidth: width, isRulerActive: false)
    }

    /// The width of the clear run between the first and last ink along the middle row of an area of the drawing, in its points.
    private func gap(in drawing: PKDrawing, area: CGRect, pixelsPerPoint: CGFloat = 16) throws -> Double {
        let picture = try XCTUnwrap(drawing.image(from: area, scale: pixelsPerPoint).cgImage)
        var bytes = [UInt8](repeating: 0, count: picture.width * picture.height * 4)
        let context = try XCTUnwrap(CGContext(data: &bytes, width: picture.width, height: picture.height, bitsPerComponent: 8, bytesPerRow: picture.width * 4,
                                              space: XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB)), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(picture, in: CGRect(x: 0, y: 0, width: picture.width, height: picture.height))
        let middleRow = picture.height / 2
        let row = (0..<picture.width).map { column in bytes[(middleRow * picture.width + column) * 4 + 3] }
        let firstInk = try XCTUnwrap(row.firstIndex { opacity in opacity >= 128 }), lastInk = try XCTUnwrap(row.lastIndex { opacity in opacity >= 128 })
        return Double(row[firstInk...lastInk].filter { opacity in opacity < 128 }.count) / Double(pixelsPerPoint)
    }

    /// How dark the window shows a point, 0 for white, 1 for black.
    private func darkness(of window: UIWindow, at windowPoint: CGPoint) -> CGFloat {
        let picture = UIGraphicsImageRenderer(bounds: CGRect(x: windowPoint.x - 0.5, y: windowPoint.y - 0.5, width: 1, height: 1)).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: false)
        }
        var pixel = [UInt8](repeating: 255, count: 4)
        guard let cgPicture = picture.cgImage, let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return 0 }
        context.setFillColor(UIColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        context.draw(cgPicture, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return 1 - (CGFloat(pixel[0]) + CGFloat(pixel[1]) + CGFloat(pixel[2])) / (3 * 255)
    }

    // MARK: A PDF page

    /// A one-point eraser cuts one point of the page at the fitted zoom, where PencilKit's narrowest
    /// cuts about twelve, and at four times; the ink under the tip is gone while the touch moves,
    /// PencilKit is not given a drawing at each move, and Undo puts the whole line back in one step.
    func testAOnePointEraserCutsOnePointOfThePageAtTheFittedZoomAndAtFourTimes() async throws {
        let restoreFingers = SynthesizedStrokes.letFingersDraw()
        defer { restoreFingers() }
        let (session, canvas, pdfView, window) = try await hostedPageCanvas(named: "FineEraser")
        defer { window.isHidden = true; window.rootViewController = nil }
        let toolPicker = PKToolPicker()
        for zoom in [nil, 4] as [CGFloat?] {
            if let zoom {
                pdfView.autoScales = false
                pdfView.scaleFactor = zoom
            } else {
                pdfView.autoScales = true
            }
            try await SynthesizedStrokes.waitForPageToDraw(milliseconds: 400)
            try await SynthesizedStrokes.waitForCanvasToDrawAtTheZoom(of: canvas, in: pdfView)
            let label = zoom.map { zoom in "zoom \(zoom)" } ?? "fitted zoom \(pdfView.scaleFactor)"
            canvas.takeTool(from: toolPicker, fixedTool: pen(width: 2))
            canvas.drawing = PKDrawing()
            try await SynthesizedStrokes.waitForPageToDraw(milliseconds: 50)
            let middle = pdfView.convert(CGPoint(x: pdfView.bounds.midX, y: pdfView.bounds.midY), to: window)
            let drawnLine = try await SynthesizedStrokes.draw(on: canvas, through: SynthesizedStrokes.line(from: CGPoint(x: middle.x - 150, y: middle.y),
                                                                                                    to: CGPoint(x: middle.x + 150, y: middle.y), steps: 60), in: window)
            let line = try XCTUnwrap(drawnLine, "The line at \(label) is drawn")
            let inkBounds = canvas.drawing.bounds
            try await SynthesizedStrokes.waitForPageToDraw(milliseconds: 50)

            canvas.takeTool(from: toolPicker, fixedTool: pixelEraser(width: 1))
            XCTAssertTrue(canvas.pixelEraser.isErasing, "Graphite erases at \(label)")
            XCTAssertFalse(canvas.isDrawingEnabled, "PencilKit's eraser does not erase as well")
            let lineOnScreen = CGPoint(x: middle.x + 60, y: middle.y)
            var hiddenDarkness: CGFloat = 1, keptDarkness: CGFloat = 0
            let cutLine = try await SynthesizedStrokes.draw(on: canvas, through: SynthesizedStrokes.line(from: CGPoint(x: middle.x, y: middle.y - 120),
                                                                                                  to: CGPoint(x: middle.x, y: middle.y + 120), steps: 30),
                                                            in: window, toldTo: canvas.pixelEraser.touchRecognizer) {
                XCTAssertEqual(canvas.drawing.strokes.count, 1, "PencilKit is not given a drawing while the touch moves")
                XCTAssertTrue(canvas.pixelEraser.isHidingSweptInk)
                XCTAssertTrue(canvas.pixelEraser.isShowingCursor, "The eraser's circle shows")
                try await SynthesizedStrokes.waitForPageToDraw(milliseconds: 60)
                hiddenDarkness = self.darkness(of: window, at: middle)
                keptDarkness = self.darkness(of: window, at: lineOnScreen)
            }
            XCTAssertNotNil(cutLine, "The one-point eraser cut the line in two at \(label)")
            print("FINE-ERASER page \(label): darkness under the tip while moving \(hiddenDarkness), on the line beside it \(keptDarkness)")
            XCTAssertLessThan(hiddenDarkness, 0.2, "The ink under the tip is hidden while the touch moves, at \(label)")
            XCTAssertGreaterThan(keptDarkness, 0.5, "The rest of the line still shows, at \(label)")
            XCTAssertFalse(canvas.pixelEraser.isShowingCursor)
            let measuredGap = try gap(in: canvas.drawing, area: inkBounds)
            print("FINE-ERASER page \(label): canvas zoom \(canvas.zoomScale), gap \(measuredGap) points of the page, "
                  + "\(canvas.drawing.strokes.count) strokes, masks \(canvas.drawing.strokes.map { stroke in stroke.mask?.bounds ?? .null })")
            XCTAssertEqual(measuredGap, 1, accuracy: 0.3, "One point of the page at \(label)")
            XCTAssertTrue(canvas.drawing.strokes.allSatisfy { piece in piece.path.count == line.path.count }, "Each piece keeps the line's path")

            try await SynthesizedStrokes.waitForPageToDraw(milliseconds: 50)
            session.undoAvailability.undo()
            XCTAssertNil(session.errorMessage)
            XCTAssertEqual(canvas.drawing.strokes.count, 1, "One Undo puts the whole line back at \(label)")
            XCTAssertNil(canvas.drawing.strokes.first?.mask)
            try await SynthesizedStrokes.waitForPageToDraw(milliseconds: 50)
        }
    }

    /// What PencilKit's own eraser leaves, at a width it makes, beside what Graphite's leaves: both cut
    /// the line into strokes that keep its path and hide the gap with their masks.
    func testGraphitesEraserLeavesWhatPencilKitsOwnLeaves() async throws {
        let restoreFingers = SynthesizedStrokes.letFingersDraw()
        defer { restoreFingers() }
        let (_, canvas, pdfView, window) = try await hostedPageCanvas(named: "EraserResults")
        defer { window.isHidden = true; window.rootViewController = nil }
        let toolPicker = PKToolPicker()
        pdfView.autoScales = false
        pdfView.scaleFactor = 1.5
        try await SynthesizedStrokes.waitForPageToDraw(milliseconds: 400)
        try await SynthesizedStrokes.waitForCanvasToDrawAtTheZoom(of: canvas, in: pdfView)
        var results: [String: [PKStroke]] = [:]
        for (name, eraserWidth) in [("PencilKit", 24.0), ("Graphite", 1.0)] {
            canvas.takeTool(from: toolPicker, fixedTool: pen(width: 2))
            canvas.drawing = PKDrawing()
            let middle = pdfView.convert(CGPoint(x: pdfView.bounds.midX, y: pdfView.bounds.midY), to: window)
            let drawnLine = try await SynthesizedStrokes.draw(on: canvas, through: SynthesizedStrokes.line(from: CGPoint(x: middle.x - 150, y: middle.y),
                                                                                                    to: CGPoint(x: middle.x + 150, y: middle.y), steps: 60), in: window)
            let line = try XCTUnwrap(drawnLine)
            canvas.takeTool(from: toolPicker, fixedTool: pixelEraser(width: eraserWidth))
            XCTAssertEqual(canvas.pixelEraser.isErasing, name == "Graphite")
            let cutLine = try await SynthesizedStrokes.draw(on: canvas, through: SynthesizedStrokes.line(from: CGPoint(x: middle.x, y: middle.y - 120),
                                                                                                  to: CGPoint(x: middle.x, y: middle.y + 120), steps: 30),
                                                            in: window, toldTo: name == "Graphite" ? canvas.pixelEraser.touchRecognizer : nil)
            XCTAssertNotNil(cutLine, "\(name)'s eraser cut the line")
            try await SynthesizedStrokes.waitForPageToDraw(milliseconds: 150)
            let strokes = canvas.drawing.strokes
            results[name] = strokes
            print("FINE-ERASER \(name)'s eraser, \(eraserWidth) points: \(strokes.count) strokes from one of \(line.path.count) points; "
                  + strokes.map { stroke in
                      "points \(stroke.path.count), same path \(stroke.path.map(\.location) == line.path.map(\.location)), transform \(stroke.transform), "
                          + "mask \(stroke.mask.map { mask in "\(mask.bounds), \(mask.cgPath.boundingBoxOfPath)" } ?? "none"), "
                          + "masked ranges \(stroke.maskedPathRanges), render bounds \(stroke.renderBounds)"
                  }.joined(separator: " | "))
        }
        let pencilKitStrokes = try XCTUnwrap(results["PencilKit"]), graphiteStrokes = try XCTUnwrap(results["Graphite"])
        XCTAssertEqual(graphiteStrokes.count, pencilKitStrokes.count, "As many pieces as PencilKit's eraser leaves")
        XCTAssertEqual(graphiteStrokes.map { stroke in stroke.mask != nil }, pencilKitStrokes.map { stroke in stroke.mask != nil }, "Masked as PencilKit's are")
    }

    // MARK: A drawing

    /// In a drawing, fitted and zoomed four times, a one-point eraser cuts one point of the drawing, and
    /// the canvas reports the erase once, as one change for its owner to record.
    func testAOnePointEraserCutsOnePointOfADrawingAndIsReportedOnce() async throws {
        let restoreFingers = SynthesizedStrokes.letFingersDraw()
        defer { restoreFingers() }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.effectiveGeometry.coordinateSpace.bounds
        window.rootViewController = UIViewController()
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        let canvas = InfiniteCanvasView(frame: CGRect(x: 0, y: 0, width: 800, height: 1_000))
        canvas.drawingPolicy = .anyInput
        let changeCounter = DrawingChangeCounter()
        canvas.delegate = changeCounter
        canvas.canvasWidth = 400
        window.rootViewController?.view.addSubview(canvas)
        canvas.layoutIfNeeded()
        let fittedZoom = canvas.zoomScale
        canvas.maximumZoomScale = fittedZoom * 4
        let original = PKStroke(ink: PKInk(.monoline, color: .black), path: PKStrokePath(controlPoints: (0...40).map { pointIndex in
            PKStrokePoint(location: CGPoint(x: 100 + CGFloat(pointIndex) * 5, y: 120), timeOffset: Double(pointIndex) / 60, size: CGSize(width: 3, height: 3),
                          opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }, creationDate: Date()))
        for zoom in [fittedZoom, fittedZoom * 4] {
            canvas.zoomScale = zoom
            canvas.contentOffset = CGPoint(x: max(200 * zoom - canvas.bounds.width / 2, 0), y: max(120 * zoom - canvas.bounds.height / 2, 0))
            canvas.layoutIfNeeded()
            canvas.drawing = PKDrawing(strokes: [original])
            canvas.takeTool(from: PKToolPicker(), fixedTool: pixelEraser(width: 1))
            XCTAssertTrue(canvas.pixelEraser.isErasing, "Graphite erases at zoom \(zoom)")
            try await SynthesizedStrokes.waitForPageToDraw(milliseconds: 50)
            let changesBefore = changeCounter.drawingChangeCount
            let crossing = canvas.convert(CGPoint(x: 200 * zoom, y: 120 * zoom), to: window)
            let cutLine = try await SynthesizedStrokes.draw(on: canvas, through: SynthesizedStrokes.line(from: CGPoint(x: crossing.x, y: crossing.y - 80),
                                                                                                  to: CGPoint(x: crossing.x, y: crossing.y + 80), steps: 30),
                                                            in: window, toldTo: canvas.pixelEraser.touchRecognizer)
            XCTAssertNotNil(cutLine, "The line is cut at zoom \(zoom)")
            XCTAssertEqual(changeCounter.drawingChangeCount - changesBefore, 1, "One erase, one change, at zoom \(zoom)")
            let measuredGap = try gap(in: canvas.drawing, area: CGRect(x: 90, y: 100, width: 220, height: 40))
            print("FINE-ERASER drawing at zoom \(zoom) (fitted \(fittedZoom)): gap \(measuredGap) points of the drawing")
            XCTAssertEqual(measuredGap, 1, accuracy: 0.3, "Zoom \(zoom)")
        }
    }

    // MARK: Hosting

    private func hostedPageCanvas(named name: String) async throws -> (PDFSession, PDFPageCanvasView, GraphitePDFDisplayView, UIWindow) {
        let location = try makeHostedBlankNotebook(named: name)
        temporaryLocations.append(location)
        let session = try await PDFSession.open(location)
        session.isWriting = true
        let controller = UIHostingController(rootView: NavigationStack { PDFPane(session: session, resolveConflict: { _ in }) })
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.effectiveGeometry.coordinateSpace.bounds
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()
        try await waitUntil("the page's canvas is shown") { self.canvases(in: controller.view).contains { canvas in !canvas.isHidden && canvas.delegate != nil } }
        let canvas = try XCTUnwrap(canvases(in: controller.view).first { canvas in !canvas.isHidden })
        return (session, canvas, try XCTUnwrap(session.pdfView as? GraphitePDFDisplayView), window)
    }

    private func canvases(in view: UIView) -> [PDFPageCanvasView] {
        view.subviews.flatMap { child in ((child as? PDFPageCanvasView).map { [$0] } ?? []) + canvases(in: child) }
    }
}

/// Counts the drawing changes a canvas reports, as its owner hears them.
@MainActor
private final class DrawingChangeCounter: NSObject, PKCanvasViewDelegate {
    private(set) var drawingChangeCount = 0

    func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
        drawingChangeCount += 1
    }

    func canvasViewDidFinishRendering(_ canvasView: PKCanvasView) {
        (canvasView as? HistoryCanvasView)?.drawingDidFinishRendering()
    }
}
#endif
