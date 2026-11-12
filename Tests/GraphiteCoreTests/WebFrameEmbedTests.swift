/**
 * File: WebFrameEmbedTests.swift
 * ------------------------------
 * Layer: Tests
 * Description: Web frames found in note source: the owner's `<iframe>` line, attributes in every spelling, sizes and
 *              looks, addresses that stay text, frames in callouts, list items, code and comments, the reading view's
 *              and Live Preview's blocks agreeing, which frames hold a live page, and `#ccc` in HTML left untagged.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 12/11/2026
 */

import XCTest
@testable import GraphiteCore

final class WebFrameEmbedTests: XCTestCase {
    /// The line of the owner's note `4_Amdahl's Law in the Multicore Era` (2026-11-12).
    static let ownersLine = #"<iframe src="https://research.cs.wisc.edu/multifacet/amdahl/" width="100%" height="900" style="border:1px solid #ccc; border-radius:6px"></iframe>"#

    private func frame(_ text: String) -> WebFrameEmbed? {
        let lines = text.components(separatedBy: "\n")
        return WebFrameSyntax.frame(startingAt: 0, lineCount: lines.count, line: { index in lines[index] })?.frame
    }

    private func frameLines(_ text: String) -> (frame: WebFrameEmbed, lastLineIndex: Int)? {
        let lines = text.components(separatedBy: "\n")
        return WebFrameSyntax.frame(startingAt: 0, lineCount: lines.count, line: { index in lines[index] })
    }

    // MARK: The tag

    func testTheOwnersLineIsAFrameOfItsAddressSizeBorderAndCorners() throws {
        let frame = try XCTUnwrap(frame(Self.ownersLine))
        XCTAssertEqual(frame.address.absoluteString, "https://research.cs.wisc.edu/multifacet/amdahl/")
        XCTAssertEqual(frame.width, .fractionOfColumn(1))
        XCTAssertEqual(frame.height, 900)
        XCTAssertEqual(frame.cornerRadius, 6)
        let border = try XCTUnwrap(frame.border)
        XCTAssertEqual(border.width, 1)
        let color = try XCTUnwrap(border.color)
        XCTAssertEqual(color.red, 0.8, accuracy: 0.001)
        XCTAssertEqual(color.green, 0.8, accuracy: 0.001)
        XCTAssertEqual(color.blue, 0.8, accuracy: 0.001)
        XCTAssertEqual(frame.shownWidth(columnWidth: 700), 700)
        XCTAssertEqual(frame.shownHeight, 900)
        XCTAssertEqual(frame.siteName, "research.cs.wisc.edu")
        XCTAssertEqual(frame.name, frame.address.absoluteString, "Without a title the frame is named by its address.")
    }

    func testAttributesAreReadInAnyOrderCaseAndQuoting() throws {
        let spellings = [
            #"<IFRAME HEIGHT=200 SRC='https://example.com/page' WIDTH="400"></IFRAME>"#,
            #"<iframe width='400' src=https://example.com/page height="200"></iframe>"#,
            #"   <iframe height="200"   width=400 src="https://example.com/page" ></iframe >  "#,
        ]
        for spelling in spellings {
            let frame = try XCTUnwrap(frame(spelling), spelling)
            XCTAssertEqual(frame.address.absoluteString, "https://example.com/page", spelling)
            XCTAssertEqual(frame.width, .points(400), spelling)
            XCTAssertEqual(frame.height, 200, spelling)
            XCTAssertNil(frame.border, "No style, no border: \(spelling)")
        }
    }

    func testTheTagMayRunOverSeveralLinesAndItsClosingTagEndsTheLastOne() throws {
        let source = """
            <iframe
              src="https://example.com/grapher"
              title="Amdahl's grapher"
              height="480">
            </iframe>
            After
            """
        let found = try XCTUnwrap(frameLines(source))
        XCTAssertEqual(found.lastLineIndex, 4)
        XCTAssertEqual(found.frame.title, "Amdahl's grapher")
        XCTAssertEqual(found.frame.name, "Amdahl's grapher")
        XCTAssertEqual(found.frame.height, 480)
        XCTAssertNil(found.frame.width)
        XCTAssertEqual(found.frame.shownWidth(columnWidth: 700), 300, "Without a width, a browser's 300 points.")
        XCTAssertEqual(found.frame.shownWidth(columnWidth: 250), 250, "Never wider than the column.")
        XCTAssertNil(frame("<iframe src=\"https://example.com\"\n\n></iframe>"), "A blank line ends an HTML block.")
    }

    func testSizesInPointsPercentagesAndTheStyleWhichWinsOverTheAttributes() throws {
        XCTAssertEqual(frame(#"<iframe src="https://a.example" width="600px" height="320px"></iframe>"#)?.width, .points(600))
        XCTAssertEqual(frame(#"<iframe src="https://a.example" width="50%"></iframe>"#)?.shownWidth(columnWidth: 700), 350)
        let styled = try XCTUnwrap(frame(#"<iframe src="https://a.example" width="300" height="100" style="width: 80%; height: 400px !important"></iframe>"#))
        XCTAssertEqual(styled.width, .fractionOfColumn(0.8))
        XCTAssertEqual(styled.height, 400)
        let defaults = try XCTUnwrap(frame(#"<iframe src="https://a.example"></iframe>"#))
        XCTAssertNil(defaults.height)
        XCTAssertEqual(defaults.shownHeight, 150, "Without a height, a browser's 150 points.")
        // Units Graphite does not read, a height in percent, and nonsense leave the default.
        let unread = try XCTUnwrap(frame(#"<iframe src="https://a.example" width="20em" height="50%" style="height: 3vh; color: red"></iframe>"#))
        XCTAssertNil(unread.width)
        XCTAssertNil(unread.height)
        XCTAssertNil(frame(#"<iframe src="https://a.example" height="99999999"></iframe>"#)?.height, "A size past any page's is not taken.")
        XCTAssertNil(frame(#"<iframe src="https://a.example" height="-20"></iframe>"#)?.height)
    }

    func testBordersFollowCSSAndOtherStylesAreLeftOut() throws {
        XCTAssertNil(frame(#"<iframe src="https://a.example" style="border: none"></iframe>"#)?.border)
        XCTAssertNil(frame(#"<iframe src="https://a.example" style="border: 0"></iframe>"#)?.border)
        XCTAssertNil(frame(#"<iframe src="https://a.example" style="border: 1px #ccc"></iframe>"#)?.border, "Without a style, CSS draws no line.")
        let dashed = try XCTUnwrap(frame(#"<iframe src="https://a.example" style="BORDER: 2px dashed rgb(255, 0, 0)"></iframe>"#)?.border)
        XCTAssertEqual(dashed.width, 2)
        XCTAssertEqual(dashed.color, WebFrameEmbed.Color(red: 1, green: 0, blue: 0, alpha: 1))
        let medium = try XCTUnwrap(frame(#"<iframe src="https://a.example" style="border: solid gray"></iframe>"#)?.border)
        XCTAssertEqual(medium.width, 3, "A style with no width is medium.")
        XCTAssertEqual(medium.color?.red ?? 0, 128.0 / 255, accuracy: 0.001)
        let unknownColor = try XCTUnwrap(frame(#"<iframe src="https://a.example" style="border: thin solid currentColor"></iframe>"#)?.border)
        XCTAssertEqual(unknownColor.width, 1)
        XCTAssertNil(unknownColor.color, "A colour Graphite does not read draws the note's own.")
        XCTAssertEqual(frame(#"<iframe src="https://a.example" style="border-radius: 12px 4px"></iframe>"#)?.cornerRadius, 12)
        XCTAssertEqual(frame(#"<iframe src="https://a.example" style="border-radius: 50%"></iframe>"#)?.cornerRadius, 0)
    }

    func testCharacterReferencesInTheAddressAndTitleAreRead() throws {
        let frame = try XCTUnwrap(frame(#"<iframe src="https://www.youtube.com/embed/abc?start=10&amp;rel=0" title="A &quot;talk&quot; &#8212; part 1"></iframe>"#))
        XCTAssertEqual(frame.address.absoluteString, "https://www.youtube.com/embed/abc?start=10&rel=0")
        XCTAssertEqual(frame.title, "A \"talk\" \u{2014} part 1")
    }

    /// Decision 1: only web addresses. Every other `src`, and a frame without one, stays text until a later section decides.
    func testOnlyWebAddressesAreFramesAndAnythingElseStaysText() {
        for source in ["file:///Users/someone/notes/a.html", "javascript:alert(1)", "data:text/html,<b>hi</b>", "Notes/Page.html", "//example.com/a",
                       "ftp://example.com/a", "https://", ""] {
            XCTAssertNil(frame("<iframe src=\"\(source)\"></iframe>"), source)
        }
        XCTAssertNil(frame("<iframe width=\"100%\"></iframe>"), "No src.")
        XCTAssertNotNil(frame("<iframe src=\"http://example.com/plain\"></iframe>"), "http is a web address too.")
    }

    func testMalformedTagsStayText() {
        XCTAssertNil(frame(#"<iframe src="https://a.example">"#), "No closing tag.")
        XCTAssertNil(frame(#"<iframe src="https://a.example"></iframe> and more text"#), "Text after the closing tag: inline HTML in a paragraph.")
        XCTAssertNil(frame(#"See <iframe src="https://a.example"></iframe>"#), "A frame inside a sentence stays text.")
        XCTAssertNil(frame(#"<iframes src="https://a.example"></iframes>"#))
        XCTAssertNil(frame(#"<iframe src="https://a.example></iframe>"#), "An unclosed quote.")
        XCTAssertNil(frame(#"<iframe src="https://a.example"></iframe"#))
        let unclosed = Array(repeating: "line", count: 40).joined(separator: "\n")
        XCTAssertNil(frame("<iframe src=\"https://a.example\"\n" + unclosed), "An open tag is not read past its limit.")
    }

    func testAFrameAloneInAListItemIsAFrameAndOneInATaskIsNot() {
        XCTAssertNotNil(frame("- " + Self.ownersLine))
        XCTAssertNotNil(frame("  12. " + Self.ownersLine))
        XCTAssertNil(frame("- [ ] " + Self.ownersLine), "A task keeps its checkbox and its text.")
        XCTAssertNil(frame("-" + Self.ownersLine))
    }

    // MARK: The reading view's blocks

    func testTheReadingViewGivesTheFrameABlockOfItsOwnBetweenItsText() throws {
        let body = "Intro paragraph.\n" + Self.ownersLine + "\nAfter the frame, #tag."
        let located = NotePreviewDocument.locatedBlocks(from: body)
        XCTAssertEqual(located.map(\.block), [.markdown("Intro paragraph."), .webFrame(try XCTUnwrap(frame(Self.ownersLine))), .markdown("After the frame, #tag.")])
        XCTAssertEqual(located[1].startOffset, ("Intro paragraph.\n" as NSString).length)
        XCTAssertEqual(located[1].lineCount, 1)
    }

    func testFramesInCalloutsAndListItemsAreBlocksAndInCodeOrCommentsAreText() throws {
        let callout = NotePreviewDocument.blocks(from: "> [!note] Grapher\n> " + Self.ownersLine + "\n> Below it.")
        guard case .callout(_, _, _, let body) = try XCTUnwrap(callout.first) else { return XCTFail("A callout") }
        XCTAssertEqual(body.first, .webFrame(try XCTUnwrap(frame(Self.ownersLine))))
        XCTAssertEqual(NotePreviewDocument.blocks(from: "- first\n- " + Self.ownersLine + "\n- third").count, 3)
        let fenced = NotePreviewDocument.blocks(from: "```html\n" + Self.ownersLine + "\n```")
        XCTAssertEqual(fenced, [.markdown("```html\n" + Self.ownersLine + "\n```")])
        XCTAssertEqual(NotePreviewDocument.blocks(from: "`" + Self.ownersLine + "`"), [.markdown("`" + Self.ownersLine + "`")])
        XCTAssertFalse(NotePreviewDocument.blocks(from: "%%\n" + Self.ownersLine + "\n%%\nText").contains { block in
            if case .webFrame = block { true } else { false }
        }, "A frame in a comment is hidden with it.")
        XCTAssertEqual(NotePreviewDocument.blocks(from: "Text with <iframe src=\"https://a.example\"></iframe> inside."),
                       [.markdown("Text with <iframe src=\"https://a.example\"></iframe> inside.")])
    }

    // MARK: Live Preview's blocks

    func testLivePreviewFindsTheSameLinesAsTheReadingView() throws {
        let note = "# Notes\n\nIntro\n<iframe\n  src=\"https://example.com/grapher\" height=\"480\">\n</iframe>\n\n> [!tip]\n> " + Self.ownersLine + "\n\n```\n" + Self.ownersLine + "\n```\n"
        let source = note as NSString
        let frames = LivePreviewBlockScanner.blocks(in: source).filter { block in
            if case .webFrame = block.kind { true } else { false }
        }
        XCTAssertEqual(frames.count, 1, "The tag on lines of its own; the callout draws its own, and code stays code.")
        let block = try XCTUnwrap(frames.first)
        XCTAssertEqual(source.substring(with: block.range), "<iframe\n  src=\"https://example.com/grapher\" height=\"480\">\n</iframe>\n")
        guard case .webFrame(let found) = block.kind else { return XCTFail("A frame") }
        let readingFrames = NotePreviewDocument.blocks(from: note).compactMap { block -> WebFrameEmbed? in
            if case .webFrame(let frame) = block { frame } else { nil }
        }
        XCTAssertEqual(readingFrames.first, found, "The two views read the same frame.")
        XCTAssertTrue(LivePreviewBlockScanner.blocks(in: source).contains { block in block.kind == .callout && WebFrameSyntax.mayHoldFrame(block.markdown) })
        XCTAssertTrue(LivePreviewBlockScanner.blocks(in: "%% " + Self.ownersLine + " %%" as NSString).isEmpty)
    }

    // MARK: Which frames hold a live page

    func testOnlyTheFewFramesNearestTheScreenHoldAPage() {
        let distances = ["on screen": 0, "below": 0.4, "next screen": 0.9, "far": 2.5, "farther": 6, "also near": 0.2, "near too": 0.5]
        let live = WebFrameLiveSelection.liveFrames(distances: distances, currentlyLive: [])
        XCTAssertEqual(live, ["on screen", "also near", "below", "near too"], "The four nearest; one a screen away waits.")
        XCTAssertEqual(WebFrameLiveSelection.liveFrames(distances: ["a": 2.5], currentlyLive: []), [], "Not loaded two screens away.")
        XCTAssertEqual(WebFrameLiveSelection.liveFrames(distances: ["a": 2.5], currentlyLive: ["a"]), ["a"], "Kept until three screens away.")
        XCTAssertEqual(WebFrameLiveSelection.liveFrames(distances: ["a": 3.5], currentlyLive: ["a"]), [], "Given up past three.")
        XCTAssertEqual(WebFrameLiveSelection.liveFrames(distances: ["a": 0, "b": 0], currentlyLive: ["b"], maximumLiveCount: 1), ["b"],
                       "Between two as near, the live one keeps its page.")
        XCTAssertEqual(WebFrameLiveSelection.distance(frameTop: -500, frameBottom: -100, visibleTop: 0, visibleBottom: 1_000), 0.1)
        XCTAssertEqual(WebFrameLiveSelection.distance(frameTop: 3_000, frameBottom: 3_100, visibleTop: 0, visibleBottom: 1_000), 2)
        XCTAssertEqual(WebFrameLiveSelection.distance(frameTop: 900, frameBottom: 1_800, visibleTop: 0, visibleBottom: 1_000), 0)
    }

    // MARK: Tags inside HTML (section 1)

    /// The owner's line coloured `#ccc` as a tag. The index already leaves HTML out of a note's tags; the editor's
    /// highlighting now does too, and a tag beside the HTML is still one.
    func testAHashInsideAnHTMLTagIsNotATagInTheIndexOrTheEditor() throws {
        XCTAssertEqual(try MarkdownSemantics.parse(Self.ownersLine + "\n\nFiled under #real").tags, ["real"])
        XCTAssertEqual(try MarkdownSemantics.parse("<div style=\"color: #abc\">\n#inside\n</div>\n\nafter #tag").tags, ["tag"])
        let line = "Red <span style=\"color:#f00\">text</span> and #real" as NSString
        let tags = MarkdownStyleScanner.spans(in: line, range: NSRange(location: 0, length: line.length))
            .filter { span in span.style == .tag }.map { span in line.substring(with: span.range) }
        XCTAssertEqual(tags, ["#real"])
        let owners = Self.ownersLine as NSString
        XCTAssertFalse(MarkdownStyleScanner.spans(in: owners, range: NSRange(location: 0, length: owners.length)).contains { span in span.style == .tag })
    }
}
