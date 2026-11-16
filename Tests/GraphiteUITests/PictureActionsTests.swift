/**
 * File: PictureActionsTests.swift
 * -------------------------------
 * Layer: Tests
 * Description: What a picture of a note offers and does: its commands and their wording, a ⌘-click to a tab, the
 *              menu its text link gives, a rendered block's menu, and the buttons shown while the pointer rests on it.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 11/11/2026
 */

import XCTest
import SwiftUI
import Textual
import GraphiteCore
@testable import GraphiteUI
import GraphiteTestSupport

/// The commands of a picture shown in a note (Zoom In, Open in New Tab, the other side), declared
/// once in `PictureCommand` and run through `ReadingImageActions`, wherever the picture is drawn.
@MainActor
final class PictureActionsTests: XCTestCase {
    // XCTest makes a new test case for each test, so each starts with these empty.
    private var zoomedPaths: [VaultPath] = []
    private var openedPictures: [(VaultPath, GraphiteUI.TabPlacement)] = []

    private func actions(withTabs: Bool = true) -> ReadingImageActions {
        ReadingImageActions(providerIdentity: ObjectIdentifier(self), viewImage: { [weak self] path in self?.zoomedPaths.append(path) }, editDrawing: nil,
                            tabOpening: withTabs ? PictureTabOpening(open: { [weak self] path, placement in self?.openedPictures.append((path, placement)) },
                                                                     otherSideTitle: "Open to the Right") : nil)
    }

    private func zoomLink(_ rawPath: String) throws -> URL {
        try XCTUnwrap(GraphiteOpenLink.zoomedImageLink(path: try VaultPath(rawPath)))
    }

    func testAPictureOffersZoomingAndTheTabsInMenuOrderWithTheWindowsWording() {
        XCTAssertEqual(actions(withTabs: false).offeredCommands, [.zoomIn], "Without tabs a picture only zooms.")
        let tabbed = actions()
        XCTAssertEqual(tabbed.offeredCommands, [.zoomIn, .openInNewTab, .openOnOtherSide])
        XCTAssertEqual(tabbed.offeredCommands.map(tabbed.title(of:)), ["Zoom In", "Open in New Tab", "Open to the Right"])
        XCTAssertEqual(PictureCommand.openInNewTab.systemImage, VaultEntryAction.openInNewTab.systemImage, "The file tree's wording and symbol, declared once.")
        XCTAssertEqual(PictureCommand.hoverButtons, [.zoomIn, .openInNewTab])
    }

    func testEachCommandZoomsOrOpensThePictureInItsPlace() throws {
        let picture = try VaultPath("Figures/Scan.png")
        let tabbed = actions()
        tabbed.perform(.zoomIn, on: picture)
        tabbed.perform(.openInNewTab, on: picture)
        tabbed.perform(.openOnOtherSide, on: picture)
        XCTAssertEqual(zoomedPaths, [picture])
        XCTAssertEqual(openedPictures.map(\.0), [picture, picture])
        XCTAssertEqual(openedPictures.map(\.1), [.newTab, .otherGroup])
    }

    func testACommandClickOpensWhereALinkWouldAndAPlainClickIsLeftToZoom() throws {
        XCTAssertNil(PictureTabOpening.placement(forClickWith: []))
        XCTAssertNil(PictureTabOpening.placement(forClickWith: .shift))
        XCTAssertEqual(PictureTabOpening.placement(forClickWith: .command), .newTab)
        XCTAssertEqual(PictureTabOpening.placement(forClickWith: [.command, .option]), .otherGroup)
        XCTAssertEqual(PictureTabOpening.placement(forClickWith: [.command, .option, .shift]), .newWindow)

        let picture = try VaultPath("Scan.png")
        XCTAssertFalse(actions().open(picture, clickedWith: []), "A plain click zooms.")
        XCTAssertFalse(actions(withTabs: false).open(picture, clickedWith: .command), "Without tabs ⌘-click zooms too.")
        XCTAssertTrue(actions().open(picture, clickedWith: .command))
        XCTAssertEqual(openedPictures.map(\.1), [.newTab])
    }

    /// A picture inside text links to its zoom; the text's link gives it the picture's menu and
    /// ⌘-click. A note link, a web address and a web image (which has no zoom link) get neither.
    func testThePictureLinkOfATextHasThePicturesMenuAndOtherLinksHaveNone() throws {
        let interactions = actions().textLinkInteractions()
        let link = try zoomLink("Figures/Scan 2) final.png")
        let items = interactions.menuItems(link)
        XCTAssertEqual(items.map(\.title), ["Zoom In", "Open in New Tab", "Open to the Right"])
        XCTAssertEqual(items.map(\.systemImage), PictureCommand.allCases.map(\.systemImage))
        items[1].action()
        XCTAssertEqual(openedPictures.map(\.0), [try VaultPath("Figures/Scan 2) final.png")])
        XCTAssertEqual(openedPictures.map(\.1), [.newTab])
        items[0].action()
        XCTAssertEqual(zoomedPaths, [try VaultPath("Figures/Scan 2) final.png")])

        let noteLink = try XCTUnwrap(URL(string: GraphiteOpenLink.markdownDestination(target: "Lecture")))
        let webPage = try XCTUnwrap(URL(string: "https://example.com/chart.png"))
        for otherLink in [noteLink, webPage] {
            XCTAssertEqual(interactions.menuItems(otherLink).count, 0, "\(otherLink) keeps the text's menu")
            XCTAssertFalse(interactions.openWithModifiers(otherLink, .command), "\(otherLink) is followed as it is")
        }
        XCTAssertTrue(interactions.openWithModifiers(link, .command))
        XCTAssertFalse(interactions.openWithModifiers(link, []))
        XCTAssertEqual(openedPictures.count, 2)

        XCTAssertEqual(actions().textLinkInteractions(offersMenu: false).menuItems(link).count, 0, "A block with its own menu offers them there.")
        let web = try ObsidianMarkdownParser(baseURL: URL(fileURLWithPath: "/Vault"), textSize: 17)
            .attributedString(for: "| Chart |\n| --- |\n| ![chart](https://example.com/chart.png) |\n")
        XCTAssertEqual(web.runs.compactMap(\.link), [], "A web image in a table has no zoom link, so no menu and no tab.")
    }

    /// A rendered block's menu opened on a picture starts with its commands, before the block's own.
    func testABlocksMenuOnAPictureStartsWithThePicturesCommands() throws {
        let pictures = RenderedBlockPictures()
        pictures.frames = [ZoomablePictureFrame(path: try VaultPath("A.png"), frame: CGRect(x: 10, y: 10, width: 100, height: 80)),
                           ZoomablePictureFrame(path: try VaultPath("B.png"), frame: CGRect(x: 60, y: 40, width: 100, height: 80))]
        XCTAssertEqual(pictures.picture(at: CGPoint(x: 20, y: 20))?.path, try VaultPath("A.png"))
        XCTAssertEqual(pictures.picture(at: CGPoint(x: 80, y: 60))?.path, try VaultPath("B.png"), "Where two overlap, the one drawn last is on top.")
        XCTAssertNil(pictures.picture(at: CGPoint(x: 300, y: 300)))

        let context = RenderedBlockMenuContext()
        let tabbed = actions()
        context.itemsAtPoint = { _ in [RenderedBlockMenuItem(title: "Row")] }
        context.pictureItemsAtPoint = { point in pictures.picture(at: point).map { picture in tabbed.blockMenuItems(for: picture) } ?? [] }
        XCTAssertEqual(context.items(at: CGPoint(x: 20, y: 20)).map(\.title), ["Zoom In", "Open in New Tab", "Open to the Right", "Row"])
        XCTAssertEqual(context.items(at: CGPoint(x: 300, y: 300)).map(\.title), ["Row"])
        context.items(at: CGPoint(x: 20, y: 20))[1].action?()
        XCTAssertEqual(openedPictures.map(\.0), [try VaultPath("A.png")])
    }

    // MARK: Buttons while the pointer rests on a picture

    func testThePicturesButtonsShowAtOnceAndStayWhileThePointerMovesOntoThem() async throws {
        let clock = ManualClock()
        let hover = ReadingPictureHover(clock: clock)
        let frame = CGRect(x: 40, y: 300, width: 200, height: 120)
        hover.pointerEntered(try zoomLink("Scan.png"), frame: frame)
        XCTAssertEqual(hover.hoveredPicture, ReadingPictureHover.HoveredPicture(path: try VaultPath("Scan.png"), windowFrame: frame))

        // The buttons are drawn over the picture, so reaching them leaves the picture's link first.
        hover.pointerLeftLink()
        try await clock.awaitPendingSleepers()
        hover.pointerEnteredButtons()
        clock.advance(by: ReadingPictureHover.hideDelay)
        await ManualClock.letResumedTasksRun()
        XCTAssertNotNil(hover.hoveredPicture, "On the buttons, they stay.")

        hover.pointerLeftButtons()
        try await clock.awaitPendingSleepers()
        clock.advance(by: ReadingPictureHover.hideDelay - .milliseconds(1))
        await ManualClock.letResumedTasksRun()
        XCTAssertNotNil(hover.hoveredPicture, "Not before the delay.")
        clock.advance(by: .milliseconds(1))
        try await waitUntil("the buttons go once the pointer left both") { hover.hoveredPicture == nil }
    }

    func testAnotherLinkOrAScrollHidesThePicturesButtonsAtOnce() throws {
        let hover = ReadingPictureHover(clock: ManualClock())
        let frame = CGRect(x: 0, y: 0, width: 50, height: 50)
        hover.pointerEntered(try zoomLink("Scan.png"), frame: frame)
        hover.pointerEntered(try XCTUnwrap(URL(string: GraphiteOpenLink.markdownDestination(target: "Lecture"))), frame: frame)
        XCTAssertNil(hover.hoveredPicture, "A note link shows no picture buttons.")
        hover.pointerEntered(try zoomLink("Scan.png"), frame: frame)
        hover.hide()
        XCTAssertNil(hover.hoveredPicture)
    }

    /// The reading view's texts follow the pointer only when pictures or preview cards ask.
    func testTheReadingViewsTextsFollowThePointerOnlyForPicturesOrPreviews() throws {
        let note = try VaultPath("Note.md")
        XCTAssertNil(ReadingPictureHover.linkHoverAction(pictures: nil, previews: nil, sourceNote: note))
        XCTAssertNotNil(ReadingPictureHover.linkHoverAction(pictures: ReadingPictureHover(clock: ManualClock()), previews: nil, sourceNote: note))
    }
}
