/**
 * File: TextualFirstLayoutTests.swift
 * -----------------------------------
 * Layer: Tests
 * Description: A rendered block's text is laid out with its blocks and styled text the first time, at its final height
 *              (Textual patches 30 to 32), so a block that scrolls in is laid out once.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 27/11/2026
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

/// Passes its one subview through and writes down the height it measures.
private struct HeightRecordingLayout: Layout {
    let record: LaidOutHeights

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let size = subviews.first?.sizeThatFits(proposal) ?? .zero
        MainActor.assumeIsolated { record.heights.append(size.height) }
        return size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, proposal: ProposedViewSize(bounds.size))
    }
}

@MainActor
final class TextualFirstLayoutTests: XCTestCase {
    /// Upstream Textual parsed the Markdown and styled each fragment's text in `onChange`, after
    /// the first update: every rendered block was first laid out empty (a table or a formula at
    /// 0 points), then again as its text arrived, and the measuring of a table that fits laid
    /// it out once more. Measured on the iPad simulator, a table, a callout or a formula took
    /// four layout passes in the frame it scrolled in. Text of several blocks, such as a list,
    /// still takes one more pass: the block stack learns the spacing between them from a
    /// preference (`BlockVStack`), which is left as it is.
    func testTheTextOfARenderedBlockIsLaidOutAtItsFinalHeightTheFirstTime() throws {
        let blocks = [
            "A paragraph with **bold**, *emphasis*, `code`, $p$ inline and a [link](https://example.com).",
            "| Stage | Size | Delay |\n| --- | --- | --- |\n| 1 | 1 | 5 ps |\n| 2 | 4 | 5 ps |",
            "$$\nt_p = 0.69\\, R_{eq} \\left( C_{int} + C_L \\right)\n$$",
        ]
        for markdown in blocks {
            let record = LaidOutHeights()
            let text = ObsidianMarkdownText(markdown: markdown, root: URL(fileURLWithPath: "/", isDirectory: true), textSize: 17,
                                            navigate: { _, _ in }, scrollToHeading: { _ in })
            let hosting = NSHostingView(rootView: HeightRecordingLayout(record: record) { text }.frame(width: 600, alignment: .topLeading))
            let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 600, height: 400), styleMask: .borderless, backing: .buffered, defer: false)
            window.contentView = hosting
            window.showInvisibly()
            defer { window.contentView = nil; window.orderOut(nil) }
            hosting.layoutSubtreeIfNeeded()
            let firstHeight = try XCTUnwrap(record.heights.first, markdown)
            // Whatever an update sets off afterwards (state set in `onChange`, a preference, a measurement).
            RunLoop.main.run(until: Date().addingTimeInterval(0.3))
            hosting.layoutSubtreeIfNeeded()
            XCTAssertGreaterThan(firstHeight, 10, "Laid out empty first: \(markdown)")
            XCTAssertEqual(record.heights.last, firstHeight, "Laid out at \(record.heights): \(markdown)")
        }
    }
}
#endif
