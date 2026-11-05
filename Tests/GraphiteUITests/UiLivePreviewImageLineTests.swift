/**
 * File: UiLivePreviewImageLineTests.swift
 * ---------------------------------------
 * Layer: Tests
 * Description: A line of image embeds, or of images among text, is drawn in Live Preview as pictures side by
 *              side at their sizes, and shows its source while the cursor is on it (HUNT-323).
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 05/11/2026
 */

import XCTest
import SwiftUI
import ImageIO
import UniformTypeIdentifiers
import GraphiteCore
@testable import GraphiteUI
import GraphiteTestSupport

/// The owner's photo row showed in Live Preview as blue link text, `IMG_6482.JPG|200 …`, while
/// reading view showed the pictures: Live Preview drew an embed only when it was alone on its line.
@MainActor
final class UiLivePreviewImageLineTests: XCTestCase {
    private var vault: URL!

    override func setUp() async throws {
        vault = try TemporaryVault.make(prefix: "ImageLine", for: self).root
    }

    /// The owner's line, with made-up file names: nine photos 200 points wide, uppercase `.JPG`.
    private static let photoRow = (1...9).map { number in "![[Photo_\(number).JPG|200]]" }.joined(separator: " ")

    /// A red picture of `width` by `height` pixels, written as JPEG or PNG by its extension.
    @discardableResult
    private func writeRedImage(named name: String, width: Int = 80, height: Int = 40) throws -> URL {
        let colorSpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let location = vault.appendingPathComponent(name)
        let type = (name as NSString).pathExtension.lowercased() == "png" ? UTType.png : UTType.jpeg
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(location as CFURL, type.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try XCTUnwrap(context.makeImage()), nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return location
    }

    private func imageLinePieces(_ line: String) throws -> [ImageLinePiece] {
        let blocks = LivePreviewBlockScanner.blocks(in: line as NSString)
        XCTAssertEqual(blocks.count, 1, "The line is one block.")
        let block = try XCTUnwrap(blocks.first)
        guard case .imageLine(let pieces) = block.kind else {
            XCTFail("The scanner did not find a line of images in \(line): \(block.kind)")
            return []
        }
        XCTAssertEqual(block.range, NSRange(location: 0, length: (line as NSString).length))
        return pieces
    }

    private func images(in pieces: [ImageLinePiece]) -> [EmbedReference] {
        pieces.compactMap { piece in if case .image(let embed) = piece { embed } else { nil } }
    }

    /// What an earlier look-up of each picture left behind: where it was found and its decoded
    /// pixels, for the width it is shown at one pixel a point. The first frame of a new view
    /// draws those, since a look-up only ends after it.
    private func rememberPictures(of pieces: [ImageLinePiece]) async throws {
        for embed in images(in: pieces) {
            let path = try VaultPath(embed.target)
            let location = try path.url(in: vault)
            let pixelWidth = EmbeddedImageDisplayWidth.pixelWidth(columnWidth: nil, displaySize: embed.displaySize, displayScale: 1)
            _ = try await ReadingImageCache.shared.thumbnail(for: location, kind: .block, displayPixelWidth: pixelWidth)
            LivePreviewEmbedImageLocations.remember(.init(path: path, location: location), for: embed, in: vault)
        }
    }

    /// Each embed's file is where its target says; the decoded pixels remembered for it are
    /// what a first frame draws.
    private func environment() -> LivePreviewEnvironment {
        LivePreviewEnvironment(root: vault, textSize: 17, colorsEnabled: true, paletteHexByName: [:], drawingVersion: 0,
                               resolve: { target, _ in try? VaultPath(target) },
                               open: { _ in }, follow: { _, _ in }, updateProperties: nil)
    }

    private func firstFrame(of line: String, width: CGFloat) throws -> CGImage {
        let block = try XCTUnwrap(LivePreviewBlockScanner.blocks(in: line as NSString).first)
        let renderer = ImageRenderer(content: LivePreviewWidgetView(block: block, environment: environment(), revealSource: {}, reportHeight: { _ in })
            .environment(\.displayScale, 1)
            .frame(width: width))
        renderer.scale = 1
        return try XCTUnwrap(renderer.cgImage)
    }

    private func isRed(_ image: CGImage, x pixelColumn: Int, y pixelRow: Int) throws -> Bool {
        let colorSpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try XCTUnwrap(CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                              space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: -pixelColumn, y: pixelRow - image.height + 1, width: image.width, height: image.height))
        let pixelBytes = try XCTUnwrap(context.data).bindMemory(to: UInt8.self, capacity: 4)
        return pixelBytes[0] > 200 && pixelBytes[1] < 60 && pixelBytes[2] < 60 && pixelBytes[3] > 200
    }

    // MARK: The owner's line

    func testTheOwnersLineOfNinePhotosIsOneBlockOfNinePicturesTwoHundredPointsWide() throws {
        let embeds = images(in: try imageLinePieces(Self.photoRow))
        XCTAssertEqual(embeds.count, 9)
        XCTAssertEqual(embeds.map(\.target), (1...9).map { number in "Photo_\(number).JPG" })
        XCTAssertTrue(embeds.allSatisfy { embed in embed.displaySize == EmbedDisplaySize(width: 200, height: nil) })
    }

    func testTheOwnersLineDrawsNinePicturesTwoHundredPointsWideThreeToARow() async throws {
        for number in 1...9 { try writeRedImage(named: "Photo_\(number).JPG") }
        try await rememberPictures(of: try imageLinePieces(Self.photoRow))

        // 700 points take three 200-point pictures and their gaps, 608 points; a fourth would need 812.
        let rendered = try firstFrame(of: Self.photoRow, width: 700)
        // Two to one, each picture is 100 points tall: three rows and their two gaps, under 4 points of padding each side.
        XCTAssertEqual(rendered.height, 3 * 100 + 2 * 4 + 2 * 4, "The nine pictures take three rows.")
        let spacing = Int(ImageLineFlowLayout.spacing)
        for row in 0..<3 {
            let middleY = 4 + row * (100 + spacing) + 50
            for column in 0..<3 {
                let left = column * (200 + spacing)
                XCTAssertTrue(try isRed(rendered, x: left + 2, y: middleY), "Picture \(row * 3 + column + 1) starts at \(left) points.")
                XCTAssertTrue(try isRed(rendered, x: left + 197, y: middleY), "Picture \(row * 3 + column + 1) is 200 points wide.")
                XCTAssertFalse(try isRed(rendered, x: left + 201, y: middleY), "A gap follows picture \(row * 3 + column + 1).")
            }
            XCTAssertFalse(try isRed(rendered, x: 650, y: middleY), "No fourth picture in row \(row + 1).")
        }
    }

    func testTheSourceShowsWhileTheCursorIsOnTheLineAndThePicturesOtherwise() {
        let text = "## Photos\n" + Self.photoRow + "\nAfter"
        let source = text as NSString
        let lineRange = source.range(of: Self.photoRow)
        // The blocks as the editor keeps them, and the ones it conceals under their views for a selection.
        let blocks = LivePreviewBlockScanner.blocks(in: source)
        let entries = zip(blocks, LivePreviewBlockKey.keys(for: blocks)).map { block, key in LivePreviewBlockEntry(block: block, range: block.range, key: key) }
        func concealed(cursorAt location: Int) -> [LivePreviewBlockEntry] {
            LivePreviewRenderedBlocks.concealedEntries(entries, in: source, selection: NSRange(location: location, length: 0),
                                                       propertiesSource: .afterEditSource(isShown: false))
        }
        let concealedElsewhere = concealed(cursorAt: 2)
        XCTAssertEqual(concealedElsewhere.count, 1, "The line is drawn as its pictures while the cursor is elsewhere.")
        XCTAssertEqual(concealedElsewhere.first?.range.location, lineRange.location)
        XCTAssertTrue(concealed(cursorAt: lineRange.location + 40).isEmpty, "The cursor on the line shows its source.")
        XCTAssertTrue(concealed(cursorAt: NSMaxRange(lineRange) - 1).isEmpty, "The cursor at the line's end shows its source.")
    }

    // MARK: Other forms

    func testAWidthAndHeightFitsThePictureInsideBoth() async throws {
        try writeRedImage(named: "Square.png", width: 40, height: 40)
        try writeRedImage(named: "Wide.png")
        let line = "![[Square.png|200x150]] ![[Wide.png|200x150]]"
        let pieces = try imageLinePieces(line)
        XCTAssertEqual(images(in: pieces).map(\.displaySize), [EmbedDisplaySize(width: 200, height: 150), EmbedDisplaySize(width: 200, height: 150)])
        try await rememberPictures(of: pieces)

        let rendered = try firstFrame(of: line, width: 700)
        // The square is held to 150 points by its height; the two-to-one picture, 200 by 100, by its width.
        XCTAssertEqual(rendered.height, 150 + 2 * 4)
        XCTAssertTrue(try isRed(rendered, x: 147, y: 4 + 75))
        XCTAssertFalse(try isRed(rendered, x: 152, y: 4 + 75), "The square is 150 points wide.")
        // The rows' pieces stand on its bottom edge.
        XCTAssertTrue(try isRed(rendered, x: 154 + 100, y: 4 + 150 - 50))
        XCTAssertFalse(try isRed(rendered, x: 154 + 100, y: 4 + 20), "The wide picture is 100 points tall, at the row's bottom.")
        XCTAssertTrue(try isRed(rendered, x: 154 + 197, y: 4 + 100))
    }

    func testAMarkdownImageWithAWidthInItsTextIsAPictureOfTheLine() async throws {
        try writeRedImage(named: "Wide.png")
        let line = "![Wide|200](Wide.png) ![[Wide.png|100]]"
        let pieces = try imageLinePieces(line)
        let embeds = images(in: pieces)
        XCTAssertEqual(embeds.map(\.isWiki), [false, true])
        XCTAssertEqual(embeds.map(\.displayWidth), [200, 100])
        try await rememberPictures(of: pieces)

        let rendered = try firstFrame(of: line, width: 700)
        XCTAssertEqual(rendered.height, 100 + 2 * 4)
        XCTAssertTrue(try isRed(rendered, x: 197, y: 4 + 50))
        XCTAssertTrue(try isRed(rendered, x: 204 + 97, y: 4 + 75))
        XCTAssertFalse(try isRed(rendered, x: 204 + 102, y: 4 + 75), "The wiki embed is 100 points wide.")
    }

    func testTextAndPicturesOnOneLineKeepTheirOrder() throws {
        let pieces = try imageLinePieces("Before ![[a.png|100]] between **bold** ![alt|50](b.jpg) after")
        XCTAssertEqual(pieces.count, 5)
        guard pieces.count == 5, case .text(let before) = pieces[0], case .image(let first) = pieces[1], case .text(let between) = pieces[2],
              case .image(let second) = pieces[3], case .text(let after) = pieces[4] else { return XCTFail("Text, picture, text, picture, text: \(pieces)") }
        XCTAssertEqual([before, between, after], ["Before", "between **bold**", "after"])
        XCTAssertEqual(first.target, "a.png")
        XCTAssertEqual(first.range, NSRange(location: 7, length: 14))
        XCTAssertEqual(second.target, "b.jpg")
        XCTAssertEqual(second.displayWidth, 50)
    }

    func testTheHeightEstimatePlacesThePicturesInRows() throws {
        let pieces = try imageLinePieces(Self.photoRow)
        // 200 by 150 each, three to a row of 700 points: three rows, two gaps, the block's padding.
        XCTAssertEqual(LivePreviewBlockHeightEstimate.height(of: LivePreviewBlockScanner.blocks(in: Self.photoRow as NSString)[0], columnWidth: 700),
                       3 * 150 + 2 * 4 + 8)
        XCTAssertEqual(LivePreviewImageLineView.estimatedHeight(of: pieces, columnWidth: 200), 9 * 150 + 8 * 4 + 8, "One to a row in a narrow column.")
    }

    // MARK: Lines that keep their drawing

    func testLinesWhoseImagesStayInlineAreNotLinesOfImages() {
        for line in ["- ![[a.png|100]] ![[b.png|100]]", "# Title ![[a.png|100]]", "> ![[a.png|100]] ![[b.png|100]]",
                     "    ![[a.png|100]] ![[b.png|100]]", "`![[a.png|100]]` and `![[b.png]]`", "![](https://example.com/a.png) ![](https://example.com/b.png)",
                     "![[Other note]] ![[Second note]]", "Plain text with [[a link]]"] {
            let blocks = LivePreviewBlockScanner.blocks(in: line as NSString)
            XCTAssertFalse(blocks.contains { block in if case .imageLine = block.kind { true } else { false } }, line)
        }
        // A single image alone on its line is still an embed block of its own.
        guard case .embed = LivePreviewBlockScanner.blocks(in: "![[a.png|200]]" as NSString).first?.kind else { return XCTFail("A lone image is an embed block.") }
    }
}
