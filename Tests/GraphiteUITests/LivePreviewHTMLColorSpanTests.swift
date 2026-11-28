/**
 * File: LivePreviewHTMLColorSpanTests.swift
 * -----------------------------------------
 * Layer: Tests
 * Description: Live Preview draws a `<span style="color:…;background-color:…">` in its colours with its tags hidden, shows
 *              the tags while the cursor is in the span, draws spans whether or not the Colors core plugin is on, and
 *              styles one edited line as it styles the whole note.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 28/11/2026
 */

#if os(macOS)
import XCTest
import AppKit
@testable import GraphiteCore
@testable import GraphiteUI

@MainActor
final class LivePreviewHTMLColorSpanTests: XCTestCase {
    private let note = "Plain <span style=\"color:#0b6e99;background-color:#fbf3db\">blue on yellow</span> and <span style=\"background:#ddebf1\">blue background</span> end\n"

    private func styled(_ note: String, configuration: EditorConfiguration = EditorConfiguration(mode: .livePreview),
                        revealedSelection: NSRange? = nil) -> NSTextStorage {
        let textStorage = NSTextStorage(string: note)
        let styler = MarkdownTextStyler(configuration: configuration, accentColor: .systemBlue)
        styler.applyStyles(to: textStorage, editedRange: NSRange(location: 0, length: 0), restyleEverything: true,
                            revealedMarkup: revealedSelection.map { selection in RevealedMarkup(selection: selection, in: note as NSString) }, concealedBlocks: [])
        return textStorage
    }

    private func greenComponent(of color: NSColor?) throws -> Double {
        var green = 0.0
        try XCTUnwrap(NSAppearance(named: .aqua)).performAsCurrentDrawingAppearance {
            green = Double(color?.usingColorSpace(.sRGB)?.greenComponent ?? -1)
        }
        return green
    }

    func testASpansTextAndBackgroundAreColouredAndItsTagsHidden() throws {
        let textStorage = styled(note)
        let source = note as NSString
        let blue = source.range(of: "blue on yellow").location
        XCTAssertEqual(try greenComponent(of: textStorage.attribute(.foregroundColor, at: blue, effectiveRange: nil) as? NSColor), 110.0 / 255, accuracy: 0.02)
        XCTAssertNotNil(textStorage.attribute(.backgroundColor, at: blue, effectiveRange: nil))
        let backgroundOnly = source.range(of: "blue background").location
        XCTAssertNotNil(textStorage.attribute(.backgroundColor, at: backgroundOnly, effectiveRange: nil), "`background:` colours the background too.")
        XCTAssertEqual(textStorage.attribute(.foregroundColor, at: backgroundOnly, effectiveRange: nil) as? NSColor, MarkdownTextStyler.primaryTextColor)
        XCTAssertEqual(textStorage.attribute(.foregroundColor, at: source.range(of: "<span").location, effectiveRange: nil) as? NSColor, .clear)
        XCTAssertEqual(textStorage.attribute(.foregroundColor, at: source.range(of: "</span>").location, effectiveRange: nil) as? NSColor, .clear)
        XCTAssertNil(textStorage.attribute(.backgroundColor, at: source.range(of: "Plain").location, effectiveRange: nil))
    }

    func testTheTagsShowWhileTheCursorIsInTheSpan() {
        let source = note as NSString
        let textStorage = styled(note, revealedSelection: NSRange(location: source.range(of: "on yellow").location, length: 0))
        let tagColor = textStorage.attribute(.foregroundColor, at: source.range(of: "<span").location, effectiveRange: nil) as? NSColor
        XCTAssertNotEqual(tagColor, .clear)
    }

    func testSpansAreDrawnWithTheColorsPluginOffAndNotInCode() {
        var configuration = EditorConfiguration(mode: .livePreview)
        configuration.colorsEnabled = false
        let source = note as NSString
        XCTAssertNotNil(styled(note, configuration: configuration).attribute(.backgroundColor, at: source.range(of: "blue on yellow").location, effectiveRange: nil))
        let code = "`<span style=\"background:#ddebf1\">x</span>`\n"
        XCTAssertNotEqual(styled(code).attribute(.backgroundColor, at: (code as NSString).range(of: "x<").location, effectiveRange: nil) as? NSColor,
                          NSColor.noteBackground(hex: "#ddebf1"), "Code keeps its own background.")
    }

    func testRestylingTheSpansLineMatchesRestylingTheWholeNote() {
        let multiline = "Intro\n\nFirst <span style=\"color:#d9730d\">orange\nstill orange</span> after\n\nLast line\n"
        let source = multiline as NSString
        let styler = MarkdownTextStyler(configuration: EditorConfiguration(mode: .livePreview), accentColor: .systemBlue)
        let whole = NSTextStorage(string: multiline)
        styler.applyStyles(to: whole, editedRange: NSRange(location: 0, length: 0), restyleEverything: true, revealedMarkup: nil, concealedBlocks: [])
        let line = NSTextStorage(string: multiline)
        styler.applyStyles(to: line, editedRange: NSRange(location: 0, length: 0), restyleEverything: true, revealedMarkup: nil, concealedBlocks: [])
        line.setAttributes([:], range: source.lineRange(for: NSRange(location: source.range(of: "still").location, length: 0)))
        styler.applyStyles(to: line, editedRange: source.lineRange(for: NSRange(location: source.range(of: "still").location, length: 0)),
                           restyleEverything: false, revealedMarkup: nil, concealedBlocks: [])
        let still = source.range(of: "still orange").location
        XCTAssertEqual(line.attribute(.foregroundColor, at: still, effectiveRange: nil) as? NSColor,
                       whole.attribute(.foregroundColor, at: still, effectiveRange: nil) as? NSColor)
        XCTAssertNotEqual(whole.attribute(.foregroundColor, at: still, effectiveRange: nil) as? NSColor, MarkdownTextStyler.primaryTextColor)
    }

    func testNoSpellingMarkIsSetInAHiddenTag() {
        let textStorage = styled(note)
        let source = note as NSString
        XCTAssertTrue(MarkdownTextStyler.touchesConcealedMarkup(source.range(of: "fbf3db"), in: textStorage))
        XCTAssertFalse(MarkdownTextStyler.touchesConcealedMarkup(source.range(of: "yellow"), in: textStorage), "A word of the span's text keeps its marks.")
        XCTAssertFalse(MarkdownTextStyler.touchesConcealedMarkup(source.range(of: "fbf3db"),
                                                                 in: styled(note, revealedSelection: NSRange(location: source.range(of: "on yellow").location, length: 0))),
                       "A shown tag is checked as it is typed.")
    }
}
#endif
