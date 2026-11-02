/**
 * File: HighlightBehindFormulaTests.swift
 * ---------------------------------------
 * Layer: Tests
 * Description: Textual patch 23: a highlight runs unbroken behind a formula and stays as tall as
 *              its text, with Graphite's own colors and with a vault theme's. Reads the pixels.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 02/11/2026
 */

import XCTest
import AppKit
import SwiftUI
@testable import Textual
import GraphiteCore
@testable import GraphiteUI
import GraphiteTestSupport

@MainActor
final class HighlightBehindFormulaTests: XCTestCase {
    private static let formulas = [#"x"#, #"x=1"#, #"\frac{a}{b}"#, #"\dfrac{a}{b}"#, #"\sum_{i=1}^n x_i"#]
    private static let textSize: CGFloat = 17

    private enum Colors: CaseIterable {
        case graphites, theme
    }

    /// There was a gap as wide as the formula with Graphite's colors.
    func testAHighlightRunsUnbrokenBehindAFormula() async throws {
        for colors in Colors.allCases {
            for formula in Self.formulas {
                let drawn = try await drawing(markdown: "Before ==some $\(formula)$ words== after", colors: colors)
                let line = try XCTUnwrap(drawn.lines.first)
                // The first and the last runs are the words outside the highlight.
                let highlighted = try XCTUnwrap(line.runs.dropFirst().first).minX..<XCTUnwrap(line.runs.dropLast().last).maxX
                XCTAssertEqual(drawn.columnsWithoutHighlight(in: highlighted, of: line), [], "\(colors) \(formula)")
            }
        }
    }

    /// A background is as tall as its text, and a taller formula stands out of it. It used to grow
    /// to the formula's height, with a theme, on the whole line.
    func testAHighlightIsAsTallAsItsTextBehindATallFormula() async throws {
        for colors in Colors.allCases {
            for formula in Self.formulas {
                let drawn = try await drawing(markdown: "Before ==some $\(formula)$ words== after", colors: colors)
                let line = try XCTUnwrap(drawn.lines.first)
                let highlighted = try XCTUnwrap(line.runs.dropFirst().first).minX..<XCTUnwrap(line.runs.dropLast().last).maxX
                XCTAssertEqual(drawn.highlightedRowsOutsideItsText(in: highlighted, of: line), 0, "\(colors) \(formula)")
            }
        }
    }

    /// A paragraph that is only a highlighted formula has no text to take a height from.
    func testAHighlightHoldingOnlyAFormulaIsAsTallAsALineOfText() async throws {
        let plainLineHeight: CGFloat = try await {
            let drawn = try await drawing(markdown: "Words", colors: .graphites)
            return try XCTUnwrap(drawn.lines.first?.textHeight)
        }()
        for colors in Colors.allCases {
            for formula in Self.formulas {
                let drawn = try await drawing(markdown: "==$\(formula)$==", colors: colors)
                let line = try XCTUnwrap(drawn.lines.first)
                let height = drawn.highlightHeight(in: try XCTUnwrap(line.runs.first).minX..<XCTUnwrap(line.runs.last).maxX)
                XCTAssertEqual(height, plainLineHeight, accuracy: 1, "\(colors) \(formula)")
            }
        }
    }

    /// As tall as SwiftUI's `backgroundColor` drew it: the run's typographic height.
    func testAHighlightWithoutAFormulaIsAsTallAsItsText() async throws {
        for colors in Colors.allCases {
            let drawn = try await drawing(markdown: "Before ==some words== after", colors: colors)
            let line = try XCTUnwrap(drawn.lines.first)
            let highlighted = try XCTUnwrap(line.runs.dropFirst().first)
            XCTAssertEqual(drawn.highlightHeight(in: highlighted.minX..<highlighted.maxX), try XCTUnwrap(line.textHeight), accuracy: 1, "\(colors)")
        }
    }

    func testAHighlightIsUnbrokenOnEveryLineItWrapsTo() async throws {
        for colors in Colors.allCases {
            let markdown = #"==some words $a+b$ and more words $\frac{c}{d}$ and yet more words $e=f$ to the end=="#
            let drawn = try await drawing(markdown: markdown, colors: colors, width: 170)
            XCTAssertGreaterThan(drawn.lines.count, 1)
            for line in drawn.lines {
                let highlighted = try XCTUnwrap(line.runs.first).minX..<XCTUnwrap(line.runs.last).maxX
                XCTAssertEqual(drawn.columnsWithoutHighlight(in: highlighted, of: line), [], "\(colors)")
            }
        }
    }

    /// The reading view's highlight did not see a formula holding `=` as text it could cover: the
    /// `==` around it were shown as they are written.
    func testAFormulaWithAnEqualsSignStaysInItsHighlight() throws {
        let markdown = ObsidianInlineMarkup.preparedForReading(#"Before ==some $x=1$ words== after"#, colorsEnabled: true, paletteHexByName: [:])
        let attributed = try ObsidianMarkdownParser(baseURL: nil, textSize: Double(Self.textSize)).attributedString(for: markdown)
        XCTAssertFalse(String(attributed.characters).contains("=="))
        let formula = try XCTUnwrap(attributed.runs.first { run in run.textual.attachment != nil })
        XCTAssertNotNil(formula[RoundedRunBackgroundAttribute.self])
    }

    // MARK: Helpers

    private struct DrawnLine {
        let runs: [CGRect]
        /// The top and bottom of the line's text, or nil for a line holding only attachments.
        let textTop: CGFloat?
        let textBottom: CGFloat?
        var textHeight: CGFloat? { textBottom.flatMap { bottom in textTop.map { top in bottom - top } } }
    }

    private struct Drawing {
        let lines: [DrawnLine]
        let bitmap: NSBitmapImageRep
        let pixelsPerPoint: CGFloat

        /// Graphite's yellow at 35% over white, and the theme's own, and neither black ink nor white.
        private func isHighlighted(column: Int, row: Int) -> Bool {
            guard let color = bitmap.colorAt(x: column, y: row)?.usingColorSpace(.deviceRGB) else { return false }
            return color.blueComponent < 0.85 && color.redComponent > 0.85 && color.greenComponent > 0.75
        }

        private func columns(in range: Range<CGFloat>) -> Range<Int> {
            // A pixel at either end is only partly covered.
            Int((range.lowerBound * pixelsPerPoint).rounded(.up)) + 1 ..< Int((range.upperBound * pixelsPerPoint).rounded(.down)) - 1
        }

        func columnsWithoutHighlight(in range: Range<CGFloat>, of line: DrawnLine) -> [Int] {
            let lineRows = rows(of: line)
            return columns(in: range).filter { column in !lineRows.contains { row in isHighlighted(column: column, row: row) } }
        }

        /// How many pixels are highlighted a whole point or more above or below the text.
        func highlightedRowsOutsideItsText(in range: Range<CGFloat>, of line: DrawnLine) -> Int {
            guard let top = line.textTop, let bottom = line.textBottom else { return 0 }
            let inside = Int(((top - 1) * pixelsPerPoint).rounded(.down))...Int(((bottom + 1) * pixelsPerPoint).rounded(.up))
            let outside = (0..<bitmap.pixelsHigh).filter { row in !inside.contains(row) }
            return columns(in: range).reduce(0) { count, column in
                count + outside.filter { row in isHighlighted(column: column, row: row) }.count
            }
        }

        /// The points between the topmost and the bottommost highlighted pixel.
        func highlightHeight(in range: Range<CGFloat>) -> CGFloat {
            let highlightedRows = (0..<bitmap.pixelsHigh).filter { row in
                columns(in: range).contains { column in isHighlighted(column: column, row: row) }
            }
            guard let first = highlightedRows.first, let last = highlightedRows.last else { return 0 }
            return CGFloat(last - first + 1) / pixelsPerPoint
        }

        private func rows(of line: DrawnLine) -> Range<Int> {
            let top = line.runs.map(\.minY).min() ?? 0
            let bottom = line.runs.map(\.maxY).max() ?? 0
            return max(0, Int(top * pixelsPerPoint))..<min(bitmap.pixelsHigh, Int((bottom * pixelsPerPoint).rounded(.up)))
        }
    }

    /// The paragraph through the reading view's parser, in a window that never shows.
    private func drawing(markdown source: String, colors: Colors, width: CGFloat = 500) async throws -> Drawing {
        let capture = LayoutCapture()
        let markdown = ObsidianInlineMarkup.preparedForReading(source, colorsEnabled: true, paletteHexByName: [:])
        let themeColors = colors == .theme ? ReadingThemeColors(theme: Self.theme) : nil
        let view = StructuredText(markdown, parser: ObsidianMarkdownParser(baseURL: nil, textSize: Double(Self.textSize), themeColors: themeColors))
            .font(.system(size: Self.textSize))
            .foregroundStyle(.black)
            .overlayPreferenceValue(Text.LayoutKey.self) { layouts in
                let _ = capture.record(layouts)
                Color.clear
            }
            .frame(width: width, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .background(.white)
        let hostingView = NSHostingView(rootView: view)
        hostingView.appearance = NSAppearance(named: .aqua)
        hostingView.layoutSubtreeIfNeeded()
        let size = hostingView.fittingSize
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = hostingView
        hostingView.frame = CGRect(origin: .zero, size: size)
        window.showInvisibly()
        defer { window.contentView = nil; window.orderOut(nil) }
        for _ in 0..<5 {
            hostingView.layoutSubtreeIfNeeded()
            hostingView.displayIfNeeded()
            await Task.yield()
        }
        let layout = try XCTUnwrap(capture.layout, source)
        let bitmap = try XCTUnwrap(hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds), source)
        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)
        let lines = layout.map { line in
            let runs = Array(line)
            let text = runs.filter { run in run.attachment == nil }.map(\.typographicBounds.rect)
            return DrawnLine(runs: runs.map(\.contentBounds), textTop: text.map(\.minY).min(), textBottom: text.map(\.maxY).max())
        }
        return Drawing(lines: lines, bitmap: bitmap, pixelsPerPoint: CGFloat(bitmap.pixelsWide) / hostingView.bounds.width)
    }

    private static var theme: NoteThemeStyle {
        var light = ThemeModeTokens()
        light.highlightBackground = ThemeColor(red: 1, green: 0.8, blue: 0.2)
        return NoteThemeStyle(tokens: VaultThemeTokens(fingerprint: "test", themeName: "Test", light: light, dark: light))
    }
}

@MainActor
private final class LayoutCapture {
    private(set) var layout: Text.Layout?

    func record(_ layouts: Text.LayoutKey.Value) {
        if let anchoredLayout = layouts.first { layout = anchoredLayout.layout }
    }
}
