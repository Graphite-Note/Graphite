/**
 * File: PencilEraserWidthsTests.swift
 * -----------------------------------
 * Layer: Tests
 * Description: The pixel eraser's sizes (HUNT-319): a smallest about a thin pen line, fine steps up to the
 *              broadest, three starting sizes, sizes kept as the bar keeps the others, and PencilKit's limits.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 04/11/2026
 */

import XCTest
#if canImport(PencilKit)
import PencilKit
#endif
@testable import GraphiteUI
import GraphiteTestSupport

/// The owner's report of 2026-11-04: "eraser needs to go much much smaller, more granularity". Values only:
/// the eraser cutting a gap in a stroke is a hosted test (`InkWidthAtZoomTests`).
@MainActor
final class PencilEraserWidthsTests: XCTestCase {
    private var defaults: UserDefaults!

    override func setUp() async throws {
        defaults = try IsolatedDeviceState.make(prefix: "PencilEraserWidthsTests", for: self).preferences
    }

    func testTheSmallestSizeIsAboutAThinPenLine() {
        XCTAssertEqual(PencilEraserWidths.range.lowerBound, 1)
        XCTAssertLessThanOrEqual(PencilEraserWidths.range.lowerBound, 2, "A thin pen line is one or two points wide.")
        XCTAssertEqual(PencilEraserWidths.steps.first, PencilEraserWidths.range.lowerBound)
        XCTAssertEqual(PencilEraserWidths.steps.last, PencilEraserWidths.range.upperBound)
        XCTAssertEqual(PencilEraserWidths.defaultChoices, [2, 6, 14])
        XCTAssertEqual(PencilToolbox.defaultEraserWidthChoices, PencilEraserWidths.defaultChoices)
        XCTAssertEqual(PencilToolbox.eraserWidthRange, PencilEraserWidths.range)
        XCTAssertLessThan(PencilEraserWidths.defaultChoices.last ?? 100, PencilEraserWidths.previousDefaultChoices.first ?? 0,
                          "Even the broadest starting size is finer than the earlier finest.")
    }

    func testTheStepsAreFineWhereTheEraserIsSmallAndNeverSkipAWidthTheBarOffers() {
        let steps = PencilEraserWidths.steps
        XCTAssertGreaterThanOrEqual(steps.count, 40)
        XCTAssertEqual(steps, steps.sorted())
        XCTAssertEqual(Set(steps).count, steps.count, "No width twice.")
        for (smaller, larger) in zip(steps, steps.dropFirst()) {
            XCTAssertLessThanOrEqual(larger - smaller, 6, "No step wider than the one from 64 to 70.")
            if larger <= 10 { XCTAssertEqual(larger - smaller, 0.5, accuracy: 0.0001, "Half a point apart up to ten.") }
            if larger <= 30 { XCTAssertLessThanOrEqual(larger - smaller, 1.0001) }
        }
        for width in PencilEraserWidths.defaultChoices + PencilEraserWidths.previousDefaultChoices {
            XCTAssertTrue(steps.contains(width), "\(width) is one of the steps, so the control can show it.")
        }
    }

    func testAWidthSnapsToTheNearestStepWithinTheRange() {
        XCTAssertEqual(PencilEraserWidths.snapped(0.1), 1)
        XCTAssertEqual(PencilEraserWidths.snapped(1.2), 1)
        XCTAssertEqual(PencilEraserWidths.snapped(1.3), 1.5)
        XCTAssertEqual(PencilEraserWidths.snapped(6.2), 6)
        XCTAssertEqual(PencilEraserWidths.snapped(500), 100)
        XCTAssertEqual(PencilEraserWidths.snapped(.nan), 1)
        XCTAssertEqual(PencilEraserWidths.steps[PencilEraserWidths.stepIndex(forWidth: 14)], 14)
    }

    func testTheBarsSmallestSizeIsChosenAtItsRangesLowerBoundAndErasesWithIt() {
        let toolbox = PencilToolbox(defaults: defaults)
        XCTAssertEqual(toolbox.eraserWidthChoices, [2, 6, 14])
        XCTAssertEqual(toolbox.eraserWidth, 6, "The medium size is in use at first.")
        toolbox.changeEraserWidthChoice(at: 0, to: 0.2)
        XCTAssertEqual(toolbox.eraserWidthChoices, [1, 6, 14])
        XCTAssertEqual(toolbox.selection.eraserWidth, PencilEraserWidths.range.lowerBound, "The tool is given the smallest size as chosen.")
        toolbox.changeEraserWidthChoice(at: 1, to: 3.3)
        XCTAssertEqual(toolbox.eraserWidthChoices[1], 3.5, "A width between steps is the nearest step.")
        XCTAssertEqual(PencilToolbox(defaults: defaults).eraserWidthChoices, [1, 3.5, 14], "Kept between launches.")
    }

    func testSizesSavedByEarlierBuildsKeepTheirMeaning() {
        let neverChanged = PencilEraserWidths.restored(choices: [18, 36, 64], widthInUse: 64)
        XCTAssertEqual(neverChanged.choices, PencilEraserWidths.defaultChoices, "The earlier starting sizes become the new ones.")
        XCTAssertEqual(neverChanged.widthInUse, 14, "The broad size stays the one in use.")
        XCTAssertEqual(PencilEraserWidths.restored(choices: [18, 36, 64], widthInUse: 7).widthInUse, 6)

        let changedByThePerson = PencilEraserWidths.restored(choices: [12, 36, 64], widthInUse: 12)
        XCTAssertEqual(changedByThePerson.choices, [12, 36, 64], "Sizes the person set are theirs.")
        XCTAssertEqual(changedByThePerson.widthInUse, 12)

        let nothingSaved = PencilEraserWidths.restored(choices: nil, widthInUse: nil)
        XCTAssertEqual(nothingSaved.choices, PencilEraserWidths.defaultChoices)
        XCTAssertEqual(nothingSaved.widthInUse, 6)
        XCTAssertEqual(PencilEraserWidths.restored(choices: [0.5, 6, 14], widthInUse: 6).choices, PencilEraserWidths.defaultChoices, "Narrower than a build offers.")
        XCTAssertEqual(PencilEraserWidths.restored(choices: [2, 6], widthInUse: 2).choices, PencilEraserWidths.defaultChoices, "Not three sizes.")

        // A state of an earlier build, with its three sizes and the broad one in use, opens with the new starting sizes.
        let stored = ##"{"toolInUse":"eraser","presetInUseIndex":0,"erasesWholeStrokes":false,"eraserWidth":64,"eraserWidthChoices":[18,36,64],"presets":[]}"##
        defaults.set(Data(stored.utf8), forKey: PencilToolbox.storageKey)
        let relaunched = PencilToolbox(defaults: defaults)
        XCTAssertEqual(relaunched.eraserWidthChoices, [2, 6, 14])
        XCTAssertEqual(relaunched.eraserWidth, 14)
        XCTAssertEqual(relaunched.chosenEraserWidthIndex, 2)
    }

    func testTheSavedStateKeepsTheSameKeysSoEarlierBuildsCanReadIt() throws {
        let toolbox = PencilToolbox(defaults: defaults)
        toolbox.changeEraserWidthChoice(at: 0, to: 5)
        let saved = try XCTUnwrap(defaults.data(forKey: PencilToolbox.storageKey))
        let state = try XCTUnwrap(JSONSerialization.jsonObject(with: saved) as? [String: Any])
        XCTAssertEqual(state["eraserWidth"] as? Double, 5)
        XCTAssertEqual(state["eraserWidthChoices"] as? [Double], [5, 6, 14])
        XCTAssertEqual(PencilToolbox.storageKey, "GraphitePencilToolbox.v2", "The same record as before.")
    }

    func testTheFixedWidthEraserCutsNoLessThanPencilKitsFloorOnTheScreenSoZoomingInGivesAFinerCut() {
        let smallest = PencilEraserWidths.range.lowerBound
        XCTAssertEqual(PencilEraserWidths.widthOnPage(chosen: smallest, screenPointsPerPagePoint: 1), 16.4, accuracy: 0.0001, "At the page's size.")
        XCTAssertEqual(PencilEraserWidths.widthOnPage(chosen: smallest, screenPointsPerPagePoint: 4), 4.1, accuracy: 0.0001)
        XCTAssertEqual(PencilEraserWidths.widthOnPage(chosen: smallest, screenPointsPerPagePoint: 16.4), smallest, accuracy: 0.0001, "The chosen width, once the zoom allows it.")
        XCTAssertEqual(PencilEraserWidths.widthOnPage(chosen: 24, screenPointsPerPagePoint: 1.5), 24, accuracy: 0.0001, "HUNT-023: the same gap at any zoom.")
        XCTAssertEqual(PencilEraserWidths.widthOnPage(chosen: 64, screenPointsPerPagePoint: 3), 80.4 / 3, accuracy: 0.0001, "Up to PencilKit's widest.")
        XCTAssertEqual(PencilEraserWidths.widthOnPage(chosen: 6, screenPointsPerPagePoint: 0), 6)
    }

    #if canImport(PencilKit)
    func testPencilKitsLimitsAreTheOnesTheEraserCountsWith() {
        let fixedWidth = PKEraserTool.EraserType.fixedWidthBitmap
        XCTAssertEqual(Double(fixedWidth.validWidthRange.lowerBound), PencilEraserWidths.pencilKitWidthOnScreen.lowerBound, accuracy: 0.0001)
        XCTAssertEqual(Double(fixedWidth.validWidthRange.upperBound), PencilEraserWidths.pencilKitWidthOnScreen.upperBound, accuracy: 0.0001)
        // A width the eraser may have reaches PencilKit unchanged; the smallest, below its floor, is the floor.
        let smallest = PencilEraserWidths.range.lowerBound
        XCTAssertEqual(Double(PKEraserTool(fixedWidth, width: CGFloat(smallest * 20)).width), smallest * 20, accuracy: 0.0001)
        XCTAssertEqual(Double(PKEraserTool(fixedWidth, width: CGFloat(smallest)).width), PencilEraserWidths.pencilKitWidthOnScreen.lowerBound, accuracy: 0.0001)
        XCTAssertEqual(Double(PKEraserTool(fixedWidth, width: 100).width), PencilEraserWidths.pencilKitWidthOnScreen.upperBound, accuracy: 0.0001)
    }
    #endif
}
