/**
 * File: ImageZoomOverlayMacTests.swift
 * ------------------------------------
 * Layer: Tests
 * Description: Zooming into a picture on the Mac: the picture fits the window, magnifies, and closes on a click while fitted.
 *
 * Authors: Bahey Shalash
 * Version: 0.8
 * Date: 09/11/2026
 */

#if os(macOS)
import AppKit
import XCTest
@testable import GraphiteUI

/// The Mac's zoomed picture (`MagnifyingImageScrollView`), which the zoom over a note and the
/// image tab show.
@MainActor
final class ImageZoomOverlayMacTests: XCTestCase {
    private func picture(width: Int, height: Int) throws -> CGImage {
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try XCTUnwrap(context.makeImage())
    }

    /// A picture larger than the view is fitted inside it, with a margin, and can be magnified
    /// up to eight times that; one smaller than the view is shown at its own size.
    func testAPictureFitsTheViewAndMagnifiesFromThere() throws {
        let scrollView = MagnifyingImageScrollView(frame: NSRect(x: 0, y: 0, width: 848, height: 548))
        scrollView.image = try picture(width: 1600, height: 1000)
        scrollView.layoutSubtreeIfNeeded()
        XCTAssertEqual(scrollView.fittedMagnification, 0.5, accuracy: 0.001, "(848 - 2 × 24) / 1600 and (548 - 2 × 24) / 1000")
        XCTAssertEqual(scrollView.magnification, 0.5, accuracy: 0.001)
        XCTAssertTrue(scrollView.isFitted)
        XCTAssertEqual(scrollView.maxMagnification, 4, accuracy: 0.001)

        let small = MagnifyingImageScrollView(frame: NSRect(x: 0, y: 0, width: 848, height: 548))
        small.image = try picture(width: 200, height: 100)
        small.layoutSubtreeIfNeeded()
        XCTAssertEqual(small.fittedMagnification, 1, accuracy: 0.001, "A small picture is not enlarged to fit.")
    }

    /// A click on the fitted picture closes the zoom; once magnified, a click does not.
    func testAClickClosesOnlyWhileThePictureIsFitted() throws {
        let scrollView = MagnifyingImageScrollView(frame: NSRect(x: 0, y: 0, width: 848, height: 548))
        scrollView.image = try picture(width: 1600, height: 1000)
        scrollView.layoutSubtreeIfNeeded()
        var closeCount = 0
        scrollView.singleClickWhileFitted = { closeCount += 1 }
        scrollView.clickedOnce()
        XCTAssertEqual(closeCount, 1)
        scrollView.magnification = 2
        scrollView.clickedOnce()
        XCTAssertEqual(closeCount, 1)
    }
}
#endif
