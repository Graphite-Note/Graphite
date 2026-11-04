/**
 * File: PencilBarFavoritesAndSizesTests.swift
 * -------------------------------------------
 * Layer: Tests
 * Description: The Pencil bar's own edits of the favorite colors (move, add, remove), the eraser's sizes in both of its
 *              kinds, and the device preferences following a change the bar stored (HUNT-312, HUNT-310).
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 04/11/2026
 */

import XCTest
@testable import GraphiteUI
import GraphiteCore
import GraphiteTestSupport

/// What the bar offers again after the owner's report of 2026-11-04 ("move around colors, add more colors to the presets,
/// change the thickness presets"), as values: nothing here draws.
@MainActor
final class PencilBarFavoritesAndSizesTests: XCTestCase {
    private var defaults: UserDefaults!
    private let red = PaletteColor(name: "red", hex: "#e93147")
    private let green = PaletteColor(name: "green", hex: "#08b94e")
    private let blue = PaletteColor(name: "blue", hex: "#086ddd")

    override func setUp() async throws {
        defaults = try IsolatedDeviceState.make(prefix: "PencilBarFavoritesAndSizesTests", for: self).preferences
    }

    // MARK: Moving, adding and removing a favorite color on the bar

    func testAColorMovesOnePlaceAndStaysAtEitherEnd() {
        let palette = [red, green, blue]
        XCTAssertEqual(FavoriteColorEditing.moving(green.id, .earlier, in: palette).map(\.name), ["green", "red", "blue"])
        XCTAssertEqual(FavoriteColorEditing.moving(green.id, .later, in: palette).map(\.name), ["red", "blue", "green"])
        XCTAssertEqual(FavoriteColorEditing.moving(red.id, .earlier, in: palette), palette, "The first color has nowhere earlier to go.")
        XCTAssertEqual(FavoriteColorEditing.moving(blue.id, .later, in: palette), palette)
        XCTAssertFalse(FavoriteColorEditing.canMove(red.id, .earlier, in: palette))
        XCTAssertTrue(FavoriteColorEditing.canMove(red.id, .later, in: palette))
        XCTAssertEqual(FavoriteColorEditing.moving(UUID(), .later, in: palette), palette, "A color the list does not have moves nothing.")
    }

    func testTheColorInUseIsAddedOnceUnderAFreeName() {
        let palette = [red, green]
        let added = FavoriteColorEditing.adding(hex: "#123ABC", to: palette)
        XCTAssertEqual(added.count, 3)
        XCTAssertEqual(added.last?.hex, TextColorMarkup.canonicalHex("#123abc"))
        XCTAssertEqual(added.last?.name, PaletteColorNames.unusedName(in: palette), "A name notes can use, which Settings › Colors can change.")
        XCTAssertEqual(FavoriteColorEditing.adding(hex: "#E93147", to: palette), palette, "Red is in the list already, however its hex is written.")
        XCTAssertEqual(FavoriteColorEditing.adding(hex: "not a color", to: palette), palette)
        XCTAssertTrue(FavoriteColorEditing.contains(hex: "#e93147", in: palette))
    }

    func testAColorIsRemovedAndTheOthersKeepTheirOrder() {
        XCTAssertEqual(FavoriteColorEditing.removing(green.id, from: [red, green, blue]).map(\.name), ["red", "blue"])
    }

    /// The bar stores its edit under the key Settings › Colors reads; the preferences already open take it, so the next
    /// change in Settings does not write the old list back over the bar's.
    func testPreferencesTakeThePaletteTheBarStored() async throws {
        let preferences = GraphitePreferences(defaults: defaults)
        let moved = FavoriteColorEditing.moving(preferences.colorPalette[1].id, .earlier, in: preferences.colorPalette)
        defaults.set(try JSONEncoder().encode(moved), forKey: GraphitePreferences.colorPaletteKey)
        try await waitUntil("the preferences take the bar's order") { preferences.colorPalette == moved }
        let highlighterColors = FavoriteColorEditing.adding(hex: "#a0a0ff", to: preferences.highlighterPalette)
        defaults.set(try JSONEncoder().encode(highlighterColors), forKey: GraphitePreferences.highlighterPaletteKey)
        try await waitUntil("the preferences take the bar's highlighter colors") { preferences.highlighterPalette == highlighterColors }
        preferences.colorPalette.append(PaletteColor(name: "grey", hex: "#888888"))
        XCTAssertEqual(GraphitePreferences.storedColorPalette(in: defaults).prefix(moved.count).map(\.id), moved.map(\.id),
                       "A change in Settings starts from the bar's order.")
    }

    // MARK: The eraser's sizes on the bar

    func testChoosingAnEraserSizeWhileItRemovesStrokesErasesPixelsAtThatWidth() {
        let toolbox = PencilToolbox(defaults: defaults)
        toolbox.use(.eraser)
        XCTAssertTrue(toolbox.erasesWholeStrokes)
        XCTAssertNil(toolbox.chosenEraserWidthIndex, "Removing whole strokes has no width.")
        toolbox.useEraserWidthChoice(at: 2)
        XCTAssertFalse(toolbox.erasesWholeStrokes)
        XCTAssertEqual(toolbox.eraserWidth, toolbox.eraserWidthChoices[2])
        XCTAssertEqual(toolbox.chosenEraserWidthIndex, 2)
        toolbox.changeEraserWidthChoice(at: 2, to: 80)
        XCTAssertEqual(toolbox.eraserWidthChoices[2], 80, "A second tap on the size changes it, its thickness preset.")
        XCTAssertEqual(PencilToolbox(defaults: defaults).eraserWidthChoices[2], 80, "The changed size is kept.")
        toolbox.useEraserWidthChoice(at: 9)
        XCTAssertEqual(toolbox.chosenEraserWidthIndex, 2, "A size the eraser does not have changes nothing.")
    }

    func testChoosingAnEraserSizeWithAnInkInUseTakesUpTheEraser() {
        let toolbox = PencilToolbox(defaults: defaults)
        XCTAssertEqual(toolbox.toolInUse, .ink)
        toolbox.useEraserWidthChoice(at: 0)
        XCTAssertEqual(toolbox.toolInUse, .eraser)
        XCTAssertEqual(toolbox.chosenEraserWidthIndex, 0)
    }

    func testTheInkSizesChangeTheirOwnWidthAndStayChosen() {
        let toolbox = PencilToolbox(defaults: defaults)
        toolbox.useWidthChoice(at: 0)
        XCTAssertEqual(toolbox.chosenWidthIndex, 0)
        toolbox.changeWidthChoice(at: 0, to: toolbox.presetInUse.ink.widthRange.lowerBound + 0.5)
        XCTAssertEqual(toolbox.chosenWidthIndex, 0, "The size in use takes its new width and stays the one chosen.")
        XCTAssertEqual(PencilToolbox(defaults: defaults).presetInUse.widthChoices[0], toolbox.presetInUse.widthChoices[0])
    }
}
