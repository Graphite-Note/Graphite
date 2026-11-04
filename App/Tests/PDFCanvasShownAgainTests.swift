/**
 * File: PDFCanvasShownAgainTests.swift
 * ------------------------------------
 * Layer: Tests
 * Description: Hosted tests of the main-thread work when writing starts on a PDF: a page PDFKit shows again after its
 *              canvas was let go keeps the PDF's view and records its first stroke, and the first stroke on a page reads
 *              and decodes nothing (HUNT-313).
 *
 * Authors: Bahey Shalash
 * Version: 0.2
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

/// The owner's report of 2026-11-04: "when I start writing, it freezes quite frequently". Counted here: how often the
/// PDF's view is built again, how many pages' ink is decoded, and whether the first stroke is recorded, when PDFKit
/// shows a page again with the overlay it kept after Graphite let go of the page's canvas (more than six other pages
/// shown, or a memory warning). Until 2026-11-04 the health check found that canvas "not its own" within a second and
/// built the whole view again: every page shown decoded again, the zoom back to fitting, a blank page meanwhile, and
/// the strokes on that canvas unrecorded until then. Nothing here plays sound.
@MainActor
final class PDFCanvasShownAgainTests: XCTestCase {
    private static let storedStrokeCount = 60
    private var temporaryLocations: [URL] = []

    override func tearDown() async throws {
        for location in temporaryLocations { try? FileManager.default.removeItem(at: location) } // A file left in the temporary folder harms nothing.
        temporaryLocations = []
    }

    private func stroke(atHeight height: CGFloat, creationSeconds: TimeInterval) -> PKStroke {
        let points = (0..<12).map { pointIndex in
            PKStrokePoint(location: CGPoint(x: 60 + CGFloat(pointIndex) * 10, y: height), timeOffset: Double(pointIndex) / 120, size: CGSize(width: 3, height: 3),
                          opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }
        return PKStroke(ink: PKInk(.pen, color: .black), path: PKStrokePath(controlPoints: points, creationDate: Date(timeIntervalSince1970: creationSeconds)))
    }

    private func storedDrawing() -> PKDrawing {
        PKDrawing(strokes: (0..<Self.storedStrokeCount).map { strokeIndex in
            stroke(atHeight: 20 + CGFloat(strokeIndex) * 5, creationSeconds: 1_000 + TimeInterval(strokeIndex))
        })
    }

    private func inkAnnotationCount(on page: PDFPage) -> Int {
        page.annotations.filter { annotation in annotation.type == "Ink" }.count
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

    /// An eight-page notebook written on in a pane, its first page holding stored ink, with that page's canvas ready.
    private func hostedNotebookWithInk(named name: String) async throws
        -> (session: PDFSession, pdfView: GraphitePDFDisplayView, coordinator: PDFAnnotationCoordinator, page: PDFPage, window: UIWindow) {
        let location = try makeHostedBlankNotebook(named: name, pageCount: 8)
        temporaryLocations.append(location)
        let session = try await PDFSession.open(location)
        let page = try XCTUnwrap(session.document.page(at: 0))
        let coordinates = try PageCoordinates(cropBox: page.bounds(for: .cropBox), overlaySize: page.bounds(for: .cropBox).size)
        var tracker = PDFPageInkTracker(group: PDFInkGroups.newGroup(on: page))
        try session.apply(.updateInk(tracker.update(for: storedDrawing(), pageIndex: 0, coordinates: coordinates)))
        try await session.save()
        session.isWriting = true
        let controller = UIHostingController(rootView: NavigationStack { PDFPane(session: session, resolveConflict: { _ in }) })
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        window.rootViewController = controller
        window.makeKeyAndVisible()
        // SwiftUI makes the PDF's view at the window's first layout pass, after this returns, not inside it.
        try await waitUntil("the pane made the PDF's view") { (session.pdfView as? GraphitePDFDisplayView)?.annotationCoordinator != nil }
        let pdfView = try XCTUnwrap(session.pdfView as? GraphitePDFDisplayView)
        let coordinator = try XCTUnwrap(pdfView.annotationCoordinator)
        try await waitUntil("the first page's ink is on its canvas") {
            coordinator.canvasesByPage[ObjectIdentifier(page)].map { canvas in
                canvas.delegate === coordinator && !canvas.isRestoringStoredInk && canvas.drawing.strokes.count == Self.storedStrokeCount
            } ?? false
        }
        return (session, pdfView, coordinator, page, window)
    }

    /// Lets go of the page's canvas as Graphite does once more than six other pages were shown, or at a memory warning,
    /// while PDFKit keeps the page's view and its overlay; then PDFKit shows that overlay again.
    private func letGoOfTheCanvasAndShowItsOverlayAgain(of page: PDFPage, coordinator: PDFAnnotationCoordinator, pdfView: GraphitePDFDisplayView)
        async throws -> PDFPageOverlayView {
        let canvas = try XCTUnwrap(coordinator.canvasesByPage[ObjectIdentifier(page)])
        let overlay = try XCTUnwrap(canvas.overlayView)
        coordinator.pdfView(pdfView, willEndDisplayingOverlayView: overlay, for: page)
        NotificationCenter.default.post(name: UIApplication.didReceiveMemoryWarningNotification, object: nil)
        try await waitUntil("the page's canvas was let go") { coordinator.canvasesByPage[ObjectIdentifier(page)] == nil }
        coordinator.pdfView(pdfView, willDisplayOverlayView: overlay, for: page)
        return overlay
    }

    /// A page shown again with its kept overlay, nothing changed meanwhile: its canvas is the page's own again at once,
    /// with no decode, the view is not built again, and the first stroke on it is recorded and undoable.
    func testAPageShownAgainAfterItsCanvasWasLetGoKeepsTheViewAndRecordsTheFirstStroke() async throws {
        let (session, pdfView, coordinator, page, window) = try await hostedNotebookWithInk(named: "ShownAgain")
        defer { window.isHidden = true; window.rootViewController = nil }
        let viewGeneration = session.viewGeneration
        let decodesBefore = coordinator.storedInkDecodeCount

        let overlay = try await letGoOfTheCanvasAndShowItsOverlayAgain(of: page, coordinator: coordinator, pdfView: pdfView)
        let canvas = overlay.canvas
        XCTAssertTrue(coordinator.canvasesByPage[ObjectIdentifier(page)] === canvas, "The canvas shown is the page's own again")
        XCTAssertTrue(canvas.delegate === coordinator, "and records its changes")
        XCTAssertTrue(canvas.isUserInteractionEnabled, "and takes touches")
        XCTAssertEqual(coordinator.storedInkDecodeCount, decodesBefore, "Nothing of the page changed: its ink is not decoded again")
        XCTAssertEqual(canvas.drawing.strokes.count, Self.storedStrokeCount)

        let repairs = coordinator.repairCanvases()
        XCTAssertFalse(repairs.contains { repair in repair.contains("built again") }, "The health check builds nothing again: \(repairs)")
        XCTAssertEqual(session.viewGeneration, viewGeneration, "The PDF's view is the same one")

        let annotationsBefore = inkAnnotationCount(on: page)
        coordinator.canvasViewDidBeginUsingTool(canvas)
        canvas.drawing = PKDrawing(strokes: canvas.drawing.strokes + [stroke(atHeight: 700, creationSeconds: 9_000)])
        coordinator.canvasViewDidEndUsingTool(canvas)
        try await waitUntil("the first stroke is recorded") { self.inkAnnotationCount(on: page) == annotationsBefore + 1 }
        XCTAssertTrue(session.undoAvailability.canUndo, "The stroke is an undo step")
        XCTAssertEqual(coordinator.storedInkDecodeCount, decodesBefore, "The first stroke decodes nothing")
        XCTAssertEqual(coordinator.everyStrokeComparisonCount, 0, "and compares no stored strokes")
        XCTAssertEqual(session.viewGeneration, viewGeneration)
        attachScreenshot(of: window, named: "A page shown again, its first stroke recorded")
    }

    /// The same page shown again after its ink changed while its canvas was let go (undo, or another view of the PDF):
    /// the canvas reads the page's ink again, once, and still nothing is built again.
    func testAPageShownAgainAfterItsInkChangedReadsItAgainOnce() async throws {
        let (session, pdfView, coordinator, page, window) = try await hostedNotebookWithInk(named: "ShownAgainChanged")
        defer { window.isHidden = true; window.rootViewController = nil }
        let viewGeneration = session.viewGeneration
        let canvas = try XCTUnwrap(coordinator.canvasesByPage[ObjectIdentifier(page)])
        let overlay = try XCTUnwrap(canvas.overlayView)
        coordinator.pdfView(pdfView, willEndDisplayingOverlayView: overlay, for: page)
        NotificationCenter.default.post(name: UIApplication.didReceiveMemoryWarningNotification, object: nil)
        try await waitUntil("the page's canvas was let go") { coordinator.canvasesByPage[ObjectIdentifier(page)] == nil }

        // Another stroke reaches the page while no canvas covers it.
        let coordinates = try PageCoordinates(cropBox: page.bounds(for: .cropBox), overlaySize: page.bounds(for: .cropBox).size)
        let storedGroup = try XCTUnwrap(PDFInkGroups.editableGroup(on: page))
        var tracker = try XCTUnwrap(PDFPageInkTracker.restoring(storedGroup)).tracker
        let changedDrawing = PKDrawing(strokes: storedDrawing().strokes + [stroke(atHeight: 720, creationSeconds: 9_500)])
        try session.apply(.updateInk(tracker.update(for: changedDrawing, pageIndex: 0, coordinates: coordinates)))
        let decodesBefore = coordinator.storedInkDecodeCount

        coordinator.pdfView(pdfView, willDisplayOverlayView: overlay, for: page)
        try await waitUntil("the canvas has the page's ink as it is now") {
            !canvas.isRestoringStoredInk && canvas.delegate === coordinator && canvas.drawing.strokes.count == Self.storedStrokeCount + 1
        }
        XCTAssertTrue(coordinator.canvasesByPage[ObjectIdentifier(page)] === canvas)
        XCTAssertEqual(coordinator.storedInkDecodeCount, decodesBefore + 1, "The changed ink is decoded once")
        XCTAssertEqual(canvas.recordedDrawing.strokes.count, Self.storedStrokeCount + 1, "and taken as recorded, not as a new edit")
        XCTAssertFalse(coordinator.repairCanvases().contains { repair in repair.contains("built again") })
        XCTAssertEqual(session.viewGeneration, viewGeneration, "The PDF's view is the same one")
    }

    /// The first stroke on a page whose ink is on its canvas, right after writing begins: no record read, no decode, no
    /// stroke comparison, no view built again, one annotation added and one undo step.
    func testTheFirstStrokeAfterWritingBeginsReadsAndDecodesNothing() async throws {
        let (session, _, coordinator, page, window) = try await hostedNotebookWithInk(named: "FirstStroke")
        defer { window.isHidden = true; window.rootViewController = nil }
        session.isWriting = false
        try await waitUntil("the PDF is read") { !coordinator.isWriting }
        let canvas = try XCTUnwrap(coordinator.canvasesByPage[ObjectIdentifier(page)])
        let viewGeneration = session.viewGeneration
        let decodesBefore = coordinator.storedInkDecodeCount
        let comparisonsBefore = coordinator.everyStrokeComparisonCount
        let annotationsBefore = inkAnnotationCount(on: page)

        session.isWriting = true
        try await waitUntil("the canvas takes touches") { coordinator.isWriting && canvas.isUserInteractionEnabled }
        coordinator.canvasViewDidBeginUsingTool(canvas)
        canvas.drawing = PKDrawing(strokes: canvas.drawing.strokes + [stroke(atHeight: 740, creationSeconds: 9_900)])
        coordinator.canvasViewDidEndUsingTool(canvas)
        try await waitUntil("the stroke is recorded") { self.inkAnnotationCount(on: page) == annotationsBefore + 1 }
        XCTAssertEqual(coordinator.storedInkDecodeCount, decodesBefore, "No decode")
        XCTAssertEqual(coordinator.everyStrokeComparisonCount, comparisonsBefore, "No comparison of every stroke")
        XCTAssertEqual(session.viewGeneration, viewGeneration, "No view built again")
        XCTAssertTrue(session.undoAvailability.canUndo)
    }
}
#endif
