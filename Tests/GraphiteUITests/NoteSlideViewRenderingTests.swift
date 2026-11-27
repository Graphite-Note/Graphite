/**
 * File: NoteSlideViewRenderingTests.swift
 * ---------------------------------------
 * Layer: Tests
 * Description: Slides of a presented note drawn as the screen draws them and read back from the pictures: text,
 *              display math, a Mermaid diagram and an image, light and dark, and a slide too tall shrunk to fit.
 *              With GRAPHITE_SLIDE_PICTURES set to a folder, the pictures are also written there to look at.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 27/11/2026
 */

import XCTest
import SwiftUI
import GraphiteCore
import GraphiteIndex
import GraphiteApple
@testable import GraphiteUI
import GraphiteTestSupport

@MainActor
final class NoteSlideViewRenderingTests: XCTestCase {
    private var vault: TemporaryVault!
    private var index: VaultIndex!

    override func setUp() async throws {
        vault = try TemporaryVault.make(prefix: "NoteSlideRenderingVault", for: self)
        index = try VaultIndex(databaseURL: vault.cacheDirectory.appendingPathComponent("index.sqlite"))
    }

    override func tearDown() async throws {
        index = nil
        try? FileManager.default.removeItem(at: vault.cacheDirectory) // Best-effort removal of a temporary folder.
    }

    /// A short lecture of four slides: text, a formula, a diagram, and a picture.
    private static let lecture = """
    # Sampling a signal

    A continuous signal is read every **T** seconds, at the sampling rate $f_s = 1/T$.

    - Too slow, and high frequencies fold over
    - Fast enough, and nothing is lost

    ---

    ## Nyquist

    $$
    f_s > 2 f_{max}
    $$

    ---

    ```mermaid
    flowchart LR
        Signal --> Sampler --> Quantizer --> Bits
    ```

    ---

    ![[Spectrum.png]]

    """

    private func builtSlides(of text: String) async throws -> NotePresentation {
        let path = try VaultPath("Sampling.md")
        _ = try vault.writeFile(path.rawValue, text: text)
        let source = NotePresentationSource(text: text, path: path, vault: try XCTUnwrap(ReadingVault(vault.root, index)), configuration: ReadingConfiguration())
        let presentation = NotePresentation.started(from: source, clock: ManualClock(),
                                                    pencil: PresentationPencilChoices(tool: .laser, inkColor: .red, laserStyle: .dot))
        try await waitUntil("every slide is built") {
            presentation.slides.allSatisfy { content in if case .built = content { true } else { false } }
        }
        return presentation
    }

    /// A blue picture, as a drawing or a figure would be.
    private func writePicture() throws {
        let context = try XCTUnwrap(CGContext(data: nil, width: 480, height: 240, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.05, green: 0.1, blue: 0.9, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 480, height: 240))
        _ = try vault.writeFile("Spectrum.png", data: try ImageEncoding.pngData(from: try XCTUnwrap(context.makeImage())))
    }

    /// The slide drawn at the canvas's size until its drawing stops changing (Textual and the fit settle over
    /// several drawings).
    private func picture(of content: PresentedSlideContent, root: URL, colorScheme: ColorScheme) async throws -> SlidePicture {
        let appearance = PresentationAppearance(noteTheme: nil, typography: .standard, codeColorTheme: .obsidian, accent: .blue, colorScheme: colorScheme)
        let canvasSize = NotePresentation.canvasSize
        let renderer = ImageRenderer(content: NoteSlideView(content: content, root: root)
            .frame(width: canvasSize.width, height: canvasSize.height)
            .presentationEnvironment(appearance))
        renderer.proposedSize = ProposedViewSize(canvasSize)
        renderer.scale = 1
        var previous: SlidePicture?
        for drawing in 1...40 {
            let image = try XCTUnwrap(renderer.cgImage)
            let picture = try XCTUnwrap(SlidePicture(image))
            if drawing >= 6, let previous, previous.inkBounds == picture.inkBounds { return picture }
            previous = picture
            await Task.yield()
        }
        return try XCTUnwrap(previous)
    }

    private func keep(_ picture: SlidePicture, named name: String) throws {
        let data = try ImageEncoding.pngData(from: picture.image)
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let folder = ProcessInfo.processInfo.environment["GRAPHITE_SLIDE_PICTURES"] {
            try data.write(to: URL(fileURLWithPath: folder).appendingPathComponent(name + ".png"))
        }
    }

    func testTheSlidesDrawTheirTextMathDiagramAndPictureInLightAndDark() async throws {
        try writePicture()
        let presentation = try await builtSlides(of: Self.lecture)
        XCTAssertEqual(presentation.slides.count, 4)
        for colorScheme in [ColorScheme.light, .dark] {
            let name = colorScheme == .dark ? "dark" : "light"
            var pictures: [SlidePicture] = []
            for (slideIndex, content) in presentation.slides.enumerated() {
                let picture = try await picture(of: content, root: vault.root, colorScheme: colorScheme)
                try keep(picture, named: "Slide \(slideIndex + 1) \(name)")
                pictures.append(picture)
            }
            for (slideIndex, picture) in pictures.enumerated() {
                let ink = try XCTUnwrap(picture.inkBounds, "Slide \(slideIndex + 1) (\(name)) draws something.")
                XCTAssertGreaterThanOrEqual(ink.minX, NoteSlideCanvas.horizontalMargin - 2, "Inside the margins: \(ink)")
                XCTAssertLessThanOrEqual(ink.maxY, NotePresentation.canvasSize.height - NoteSlideCanvas.verticalMargin + 2, "Nothing cut off: \(ink)")
            }
            XCTAssertEqual(pictures[0].isDarkBackground, colorScheme == .dark, "The slide follows the app's appearance.")
            // The text slide is centred on the canvas, not drawn from its top.
            let textInk = try XCTUnwrap(pictures[0].inkBounds)
            XCTAssertEqual(textInk.midY, NotePresentation.canvasSize.height / 2, accuracy: 60, "\(textInk)")
            XCTAssertGreaterThan(try XCTUnwrap(pictures[1].inkBounds).width, 120, "The formula is drawn, not left as text.")
            XCTAssertGreaterThan(try XCTUnwrap(pictures[2].inkBounds).width, 400, "The diagram's four boxes are drawn in a row.")
            XCTAssertGreaterThan(pictures[3].blueFraction, 0.05, "The picture is drawn.")
        }
    }

    func testASlideTallerThanTheScreenIsShrunkUntilItFits() async throws {
        let lines = (1...40).map { number in "Line \(number) of a slide far too long for one screen." }
        let presentation = try await builtSlides(of: lines.joined(separator: "\n\n") + "\n")
        let picture = try await picture(of: try XCTUnwrap(presentation.currentSlide), root: vault.root, colorScheme: .light)
        try keep(picture, named: "Tall slide shrunk")
        let ink = try XCTUnwrap(picture.inkBounds)
        XCTAssertGreaterThanOrEqual(ink.minY, NoteSlideCanvas.verticalMargin - 2, "The first line is on the slide: \(ink)")
        XCTAssertLessThanOrEqual(ink.maxY, NotePresentation.canvasSize.height - NoteSlideCanvas.verticalMargin + 2, "The last line is too: \(ink)")
        XCTAssertGreaterThan(ink.height, NoteSlideCanvas.columnHeight * 0.85, "Shrunk to fill the column, not further: \(ink)")
    }
}

/// A slide's picture, read for where something is drawn on its background and which colours it has.
private struct SlidePicture {
    let image: CGImage
    /// The rectangle, in the canvas's points from its top left, holding every pixel that differs from the
    /// background (the top left corner's colour); nil when nothing is drawn.
    let inkBounds: CGRect?
    let blueFraction: Double
    let isDarkBackground: Bool

    init?(_ image: CGImage) {
        let width = image.width, height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let didDraw = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard didDraw, width > 0, height > 0 else { return nil }
        self.image = image
        let background = (Int(pixels[0]), Int(pixels[1]), Int(pixels[2]))
        isDarkBackground = background.0 + background.1 + background.2 < 3 * 100
        var minimumColumn = width, maximumColumn = -1, minimumRow = height, maximumRow = -1, blueCount = 0
        for row in 0..<height {
            for column in 0..<width {
                let offset = (row * width + column) * 4
                let red = Int(pixels[offset]), green = Int(pixels[offset + 1]), blue = Int(pixels[offset + 2])
                if blue > 180, red < 90, green < 90 { blueCount += 1 }
                guard abs(red - background.0) + abs(green - background.1) + abs(blue - background.2) > 60 else { continue }
                minimumColumn = min(minimumColumn, column); maximumColumn = max(maximumColumn, column)
                minimumRow = min(minimumRow, row); maximumRow = max(maximumRow, row)
            }
        }
        blueFraction = Double(blueCount) / Double(width * height)
        inkBounds = maximumColumn < 0 ? nil
            : CGRect(x: minimumColumn, y: minimumRow, width: maximumColumn - minimumColumn + 1, height: maximumRow - minimumRow + 1)
    }
}
