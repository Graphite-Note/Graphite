/**
 * File: PencilBarFitTests.swift
 * -----------------------------
 * Layer: Tests
 * Description: Which form the Pencil bar takes at each width of the 11-inch iPad: every favorite color and the ruler on
 *              the bar upright, sideways and beside the sidebar, closer before anything moves into a menu (HUNT-317).
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 04/11/2026
 */

import XCTest
@testable import GraphiteUI

/// The owner's report of 2026-11-04: the colors used to be a row on the bar, and now needed a tap before choosing one;
/// the ruler and the other tools were behind the bar's "…". These tests take the bar's widths from
/// `PencilToolRowLayout`, the same numbers the bar is built with, at the widths of the 11-inch iPad: 1,194 points
/// sideways, about 874 sideways beside the sidebar, 834 upright and about 514 upright beside the sidebar. The hosted
/// `PencilBarPlacementHostedTests` measure the bar itself at those widths. Nothing here draws.
final class PencilBarFitTests: XCTestCase {
    private typealias Layout = PencilToolRowLayout

    /// A PDF's bar with the pen in use: three presets, the eraser, the lasso, the laser pointer, the text tool and the
    /// Read Aloud pen; three sizes; black and the eight default favorite colors.
    private func pensBar(presetCount: Int = 3, favoriteCount: Int = PaletteColor.defaultPalette.count, showsAddColor: Bool = false) -> Layout.Contents {
        Layout.Contents(tools: Layout.tools(presetCount: presetCount, offersTextBoxes: true, offersReadAloudPen: true), toolInUse: .preset(index: 0),
                        sizeCount: 3, offersColors: true, swatchCount: 1 + favoriteCount, showsAddColor: showsAddColor, offersImages: true)
    }

    private func width(_ arrangement: Layout.Arrangement, _ contents: Layout.Contents) throws -> Double {
        try XCTUnwrap(Layout.width(of: arrangement, holding: contents))
    }

    // MARK: The 11-inch iPad

    func testEveryColorAndTheRulerAreOnTheBarAtEveryWidthOfTheElevenInchIPad() throws {
        let contents = pensBar()
        XCTAssertEqual(Layout.arrangement(forWidth: 1_194, holding: contents), .whole(.regular), "Sideways: everything, at the regular spacing.")
        XCTAssertEqual(Layout.arrangement(forWidth: 874, holding: contents), .whole(.tight), "Sideways beside the sidebar: everything, closer.")
        XCTAssertEqual(Layout.arrangement(forWidth: 834, holding: contents), .whole(.tight), "Upright: everything, closer.")
        XCTAssertEqual(Layout.arrangement(forWidth: 514, holding: contents), .folded(.addImage),
                       "Upright beside the sidebar: every color and the ruler stay; the laser, text, Read Aloud, Shapes and Add Image go behind More.")
        XCTAssertEqual(Layout.arrangement(forWidth: 590, holding: contents), .folded(.occasionalTools),
                       "Sideways in half the screen: only the laser, text and Read Aloud tools go behind More.")
        XCTAssertEqual(Layout.arrangement(forWidth: 540, holding: contents), .folded(.choicesAndShapes), "Then Other Color and Shapes; Add Image stays.")
        // The widths the bar is built at, which the hosted tests measure on the bar itself.
        XCTAssertEqual(try width(.whole(.regular), contents), 883)
        XCTAssertEqual(try width(.whole(.tight), contents), 761)
        XCTAssertEqual(try width(.whole(.tightest), contents), 635)
        XCTAssertEqual(try width(.folded(.occasionalTools), contents), 579)
        XCTAssertEqual(try width(.folded(.choicesAndShapes), contents), 523)
        XCTAssertEqual(try width(.folded(.addImage), contents), 495)
    }

    func testTheBarStaysWholeUprightWithThePlusThatAddsTheColorInUse() throws {
        let contents = pensBar(showsAddColor: true)
        XCTAssertEqual(try width(.whole(.tight), contents), 789)
        XCTAssertEqual(Layout.arrangement(forWidth: 834, holding: contents), .whole(.tight))
    }

    func testTheSpacingAndTheDotsShrinkBeforeAnythingMovesIntoTheMoreControl() throws {
        let contents = pensBar()
        XCTAssertEqual(Layout.preferredArrangements, [.whole(.regular), .whole(.tight), .whole(.tightest),
                                                      .folded(.occasionalTools), .folded(.choicesAndShapes), .folded(.addImage)])
        let widths = try Layout.preferredArrangements.map { arrangement in try width(arrangement, contents) }
        XCTAssertEqual(widths, widths.sorted(by: >), "Each form tried is narrower than the one before.")
        XCTAssertEqual(Layout.arrangement(forWidth: 700, holding: contents), .whole(.tightest), "Everything, mini colors, before any menu.")
        for density in [Layout.Density.regular, .tight, .tightest] {
            XCTAssertLessThanOrEqual(density.swatchRingDiameter, density.swatchPitch, "The ring of the color in use stays inside its own width.")
            XCTAssertGreaterThanOrEqual(density.swatchDiameter, 16, "A color is still a dot a finger can aim at.")
        }
    }

    // MARK: The folded forms

    func testEachFoldStageMovesTheLeastUsedControlsFirstAndKeepsTheWritingOnesOnTheBar() throws {
        let contents = pensBar()
        let occasional = try XCTUnwrap(Layout.placement(of: .folded(.occasionalTools), holding: contents))
        XCTAssertEqual(occasional.foldedTools, [.laser, .text, .readAloud])
        XCTAssertTrue(occasional.showsToolChoices && occasional.showsOtherColor && occasional.showsShapes && occasional.showsAddImage)
        let choices = try XCTUnwrap(Layout.placement(of: .folded(.choicesAndShapes), holding: contents))
        XCTAssertFalse(choices.showsToolChoices || choices.showsOtherColor || choices.showsShapes)
        XCTAssertTrue(choices.showsAddImage)
        let addImage = try XCTUnwrap(Layout.placement(of: .folded(.addImage), holding: contents))
        XCTAssertFalse(addImage.showsAddImage)
        for placement in [occasional, choices, addImage] {
            XCTAssertEqual(placement.shownTools, [.preset(index: 0), .preset(index: 1), .preset(index: 2), .eraser, .lasso])
            XCTAssertTrue(placement.showsSwatches && placement.showsSizes && placement.showsRuler && placement.hasMoreControl)
            XCTAssertEqual(placement.density, .tightest, "Folding comes after the mini colors.")
        }
        let whole = try XCTUnwrap(Layout.placement(of: .whole(.tight), holding: contents))
        XCTAssertFalse(whole.hasMoreControl)
        XCTAssertTrue(whole.foldedTools.isEmpty)
        XCTAssertNil(Layout.placement(of: .condensed, holding: contents))
    }

    func testTheCompactBarKeepsTheToolsAPersonWritesWithAndTheToolInUse() {
        let tools = Layout.tools(presetCount: 3, offersTextBoxes: true, offersReadAloudPen: true)
        let split = Layout.compactSplit(tools, toolInUse: .preset(index: 1))
        XCTAssertEqual(split.shown, [.preset(index: 0), .preset(index: 1), .preset(index: 2), .eraser, .lasso])
        XCTAssertEqual(split.folded, [.laser, .text, .readAloud], "Used now and then: behind More, never lost.")
        XCTAssertEqual(Layout.compactSplit(tools, toolInUse: .laser).shown, [.preset(index: 0), .preset(index: 1), .preset(index: 2), .eraser, .lasso, .laser],
                       "The tool in use is always on the bar, in the bar's order.")
    }

    func testAToolWithoutColorsOrSizesKeepsTheWholeBarBesideTheSidebar() {
        var laserBar = pensBar()
        laserBar.toolInUse = .laser
        laserBar.sizeCount = 0
        laserBar.offersColors = false
        laserBar.swatchCount = 0
        laserBar.toolChoicesWidth = 110
        XCTAssertEqual(Layout.arrangement(forWidth: 514, holding: laserBar), .whole(.tight))
    }

    func testTheEraserAndItsKindStayOnTheWholeBarUpright() {
        var eraserBar = pensBar()
        eraserBar.toolInUse = .eraser
        eraserBar.toolChoicesWidth = 150
        XCTAssertEqual(Layout.arrangement(forWidth: 834, holding: eraserBar), .whole(.tightest))
    }

    // MARK: More colors than fit

    func testOnlyMoreFavoritesThanFitEvenAsMiniDotsScrollAndThenInWholeColors() throws {
        XCTAssertNil(Layout.scrollingColorsArrangement(forWidth: 514, holding: pensBar()), "The default colors all fit: nothing scrolls.")
        let manyColors = pensBar(favoriteCount: 16)
        let arrangement = Layout.arrangement(forWidth: 514, holding: manyColors)
        XCTAssertEqual(arrangement, .compactWithScrollingColors(visibleSwatchCount: 9))
        XCTAssertLessThanOrEqual(try width(arrangement, manyColors), 514)
        let widthWithoutColors = try width(.compactWithScrollingColors(visibleSwatchCount: 0), manyColors)
        let stripWidth = try width(arrangement, manyColors) - widthWithoutColors - Layout.Density.tightest.separatorWidth
        XCTAssertEqual(stripWidth.truncatingRemainder(dividingBy: Layout.Density.tightest.swatchPitch), 0, "The strip shows whole colors, none cut in half.")
        XCTAssertEqual(Layout.arrangement(forWidth: 1_194, holding: manyColors), .whole(.regular), "Sideways, seventeen colors still all fit.")
    }

    func testSixPresetsBesideTheSidebarScrollTheColorsRatherThanHideThem() {
        XCTAssertEqual(Layout.arrangement(forWidth: 514, holding: pensBar(presetCount: 6)), .compactWithScrollingColors(visibleSwatchCount: 6))
        XCTAssertEqual(Layout.arrangement(forWidth: 834, holding: pensBar(presetCount: 6)), .whole(.tightest))
    }

    func testABarTooNarrowForThreeColorsIsCondensed() {
        XCTAssertEqual(Layout.arrangement(forWidth: 320, holding: pensBar()), .condensed)
        XCTAssertEqual(Layout.arrangement(forWidth: 245, holding: pensBar()), .condensed)
        XCTAssertNil(Layout.width(of: .condensed, holding: pensBar()))
    }
}
