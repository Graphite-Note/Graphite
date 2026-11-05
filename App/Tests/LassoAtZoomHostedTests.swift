/**
 * File: LassoAtZoomHostedTests.swift
 * ----------------------------------
 * Layer: Tests
 * Description: HUNT-007 on a hosted PDF page: words written by PencilKit at the fitted zoom, at 3.3 and
 *              zoomed far in over part of the page, each taken by loops through the lasso's recognizer.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 05/11/2026
 */
#if os(iOS)
import XCTest
import SwiftUI
import PencilKit
import PDFKit
import GraphiteApple
import GraphiteCore
@testable import GraphiteUI

/// HUNT-007: a stroke written while zoomed in, lassoed at another zoom, selected nothing and
/// marked an empty area. Each word here is written with the canvas's own drawing recognizer
/// (`SynthesizedStrokes`), so its points, sizes and transform are PencilKit's; zoomed far in the
/// canvas covers only the part of the page around the screen, scrolled within the page's drawing
/// (`PDFCanvasShownRegion`). Each loop is a finger through UIKit's event path
/// (`SynthesizedTouches`), so it goes through the lasso's recognizer and `handleLoop`, as a
/// hand's. Every stroke's storage is printed in `LASSO-ZOOM` lines for the device's log.
@MainActor
final class LassoAtZoomHostedTests: XCTestCase {
    private var windows: [UIWindow] = []

    override func setUp() async throws {
        putAwayPaletteToolsInEveryWindow()
    }

    override func tearDown() async throws {
        for window in windows { window.isHidden = true; window.rootViewController = nil }
        windows = []
        putAwayPaletteToolsInEveryWindow()
    }

    /// Each window keeps its palette's modes; the tests' windows share the app's scene.
    private func putAwayPaletteToolsInEveryWindow() {
        for case let windowScene as UIWindowScene in UIApplication.shared.connectedScenes {
            PaletteInkSelection.of(windowScene).endForChosenTool()
        }
    }

    func testAWordWrittenAtEachZoomIsTakenByALoopAtEveryOtherAndMovesAlone() async throws {
        XCTAssertNil(SynthesizedTouches.unavailableReason)
        let restoreFingers = SynthesizedStrokes.letFingersDraw()
        defer { restoreFingers() }
        let shapeBefore = LassoShape.stored
        LassoShape.stored = .freehand
        defer { LassoShape.stored = shapeBefore }
        let (session, canvas, page) = try await openPageWithCanvas()
        let pdfView = try XCTUnwrap(session.pdfView)
        let window = try XCTUnwrap(canvas.window)
        let overlay = try XCTUnwrap(canvas.overlayView)
        pdfView.autoScales = false
        let fittedZoom = pdfView.scaleFactorForSizeToFit
        let deepZoom = min(8, pdfView.maxScaleFactor)
        let pageSize = page.bounds(for: .cropBox).size

        // One word at each zoom, each at its own place on the page, in the page's points from its top-left corner.
        let words: [(zoom: CGFloat, middle: CGPoint)] = [(fittedZoom, CGPoint(x: 180, y: 240)), (3.3, CGPoint(x: 400, y: 240)), (deepZoom, CGPoint(x: 300, y: 400))]
        for (zoom, middle) in words {
            try await show(middle, at: zoom, on: page, canvas: canvas, in: pdfView)
            if zoom == deepZoom {
                XCTAssertNotEqual(overlay.shownRegion.size, pageSize, "Zoomed far in, the canvas covers part of the page")
                // Scrolled within the page's drawing to its part, which may begin at the page's corner.
                XCTAssertEqual(canvas.contentOffset.x, overlay.shownRegion.minX * canvas.zoomScale, accuracy: 0.5, "and is scrolled within the page's drawing to it, across")
                XCTAssertEqual(canvas.contentOffset.y, overlay.shownRegion.minY * canvas.zoomScale, accuracy: 0.5, "and down")
            }
            let written = wave(around: middle)
            let windowPoints = Self.densified(written.map { pagePoint in windowPoint(ofPage: pagePoint, on: canvas, in: window) }, spacing: 4)
            let drawn = try await SynthesizedStrokes.draw(on: canvas, through: windowPoints, in: window)
            let stroke = try XCTUnwrap(drawn, "PencilKit made the word written at zoom \(zoom)")
            report(stroke, drawnAt: zoom, canvas: canvas, overlay: overlay)
            // Where PencilKit put it on the page is where the hand wrote it.
            let placed = InkLasso.bounds(of: InkLasso.pageSamplePoints(of: stroke))
            let intended = InkLasso.bounds(of: written)
            XCTAssertEqual(placed.midX, intended.midX, accuracy: 3, "The word written at zoom \(zoom) is where it was written, across")
            XCTAssertEqual(placed.midY, intended.midY, accuracy: 3, "and down")
            XCTAssertEqual(placed.width, intended.width, accuracy: 4, "and as long")
        }
        XCTAssertEqual(canvas.drawing.strokes.count, words.count)

        canvas.selectsInk = true
        let selection = canvas.inkSelection
        for loopZoom in [fittedZoom, 3.3, deepZoom] {
            for (strokeIndex, word) in words.enumerated() {
                selection.clearSelection()
                try await show(word.middle, at: loopZoom, on: page, canvas: canvas, in: pdfView)
                let wordBounds = InkLasso.bounds(of: InkLasso.pageSamplePoints(of: canvas.drawing.strokes[strokeIndex]))
                try await drawLoopOfTouches(around: wordBounds, on: canvas, in: window)
                try await waitUntil("the loop at \(loopZoom) has selected") { selection.hasSelection || selection.isShowingLassoedArea }
                print("LASSO-ZOOM loop at zoom \(format(loopZoom)) around the word written at \(format(word.zoom)): selected \(selection.selectedStrokeIndices), "
                      + "area \(selection.isShowingLassoedArea), canvas zoom \(format(canvas.zoomScale)), offset \(canvas.contentOffset), region \(overlay.shownRegion)")
                XCTAssertEqual(selection.selectedStrokeIndices, [strokeIndex], "The word written at zoom \(word.zoom), lassoed at zoom \(loopZoom)")
                XCTAssertFalse(selection.isShowingLassoedArea, "Its menu has Cut, Copy and Duplicate, not only Take Screenshot")
            }
        }

        // The word written far in, taken at the fitted zoom and moved by a drag of its frame, moves alone and keeps its shape.
        selection.clearSelection()
        try await show(words[2].middle, at: fittedZoom, on: page, canvas: canvas, in: pdfView)
        let strokesBefore = canvas.drawing.strokes
        try await drawLoopOfTouches(around: InkLasso.bounds(of: InkLasso.pageSamplePoints(of: strokesBefore[2])), on: canvas, in: window)
        try await waitUntil("the deep word is selected") { selection.selectedStrokeIndices == [2] }
        let frame = try XCTUnwrap(selection.selectionFrame)
        let offsetOnPage = CGSize(width: 30, height: 20)
        selection.moveSelection(in: canvas.drawing, from: frame,
                                to: frame.offsetBy(dx: offsetOnPage.width * canvas.zoomScale, dy: offsetOnPage.height * canvas.zoomScale))
        try await waitUntil("the move is recorded") { session.undoAvailability.canUndo && canvas.drawing.strokes[2].renderBounds != strokesBefore[2].renderBounds }
        let strokesAfter = canvas.drawing.strokes
        XCTAssertEqual(strokesAfter.count, strokesBefore.count)
        XCTAssertEqual(strokesAfter[0].renderBounds, strokesBefore[0].renderBounds, "The other words stay")
        XCTAssertEqual(strokesAfter[1].renderBounds, strokesBefore[1].renderBounds)
        let samplesBefore = InkLasso.pageSamplePoints(of: strokesBefore[2]), samplesAfter = InkLasso.pageSamplePoints(of: strokesAfter[2])
        XCTAssertEqual(samplesAfter.count, samplesBefore.count, accuracy: 2)
        for (before, after) in zip(samplesBefore, samplesAfter).prefix(8) {
            XCTAssertEqual(after.x - before.x, offsetOnPage.width, accuracy: 0.75, "The word moves by the drag on the page, across")
            XCTAssertEqual(after.y - before.y, offsetOnPage.height, accuracy: 0.75, "and down")
        }
        // The stroke's own transform is carried into the moved one's points: its ink covers as much of the page.
        XCTAssertEqual(strokesAfter[2].renderBounds.width, strokesBefore[2].renderBounds.width, accuracy: 0.5, "As long and as heavy as before")
        XCTAssertEqual(strokesAfter[2].renderBounds.height, strokesBefore[2].renderBounds.height, accuracy: 0.5)
        XCTAssertEqual(strokesAfter[2].renderBounds.minX - strokesBefore[2].renderBounds.minX, offsetOnPage.width, accuracy: 0.75)
        XCTAssertEqual(selection.selectedStrokeIndices, [2], "The moved word stays selected")
    }

    /// The canvas is laid out again while the hand draws the loop, as when a zoom settles 0.2
    /// seconds after a pinch or the canvas's part of the page moves: the loop keeps enclosing
    /// what the hand circled. Kept in the canvas's own coordinates, the points before a change
    /// of scale were read at the new one and the loop enclosed another place; a move of the
    /// part covered alone leaves the canvas's coordinates the page's times its zoom.
    func testALoopKeepsWhatItCirclesWhenTheCanvasIsLaidOutAgainWhileItIsDrawn() async throws {
        XCTAssertNil(SynthesizedTouches.unavailableReason)
        let restoreFingers = SynthesizedStrokes.letFingersDraw()
        defer { restoreFingers() }
        let shapeBefore = LassoShape.stored
        LassoShape.stored = .freehand
        defer { LassoShape.stored = shapeBefore }
        let (session, canvas, page) = try await openPageWithCanvas()
        let pdfView = try XCTUnwrap(session.pdfView)
        let window = try XCTUnwrap(canvas.window)
        let overlay = try XCTUnwrap(canvas.overlayView)
        pdfView.autoScales = false
        let middle = CGPoint(x: 300, y: 400)
        try await show(middle, at: 2, on: page, canvas: canvas, in: pdfView)
        let written = wave(around: middle)
        let windowPoints = Self.densified(written.map { pagePoint in windowPoint(ofPage: pagePoint, on: canvas, in: window) }, spacing: 4)
        let drawn = try await SynthesizedStrokes.draw(on: canvas, through: windowPoints, in: window)
        let stroke = try XCTUnwrap(drawn)
        canvas.selectsInk = true
        let selection = canvas.inkSelection

        let changes: [(name: String, change: () -> Void)] = [
            ("drawn at another scale", { overlay.setRenderingScale(3) }),
            ("covering a smaller part of the page", { overlay.canvasPixelBudget = PDFCanvasShownRegion.maximumCanvasPixelCount / 16 }),
        ]
        for (name, change) in changes {
            selection.clearSelection()
            overlay.setRenderingScale(2)
            overlay.canvasPixelBudget = PDFCanvasShownRegion.maximumCanvasPixelCount
            overlay.layoutIfNeeded()
            let offsetBefore = canvas.contentOffset, scaleBefore = canvas.zoomScale
            try await drawLoopOfTouches(around: InkLasso.bounds(of: InkLasso.pageSamplePoints(of: stroke)), on: canvas, in: window) {
                change()
                overlay.layoutIfNeeded()
            }
            try await waitUntil("the loop has selected") { selection.hasSelection || selection.isShowingLassoedArea }
            XCTAssertTrue(canvas.zoomScale != scaleBefore || canvas.contentOffset != offsetBefore, "The canvas was laid out again, \(name)")
            XCTAssertEqual(selection.selectedStrokeIndices, [0], "The circled word is taken with the canvas \(name) during the loop")
            XCTAssertFalse(selection.isShowingLassoedArea)
            let lassoedLoop = try XCTUnwrap(selection.lassoedLoop)
            XCTAssertTrue(InkLasso.isPoint(CGPoint(x: middle.x, y: middle.y), insideLoop: lassoedLoop), "The loop is around the word on the page")
        }
    }

    // MARK: Helpers

    /// A written word: a wave 60 points of the page long and 16 high around a point of the page.
    private func wave(around middle: CGPoint) -> [CGPoint] {
        stride(from: CGFloat(-30), through: 30, by: 1.5).map { travelled in
            CGPoint(x: middle.x + travelled, y: middle.y + 8 * sin(travelled / 5))
        }
    }

    /// A point of the page, from its top-left corner, in the window: through the canvas's own
    /// coordinates, the drawing's times its zoom, whatever part of the page it covers.
    private func windowPoint(ofPage pagePoint: CGPoint, on canvas: PDFPageCanvasView, in window: UIWindow) -> CGPoint {
        canvas.convert(CGPoint(x: pagePoint.x * canvas.zoomScale, y: pagePoint.y * canvas.zoomScale), to: window)
    }

    /// Points no further apart than `spacing`, as a hand's touches arrive.
    private static func densified(_ points: [CGPoint], spacing: CGFloat) -> [CGPoint] {
        guard let first = points.first else { return [] }
        return [first] + zip(points, points.dropFirst()).flatMap { start, end -> [CGPoint] in
            let steps = max(Int((hypot(end.x - start.x, end.y - start.y) / spacing).rounded(.up)), 1)
            return SynthesizedStrokes.line(from: start, to: end, steps: steps).dropFirst().map { $0 }
        }
    }

    /// Zooms the PDF to `zoom` with a point of the page in the middle of the view, and waits
    /// until the canvas draws at that zoom over a part of the page holding the point.
    private func show(_ pagePoint: CGPoint, at zoom: CGFloat, on page: PDFPage, canvas: PDFPageCanvasView, in pdfView: PDFView) async throws {
        pdfView.scaleFactor = zoom
        try await SynthesizedStrokes.waitForPageToDraw(milliseconds: 400)
        let visibleWidth = pdfView.bounds.width / zoom, visibleHeight = pdfView.bounds.height / zoom
        let cropBox = page.bounds(for: .cropBox)
        pdfView.go(to: CGRect(x: cropBox.minX + pagePoint.x - visibleWidth / 2, y: cropBox.maxY - pagePoint.y - visibleHeight / 2,
                              width: visibleWidth, height: visibleHeight), on: page)
        try await SynthesizedStrokes.waitForPageToDraw(milliseconds: 300)
        try await SynthesizedStrokes.waitForCanvasToDrawAtTheZoom(of: canvas, in: pdfView)
        let overlay = try XCTUnwrap(canvas.overlayView)
        try await waitUntil("the canvas covers \(pagePoint) at \(zoom)") {
            overlay.followVisibleArea()
            return overlay.shownRegion.insetBy(dx: 40, dy: 40).contains(pagePoint)
        }
    }

    /// A finger circling an area of the page 16 screen points clear of it, through UIKit's
    /// event path, so the lasso's own recognizer receives it; `midway` runs halfway round.
    private func drawLoopOfTouches(around pageArea: CGRect, on canvas: PDFPageCanvasView, in window: UIWindow,
                                   midway: (() -> Void)? = nil) async throws {
        let middle = windowPoint(ofPage: CGPoint(x: pageArea.midX, y: pageArea.midY), on: canvas, in: window)
        let corner = windowPoint(ofPage: CGPoint(x: pageArea.maxX, y: pageArea.maxY), on: canvas, in: window)
        let radius = hypot(corner.x - middle.x, corner.y - middle.y) + 16
        let pointCount = max(Int((2 * .pi * radius / 10).rounded(.up)), 24)
        let circle = (0...pointCount).map { pointIndex in
            let angle = 2 * CGFloat.pi * CGFloat(pointIndex) / CGFloat(pointCount)
            return CGPoint(x: middle.x + radius * cos(angle), y: middle.y + radius * sin(angle))
        }
        let touches = SynthesizedTouches(window: window)
        touches.begin(at: [circle[0]])
        try await SynthesizedStrokes.waitForPageToDraw(milliseconds: 16)
        for (pointIndex, point) in circle.enumerated().dropFirst() {
            touches.moveTo([point])
            try await SynthesizedStrokes.waitForPageToDraw(milliseconds: 16)
            if pointIndex == circle.count / 2 { midway?() }
        }
        touches.end()
    }

    /// How PencilKit stored a stroke written at a zoom, for the device's log.
    private func report(_ stroke: PKStroke, drawnAt zoom: CGFloat, canvas: PDFPageCanvasView, overlay: PDFPageOverlayView) {
        let storedPoints = stroke.path.map(\.location)
        print("LASSO-ZOOM word written at zoom \(format(zoom)): transform \(stroke.transform), stored points within \(InkLasso.bounds(of: storedPoints)), "
              + "on the page within \(InkLasso.bounds(of: InkLasso.pageSamplePoints(of: stroke))), render bounds \(stroke.renderBounds), "
              + "first size \(stroke.path.first?.size ?? .zero), mask \(stroke.mask == nil ? "none" : "set"), canvas zoom \(format(canvas.zoomScale)), "
              + "offset \(canvas.contentOffset), content size \(canvas.contentSize), region \(overlay.shownRegion)")
    }

    private func format(_ value: CGFloat) -> String { String(format: "%.2f", Double(value)) }

    private func openPageWithCanvas() async throws -> (PDFSession, PDFPageCanvasView, PDFPage) {
        let vault = try TemporaryVault.make(prefix: "LassoAtZoom", for: self)
        let location = try vault.writeFile("Lasso at zoom.pdf", data: PDFTemplateGenerator.documentData(paper: PaperSpecification(template: .blank)))
        let session = try await PDFSession.open(location)
        let controller = UIHostingController(rootView: AnyView(NavigationStack { PDFPane(session: session, resolveConflict: { _ in }) }))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.effectiveGeometry.coordinateSpace.bounds
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()
        windows.append(window)
        let page = try XCTUnwrap(session.document.page(at: 0))
        func coordinator() -> PDFAnnotationCoordinator? { (session.pdfView as? GraphitePDFDisplayView)?.annotationCoordinator }
        try await waitUntil("the page has its canvas") { coordinator()?.editingCanvas(for: page)?.overlayView != nil }
        return (session, try XCTUnwrap(coordinator()?.editingCanvas(for: page)), page)
    }
}
#endif
