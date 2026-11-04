/**
 * File: TabThumbnailsTests.swift
 * ------------------------------
 * Layer: Tests
 * Description: The thumbnails the tab overview's cards show.
 *
 * Authors: felixchvl
 * Version: 0.2
 * Date: 01/11/2026
 */

import XCTest
import CoreGraphics
import GraphiteCore
@testable import GraphiteUI
#if os(macOS)
import AppKit
#endif

/// The thumbnails the tab overview's cards show: few, the latest kept, those of closed tabs
/// let go, and a side's document area found while SwiftUI hands it from one view to the next.
@MainActor
final class TabThumbnailsTests: XCTestCase {
    func testOnlyTheMostRecentThumbnailsAreKeptAndClosedTabsLoseTheirs() throws {
        let thumbnails = TabThumbnails()
        let tabIDs = (0..<(TabThumbnails.maximumThumbnailCount + 6)).map { _ in UUID() }
        let image = try XCTUnwrap(blankImage())
        for tabID in tabIDs { thumbnails.store(image, for: tabID, showing: nil) }
        XCTAssertEqual(thumbnails.thumbnailCount, TabThumbnails.maximumThumbnailCount)
        XCTAssertNil(thumbnails.thumbnail(of: tabIDs[0]), "The oldest thumbnails go first.")
        XCTAssertNotNil(thumbnails.thumbnail(of: try XCTUnwrap(tabIDs.last)))

        // Capturing a tab again makes its thumbnail the newest.
        thumbnails.store(image, for: tabIDs[6], showing: nil)
        thumbnails.store(image, for: UUID(), showing: nil)
        XCTAssertNotNil(thumbnails.thumbnail(of: tabIDs[6]))
        XCTAssertNil(thumbnails.thumbnail(of: tabIDs[7]))

        let remainingLayout = TabLayout()
        thumbnails.store(image, for: remainingLayout.activeTab.id, showing: nil)
        thumbnails.keepThumbnails(of: remainingLayout.allTabs)
        XCTAssertEqual(thumbnails.thumbnailCount, 1)
        thumbnails.removeAllThumbnails()
        XCTAssertEqual(thumbnails.thumbnailCount, 0)
    }

    /// HUNT-189: the thumbnails of closed tabs stayed until the overview was opened again; the
    /// window now lets them go as the tabs change.
    func testTheThumbnailOfAClosedTabIsLetGoWhenTheTabsChange() throws {
        let thumbnails = TabThumbnails()
        let image = try XCTUnwrap(blankImage())
        var layout = TabLayout()
        let keptTabID = layout.tabForOpeningHere()
        layout.show(try VaultPath("Kept.md"), inTab: keptTabID, recordsHistory: true)
        let closedTabID = layout.addTab(showing: try VaultPath("Closed.md"))
        thumbnails.store(image, for: keptTabID, showing: try VaultPath("Kept.md"))
        thumbnails.store(image, for: closedTabID, showing: try VaultPath("Closed.md"))
        layout.closeTab(closedTabID)

        thumbnails.keepThumbnails(of: layout.allTabs)

        XCTAssertNotNil(thumbnails.thumbnail(of: keptTabID))
        XCTAssertNil(thumbnails.thumbnail(of: closedTabID))
        XCTAssertEqual(thumbnails.thumbnailCount, 1)
    }

    /// HUNT-195: a tab that shows another file since its picture was taken drew the old file.
    func testTheThumbnailOfATabThatShowsAnotherFileNowIsLetGo() throws {
        let thumbnails = TabThumbnails()
        let image = try XCTUnwrap(blankImage())
        var layout = TabLayout()
        let tabID = layout.tabForOpeningHere()
        layout.show(try VaultPath("X.md"), inTab: tabID, recordsHistory: true)
        thumbnails.store(image, for: tabID, showing: try VaultPath("X.md"))

        thumbnails.keepThumbnails(of: layout.allTabs)
        XCTAssertNotNil(thumbnails.thumbnail(of: tabID), "The same file keeps its picture.")
        layout.show(try VaultPath("Y.md"), inTab: tabID, recordsHistory: true)
        thumbnails.keepThumbnails(of: layout.allTabs)
        XCTAssertNil(thumbnails.thumbnail(of: tabID))
        XCTAssertEqual(thumbnails.thumbnailCount, 0)
    }

    #if os(macOS)
    /// SwiftUI made a side's new area, updated the old one, then let the old one go; the iPad
    /// was then left with no area to capture.
    func testASidesNewAreaStaysWhenItsOldAreaGoesAfterIt() throws {
        let thumbnails = TabThumbnails()
        let groupID = UUID()
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 400, height: 300), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let oldArea = DocumentAreaView(frame: CGRect(x: 0, y: 0, width: 400, height: 300))
        let newArea = DocumentAreaView(frame: CGRect(x: 0, y: 0, width: 400, height: 200))
        window.contentView?.addSubview(oldArea)
        window.contentView?.addSubview(newArea)

        thumbnails.register(oldArea, forGroup: groupID)
        thumbnails.register(newArea, forGroup: groupID)
        thumbnails.register(oldArea, forGroup: groupID)
        thumbnails.unregister(oldArea, forGroup: groupID)
        oldArea.removeFromSuperview()

        XCTAssertEqual(try XCTUnwrap(thumbnails.aspectRatio(ofGroup: groupID)), 2, accuracy: 0.001, "The new area is the side's.")
        newArea.removeFromSuperview()
        XCTAssertNil(thumbnails.aspectRatio(ofGroup: groupID), "An area off screen is not captured.")
    }
    #endif

    private func blankImage() -> CGImage? {
        CGContext(data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceGray(),
                  bitmapInfo: CGImageAlphaInfo.none.rawValue)?.makeImage()
    }
}
