/**
 * File: ErasedInkStaysErasedHostedTests.swift
 * -------------------------------------------
 * Layer: Tests
 * Description: Hosted tests of ink erased on a PDF page with Graphite's fine eraser and with PencilKit's pixel eraser:
 *              each erase takes the ink from under the tip, the eraser follows the next touch, and the erased ink
 *              stays erased on the canvas, in the page's annotations and record, in the saved file, across another
 *              tab and back and after the PDF is closed and opened again (HUNT-326).
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 05/11/2026
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

/// The owner's recording of 2026-11-05 (IMG_7059, the iPad Pro 11-inch, iPadOS 27): on page 5 of 16_Interconnects.pdf,
/// with the bar's pixel eraser, a tick under "Interconnection network" stayed after every pass of the Pencil over it,
/// and the eraser's circle stayed still on the line below it, until the tab of 16_Interconnects.pptx and back, after
/// which the eraser followed the Pencil and erased. Followed here: two pen strokes on a page, saved, one cut and then
/// erased whole by Graphite's eraser, the other by PencilKit's at a width it makes, the PDF's other tab and back after
/// the cut and after the whole erase, a save, and the PDF closed and opened again; every touch of the eraser before and
/// after another tab; and a hand resting on the page while the Pencil erases. Nothing here plays sound.
@MainActor
final class ErasedInkStaysErasedHostedTests: XCTestCase {
    private var scene: UIWindowScene {
        get throws { try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first) }
    }

    private func pen() -> PencilToolSelection {
        var preset = InkPreset(ink: .monoline)
        preset.width = 2
        return PencilToolSelection(kind: .ink, preset: preset, erasesWholeStrokes: true, eraserWidth: 6, isRulerActive: false)
    }

    private func pixelEraser(width: Double) -> PencilToolSelection {
        PencilToolSelection(kind: .eraser, preset: InkPreset(ink: .monoline), erasesWholeStrokes: false, eraserWidth: width, isRulerActive: false)
    }

    /// A vault with the lecture's PDF and its slides, open in two tabs as the owner had them, the PDF in front and written on.
    private func workspace(named name: String) async throws -> (WorkspaceModel, PDFSession) {
        let directory = try TemporaryVault.make(prefix: name, for: self).root
        try PDFTemplateGenerator.documentData(paper: PaperSpecification(template: .blank), pageCount: 4)
            .write(to: directory.appendingPathComponent("Lecture.pdf"))
        try Data("PK slides".utf8).write(to: directory.appendingPathComponent("Lecture.pptx"))
        let workspace = WorkspaceModel()
        workspace.folderAccess = FolderAccess(root: directory)
        workspace.store = VaultStore(root: directory)
        workspace.index = try VaultIndex(databaseURL: directory.appendingPathComponent("index.sqlite"))
        await workspace.open(try VaultPath("Lecture.pdf"))
        await workspace.open(try VaultPath("Lecture.pptx"), placement: .newTab)
        let pdfTab = try XCTUnwrap(workspace.layout.tabID(showing: try VaultPath("Lecture.pdf")))
        workspace.activateTab(pdfTab)
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

    /// The first page's canvas of the PDF in front, once it shows the page's ink and records its changes.
    private func shownCanvas(of session: PDFSession, in window: UIWindow) async throws -> (PDFPageCanvasView, PDFAnnotationCoordinator, GraphitePDFDisplayView) {
        try await waitUntil("the PDF shows") { (session.pdfView as? GraphitePDFDisplayView)?.window === window }
        let pdfView = try XCTUnwrap(session.pdfView as? GraphitePDFDisplayView)
        let coordinator = try XCTUnwrap(pdfView.annotationCoordinator)
        let page = try XCTUnwrap(session.document.page(at: 0))
        try await waitUntil("the PDF is written on") { coordinator.isWriting }
        try await waitUntil("the first page's canvas has its ink") {
            guard let canvas = coordinator.canvasesByPage[ObjectIdentifier(page)] else { return false }
            return canvas.window === window && !canvas.isRestoringStoredInk && canvas.delegate === coordinator && canvas.bounds.width > 0
        }
        let canvas = try XCTUnwrap(coordinator.canvasesByPage[ObjectIdentifier(page)])
        try await SynthesizedStrokes.waitForCanvasToDrawAtTheZoom(of: canvas, in: pdfView)
        return (canvas, coordinator, pdfView)
    }

    /// A point of the window in the drawing's points, as the eraser reads its touches.
    private func drawingPoint(_ windowPoint: CGPoint, on canvas: PDFPageCanvasView, in window: UIWindow) -> CGPoint {
        let canvasPoint = canvas.convert(windowPoint, from: window)
        return CGPoint(x: canvasPoint.x / canvas.zoomScale, y: canvasPoint.y / canvas.zoomScale)
    }

    /// Half the side of the square looked at around a point, in the drawing's points: well inside a cut six points wide.
    private static let probeRadius: CGFloat = 0.3

    /// The most opaque ink of a drawing within `probeRadius` of `drawingPoint`.
    private func inkOpacity(of drawing: PKDrawing, at drawingPoint: CGPoint) throws -> CGFloat {
        let radius = Self.probeRadius
        let area = CGRect(x: drawingPoint.x - radius, y: drawingPoint.y - radius, width: 2 * radius, height: 2 * radius)
        let pixelsPerPoint: CGFloat = 8
        let picture = try XCTUnwrap(drawing.image(from: area, scale: pixelsPerPoint).cgImage)
        return try Self.mostOpaque(in: picture)
    }

    private static func mostOpaque(in picture: CGImage) throws -> CGFloat {
        var bytes = [UInt8](repeating: 0, count: picture.width * picture.height * 4)
        let context = try XCTUnwrap(CGContext(data: &bytes, width: picture.width, height: picture.height, bitsPerComponent: 8, bytesPerRow: picture.width * 4,
                                              space: XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB)), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(picture, in: CGRect(x: 0, y: 0, width: picture.width, height: picture.height))
        return CGFloat(stride(from: 3, to: bytes.count, by: 4).map { index in bytes[index] }.max() ?? 0) / 255
    }

    /// The most opaque ink the page's ink annotations draw within `probeRadius` of `pagePoint`, shown or hidden.
    private func annotationInkOpacity(on page: PDFPage, at pagePoint: CGPoint) throws -> CGFloat {
        let pixelsPerPoint: CGFloat = 20
        let radius = Self.probeRadius
        let side = (2 * radius * pixelsPerPoint).rounded(.up)
        let context = try XCTUnwrap(CGContext(data: nil, width: Int(side), height: Int(side), bitsPerComponent: 8, bytesPerRow: Int(side) * 4,
                                              space: XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB)), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.scaleBy(x: pixelsPerPoint, y: pixelsPerPoint)
        context.translateBy(x: -(pagePoint.x - radius), y: -(pagePoint.y - radius))
        for annotation in page.annotations where annotation.type == "Ink" {
            let wasShown = annotation.shouldDisplay
            annotation.shouldDisplay = true
            annotation.draw(with: .cropBox, in: context)
            annotation.shouldDisplay = wasShown
        }
        return try Self.mostOpaque(in: XCTUnwrap(context.makeImage()))
    }

    /// The page's ink as its re-editing record holds it, after the records the session defers are written.
    private func recordedDrawing(on page: PDFPage, of session: PDFSession) throws -> PKDrawing {
        session.writePendingInkRecords()
        guard let editableGroup = PDFInkGroups.editableGroup(on: page) else { return PKDrawing() }
        return try XCTUnwrap(PDFPageInkTracker.restoring(editableGroup)?.drawing, "The page's record decodes")
    }

    /// Where ink was erased and where it was kept, in the drawing's points.
    private struct ExpectedInk {
        var erasedPoints: [String: CGPoint] = [:]
        var keptPoints: [String: CGPoint] = [:]
    }

    private func assertInk(_ drawing: PKDrawing, matches expected: ExpectedInk, _ label: String) throws {
        for (name, point) in expected.erasedPoints.sorted(by: { $0.key < $1.key }) {
            let opacity = try inkOpacity(of: drawing, at: point)
            XCTAssertLessThan(opacity, 0.1, "\(label): \(name) stays erased (opacity \(opacity))")
        }
        for (name, point) in expected.keptPoints.sorted(by: { $0.key < $1.key }) {
            let opacity = try inkOpacity(of: drawing, at: point)
            XCTAssertGreaterThan(opacity, 0.5, "\(label): \(name) keeps its ink (opacity \(opacity))")
        }
    }

    /// The canvas, the page's record and its annotations all show what was erased as erased and the rest as kept.
    private func assertPage(_ page: PDFPage, canvas: PDFPageCanvasView, session: PDFSession, matches expected: ExpectedInk, _ label: String) throws {
        try assertInk(canvas.drawing, matches: expected, "\(label), the canvas")
        try assertInk(recordedDrawing(on: page, of: session), matches: expected, "\(label), the page's record")
        try assertAnnotations(on: page, drawingSize: canvas.drawingSize, match: expected, label)
    }

    private func assertAnnotations(on page: PDFPage, drawingSize: CGSize, match expected: ExpectedInk, _ label: String) throws {
        let coordinates = try PageCoordinates(cropBox: page.bounds(for: .cropBox), overlaySize: drawingSize)
        for (name, point) in expected.erasedPoints.sorted(by: { $0.key < $1.key }) {
            let opacity = try annotationInkOpacity(on: page, at: coordinates.pdfPoint(fromOverlay: point))
            XCTAssertLessThan(opacity, 0.1, "\(label), the annotations: \(name) stays erased (opacity \(opacity))")
        }
        for (name, point) in expected.keptPoints.sorted(by: { $0.key < $1.key }) {
            let opacity = try annotationInkOpacity(on: page, at: coordinates.pdfPoint(fromOverlay: point))
            XCTAssertGreaterThan(opacity, 0.3, "\(label), the annotations: \(name) keeps its ink (opacity \(opacity))")
        }
    }

    /// What lies where the touches land: the page's own canvas, which records its changes, and nothing over it.
    private func describeTouchTarget(at windowPoint: CGPoint, canvas: PDFPageCanvasView, coordinator: PDFAnnotationCoordinator, in window: UIWindow) -> String {
        let hitView = window.hitTest(windowPoint, with: nil)
        var enclosingCanvas: UIView? = hitView
        while let view = enclosingCanvas, !(view is PDFPageCanvasView) { enclosingCanvas = view.superview }
        let pdfViewCount = Self.views(of: GraphitePDFDisplayView.self, in: window).count
        let canvasCount = Self.views(of: PDFPageCanvasView.self, in: window).filter { shownCanvas in shownCanvas.page === canvas.page }.count
        return "hit \(hitView.map { String(describing: type(of: $0)) } ?? "nothing"), its canvas is the page's own \(enclosingCanvas === canvas), "
            + "PDF views in the window \(pdfViewCount), canvases of the page \(canvasCount), records \(canvas.delegate === coordinator), "
            + "cursor \(canvas.pixelEraser.isShowingCursor), hiding swept ink \(canvas.pixelEraser.isHidingSweptInk), covered \(canvas.isCoveredWhileRendering)"
    }

    private static func views<ViewType: UIView>(of type: ViewType.Type, in view: UIView) -> [ViewType] {
        ((view as? ViewType).map { [$0] } ?? []) + view.subviews.flatMap { subview in views(of: type, in: subview) }
    }

    /// Erases through window points with the bar's pixel eraser at `width`, by Graphite's eraser or PencilKit's as the
    /// width and zoom call for, then waits until the canvas has the erased drawing and its cover is gone.
    /// `fingerThroughUIKit` sends a finger's touches through UIKit's own event path (`SynthesizedTouches`), as the screen
    /// does, to every recognizer under them; otherwise the eraser's recognizer, or PencilKit's, is told of them directly.
    private func erase(through windowPoints: [CGPoint], width: Double, expectingGraphitesEraser: Bool, on canvas: PDFPageCanvasView,
                       in window: UIWindow, fingerThroughUIKit: Bool = false, _ label: String) async throws {
        canvas.takeTool(from: PKToolPicker(), fixedTool: pixelEraser(width: width))
        XCTAssertEqual(canvas.pixelEraser.isErasing, expectingGraphitesEraser, "\(label): \(expectingGraphitesEraser ? "Graphite's" : "PencilKit's") eraser erases")
        let drawingBefore = canvas.drawing
        if fingerThroughUIKit, let start = windowPoints.first, let end = windowPoints.last {
            await SynthesizedTouches(window: window).drag(from: start, to: end, steps: windowPoints.count, holdSeconds: 0.1)
        } else {
            try await SynthesizedStrokes.draw(on: canvas, through: windowPoints, in: window,
                                              toldTo: expectingGraphitesEraser ? canvas.pixelEraser.touchRecognizer : nil)
        }
        // A few seconds, then the test goes on to say what else holds: an erase that never came is a failure, not a wait.
        for _ in 0..<60 where PencilDrawingChange(from: drawingBefore, to: canvas.drawing) == nil || canvas.isCoveredWhileRendering {
            try await SynthesizedStrokes.waitForPageToDraw(milliseconds: 50)
        }
        XCTAssertNotNil(PencilDrawingChange(from: drawingBefore, to: canvas.drawing), "\(label): the erase reaches the canvas")
        XCTAssertFalse(canvas.pixelEraser.isShowingCursor, "\(label): the eraser's circle goes at the lift")
        XCTAssertFalse(canvas.pixelEraser.isHidingSweptInk, "\(label): the ink is shown as it is at the lift")
        try await SynthesizedStrokes.waitForPageToDraw(milliseconds: 100)
    }

    private func switchToTheSlidesAndBack(_ workspace: WorkspaceModel, session: PDFSession, window: UIWindow) async throws {
        let slidesTab = try XCTUnwrap(workspace.layout.tabID(showing: try VaultPath("Lecture.pptx")))
        let pdfTab = try XCTUnwrap(workspace.layout.tabID(showing: try VaultPath("Lecture.pdf")))
        let pdfView = session.pdfView
        workspace.activateTab(slidesTab)
        try await waitUntil("the slides' tab is in front") { pdfView?.window == nil }
        try await SynthesizedStrokes.waitForPageToDraw(milliseconds: 300)
        workspace.activateTab(pdfTab)
        try await waitUntil("the PDF is in front again") { workspace.pdfSession === session && session.pdfView?.window === window }
    }

    func testInkErasedWithEitherEraserStaysErasedAcrossTabsSavingAndReopening() async throws {
        let restoreFingers = SynthesizedStrokes.letFingersDraw()
        defer { restoreFingers() }
        let (workspace, session) = try await workspace(named: "ErasedStaysErased")
        let window = try host(workspace)
        defer { window.isHidden = true; window.rootViewController = nil }
        var (canvas, coordinator, pdfView) = try await shownCanvas(of: session, in: window)
        let page = try XCTUnwrap(session.document.page(at: 0))
        let location = session.location

        // Two lines across the page, as the tick was there before the session: drawn, then saved.
        let middle = pdfView.convert(CGPoint(x: pdfView.bounds.midX, y: pdfView.bounds.midY), to: window)
        let upperHeight = middle.y - 100, lowerHeight = middle.y + 100
        for height in [upperHeight, lowerHeight] {
            canvas.takeTool(from: PKToolPicker(), fixedTool: pen())
            let line = try await SynthesizedStrokes.draw(on: canvas, through: SynthesizedStrokes.line(from: CGPoint(x: middle.x - 150, y: height),
                                                                                               to: CGPoint(x: middle.x + 150, y: height), steps: 60), in: window)
            XCTAssertNotNil(line, "The line at \(height) is drawn")
            try await SynthesizedStrokes.waitForPageToDraw(milliseconds: 100)
        }
        try await session.save()
        let linePlaces = stride(from: -140, through: 140, by: 70).map { offset in CGFloat(offset) }
        func places(atHeight height: CGFloat, _ name: String) -> [String: CGPoint] {
            Dictionary(uniqueKeysWithValues: linePlaces.map { offset in
                ("\(name) at \(Int(offset))", drawingPoint(CGPoint(x: middle.x + offset, y: height), on: canvas, in: window))
            })
        }
        let upperLine = places(atHeight: upperHeight, "upper line"), lowerLine = places(atHeight: lowerHeight, "lower line")
        var expected = ExpectedInk(keptPoints: upperLine.merging(lowerLine) { kept, _ in kept })
        try assertPage(page, canvas: canvas, session: session, matches: expected, "Drawn")
        print("ERASED-STAYS drawn: \(describeTouchTarget(at: CGPoint(x: middle.x, y: upperHeight), canvas: canvas, coordinator: coordinator, in: window))")

        // Graphite's eraser, six points wide, cuts the upper line where it crosses it.
        let upperCut = CGPoint(x: middle.x - 70, y: upperHeight)
        try await erase(through: SynthesizedStrokes.line(from: CGPoint(x: upperCut.x, y: upperHeight - 40), to: CGPoint(x: upperCut.x, y: upperHeight + 40)),
                        width: 6, expectingGraphitesEraser: true, on: canvas, in: window, "Graphite's cut")
        let upperCutName = "upper line at -70"
        expected.erasedPoints[upperCutName] = expected.keptPoints.removeValue(forKey: upperCutName)
        try assertPage(page, canvas: canvas, session: session, matches: expected, "After Graphite's cut")
        print("ERASED-STAYS after Graphite's cut: \(describeTouchTarget(at: upperCut, canvas: canvas, coordinator: coordinator, in: window))")

        // The other tab and back: the cut is still there.
        try await switchToTheSlidesAndBack(workspace, session: session, window: window)
        (canvas, coordinator, pdfView) = try await shownCanvas(of: session, in: window)
        print("ERASED-STAYS back after the cut: \(describeTouchTarget(at: upperCut, canvas: canvas, coordinator: coordinator, in: window))")
        try assertPage(page, canvas: canvas, session: session, matches: expected, "Back after Graphite's cut")

        // Graphite's eraser, wider than PencilKit's can be, along the whole upper line.
        try await erase(through: SynthesizedStrokes.line(from: CGPoint(x: middle.x - 175, y: upperHeight), to: CGPoint(x: middle.x + 175, y: upperHeight), steps: 40),
                        width: 120, expectingGraphitesEraser: true, on: canvas, in: window, "Graphite's whole erase")
        for (name, point) in upperLine {
            expected.keptPoints[name] = nil
            expected.erasedPoints[name] = point
        }
        try assertPage(page, canvas: canvas, session: session, matches: expected, "After Graphite's whole erase")

        // PencilKit's eraser, at a width it makes, cuts the lower line, then erases the rest of it.
        let lowerCut = CGPoint(x: middle.x + 70, y: lowerHeight)
        try await erase(through: SynthesizedStrokes.line(from: CGPoint(x: lowerCut.x, y: lowerHeight - 60), to: CGPoint(x: lowerCut.x, y: lowerHeight + 60)),
                        width: 24, expectingGraphitesEraser: false, on: canvas, in: window, "PencilKit's cut")
        let lowerCutName = "lower line at 70"
        expected.erasedPoints[lowerCutName] = expected.keptPoints.removeValue(forKey: lowerCutName)
        try assertPage(page, canvas: canvas, session: session, matches: expected, "After PencilKit's cut")
        try await erase(through: SynthesizedStrokes.line(from: CGPoint(x: middle.x - 175, y: lowerHeight), to: CGPoint(x: middle.x + 175, y: lowerHeight), steps: 60),
                        width: 24, expectingGraphitesEraser: false, on: canvas, in: window, "PencilKit's whole erase")
        for (name, point) in lowerLine {
            expected.keptPoints[name] = nil
            expected.erasedPoints[name] = point
        }
        try assertPage(page, canvas: canvas, session: session, matches: expected, "After PencilKit's whole erase")

        // The other tab and back again, then saved: the page, its record and the file keep every erase.
        try await switchToTheSlidesAndBack(workspace, session: session, window: window)
        (canvas, coordinator, pdfView) = try await shownCanvas(of: session, in: window)
        print("ERASED-STAYS back after every erase: \(describeTouchTarget(at: lowerCut, canvas: canvas, coordinator: coordinator, in: window))")
        try assertPage(page, canvas: canvas, session: session, matches: expected, "Back after every erase")
        try await session.save()
        let savedDocument = try XCTUnwrap(PDFDocument(url: location), "The saved file opens")
        let savedPage = try XCTUnwrap(savedDocument.page(at: 0))
        let savedDrawing = try PDFInkGroups.editableGroup(on: savedPage).map { editableGroup in
            try XCTUnwrap(PDFPageInkTracker.restoring(editableGroup)?.drawing)
        } ?? PKDrawing()
        try assertInk(savedDrawing, matches: expected, "The saved file's record")
        try assertAnnotations(on: savedPage, drawingSize: canvas.drawingSize, match: expected, "The saved file")

        // Closed and opened again: a new session reads the file, and its canvas shows what was left.
        let pdfPath = try VaultPath("Lecture.pdf")
        let pdfTab = try XCTUnwrap(workspace.layout.tabID(showing: pdfPath))
        await workspace.closeTab(pdfTab)
        try await waitUntil("the PDF is closed") { workspace.layout.tabID(showing: pdfPath) == nil }
        await workspace.open(try VaultPath("Lecture.pdf"), placement: .newTab)
        let reopenedSession = try XCTUnwrap(workspace.pdfSession)
        XCTAssertFalse(reopenedSession === session, "The file is read again")
        reopenedSession.isWriting = true
        let reopenedPage = try XCTUnwrap(reopenedSession.document.page(at: 0))
        let (reopenedCanvas, _, _) = try await shownCanvas(of: reopenedSession, in: window)
        try assertPage(reopenedPage, canvas: reopenedCanvas, session: reopenedSession, matches: expected, "Opened again")
    }

    /// Lets only the Pencil draw on a PDF page, as the owner's iPad does, until `restore` is called.
    private func letOnlyThePencilDraw() -> () -> Void {
        let restore = HostedDevicePreferences.saving([PDFAnnotationPreferenceKey.drawsWithFinger])
        let preference = AppStorage(wrappedValue: false, PDFAnnotationPreferenceKey.drawsWithFinger)
        preference.wrappedValue = false
        return restore
    }

    /// While only the Pencil draws, a hand resting on the page is no eraser's touch, and the Pencil erases while it rests.
    func testAHandRestingOnThePageLeavesThePencilErasing() async throws {
        let restorePencilOnly = letOnlyThePencilDraw()
        defer { restorePencilOnly() }
        try await handRestsWhileThePencilErases(fingersDraw: false)
    }

    /// The video's cause. With fingers drawing, the hand holding the Pencil lands on the page before the Pencil is active,
    /// so it is a finger like any other and Graphite's eraser takes its touch: its circle stays where the hand lies. Until
    /// 2026-11-05 the eraser's recognizer took touches of one type only, so UIKit kept every Pencil touch from it while
    /// the hand lay there, and the Pencil erased nothing. The Pencil landing while the hand rests now takes the eraser.
    func testThePencilTakesTheEraserFromAFingerWhenFingersDraw() async throws {
        let restoreFingers = SynthesizedStrokes.letFingersDraw()
        defer { restoreFingers() }
        try await handRestsWhileThePencilErases(fingersDraw: true)
    }

    private func handRestsWhileThePencilErases(fingersDraw: Bool) async throws {
        // These tests are about touches through UIKit's event path; without it they cannot say anything, and fail.
        if let reason = SynthesizedTouches.unavailableReason { return XCTFail(reason) }
        let (workspace, session) = try await workspace(named: fingersDraw ? "FingerThenPencil" : "HandResting")
        let window = try host(workspace)
        defer { window.isHidden = true; window.rootViewController = nil }
        let (canvas, coordinator, pdfView) = try await shownCanvas(of: session, in: window)
        try await waitUntil("the canvas takes the preference") { canvas.drawingPolicy == (fingersDraw ? .anyInput : .pencilOnly) }
        let middle = pdfView.convert(CGPoint(x: pdfView.bounds.midX, y: pdfView.bounds.midY), to: window)
        canvas.takeTool(from: PKToolPicker(), fixedTool: pen())
        let line = try await SynthesizedStrokes.draw(on: canvas, through: SynthesizedStrokes.line(from: CGPoint(x: middle.x - 150, y: middle.y),
                                                                                           to: CGPoint(x: middle.x + 150, y: middle.y), steps: 60),
                                                     in: window, touchType: .pencil)
        XCTAssertNotNil(line, "The Pencil draws the line")
        try await SynthesizedStrokes.waitForPageToDraw(milliseconds: 100)

        canvas.takeTool(from: PKToolPicker(), fixedTool: pixelEraser(width: 6))
        XCTAssertTrue(canvas.pixelEraser.isErasing, "Graphite's eraser erases")
        let recognizer = canvas.pixelEraser.touchRecognizer
        print("ERASED-STAYS fingers draw \(fingersDraw): PencilKit's drawing recognizer allows touch types "
              + "\(canvas.drawingGestureRecognizer.allowedTouchTypes.map(\.intValue)) (0 a finger, 2 the Pencil), the eraser's "
              + "\(recognizer.allowedTouchTypes.map(\.intValue)), exclusive touch type \(recognizer.requiresExclusiveTouchType)")

        // The hand lands below the line and rests there, through UIKit's own event path.
        let hand = SynthesizedTouches(window: window)
        let handPoint = CGPoint(x: middle.x - 40, y: middle.y + 60)
        hand.begin(at: [handPoint])
        for _ in 0..<4 {
            try await SynthesizedStrokes.waitForPageToDraw(milliseconds: 50)
            hand.stay()
        }
        print("ERASED-STAYS hand resting, fingers draw \(fingersDraw): \(describeTouchTarget(at: handPoint, canvas: canvas, coordinator: coordinator, in: window)), "
              + "eraser's recognizer state \(recognizer.state.rawValue) with \(recognizer.numberOfTouches) touches")
        if !fingersDraw {
            XCTAssertFalse(canvas.pixelEraser.isShowingCursor, "A hand shows no eraser where it rests when fingers do not draw")
            XCTAssertEqual(recognizer.numberOfTouches, 0, "The eraser does not take the hand's touch")
        }

        // The Pencil erases across the line while the hand rests, then the hand lifts. UIKit gives a recognizer that
        // holds a finger's touch no Pencil touch unless it takes touches of more than one type; a stand-in told to it
        // otherwise would say nothing of what the screen does.
        let drawingBefore = canvas.drawing
        let cut = CGPoint(x: middle.x + 40, y: middle.y)
        if recognizer.numberOfTouches == 0 || !recognizer.requiresExclusiveTouchType {
            try await SynthesizedStrokes.draw(on: canvas, through: SynthesizedStrokes.line(from: CGPoint(x: cut.x, y: cut.y - 40), to: CGPoint(x: cut.x, y: cut.y + 40)),
                                              in: window, touchType: .pencil, toldTo: recognizer)
        } else {
            XCTFail("The Pencil cannot erase while the hand rests: the eraser holds the hand's touch, and UIKit keeps the Pencil's from it")
        }
        hand.end()
        for _ in 0..<60 where PencilDrawingChange(from: drawingBefore, to: canvas.drawing) == nil || canvas.isCoveredWhileRendering {
            try await SynthesizedStrokes.waitForPageToDraw(milliseconds: 50)
        }
        try await SynthesizedStrokes.waitForPageToDraw(milliseconds: 100)
        XCTAssertFalse(canvas.pixelEraser.isShowingCursor, "No circle is left after the hand and the Pencil lift")
        var expected = ExpectedInk()
        expected.erasedPoints["the Pencil's cut"] = drawingPoint(cut, on: canvas, in: window)
        expected.keptPoints["beside the cut"] = drawingPoint(CGPoint(x: cut.x + 25, y: cut.y), on: canvas, in: window)
        expected.keptPoints["above the hand"] = drawingPoint(CGPoint(x: handPoint.x, y: middle.y), on: canvas, in: window)
        try assertInk(canvas.drawing, matches: expected, "The Pencil while the hand rests, fingers draw \(fingersDraw)")
    }

    /// The video's eraser: its circle stayed where an earlier touch had left it and the Pencil erased nothing until another
    /// tab and back. Every touch after another, and after the other tab, erases where it lands and lets its circle go.
    func testTheFineEraserFollowsEveryTouchBeforeAndAfterAnotherTab() async throws {
        // These tests are about touches through UIKit's event path; without it they cannot say anything, and fail.
        if let reason = SynthesizedTouches.unavailableReason { return XCTFail(reason) }
        let restoreFingers = SynthesizedStrokes.letFingersDraw()
        defer { restoreFingers() }
        let (workspace, session) = try await workspace(named: "EraserFollows")
        let window = try host(workspace)
        defer { window.isHidden = true; window.rootViewController = nil }
        var (canvas, coordinator, pdfView) = try await shownCanvas(of: session, in: window)
        let middle = pdfView.convert(CGPoint(x: pdfView.bounds.midX, y: pdfView.bounds.midY), to: window)
        canvas.takeTool(from: PKToolPicker(), fixedTool: pen())
        try await SynthesizedStrokes.draw(on: canvas, through: SynthesizedStrokes.line(from: CGPoint(x: middle.x - 150, y: middle.y),
                                                                                    to: CGPoint(x: middle.x + 150, y: middle.y), steps: 60), in: window)
        try await SynthesizedStrokes.waitForPageToDraw(milliseconds: 100)
        var expected = ExpectedInk()
        for (cutIndex, offset) in [-120, -60, 0, 60, 120].enumerated() {
            if cutIndex == 3 {
                try await switchToTheSlidesAndBack(workspace, session: session, window: window)
                (canvas, coordinator, pdfView) = try await shownCanvas(of: session, in: window)
            }
            let cut = CGPoint(x: middle.x + CGFloat(offset), y: middle.y)
            print("ERASED-STAYS before cut \(cutIndex): \(describeTouchTarget(at: cut, canvas: canvas, coordinator: coordinator, in: window))")
            try await erase(through: SynthesizedStrokes.line(from: CGPoint(x: cut.x, y: cut.y - 40), to: CGPoint(x: cut.x, y: cut.y + 40), steps: 16),
                            width: 6, expectingGraphitesEraser: true, on: canvas, in: window, fingerThroughUIKit: true, "Cut \(cutIndex)")
            expected.erasedPoints["cut \(cutIndex)"] = drawingPoint(cut, on: canvas, in: window)
            expected.keptPoints["beside cut \(cutIndex)"] = drawingPoint(CGPoint(x: cut.x + 25, y: cut.y), on: canvas, in: window)
            try assertInk(canvas.drawing, matches: expected, "After cut \(cutIndex)")
        }
        try await session.save()
        let savedPage = try XCTUnwrap(PDFDocument(url: session.location)?.page(at: 0))
        try assertAnnotations(on: savedPage, drawingSize: canvas.drawingSize, match: expected, "The saved file")
    }
}
#endif
