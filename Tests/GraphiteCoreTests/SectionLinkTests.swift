/**
 * File: SectionLinkTests.swift
 * ----------------------------
 * Layer: Tests
 * Description: Links to a note's sections kept on PDF pages: the section a drag starts in, the obsidian:// address
 *              written for other PDF readers, and that address read back.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 21/11/2026
 */

import XCTest
@testable import GraphiteCore

final class SectionLinkTests: XCTestCase {
    private let note = """
    ---
    tags: [physics]
    # not a heading: YAML
    ---
    # Entropy

    Entropy counts the states. ^counting

    A paragraph with no identifier.

    ## Second law

    - It never decreases.
    """

    private func location(of fragment: String) -> Int {
        (note as NSString).range(of: fragment).location
    }

    private var notePath: VaultPath { get throws { try VaultPath("Physics/Lecture 1.md") } }

    func testADragOnAHeadingLinksItsSection() throws {
        let result = SectionLink.link(startingAt: location(of: "Second law") + 3, in: note, notePath: try notePath)
        XCTAssertEqual(result.link, SectionLink(note: "Physics/Lecture 1", subpath: "Second law"))
        XCTAssertNil(result.identifierEdit)
        XCTAssertEqual(result.link.linkText, "Physics/Lecture 1#Second law")
        XCTAssertEqual(result.link.title, "Lecture 1 › Second law")
    }

    func testADragInABlockWithAnIdentifierLinksTheBlock() throws {
        let result = SectionLink.link(startingAt: location(of: "counts the states"), in: note, notePath: try notePath)
        XCTAssertEqual(result.link.subpath, "^counting")
        XCTAssertNil(result.identifierEdit)
        XCTAssertEqual(result.link.title, "Lecture 1", "A block is named by its note, as Obsidian names it.")
    }

    func testADragInABlockWithoutAnIdentifierGivesItOne() throws {
        let result = SectionLink.link(startingAt: location(of: "no identifier"), in: note, notePath: try notePath)
        let subpath = try XCTUnwrap(result.link.subpath)
        XCTAssertTrue(subpath.hasPrefix("^"))
        let edit = try XCTUnwrap(result.identifierEdit)
        let edited = (note as NSString).replacingCharacters(in: edit.range, with: edit.replacement)
        XCTAssertTrue(edited.contains("A paragraph with no identifier. " + subpath), edited)
        XCTAssertEqual(NoteBlocks.embeddedPart(of: edited, subpath: subpath), "A paragraph with no identifier.")
    }

    func testADragOnABlankLineLinksTheSectionAboveAndFrontmatterLinksTheNote() throws {
        let blankLineAfterSecondLaw = location(of: "## Second law") + "## Second law\n".utf16.count
        XCTAssertEqual(SectionLink.link(startingAt: blankLineAfterSecondLaw, in: note, notePath: try notePath).link.subpath, "Second law")
        XCTAssertNil(SectionLink.link(startingAt: location(of: "not a heading"), in: note, notePath: try notePath).link.subpath,
                     "A YAML comment in the frontmatter is not a heading, and the frontmatter links the whole note.")
    }

    func testTheAddressIsObsidiansAndReadsBack() throws {
        let link = SectionLink(note: "Physics/Lecture 1", subpath: "Second law & more")
        let url = try XCTUnwrap(link.openingURL(inVaultNamed: "Study Vault"))
        XCTAssertEqual(url.absoluteString, "obsidian://open?vault=Study%20Vault&file=Physics%2FLecture%201%23Second%20law%20%26%20more")
        XCTAssertEqual(SectionLink(openingURL: url), link)
        XCTAssertEqual(SectionLink.vaultName(ofOpeningURL: url), "Study Vault")
        let graphiteAddress = try XCTUnwrap(URL(string: "graphite://open?vault=V&file=Note.md"))
        XCTAssertEqual(SectionLink(openingURL: graphiteAddress), SectionLink(note: "Note", subpath: nil))
        XCTAssertNil(SectionLink(openingURL: try XCTUnwrap(URL(string: "https://example.com/Note"))))
    }
}
