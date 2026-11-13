/**
 * File: PencilColorArrangementTests.swift
 * ---------------------------------------
 * Layer: Tests
 * Description: Where a color dragged along the Pencil bar lands for every drop place (first, last, past either end, on
 *              itself), how the others slide aside, when a drag removes it, when the strip scrolls under it, and the
 *              palette edits a drop, a color picker and Undo make (Docs/Pen-color-palette-todo.md section 1).
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 13/11/2026
 */

import XCTest
@testable import GraphiteUI
import GraphiteCore

/// The owner's request of 2026-11-13: arrange the bar's colors by dragging, as in Apple's markup palette. Values only.
final class PencilColorArrangementTests: XCTestCase {
    private let red = PaletteColor(name: "red", hex: "#e93147")
    private let orange = PaletteColor(name: "orange", hex: "#ec7500")
    private let green = PaletteColor(name: "green", hex: "#08b94e")
    private let blue = PaletteColor(name: "blue", hex: "#086ddd")
    private var palette: [PaletteColor] { [red, orange, green, blue] }
    /// Four colors 32 points apart, removed past 44 points across the row: the regular bar.
    private let arrangement = PencilColorArrangement(colorCount: 4, swatchPitch: 32, removalDistance: 44)

    // MARK: Drop places

    func testADropLandsOnTheNearestPlaceAndClampsPastEitherEnd() {
        XCTAssertEqual(arrangement.destinationIndex(draggedFrom: 1, horizontalTravel: 0), 1, "On itself.")
        XCTAssertEqual(arrangement.destinationIndex(draggedFrom: 1, horizontalTravel: 15), 1, "Less than half a place stays.")
        XCTAssertEqual(arrangement.destinationIndex(draggedFrom: 1, horizontalTravel: 17), 2, "More than half a place moves on.")
        XCTAssertEqual(arrangement.destinationIndex(draggedFrom: 1, horizontalTravel: -32), 0, "The first place.")
        XCTAssertEqual(arrangement.destinationIndex(draggedFrom: 1, horizontalTravel: 64), 3, "The last place.")
        XCTAssertEqual(arrangement.destinationIndex(draggedFrom: 1, horizontalTravel: -500), 0, "Past the start.")
        XCTAssertEqual(arrangement.destinationIndex(draggedFrom: 2, horizontalTravel: 500), 3, "Past the end.")
        XCTAssertEqual(arrangement.destinationIndex(draggedFrom: 0, horizontalTravel: .nan), 0)
    }

    func testEveryDropPlaceGivesThePaletteInThatOrder() {
        let names = { (colors: [PaletteColor]) in colors.map(\.name) }
        XCTAssertEqual(names(FavoriteColorEditing.moving(green.id, toIndex: 0, in: palette)), ["green", "red", "orange", "blue"])
        XCTAssertEqual(names(FavoriteColorEditing.moving(red.id, toIndex: 3, in: palette)), ["orange", "green", "blue", "red"])
        XCTAssertEqual(names(FavoriteColorEditing.moving(orange.id, toIndex: 2, in: palette)), ["red", "green", "orange", "blue"])
        XCTAssertEqual(names(FavoriteColorEditing.moving(blue.id, toIndex: 1, in: palette)), ["red", "blue", "orange", "green"])
        XCTAssertEqual(FavoriteColorEditing.moving(orange.id, toIndex: 1, in: palette), palette, "A drop on its own place changes nothing.")
        XCTAssertEqual(names(FavoriteColorEditing.moving(orange.id, toIndex: -4, in: palette)), ["orange", "red", "green", "blue"])
        XCTAssertEqual(names(FavoriteColorEditing.moving(orange.id, toIndex: 40, in: palette)), ["red", "green", "blue", "orange"])
        XCTAssertEqual(FavoriteColorEditing.moving(UUID(), toIndex: 0, in: palette), palette, "A color the list does not have moves nothing.")
    }

    // MARK: Sliding aside

    func testTheColorsBetweenTheTwoPlacesSlideOnePlaceTowardsTheDraggedColorsPlace() {
        let rightwards = PencilColorArrangement.Outcome.arranged(destinationIndex: 3)
        XCTAssertEqual((0..<4).map { index in arrangement.slideOffset(ofColorAt: index, draggedFrom: 1, outcome: rightwards) }, [0, 0, -32, -32])
        let leftwards = PencilColorArrangement.Outcome.arranged(destinationIndex: 0)
        XCTAssertEqual((0..<4).map { index in arrangement.slideOffset(ofColorAt: index, draggedFrom: 2, outcome: leftwards) }, [32, 32, 0, 0])
        let inPlace = PencilColorArrangement.Outcome.arranged(destinationIndex: 2)
        XCTAssertEqual((0..<4).map { index in arrangement.slideOffset(ofColorAt: index, draggedFrom: 2, outcome: inPlace) }, [0, 0, 0, 0])
    }

    // MARK: Removing

    func testADragFarAcrossTheRowRemovesAndTheLaterColorsCloseUp() {
        XCTAssertEqual(arrangement.outcome(draggedFrom: 1, horizontalTravel: 40, verticalTravel: -30), .arranged(destinationIndex: 2))
        XCTAssertEqual(arrangement.outcome(draggedFrom: 1, horizontalTravel: 40, verticalTravel: -45), .removed, "Up and off the bar.")
        XCTAssertEqual(arrangement.outcome(draggedFrom: 1, horizontalTravel: 0, verticalTravel: 60), .removed, "Down and off the bar.")
        XCTAssertEqual((0..<4).map { index in arrangement.slideOffset(ofColorAt: index, draggedFrom: 1, outcome: .removed) }, [0, 0, -32, -32])
    }

    func testARemovedColorIsPutBackAtItsPlaceOnce() {
        let withoutGreen = FavoriteColorEditing.removing(green.id, from: palette)
        XCTAssertEqual(FavoriteColorEditing.puttingBack(green, at: 2, in: withoutGreen), palette)
        XCTAssertEqual(FavoriteColorEditing.puttingBack(green, at: 9, in: [red]).map(\.name), ["red", "green"], "At the end of a shorter list.")
        XCTAssertEqual(FavoriteColorEditing.puttingBack(green, at: 0, in: palette), palette, "Not twice.")
        let greenAddedAgain = FavoriteColorEditing.adding(hex: green.hex, to: withoutGreen)
        XCTAssertEqual(FavoriteColorEditing.puttingBack(green, at: 2, in: greenAddedAgain), greenAddedAgain, "Not when its hex came back already.")
    }

    // MARK: The color picker of a second tap

    func testThePickerChangesTheColorsHexUnlessAnotherColorHasIt() {
        let changed = FavoriteColorEditing.changingHex(of: orange.id, to: "#123ABC", in: palette)
        XCTAssertEqual(changed.map(\.name), palette.map(\.name), "The color keeps its name and place.")
        XCTAssertEqual(changed[1].hex, TextColorMarkup.canonicalHex("#123abc"))
        XCTAssertEqual(FavoriteColorEditing.changingHex(of: orange.id, to: "#E93147", in: palette), palette, "Red is in the list already.")
        XCTAssertEqual(FavoriteColorEditing.changingHex(of: orange.id, to: "no color", in: palette), palette)
    }

    // MARK: Scrolling under a drag

    func testTheStripScrollsOnlyWhileTheDragIsNearAnEnd() {
        let strip = PencilColorArrangement(colorCount: 8, swatchPitch: 22, removalDistance: 44)
        XCTAssertEqual(strip.scrollDirection(atVisibleLocation: 5, visibleWidth: 132), -1)
        XCTAssertEqual(strip.scrollDirection(atVisibleLocation: 66, visibleWidth: 132), 0)
        XCTAssertEqual(strip.scrollDirection(atVisibleLocation: 128, visibleWidth: 132), 1)
        XCTAssertEqual(strip.scrollDirection(atVisibleLocation: 5, visibleWidth: 20), 0, "Too narrow to have ends.")
    }
}
