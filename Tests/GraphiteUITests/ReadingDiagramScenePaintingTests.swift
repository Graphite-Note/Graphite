/**
 * File: ReadingDiagramScenePaintingTests.swift
 * --------------------------------------------
 * Layer: Tests
 * Description: The one painter of every diagram type: a sample of each drawn at its scene's size, not blank, in the theme's colors.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

#if os(macOS)
import XCTest
import SwiftUI
import MermaidDiagrams
@testable import GraphiteUI

/// `ReadingDiagramScenePainting` paints any type's scene. Each sample is drawn off screen (`ImageRenderer`, shapes and text
/// only, so one pass draws it) and compared with the package's own Core Graphics renderer drawing the same scene in the same
/// colors: the two differ only where SwiftUI and Core Text set the same text a little apart.
@MainActor
final class ReadingDiagramScenePaintingTests: XCTestCase {
    private let typography = DiagramTypography(font: DiagramFont(postScriptName: nil, size: 16))
    /// Two pixels a point, as a Retina screen draws.
    private let scale: CGFloat = 2

    /// The note's colors with a text color no default is: a pixel of it comes from the theme, not from a fallback.
    private func colors(dark: Bool) -> ReadingDiagramColors {
        dark ? ReadingDiagramColors(background: Color(.sRGB, red: 0.08, green: 0.08, blue: 0.1), foreground: Color(.sRGB, red: 1, green: 0.85, blue: 0.4))
            : ReadingDiagramColors(background: Color(.sRGB, red: 1, green: 1, blue: 1), foreground: Color(.sRGB, red: 0.6, green: 0, blue: 0.3))
    }

    func testEveryTypeIsPaintedAtItsScenesSizeInTheThemesColorsAsThePackageDrawsIt() throws {
        for dark in [false, true] {
            let colors = colors(dark: dark)
            var environment = EnvironmentValues()
            environment.colorScheme = dark ? .dark : .light
            let palette = colors.palette(in: environment)
            for sample in ReadingDiagramSamples.oneOfEachType {
                let scene = try ReadingDiagram(source: sample.source, typography: typography).drawn(as: sample.kind).scene
                let label = "\(sample.kind) \(dark ? "dark" : "light")"
                let painted = try XCTUnwrap(DiagramPicture(painting: ReadingDiagramScenePainting(scene: scene, colors: colors), background: colors.background,
                                                           size: scene.size, scale: scale), label)
                XCTAssertEqual(painted.width, Int((scene.size.width * scale).rounded()), label)
                XCTAssertEqual(painted.height, Int((scene.size.height * scale).rounded()), label)
                XCTAssertGreaterThan(painted.share { pixel in !pixel.isClose(to: painted.pixel(atX: 0, y: 0)) }, 0.01, "Not blank: \(label)")
                let sRGB = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
                let text = try XCTUnwrap(palette.foreground.converted(to: sRGB, intent: .defaultIntent, options: nil)?.components)
                XCTAssertGreaterThan(painted.share { pixel in pixel.isClose(to: DiagramPixel(red: text[0], green: text[1], blue: text[2])) }, 0, "The theme's text color: \(label)")
                let drawn = try XCTUnwrap(DiagramPicture(scene: scene, palette: palette, scale: scale), label)
                XCTAssertLessThan(painted.share(differingFrom: drawn), 0.03, "As the package draws it: \(label)")
            }
        }
    }

    /// A theme change paints the same scene again: nothing but the colors changes.
    func testTheSameSceneIsPaintedInAnotherThemeWithoutBeingPreparedAgain() throws {
        let scene = try ReadingDiagram(source: ReadingDiagramSamples.oneOfEachType[0].source, typography: typography).drawn(as: .flowchart).scene
        let light = try XCTUnwrap(DiagramPicture(painting: ReadingDiagramScenePainting(scene: scene, colors: colors(dark: false)),
                                                 background: colors(dark: false).background, size: scene.size, scale: scale))
        let dark = try XCTUnwrap(DiagramPicture(painting: ReadingDiagramScenePainting(scene: scene, colors: colors(dark: true)),
                                                background: colors(dark: true).background, size: scene.size, scale: scale))
        XCTAssertEqual(light.width, dark.width)
        XCTAssertGreaterThan(light.share(differingFrom: dark), 0.5)
    }
}

/// One pixel's color, its channels from 0 to 1.
struct DiagramPixel {
    let red: CGFloat
    let green: CGFloat
    let blue: CGFloat

    /// Within about a fifth of the channel's range on each channel: antialiased edges and text set apart count as close.
    func isClose(to other: DiagramPixel, tolerance: CGFloat = 48 / 255) -> Bool {
        abs(red - other.red) <= tolerance && abs(green - other.green) <= tolerance && abs(blue - other.blue) <= tolerance
    }
}

/// A diagram drawn into an sRGB bitmap, its first row at the top.
struct DiagramPicture {
    let width: Int
    let height: Int
    private let bytes: [UInt8]

    /// The SwiftUI painting over `background`, drawn at `scale` pixels a point.
    @MainActor
    init?(painting: some View, background: Color, size: CGSize, scale: CGFloat) {
        let renderer = ImageRenderer(content: painting.background(background).frame(width: size.width, height: size.height, alignment: .topLeading))
        renderer.scale = scale
        renderer.proposedSize = ProposedViewSize(size)
        guard let image = renderer.cgImage else { return nil }
        self.init(image: image)
    }

    /// The scene drawn by the package's Core Graphics renderer over the palette's background.
    init?(scene: DiagramScene, palette: DiagramPalette, scale: CGFloat) {
        let width = Int((scene.size.width * scale).rounded()), height = Int((scene.size.height * scale).rounded())
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.setFillColor(palette.background)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        // The renderer's y runs down, from the top.
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: scale, y: -scale)
        DiagramSceneRenderer.draw(scene, in: context, palette: palette)
        guard let image = context.makeImage() else { return nil }
        self.init(image: image)
    }

    init?(image: CGImage) {
        width = image.width
        height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let space = CGColorSpace(name: CGColorSpace.sRGB),
                  let context = CGContext(data: buffer.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                          space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return true
        }
        guard drawn else { return nil }
        self.bytes = bytes
    }

    func pixel(atX x: Int, y: Int) -> DiagramPixel {
        let offset = (y * width + x) * 4
        return DiagramPixel(red: CGFloat(bytes[offset]) / 255, green: CGFloat(bytes[offset + 1]) / 255, blue: CGFloat(bytes[offset + 2]) / 255)
    }

    /// The share of the pixels that are `matching`.
    func share(_ matching: (DiagramPixel) -> Bool) -> Double {
        var count = 0
        for y in 0..<height { for x in 0..<width where matching(pixel(atX: x, y: y)) { count += 1 } }
        return Double(count) / Double(max(1, width * height))
    }

    /// The share of the pixels not close to the same pixel of `other`, of the same size.
    func share(differingFrom other: DiagramPicture) -> Double {
        guard other.width == width, other.height == height else { return 1 }
        var count = 0
        for y in 0..<height { for x in 0..<width where !pixel(atX: x, y: y).isClose(to: other.pixel(atX: x, y: y)) { count += 1 } }
        return Double(count) / Double(max(1, width * height))
    }
}
#endif
