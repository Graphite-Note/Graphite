/**
 * File: CanvasRecognizersResetHostedTests.swift
 * ---------------------------------------------
 * Layer: Tests
 * Description: Hosted tests of the freeze of 2026-11-18 on a simulator: the recognizers that follow a
 *              canvas's stroke fail once every touch has lifted, so UIKit resets the canvas's recognizers, and a canvas
 *              whose drawing recognizer is left finished with no touch down has its recognizers reset within seconds.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 18/11/2026
 */
#if os(iOS)
import XCTest
import SwiftUI
import UIKit
import UIKit.UIGestureRecognizerSubclass
import PDFKit
import GraphiteCore
import GraphiteApple
@testable import GraphiteUI

/// Drawn with the highlighter, the page stopped taking ink, while the toolbar still worked; switching tabs
/// put it right (2026-11-18, "Graphite Highlighter Checks iPad"). Read live: PencilKit's drawing recognizer was left
/// ended and never reset, its canvas still drawing the stroke of a touch that had ended and left the window, and
/// Graphite's `StrokeHoldRecognizer` and `DrawnStrokeFollower` on the canvas sat in possible, never failed, holding no
/// touch. Nothing here plays sound.
@MainActor
final class CanvasRecognizersResetHostedTests: XCTestCase {
    private var temporaryLocations: [URL] = []
    private var windows: [UIWindow] = []

    override func tearDown() async throws {
        for window in windows { window.isHidden = true; window.rootViewController = nil }
        windows = []
        for location in temporaryLocations { try? FileManager.default.removeItem(at: location) } // A file left in the temporary folder harms nothing.
        temporaryLocations = []
    }

    private func makeWindow() throws -> UIWindow {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.effectiveGeometry.coordinateSpace.bounds
        windows.append(window)
        return window
    }

    /// A touch ends while the two recognizers follow none, as when its end reached them without its start: each fails,
    /// and so is reset with the others, rather than staying possible after the last touch lifted.
    func testTheStrokeFollowersFailOnceEveryTouchHasLifted() async throws {
        XCTAssertNil(SynthesizedTouches.unavailableReason)
        let window = try makeWindow()
        let controller = UIViewController()
        window.rootViewController = controller
        window.makeKeyAndVisible()
        let page = UIView(frame: window.bounds)
        controller.view.addSubview(page)
        let strokeHold = StrokeHoldRecognizer(target: nil, action: nil)
        strokeHold.tracksTouch = { _ in false }
        let follower = DrawnStrokeFollower(target: nil, action: nil)
        follower.followsTouch = { _ in false }
        page.addGestureRecognizer(strokeHold)
        page.addGestureRecognizer(follower)
        var statesSeen: [String: [UIGestureRecognizer.State]] = ["hold": [], "follower": []]
        let observations = [
            strokeHold.observe(\.state, options: [.new]) { recognizer, _ in MainActor.assumeIsolated { statesSeen["hold"]?.append(recognizer.state) } },
            follower.observe(\.state, options: [.new]) { recognizer, _ in MainActor.assumeIsolated { statesSeen["follower"]?.append(recognizer.state) } },
        ]
        defer { observations.forEach { observation in observation.invalidate() } }

        let touches = SynthesizedTouches(window: window)
        let point = CGPoint(x: window.bounds.midX, y: window.bounds.midY)
        await touches.drag(from: point, to: CGPoint(x: point.x + 60, y: point.y + 20), steps: 6, holdSeconds: 0)
        try await waitUntil("both are reset after the touch lifted") { strokeHold.state == .possible && follower.state == .possible }
        XCTAssertTrue(statesSeen["hold"]?.contains(.failed) == true, "The stroke hold failed once the touch lifted: \(statesSeen).")
        XCTAssertTrue(statesSeen["follower"]?.contains(.failed) == true, "The follower failed once the touch lifted: \(statesSeen).")
    }

    /// While touches are down, as a hand resting on the page with the Pencil, the stroke hold stays possible, so the
    /// next stroke is still followed; once they have all lifted, it fails and is reset.
    func testTheStrokeHoldStaysPossibleWhileTouchesAreDownAndFailsOnceTheyLift() async throws {
        XCTAssertNil(SynthesizedTouches.unavailableReason)
        let window = try makeWindow()
        let controller = UIViewController()
        window.rootViewController = controller
        window.makeKeyAndVisible()
        let page = UIView(frame: window.bounds)
        controller.view.addSubview(page)
        let strokeHold = StrokeHoldRecognizer(target: nil, action: nil)
        var endedStrokes = 0
        strokeHold.touchDidEnd = { _ in endedStrokes += 1 }
        page.addGestureRecognizer(strokeHold)
        var failed = false
        let observation = strokeHold.observe(\.state, options: [.new]) { recognizer, _ in
            MainActor.assumeIsolated { if recognizer.state == .failed { failed = true } }
        }
        defer { observation.invalidate() }

        // Both fingers down; the stroke hold follows the first touch that began.
        let touches = SynthesizedTouches(window: window)
        let stroke = CGPoint(x: window.bounds.midX, y: window.bounds.midY)
        let hand = CGPoint(x: window.bounds.midX + 200, y: window.bounds.midY + 200)
        touches.begin(at: [stroke, hand])
        touches.moveTo([CGPoint(x: stroke.x + 40, y: stroke.y), hand])
        XCTAssertFalse(failed, "Still possible while touches are down.")
        touches.end()
        try await waitUntil("the stroke ended") { endedStrokes == 1 }
        XCTAssertTrue(failed, "Once every touch lifted, it failed and was reset.")
    }

    /// A page's canvas whose drawing recognizer is left ended, no touch down, has its recognizers reset by the PDF's
    /// health check once that lasted `stuckGestureSeconds`, and takes the next stroke.
    func testACanvasLeftDrawingWithNoTouchDownIsResetByTheHealthCheck() async throws {
        let location = try makeHostedBlankNotebook(named: "LeftDrawing", pageCount: 2)
        temporaryLocations.append(location)
        let session = try await PDFSession.open(location)
        session.isWriting = true
        let window = try makeWindow()
        window.rootViewController = UIHostingController(rootView: NavigationStack { PDFPane(session: session, resolveConflict: { _ in }) })
        window.makeKeyAndVisible()
        try await waitUntil("the pane made the PDF's view") { (session.pdfView as? GraphitePDFDisplayView)?.annotationCoordinator != nil }
        let coordinator = try XCTUnwrap((session.pdfView as? GraphitePDFDisplayView)?.annotationCoordinator)
        let page = try XCTUnwrap(session.document.page(at: 0))
        try await waitUntil("the first page's canvas is on screen") { coordinator.canvasesByPage[ObjectIdentifier(page)]?.window != nil }
        let canvas = try XCTUnwrap(coordinator.canvasesByPage[ObjectIdentifier(page)])

        canvas.drawingGestureRecognizer.state = .ended
        XCTAssertEqual(canvas.drawingGestureRecognizer.state, .ended, "Left ended, as the simulator showed it.")
        let stuck = PDFPaneHealthMonitor.stuckGestureSeconds
        func repaired(touchIsDown: Bool, at now: TimeInterval) -> Bool {
            coordinator.repairCanvases(touchIsDown: touchIsDown, now: now).contains { repair in repair.contains("left drawing") }
        }
        XCTAssertFalse(repaired(touchIsDown: false, at: 1_000), "Not at once.")
        XCTAssertFalse(repaired(touchIsDown: true, at: 1_000 + stuck + 1), "Never while a touch is down.")
        XCTAssertFalse(repaired(touchIsDown: false, at: 1_000 + stuck + 2), "A touch down started the count again.")
        XCTAssertTrue(repaired(touchIsDown: false, at: 1_000 + 2 * stuck + 3), "Repaired once it lasted.")
        // Switched off and on, it is reset as UIKit resets recognizers, on the next turn.
        try await waitUntil("the drawing recognizer is reset and takes the next stroke") { canvas.drawingGestureRecognizer.state == .possible }
        XCTAssertTrue(canvas.drawingGestureRecognizer.isEnabled)
    }
}
#endif
