/**
 * File: ReadingDiagramPicturesHostedTests.swift
 * ---------------------------------------------
 * Layer: Tests
 * Description: The reading view's diagrams as pictures on the iPad and the iPhone: painted as the package paints them and
 *              as the SwiftUI painting looks, kept within the budget, let go on a memory warning, painted ahead of a scroll.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 27/11/2026
 */
#if os(iOS)
import XCTest
import SwiftUI
import MermaidDiagrams
@testable import GraphiteUI

@MainActor
final class ReadingDiagramPicturesHostedTests: XCTestCase {
    private let typography = DiagramTypography(font: DiagramFont(postScriptName: nil, size: 17))
    private let scale: CGFloat = 2

    private func readingDiagrams() -> [ReadingDiagram] {
        DiagramScrollingNote.diagrams.map { diagram in ReadingDiagram(source: diagram.source, typography: typography) }
    }

    private func preparedDiagrams(of diagrams: [ReadingDiagram]? = nil) throws -> [PreparedMermaidDiagram] {
        try (diagrams ?? readingDiagrams()).enumerated().map { index, diagram in
            guard case .drawn(let prepared, _) = diagram else { throw DiagramNotDrawn(title: DiagramScrollingNote.diagrams[index].title) }
            return prepared
        }
    }

    private func appearance(_ colorScheme: ColorScheme) -> ReadingDiagramPictureAppearance {
        ReadingDiagramPictureAppearance(colors: ReadingDiagramColors(theme: nil, colorScheme: colorScheme), colorScheme: colorScheme, contrast: .standard)
    }

    private func environment(_ colorScheme: ColorScheme) -> EnvironmentValues {
        var environment = EnvironmentValues()
        environment.colorScheme = colorScheme
        return environment
    }

    /// Each picture is the scene at its size in pixels, as the SwiftUI painting draws it in the same colors, within the
    /// share `ReadingDiagramScenePaintingTests` allows the painting and the package's painter to differ by.
    func testAPictureIsTheSceneAsTheSwiftUIPaintingDrawsIt() throws {
        for colorScheme in [ColorScheme.light, .dark] {
            let colors = ReadingDiagramColors(theme: nil, colorScheme: colorScheme)
            let palette = colors.palette(in: environment(colorScheme))
            for (index, prepared) in try preparedDiagrams().enumerated().prefix(12) {
                let scene = prepared.scene
                let label = "\(DiagramScrollingNote.diagrams[index].title) \(colorScheme)"
                let picture = try XCTUnwrap(ReadingDiagramPictures.picture(of: scene, in: palette, pixelsPerPoint: scale), label)
                XCTAssertEqual(picture.width, Int((scene.size.width * scale).rounded(.up)), label)
                XCTAssertEqual(picture.height, Int((scene.size.height * scale).rounded(.up)), label)
                let renderer = ImageRenderer(content: ReadingDiagramScenePainting(scene: scene, colors: colors)
                    .frame(width: CGFloat(picture.width) / scale, height: CGFloat(picture.height) / scale, alignment: .topLeading)
                    .environment(\.colorScheme, colorScheme))
                renderer.scale = scale
                let painted = try XCTUnwrap(renderer.cgImage, label)
                let pictureBytes = try XCTUnwrap(Self.bytes(of: picture)), paintedBytes = try XCTUnwrap(Self.bytes(of: painted))
                XCTAssertEqual(pictureBytes.count, paintedBytes.count, label)
                let inked = Self.share(of: pictureBytes) { pixel in pixel.alpha > 0.1 }
                XCTAssertGreaterThan(inked, 0.005, "Not blank: \(label)")
                let differing = Self.differingShare(pictureBytes, paintedBytes)
                XCTAssertLessThan(differing, 0.03, "As the SwiftUI painting draws it: \(label)")
            }
        }
    }

    /// The pictures shown last are kept up to the budget, the least recently shown let go first, the newest always kept;
    /// a memory warning lets every one go.
    func testPicturesAreKeptWithinTheBudgetAndLetGoOnAMemoryWarning() async throws {
        let pictures = ReadingDiagramPictures()
        let scenes = try preparedDiagrams().map(\.scene)
        let keys = scenes.map { scene in ReadingDiagramPictureKey(scene: scene, appearance: appearance(.light), pixelsPerPoint: 8) }
        for (scene, key) in zip(scenes, keys) {
            let painted = await pictures.paint(scene, for: key, resolvingColorsIn: environment(.light))
            XCTAssertNotNil(painted)
            XCTAssertNotNil(pictures.picture(for: key), "The picture just painted is kept.")
        }
        // At eight pixels a point the note's pictures are far over the budget: the first ones painted are let go.
        XCTAssertNil(pictures.picture(for: keys[0]), "The least recently shown picture is let go.")
        XCTAssertNotNil(pictures.picture(for: keys[keys.count - 1]))
        NotificationCenter.default.post(name: UIApplication.didReceiveMemoryWarningNotification, object: nil)
        try await waitUntil("a memory warning lets every picture go") { pictures.picture(for: keys[keys.count - 1]) == nil }
        XCTAssertNil(pictures.picture(for: keys[keys.count - 2]))
    }

    /// A theme or appearance change is a new picture of the same scene; another scene is another picture.
    func testAnotherAppearanceOrSceneIsAnotherPicture() throws {
        let scenes = try preparedDiagrams().map(\.scene)
        let light = ReadingDiagramPictureKey(scene: scenes[0], appearance: appearance(.light), pixelsPerPoint: scale)
        let dark = ReadingDiagramPictureKey(scene: scenes[0], appearance: appearance(.dark), pixelsPerPoint: scale)
        let copy = scenes[0]
        XCTAssertEqual(light, ReadingDiagramPictureKey(scene: copy, appearance: appearance(.light), pixelsPerPoint: scale), "A copy of the scene is the scene.")
        XCTAssertNotEqual(light, dark)
        XCTAssertTrue(light.paintsTheSameScene(as: dark))
        let other = ReadingDiagramPictureKey(scene: scenes[1], appearance: appearance(.light), pixelsPerPoint: scale)
        XCTAssertNotEqual(light, other)
        XCTAssertFalse(light.paintsTheSameScene(as: other))
        // The same text prepared again is another scene of the same size: its own picture while both are kept.
        let again = try preparedDiagrams().map(\.scene)[0]
        let lightAgain = ReadingDiagramPictureKey(scene: again, appearance: appearance(.light), pixelsPerPoint: scale)
        XCTAssertEqual(again.size, scenes[0].size)
        XCTAssertNotEqual(light, lightAgain)
        XCTAssertFalse(light.paintsTheSameScene(as: lightAgain))
    }

    /// The pictures of the diagrams read just before and after one shown are painted, in the column it is shown in.
    func testTheNeighboursOfADiagramShownArePaintedAhead() async throws {
        let diagrams = readingDiagrams()
        // The same preparation the blocks hold: a diagram is told by its scene's storage identifier.
        let prepared = try preparedDiagrams(of: diagrams)
        // Under a callout too, as a note's diagrams may be.
        let blocks = [RenderedBlock.callout(id: -1, type: "note", title: "Diagrams", folding: .notFoldable,
                                            body: diagrams.enumerated().map { index, diagram in RenderedBlock.diagram(id: index, diagram: diagram) })]
        let pictures = ReadingDiagramPictures()
        pictures.showNote(blocks)
        let columnWidth: CGFloat = 700
        func key(_ index: Int) -> ReadingDiagramPictureKey {
            let scene = ReadingScaledDiagram<EmptyView>.shownScene(of: prepared[index], inColumnWidth: columnWidth, scaleAtNaturalWidth: 1)
            return ReadingDiagramPictureKey(scene: scene, appearance: appearance(.light), pixelsPerPoint: scale)
        }
        let shown = 10
        await pictures.paintNeighbors(of: key(shown), placement: ReadingDiagramPlacement(columnWidth: columnWidth, textSize: 17,
                                                                                         diagramScene: prepared[shown].scene.storageIdentifier),
                                      resolvingColorsIn: environment(.light))
        for neighbor in [8, 9, 11, 12] {
            XCTAssertNotNil(pictures.picture(for: key(neighbor)), "Diagram \(neighbor) is painted ahead.")
        }
        XCTAssertNil(pictures.picture(for: key(7)))
        XCTAssertNil(pictures.picture(for: key(13)))
    }

    /// Every diagram of the note is drawn (`DiagramNoteScrollingHostedTests.testEveryDiagramOfTheNoteIsDrawn`).
    private struct DiagramNotDrawn: Error {
        let title: String
    }

    // MARK: Pixels

    private struct Pixel { let red, green, blue, alpha: CGFloat }

    /// The picture's pixels, premultiplied sRGB, four bytes each.
    private static func bytes(of image: CGImage) -> [UInt8]? {
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let space = CGColorSpace(name: CGColorSpace.sRGB),
                  let context = CGContext(data: buffer.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                          space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return true
        }
        return drawn ? bytes : nil
    }

    private static func share(of bytes: [UInt8], _ matching: (Pixel) -> Bool) -> Double {
        let count = bytes.count / 4
        var matched = 0
        for pixelIndex in 0..<count {
            let offset = pixelIndex * 4
            let pixel = Pixel(red: CGFloat(bytes[offset]) / 255, green: CGFloat(bytes[offset + 1]) / 255, blue: CGFloat(bytes[offset + 2]) / 255,
                              alpha: CGFloat(bytes[offset + 3]) / 255)
            if matching(pixel) { matched += 1 }
        }
        return Double(matched) / Double(max(1, count))
    }

    /// The share of pixels further apart than about a fifth of a channel's range on any channel: antialiased edges and
    /// text set a little apart count as alike.
    private static func differingShare(_ first: [UInt8], _ second: [UInt8]) -> Double {
        let count = first.count / 4
        var differing = 0
        for pixelIndex in 0..<count {
            let offset = pixelIndex * 4
            if (0..<4).contains(where: { channel in abs(Int(first[offset + channel]) - Int(second[offset + channel])) > 48 }) { differing += 1 }
        }
        return Double(differing) / Double(max(1, count))
    }
}
#endif
