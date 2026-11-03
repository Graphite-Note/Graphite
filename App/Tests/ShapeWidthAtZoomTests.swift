/**
 * File: ShapeWidthAtZoomTests.swift
 * ---------------------------------
 * Layer: Tests
 * Description: A shape held on a zoomed page shows as wide as the stroke it becomes, and a pen's
 *              footprint is remembered by the pen's own width, whatever the zoom it drew at.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 02/11/2026
 */
#if os(iOS)
import XCTest
import SwiftUI
import PencilKit
import PDFKit
import GraphiteCore
import GraphiteApple
@testable import GraphiteUI

/// A shape held on a zoomed page shows as wide as the stroke it becomes, and a pen's footprint
/// is remembered by the pen's own width, whatever the zoom it drew at.
@MainActor
final class ShapeWidthAtZoomTests: XCTestCase {
    private var temporaryLocations: [URL] = []

    override func tearDown() async throws {
        for location in temporaryLocations { try? FileManager.default.removeItem(at: location) } // A file left in the temporary folder harms nothing.
        temporaryLocations = []
    }

    private func selection(_ ink: PencilInk, width: Double) -> PencilToolSelection {
        var preset = InkPreset(ink: ink)
        preset.width = width
        return PencilToolSelection(kind: .ink, preset: preset, erasesWholeStrokes: true, eraserWidth: 18, isRulerActive: false)
    }

    private func canvases(in view: UIView) -> [PDFPageCanvasView] {
        view.subviews.flatMap { child in ((child as? PDFPageCanvasView).map { [$0] } ?? []) + canvases(in: child) }
    }

    private func hostedPageCanvas(named name: String) async throws -> (PDFPageCanvasView, GraphitePDFDisplayView, UIWindow) {
        let location = try makeHostedBlankNotebook(named: name)
        temporaryLocations.append(location)
        let session = try await PDFSession.open(location)
        session.isWriting = true
        let controller = UIHostingController(rootView: NavigationStack { PDFPane(session: session, resolveConflict: { _ in }) })
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()
        try await waitUntil("the page's canvas is shown") { self.canvases(in: controller.view).contains { !$0.isHidden && $0.delegate != nil } }
        let canvas = try XCTUnwrap(canvases(in: controller.view).first { !$0.isHidden })
        return (canvas, try XCTUnwrap(session.pdfView as? GraphitePDFDisplayView), window)
    }

    private func zoom(_ pdfView: GraphitePDFDisplayView, canvas: PDFPageCanvasView, to scale: CGFloat) async throws {
        pdfView.autoScales = false
        pdfView.scaleFactor = scale
        try await SynthesizedStrokes.waitForPageToDraw(milliseconds: 350)
        try await waitUntil("the canvas draws at \(scale)") { abs(canvas.zoomScale - scale) < 0.02 }
    }

    private func lineAcrossThePage(_ pdfView: GraphitePDFDisplayView, in window: UIWindow, height: CGFloat = 0) -> [CGPoint] {
        let middle = pdfView.convert(CGPoint(x: pdfView.bounds.midX, y: pdfView.bounds.midY + height), to: window)
        return SynthesizedStrokes.line(from: CGPoint(x: middle.x - 120, y: middle.y), to: CGPoint(x: middle.x + 120, y: middle.y))
    }

    /// In the canvas's own coordinates, as the hold reports them, a circle on the page.
    private func circlePoints(on canvas: PDFPageCanvasView) -> [CGPoint] {
        let center = CGPoint(x: 200 * canvas.zoomScale, y: 200 * canvas.zoomScale), radius = 60 * canvas.zoomScale
        return (0...48).map { step in
            let angle = Double(step) / 48 * 2 * .pi
            return CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
        }
    }

    /// HUNT-019: the preview was 3 times the stroke at zoom 3, and snapped thinner at the lift.
    func testAShapeHeldOnAZoomedPageShowsAsWideAsItsStroke() async throws {
        let restoreFingers = SynthesizedStrokes.letFingersDraw()
        defer { restoreFingers() }
        let (canvas, pdfView, window) = try await hostedPageCanvas(named: "HeldShapeWidth")
        defer { window.isHidden = true; window.rootViewController = nil }
        let toolPicker = PKToolPicker()
        // A width no other test draws with: nothing is remembered of it yet.
        canvas.takeTool(from: toolPicker, fixedTool: selection(.pen, width: 2.85))
        try await zoom(pdfView, canvas: canvas, to: 3)

        // Before the pen has drawn, its width is the one to go by.
        canvas.strokeTouchDidRest(afterStrokeThrough: circlePoints(on: canvas))
        XCTAssertTrue(canvas.isShowingShapePreview)
        XCTAssertEqual(canvas.shapePreviewWidthInDrawing, 2.85, accuracy: 0.01, "On the page, whatever the zoom")
        canvas.strokeTouchDidEnd(wasCancelled: true)

        // Once it has, the preview is as wide as what it drew.
        let drawnStroke = try await SynthesizedStrokes.draw(on: canvas, through: lineAcrossThePage(pdfView, in: window), in: window)
        let renderedWidth = try XCTUnwrap(SynthesizedStrokes.renderedWidth(of: XCTUnwrap(drawnStroke)))
        canvas.strokeTouchDidRest(afterStrokeThrough: circlePoints(on: canvas))
        XCTAssertTrue(canvas.isShowingShapePreview)
        XCTAssertEqual(canvas.shapePreviewWidthInDrawing / renderedWidth, 1, accuracy: 0.15, "The stroke it becomes at the lift draws \(renderedWidth)")
        canvas.strokeTouchDidEnd(wasCancelled: true)
    }

    /// HUNT-020: a 3 point pen at scale 2 and a 2 point pen at scale 3 shared a footprint, and
    /// the same pen at another zoom had none.
    func testAPensFootprintIsRememberedByItsOwnWidthAtAnyZoom() async throws {
        let restoreFingers = SynthesizedStrokes.letFingersDraw()
        defer { restoreFingers() }
        let (canvas, pdfView, window) = try await hostedPageCanvas(named: "FootprintAtZoom")
        defer { window.isHidden = true; window.rootViewController = nil }
        let toolPicker = PKToolPicker()

        func drawnFootprint(width: Double, zoomedTo scale: CGFloat, height: CGFloat) async throws -> (footprint: StrokeFootprint, stroke: PKStroke) {
            try await zoom(pdfView, canvas: canvas, to: scale)
            canvas.takeTool(from: toolPicker, fixedTool: selection(.pen, width: width))
            let drawnStroke = try await SynthesizedStrokes.draw(on: canvas, through: lineAcrossThePage(pdfView, in: window, height: height), in: window)
            let stroke = try XCTUnwrap(drawnStroke, "The pen of \(width) drew nothing at \(scale)")
            let tool = try XCTUnwrap(canvas.tool as? PKInkingTool)
            XCTAssertEqual(tool.width, width, accuracy: 0.01, "The tool is the pen's own width")
            try await waitUntil("the stroke is recorded") { canvas.recordedDrawing.strokes.count == canvas.drawing.strokes.count }
            return (try XCTUnwrap(HistoryCanvasView.footprint(of: tool), "A footprint of the pen of \(width)"), stroke)
        }

        let threePointPen = try await drawnFootprint(width: 3.05, zoomedTo: 2, height: -40)
        let twoPointPen = try await drawnFootprint(width: 2.05, zoomedTo: 3, height: 40)
        XCTAssertEqual(threePointPen.footprint.size.width, try XCTUnwrap(threePointPen.stroke.path.first).size.width, accuracy: 0.5)
        XCTAssertEqual(twoPointPen.footprint.size.width, try XCTUnwrap(twoPointPen.stroke.path.first).size.width, accuracy: 0.5)
        XCTAssertLessThan(twoPointPen.footprint.size.width, threePointPen.footprint.size.width, "Two pens, two footprints")

        // The pen at another zoom still has the footprint it left, so a dragged shape can be made.
        try await zoom(pdfView, canvas: canvas, to: 1.4)
        canvas.takeTool(from: toolPicker, fixedTool: selection(.pen, width: 3.05))
        let footprintAtAnotherZoom = HistoryCanvasView.footprint(of: try XCTUnwrap(canvas.tool as? PKInkingTool))
        XCTAssertEqual(footprintAtAnotherZoom?.size.width, threePointPen.footprint.size.width)
    }
}
#endif
