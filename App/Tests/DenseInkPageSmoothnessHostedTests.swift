/**
 * File: DenseInkPageSmoothnessHostedTests.swift
 * ---------------------------------------------
 * Layer: Tests
 * Description: On the iPad, a notebook written as densely as a formula sheet (6,000 strokes a page) scrolls, zooms and
 *              takes a lasso's move within its frame budget, and its pages' ink stays hidden under their canvases.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 12/11/2026
 */
#if os(iOS)
import XCTest
import SwiftUI
import PencilKit
import PDFKit
import GraphiteCore
@testable import GraphiteApple
@testable import GraphiteUI

/// The owner's report of 2026-11-12, after importing a Goodnotes formula sheet (5,159 and 6,145 strokes on two A3
/// landscape pages): "moving etc etc is supppperrrr slow and not smooth". PDFKit on the iPad keeps a layer for every
/// annotation of a page, also while the page's canvas hides the ink, so such a page has 6,000 of them. Graphite looked
/// at every one at each frame of a scroll and drew each again at the screen's resolution at each zoom, and it showed a
/// page's ink each time the page's view left the screen, which PDFKit then drew stroke by stroke from the file.
///
/// Measured on the iPad simulator on 2026-11-12 (debug build), three pages of 6,000 strokes: before, a scroll's median
/// frame 48 to 50 ms, longest 657 to 765 ms; each step of a settling zoom 1 to 3.1 s. After: median 16.7 ms, longest
/// 16 ms; each zoom step 120 to 175 ms (PDFKit's own walk over the page's annotations and Core Animation's commit of
/// 18,000 layers remain). `Docs/Bug-hunt-todo.md`, section 16 (HUNT-343 to HUNT-347).
@MainActor
final class DenseInkPageSmoothnessHostedTests: XCTestCase {
    private static let densePageCount = 3
    private static let lightStrokeCount = 60
    private var temporaryLocations: [URL] = []
    private var window: UIWindow?

    override func tearDown() async throws {
        window?.isHidden = true
        window?.rootViewController = nil
        window = nil
        for location in temporaryLocations { try? FileManager.default.removeItem(at: location) } // A file left in the temporary folder harms nothing.
        temporaryLocations = []
    }

    /// A fast scroll down the three pages and back keeps its median frame and at most one frame in six over 33 ms;
    /// zooming in and out in settled steps freezes no frame for 600 ms; moving 40 strokes with the lasso takes under
    /// half a second.
    func testADenselyWrittenNotebookScrollsZoomsAndTakesAMoveWithinItsFrameBudget() async throws {
        try TimingBudgets.requireTheOwnersDevice()
        let strokesPerPage = DenseHandwritingNotebook.formulaSheetStrokeCount
        let (session, pdfView) = try await openNotebook(pageCount: Self.densePageCount, strokesPerPage: strokesPerPage)
        let firstPage = try XCTUnwrap(session.document.page(at: 0))
        let openStart = Date()
        try await waitUntil("the first page's canvas shows its ink", timeoutSeconds: 60) {
            self.restoredCanvas(of: firstPage, in: pdfView, strokeCount: strokesPerPage) != nil
        }
        let openSeconds = Date().timeIntervalSince(openStart)
        try await settle(seconds: 2)

        let scrollView = try XCTUnwrap(pdfView.pagesScrollView)
        let scroll = await FrameRecorder.record { frameIndex in
            let maximumOffset = max(0, scrollView.contentSize.height - scrollView.bounds.height)
            let fraction = Double(frameIndex) / 120
            scrollView.contentOffset.y = maximumOffset * (fraction <= 1 ? fraction : 2 - fraction)
            return frameIndex < 240
        }
        try await settle(seconds: 2)

        // Zoom steps that each settle, as a pinch ends or a double tap zooms: PDFKit lays out its pages and their
        // annotations again at each new scale.
        pdfView.go(to: firstPage)
        let fitScale = pdfView.scaleFactor
        let zoomSteps: [CGFloat] = [1.5, 2, 3, 2, 1.5, 1]
        let zoom = await FrameRecorder.record { frameIndex in
            if frameIndex % 30 == 0, frameIndex / 30 < zoomSteps.count { pdfView.scaleFactor = fitScale * zoomSteps[frameIndex / 30] }
            return frameIndex < zoomSteps.count * 30 + 30
        }
        try await settle(seconds: 1)

        // The lasso moving 40 strokes, as PencilKit reports it: the drawing with those strokes moved.
        let canvas = try XCTUnwrap(restoredCanvas(of: firstPage, in: pdfView, strokeCount: strokesPerPage))
        var movedStrokes = canvas.drawing.strokes
        for strokeIndex in 0..<40 { movedStrokes[strokeIndex].transform = movedStrokes[strokeIndex].transform.translatedBy(x: 30, y: 12) }
        let moveStart = Date()
        canvas.drawing = PKDrawing(strokes: movedStrokes)
        try await waitUntil("the move is recorded") { session.undoAvailability.canUndo }
        let moveSeconds = Date().timeIntervalSince(moveStart)

        print("DenseInkPageSmoothnessHostedTests timing: ink on the canvas \(Self.seconds(openSeconds)) after the view; scroll \(scroll.report)")
        print("DenseInkPageSmoothnessHostedTests timing: zoom \(zoom.report); moving 40 strokes \(Self.seconds(moveSeconds))")
        XCTAssertGreaterThan(scroll.gaps.count, 200, "The scroll went through the notebook.")
        XCTAssertLessThan(scroll.medianMilliseconds, 20, "Median frame while scrolling: \(scroll.report).")
        XCTAssertLessThan(scroll.slowFrameCount * 6, scroll.gaps.count, "Frames over 33 ms while scrolling: \(scroll.report).")
        XCTAssertLessThan(scroll.longestMilliseconds, 300, "Longest frame while scrolling: \(scroll.report).")
        XCTAssertLessThan(zoom.longestMilliseconds, 600, "Longest frame as the zoom settles: \(zoom.report).")
        XCTAssertLessThan(moveSeconds, 0.5, "Moving 40 strokes of a full page.")
    }

    /// A page's ink stays hidden under its canvas while the page's view is off screen and the canvas is kept for
    /// scrolling back, and shows again once the canvas is let go. Before 2026-11-12 it was shown each time the page's
    /// view left the screen, and PDFKit drew every stroke of it again.
    func testAPageLeavingTheScreenKeepsItsInkHiddenUntilItsCanvasIsLetGo() async throws {
        let (session, pdfView) = try await openNotebook(pageCount: 2, strokesPerPage: Self.lightStrokeCount)
        let page = try XCTUnwrap(session.document.page(at: 0))
        try await waitUntil("the first page's canvas shows its ink") { self.restoredCanvas(of: page, in: pdfView, strokeCount: Self.lightStrokeCount) != nil }
        let coordinator = try XCTUnwrap(pdfView.annotationCoordinator)
        let overlay = try XCTUnwrap(coordinator.canvasesByPage[ObjectIdentifier(page)]?.overlayView)
        let ink = page.annotations.filter { annotation in annotation.type == "Ink" }
        XCTAssertEqual(ink.count, Self.lightStrokeCount)
        XCTAssertTrue(ink.allSatisfy { annotation in annotation is PDFShownInkAnnotation }, "Ink read from the file draws nothing while hidden.")
        XCTAssertTrue(ink.allSatisfy { annotation in !annotation.shouldDisplay }, "The canvas shows the ink.")

        coordinator.pdfView(pdfView, willEndDisplayingOverlayView: overlay, for: page)
        XCTAssertFalse(coordinator.isDisplaying(page))
        XCTAssertNotNil(coordinator.canvasesByPage[ObjectIdentifier(page)], "The canvas is kept for scrolling back")
        XCTAssertTrue(ink.allSatisfy { annotation in !annotation.shouldDisplay }, "and the ink stays hidden under it.")

        coordinator.pdfView(pdfView, willDisplayOverlayView: overlay, for: page)
        XCTAssertTrue(ink.allSatisfy { annotation in !annotation.shouldDisplay }, "Shown again, the page needs no change.")

        coordinator.pdfView(pdfView, willEndDisplayingOverlayView: overlay, for: page)
        NotificationCenter.default.post(name: UIApplication.didReceiveMemoryWarningNotification, object: nil)
        try await waitUntil("the page's canvas is let go") { coordinator.canvasesByPage[ObjectIdentifier(page)] == nil }
        XCTAssertTrue(ink.allSatisfy { annotation in annotation.shouldDisplay }, "Without its canvas, the page shows its ink.")
    }

    /// PDFKit hides the layer of a hidden annotation and keeps it; the layers kept at the screen's resolution are only
    /// those shown, so the canvas's hidden ink is never drawn again.
    func testTheLayersOfInkHiddenUnderACanvasAreNotDrawnAgain() async throws {
        let (session, pdfView) = try await openNotebook(pageCount: 1, strokesPerPage: Self.lightStrokeCount)
        let page = try XCTUnwrap(session.document.page(at: 0))
        try await waitUntil("the page's canvas shows its ink") { self.restoredCanvas(of: page, in: pdfView, strokeCount: Self.lightStrokeCount) != nil }
        let documentLayer = try XCTUnwrap(pdfView.documentView?.layer)
        let layerClass: AnyClass = try XCTUnwrap(NSClassFromString(PDFAnnotationLayerResolution.annotationLayerClassName))
        try await waitUntil("PDFKit hides the ink's layers") {
            let layers = Self.allAnnotationLayers(under: documentLayer, layerClass: layerClass)
            return layers.count == Self.lightStrokeCount && layers.allSatisfy(\.isHidden)
        }
        XCTAssertTrue(PDFAnnotationLayerResolution.annotationLayers(under: documentLayer, annotationLayerClass: layerClass).isEmpty,
                      "None of them is drawn again at the screen's resolution.")
    }

    // MARK: Hosting

    /// The notebook written to a new file, as Graphite writes its ink, then opened in a PDF pane.
    private func openNotebook(pageCount: Int, strokesPerPage: Int) async throws -> (PDFSession, GraphitePDFDisplayView) {
        let location = hostedTemporaryLocation(named: "DenseInk").appendingPathExtension("pdf")
        temporaryLocations.append(location)
        try await Task.detached(priority: .userInitiated) {
            _ = try DenseHandwritingNotebook.write(pageCount: pageCount, strokesPerPage: strokesPerPage, to: location)
        }.value
        let session = try await PDFSession.open(location)
        let controller = UIHostingController(rootView: NavigationStack { PDFPane(session: session, resolveConflict: { _ in }) })
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.effectiveGeometry.coordinateSpace.bounds
        window.rootViewController = controller
        window.makeKeyAndVisible()
        self.window = window
        try await waitUntil("the pane made the PDF's view") { (session.pdfView as? GraphitePDFDisplayView)?.annotationCoordinator != nil }
        return (session, try XCTUnwrap(session.pdfView as? GraphitePDFDisplayView))
    }

    private func restoredCanvas(of page: PDFPage, in view: UIView, strokeCount: Int) -> PDFPageCanvasView? {
        canvases(in: view).first { canvas in
            canvas.page === page && canvas.window != nil && !canvas.isRestoringStoredInk && canvas.drawing.strokes.count == strokeCount
        }
    }

    private func canvases(in view: UIView) -> [PDFPageCanvasView] {
        view.subviews.flatMap { child in ((child as? PDFPageCanvasView).map { [$0] } ?? []) + canvases(in: child) }
    }

    /// Every layer PDFKit made for a single annotation, hidden or not.
    private static func allAnnotationLayers(under layer: CALayer, layerClass: AnyClass) -> [CALayer] {
        (layer.sublayers ?? []).flatMap { sublayer in
            type(of: sublayer) == layerClass ? [sublayer] : allAnnotationLayers(under: sublayer, layerClass: layerClass)
        }
    }

    /// Lets the frames of what was just shown pass.
    private func settle(seconds: Double) async throws {
        let end = Date().addingTimeInterval(seconds)
        try await waitUntil("time passes", timeoutSeconds: seconds + 5) { Date() >= end }
    }

    private static func seconds(_ interval: TimeInterval) -> String { String(format: "%.2f s", interval) }
}

/// Runs `step` at each frame of a display link until it returns false, recording the gap before each frame and the
/// processor time the process spent meanwhile, on every thread (PDFKit and PencilKit draw away from the main thread).
@MainActor
private final class FrameRecorder: NSObject {
    struct Recording {
        let gaps: [CFTimeInterval]
        let processorSeconds: Double
        let wallSeconds: Double

        var medianMilliseconds: Double { gaps.isEmpty ? 0 : gaps.sorted()[gaps.count / 2] * 1_000 }
        var longestMilliseconds: Double { (gaps.max() ?? 0) * 1_000 }
        var slowFrameCount: Int { gaps.filter { gap in gap > 1.0 / 30 }.count }

        var report: String {
            let longestFrames = gaps.indices.sorted { leftIndex, rightIndex in gaps[leftIndex] > gaps[rightIndex] }.prefix(3)
                .map { frameIndex in "frame \(frameIndex) \(Int(gaps[frameIndex] * 1_000)) ms" }
            return "\(gaps.count) frames in \(String(format: "%.2f", wallSeconds)) s, median \(String(format: "%.1f", medianMilliseconds)) ms, "
                + "longest \(Int(longestMilliseconds)) ms, \(slowFrameCount) over 33 ms, processor \(String(format: "%.2f", processorSeconds)) s "
                + "(\(longestFrames.joined(separator: ", ")))"
        }
    }

    private let step: (Int) -> Bool
    private var displayLink: CADisplayLink?
    private var previousTimestamp: CFTimeInterval?
    private var gaps: [CFTimeInterval] = []
    private var frameIndex = 0
    private var continuation: CheckedContinuation<[CFTimeInterval], Never>?

    private init(step: @escaping (Int) -> Bool) {
        self.step = step
    }

    static func record(_ step: @escaping (Int) -> Bool) async -> Recording {
        let recorder = FrameRecorder(step: step)
        let processorStart = processorSeconds()
        let wallStart = Date()
        let gaps = await recorder.run()
        return Recording(gaps: gaps, processorSeconds: processorSeconds() - processorStart, wallSeconds: Date().timeIntervalSince(wallStart))
    }

    private func run() async -> [CFTimeInterval] {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            let displayLink = CADisplayLink(target: self, selector: #selector(frame(_:)))
            displayLink.add(to: .main, forMode: .common)
            self.displayLink = displayLink
        }
    }

    @objc private func frame(_ link: CADisplayLink) {
        if let previousTimestamp { gaps.append(link.timestamp - previousTimestamp) }
        previousTimestamp = link.timestamp
        let goesOn = step(frameIndex)
        frameIndex += 1
        guard !goesOn else { return }
        link.invalidate()
        displayLink = nil
        continuation?.resume(returning: gaps)
        continuation = nil
    }

    /// The processor time of the whole process, user and system, in seconds.
    private static func processorSeconds() -> Double {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        func seconds(_ time: timeval) -> Double { Double(time.tv_sec) + Double(time.tv_usec) / 1_000_000 }
        return seconds(usage.ru_utime) + seconds(usage.ru_stime)
    }
}
#endif
