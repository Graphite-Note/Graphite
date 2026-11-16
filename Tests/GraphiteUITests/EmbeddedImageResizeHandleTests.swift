/**
 * File: EmbeddedImageResizeHandleTests.swift
 * ------------------------------------------
 * Layer: UI tests
 * Description: Checks the widths an image's corner handle gives as it is dragged.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 16/11/2026
 */

import XCTest
import ImageIO
import UniformTypeIdentifiers
import GraphiteTestSupport
@testable import GraphiteUI

/// A dragged corner makes the image as wide as the drag says, within the column and never
/// so narrow that the handle leaves it.
final class EmbeddedImageResizeHandleTests: XCTestCase {
    func testTheImageFollowsTheDrag() {
        XCTAssertEqual(EmbeddedImageResizeHandle.width(from: 400, horizontalTranslation: -120, columnWidth: 700), 280)
        XCTAssertEqual(EmbeddedImageResizeHandle.width(from: 400, horizontalTranslation: 150, columnWidth: 700), 550)
    }

    func testTheImageStaysInsideItsColumn() {
        XCTAssertEqual(EmbeddedImageResizeHandle.width(from: 600, horizontalTranslation: 400, columnWidth: 700), 700)
        XCTAssertEqual(EmbeddedImageResizeHandle.width(from: 600, horizontalTranslation: 400, columnWidth: nil), 1000,
                       "With no column known, only the drag limits it.")
    }

    func testTheImageIsNeverNarrowerThanItsHandle() {
        XCTAssertEqual(EmbeddedImageResizeHandle.width(from: 200, horizontalTranslation: -500, columnWidth: 700), EmbeddedImageResizeHandle.minimumWidth)
        XCTAssertEqual(EmbeddedImageResizeHandle.width(from: 200, horizontalTranslation: 0, columnWidth: 20), EmbeddedImageResizeHandle.minimumWidth)
    }

    /// After a resize the image is decoded for its new width; until then its thumbnail at
    /// the old width stands in, scaled, rather than a progress indicator.
    func testTheThumbnailAtAnotherWidthStandsInForTheNewWidth() async throws {
        let vault = try TemporaryVault.make(prefix: "ImageResize", for: self)
        let location = vault.location(of: "picture.png")
        try writePicture(to: location, width: 800, height: 400)
        let cache = ReadingImageCache()
        XCTAssertNil(cache.latestThumbnail(for: location, kind: .block))
        _ = try await cache.thumbnail(for: location, kind: .block, displayPixelWidth: 600)
        XCTAssertNil(cache.lastThumbnail(for: location, kind: .block, displayPixelWidth: 360), "Nothing was made for the new width yet.")
        let standIn = try XCTUnwrap(cache.latestThumbnail(for: location, kind: .block))
        XCTAssertEqual(standIn.aspectRatio, 2, accuracy: 0.01)
    }

    private func writePicture(to location: URL, width: Int, height: Int) throws {
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try XCTUnwrap(context.makeImage())
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(location as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
    }
}
