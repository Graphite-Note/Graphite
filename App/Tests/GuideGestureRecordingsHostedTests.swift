/**
 * File: GuideGestureRecordingsHostedTests.swift
 * ---------------------------------------------
 * Layer: Tests
 * Description: Plays the gestures that the Graphite Guide shows as short animated pictures (switching a note's views,
 *              writing on a notebook page, the lasso, choosing and arranging pen colours) in Graphite's window, on the
 *              guide vault, while the simulator's screen is recorded from outside.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 16/11/2026
 */

#if os(iOS)
import XCTest
import UIKit
import PencilKit
import PDFKit
import GraphiteCore
@testable import GraphiteUI

/// Docs/Guide-vault-todo.md, section 2: the guide's animated pictures. Runs only with `TEST_RUNNER_GRAPHITE_GUIDE_GESTURES`
/// given to xcodebuild as the path of a file, where it writes when each gesture begins and ends;
/// `scripts/record-guide-gestures.sh` reads it and records the simulator's screen during each gesture, which waits for
/// it. Touches go through UIKit's event path as a hand's (`SynthesizedTouches`, `SynthesizedStrokes`), so the pictures
/// show Graphite's own drawing and tools. Nothing plays sound.
@MainActor
final class GuideGestureRecordingsHostedTests: XCTestCase {
    static let switchVariable = "GRAPHITE_GUIDE_GESTURES"
    private var marks: URL?

    func testPlayTheGuidesGesturesForTheirRecordings() async throws {
        // Returns rather than skipping: the suites' skip count may not rise (FR-93), and this is not a missing capability.
        guard let marksPath = ProcessInfo.processInfo.environment[Self.switchVariable] else { return }
        marks = URL(fileURLWithPath: marksPath)
        try Data().write(to: try XCTUnwrap(marks))
        XCTAssertNil(SynthesizedTouches.unavailableReason)
        let restoreFingers = SynthesizedStrokes.letFingersDraw()
        defer { restoreFingers() }
        let pass = try await ReleaseVaultPass.open(for: self, vault: FixtureFolders.guideVault)
        // The window's views read the workspace's own settings, not the app's.
        pass.workspace.deviceDefaults.set(true, forKey: PDFAnnotationPreferenceKey.drawsWithFinger)
        // Graphite's own bar, whose colours are held and dragged (Settings › Pencil Drawings › Tools).
        pass.workspace.preferences.pencilToolbarStyle = .fixed
        try await switchViews(in: pass)
        let canvas = try await openNotebookPage(in: pass)
        try await write(on: canvas, in: pass.window)
        // The colours before the lasso: a change of tool can scroll the notebook back to its cover.
        try await chooseAndArrangeColors(on: canvas, in: pass.window)
        try await lassoAndMove(on: canvas, in: pass.window)
    }

    // MARK: The gestures

    private func switchViews(in pass: ReleaseVaultPass) async throws {
        let path = "6 Everyday examples/Recipes/Tomato soup.md"
        _ = await pass.workspace.open(try VaultPath(path), placement: .currentTab)
        try await waitUntil("the recipe is open") { pass.workspace.activeDocument.loadedPath?.rawValue == path }
        let session = try XCTUnwrap(pass.workspace.markdownSession)
        session.viewMode = .livePreview
        try await pause(seconds: 2)
        try await mark("switching-views", "begin")
        for viewMode in [NoteViewMode.reading, .source, .livePreview] {
            session.viewMode = viewMode
            try await pause(seconds: 1.8)
        }
        try await mark("switching-views", "end")
    }

    private func openNotebookPage(in pass: ReleaseVaultPass) async throws -> PDFPageCanvasView {
        let path = "6 Everyday examples/Everyday Electronics/Week 1 notebook.pdf"
        _ = await pass.workspace.open(try VaultPath(path), placement: .currentTab)
        try await waitUntil("the notebook is open") { (pass.workspace.pdfSession?.pageCount ?? 0) > 0 }
        let session = try XCTUnwrap(pass.workspace.pdfSession)
        // A ruled page after the notebook's cover.
        let page = try XCTUnwrap(session.document.page(at: min(1, session.pageCount - 1)))
        try await waitUntil("the notebook is shown") { session.pdfView?.window != nil }
        let pdfView = try XCTUnwrap(session.pdfView)
        try await pause(seconds: 1)
        try await waitUntil("the ruled page is shown") {
            if pdfView.currentPage != page { pdfView.go(to: page) }
            return pdfView.currentPage == page
        }
        func canvas() -> PDFPageCanvasView? { (pdfView as? GraphitePDFDisplayView)?.annotationCoordinator?.editingCanvas(for: page) }
        try await waitUntil("the page has its canvas") { canvas()?.overlayView != nil }
        PencilToolbox.shared.usePreset(at: 0)
        try await pause(seconds: 2)
        return try XCTUnwrap(canvas())
    }

    /// "V = IR" and a resistor's zigzag under it, written stroke by stroke.
    private func write(on canvas: PDFPageCanvasView, in window: UIWindow) async throws {
        PencilToolbox.shared.chooseColor(hex: "#000000")
        try await pause(seconds: 0.5)
        try await mark("drawing", "begin")
        for stroke in Self.handwriting(at: CGPoint(x: 120, y: 230)) {
            let windowPoints = Self.densified(stroke.map { pagePoint in windowPoint(ofPage: pagePoint, on: canvas, in: window) }, spacing: 3)
            try await SynthesizedStrokes.draw(on: canvas, through: windowPoints, in: window)
            try await pause(seconds: 0.25)
        }
        try await pause(seconds: 1)
        try await mark("drawing", "end")
    }

    /// The lasso drawn round the writing, then the writing moved down and to the right.
    private func lassoAndMove(on canvas: PDFPageCanvasView, in window: UIWindow) async throws {
        let shapeBefore = LassoShape.stored
        LassoShape.stored = .freehand
        defer { LassoShape.stored = shapeBefore }
        PencilToolbox.shared.use(.lasso)
        canvas.selectsInk = true
        try await pause(seconds: 0.8)
        try await mark("lasso", "begin")
        try await pause(seconds: 0.5)
        let selection = canvas.inkSelection
        let writtenPoints = canvas.drawing.strokes.flatMap(InkLasso.pageSamplePoints(of:))
        try await drawLoopOfTouches(around: InkLasso.bounds(of: writtenPoints), on: canvas, in: window)
        try await waitUntil("the loop has selected the writing") { selection.hasSelection }
        try await pause(seconds: 0.6)
        for _ in 0..<20 {
            let frame = try XCTUnwrap(selection.selectionFrame)
            selection.moveSelection(in: canvas.drawing, from: frame, to: frame.offsetBy(dx: 3 * canvas.zoomScale, dy: 2.5 * canvas.zoomScale))
            try await pause(seconds: 0.04)
        }
        try await pause(seconds: 1.2)
        selection.clearSelection()
        canvas.selectsInk = false
        try await pause(seconds: 0.6)
        try await mark("lasso", "end")
    }

    /// A colour chosen by a tap, a line in it, then a colour held and dragged two places along the row.
    private func chooseAndArrangeColors(on canvas: PDFPageCanvasView, in window: UIWindow) async throws {
        let row = try XCTUnwrap(colorRow(in: window), "the Pencil bar's colours are on screen")
        let pitch = try XCTUnwrap(row.touches?.swatchPitch)
        func center(ofPlace place: Int) -> CGPoint { row.convert(CGPoint(x: (Double(place) + 0.5) * pitch, y: row.bounds.midY), to: window) }
        try await pause(seconds: 0.8)
        try await mark("pen-colors", "begin")
        try await pause(seconds: 0.5)
        let chosen = center(ofPlace: 2)
        await SynthesizedTouches(window: window).move(paths: [(chosen, chosen)], steps: 1, stepSeconds: 0.05, holdSeconds: 0)
        try await pause(seconds: 0.6)
        let underline = SynthesizedStrokes.line(from: CGPoint(x: 150, y: 330), to: CGPoint(x: 330, y: 330), steps: 60)
        try await SynthesizedStrokes.draw(on: canvas, through: underline.map { windowPoint(ofPage: $0, on: canvas, in: window) }, in: window)
        try await pause(seconds: 0.8)
        let start = center(ofPlace: 1)
        let touches = SynthesizedTouches(window: window)
        touches.begin(at: [start])
        await touches.hold(seconds: PencilColorRowTouches.holdSeconds + 0.2)
        await touches.slide(to: [CGPoint(x: start.x + 2 * pitch, y: start.y)], steps: 40)
        await touches.hold(seconds: 0.4)
        touches.end()
        try await pause(seconds: 1.4)
        try await mark("pen-colors", "end")
    }

    // MARK: Helpers

    /// Tells the recording script that a gesture begins or ends, and waits until it has started or stopped recording
    /// it (the file `<marks>.<phase>-<gesture>`), so each gesture is recorded on its own, from its first frame.
    private func mark(_ gesture: String, _ phase: String) async throws {
        print("GUIDE-GESTURE \(gesture) \(phase)")
        guard let marks else { return }
        if phase == "end" { try await pushOutTheLastPicture() }
        let handle = try FileHandle(forWritingTo: marks)
        handle.seekToEndOfFile()
        handle.write(Data("\(gesture) \(phase)\n".utf8))
        try handle.close()
        let answer = marks.path + ".\(phase)-\(gesture)"
        try await waitUntil("the recording of \(gesture) has \(phase == "begin" ? "started" : "stopped")", timeoutSeconds: 60) {
            FileManager.default.fileExists(atPath: answer)
        }
    }

    /// recordVideo writes a picture of the screen only when the next one comes, so the gesture's last picture would be
    /// lost when it stops: a dot hardly to be seen is shown in a corner of the window and taken away again after it.
    private func pushOutTheLastPicture() async throws {
        try await pause(seconds: 0.6)
        guard let window = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first?.keyWindow else { return }
        let dot = UIView(frame: CGRect(x: window.bounds.maxX - 1, y: window.bounds.maxY - 1, width: 1, height: 1))
        dot.backgroundColor = UIColor.black.withAlphaComponent(0.04)
        window.addSubview(dot)
        try await pause(seconds: 0.3)
        dot.removeFromSuperview()
        try await pause(seconds: 0.3)
    }

    private func pause(seconds: Double) async throws {
        try await SynthesizedStrokes.waitForPageToDraw(milliseconds: Int(seconds * 1_000))
    }

    /// The strokes of "V = IR" and a zigzag, in the page's points from its top-left corner.
    private static func handwriting(at origin: CGPoint) -> [[CGPoint]] {
        let letterScale: CGFloat = 1.6
        func shape(_ points: [(CGFloat, CGFloat)]) -> [CGPoint] {
            points.map { x, y in CGPoint(x: origin.x + x * letterScale, y: origin.y + y * letterScale) }
        }
        let bowl = stride(from: -CGFloat.pi / 2, through: CGFloat.pi / 2, by: CGFloat.pi / 10).map { angle in (CGFloat(82) + 9 * cos(angle), CGFloat(7.5) + 7.5 * sin(angle)) }
        return [
            shape([(0, 0), (10, 30), (20, 0)]),
            shape([(32, 11), (48, 11)]),
            shape([(32, 20), (48, 20)]),
            shape([(62, 0), (62, 30)]),
            shape([(76, 30), (76, 0)] + bowl + [(76, 15)]),
            shape([(80, 15), (92, 30)]),
            shape([(0, 50), (12, 50), (16, 42), (24, 58), (32, 42), (40, 58), (48, 42), (52, 50), (64, 50)]),
        ]
    }

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

    /// A finger circling an area of the page 18 screen points clear of it, through UIKit's event path.
    private func drawLoopOfTouches(around pageArea: CGRect, on canvas: PDFPageCanvasView, in window: UIWindow) async throws {
        let middle = windowPoint(ofPage: CGPoint(x: pageArea.midX, y: pageArea.midY), on: canvas, in: window)
        let corner = windowPoint(ofPage: CGPoint(x: pageArea.maxX, y: pageArea.maxY), on: canvas, in: window)
        let radiusAcross = abs(corner.x - middle.x) + 18, radiusDown = abs(corner.y - middle.y) + 18
        let pointCount = 72
        let loop = (0...pointCount).map { pointIndex in
            let angle = 2 * CGFloat.pi * CGFloat(pointIndex) / CGFloat(pointCount)
            return CGPoint(x: middle.x + radiusAcross * cos(angle), y: middle.y + radiusDown * sin(angle))
        }
        let touches = SynthesizedTouches(window: window)
        touches.begin(at: [loop[0]])
        try await SynthesizedStrokes.waitForPageToDraw(milliseconds: 16)
        for point in loop.dropFirst() {
            touches.moveTo([point])
            try await SynthesizedStrokes.waitForPageToDraw(milliseconds: 16)
        }
        touches.end()
    }

    /// The clear view that takes the Pencil bar's colour touches.
    private func colorRow(in window: UIWindow) -> PencilColorRowTouchView? {
        func search(_ view: UIView) -> PencilColorRowTouchView? {
            if let rowView = view as? PencilColorRowTouchView, rowView.window != nil, !rowView.isHidden { return rowView }
            for subview in view.subviews { if let found = search(subview) { return found } }
            return nil
        }
        return search(window)
    }
}
#endif
