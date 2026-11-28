/**
 * File: InlineCodeChipTests.swift
 * -------------------------------
 * Layer: Tests
 * Description: The reading view draws inline code on a rounded tint a little wider than its text, as Obsidian and
 *              Notion do: the theme's code background or Graphite's, never over a highlight. Reads the pixels.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 28/11/2026
 */

import XCTest
import SwiftUI
@testable import Textual
import GraphiteCore
@testable import GraphiteUI

@MainActor
final class InlineCodeChipTests: XCTestCase {
    private let parser = ObsidianMarkdownParser(baseURL: nil, textSize: 16)

    private func chips(in markdown: String, parser: ObsidianMarkdownParser? = nil) throws -> [(text: String, chip: RoundedRunBackground)] {
        let text = try (parser ?? self.parser).attributedString(for: markdown)
        return text.runs.compactMap { run in
            run[RoundedRunBackgroundAttribute.self].map { chip in (String(text[run.range].characters), chip) }
        }
    }

    func testInlineCodeIsOnARoundedChipWiderThanItsText() throws {
        let found = try chips(in: "Input → `State estimation` + `start/stop` commands")
        XCTAssertEqual(found.map(\.text), ["State estimation", "start/stop"])
        for (_, chip) in found {
            XCTAssertEqual(chip.cornerRadius, 4, "Obsidian's 4-pixel corners at 16-point text.")
            XCTAssertEqual(chip.horizontalPadding, 2, "The overhang beside the text.")
            XCTAssertEqual(chip.color, Color(MarkdownTextStyler.codeBackgroundColor), "Live Preview's tint without a theme.")
        }
        XCTAssertEqual(try chips(in: "`x`", parser: ObsidianMarkdownParser(baseURL: nil, textSize: 32)).first?.chip.cornerRadius, 8,
                       "The corners follow the text size.")
        XCTAssertTrue(try chips(in: "Plain text without code.").isEmpty)
        let spaced = try parser.attributedString(for: "a `b` c")
        let kerned = spaced.runs.filter { run in run.kern != nil }.map { run in String(spaced[run.range].characters) }
        XCTAssertEqual(kerned, [" ", " "], "The spaces beside the code are widened by the chip's overhang.")
        XCTAssertEqual(try parser.attributedString(for: "`b` c").runs.filter { run in run.kern != nil }.count, 1, "None before code at the start.")
    }

    func testAThemesCodeBackgroundColoursTheChipAndAHighlightKeepsItsOwn() throws {
        var light = ThemeModeTokens()
        light.codeBackground = ThemeColor(red: 1, green: 0, blue: 0)
        let theme = NoteThemeStyle(tokens: VaultThemeTokens(fingerprint: "test", themeName: "Test", light: light, dark: light))
        let themed = ObsidianMarkdownParser(baseURL: nil, textSize: 16, themeColors: ReadingThemeColors(theme: theme))
        XCTAssertEqual(try chips(in: "a `b` c", parser: themed).first?.chip.color, theme.codeBackground.map { color in Color(color) })
        // `==a `b` c==` as the reading view hands it to the parser.
        let highlighted = try chips(in: "\(ReadingMarkers.highlightStartMarker)a `b` c\(ReadingMarkers.highlightEndMarker)")
        XCTAssertFalse(highlighted.isEmpty)
        XCTAssertTrue(highlighted.allSatisfy { found in found.chip.color == Color.yellow.opacity(0.35) }, "The highlight runs on behind its code.")
    }

    func testTheChipIsDrawnBehindTheCode() throws {
        func inkedPixels(_ markdown: String) throws -> Int {
            let view = StructuredText(markdown, parser: parser).font(.system(size: 16)).frame(width: 300, alignment: .leading)
                .environment(\.colorScheme, .light)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            let image = try XCTUnwrap(renderer.cgImage)
            let data = try XCTUnwrap(image.dataProvider?.data as Data?)
            return (0..<image.height).reduce(0) { count, row in
                count + (0..<image.width).filter { column in data[row * image.bytesPerRow + column * 4 + 3] > 0 }.count
            }
        }
        // The code's text alone inks a few hundred pixels; its chip fills its whole box, more than twice as many.
        XCTAssertGreaterThan(try inkedPixels("`mmmmmmmm`"), try inkedPixels("mmmmmmmm") * 2)
    }
}
