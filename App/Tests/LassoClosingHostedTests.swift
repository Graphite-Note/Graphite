/**
 * File: LassoClosingHostedTests.swift
 * -----------------------------------
 * Layer: Tests
 * Description: Graphite's lasso on a hosted PDF page, through its own recognizer: a loop the hand leaves
 *              open closes when it lifts, shows closed, and takes a stroke it only partly circles.
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
import GraphiteApple
import GraphiteCore
@testable import GraphiteUI

/// HUNT-318: the lasso closes the loop by itself when the hand lifts, and takes what it circles
/// only partly (owner, 2026-11-04). The ink is drawn by PencilKit from stand-in touches
/// (`SynthesizedStrokes`); the loop is a finger through UIKit's own event path
/// (`SynthesizedTouches`), so it goes through the lasso's recognizer, `handleLoop`, as a hand's.
@MainActor
final class LassoClosingHostedTests: XCTestCase {
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

    func testAnOpenLoopThroughTheLassosRecognizerClosesAndTakesTheStrokeItPartlyCircles() async throws {
        XCTAssertNil(SynthesizedTouches.unavailableReason)
        let restoreFingers = SynthesizedStrokes.letFingersDraw()
        defer { restoreFingers() }
        let shapeBefore = LassoShape.stored
        LassoShape.stored = .freehand
        defer { LassoShape.stored = shapeBefore }
        let (session, canvas) = try await openPageWithCanvas()
        let pdfView = try XCTUnwrap(session.pdfView)
        let window = try XCTUnwrap(canvas.window)
        try await SynthesizedStrokes.waitForCanvasToDrawAtTheZoom(of: canvas, in: pdfView)
        let middle = pdfView.convert(CGPoint(x: pdfView.bounds.midX, y: pdfView.bounds.midY), to: window)

        // A line of writing 300 points long, and below it a line the loop's edge will graze.
        let writing = try await SynthesizedStrokes.draw(on: canvas, through: SynthesizedStrokes.line(
            from: CGPoint(x: middle.x - 150, y: middle.y), to: CGPoint(x: middle.x + 150, y: middle.y)), in: window)
        let grazed = try await SynthesizedStrokes.draw(on: canvas, through: SynthesizedStrokes.line(
            from: CGPoint(x: middle.x - 75, y: middle.y + 97), to: CGPoint(x: middle.x + 225, y: middle.y + 97)), in: window)
        let writingStroke = try XCTUnwrap(writing, "The line of writing")
        _ = try XCTUnwrap(grazed, "The grazed line")
        XCTAssertEqual(canvas.drawing.strokes.count, 2)

        // A circle of radius 100 around the writing's left half, begun below its right side and lifted
        // above it, open where the writing leaves it: closed, it holds a little over half the writing.
        let circleCenter = CGPoint(x: middle.x - 75, y: middle.y)
        let openLoop = stride(from: CGFloat(30), through: 330, by: 6).map { degrees in
            CGPoint(x: circleCenter.x + 100 * cos(degrees * .pi / 180), y: circleCenter.y + 100 * sin(degrees * .pi / 180))
        }
        canvas.selectsInk = true
        let selection = canvas.inkSelection
        try await drawLoopOfTouches(through: openLoop, in: window)
        try await waitUntil("the loop has selected") { selection.hasSelection || selection.isShowingLassoedArea }

        XCTAssertEqual(selection.selectedStrokeIndices, [0], "The partly circled writing is taken, the grazed line is not.")
        XCTAssertFalse(selection.isShowingLassoedArea, "Its menu has Cut, Copy and Duplicate.")
        let lassoedLoop = try XCTUnwrap(selection.lassoedLoop)
        XCTAssertEqual(lassoedLoop.first, lassoedLoop.last, "The loop is closed from where the hand lifted back to where it came down.")
        let writingSamples = writingStroke.path.interpolatedPoints(by: .distance(4)).map { point in point.location.applying(writingStroke.transform) }
        let enclosedShare = InkLasso.enclosedFraction(of: writingSamples, inLoop: lassoedLoop)
        XCTAssertGreaterThanOrEqual(enclosedShare, InkLasso.minimumEnclosedStrokeFraction)
        XCTAssertLessThan(enclosedShare, 0.6, "Under the old rule of 60 % the writing was left and the loop marked an empty area.")

        let layers = try XCTUnwrap(selection.shownLoopLayers, "The loop shows once the hand lifts.")
        let shownPath = try XCTUnwrap(layers.line.path)
        XCTAssertTrue(isClosed(shownPath), "It shows closed.")
        XCTAssertNil(layers.line.fillColor, "Around a selection it is not tinted, as a marked area is.")
        XCTAssertNotNil(selection.selectionFrame)
        attachScreenshot(of: window, named: "Open loop closed around partly circled writing")

        // Dragging the selection leaves the loop behind; ending the selection removes it.
        selection.selectionDragDidBegin()
        XCTAssertNil(selection.shownLoopLayers, "The frame carries the selection away from where the loop was drawn.")
        selection.clearSelection()
        XCTAssertEqual(canvas.drawing.strokes.count, 2, "Ending the drag puts the strokes back.")
        XCTAssertNil(selection.shownLoopLayers)
    }

    // MARK: Helpers

    /// A finger along points of the window, not returning to where it came down, through UIKit's
    /// event path, so the lasso's own recognizer receives it.
    private func drawLoopOfTouches(through windowPoints: [CGPoint], in window: UIWindow) async throws {
        let touches = SynthesizedTouches(window: window)
        touches.begin(at: [windowPoints[0]])
        try await SynthesizedStrokes.waitForPageToDraw(milliseconds: 16)
        for (start, end) in zip(windowPoints, windowPoints.dropFirst()) {
            for point in SynthesizedStrokes.line(from: start, to: end, steps: 3).dropFirst() {
                touches.moveTo([point])
                try await SynthesizedStrokes.waitForPageToDraw(milliseconds: 16)
            }
        }
        touches.end()
    }

    private func isClosed(_ path: CGPath) -> Bool {
        var hasCloseElement = false
        path.applyWithBlock { element in
            if element.pointee.type == .closeSubpath { hasCloseElement = true }
        }
        return hasCloseElement
    }

    private func attachScreenshot(of window: UIWindow, named name: String) {
        let screenshot = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func openPageWithCanvas() async throws -> (PDFSession, PDFPageCanvasView) {
        let vault = try TemporaryVault.make(prefix: "LassoClosing", for: self)
        let location = try vault.writeFile("Lasso.pdf", data: PDFTemplateGenerator.documentData(paper: PaperSpecification(template: .blank)))
        let session = try await PDFSession.open(location)
        let controller = UIHostingController(rootView: AnyView(NavigationStack { PDFPane(session: session, resolveConflict: { _ in }) }))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()
        windows.append(window)
        let page = try XCTUnwrap(session.document.page(at: 0))
        func coordinator() -> PDFAnnotationCoordinator? { (session.pdfView as? GraphitePDFDisplayView)?.annotationCoordinator }
        try await waitUntil("the page has its canvas") { coordinator()?.editingCanvas(for: page) != nil }
        return (session, try XCTUnwrap(coordinator()?.editingCanvas(for: page)))
    }
}
#endif
