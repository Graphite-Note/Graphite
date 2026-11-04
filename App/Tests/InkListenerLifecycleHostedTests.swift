/**
 * File: InkListenerLifecycleHostedTests.swift
 * -------------------------------------------
 * Layer: Tests
 * Description: The listeners and first-responder changes of the ink views end with the views (HUNT-106, HUNT-110, HUNT-111).
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 04/11/2026
 */
#if os(iOS)
import XCTest
import PencilKit
@testable import GraphiteUI

/// The listeners a canvas and its lasso register last only as long as they are needed, and a view being
/// dismantled changes the first responder after SwiftUI's update, not in the middle of it.
@MainActor
final class InkListenerLifecycleHostedTests: XCTestCase {
    private var windows: [UIWindow] = []

    override func tearDown() async throws {
        for window in windows { window.isHidden = true; window.rootViewController = nil }
        windows = []
    }

    private func showInAWindow(_ view: UIView) throws -> UIWindow {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.effectiveGeometry.coordinateSpace.bounds
        let controller = UIViewController()
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.addSubview(view)
        windows.append(window)
        return window
    }

    /// Releasing the host while SwiftUI updates its views changed the first responder in the middle of that
    /// update, the known cause of the app computing without end.
    func testTheToolPickerHostGivesUpFirstResponderOnTheNextTurnNotAtOnce() async throws {
        let host = PencilToolPickerHostView(frame: CGRect(x: 0, y: 0, width: 10, height: 10))
        _ = try showInAWindow(host)
        XCTAssertTrue(host.becomeFirstResponder())

        host.resignFirstResponderOnNextTurn()

        XCTAssertTrue(host.isFirstResponder, "Nothing changes while the caller is still running.")
        try await waitUntil("the host gave up first responder") { !host.isFirstResponder }
    }

    /// Every page canvas opened in a PDF registered a listener for the preference and kept it for the rest of
    /// the session.
    func testACanvasHearsTheEvenHighlighterPreferenceOnlyWhileItIsInAWindow() throws {
        let canvas = HistoryCanvasView(frame: CGRect(x: 0, y: 0, width: 400, height: 400))
        XCTAssertFalse(canvas.isFollowingEvenHighlighterPreference)

        _ = try showInAWindow(canvas)
        XCTAssertTrue(canvas.isFollowingEvenHighlighterPreference)

        canvas.removeFromSuperview()
        XCTAssertFalse(canvas.isFollowingEvenHighlighterPreference, "A canvas that left its window has no listener.")

        let window = try showInAWindow(canvas)
        XCTAssertTrue(canvas.isFollowingEvenHighlighterPreference, "It listens again when it is shown again.")
        XCTAssertNotNil(window)
    }

    /// The lasso registered a zoom listener when first switched on and never removed it, so a PDF of many
    /// pages left one for each canvas it was used on.
    func testTheLassoListensToZoomOnlyWhileItIsOn() throws {
        let canvas = HistoryCanvasView(frame: CGRect(x: 0, y: 0, width: 400, height: 400))
        _ = try showInAWindow(canvas)
        XCTAssertFalse(canvas.inkSelection.isObservingZoom)

        canvas.inkSelection.isActive = true
        XCTAssertTrue(canvas.inkSelection.isObservingZoom)

        canvas.inkSelection.isActive = false
        XCTAssertFalse(canvas.inkSelection.isObservingZoom)

        canvas.inkSelection.isActive = true
        XCTAssertTrue(canvas.inkSelection.isObservingZoom, "Switched on again, it listens again.")
    }
}
#endif
