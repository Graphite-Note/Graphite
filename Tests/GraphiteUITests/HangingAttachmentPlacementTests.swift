/**
 * File: HangingAttachmentPlacementTests.swift
 * -------------------------------------------
 * Layer: Tests
 * Description: Textual patch 22: a line grows only by what an attachment hanging below its baseline
 *              needs, and the attachment is drawn, selected and highlighted where it really is.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 02/11/2026
 */

import XCTest
import AppKit
import SwiftUI
@testable import Textual
import GraphiteTestSupport

@MainActor
final class HangingAttachmentPlacementTests: XCTestCase {
    private static let bodyFont = Font.system(size: 17)
    private static let tolerance: CGFloat = 0.01

    // MARK: The placeholder, from plain values

    func testAnAttachmentOnOrAboveTheBaselineIsSetAsItIs() {
        for baselineOffset: CGFloat in [0, 2] {
            XCTAssertNil(HangingAttachmentPlacement(attachmentSize: CGSize(width: 10, height: 20), baselineOffset: baselineOffset, fontLineDescent: 4))
        }
    }

    func testADescentTheFontsLineHoldsDoesNotMoveThePlaceholder() throws {
        let placement = try XCTUnwrap(HangingAttachmentPlacement(attachmentSize: CGSize(width: 10, height: 21.6), baselineOffset: -3, fontLineDescent: 4))
        XCTAssertEqual(placement.placeholderSize, CGSize(width: 10, height: 18.6))
        XCTAssertEqual(placement.placeholderBaselineOffset, 0)
    }

    func testOnlyTheDescentBeyondTheFontsLineMovesThePlaceholder() throws {
        let placement = try XCTUnwrap(HangingAttachmentPlacement(attachmentSize: CGSize(width: 10, height: 21.6), baselineOffset: -7, fontLineDescent: 4))
        XCTAssertEqual(placement.placeholderSize.height, 14.6, accuracy: Self.tolerance)
        XCTAssertEqual(placement.placeholderBaselineOffset, -3)
    }

    /// SwiftUI draws an image of height 0 at 32 points, which would make the line that tall.
    func testAnAttachmentWhollyBelowTheBaselineStillHasAPlaceholderWithAHeight() throws {
        let placement = try XCTUnwrap(HangingAttachmentPlacement(attachmentSize: CGSize(width: 10, height: 5), baselineOffset: -5, fontLineDescent: 4))
        XCTAssertEqual(placement.placeholderSize, CGSize(width: 10, height: 1))
    }

    /// SwiftUI rounds the placeholder's height up, 14.6 to 15, and moves it down from the baseline.
    func testTheFrameIsTheAttachmentsOwnSizeOnTheBaselineWhateverThePlaceholdersBounds() throws {
        let placement = try XCTUnwrap(HangingAttachmentPlacement(attachmentSize: CGSize(width: 10, height: 21.6), baselineOffset: -7, fontLineDescent: 4))
        let baseline: CGFloat = 16
        let placeholderBounds = CGRect(x: 48, y: baseline + 3 - 15, width: 10, height: 15)
        let frame = placement.frame(onPlaceholderBounds: placeholderBounds)
        XCTAssertEqual(frame.minX, 48)
        XCTAssertEqual(frame.width, 10)
        XCTAssertEqual(frame.minY, baseline - 14.6, accuracy: Self.tolerance)
        XCTAssertEqual(frame.maxY, baseline + 7, accuracy: Self.tolerance)
    }

    // MARK: The line SwiftUI lays out

    /// The line has the taller of the two ascents and the taller of the two descents, and the
    /// formula is in it, its own descent below the line's baseline. It added the formula's descent
    /// and the font's on top of its whole height.
    func testALineHasTheRoomItsFormulaAndItsFontNeedAndNoMore() throws {
        let fonts: [Font] = [Self.bodyFont, .system(size: 34), .custom("Georgia", size: 30), .system(size: 13, design: .monospaced)]
        let formulas = [#"x"#, #"x_i"#, #"\frac{a}{b}"#, #"\sum_{i=1}^n x_i"#, #"\lim_{x\to 0} f"#, #"\dfrac{a}{b}"#]
        for font in fonts {
            let plainLine = try XCTUnwrap(try laidOutLines(ofMarkdown: "Some words", font: font).first)
            let environment = TextEnvironmentValues(font: font)
            for formula in formulas {
                let attachment = MathAttachment(latex: formula, style: .inline)
                let size = attachment.sizeThatFits(.unspecified, in: environment)
                let descent = -attachment.baselineOffset(in: environment)
                let line = try XCTUnwrap(try laidOutLines(ofMarkdown: "Some $\(formula)$ words", font: font).first, formula)
                // SwiftUI rounds a placeholder's height up to a whole pixel.
                let ascent = max(plainLine.ascent, size.height - descent)
                XCTAssertGreaterThanOrEqual(line.ascent, ascent - Self.tolerance, formula)
                XCTAssertLessThanOrEqual(line.ascent, ascent.rounded(.up) + Self.tolerance, formula)
                XCTAssertEqual(line.descent, max(plainLine.descent, descent), accuracy: Self.tolerance, formula)
                let frame = try XCTUnwrap(line.attachmentFrames.first, formula)
                XCTAssertEqual(frame.height, size.height, accuracy: Self.tolerance, formula)
                XCTAssertEqual(frame.maxY - line.baseline, descent, accuracy: Self.tolerance, formula)
            }
        }
    }

    /// A formula alone on a line still has the line's height: the font's, not the formula's.
    func testALineHoldingOnlyASmallFormulaIsAsTallAsALineOfText() throws {
        let plainLine = try XCTUnwrap(try laidOutLines(ofMarkdown: "Some words").first)
        let line = try XCTUnwrap(try laidOutLines(ofMarkdown: "$x$").first)
        XCTAssertEqual(line.ascent, plainLine.ascent)
        XCTAssertEqual(line.descent, plainLine.descent)
    }

    /// Display math is a block of its own and keeps the room around it: `testALineHasTheRoom…` is
    /// about formulas among words.
    func testDisplayMathKeepsItsRoom() throws {
        let plainLine = try XCTUnwrap(try laidOutLines(ofMarkdown: "Some words").first)
        let formula = #"\frac{a}{b}"#
        let environment = TextEnvironmentValues(font: Self.bodyFont)
        let attachment = MathAttachment(latex: formula, style: .block)
        let size = attachment.sizeThatFits(.unspecified, in: environment)
        let descent = -attachment.baselineOffset(in: environment)
        let line = try XCTUnwrap(try laidOutLines(ofMarkdown: "$$\(formula)$$").first)
        XCTAssertGreaterThanOrEqual(line.ascent, size.height - Self.tolerance)
        XCTAssertEqual(line.descent, plainLine.descent + descent, accuracy: Self.tolerance)
    }

    /// Each piece of a formula that wraps (patch 21) has its own line, and stays inside it.
    func testPiecesOfAWrappedFormulaStayInsideTheirLines() throws {
        let lines = try laidOutLines(ofMarkdown: #"$\frac{a}{b} + \frac{c}{d} + \frac{e}{f} + \frac{g}{h} + \frac{i}{j} + \frac{k}{l}$"#, width: 90)
        XCTAssertGreaterThan(lines.count, 1)
        XCTAssertEqual(lines.flatMap(\.attachmentFrames).count, 6)
        for line in lines {
            for frame in line.attachmentFrames {
                XCTAssertGreaterThanOrEqual(frame.minY, line.top - Self.tolerance)
                XCTAssertLessThanOrEqual(frame.maxY, line.bottom + Self.tolerance)
            }
        }
    }

    /// A row of a table is as low as the formula in its cell lets it be.
    func testATableRowGrowsOnlyByWhatItsFormulaNeeds() {
        func height(ofCell cell: String) -> CGFloat {
            let table = "| Heading |\n| --- |\n| \(cell) |"
            let view = StructuredText(markdown: table, syntaxExtensions: [.math]).font(Self.bodyFont).frame(width: 300, alignment: .leading)
            let hostingView = NSHostingView(rootView: view)
            hostingView.layoutSubtreeIfNeeded()
            return hostingView.fittingSize.height
        }
        XCTAssertLessThan(height(ofCell: #"$\frac{a}{b}$"#) - height(ofCell: "plain"), 5)
    }

    // MARK: Whatever needs the attachment's place

    func testSelectionFindsAnAttachmentWhereItIsNotWhereItsPlaceholderIs() throws {
        let attachmentRuns = try laidOutRuns(ofMarkdown: #"Some $\dfrac{a}{b}$ words"#).filter { run in run.attachment != nil }
        let run = try XCTUnwrap(attachmentRuns.first)
        XCTAssertGreaterThan(run.contentBounds.height, run.typographicBounds.rect.height, "The placeholder is smaller than the formula.")
        let selectable = LiveTextRun(base: run, offset: 0)
        XCTAssertEqual(selectable.typographicBounds, run.contentBounds)
        XCTAssertEqual(selectable.slices.first?.typographicBounds, run.contentBounds)
    }

    func testTheReadingHighlightCoversTheFormula() async throws {
        let frames = HighlightFrames()
        let formula = #"\dfrac{a}{b}"#
        let view = StructuredText("Some words", parser: FormulaWithSourceRangeParser(latex: formula))
            .font(Self.bodyFont)
            .textual.readingHighlight(FormulaWithSourceRangeParser.sourceRange, coordinateSpace: "Probe")
            .coordinateSpace(.named("Probe"))
            .onPreferenceChange(ReadingHighlightGeometryKey.self) { geometries in
                MainActor.assumeIsolated { frames.geometries = geometries }
            }
            .frame(width: 400, height: 200, alignment: .topLeading)
        let hostingView = NSHostingView(rootView: view)
        let window = shownInvisibly(hostingView, size: CGSize(width: 400, height: 200))
        defer { window.contentView = nil; window.orderOut(nil) }
        let deadline = ContinuousClock.now + .seconds(10)
        while frames.geometries.isEmpty, ContinuousClock.now < deadline {
            hostingView.layoutSubtreeIfNeeded()
            hostingView.displayIfNeeded()
            await Task.yield()
        }
        let frame = try XCTUnwrap(frames.geometries.first).frame
        let environment = TextEnvironmentValues(font: Self.bodyFont)
        let size = MathAttachment(latex: formula, style: .inline).sizeThatFits(.unspecified, in: environment)
        XCTAssertEqual(frame.height, size.height, accuracy: Self.tolerance)
    }

    /// The formula is really drawn on the baseline of the words around it, with a descent the
    /// line has to grow for and with none: the letter's feet are as low as a word's.
    func testAFormulaIsDrawnOnTheBaselineOfTheWordsAroundIt() throws {
        for formula in [#"n"#, #"n_{i_j}"#] {
            let lettersFeet = try lowestInk(ofMarkdown: "n $\(formula)$ n", formula: formula)
            XCTAssertEqual(lettersFeet.formula, lettersFeet.word, accuracy: 0.75, formula)
        }
    }

    // MARK: Helpers

    private struct LaidOutLine {
        let ascent: CGFloat
        let descent: CGFloat
        let baseline: CGFloat
        let attachmentFrames: [CGRect]

        var top: CGFloat { baseline - ascent }
        var bottom: CGFloat { baseline + descent }
    }

    private func laidOutLines(ofMarkdown markdown: String, width: CGFloat = 800, font: Font = bodyFont) throws -> [LaidOutLine] {
        let layout = try XCTUnwrap(laidOutLayout(ofMarkdown: markdown, width: width, font: font).layout, markdown)
        return layout.map { line in
            let runs = Array(line)
            return LaidOutLine(
                ascent: line.typographicBounds.ascent,
                descent: line.typographicBounds.descent,
                baseline: line.typographicBounds.origin.y,
                attachmentFrames: runs.filter { run in run.attachment != nil }.map(\.contentBounds)
            )
        }
    }

    private func laidOutRuns(ofMarkdown markdown: String) throws -> [Text.Layout.Run] {
        let layout = try XCTUnwrap(laidOutLayout(ofMarkdown: markdown, width: 800, font: Self.bodyFont).layout, markdown)
        return layout.flatMap { line in Array(line) }
    }

    /// The paragraph hosted in a window that never shows, and the layout SwiftUI made of it.
    private func laidOutLayout(ofMarkdown markdown: String, width: CGFloat, font: Font) -> (layout: Text.Layout?, hostingView: NSView, window: NSWindow) {
        let capture = LayoutCapture()
        let view = StructuredText(markdown: markdown, syntaxExtensions: [.math])
            .font(font)
            .foregroundStyle(.black)
            .overlayPreferenceValue(Text.LayoutKey.self) { layouts in
                let _ = capture.record(layouts)
                Color.clear
            }
            .frame(width: width, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .background(.white)
        let hostingView = NSHostingView(rootView: view)
        hostingView.layoutSubtreeIfNeeded()
        let size = hostingView.fittingSize
        let window = shownInvisibly(hostingView, size: size)
        hostingView.layoutSubtreeIfNeeded()
        hostingView.displayIfNeeded()
        defer { window.orderOut(nil) }
        return (capture.layout, hostingView, window)
    }

    private func shownInvisibly(_ hostingView: NSView, size: CGSize) -> NSWindow {
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = hostingView
        hostingView.frame = CGRect(origin: .zero, size: size)
        window.showInvisibly()
        return window
    }

    /// How low the ink goes, in points from the view's top: of the word before the formula, and of
    /// the formula's first letter, which ends before its subscript starts.
    private func lowestInk(ofMarkdown markdown: String, formula: String) throws -> (word: CGFloat, formula: CGFloat) {
        let laidOut = laidOutLayout(ofMarkdown: markdown, width: 400, font: Self.bodyFont)
        defer { laidOut.window.contentView = nil }
        let layout = try XCTUnwrap(laidOut.layout, formula)
        let line = try XCTUnwrap(layout.first, formula)
        let runs = Array(line)
        let word = try XCTUnwrap(runs.first { run in run.attachment == nil }).contentBounds
        let drawnFormula = try XCTUnwrap(runs.first { run in run.attachment != nil }).contentBounds
        let bitmap = try XCTUnwrap(laidOut.hostingView.bitmapImageRepForCachingDisplay(in: laidOut.hostingView.bounds), formula)
        laidOut.hostingView.cacheDisplay(in: laidOut.hostingView.bounds, to: bitmap)
        let pixelsPerPoint = CGFloat(bitmap.pixelsWide) / laidOut.hostingView.bounds.width
        func lowestInk(from minimumX: CGFloat, to maximumX: CGFloat) -> CGFloat? {
            for row in stride(from: bitmap.pixelsHigh - 1, through: 0, by: -1) {
                for column in Int(minimumX * pixelsPerPoint)..<Int(maximumX * pixelsPerPoint) {
                    guard let color = bitmap.colorAt(x: column, y: row)?.usingColorSpace(.deviceGray) else { continue }
                    if color.whiteComponent < 0.5 { return CGFloat(row + 1) / pixelsPerPoint }
                }
            }
            return nil
        }
        let wordCharacterWidth: CGFloat = 8 // The letter `n` of the word, without the space after it.
        let firstLetterWidth: CGFloat = 8 // The letter `n` of the formula, without its subscript.
        return (
            try XCTUnwrap(lowestInk(from: word.minX, to: word.minX + wordCharacterWidth), formula),
            try XCTUnwrap(lowestInk(from: drawnFormula.minX, to: drawnFormula.minX + firstLetterWidth), formula)
        )
    }
}

@MainActor
private final class LayoutCapture {
    private(set) var layout: Text.Layout?

    func record(_ layouts: Text.LayoutKey.Value) {
        if let anchoredLayout = layouts.first { layout = anchoredLayout.layout }
    }
}

@MainActor
private final class HighlightFrames {
    var geometries: [ReadingHighlightGeometry] = []
}

/// Words around one formula, which carries a source range as the reading view's formulas do.
private struct FormulaWithSourceRangeParser: MarkupParser {
    static let sourceRange = NSRange(location: 0, length: 1)

    let latex: String

    func attributedString(for input: String) throws -> AttributedString {
        var formula = AttributedString(
            "\u{FFFC}",
            attributes: AttributeContainer().attachment(AnyAttachment(MathAttachment(latex: latex, style: .inline)))
        )
        formula[ReadingSourceRangeAttribute.self] = Self.sourceRange
        return AttributedString("\(input) ") + formula
    }
}
