/**
 * File: UiInlineImageDecodeSizeTests.swift
 * ----------------------------------------
 * Layer: Tests
 * Description: Photos shown side by side at a width are decoded for that width, never as the full camera
 *              image: a Live Preview line of ten 250-point photos, the same photos in a table cell drawn by the
 *              reading view's renderer, and a picture without a width, which keeps the inline limit (issue #102).
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 11/11/2026
 */

#if os(macOS)
import XCTest
import AppKit
import SwiftUI
import ImageIO
import UniformTypeIdentifiers
import GraphiteCore
@testable import GraphiteUI
import GraphiteTestSupport

/// The owner's "Butter-basted steak.md" shows ten camera photos at `|250` on one line. Each picture is to be
/// decoded off the main actor, through `ReadingImageCache`, at 250 points times the screen's scale: decoded
/// at the inline limit, ten 4:3 photos held about 97 MB; at 250 points on a Retina screen, about 5 MB.
@MainActor
final class UiInlineImageDecodeSizeTests: XCTestCase {
    private var vault: URL!
    private var window: NSWindow?

    /// A camera photo's size, larger than every limit a picture is decoded within.
    private static let photoPixelWidth = 3000
    private static let photoPixelHeight = 2250

    override func setUp() async throws {
        vault = try TemporaryVault.make(prefix: "InlineImageDecodeSize", for: self).root
    }

    override func tearDown() async throws {
        window?.orderOut(nil)
        window?.contentView = nil
        window = nil
    }

    /// Ten JPEG photos of one color, named as the owner's are, with names no other test uses.
    private func writePhotos(prefix: String, count: Int = 10) throws -> [URL] {
        let colorSpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try XCTUnwrap(CGContext(data: nil, width: Self.photoPixelWidth, height: Self.photoPixelHeight, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: colorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.setFillColor(CGColor(srgbRed: 0.8, green: 0.3, blue: 0.2, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: Self.photoPixelWidth, height: Self.photoPixelHeight))
        let photo = try XCTUnwrap(context.makeImage())
        return try (1...count).map { number in
            let location = vault.appendingPathComponent("\(prefix)_\(6651 + number).JPG")
            let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(location as CFURL, UTType.jpeg.identifier as CFString, 1, nil))
            CGImageDestinationAddImage(destination, photo, [kCGImageDestinationLossyCompressionQuality: 0.5] as CFDictionary)
            XCTAssertTrue(CGImageDestinationFinalize(destination))
            return location
        }
    }

    private func environment() -> LivePreviewEnvironment {
        LivePreviewEnvironment(root: vault, textSize: 17, colorsEnabled: true, paletteHexByName: [:], drawingVersion: 0,
                               resolve: { target, _ in try? VaultPath(target) }, open: { _ in }, follow: { _, _ in }, updateProperties: nil)
    }

    /// Shows `view` in a window no one sees, 1,800 points wide so the ten photos fit, and returns its pixels a point.
    private func show(_ view: some View) -> CGFloat {
        let hostingView = NSHostingView(rootView: view.frame(width: 1800))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1800, height: 900), styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = hostingView
        window.showInvisibly()
        hostingView.layoutSubtreeIfNeeded()
        self.window = window
        return window.backingScaleFactor
    }

    /// 250 points at `scale` pixels a point, as `EmbeddedImageDisplayWidth` rounds it.
    private func pixelWidth(ofPoints points: CGFloat, scale: CGFloat) -> Int {
        Int((points * max(scale, 1)).rounded(.up))
    }

    // MARK: Live Preview

    func testALivePreviewLineOfTenPhotosAtTwoHundredFiftyPointsDecodesEachForThatWidth() async throws {
        let photos = try writePhotos(prefix: "IMG")
        let line = photos.map { photo in "![[\(photo.lastPathComponent)|250]]" }.joined(separator: " ")
        let block = try XCTUnwrap(LivePreviewBlockScanner.blocks(in: line as NSString).first)
        let scale = show(LivePreviewWidgetView(block: block, environment: environment(), revealSource: {}, reportHeight: { _ in }))
        let expectedWidth = pixelWidth(ofPoints: 250, scale: scale)

        try await waitUntil("all ten photos are decoded") {
            photos.allSatisfy { photo in ReadingImageCache.shared.lastThumbnail(for: photo, kind: .block, displayPixelWidth: expectedWidth) != nil }
        }
        var decodedBytes = 0
        for photo in photos {
            let thumbnail = try XCTUnwrap(ReadingImageCache.shared.lastThumbnail(for: photo, kind: .block, displayPixelWidth: expectedWidth))
            XCTAssertEqual(thumbnail.image.width, expectedWidth, "\(photo.lastPathComponent) is decoded for 250 points at \(scale)x.")
            XCTAssertEqual(thumbnail.image.height, expectedWidth * 3 / 4, accuracy: 1)
            XCTAssertNil(ReadingImageCache.shared.lastThumbnail(for: photo, kind: .block), "\(photo.lastPathComponent) is never decoded whole.")
            decodedBytes += thumbnail.image.bytesPerRow * thumbnail.image.height
        }
        // At most 750 by 563 pixels of four bytes each, at three pixels a point.
        XCTAssertLessThanOrEqual(decodedBytes, 10 * 750 * 563 * 4 + 10 * 4096, "The row holds \(decodedBytes) decoded bytes.")
    }

    // MARK: The reading view's renderer

    /// A table cell's pictures are drawn inside text by the reading view's renderer, the one the reading view
    /// draws a paragraph of side-by-side photos with: given a width, each is decoded for it.
    func testPhotosWithAWidthInATableCellAreDecodedForThatWidthAndOneWithoutKeepsTheInlineLimit() async throws {
        let photos = try writePhotos(prefix: "Cell", count: 3)
        let cell = photos.dropLast().map { photo in "![[\(photo.lastPathComponent)\\|250]]" }.joined(separator: " ")
        let table = "| Photos | Without a width |\n| --- | --- |\n| \(cell) | ![[\(photos[2].lastPathComponent)]] |\n"
        let scale = show(RenderedMarkdownBlock(markdown: table, environment: environment()))
        let expectedWidth = pixelWidth(ofPoints: 250, scale: scale)

        try await waitUntil("the table's three photos are decoded") {
            photos.dropLast().allSatisfy { photo in ReadingImageCache.shared.lastThumbnail(for: photo, kind: .inline, displayPixelWidth: expectedWidth) != nil }
                && ReadingImageCache.shared.lastThumbnail(for: photos[2], kind: .inline) != nil
        }
        for photo in photos.dropLast() {
            let thumbnail = try XCTUnwrap(ReadingImageCache.shared.lastThumbnail(for: photo, kind: .inline, displayPixelWidth: expectedWidth))
            XCTAssertEqual(thumbnail.image.width, expectedWidth, "\(photo.lastPathComponent) is decoded for 250 points at \(scale)x.")
            XCTAssertNil(ReadingImageCache.shared.lastThumbnail(for: photo, kind: .inline), "\(photo.lastPathComponent) is not decoded at the inline limit.")
        }
        // A picture without a width is laid out at its pixel size, so it keeps the longest side an inline picture may have.
        let unsized = try XCTUnwrap(ReadingImageCache.shared.lastThumbnail(for: photos[2], kind: .inline))
        XCTAssertEqual(unsized.image.width, ReadingThumbnailKind.inline.maximumDimension)
    }

    func testTheLoaderDecodesForTheEmbedsWidthAtTheScreensScale() throws {
        let location = vault.appendingPathComponent("Photo.JPG")
        let sized = PreviewImageFragment.url(for: location, displaySize: EmbedDisplaySize(width: 250, height: nil), version: 0)
        XCTAssertEqual(VaultImageLoader(root: vault, displayScale: 3).displayPixelWidth(for: sized), 750)
        XCTAssertEqual(VaultImageLoader(root: vault, displayScale: 2).displayPixelWidth(for: sized), 500)
        // A view not on a screen yet reports no scale: one pixel a point, decoded again once it is.
        XCTAssertEqual(VaultImageLoader(root: vault, displayScale: 0).displayPixelWidth(for: sized), 250)
        let unsized = PreviewImageFragment.url(for: location, displaySize: nil, version: 0)
        XCTAssertNil(VaultImageLoader(root: vault, displayScale: 3).displayPixelWidth(for: unsized))
    }
}
#endif
