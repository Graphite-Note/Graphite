/**
 * File: NoteEditorCommandTests.swift
 * ----------------------------------
 * Layer: Tests
 * Description: The note editor's text commands that the bug hunt of 2026-11-01 found broken, each as the person meets it.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 01/11/2026
 */

import Foundation
import XCTest
@testable import GraphiteCore

final class NoteEditorCommandTests: XCTestCase {
    private func applied(_ edit: MarkdownTextEdit, to text: String) -> String {
        (text as NSString).replacingCharacters(in: edit.range, with: edit.replacement)
    }

    // MARK: HUNT-047

    /// The menus and the keyboard toolbar always name the closing marker, so the check runs
    /// with it: without one, only tests reached the code that removes the markup.
    func testBoldOrItalicWithTheCursorInsideRemovesTheMarkup() {
        let cases: [(text: String, opening: String)] = [("**hello world**", "**"), ("*hello world*", "*"), ("~~hello world~~", "~~"), ("==hello world==", "==")]
        for (text, opening) in cases {
            let location = (text as NSString).range(of: "world").location + 2
            let edit = MarkdownEditing.togglingWrap(opening, closingMarker: opening, in: text as NSString, selection: NSRange(location: location, length: 0))
            XCTAssertEqual(applied(edit, to: text), "hello world", opening)
            XCTAssertEqual(edit.selectionAfter, NSRange(location: location - opening.utf16.count, length: 0), opening)
        }
    }

    func testTheOtherMarkerInsideBoldStillWraps() {
        let text = "**hello world**"
        let location = (text as NSString).range(of: "world").location + 2
        let edit = MarkdownEditing.togglingWrap("~~", closingMarker: "~~", in: text as NSString, selection: NSRange(location: location, length: 0))
        XCTAssertEqual(applied(edit, to: text), "**hello ~~world~~**")
    }

    // MARK: HUNT-049

    func testLinkWithParenthesesOpensTheWholeAddress() throws {
        let located = LinkLocator.locatedLink(in: "[A](https://en.wikipedia.org/wiki/A_(B))", at: 5, includesEnd: false)
        XCTAssertEqual(located?.link, .web(try XCTUnwrap(URL(string: "https://en.wikipedia.org/wiki/A_(B)"))))
        XCTAssertEqual(located?.range.length, 40)
    }

    /// Graphite writes an address holding parentheses this way itself (`linkingSelection`).
    func testLinkInAngleBracketsOpens() throws {
        let located = LinkLocator.locatedLink(in: "[x](<https://a.b/c_(d)>)", at: 5, includesEnd: false)
        XCTAssertEqual(located?.link, .web(try XCTUnwrap(URL(string: "https://a.b/c_(d)"))))
        let note = LinkLocator.locatedLink(in: "[x](<My note.md>)", at: 5, includesEnd: false)
        XCTAssertEqual(note?.link, .note(target: "My note.md", isWiki: false))
    }

    func testLinkTitleIsNotPartOfTheAddress() throws {
        let located = LinkLocator.locatedLink(in: "[x](https://a.b \"Title\")", at: 5, includesEnd: false)
        XCTAssertEqual(located?.link, .web(try XCTUnwrap(URL(string: "https://a.b"))))
        let note = LinkLocator.locatedLink(in: "[x](Note.md 'Title')", at: 5, includesEnd: false)
        XCTAssertEqual(note?.link, .note(target: "Note.md", isWiki: false))
    }

    func testPasteOverSelectionWritesALinkThatOpens() throws {
        let text = "see this"
        let edit = try XCTUnwrap(MarkdownEditing.linkingSelection(to: "https://a.b/c_(d)", in: text as NSString, selection: NSRange(location: 4, length: 4)))
        let result = applied(edit, to: text)
        XCTAssertEqual(LinkLocator.link(in: result, at: 6, includesEnd: false), .web(try XCTUnwrap(URL(string: "https://a.b/c_(d)"))))
    }

    // MARK: HUNT-050

    func testReturnInAMathBlockAddsNoListMarker() {
        for line in ["+ b", "- c", "1. x"] {
            let text = "$$\n\(line)\n$$" as NSString
            let edit = MarkdownEditing.continuingList(in: text, selection: NSRange(location: 3 + line.utf16.count, length: 0), indentUnit: "    ")
            XCTAssertNil(edit, line)
        }
        let afterBlock = "$$\nx\n$$\n- item" as NSString
        XCTAssertNotNil(MarkdownEditing.continuingList(in: afterBlock, selection: NSRange(location: afterBlock.length, length: 0), indentUnit: "    "))
    }

    // MARK: HUNT-051 and HUNT-070

    func testHeadingOnAQuotedLineStaysInTheQuote() {
        let text = "> text"
        let edit = MarkdownEditing.settingHeading(level: 2, in: text as NSString, selection: NSRange(location: 3, length: 0))
        XCTAssertEqual(applied(edit, to: text), "> ## text")
        XCTAssertEqual(edit.selectionAfter, NSRange(location: 6, length: 0))
        let removed = MarkdownEditing.settingHeading(level: 2, in: "> ## text" as NSString, selection: NSRange(location: 6, length: 0))
        XCTAssertEqual(applied(removed, to: "> ## text"), "> text")
    }

    func testHeadingInACalloutKeepsTheCallout() {
        let text = "> [!note] Title\n> body"
        let edit = MarkdownEditing.settingHeading(level: 3, in: text as NSString, selection: NSRange(location: 0, length: (text as NSString).length))
        XCTAssertEqual(applied(edit, to: text), "> [!note] Title\n> ### body")
    }

    func testHeadingKeepsTheSelectionOnTheSameWord() {
        let text = "abc def"
        let edit = MarkdownEditing.settingHeading(level: 2, in: text as NSString, selection: NSRange(location: 0, length: 3))
        XCTAssertEqual(applied(edit, to: text), "## abc def")
        XCTAssertEqual(edit.selectionAfter, NSRange(location: 3, length: 3))
    }

    // MARK: HUNT-068

    func testTextTypedBelowClosingPropertiesKeepsThem() throws {
        let text = "---\ntitle: x\n---"
        let edit = try XCTUnwrap(MarkdownEditing.typingBelowClosingProperties(typed: "H", in: text as NSString, selection: NSRange(location: (text as NSString).length, length: 0)))
        let result = applied(edit, to: text)
        XCTAssertEqual(result, "---\ntitle: x\n---\nH")
        XCTAssertEqual(FrontmatterLocator.length(in: result as NSString), (text as NSString).length + 1)
        XCTAssertEqual(edit.selectionAfter, NSRange(location: (result as NSString).length, length: 0))
    }

    func testTypingBelowPropertiesOnlyActsAtTheirClosingLine() {
        let closed = "---\r\ntitle: x\r\n---"
        XCTAssertEqual(MarkdownEditing.typingBelowClosingProperties(typed: "H", in: closed as NSString, selection: NSRange(location: (closed as NSString).length, length: 0))?.replacement, "\r\nH", "A CRLF note stays CRLF.")
        let withLineBreak = "---\ntitle: x\n---\n" as NSString
        XCTAssertNil(MarkdownEditing.typingBelowClosingProperties(typed: "H", in: withLineBreak, selection: NSRange(location: withLineBreak.length, length: 0)))
        let closedText = "---\ntitle: x\n---" as NSString
        XCTAssertNil(MarkdownEditing.typingBelowClosingProperties(typed: " ", in: closedText, selection: NSRange(location: closedText.length, length: 0)))
        XCTAssertNil(MarkdownEditing.typingBelowClosingProperties(typed: "\n", in: closedText, selection: NSRange(location: closedText.length, length: 0)))
        XCTAssertNil(MarkdownEditing.typingBelowClosingProperties(typed: "H", in: closedText, selection: NSRange(location: 3, length: 0)))
        let plain = "Just text" as NSString
        XCTAssertNil(MarkdownEditing.typingBelowClosingProperties(typed: "H", in: plain, selection: NSRange(location: plain.length, length: 0)))
    }

    // MARK: HUNT-069

    private let foldedNote = "line\n# Folded\nhidden one\nhidden two\n# Next\n"
    private var foldedSection: NSRange { NSRange(location: 5, length: 31) }

    func testMoveLineDownGoesPastAFoldedSection() throws {
        let text = foldedNote
        let edit = try XCTUnwrap(MarkdownEditing.movingLines(up: false, in: text as NSString, selection: NSRange(location: 1, length: 0), foldedSections: [foldedSection]))
        XCTAssertEqual(applied(edit, to: text), "# Folded\nhidden one\nhidden two\nline\n# Next\n")
        XCTAssertEqual(edit.selectionAfter, NSRange(location: foldedSection.length + 1, length: 0))
    }

    func testMoveLineUpGoesPastAFoldedSection() throws {
        let text = foldedNote
        let location = (text as NSString).range(of: "# Next").location
        let edit = try XCTUnwrap(MarkdownEditing.movingLines(up: true, in: text as NSString, selection: NSRange(location: location, length: 0), foldedSections: [foldedSection]))
        XCTAssertEqual(applied(edit, to: text), "line\n# Next\n# Folded\nhidden one\nhidden two\n")
        XCTAssertEqual(edit.selectionAfter, NSRange(location: 5, length: 0))
    }

    func testAFoldedSectionMovesAsOneUnit() throws {
        let text = foldedNote
        let edit = try XCTUnwrap(MarkdownEditing.movingLines(up: false, in: text as NSString, selection: NSRange(location: 7, length: 0), foldedSections: [foldedSection]))
        XCTAssertEqual(applied(edit, to: text), "line\n# Next\n# Folded\nhidden one\nhidden two\n")
    }

    func testAFoldedSectionMovesPastTheNotesLastLine() throws {
        let text = "# Folded\nhidden\nlast"
        let section = NSRange(location: 0, length: 16)
        let edit = try XCTUnwrap(MarkdownEditing.movingLines(up: false, in: text as NSString, selection: NSRange(location: 0, length: 0), foldedSections: [section]))
        XCTAssertEqual(applied(edit, to: text), "last\n# Folded\nhidden")
    }

    // MARK: HUNT-071

    func testEscapedDelimitersAreNotStyled() {
        for (written, style) in [("\\*not italic\\*", MarkdownStyle.emphasis), ("\\_not italic\\_", .emphasis), ("\\*\\*not bold\\*\\*", .strong), ("\\**not bold**", .strong),
                                 ("\\~~not struck~~", .strikethrough), ("\\==not marked==", .highlight), ("*open\\*", .emphasis)] {
            let source = written as NSString
            let spans = MarkdownStyleScanner.spans(in: source, range: NSRange(location: 0, length: source.length))
            XCTAssertFalse(spans.contains { span in span.style == style }, written)
        }
    }

    func testAnEscapedBackslashLeavesTheDelimiterReal() {
        let source = "\\\\*italic*" as NSString
        let spans = MarkdownStyleScanner.spans(in: source, range: NSRange(location: 0, length: source.length))
        XCTAssertTrue(spans.contains { span in span.style == .emphasis })
    }

    /// Live Preview shows `\*word\*` as `*word*`, as reading view does.
    func testTheEscapingBackslashHidesAwayFromTheCursor() {
        let source = "\\*word\\* and 1\\2" as NSString
        let spans = MarkdownStyleScanner.spans(in: source, range: NSRange(location: 0, length: source.length))
        let concealed = spans.filter { span in span.style == .concealableMarker }.map(\.range)
        XCTAssertEqual(concealed, [NSRange(location: 0, length: 1), NSRange(location: 6, length: 1)])
    }

    // MARK: HUNT-048

    func testCodeUnderAListItemKeepsItsIndentationWhenFormatted() throws {
        let code = "    {\n\"a\": 1\n    }\n"
        let formatted = try XCTUnwrap(CodeFormatter.formatted(code, language: try XCTUnwrap(CodeLanguage.named("json")), fenceIndentation: "    "))
        let lines = formatted.components(separatedBy: "\n")
        XCTAssertEqual(lines.first, "    {")
        XCTAssertTrue(lines[1].hasPrefix("     "), "The code's own indentation goes on top of the fence's: \(lines[1])")
        XCTAssertEqual(lines[2], "    }")
        XCTAssertEqual(lines.last, "", "The last line break stays.")
    }

    func testCodeAtTheMarginFormatsAsBefore() throws {
        let language = try XCTUnwrap(CodeLanguage.named("json"))
        let code = "{\n\"a\": 1\n}\n"
        XCTAssertEqual(CodeFormatter.formatted(code, language: language, fenceIndentation: ""), CodeFormatter.formatted(code, language: language))
    }

    // MARK: HUNT-052

    func testAHeadingsLinkPartHoldsNothingThatBreaksALink() {
        XCTAssertEqual(LinkCompletion.linkFragment(forHeading: "P | Q"), "P Q")
        XCTAssertEqual(LinkCompletion.linkFragment(forHeading: "Use [x] here"), "Use x here")
        XCTAssertEqual(LinkCompletion.linkFragment(forHeading: "C# and ^1"), "C and 1")
        XCTAssertEqual(LinkCompletion.linkFragment(forHeading: "Plain heading"), "Plain heading")
    }

    func testALinkWrittenWithoutThoseCharactersMeetsItsHeading() {
        for heading in ["P | Q", "Use [x] here", "C# and ^1"] {
            let body = "# First\n\n## \(heading)\n\nText\n"
            let fragment = LinkCompletion.linkFragment(forHeading: heading)
            let location = NotePreviewDocument.headingLineLocation(ofHeadingWithAnchor: NotePreviewDocument.anchor(forHeading: fragment), in: body)
            XCTAssertEqual(location, (body as NSString).range(of: "## ").location, heading)
            XCTAssertEqual(LinkLocator.link(in: "[[Note#\(fragment)]]", at: 3, includesEnd: false), .note(target: "Note#\(fragment)", isWiki: true), heading)
        }
    }

    // MARK: HUNT-054, folding

    /// Before: each key on a heading or list item read every line of the note. Now: none does
    /// unless the line takes another's text; the regions move and the line's key is made anew.
    func testTypingOnAHeadingOrListItemMovesTheRegions() throws {
        let before = "# One\nbody\n## Two\nmore\n- item\n    - sub\n- other\n"
        for (line, typed) in [("# One", "x"), ("## Two", " again"), ("- item", "s"), ("- other", "wise")] {
            let source = before as NSString
            let lineRange = source.range(of: line + "\n")
            let location = lineRange.location + (line as NSString).length
            let after = source.replacingCharacters(in: NSRange(location: location, length: 0), with: typed)
            let moved = try XCTUnwrap(NoteFolding.regions(NoteFolding.regions(in: before), across: NSRange(location: location, length: 0), replacementLength: typed.utf16.count,
                                                          before: source, after: after as NSString), line)
            XCTAssertEqual(moved, NoteFolding.regions(in: after), line)
        }
    }

    func testALineTakingAnothersTextFindsTheRegionsAgain() {
        // Keys count lines of the same text, so these cannot only move.
        let before = "# One\nbody\n# Onex\nmore\n"
        let source = before as NSString
        let after = source.replacingCharacters(in: NSRange(location: 5, length: 0), with: "x")
        XCTAssertNil(NoteFolding.regions(NoteFolding.regions(in: before), across: NSRange(location: 5, length: 0), replacementLength: 1, before: source, after: after as NSString))
    }

    func testANewMarkerFindsTheRegionsAgain() {
        let before = "# One\nbody\n"
        let source = before as NSString
        let after = source.replacingCharacters(in: NSRange(location: 1, length: 0), with: "#")
        XCTAssertNil(NoteFolding.regions(NoteFolding.regions(in: before), across: NSRange(location: 1, length: 0), replacementLength: 1, before: source, after: after as NSString))
    }

    // MARK: HUNT-077

    func testAnEditCoveringTheHeadersLineBreakTouchesTheFold() throws {
        let text = "# One\nhidden\n# Two\n"
        let region = try XCTUnwrap(NoteFolding.regions(in: text).first)
        XCTAssertTrue(NoteFolding.edit(replacing: NSRange(location: 5, length: 1), touchesHiddenTextOf: region), "Forward Delete at the end of the folded line.")
        XCTAssertTrue(NoteFolding.edit(replacing: NSRange(location: 7, length: 1), touchesHiddenTextOf: region))
        XCTAssertFalse(NoteFolding.edit(replacing: NSRange(location: 5, length: 0), touchesHiddenTextOf: region), "Typing at the end of the header line stays there.")
        XCTAssertFalse(NoteFolding.edit(replacing: NSRange(location: 4, length: 1), touchesHiddenTextOf: region))
    }

    // MARK: HUNT-078

    func testAddressPastedOverWordsWithAColonLinksThem() throws {
        for words in ["Note: hello", "TODO: fix this", "Note:hello"] {
            let text = words as NSString
            let edit = try XCTUnwrap(MarkdownEditing.linkingSelection(to: "https://example.com", in: text, selection: NSRange(location: 0, length: text.length)), words)
            XCTAssertEqual(edit.replacement, "[\(words)](https://example.com)")
        }
    }

    func testAddressPastedOverAnAddressReplacesIt() {
        let text = "https://old.example" as NSString
        XCTAssertNil(MarkdownEditing.linkingSelection(to: "https://new.example", in: text, selection: NSRange(location: 0, length: text.length)))
    }
}
