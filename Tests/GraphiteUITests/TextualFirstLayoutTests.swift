/**
 * File: TextualFirstLayoutTests.swift
 * -----------------------------------
 * Layer: Tests
 * Description: A rendered block's text is laid out with its blocks and styled text the first time, at its final height
 *              (Textual patches 30 to 33 and 36), so a block that scrolls in is laid out once.
 *
 * Authors: Bahey Shalash
 * Version: 0.3
 * Date: 28/11/2026
 */

#if os(macOS)
import AppKit
import SwiftUI
import XCTest
@testable import GraphiteUI
import GraphiteTestSupport

/// The heights the text was laid out at, in order.
@MainActor
private final class LaidOutHeights {
    var heights: [CGFloat] = []
}

/// Offers its one subview the width it is offered and any height, as the note's stack of
/// blocks does, and writes down the height it measures.
private struct HeightRecordingLayout: Layout {
    let record: LaidOutHeights

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let size = subviews.first?.sizeThatFits(ProposedViewSize(width: proposal.width, height: nil)) ?? .zero
        MainActor.assumeIsolated { record.heights.append(size.height) }
        return size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, proposal: ProposedViewSize(width: bounds.width, height: nil))
    }
}

@MainActor
final class TextualFirstLayoutTests: XCTestCase {
    /// Upstream Textual parsed the Markdown and styled each fragment's text in `onChange`, after
    /// the first update: every rendered block was first laid out empty (a table or a formula at
    /// 0 points), then again as its text arrived, and the measuring of a table that fits laid
    /// it out once more. Measured on the iPad simulator, a table, a callout or a formula took
    /// four layout passes in the frame it scrolled in.
    func testTheTextOfARenderedBlockIsLaidOutAtItsFinalHeightTheFirstTime() throws {
        try assertLaidOutAtItsFinalHeightTheFirstTime([
            "A paragraph with **bold**, *emphasis*, `code`, $p$ inline and a [link](https://example.com).",
            "| Stage | Size | Delay |\n| --- | --- | --- |\n| 1 | 1 | 5 ps |\n| 2 | 4 | 5 ps |",
            "$$\nt_p = 0.69\\, R_{eq} \\left( C_{int} + C_L \\right)\n$$",
        ])
    }

    /// A list's items were spaced by their views in a first pass and by the list item spacing,
    /// read from a preference, in a second; a numbered list's markers were each as wide as their
    /// own number in a first pass, lining up only in a second, which laid every item's text out
    /// again at its new width (Textual patch 33).
    func testAListIsLaidOutAtItsFinalHeightTheFirstTime() throws {
        let numberedItems = (1...12).map { number in "\(number). Item \(number) of a numbered list long enough to wrap onto a second line in the column" }
        try assertLaidOutAtItsFinalHeightTheFirstTime([
            "- First item\n- Second item, long enough to wrap onto a second line in a column of six hundred points wide\n- Third item",
            numberedItems.joined(separator: "\n"),
            "1. One\n2. Two\n3. Three",
            "- Outer item\n    - Nested item\n        - Deeper item\n- Outer again",
            "- First paragraph of a loose item\n\n  Its second paragraph\n\n- Next item",
        ])
    }

    /// Text of several blocks that is not a list was spaced by its views in a first pass and by
    /// the spacing its blocks ask for, read from a preference, in a second (Textual patch 36).
    func testTextOfSeveralBlocksIsLaidOutAtItsFinalHeightTheFirstTime() throws {
        let blocks = [
            "A quote's first paragraph, long enough to wrap onto a second line in a column of six hundred points.\n\nIts second paragraph.",
            "A paragraph before a quote.\n\n> The quote's first paragraph.\n>\n> Its second paragraph.",
            "A paragraph before a table.\n\n| Stage | Size |\n| --- | --- |\n| 1 | 1 |",
            "## A heading\n\nThe paragraph under it.\n\n---\n\nA paragraph after a rule.",
        ]
        try assertLaidOutAtItsFinalHeightTheFirstTime(blocks.map { markdown in (markdown, AnyView(Self.text(markdown))) })
        // The first is laid out as one block quote, the others as the body of a callout.
        let quoted = "> " + blocks[0].replacingOccurrences(of: "\n", with: "\n> ")
        let calloutBodies = [
            "A paragraph in a callout, before its list.\n\n- First item\n- Second item, long enough to wrap onto a second line in the callout's column",
            "A paragraph in a callout.",
            "A paragraph, a code block and a list.\n\n```swift\nlet answer = 42\nprint(answer)\n```\n\n1. One\n2. Two",
        ]
        try assertLaidOutAtItsFinalHeightTheFirstTime([(quoted, AnyView(Self.text(quoted)))] + calloutBodies.map { markdown in
            (markdown, AnyView(CalloutView(type: "note", title: "Note", folding: .notFoldable, root: Self.root, textSize: 17, navigate: { _, _ in }) {
                Self.text(markdown)
            }))
        })
    }

    private static let root = URL(fileURLWithPath: "/", isDirectory: true)

    private static func text(_ markdown: String) -> ObsidianMarkdownText {
        ObsidianMarkdownText(markdown: markdown, root: root, textSize: 17, navigate: { _, _ in }, scrollToHeading: { _ in })
    }

    private func assertLaidOutAtItsFinalHeightTheFirstTime(_ blocks: [String], file: StaticString = #filePath, line: UInt = #line) throws {
        try assertLaidOutAtItsFinalHeightTheFirstTime(blocks.map { markdown in (markdown, AnyView(Self.text(markdown))) }, file: file, line: line)
    }

    private func assertLaidOutAtItsFinalHeightTheFirstTime(_ views: [(markdown: String, view: AnyView)], file: StaticString = #filePath,
                                                           line: UInt = #line) throws {
        for (markdown, view) in views {
            let record = LaidOutHeights()
            let hosting = NSHostingView(rootView: HeightRecordingLayout(record: record) { view }.frame(width: 600, alignment: .topLeading))
            let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 600, height: 400), styleMask: .borderless, backing: .buffered, defer: false)
            window.contentView = hosting
            window.showInvisibly()
            defer { window.contentView = nil; window.orderOut(nil) }
            hosting.layoutSubtreeIfNeeded()
            let firstHeight = try XCTUnwrap(record.heights.first, markdown, file: file, line: line)
            // Whatever an update sets off afterwards (state set in `onChange`, a preference, a measurement).
            RunLoop.main.run(until: Date().addingTimeInterval(0.3))
            hosting.layoutSubtreeIfNeeded()
            XCTAssertGreaterThan(firstHeight, 10, "Laid out empty first: \(markdown)", file: file, line: line)
            XCTAssertEqual(record.heights.last, firstHeight, "Laid out at \(record.heights): \(markdown)", file: file, line: line)
        }
    }
}
#endif
