/**
 * File: PDFPageInkReadingTests.swift
 * ----------------------------------
 * Layer: Tests
 * Description: How much of a page's ink is read on the main thread as the page is shown and as it is
 *              saved, counted, since scrolling or pausing on a full page must not stutter; and the strokes
 *              drawn while that ink is decoded, which are kept.
 *
 * Authors: Bahey Shalash
 * Version: 0.3
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

/// An annotation that counts how often its Graphite keys are read on the main thread, to count
/// the walks over a page. PDFKit reads annotations on its own queues too, as it analyzes a page
/// it has drawn; those stutter nothing, and asserting the main actor there stopped the process.
private final class CountingInkAnnotation: PDFAnnotation {
    @MainActor static var readsByKey: [String: Int] = [:]

    override func value(forAnnotationKey key: PDFAnnotationKey) -> Any? {
        if Thread.isMainThread { MainActor.assumeIsolated { Self.readsByKey[key.rawValue, default: 0] += 1 } }
        return super.value(forAnnotationKey: key)
    }
}

/// How much of a page's ink is read on the main thread as the page is shown and as it is saved,
/// counted, since scrolling or pausing on a full page must not stutter.
@MainActor
final class PDFPageInkReadingTests: XCTestCase {
    private static let strokeCount = 120
    private var temporaryLocations: [URL] = []

    override func tearDown() async throws {
        CountingInkAnnotation.readsByKey = [:]
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

    private func drawing(strokeCount: Int = PDFPageInkReadingTests.strokeCount) -> PKDrawing {
        PKDrawing(strokes: (0..<strokeCount).map { strokeIndex in stroke(atHeight: 20 + CGFloat(strokeIndex) * 5, creationSeconds: 1_000 + TimeInterval(strokeIndex)) })
    }

    private func canvases(in view: UIView) -> [PDFPageCanvasView] {
        view.subviews.flatMap { child in ((child as? PDFPageCanvasView).map { [$0] } ?? []) + canvases(in: child) }
    }

    /// A notebook of `pageCount` pages shown in a pane, with its first page's canvas ready.
    private func hostedNotebook(named name: String, pageCount: Int) async throws -> (PDFSession, GraphitePDFDisplayView, UIViewController, UIWindow) {
        let location = try makeHostedBlankNotebook(named: name, pageCount: pageCount)
        temporaryLocations.append(location)
        let session = try await PDFSession.open(location)
        let controller = UIHostingController(rootView: NavigationStack { PDFPane(session: session, resolveConflict: { _ in }) })
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()
        try await waitUntil("the first page's canvas is shown") { self.canvases(in: controller.view).contains { $0.window != nil && $0.delegate != nil } }
        return (session, try XCTUnwrap(session.pdfView as? GraphitePDFDisplayView), controller, window)
    }

    /// Puts ink on a page, in annotations that count their reads, as a file holds it.
    private func addCountingInk(to page: PDFPage, drawing: PKDrawing) {
        let names = drawing.strokes.indices.map { strokeIndex in "stroke-\(strokeIndex)" }
        for (strokeIndex, name) in names.enumerated() {
            let annotation = CountingInkAnnotation(bounds: CGRect(x: 40, y: CGFloat(strokeIndex) * 5, width: 200, height: 5), forType: .ink, withProperties: nil)
            annotation.setValue(PDFInkGroups.defaultGroup, forAnnotationKey: PDFPageManager.groupKey)
            annotation.setValue(name, forAnnotationKey: PDFPageManager.annotationNameKey)
            if strokeIndex == 0 {
                annotation.setValue(drawing.dataRepresentation().base64EncodedString(), forAnnotationKey: PDFPageManager.drawingKey)
                annotation.setValue("\(names.count):" + names.joined(separator: ","), forAnnotationKey: PDFPageManager.strokeNamesKey)
            }
            page.addAnnotation(annotation)
        }
        CountingInkAnnotation.readsByKey = [:]
    }

    /// HUNT-015: a page shown read its record on the main thread twice, decoding its base64 and
    /// names both times, and walked its annotations 6 times: now once, and 3 times.
    func testShowingAFullPageReadsItsRecordOnceAndWalksItsAnnotationsThreeTimes() async throws {
        let (session, pdfView, _, window) = try await hostedNotebook(named: "ReadOnce", pageCount: 8)
        defer { window.isHidden = true; window.rootViewController = nil }
        let page = try XCTUnwrap(session.document.page(at: 7))
        addCountingInk(to: page, drawing: drawing())
        let groupReadsPerWalk = Self.strokeCount

        pdfView.go(to: page)
        try await waitUntil("the page's ink is restored") {
            self.canvases(in: pdfView).first { $0.page === page }.map { canvas in canvas.delegate != nil && !canvas.isRestoringStoredInk && canvas.drawing.strokes.count == Self.strokeCount } ?? false
        }
        let canvas = try XCTUnwrap(canvases(in: pdfView).first { $0.page === page })
        XCTAssertEqual(CountingInkAnnotation.readsByKey[PDFPageManager.drawingKey.rawValue], 1, "The record is read once")
        XCTAssertEqual(CountingInkAnnotation.readsByKey[PDFPageManager.strokeNamesKey.rawValue], 1)
        let walks = (CountingInkAnnotation.readsByKey[PDFPageManager.groupKey.rawValue] ?? 0) / groupReadsPerWalk
        XCTAssertLessThanOrEqual(walks, 3, "Read once, annotations shown under the page, annotations hidden under the canvas")
        XCTAssertFalse(page.annotations.contains { annotation in annotation.shouldDisplay }, "The canvas shows the ink")

        // Going from reading to writing changes nothing of the annotations: nothing walks them.
        CountingInkAnnotation.readsByKey = [:]
        session.isWriting = true
        try await waitUntil("the canvas takes touches") { canvas.isUserInteractionEnabled }
        XCTAssertEqual(CountingInkAnnotation.readsByKey[PDFPageManager.groupKey.rawValue] ?? 0, 0)
    }

    /// Undo or redo while a page's ink is decoded: the page shows what the undo left, not what
    /// was read before it. The count of the page's edits tells, without reading the record again.
    func testAnEditWhileAPagesInkIsDecodedIsNotLost() async throws {
        let (session, pdfView, _, window) = try await hostedNotebook(named: "EditWhileDecoding", pageCount: 8)
        defer { window.isHidden = true; window.rootViewController = nil }
        let page = try XCTUnwrap(session.document.page(at: 7))
        let coordinator = try XCTUnwrap(pdfView.annotationCoordinator)
        let fullDrawing = drawing()
        let coordinates = try PageCoordinates(cropBox: page.bounds(for: .cropBox), overlaySize: page.bounds(for: .cropBox).size)
        var tracker = PDFPageInkTracker(group: PDFInkGroups.newGroup(on: page))
        try session.apply(.updateInk(tracker.update(for: fullDrawing, pageIndex: 7, coordinates: coordinates)))

        let overlay = try XCTUnwrap(coordinator.pdfView(pdfView, overlayViewFor: page) as? PDFPageOverlayView)
        XCTAssertTrue(overlay.canvas.isRestoringStoredInk, "The decode is under way, away from the main thread")
        var shorterStrokes = fullDrawing.strokes
        shorterStrokes.removeLast()
        // In the same turn: the decode's result cannot have been taken yet.
        try session.apply(.updateInk(tracker.update(for: PKDrawing(strokes: shorterStrokes), pageIndex: 7, coordinates: coordinates)))

        try await waitUntil("the canvas has the ink") { !overlay.canvas.isRestoringStoredInk && overlay.canvas.delegate != nil }
        XCTAssertEqual(overlay.canvas.drawing.strokes.count, shorterStrokes.count, "What the edit left")
        XCTAssertEqual(overlay.canvas.recordedDrawing.strokes.count, shorterStrokes.count)
    }

    /// A page of the notebook with `drawing` stored on it, as a file holds it, and the overlay just
    /// made for it, whose canvas's decode of that ink is under way. The caller keeps the overlay,
    /// which holds the canvas.
    private func pageDecodingStoredInk(_ drawing: PKDrawing, in session: PDFSession, pdfView: GraphitePDFDisplayView)
        throws -> (page: PDFPage, overlay: PDFPageOverlayView, coordinator: PDFAnnotationCoordinator) {
        let page = try XCTUnwrap(session.document.page(at: 7))
        let coordinator = try XCTUnwrap(pdfView.annotationCoordinator)
        let coordinates = try PageCoordinates(cropBox: page.bounds(for: .cropBox), overlaySize: page.bounds(for: .cropBox).size)
        var tracker = PDFPageInkTracker(group: PDFInkGroups.newGroup(on: page))
        try session.apply(.updateInk(tracker.update(for: drawing, pageIndex: 7, coordinates: coordinates)))
        let overlay = try XCTUnwrap(coordinator.pdfView(pdfView, overlayViewFor: page) as? PDFPageOverlayView)
        return (page, overlay, coordinator)
    }

    private func inkAnnotationCount(on page: PDFPage) -> Int {
        page.annotations.filter { annotation in annotation.type == "Ink" }.count
    }

    private func creationDates(of drawing: PKDrawing) -> [Date] {
        drawing.strokes.map(\.path.creationDate)
    }

    /// HUNT-307: the canvas of a page coming on screen takes touches while its stored ink is
    /// decoded. A stroke drawn then waits for the ink, and one still under way when the ink
    /// arrives holds it back until it ends. The page then has the stored strokes followed by the
    /// new ones, the new ones are the only edit, so undo takes back just them, and the saved
    /// record keeps every stored stroke under its name, with the new ones once each.
    func testStrokesDrawnWhileAPagesInkIsDecodedComeAfterItAndAreTheOnlyEdit() async throws {
        let (session, pdfView, _, window) = try await hostedNotebook(named: "DrawWhileDecoding", pageCount: 8)
        defer { window.isHidden = true; window.rootViewController = nil }
        session.isWriting = true
        try await waitUntil("the PDF is written on") { pdfView.annotationCoordinator?.isWriting == true }
        let storedDrawing = drawing()
        let (page, overlay, coordinator) = try pageDecodingStoredInk(storedDrawing, in: session, pdfView: pdfView)
        let canvas = overlay.canvas
        let storedGroup = try XCTUnwrap(PDFInkGroups.editableGroup(on: page))
        XCTAssertTrue(canvas.isRestoringStoredInk, "The decode is under way")
        XCTAssertTrue(canvas.isUserInteractionEnabled, "The canvas takes touches meanwhile")
        XCTAssertTrue(canvas.delegate === coordinator, "and hears of its strokes")

        // In the same turn, so the decode's result cannot have been taken yet: one stroke drawn
        // and ended as PencilKit reports it, then a second one begun.
        let firstNewStroke = stroke(atHeight: 700, creationSeconds: 9_000)
        coordinator.canvasViewDidBeginUsingTool(canvas)
        canvas.drawing = PKDrawing(strokes: [firstNewStroke])
        coordinator.canvasViewDidEndUsingTool(canvas)
        coordinator.canvasViewDidBeginUsingTool(canvas)
        try await waitUntil("the decoded ink waits for the stroke under way") { canvas.heldStoredInk != nil }
        XCTAssertTrue(canvas.isRestoringStoredInk)
        XCTAssertEqual(creationDates(of: canvas.drawing), [firstNewStroke.path.creationDate], "Nothing replaced the canvas's drawing under the stroke")
        XCTAssertEqual(inkAnnotationCount(on: page), Self.strokeCount, "Nothing is recorded before the stored ink")

        let secondNewStroke = stroke(atHeight: 720, creationSeconds: 9_001)
        canvas.drawing = PKDrawing(strokes: canvas.drawing.strokes + [secondNewStroke])
        coordinator.canvasViewDidEndUsingTool(canvas)
        try await waitUntil("the stored ink is shown") { !canvas.isRestoringStoredInk }
        let expectedDates = creationDates(of: storedDrawing) + [firstNewStroke.path.creationDate, secondNewStroke.path.creationDate]
        XCTAssertEqual(creationDates(of: canvas.drawing), expectedDates, "The stored strokes, then the new ones")
        XCTAssertEqual(creationDates(of: canvas.recordedDrawing), expectedDates, "Recorded")
        XCTAssertEqual(inkAnnotationCount(on: page), Self.strokeCount + 2, "Each new stroke added once, no stored one again")
        XCTAssertEqual(canvas.inkTracker.group, storedGroup.group, "Added to the stored ink's group")

        try await session.save()
        let reopened = try XCTUnwrap(PDFDocument(url: session.location)?.page(at: 7))
        let savedGroup = try XCTUnwrap(PDFInkGroups.editableGroup(on: reopened), "The file's ink can be edited again")
        XCTAssertEqual(creationDates(of: try PKDrawing(data: savedGroup.record.drawingData)), expectedDates)
        XCTAssertEqual(Array(savedGroup.record.strokeNames.prefix(Self.strokeCount)), storedGroup.record.strokeNames, "Every stored stroke keeps its name")
        XCTAssertEqual(Set(savedGroup.record.strokeNames).count, Self.strokeCount + 2)
        XCTAssertEqual(inkAnnotationCount(on: reopened), Self.strokeCount + 2)

        try await waitUntil("the strokes are an undo step") { session.undoAvailability.canUndo }
        session.undoAvailability.undo()
        XCTAssertNil(session.errorMessage)
        XCTAssertEqual(creationDates(of: canvas.drawing), creationDates(of: storedDrawing), "Undo takes back the new strokes alone")
        XCTAssertEqual(inkAnnotationCount(on: page), Self.strokeCount)
        XCTAssertFalse(session.undoAvailability.canUndo, "Reading the stored ink was no edit")
    }

    /// HUNT-307: a save while the stored ink is still decoded reads it at once, so the strokes
    /// drawn meanwhile reach the file after the stored ones, and the late decode adds nothing.
    func testASaveWhileAPagesInkIsDecodedKeepsTheStrokesDrawnMeanwhile() async throws {
        let (session, pdfView, _, window) = try await hostedNotebook(named: "SaveWhileDecoding", pageCount: 8)
        defer { window.isHidden = true; window.rootViewController = nil }
        session.isWriting = true
        try await waitUntil("the PDF is written on") { pdfView.annotationCoordinator?.isWriting == true }
        let storedDrawing = drawing()
        let (page, overlay, _) = try pageDecodingStoredInk(storedDrawing, in: session, pdfView: pdfView)
        let canvas = overlay.canvas
        let newStroke = stroke(atHeight: 700, creationSeconds: 9_000)
        canvas.drawing = PKDrawing(strokes: [newStroke])

        try await session.save()
        let expectedDates = creationDates(of: storedDrawing) + [newStroke.path.creationDate]
        XCTAssertFalse(canvas.isRestoringStoredInk, "The save read the stored ink at once")
        XCTAssertEqual(creationDates(of: canvas.drawing), expectedDates)
        let reopened = try XCTUnwrap(PDFDocument(url: session.location)?.page(at: 7))
        let savedGroup = try XCTUnwrap(PDFInkGroups.editableGroup(on: reopened))
        XCTAssertEqual(creationDates(of: try PKDrawing(data: savedGroup.record.drawingData)), expectedDates)
        XCTAssertEqual(inkAnnotationCount(on: reopened), Self.strokeCount + 1)
        XCTAssertEqual(inkAnnotationCount(on: page), Self.strokeCount + 1)
    }

    /// HUNT-017: every save fingerprinted every stroke of all up to 8 kept canvases on the main
    /// thread: now none, for ink already recorded, and the file still holds its record.
    func testASaveComparesNoStrokesOfRecordedInkAndStillWritesItsRecord() async throws {
        let (session, pdfView, controller, window) = try await hostedNotebook(named: "SaveCompares", pageCount: 2)
        defer { window.isHidden = true; window.rootViewController = nil }
        session.isWriting = true
        let coordinator = try XCTUnwrap(pdfView.annotationCoordinator)
        let canvas = try XCTUnwrap(canvases(in: controller.view).first { $0.window != nil && $0.delegate != nil })
        canvas.drawing = drawing()
        try await waitUntil("the strokes are recorded") { canvas.recordedDrawing.strokes.count == Self.strokeCount && !canvas.mayHoldUnrecordedInk }
        let comparisonsBefore = coordinator.everyStrokeComparisonCount

        try await session.save()
        XCTAssertEqual(coordinator.everyStrokeComparisonCount, comparisonsBefore, "Nothing touched the canvas since its ink was recorded")
        XCTAssertFalse(canvas.inkTracker.hasDeferredEditableRecord)
        let reopened = try XCTUnwrap(PDFDocument(url: session.location)?.page(at: canvas.page.map { page in session.document.index(for: page) } ?? 0))
        let savedGroup = try XCTUnwrap(PDFInkGroups.editableGroup(on: reopened), "The file's ink can be edited again")
        XCTAssertEqual(try PKDrawing(data: savedGroup.record.drawingData).strokes.count, Self.strokeCount)
        XCTAssertEqual(savedGroup.record.strokeNames.count, Self.strokeCount)

        // A change that never reached the PDF is still found at the next save.
        canvas.showWithoutRecording(PKDrawing(strokes: canvas.drawing.strokes + [stroke(atHeight: 700, creationSeconds: 9_000)]))
        try await session.save()
        XCTAssertEqual(coordinator.everyStrokeComparisonCount, comparisonsBefore + 1)
        XCTAssertEqual(canvas.recordedDrawing.strokes.count, Self.strokeCount + 1, "Recorded before the save")
    }
}
#endif
