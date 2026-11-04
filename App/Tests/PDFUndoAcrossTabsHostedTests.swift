/**
 * File: PDFUndoAcrossTabsHostedTests.swift
 * ----------------------------------------
 * Layer: Tests
 * Description: Hosted tests of Undo on a PDF page written on while its stored ink was decoded, across a switch to
 *              another PDF's tab and back, and with a stroke its history was not told of: every step goes back
 *              stroke by stroke, and comes forward again, with no message (HUNT-005).
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
import GraphiteIndex
@testable import GraphiteUI

/// The owner's report of 2026-11-04, on the iPad with a Release build of `fb9d88b7`: Q7.pdf, opened in a tab after
/// Q6.pdf, written on with the pen in two colors, and Undo said "The ink on this page changed in a way this step does
/// not know, so it was not undone." Undo is followed here through what that page met that day: ink decoded while it
/// was written on (HUNT-307), the PDF's view kept while another PDF's tab was in front and shown again (HUNT-308),
/// and a stroke on the canvas its history was not told of. Nothing here plays sound.
@MainActor
final class PDFUndoAcrossTabsHostedTests: XCTestCase {
    private static let storedStrokeCount = 120

    private var scene: UIWindowScene {
        get throws { try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first) }
    }

    private func stroke(atHeight height: CGFloat, creationSeconds: TimeInterval) -> PKStroke {
        let points = (0..<12).map { pointIndex in
            PKStrokePoint(location: CGPoint(x: 60 + CGFloat(pointIndex) * 10, y: height), timeOffset: Double(pointIndex) / 120,
                          size: CGSize(width: 3, height: 3), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }
        return PKStroke(ink: PKInk(.pen, color: .black), path: PKStrokePath(controlPoints: points, creationDate: Date(timeIntervalSince1970: creationSeconds)))
    }

    /// A vault with two eight-page PDFs, Q6 and Q7, open in two tabs, Q7 in front and written on.
    private func workspace(named name: String) async throws -> (WorkspaceModel, PDFSession) {
        let directory = try TemporaryVault.make(prefix: name, for: self).root
        for fileName in ["Q6.pdf", "Q7.pdf"] {
            let pages = try PDFTemplateGenerator.documentData(paper: PaperSpecification(template: .blank), pageCount: 8)
            try pages.write(to: directory.appendingPathComponent(fileName))
        }
        let workspace = WorkspaceModel()
        workspace.folderAccess = FolderAccess(root: directory)
        workspace.store = VaultStore(root: directory)
        workspace.index = try VaultIndex(databaseURL: directory.appendingPathComponent("index.sqlite"))
        await workspace.open(try VaultPath("Q6.pdf"))
        await workspace.open(try VaultPath("Q7.pdf"), placement: .newTab)
        let session = try XCTUnwrap(workspace.pdfSession)
        session.isWriting = true
        return (workspace, session)
    }

    private func host(_ workspace: WorkspaceModel) throws -> UIWindow {
        let controller = UIHostingController(rootView: GraphiteRootView(workspace: workspace))
        controller.traitOverrides.horizontalSizeClass = .regular
        let window = UIWindow(windowScene: try scene)
        window.frame = try scene.effectiveGeometry.coordinateSpace.bounds
        window.rootViewController = controller
        window.makeKeyAndVisible()
        return window
    }

    /// A stroke as PencilKit reports one: the tool's use begins, the drawing gains the stroke, the use ends.
    private func draw(_ stroke: PKStroke, on canvas: PDFPageCanvasView, reportedTo coordinator: PDFAnnotationCoordinator) {
        coordinator.canvasViewDidBeginUsingTool(canvas)
        canvas.drawing = PKDrawing(strokes: canvas.drawing.strokes + [stroke])
        coordinator.canvasViewDidEndUsingTool(canvas)
    }

    /// The history groups what happens in one turn of the run loop into one step; a person's strokes come in turns of their own.
    private func endTurn(of session: PDFSession) async throws {
        try await waitUntil("the turn's step is closed") { session.undoManager.groupingLevel == 0 }
    }

    func testUndoGoesBackStrokeByStrokeAfterInkDecodedWhileWrittenOnAndAnotherTab() async throws {
        let (workspace, session) = try await workspace(named: "UndoAcrossTabs")
        let window = try host(workspace)
        defer { window.isHidden = true; window.rootViewController = nil }
        try await waitUntil("Q7 shows") { (session.pdfView as? GraphitePDFDisplayView)?.window === window }
        let pdfView = try XCTUnwrap(session.pdfView as? GraphitePDFDisplayView)
        let coordinator = try XCTUnwrap(pdfView.annotationCoordinator)
        try await waitUntil("Q7 is written on") { coordinator.isWriting }

        // The last page, off screen, holds ink, as a file written on before does, and its canvas is made, which decodes
        // that ink away from the main actor.
        let page = try XCTUnwrap(session.document.page(at: 7))
        let storedDrawing = PKDrawing(strokes: (0..<Self.storedStrokeCount).map { strokeIndex in
            stroke(atHeight: 20 + CGFloat(strokeIndex) * 5, creationSeconds: 1_000 + TimeInterval(strokeIndex))
        })
        let coordinates = try PageCoordinates(cropBox: page.bounds(for: .cropBox), overlaySize: page.bounds(for: .cropBox).size)
        var tracker = PDFPageInkTracker(group: PDFInkGroups.newGroup(on: page))
        try session.apply(.updateInk(tracker.update(for: storedDrawing, pageIndex: 7, coordinates: coordinates)))
        let overlay = try XCTUnwrap(coordinator.pdfView(pdfView, overlayViewFor: page) as? PDFPageOverlayView)
        let canvas = overlay.canvas
        XCTAssertTrue(canvas.isRestoringStoredInk, "The page's ink is still decoded")

        // A stroke while it is decoded, then one once it is shown.
        let newStrokes = (0..<5).map { strokeIndex in stroke(atHeight: 700 + CGFloat(strokeIndex) * 10, creationSeconds: 9_000 + TimeInterval(strokeIndex)) }
        draw(newStrokes[0], on: canvas, reportedTo: coordinator)
        try await waitUntil("the stored ink is shown") { !canvas.isRestoringStoredInk }
        try await endTurn(of: session)
        draw(newStrokes[1], on: canvas, reportedTo: coordinator)
        try await endTurn(of: session)
        XCTAssertEqual(canvas.drawing.strokes.count, Self.storedStrokeCount + 2)

        // Q6's tab and back: Q7 comes back with its view kept, or, when Q6's view was kept first and took its place, with
        // a new view, whose canvas reads the page's ink from its record.
        let firstTab = try XCTUnwrap(workspace.layout.tabID(showing: try VaultPath("Q6.pdf")))
        let secondTab = try XCTUnwrap(workspace.layout.tabID(showing: try VaultPath("Q7.pdf")))
        workspace.activateTab(firstTab)
        try await waitUntil("Q6 is in front") { pdfView.window == nil && workspace.pdfSession?.location.lastPathComponent == "Q6.pdf" }
        workspace.activateTab(secondTab)
        try await waitUntil("Q7 is in front again") { session.pdfView?.window === window }
        let shownPDFView = try XCTUnwrap(session.pdfView as? GraphitePDFDisplayView)
        let shownCoordinator = try XCTUnwrap(shownPDFView.annotationCoordinator)
        XCTAssertFalse(shownCoordinator.isDetached, "The view shown has a coordinator that still records and saves its ink")
        var heldOverlays = [overlay]
        let pageCanvas: PDFPageCanvasView
        if let keptCanvas = shownCoordinator.canvasesByPage[ObjectIdentifier(page)] {
            pageCanvas = keptCanvas
        } else {
            let newOverlay = try XCTUnwrap(shownCoordinator.pdfView(shownPDFView, overlayViewFor: page) as? PDFPageOverlayView)
            heldOverlays.append(newOverlay)
            pageCanvas = newOverlay.canvas
        }
        print("UNDO-ACROSS-TABS: view kept \(shownPDFView === pdfView), canvas kept \(pageCanvas === canvas), overlays held \(heldOverlays.count)")
        try await waitUntil("the page's canvas has its ink") { !pageCanvas.isRestoringStoredInk && pageCanvas.delegate != nil }
        XCTAssertEqual(pageCanvas.drawing.strokes.count, Self.storedStrokeCount + 2, "Every stroke drawn before the switch is on the page's canvas")

        draw(newStrokes[2], on: pageCanvas, reportedTo: shownCoordinator)
        try await endTurn(of: session)
        draw(newStrokes[3], on: pageCanvas, reportedTo: shownCoordinator)
        try await endTurn(of: session)
        // A stroke the canvas shows that its history was not told of, as when its delegate was another for a moment.
        pageCanvas.delegate = nil
        pageCanvas.drawing = PKDrawing(strokes: pageCanvas.drawing.strokes + [newStrokes[4]])
        pageCanvas.delegate = shownCoordinator
        attachScreenshot(of: window, named: "Q7 written on across the switch")

        // Undo takes back the stroke shown last first, then each before it, and Redo brings them back the same way.
        for remainingNewStrokes in stride(from: 4, through: 0, by: -1) {
            XCTAssertTrue(session.undoAvailability.canUndo, "A step to undo for each stroke, \(remainingNewStrokes) left")
            session.undoAvailability.undo()
            XCTAssertNil(session.errorMessage, "Undo down to \(remainingNewStrokes) new strokes")
            XCTAssertEqual(pageCanvas.drawing.strokes.count, Self.storedStrokeCount + remainingNewStrokes, "Undo takes back one stroke")
            let lastStrokeLeft = remainingNewStrokes == 0 ? storedDrawing.strokes.last : newStrokes[remainingNewStrokes - 1]
            XCTAssertEqual(pageCanvas.drawing.strokes.last?.path.creationDate, lastStrokeLeft?.path.creationDate, "The stroke shown last went first")
            session.errorMessage = nil
        }
        XCTAssertFalse(session.undoAvailability.canUndo, "Reading the stored ink was no step")
        for redoneNewStrokes in 1...5 {
            session.undoAvailability.redo()
            XCTAssertNil(session.errorMessage, "Redo up to \(redoneNewStrokes) new strokes")
            XCTAssertEqual(pageCanvas.drawing.strokes.count, Self.storedStrokeCount + redoneNewStrokes, "Redo brings one stroke back")
            session.errorMessage = nil
        }
        XCTAssertEqual(page.annotations.filter { annotation in annotation.type == "Ink" }.count, Self.storedStrokeCount + 5, "The page has every stroke once")
    }

    private func attachScreenshot(of window: UIWindow, named name: String) {
        let screenshot = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
        let attachment = XCTAttachment(image: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
#endif
