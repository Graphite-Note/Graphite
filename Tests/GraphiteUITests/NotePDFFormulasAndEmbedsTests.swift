/**
 * File: NotePDFFormulasAndEmbedsTests.swift
 * -----------------------------------------
 * Layer: Tests
 * Description: What a note exported to PDF shows of its wide formulas and its embeds, read back from the PDF: a wide display
 *              formula scaled onto one line in the column, Graphite drawings (SVG and PNG), a mermaid diagram, video and audio
 *              printed as their names, bases inside callouts and embedded notes, and the pictures of a base's cells.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 11/12/2026
 */

import XCTest
import SwiftUI
import PDFKit
import Textual
import GraphiteCore
import GraphiteIndex
import GraphiteApple
@testable import GraphiteUI
import GraphiteTestSupport

@MainActor
final class NotePDFFormulasAndEmbedsTests: XCTestCase {
    private var vault: TemporaryVault!
    private var index: VaultIndex!

    override func setUp() async throws {
        vault = try TemporaryVault.make(prefix: "NotePDFEmbedsVault", for: self)
        index = try VaultIndex(databaseURL: vault.cacheDirectory.appendingPathComponent("index.sqlite"))
    }

    override func tearDown() async throws {
        index = nil
        try? FileManager.default.removeItem(at: vault.cacheDirectory) // Best-effort removal of a temporary folder.
    }

    /// A derivation from the test vault's `9_Static logic`, far wider than a page's column.
    private static let wideFormula = #"\overline{Carry} = \overline{x \cdot y + y \cdot z + x \cdot z}"#
        + #" = (\bar{x} + \bar{y})(\bar{y} + \bar{z})(\bar{x} + \bar{z}) = \bar{z} \cdot (\bar{x} + \bar{y}) + z \cdot (x \cdot y)"#
        + #" = \bar{z} \cdot (\bar{x} \cdot 1 + x \cdot \bar{y}) + z \cdot (\bar{x} \cdot \bar{y} + x \cdot 0)"#

    func testAWideDisplayFormulaIsScaledOntoOneLineInsideTheColumn() async throws {
        var options = NotePDFOptions()
        options.includesFileNameAsTitle = false
        let document = try await render("$$\(Self.wideFormula)$$", options: options)
        XCTAssertEqual(document.pageCount, 1)
        let pixels = try XCTUnwrap(PrintedPagePixels(try XCTUnwrap(document.page(at: 0)), pixelsPerPoint: 2))
        let ink = try XCTUnwrap(pixels.inkBounds, "The formula is drawn.")
        let column = options.contentRect
        XCTAssertGreaterThanOrEqual(ink.minX, column.minX - 1, "Nothing is drawn left of the column: \(ink) in \(column)")
        XCTAssertLessThanOrEqual(ink.maxX, column.maxX + 1, "Nothing is drawn right of the column, no stray bar: \(ink) in \(column)")
        XCTAssertGreaterThan(ink.width, column.width * 0.9, "Scaled down to the column's width, not broken into narrower lines: \(ink)")
        let mathFontSize = CGFloat(NotePDFOptions.layoutTextSize) * MathProperties().fontScale
        let natural = try XCTUnwrap(DisplayMathRendering.metrics(for: Self.wideFormula, fontSize: mathFontSize))
        let printedLineHeight = (natural.ascent + natural.descent) * options.layoutWidth / natural.width * options.layoutScale
        XCTAssertLessThan(ink.height, printedLineHeight * 1.3, "One line, scaled as a whole (\(printedLineHeight) points), not two: \(ink)")
        attachPages(of: document, named: "Wide formula")
    }

    func testGraphiteDrawingsPrintAsTheirPicturesInSVGAndPNG() async throws {
        try writeDrawings()
        XCTAssertTrue(DrawingMetadataReader.hasEditableStrokes(at: vault.location(of: "Sketch.svg")), "A Graphite drawing, not any SVG.")
        XCTAssertTrue(DrawingMetadataReader.hasEditableStrokes(at: vault.location(of: "Board.png")), "A Graphite drawing, not any PNG.")
        let document = try await render("# Drawings\n\n![[Sketch.svg]]\n\nBetween the drawings.\n\n![[Board.png]]\n\nAfter the drawings.\n")
        let text = pageTexts(document).joined(separator: "\n")
        XCTAssertTrue(text.contains("After the drawings."), text)
        XCTAssertFalse(text.contains("Sketch.svg"), "The SVG drawing prints as its picture, not its name: \(text)")
        XCTAssertFalse(text.contains("Board.png"), "The PNG drawing prints as its picture, not its name: \(text)")
        let pages = try (0..<document.pageCount).map { pageIndex in
            try XCTUnwrap(PrintedPagePixels(try XCTUnwrap(document.page(at: pageIndex)), pixelsPerPoint: 1))
        }
        XCTAssertGreaterThan(pages.map(\.redFraction).reduce(0, +), 0.002, "The SVG drawing's red stroke is drawn.")
        XCTAssertGreaterThan(pages.map(\.blueFraction).reduce(0, +), 0.01, "The PNG drawing's blue picture is drawn.")
        attachPages(of: document, named: "Drawings")
    }

    func testAWideMermaidDiagramPrintsWholeInsideTheColumn() async throws {
        // Twenty boxes in a row: on a phone's column it would scroll sideways; paper fits it.
        let nodes = (1...20).map { number in "    Step\(number)[Step \(number)]" }
        let edges = (1..<20).map { number in "    Step\(number) --> Step\(number + 1)" }
        let note = "# Pipeline\n\n```mermaid\nflowchart LR\n" + (nodes + edges).joined(separator: "\n") + "\n```\n\nAfter the diagram.\n"
        var options = NotePDFOptions()
        options.includesFileNameAsTitle = false
        let document = try await render(note, options: options)
        let text = pageTexts(document).joined(separator: "\n")
        for number in [1, 10, 20] {
            XCTAssertTrue(text.contains("Step \(number)"), "The diagram's boxes are drawn, with their text: \(text)")
        }
        XCTAssertTrue(text.contains("After the diagram."), text)
        let pixels = try XCTUnwrap(PrintedPagePixels(try XCTUnwrap(document.page(at: 0)), pixelsPerPoint: 2))
        let ink = try XCTUnwrap(pixels.inkBounds)
        XCTAssertGreaterThanOrEqual(ink.minX, options.contentRect.minX - 1, "\(ink)")
        XCTAssertLessThanOrEqual(ink.maxX, options.contentRect.maxX + 1, "The diagram is scaled into the column: \(ink)")
        attachPages(of: document, named: "Mermaid diagram")
    }

    func testVideoAndAudioEmbedsPrintAsTheirFileNames() async throws {
        // A few bytes under a media name: nothing here could play, and printing plays nothing.
        try vault.writeFile("Clip.mp4", data: Data("not a video".utf8))
        try vault.writeFile("Lecture recording.m4a", data: Data("not a recording".utf8))
        let document = try await render("# Media\n\n![[Clip.mp4]]\n\n![[Lecture recording.m4a]]\n\nAfter the media.\n")
        let text = pageTexts(document).joined(separator: "\n")
        XCTAssertTrue(text.contains("Clip.mp4"), "The video prints as its file's name: \(text)")
        XCTAssertTrue(text.contains("Lecture recording"), "The audio prints as its file's name: \(text)")
        XCTAssertTrue(text.contains("After the media."), text)
    }

    func testBasesInsideACalloutAndAnEmbeddedNotePrintTheirRowsNotTheirYAML() async throws {
        try await writePlaces(count: 6)
        try vault.writeFile("Guide.md", text: "# Guide\n\n" + Self.placesBase(type: "list", name: "Embedded places") + "\n")
        _ = try await index.reconcile(root: vault.root)
        let calloutBase = Self.placesBase(type: "table", name: "Callout places").split(separator: "\n", omittingEmptySubsequences: false)
            .map { line in "> " + line }.joined(separator: "\n")
        let note = "# Trip\n\n> [!note] Where to eat\n> The places of the trip.\n>\n" + calloutBase + "\n\n![[Guide]]\n\nAfter the bases.\n"
        let document = try await render(note)
        let text = pageTexts(document).joined(separator: "\n")
        XCTAssertFalse(text.contains("inFolder"), "Neither base prints its YAML: \(text)")
        XCTAssertTrue(text.contains("Callout places"), "The callout's base shows its view: \(text)")
        XCTAssertTrue(text.contains("Embedded places"), "The embedded note's base shows its view: \(text)")
        for number in 1...6 {
            XCTAssertEqual(try occurrences(of: "Place \(number)", in: text), 2, "Each place is a row of both bases: Place \(number) in \(text)")
        }
        XCTAssertTrue(text.contains("After the bases."), text)
        // The embedded note's name above its blocks, then its own heading: on the Mac its
        // name was a button, which a drawing for paper shows as a placeholder.
        XCTAssertEqual(try occurrences(of: "Guide", in: text), 2, "The embedded note's name is printed as text: \(text)")
        attachPages(of: document, named: "Nested bases")
    }

    func testImageValuesInABaseTablePrintTheirPictures() async throws {
        try await writePlaces(count: 4)
        let note = Self.placesBase(type: "table", name: "With pictures", order: ["file.name", "formula.picture"],
                                   extra: "formulas:\n  picture: image(note.cover)\n")
        let document = try await render(note)
        let text = pageTexts(document).joined(separator: "\n")
        XCTAssertTrue(text.contains("Place 4"), text)
        let pixels = try XCTUnwrap(PrintedPagePixels(try XCTUnwrap(document.page(at: 0)), pixelsPerPoint: 2))
        XCTAssertGreaterThan(pixels.redFraction, 0.001, "The cells' red pictures are drawn, not empty photos.")
        attachPages(of: document, named: "Pictures in cells")
    }

    // MARK: Helpers

    private func source(_ text: String, name: String = "Trip") throws -> NotePDFSource {
        NotePDFSource(text: text, path: try VaultPath("\(name).md"), vault: try XCTUnwrap(ReadingVault(vault.root, index, store: VaultStore(root: vault.root))),
                      readingConfiguration: ReadingConfiguration(), title: name,
                      appearance: NotePDFAppearance(typography: .standard, codeColorTheme: .obsidian, accent: .blue))
    }

    private func render(_ text: String, options: NotePDFOptions = NotePDFOptions()) async throws -> PDFDocument {
        let pdf = try await NotePDFRenderer(source: try source(text), options: options).render { _ in }
        return try XCTUnwrap(PDFDocument(data: pdf.data))
    }

    private func pageTexts(_ document: PDFDocument) -> [String] {
        (0..<document.pageCount).map { pageIndex in document.page(at: pageIndex)?.string ?? "" }
    }

    /// A Graphite drawing as SVG (a red stroke, drawn from its outlines) and one as PNG (a
    /// blue picture), each with the editing data that makes it Graphite's.
    private func writeDrawings() throws {
        let red = VectorInkColor(red: 0.9, green: 0.05, blue: 0.05, alpha: 1)
        let stroke = (0...100).map { step in VectorStrokeSample(point: CGPoint(x: 20 + Double(step) * 3, y: 60), width: 14) }
        let drawing = VectorDrawing(size: CGSize(width: 340, height: 120), background: .white,
                                    shapes: [StrokeOutliner.shape(forSegments: [stroke], color: red)].compactMap { shape in shape })
        let svgPayload = DrawingPayload(width: 340, height: 120, background: .white, strokes: Data("pencil strokes".utf8))
        try vault.writeFile("Sketch.svg", data: try SVGDrawingFile.encode(drawing, payload: svgPayload))
        let context = try XCTUnwrap(CGContext(data: nil, width: 300, height: 150, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.05, green: 0.1, blue: 0.9, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 300, height: 150))
        let pngPayload = DrawingPayload(width: 300, height: 150, background: .white, strokes: Data("pencil strokes".utf8))
        let pictureData = try ImageEncoding.pngData(from: try XCTUnwrap(context.makeImage()))
        try vault.writeFile("Board.png", data: try GraphitePNG.encode(imageData: pictureData, drawing: pngPayload))
    }

    /// Places with the same red cover, in a folder of their own.
    private func writePlaces(count: Int) async throws {
        let context = try XCTUnwrap(CGContext(data: nil, width: 120, height: 80, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.9, green: 0.1, blue: 0.1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 120, height: 80))
        try vault.writeFile("Cover.png", data: try ImageEncoding.pngData(from: try XCTUnwrap(context.makeImage())))
        for number in 1...count {
            try vault.writeFile("Places/Place \(number).md", text: "---\ncuisine: Cuisine \(number)\ncover: \"[[Cover.png]]\"\n---\nA place.\n")
        }
        _ = try await index.reconcile(root: vault.root)
    }

    private static func placesBase(type: String, name: String, order: [String] = ["file.name", "cuisine"], extra: String = "") -> String {
        "```base\n" + extra + """
        filters:
          and:
            - file.inFolder("Places")
        views:
          - type: \(type)
            name: \(name)
            order:
        """ + "\n" + order.map { property in "      - \(property)" }.joined(separator: "\n") + "\n```"
    }

    /// How often `name` is printed, not counting longer names it begins ("Place 1" in "Place 12").
    private func occurrences(of name: String, in text: String) throws -> Int {
        text.matches(of: try Regex(NSRegularExpression.escapedPattern(for: name) + "(?![0-9])")).count
    }

    private func attachPages(of document: PDFDocument, named name: String) {
        let attachment = XCTAttachment(data: document.dataRepresentation() ?? Data(), uniformTypeIdentifier: "com.adobe.pdf")
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

/// A printed page's pixels on white, read for where ink is and which colours it has.
private struct PrintedPagePixels {
    /// The rectangle, in the page's points from its top left, that holds every pixel darker
    /// than the paper; nil for a blank page.
    let inkBounds: CGRect?
    /// The share of pixels that are strongly red, and strongly blue.
    let redFraction: Double
    let blueFraction: Double

    init?(_ page: PDFPage, pixelsPerPoint: CGFloat) {
        let pageSize = page.bounds(for: .mediaBox).size
        let width = Int(pageSize.width * pixelsPerPoint), height = Int(pageSize.height * pixelsPerPoint)
        guard width > 0, height > 0 else { return nil }
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let didDraw = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return false }
            context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            context.scaleBy(x: pixelsPerPoint, y: pixelsPerPoint)
            page.draw(with: .mediaBox, to: context)
            return true
        }
        guard didDraw else { return nil }
        var minimumColumn = width, maximumColumn = -1, minimumRow = height, maximumRow = -1
        var redCount = 0, blueCount = 0
        // The first row in memory is the top of the page.
        for row in 0..<height {
            for column in 0..<width {
                let offset = (row * width + column) * 4
                let red = Int(pixels[offset]), green = Int(pixels[offset + 1]), blue = Int(pixels[offset + 2])
                if red > 180, green < 90, blue < 90 { redCount += 1 }
                if blue > 180, red < 90, green < 120 { blueCount += 1 }
                guard red + green + blue < 3 * 200 else { continue }
                minimumColumn = min(minimumColumn, column); maximumColumn = max(maximumColumn, column)
                minimumRow = min(minimumRow, row); maximumRow = max(maximumRow, row)
            }
        }
        inkBounds = maximumColumn < 0 ? nil : CGRect(x: CGFloat(minimumColumn) / pixelsPerPoint, y: CGFloat(minimumRow) / pixelsPerPoint,
                                                     width: CGFloat(maximumColumn - minimumColumn + 1) / pixelsPerPoint,
                                                     height: CGFloat(maximumRow - minimumRow + 1) / pixelsPerPoint)
        redFraction = Double(redCount) / Double(width * height)
        blueFraction = Double(blueCount) / Double(width * height)
    }
}
