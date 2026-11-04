/**
 * File: MarkdownBlockRuleTests.swift
 * ----------------------------------
 * Layer: Tests
 * Description: The reading-view and Live Preview rules Core decides: footnotes, heading links, callouts, embeds, block identifiers, reference links, raw HTML.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 01/11/2026
 */

import XCTest
@testable import GraphiteCore

/// Regression tests for the bug hunt's reading-view and Live Preview rules that Core decides
/// (HUNT-117 to HUNT-134): footnotes, heading links, callouts, embeds, block identifiers,
/// reference links, raw HTML. Each states what a note shows, not how the code gets there.
final class MarkdownBlockRuleTests: XCTestCase {
    private func callout(in blocks: [NotePreviewBlock]) -> (type: String, title: String, body: [NotePreviewBlock])? {
        for block in blocks {
            if case .callout(let type, let title, _, let body) = block { return (type, title, body) }
        }
        return nil
    }

    // MARK: Footnotes

    func testSecondParagraphOfAFootnoteBelongsToTheFootnote() {
        let text = "Ref[^1]\n\n[^1]: First paragraph.\n\n    Second paragraph, indented four spaces.\n\nAfter\n"
        let parsed = Footnotes.parse(text)
        XCTAssertEqual(parsed.definitions.map(\.text), ["First paragraph.\n\nSecond paragraph, indented four spaces."])
        let prepared = Footnotes.preparedForReading(text) { number in "{\(number)}" }
        XCTAssertEqual(prepared.text, "Ref{1}\n\n\nAfter\n", "The indented paragraph is not left in the note as a code block.")
        XCTAssertEqual(prepared.notes.map(\.text), ["First paragraph.\n\nSecond paragraph, indented four spaces."])
    }

    func testABlankLineThenTextThatIsNotIndentedEndsAFootnote() {
        let parsed = Footnotes.parse("Ref[^1]\n\n[^1]: Only this.\n\nNot part of it.\n")
        XCTAssertEqual(parsed.definitions.map(\.text), ["Only this."])
        XCTAssertEqual(parsed.definitions.first.map { ("Ref[^1]\n\n[^1]: Only this.\n\nNot part of it.\n" as NSString).substring(with: $0.range) }, "[^1]: Only this.\n")
    }

    func testAnInlineFootnoteMayHoldALinkOrBrackets() {
        let wiki = Footnotes.parse("Claim^[see [[Source note]] for details] more text").references
        XCTAssertEqual(wiki.map { $0.inlineText ?? "" }, ["see [[Source note]] for details"])
        let markdown = Footnotes.parse("Claim^[a [link](https://example.com) b] after").references
        XCTAssertEqual(markdown.map { $0.inlineText ?? "" }, ["a [link](https://example.com) b"])
        let prepared = Footnotes.preparedForReading("Claim^[see [[Source note]] for details] more text") { number in "{\(number)}" }
        XCTAssertEqual(prepared.text, "Claim{1} more text", "No stray bracket stays in the paragraph.")
    }

    func testAFootnoteReferenceInACommentTakesNoNumber() {
        let text = "%% maybe cite[^1] %% Text[^2]\n\n[^1]: Hidden\n[^2]: Shown\n"
        let numbers = Footnotes.referenceNumbers(in: text)
        XCTAssertEqual(numbers.map(\.number), [1], "Only the visible reference is numbered, and it is the first.")
        let notes = Footnotes.listed(in: text).map(\.note.text)
        XCTAssertEqual(notes.first, "Shown")
    }

    // MARK: Heading links

    func testALinkFindsAHeadingWhoseTitleHasPunctuation() {
        let body = "# One\n\n## Step 1: Setup\nthe steps\n\n## Next\nmore\n"
        let link = NotePreviewDocument.anchor(forHeading: "Step 1 Setup")
        XCTAssertEqual(NoteBlocks.embeddedPart(of: body, subpath: "Step 1 Setup"), "## Step 1: Setup\nthe steps\n")
        XCTAssertEqual(NotePreviewDocument.headingLineLocation(ofHeadingWithAnchor: link, in: body), (body as NSString).range(of: "## Step 1: Setup").location)
        XCTAssertNotNil(NoteBlocks.embeddedPart(of: body, subpath: "Step 1: Setup"), "The title as written still finds it.")
    }

    func testHeadingLinksIgnoreEveryCharacterObsidianStrips() {
        let body = "## Learning C#\nc\n\n## Ratio a|b ^c [d]\nr\n"
        XCTAssertNotNil(NoteBlocks.embeddedPart(of: body, subpath: "Learning C"))
        XCTAssertNotNil(NoteBlocks.embeddedPart(of: body, subpath: "Learning C#"))
        XCTAssertNotNil(NoteBlocks.embeddedPart(of: body, subpath: "Ratio a b c d"))
        XCTAssertNil(NoteBlocks.embeddedPart(of: body, subpath: "Ratio a b c e"))
    }

    // MARK: Callouts

    func testACalloutIndentedUpToThreeSpacesIsACallout() throws {
        let header = try XCTUnwrap(MarkdownQuoteSyntax.calloutHeader(in: "  > [!note] Title"))
        XCTAssertEqual(header.title, "Title")
        XCTAssertNil(MarkdownQuoteSyntax.calloutHeader(in: "    > [!note] Title"), "Four spaces is indented code.")
        let blocks = NotePreviewDocument.blocks(from: "   > [!tip] Tip\n   > body")
        let found = try XCTUnwrap(callout(in: blocks))
        XCTAssertEqual(found.type, "tip")
        XCTAssertEqual(found.body, [.markdown("body")])
    }

    func testACalloutInAListItemIsACallout() throws {
        let blocks = NotePreviewDocument.blocks(from: "- a\n  > [!note] Title\n  > body")
        let found = try XCTUnwrap(callout(in: blocks))
        XCTAssertEqual(found.title, "Title")
        XCTAssertEqual(found.body, [.markdown("body")])
        let nested = NotePreviewDocument.blocks(from: "1. item\n   > [!warning]\n   > careful\n\nafter")
        XCTAssertEqual(callout(in: nested)?.type, "warning")
    }

    func testLivePreviewFindsACalloutInAListItem() throws {
        let source = "- a\n    > [!note] Title\n    > body\n\nafter" as NSString
        let blocks = LivePreviewBlockScanner.blocks(in: source)
        let calloutBlock = try XCTUnwrap(blocks.first { $0.kind == .callout })
        XCTAssertEqual(source.substring(with: calloutBlock.range), "    > [!note] Title\n    > body\n")
        // Cut out of its list item, read alone, the four columns would make it code; the block says how far it was indented.
        XCTAssertNil(callout(in: NotePreviewDocument.blocks(from: calloutBlock.markdown)))
        let column = NotePreviewDocument.calloutContainerColumn(ofCutOutBlock: calloutBlock.markdown)
        let found = try XCTUnwrap(callout(in: NotePreviewDocument.locatedBlocks(from: calloutBlock.markdown, calloutContainerColumn: column).map(\.block)))
        XCTAssertEqual(found.body, [.markdown("body")])
    }

    func testACalloutContinuesOverALazyLine() throws {
        let blocks = NotePreviewDocument.blocks(from: "> [!note] T\n> line one\nline two (no >)\n\nnext paragraph")
        let found = try XCTUnwrap(callout(in: blocks))
        XCTAssertEqual(found.body, [.markdown("line one\nline two (no >)")])
        let rest = blocks.dropFirst().map { "\($0)" }.joined()
        XCTAssertTrue(rest.contains("next paragraph") && !rest.contains("line two"), rest)
    }

    func testALazyLineDoesNotContinueACalloutAfterABlockOrBlankLine() throws {
        for source in ["> [!note] T\n> # Heading\nplain", "> [!note] T\n>\nplain", "> [!note] T\n> ```\n> code\n> ```\nplain", "> [!note] T\n> text\n- list"] {
            let found = try XCTUnwrap(callout(in: NotePreviewDocument.blocks(from: source)), source)
            XCTAssertFalse("\(found.body)".contains("plain") || "\(found.body)".contains("list"), source)
        }
    }

    func testLivePreviewCalloutEndsWhereReadingViewEndsIt() throws {
        let source = "> [!note] T\n> line one\nline two\n\nnext" as NSString
        let calloutBlock = try XCTUnwrap(LivePreviewBlockScanner.blocks(in: source).first { $0.kind == .callout })
        XCTAssertEqual(source.substring(with: calloutBlock.range), "> [!note] T\n> line one\nline two\n")
    }

    // MARK: Live Preview and comments

    func testLivePreviewDrawsNothingThatSitsInAComment() {
        let calloutInComment = "%%\n> [!note] hidden\n> text\n%%\nAfter" as NSString
        XCTAssertEqual(LivePreviewBlockScanner.blocks(in: calloutInComment), [])
        let embedInComment = "%% ![[Secret]] %%\n" as NSString
        XCTAssertEqual(LivePreviewBlockScanner.blocks(in: embedInComment), [])
        let tableInComment = "%%\n| a | b |\n| - | - |\n%%\n" as NSString
        XCTAssertEqual(LivePreviewBlockScanner.blocks(in: tableInComment), [])
        let mathInComment = "%%\n$$\nx\n$$\n%%\n" as NSString
        XCTAssertEqual(LivePreviewBlockScanner.blocks(in: mathInComment), [])
    }

    func testLivePreviewStillDrawsTheBlocksAroundAComment() throws {
        let source = "%% note to self %%\n| a | b |\n| - | - |\n| 1 | 2 |\n" as NSString
        let table = try XCTUnwrap(LivePreviewBlockScanner.blocks(in: source).first)
        XCTAssertEqual(table.kind, .table)
        XCTAssertEqual(source.substring(with: table.range), "| a | b |\n| - | - |\n| 1 | 2 |\n")
        let emojiComment = "%% 🙂 hidden ![[Secret]] %%\n![[Shown]]\n" as NSString
        let embeds = LivePreviewBlockScanner.blocks(in: emojiComment)
        XCTAssertEqual(embeds.count, 1)
        XCTAssertEqual(emojiComment.substring(with: embeds[0].range), "![[Shown]]\n", "Offsets are the note's, whatever the comment holds.")
    }

    // MARK: Embeds in list items

    func testAnEmbedAloneInAListItemIsATranscludedBlock() throws {
        for source in ["- ![[Other note]]", "1. ![[Other note]]", "  * ![[Other note#Heading]]", "- [ ] ![[Other note]]"] {
            let blocks = NotePreviewDocument.blocks(from: source)
            guard case .embed(let embed)? = blocks.first else { return XCTFail("\(source) is \(blocks)") }
            XCTAssertTrue(embed.target.hasPrefix("Other note"), source)
        }
        let scanned = LivePreviewBlockScanner.blocks(in: "- ![[Other note]]\n" as NSString)
        XCTAssertEqual(scanned.count, 1)
    }

    func testAnImageInAListItemStaysInTheItem() {
        XCTAssertEqual(NotePreviewDocument.blocks(from: "- ![[photo.png]]"), [.markdown("- ![[photo.png]]")])
        XCTAssertEqual(NotePreviewDocument.blocks(from: "- Text ![[Other note]]"), [.markdown("- Text ![[Other note]]")])
    }

    // MARK: Block identifiers

    func testEmbeddingAListItemShowsItsNestedItems() throws {
        let text = "- Parent ^id\n  - child 1\n  - child 2\n- Sibling\n"
        let block = try XCTUnwrap(NoteBlocks.block(withIdentifier: "id", in: text))
        XCTAssertEqual(block.text, "- Parent", "The block itself is the item's own line.")
        XCTAssertEqual(NoteBlocks.embeddedPart(of: text, subpath: "^id"), "- Parent ^id\n  - child 1\n  - child 2")
        XCTAssertEqual(NoteBlocks.locatedEmbeddedPart(of: text, subpath: "^id")?.location, 0)
        let childIdentifier = "- Parent\n  - child 1 ^c1\n    - grandchild\n  - child 2\n"
        XCTAssertEqual(NoteBlocks.embeddedPart(of: childIdentifier, subpath: "^c1"), "  - child 1 ^c1\n    - grandchild")
    }

    func testAnIdentifierOnTheLastLineOfAQuoteOrCalloutIsFound() throws {
        let text = "> [!note] Title\n> body ^abc\n\nAfter\n"
        let block = try XCTUnwrap(NoteBlocks.block(withIdentifier: "abc", in: text))
        XCTAssertEqual(block.kind, .quote)
        XCTAssertEqual(block.text, "> [!note] Title\n> body")
        XCTAssertEqual(NoteBlocks.embeddedPart(of: text, subpath: "^abc"), "> [!note] Title\n> body")
        XCTAssertNotNil(NoteBlocks.block(withIdentifier: "q", in: "> plain quote ^q\n"))
    }

    // MARK: Reference links

    func testABlockGetsTheDefinitionsItUsesFromTheRestOfTheNote() {
        let note = "# A\nSee [the docs][1] and [other].\n\n## B\ntext\n\n[1]: https://example.com\n[Other]: https://other.example\n[unused]: https://nope.example\n    [4]: https://code.example\n"
        let definitions = ReferenceLinkDefinitions.definitions(in: note)
        XCTAssertEqual(definitions.map(\.label), ["1", "other", "unused"])
        let run = "See [the docs][1] and [other]."
        XCTAssertEqual(ReferenceLinkDefinitions.appendingDefinitions(definitions, neededBy: run),
                       run + "\n\n[1]: https://example.com\n[Other]: https://other.example")
        XCTAssertEqual(ReferenceLinkDefinitions.appendingDefinitions(definitions, neededBy: "No links."), "No links.")
        XCTAssertEqual(ReferenceLinkDefinitions.appendingDefinitions(definitions, neededBy: "[x][1]\n[1]: https://own.example"), "[x][1]\n[1]: https://own.example",
                       "A definition the block has is not added again.")
    }

    func testDefinitionsInCodeAndFootnotesAreNotReferenceDefinitions() {
        XCTAssertEqual(ReferenceLinkDefinitions.definitions(in: "```\n[1]: https://code.example\n```\n[^1]: A footnote\n"), [])
    }

    // MARK: Quoted code

    func testQuotedCodeKeepsItsHighlightsTasksAndIdentifiers() {
        let source = "> ```python\n> if a==b and c==d:\n> - [ ] task ^id\n> ```\nplain ==shown=="
        let highlighted = ReadingInlineMarking.markingHighlights(in: source)
        XCTAssertTrue(highlighted.hasPrefix("> ```python\n> if a==b and c==d:\n> - [ ] task ^id\n> ```\nplain "))
        XCTAssertTrue(highlighted.hasSuffix("\(ReadingMarkers.highlightStartMarker)shown\(ReadingMarkers.highlightEndMarker)"), "The fence ended with the quote.")
        XCTAssertEqual(ReadingInlineMarking.markingTasks(in: source), source)
        XCTAssertEqual(ReadingInlineMarking.removingBlockIdentifiers(from: source), source)
    }

    func testAFenceInAQuoteEndsWithTheQuote() {
        let source = "> ```\n> unclosed code\nafter ==x=="
        XCTAssertTrue(ReadingInlineMarking.markingHighlights(in: source).hasSuffix("\(ReadingMarkers.highlightStartMarker)x\(ReadingMarkers.highlightEndMarker)"))
        var tracker = CodeFenceTracker()
        XCTAssertTrue(tracker.isCodeLine(quotedLine: "> ```"))
        XCTAssertTrue(tracker.isCodeLine(quotedLine: ">> deeper is still code"))
        XCTAssertFalse(tracker.isCodeLine(quotedLine: "not quoted"))
        XCTAssertFalse(tracker.isInsideFence)
    }

    // MARK: Raw HTML

    func testRawHTMLIsHiddenOrMapped() {
        func prepared(_ markdown: String) -> String {
            ObsidianInlineMarkup.preparedForReading(markdown, colorsEnabled: false, paletteHexByName: [:])
        }
        XCTAssertEqual(prepared("a <!-- hidden --> b"), "a  b")
        XCTAssertEqual(prepared("x\n<!--\nmany\nlines\n-->\ny"), "x\n\ny")
        XCTAssertEqual(prepared("line one<br>line two<br/>three<BR />four"),
                       "line one\(ReadingMarkers.lineBreakMarker)line two\(ReadingMarkers.lineBreakMarker)three\(ReadingMarkers.lineBreakMarker)four")
        XCTAssertEqual(prepared("H<sub>2</sub>O and E=mc<sup>2</sup>"), "H\u{2082}O and E=mc\u{00B2}")
        XCTAssertEqual(prepared("a<sup>text</sup>"), "atext", "Text with no raised form keeps just its characters.")
        XCTAssertEqual(prepared("<mark>hot</mark>"), "\(ReadingMarkers.highlightStartMarker)hot\(ReadingMarkers.highlightEndMarker)")
        XCTAssertEqual(prepared("<u>under</u>"), "\(ReadingMarkers.underlineStartMarker)under\(ReadingMarkers.underlineEndMarker)")
        XCTAssertEqual(prepared("press <kbd>Esc</kbd>"), "press `Esc`")
        XCTAssertEqual(prepared("| a<br>b | c |\n| - | - |"), "| a\(ReadingMarkers.lineBreakMarker)b | c |\n| - | - |")
    }

    func testRawHTMLInCodeIsLeftAlone() {
        func prepared(_ markdown: String) -> String {
            ObsidianInlineMarkup.preparedForReading(markdown, colorsEnabled: false, paletteHexByName: [:])
        }
        XCTAssertEqual(prepared("`a<br>b` and <!-- c -->"), "`a<br>b` and ")
        XCTAssertEqual(prepared("```html\n<br><!-- keep -->\n```"), "```html\n<br><!-- keep -->\n```")
    }

    // MARK: Callout fold keys

    func testCalloutsWithTheSameTypeAndTitleAreCountedInOrder() {
        let text = "> [!question]- Answer\n> one\n\n> [!question]- Answer\n> two\n\n> [!tip]- Answer\n> x\n\n> [!question]- Answer\n> three\n"
        let occurrences = ReadAloudFolding.calloutOccurrences(in: text)
        let starts = text.components(separatedBy: "\n").reduce(into: (offsets: [Int](), location: 0)) { result, line in
            if line.hasPrefix("> [!") { result.offsets.append(result.location) }
            result.location += line.utf16.count + 1
        }.offsets
        XCTAssertEqual(starts.map { occurrences[$0] }, [0, 1, 0, 2])
        XCTAssertEqual(ReadAloudFolding.calloutKey(type: "question", title: "Answer"), "question|Answer")
        XCTAssertEqual(ReadAloudFolding.calloutKey(type: "question", title: "Answer", occurrence: 2), "question|Answer|2")
    }

    func testOpeningOneOfSeveralEqualCalloutsHidesTheOthersOnly() {
        let text = "> [!question]- Answer\n> one\n\n> [!question]- Answer\n> two\n"
        let expansion = [ReadAloudFolding.calloutKey(type: "question", title: "Answer", occurrence: 1): true]
        let hidden = ReadAloudFolding.hiddenRanges(in: text, foldedKeys: [], calloutExpansion: expansion)
        XCTAssertEqual(hidden.count, 1)
        XCTAssertTrue((text as NSString).substring(with: hidden[0]).contains("one"), "The first is still folded.")
        XCTAssertFalse((text as NSString).substring(with: hidden[0]).contains("two"), "The second was opened.")
    }
}
