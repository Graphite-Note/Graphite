/**
 * File: CompactLinkLinesTests.swift
 * ---------------------------------
 * Layer: Tests
 * Description: Paragraphs that each hold one link to a note are drawn one per line, and nothing else changes.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 28/11/2026
 */

import XCTest
@testable import GraphiteCore

final class CompactLinkLinesTests: XCTestCase {
    func testLinkParagraphsBecomeOneLinePerLink() {
        XCTAssertEqual(CompactLinkLines.compacted("[[Lab 1]]\n\n[[Courses/Lab 2|Lab two]]\n\n\n[[Lab 3]]"),
                       "[[Lab 1]]  \n[[Courses/Lab 2|Lab two]]  \n[[Lab 3]]")
    }

    func testOtherParagraphsKeepTheirBlankLines() {
        let note = "Intro text.\n\n[[Lab 1]]\n\n[[Lab 2]]\n\nOutro with a [[link]] inside."
        XCTAssertEqual(CompactLinkLines.compacted(note), "Intro text.\n\n[[Lab 1]]  \n[[Lab 2]]\n\nOutro with a [[link]] inside.")
    }

    func testALoneLinkAndRunsWithCodeOrTasksAreLeftAlone() {
        XCTAssertEqual(CompactLinkLines.compacted("[[Only]]\n\nText"), "[[Only]]\n\nText")
        XCTAssertEqual(CompactLinkLines.compacted("[[A]]\n\n[[B]]\n\n- [ ] Task"), "[[A]]\n\n[[B]]\n\n- [ ] Task")
        XCTAssertEqual(CompactLinkLines.compacted("[[A]]\n\n```\n[[B]]\n```"), "[[A]]\n\n```\n[[B]]\n```")
        XCTAssertEqual(CompactLinkLines.compacted("![[A.png]]\n\n![[B.png]]"), "![[A.png]]\n\n![[B.png]]", "Embeds are pictures, not links.")
    }

    func testALinkLineHoldsOneWikilinkAndNothingElse() {
        XCTAssertTrue(CompactLinkLines.isLinkLine("  [[Note|Alias]] "))
        XCTAssertFalse(CompactLinkLines.isLinkLine("[[A]] and [[B]]"))
        XCTAssertFalse(CompactLinkLines.isLinkLine("See [[A]]"))
        XCTAssertFalse(CompactLinkLines.isLinkLine("[[]]"))
    }
}
