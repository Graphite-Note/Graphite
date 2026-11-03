/**
 * File: CanvasGroupBackgroundsTests.swift
 * ---------------------------------------
 * Layer: Tests
 * Description: A canvas group's background picture follows its file when the file changes (HUNT-108).
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 01/11/2026
 */

import XCTest
import ImageIO
import UniformTypeIdentifiers
import GraphiteCore
@testable import GraphiteUI
import GraphiteTestSupport

@MainActor
final class CanvasGroupBackgroundsTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = try TemporaryVault.make(prefix: "CanvasGroupBackgrounds", for: self).root
    }

    private func writePNG(width: Int, height: Int, named name: String) throws {
        let colorSpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(srgbRed: 0.2, green: 0.4, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(directory.appendingPathComponent(name) as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try XCTUnwrap(context.makeImage()), nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
    }

    private func group(background: String) -> CanvasNode {
        CanvasNode(id: "group", content: .group(label: "Group", background: background, backgroundStyle: .cover), frame: CGRect(x: 0, y: 0, width: 400, height: 300))
    }

    func testAGroupShowsThePictureItsFileHasNowAfterTheFileChanged() async throws {
        try writePNG(width: 40, height: 30, named: "Background.png")
        let backgrounds = CanvasGroupBackgrounds()
        let nodes = [group(background: "Background.png")]
        await backgrounds.load(for: nodes, root: directory)
        let firstImage = try XCTUnwrap(backgrounds.images["Background.png"])
        XCTAssertEqual(firstImage.width, 40)

        try writePNG(width: 80, height: 60, named: "Background.png")
        await backgrounds.load(for: nodes, root: directory)

        XCTAssertEqual(try XCTUnwrap(backgrounds.images["Background.png"]).width, 80, "The new file is decoded, not the picture kept from before.")
    }

    func testAnUnchangedPictureIsNotDecodedAgain() async throws {
        try writePNG(width: 40, height: 30, named: "Background.png")
        let backgrounds = CanvasGroupBackgrounds()
        let nodes = [group(background: "Background.png")]
        await backgrounds.load(for: nodes, root: directory)
        let firstImage = try XCTUnwrap(backgrounds.images["Background.png"])

        await backgrounds.load(for: nodes, root: directory)

        XCTAssertTrue(try XCTUnwrap(backgrounds.images["Background.png"]) === firstImage)
    }
}
