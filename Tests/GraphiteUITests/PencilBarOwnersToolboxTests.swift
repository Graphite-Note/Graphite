/**
 * File: PencilBarOwnersToolboxTests.swift
 * ---------------------------------------
 * Layer: Tests
 * Description: The Pencil bar with the owner's own toolbox (a monoline, a pencil and a highlighter, no pen) and with the
 *              other toolboxes a person could set up: every favorite color, the ruler, the writing tools and Add Image
 *              stay buttons on the 11-inch iPad's bar upright and sideways, and only the least used controls fold
 *              (HUNT-317).
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 04/11/2026
 */

import XCTest
@testable import GraphiteUI
import GraphiteTestSupport

/// A hosted run on the owner's iPad found his toolbox has no pen preset, and before HUNT-317 his upright bar folded to
/// the compact row, with the laser, text and Read Aloud tools, Shapes, Other Color and Add Image behind its More
/// control. These tests set his toolbox up through the toolbox's own store, as the app reads it at launch, and ask the
/// layout which form each width of the 11-inch iPad shows and what is on the bar in it. The hosted
/// `PencilBarPlacementHostedTests.testTheOwnersToolboxKeepsEveryColorTheRulerAndTheWritingToolsOnTheBar` measures the
/// bar itself with the same toolbox. Nothing here draws.
@MainActor
final class PencilBarOwnersToolboxTests: XCTestCase {
    private typealias Layout = PencilToolRowLayout

    /// The owner's toolbox as the store keeps it (`GraphitePencilToolbox.v2`): the tool kinds, colors, widths and
    /// counts of his iPad's settings of 2026-11-04, nothing else of them. The hosted test holds the same record.
    static let ownersToolboxRecord = """
    {"toolInUse":"ink","presetInUseIndex":0,"erasesWholeStrokes":false,"eraserWidth":4,"eraserWidthChoices":[4,36,64],"presets":[
    {"id":"7D0E3C1A-0000-4000-8000-000000000001","ink":"monoline","colorHex":"#086ddd","width":1.6,"widthChoices":[0.5,1.6,3],"opacity":1},
    {"id":"7D0E3C1A-0000-4000-8000-000000000002","ink":"pencil","colorHex":"#e93147","width":2.4,"widthChoices":[2.4,4,7],"opacity":1},
    {"id":"7D0E3C1A-0000-4000-8000-000000000003","ink":"highlighter","colorHex":"#8fe378","width":18,"widthChoices":[10,18,28],"opacity":0.33}]}
    """

    /// The widths of the system's segmented pickers beside the eraser (Strokes, Pixels) and the lasso (Freehand,
    /// Rectangle) on the whole bar, rounded up; only the bar measures them, and the hosted test measures the bar.
    static let eraserChoicesWidth = 150.0
    static let lassoChoicesWidth = 180.0

    /// The side's width on the 11-inch iPad with the tab bar holding Undo, Redo and Write: sideways, sideways beside
    /// the sidebar, upright.
    static let elevenInchWidths: [Double] = [1_194, 874, 834]

    /// Upright in Focus, where no tab bar holds Undo, Redo and Write and the bar shares its row with them: 834 points
    /// less the margins of 16 at each end, the gaps of 12, Undo and Redo of about 28 points each and Write of 36.
    static let uprightBesideUndoRedoAndWrite: Double = 834 - (16 + 12 + 28 + 12 + 28 + 12 + 36 + 16)

    private func ownersToolbox() throws -> PencilToolbox {
        let defaults = try IsolatedDeviceState.make(prefix: "PencilBarOwnersToolbox", for: self).preferences
        defaults.set(Data(Self.ownersToolboxRecord.utf8), forKey: PencilToolbox.storageKey)
        return PencilToolbox(defaults: defaults)
    }

    /// What a PDF's bar holds with `toolbox` and the default colors: the text tool and, as on his iPad, the Read Aloud pen.
    private func barContents(of toolbox: PencilToolbox) -> Layout.Contents {
        var contents = Layout.contents(of: toolbox, favorites: PaletteColor.defaultPalette, highlighterColors: PaletteColor.defaultHighlighterPalette,
                                       offersTextBoxes: true, offersReadAloudPen: true, offersImages: true)
        switch toolbox.toolInUse {
        case .eraser: contents.toolChoicesWidth = Self.eraserChoicesWidth
        case .lasso: contents.toolChoicesWidth = Self.lassoChoicesWidth
        default: break
        }
        return contents
    }

    /// The tools each form switches between while writing, for the owner's three presets: each ink, the eraser and the lasso.
    private func takeUpEachWritingTool(of toolbox: PencilToolbox, _ check: (String) throws -> Void) rethrows {
        for presetIndex in toolbox.presets.indices {
            toolbox.usePreset(at: presetIndex)
            try check(toolbox.presets[presetIndex].ink.title)
        }
        for kind in [PencilToolKind.eraser, .lasso] {
            toolbox.use(kind)
            try check(kind.title)
        }
    }

    // MARK: The owner's toolbox

    func testTheStoreReadsTheOwnersToolboxWithoutAPen() throws {
        let toolbox = try ownersToolbox()
        XCTAssertEqual(toolbox.presets.map(\.ink), [.monoline, .pencil, .highlighter], "His record is read, not replaced by the default presets.")
        XCTAssertFalse(toolbox.presets.contains { preset in preset.ink == .pen })
        XCTAssertEqual(toolbox.presetInUse.colorHex, "#086ddd", "His monoline writes in the favorite blue, so no plus shows.")
        XCTAssertFalse(toolbox.erasesWholeStrokes)
    }

    func testTheOwnersToolboxKeepsEveryColorTheRulerTheWritingToolsAndAddImageOnTheBar() throws {
        let toolbox = try ownersToolbox()
        for width in Self.elevenInchWidths + [Self.uprightBesideUndoRedoAndWrite] {
            try takeUpEachWritingTool(of: toolbox) { toolName in
                let contents = barContents(of: toolbox)
                let arrangement = Layout.arrangement(forWidth: width, holding: contents)
                let placement = try XCTUnwrap(Layout.placement(of: arrangement, holding: contents), "\(toolName) at \(width): not condensed.")
                print("Owner's toolbox, \(toolName) in use, \(Int(width)) points: \(arrangement), folded \(placement.foldedTools)")
                assertTheWritingControlsAreOnTheBar(placement, holding: contents, "\(toolName) at \(Int(width)) points")
            }
        }
    }

    func testTheOwnersBarFoldsNothingUprightOrSidewaysWhileWritingWithAnInk() throws {
        let toolbox = try ownersToolbox()
        for presetIndex in toolbox.presets.indices {
            toolbox.usePreset(at: presetIndex)
            let ink = toolbox.presetInUse.ink.title
            XCTAssertEqual(Layout.arrangement(forWidth: 1_194, holding: barContents(of: toolbox)), .whole(.regular), "\(ink) sideways.")
            let upright = Layout.arrangement(forWidth: 834, holding: barContents(of: toolbox))
            XCTAssertTrue([Layout.Arrangement.whole(.regular), .whole(.tight)].contains(upright), "\(ink) upright: at most the gaps are smaller (\(upright)).")
        }
        XCTAssertEqual(Layout.arrangement(forWidth: 834, holding: barContents(of: toolbox)), .whole(.regular), "The highlighter's six colors fit sideways' spacing.")
        toolbox.usePreset(at: 0)
        XCTAssertEqual(Layout.arrangement(forWidth: 834, holding: barContents(of: toolbox)), .whole(.tight), "The monoline with black and eight favorites.")
        toolbox.use(.eraser)
        XCTAssertEqual(Layout.arrangement(forWidth: 834, holding: barContents(of: toolbox)), .whole(.tightest),
                       "The eraser upright, with Strokes or Pixels beside it: smaller gaps and mini colors, nothing folded.")
        toolbox.usePreset(at: 0)
        XCTAssertEqual(Layout.arrangement(forWidth: Self.uprightBesideUndoRedoAndWrite, holding: barContents(of: toolbox)), .whole(.tightest),
                       "Beside Undo, Redo and Write, the monoline's bar still folds nothing.")
    }

    func testBesideUndoRedoAndWriteTheEraserFoldsOnlyTheLeastUsedControls() throws {
        let toolbox = try ownersToolbox()
        toolbox.use(.eraser)
        let contents = barContents(of: toolbox)
        let arrangement = Layout.arrangement(forWidth: Self.uprightBesideUndoRedoAndWrite, holding: contents)
        XCTAssertEqual(arrangement, .folded(.choicesAndShapes))
        let placement = try XCTUnwrap(Layout.placement(of: arrangement, holding: contents))
        XCTAssertEqual(placement.foldedTools, [.laser, .text, .readAloud])
        XCTAssertFalse(placement.showsToolChoices, "Strokes or Pixels is in More.")
        XCTAssertFalse(placement.showsShapes)
        XCTAssertTrue(placement.showsAddImage, "Add Image stays on the bar.")
    }

    // MARK: Toolboxes a person could set up

    /// Every count of pens, pencils and highlighters from none to four that the toolbox holds (one to six presets), with
    /// none to twelve favorite colors, each ink, the eraser and the lasso in use, and the plus showing for an ink: at
    /// 834 and 1,194 points every preset, the eraser, the lasso, the ruler, Add Image and every color are on the bar.
    func testEveryToolboxAPersonCouldSetUpKeepsTheWritingControlsOnTheBarUprightAndSideways() throws {
        var checkedCount = 0
        for penCount in 0...4 { for pencilCount in 0...4 { for highlighterCount in 0...4 {
            let inks = Array(repeating: PencilInk.pen, count: penCount) + Array(repeating: .pencil, count: pencilCount)
                + Array(repeating: .highlighter, count: highlighterCount)
            guard (1...PencilToolbox.maximumPresetCount).contains(inks.count) else { continue }
            for favoriteCount in 0...12 {
                for (toolName, contents) in barContents(inks: inks, favoriteCount: favoriteCount) {
                    for width in [834.0, 1_194] {
                        let arrangement = Layout.arrangement(forWidth: width, holding: contents)
                        let label = "\(penCount) pens, \(pencilCount) pencils, \(highlighterCount) highlighters, \(favoriteCount) favorites, \(toolName), \(Int(width))"
                        let placement = try XCTUnwrap(Layout.placement(of: arrangement, holding: contents), "\(label): not condensed.")
                        assertTheWritingControlsAreOnTheBar(placement, holding: contents, label)
                        if width == 1_194, inks.count <= 3, toolName != "eraser", toolName != "lasso" {
                            XCTAssertFalse(placement.hasMoreControl, "\(label): sideways, three presets and an ink fold nothing.")
                        }
                        checkedCount += 1
                    }
                }
            }
        } } }
        XCTAssertGreaterThan(checkedCount, 10_000)
    }

    /// The bar's contents for `inks` with each of them, the eraser and the lasso in use.
    private func barContents(inks: [PencilInk], favoriteCount: Int) -> [(String, Layout.Contents)] {
        let tools = Layout.tools(presetCount: inks.count, offersTextBoxes: true, offersReadAloudPen: true)
        let highlighterColorCount = PaletteColor.defaultHighlighterPalette.count
        var contents = inks.enumerated().map { presetIndex, ink in
            ("\(ink.title) \(presetIndex)", Layout.Contents(tools: tools, toolInUse: .preset(index: presetIndex), sizeCount: 3, offersColors: true,
                                                            swatchCount: ink == .highlighter ? highlighterColorCount : 1 + favoriteCount,
                                                            showsAddColor: true, offersImages: true))
        }
        let swatchCountOfTheLastInk = inks.last == .highlighter ? highlighterColorCount : 1 + favoriteCount
        contents.append(("eraser", Layout.Contents(tools: tools, toolInUse: .eraser, sizeCount: 3, offersColors: true, swatchCount: swatchCountOfTheLastInk,
                                                    showsAddColor: false, offersImages: true, toolChoicesWidth: Self.eraserChoicesWidth)))
        contents.append(("lasso", Layout.Contents(tools: tools, toolInUse: .lasso, sizeCount: 0, offersColors: true, swatchCount: swatchCountOfTheLastInk,
                                                   showsAddColor: false, offersImages: true, toolChoicesWidth: Self.lassoChoicesWidth)))
        return contents
    }

    private func assertTheWritingControlsAreOnTheBar(_ placement: Layout.Placement, holding contents: Layout.Contents, _ label: String,
                                                     file: StaticString = #filePath, line: UInt = #line) {
        let presets = contents.tools.filter { tool in if case .preset = tool { true } else { false } }
        XCTAssertTrue(presets.allSatisfy(placement.shownTools.contains), "\(label): every ink preset is on the bar.", file: file, line: line)
        XCTAssertTrue(placement.shownTools.contains(.eraser) && placement.shownTools.contains(.lasso), "\(label): the eraser and the lasso.",
                      file: file, line: line)
        if let toolInUse = contents.toolInUse { XCTAssertTrue(placement.shownTools.contains(toolInUse), "\(label): the tool in use.", file: file, line: line) }
        XCTAssertTrue(placement.showsSwatches, "\(label): the colors are on the bar.", file: file, line: line)
        XCTAssertNil(placement.scrollingSwatchCount, "\(label): every color is on the bar; none scrolls.", file: file, line: line)
        XCTAssertTrue(placement.showsRuler, "\(label): the ruler.", file: file, line: line)
        XCTAssertTrue(placement.showsAddImage, "\(label): Add Image.", file: file, line: line)
        XCTAssertGreaterThanOrEqual(placement.density.swatchDiameter, 16, "\(label): dots no smaller than the mini ones.", file: file, line: line)
    }
}
