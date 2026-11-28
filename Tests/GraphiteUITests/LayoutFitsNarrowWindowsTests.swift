/**
 * File: LayoutFitsNarrowWindowsTests.swift
 * ----------------------------------------
 * Layer: Tests
 * Description: The decisions behind the iPad and iPhone layout in narrow windows: which Pencil tools stay on a bar,
 *              where they stand, and the phone's palette and bookmarks.
 *
 * Authors: Bahey Shalash
 * Version: 0.6
 * Date: 28/11/2026
 */

import XCTest
import SwiftUI
import GraphiteCore
@testable import GraphiteUI
import GraphiteTestSupport

/// The decisions behind the iPad and iPhone layout in narrow windows (section 13 of the bug hunt): which Pencil
/// tools stay on a narrow bar, where the tools stand, when the navigation bar gives way, and the palette's
/// commands on a phone. Nothing here draws.
@MainActor
final class LayoutFitsNarrowWindowsTests: XCTestCase {
    /// A PDF page's bar: three presets, the eraser, the lasso, the laser, the text highlighter, the text tool and the
    /// Read Aloud pen.
    private let pageTools = PencilToolRowLayout.tools(presetCount: 3, offersTextMarking: true, offersTextBoxes: true, offersReadAloudPen: true)

    // MARK: HUNT-262, HUNT-289, HUNT-265: the Pencil bar never scrolls

    func testTheToolsOfTheRowAreThePresetsThenTheOthersWhereThePageHasThem() {
        XCTAssertEqual(PencilToolRowLayout.tools(presetCount: 3, offersTextMarking: false, offersTextBoxes: false, offersReadAloudPen: false),
                       [.preset(index: 0), .preset(index: 1), .preset(index: 2), .eraser, .lasso, .laser])
        XCTAssertEqual(pageTools.suffix(3), [.textHighlighter, .text, .readAloud])
        XCTAssertEqual(PencilToolRowLayout.tools(presetCount: 0, offersTextMarking: false, offersTextBoxes: false, offersReadAloudPen: false),
                       [.eraser, .lasso, .laser])
    }

    /// The folded forms put the text highlighter behind More with the laser, the text tool and the Read Aloud pen, and
    /// keep it on the bar while it is in use; a drawing's bar has no text highlighter.
    func testTheFoldedBarShowsTheTextHighlighterWhileItIsInUse() {
        let split = PencilToolRowLayout.compactSplit(pageTools, toolInUse: .preset(index: 0))
        XCTAssertEqual(split.folded, [.laser, .textHighlighter, .text, .readAloud])
        XCTAssertEqual(PencilToolRowLayout.compactSplit(pageTools, toolInUse: .textHighlighter).shown,
                       [.preset(index: 0), .preset(index: 1), .preset(index: 2), .eraser, .lasso, .textHighlighter])
        XCTAssertFalse(PencilToolRowLayout.tools(presetCount: 3, offersTextMarking: false, offersTextBoxes: false, offersReadAloudPen: false)
            .contains(.textHighlighter))
    }

    func testABarWithRoomForAllTheToolsFoldsNone() {
        let split = PencilToolRowLayout.split(pageTools, showing: Int.max, toolInUse: .preset(index: 1))
        XCTAssertEqual(split.shown, pageTools)
        XCTAssertTrue(split.folded.isEmpty)
    }

    func testANarrowBarShowsTheFirstToolsAndFoldsTheRestIntoItsControl() {
        let split = PencilToolRowLayout.split(pageTools, showing: 4, toolInUse: .preset(index: 0))
        XCTAssertEqual(split.shown, Array(pageTools.prefix(4)))
        XCTAssertEqual(split.folded, Array(pageTools.dropFirst(4)), "Every tool is on the bar or behind its control, none is lost.")
    }

    func testTheToolInUseIsAlwaysOnTheBarEvenWhenItWouldHaveBeenFolded() {
        let split = PencilToolRowLayout.split(pageTools, showing: 3, toolInUse: .readAloud)
        XCTAssertTrue(split.shown.contains(.readAloud))
        XCTAssertEqual(split.shown.count, 3)
        XCTAssertEqual(split.shown, [.preset(index: 0), .preset(index: 1), .readAloud], "In the bar's order, the last place taken.")
        XCTAssertEqual(Set(split.shown + split.folded), Set(pageTools))
    }

    func testABarKeepsAtLeastOneToolAndIgnoresAToolItDoesNotHave() {
        XCTAssertEqual(PencilToolRowLayout.split(pageTools, showing: 0, toolInUse: .eraser).shown, [.eraser])
        let withoutReadAloud = PencilToolRowLayout.tools(presetCount: 3, offersTextMarking: true, offersTextBoxes: true, offersReadAloudPen: false)
        let split = PencilToolRowLayout.split(withoutReadAloud, showing: 2, toolInUse: .readAloud)
        XCTAssertEqual(split.shown, Array(withoutReadAloud.prefix(2)), "The Read Aloud pen is not on a page without text.")
    }

    // MARK: HUNT-264, HUNT-261: a split uses the fixed bar

    func testASplitUsesTheFixedBarWhateverSettingsChose() {
        XCTAssertEqual(PencilToolbarStyle.floating.inEffect(sharesWindowWithOtherSide: true), .fixed)
        XCTAssertEqual(PencilToolbarStyle.fixed.inEffect(sharesWindowWithOtherSide: true), .fixed)
        XCTAssertEqual(PencilToolbarStyle.floating.inEffect(sharesWindowWithOtherSide: false), .floating)
        XCTAssertEqual(PencilToolbarStyle.fixed.inEffect(sharesWindowWithOtherSide: false), .fixed)
    }

    // Docs/PDF-annotation-todo.md section 3: side by side, the iPad keeps the fixed bar

    func testAnIPadBesideAnotherAppKeepsTheFixedBarAndAPhoneUsesThePalette() {
        XCTAssertEqual(PencilToolbarStyle.fixed.shown(horizontalSizeClass: .compact, isPhone: false), .fixed,
                       "An iPad window beside another app is compact and keeps the fixed bar, whose colors scroll in its strip.")
        XCTAssertEqual(PencilToolbarStyle.fixed.shown(horizontalSizeClass: .regular, isPhone: false), .fixed)
        XCTAssertEqual(PencilToolbarStyle.floating.shown(horizontalSizeClass: .compact, isPhone: false), .floating)
        XCTAssertEqual(PencilToolbarStyle.fixed.shown(horizontalSizeClass: .compact, isPhone: true), .floating,
                       "A phone's compact width uses the system's palette, docked at the bottom.")
        XCTAssertEqual(PencilToolbarStyle.fixed.shown(horizontalSizeClass: .regular, isPhone: true), .fixed,
                       "A Max phone held sideways is regular in width and keeps the bar.")
    }

    // MARK: HUNT-274, HUNT-260: a phone held sideways

    func testAPhoneHeldSidewaysKeepsTheControlsInTheNavigationBar() {
        XCTAssertFalse(DocumentToolbarLayout.usesControlRow(detailWidth: 700, horizontalSizeClass: .regular, verticalSizeClass: .compact, toolbar: .iPad),
                       "A Max phone held sideways is regular in width and compact in height.")
        XCTAssertTrue(DocumentToolbarLayout.usesControlRow(detailWidth: 700, horizontalSizeClass: .regular, verticalSizeClass: .regular, toolbar: .iPad))
        XCTAssertTrue(DocumentToolbarLayout.usesControlRow(detailWidth: 700, horizontalSizeClass: .regular, toolbar: .iPad), "An iPad: no vertical class given.")
    }

    func testTheBarsGiveWayToTheNoteWhileTypingInACompactHeight() {
        XCTAssertTrue(DocumentToolbarLayout.hidesChromeWhileTyping(verticalSizeClass: .compact, isKeyboardShown: true))
        XCTAssertFalse(DocumentToolbarLayout.hidesChromeWhileTyping(verticalSizeClass: .compact, isKeyboardShown: false), "They come back with the keyboard's going.")
        XCTAssertFalse(DocumentToolbarLayout.hidesChromeWhileTyping(verticalSizeClass: .regular, isKeyboardShown: true), "An iPad or a phone held upright keeps them.")
        XCTAssertFalse(DocumentToolbarLayout.hidesChromeWhileTyping(verticalSizeClass: nil, isKeyboardShown: true))
    }

    // MARK: HUNT-285

    func testATypedPageNumberStaysInsideThePDF() {
        let pages = 1...400
        XCTAssertEqual(ReadAloudPageNumberInput.page(typing: "399", in: pages), 399)
        XCTAssertEqual(ReadAloudPageNumberInput.page(typing: "0", in: pages), 1)
        XCTAssertEqual(ReadAloudPageNumberInput.page(typing: "9999", in: pages), 400)
        XCTAssertEqual(ReadAloudPageNumberInput.page(typing: "99999999999999999999", in: pages), 400, "Past any PDF, not an overflow.")
        XCTAssertEqual(ReadAloudPageNumberInput.page(typing: "2", in: 5...400), 5, "The last page is never before the first.")
        XCTAssertNil(ReadAloudPageNumberInput.page(typing: "", in: pages), "An emptied field waits for digits.")
        XCTAssertNil(ReadAloudPageNumberInput.page(typing: "abc", in: pages))
    }

    // MARK: HUNT-281, HUNT-287

    private func makeWindowActions() -> WindowActions {
        WindowActions(showQuickSwitcher: {}, showSettings: {}, showVaultManager: {}, toggleLinksInspector: {},
                      toggleSidebar: {}, showSidebar: {}, showLinksInspector: {}, create: { _ in }, showTemplatePicker: {},
                      showTabOverview: {}, toggleFocusMode: {})
    }

    func testThePaletteOffersNoSplitOnAPhone() async throws {
        let device = try IsolatedWorkspaceDevice.make(for: self)
        let vault = try TemporaryVault.make(prefix: "PaletteSplitVault", files: ["Note.md": "# Note\n"], for: self).root
        let workspace = device.makeWorkspace()
        try await workspace.openFolderAsVault(vault)
        await workspace.open(try VaultPath("Note.md"))

        let onTablet = WorkspaceCommandList.commands(for: workspace, window: makeWindowActions()).map(\.id)
        let onPhone = WorkspaceCommandList.commands(for: workspace, window: makeWindowActions(), offersSplit: false).map(\.id)

        let splitCommands: Set = ["split-right", "split-down", "move-tab"]
        XCTAssertTrue(splitCommands.isSubset(of: onTablet))
        XCTAssertTrue(splitCommands.isDisjoint(with: onPhone), "Split right or down would only make an empty second group of tabs.")
        XCTAssertEqual(onPhone.filter { identifier in !splitCommands.contains(identifier) },
                       onTablet.filter { identifier in !splitCommands.contains(identifier) }, "Nothing else changes.")
    }

    func testAGraphBookmarkOpensTheGraphView() async throws {
        let device = try IsolatedWorkspaceDevice.make(for: self)
        let vault = try TemporaryVault.make(prefix: "GraphBookmarkVault", files: ["Note.md": "# Note\n"], for: self).root
        let workspace = device.makeWorkspace()
        try await workspace.openFolderAsVault(vault)
        let graphBookmark = Bookmark(fields: ["type": .string("graph"), "ctime": .integer(1_700_000_000_000)])

        await workspace.open(graphBookmark)

        XCTAssertEqual(workspace.layout.activeTab.coreView, .graph)
    }

    /// HUNT-146: a portrait iPad with the sidebar open leaves the documents about 430 points. Pages and find stay there,
    /// with the title shortened for them; adding pages goes to More first; narrower, they fold too, so the title and More
    /// stay (the report of 2026-10-13). The sidebar holds the window's controls, so without it the bar has less room.
    func testPagesAndFindStayBesideTheTitleBeforeAddingPagesAndFoldOnlyWhenTheyDoNotFit() {
        func foldsFindAndPages(_ width: CGFloat?, sidebarIsBeside: Bool, sizeClass: UserInterfaceSizeClass? = .regular) -> Bool {
            DocumentToolbarLayout.foldsFindAndPages(detailWidth: width, horizontalSizeClass: sizeClass, sidebarIsBeside: sidebarIsBeside)
        }
        XCTAssertFalse(foldsFindAndPages(430, sidebarIsBeside: true), "Portrait with the sidebar open keeps them.")
        XCTAssertTrue(DocumentToolbarLayout.foldsSecondaryActions(detailWidth: 430, horizontalSizeClass: .regular), "Adding pages stays in More there.")
        XCTAssertFalse(DocumentToolbarLayout.foldsSecondaryActions(detailWidth: 760, horizontalSizeClass: .regular), "All three fit from the width they always did.")
        XCTAssertTrue(foldsFindAndPages(400, sidebarIsBeside: true), "Narrower they would push the title out.")
        XCTAssertTrue(foldsFindAndPages(430, sidebarIsBeside: false), "A window this narrow also shows its own controls in the bar.")
        XCTAssertFalse(foldsFindAndPages(590, sidebarIsBeside: false))
        XCTAssertTrue(foldsFindAndPages(1_000, sidebarIsBeside: true, sizeClass: .compact), "A compact width has them in More, as ever.")
        XCTAssertFalse(foldsFindAndPages(nil, sidebarIsBeside: true), "An unknown width folds nothing, as adding pages.")
        let widthAtTheEdge = DocumentToolbarLayout.minimumDetailWidthForFindAndPages(sidebarIsBeside: true)
        let spent = DocumentToolbarLayout.toolbarFixedWidth + 2 * DocumentToolbarLayout.toolbarSlotWidth
        XCTAssertGreaterThanOrEqual(widthAtTheEdge - spent, DocumentToolbarLayout.minimumToolbarTitleWidth, "The title keeps a readable width.")
    }
}
