/**
 * File: LassoSelectionKindsHostedTests.swift
 * ------------------------------------------
 * Layer: Tests
 * Description: Graphite's lasso on a canvas follows the Lasso panel's "Included in Selection" switches
 *              (Docs/Lasso-todo.md); the selection's bar is tested in LassoSelectionToolbarHostedTests.
 *
 * Authors: Bahey Shalash
 * Version: 0.3
 * Date: 18/11/2026
 */
#if os(iOS)
import XCTest
import PencilKit
import UIKit
@testable import GraphiteUI

/// The canvas is not in a window, so one canvas point is one screen point and the zoom is 1.
@MainActor
final class LassoSelectionKindsHostedTests: XCTestCase {
    private func horizontalStroke(y: CGFloat) -> PKStroke {
        let controlPoints = stride(from: CGFloat(0), through: 100, by: 10).enumerated().map { index, x in
            PKStrokePoint(location: CGPoint(x: x, y: y), timeOffset: TimeInterval(index) / 100, size: CGSize(width: 2, height: 2),
                          opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }
        return PKStroke(ink: PKInk(.pen, color: .black), path: PKStrokePath(controlPoints: controlPoints, creationDate: Date()))
    }

    private func controller(showing strokes: [PKStroke]) throws -> InkSelectionController {
        // The loops here are drawn freehand; the shape chosen before is put back.
        let keptShape = LassoShape.stored
        LassoShape.stored = .freehand
        addTeardownBlock { @MainActor in LassoShape.stored = keptShape }
        let canvas = HistoryCanvasView(frame: CGRect(x: 0, y: 0, width: 600, height: 600))
        canvas.drawing = PKDrawing(strokes: strokes)
        let controller = canvas.inkSelection
        controller.isActive = true
        return controller
    }

    /// Preferences of the test's own with only `kinds` switched on.
    private func preferences(with kinds: LassoSelectionKinds) throws -> UserDefaults {
        let suiteName = "LassoSelectionKindsHostedTests-\(UUID().uuidString)"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        addTeardownBlock { UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName) }
        kinds.store(in: preferences)
        return preferences
    }

    /// A freehand loop around the box from (-10, 20) to (110, 80), begun at its first corner.
    private func drawLoopAroundTheStroke(with controller: InkSelectionController) {
        let points = [CGPoint(x: -10, y: 20), CGPoint(x: 110, y: 20), CGPoint(x: 110, y: 80), CGPoint(x: -10, y: 80), CGPoint(x: -10, y: 20)]
        controller.loopDidBegin(at: points[0], reaching: points[1])
        for point in points.dropFirst(2) { controller.loopDidMove(to: point) }
        controller.loopDidEnd(at: points[points.count - 1])
    }

    func testWithHandwritingOffALoopAroundInkMarksItsAreaAndATapOnInkSelectsNothing() throws {
        let controller = try controller(showing: [horizontalStroke(y: 50)])
        controller.preferences = try preferences(with: [.images, .textBoxes])
        drawLoopAroundTheStroke(with: controller)
        XCTAssertEqual(controller.selectedStrokeIndices, [])
        XCTAssertTrue(controller.isShowingLassoedArea, "A loop around only what the lasso leaves out marks its area, for a screenshot.")
        controller.clearSelection()
        XCTAssertFalse(controller.selectStroke(at: CGPoint(x: 50, y: 50)))

        controller.preferences = try preferences(with: [.handwriting])
        drawLoopAroundTheStroke(with: controller)
        XCTAssertEqual(controller.selectedStrokeIndices, [0])
    }

}
#endif
