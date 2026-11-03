/**
 * File: GraphFilterOperatorsTests.swift
 * -------------------------------------
 * Layer: Tests
 * Description: The graph's filter field reads minus, file: and OR as Obsidian's search does, so it does not list nothing.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 01/11/2026
 */

import XCTest
@testable import GraphiteCore

final class GraphFilterOperatorsTests: XCTestCase {
    private func matches(_ filter: String, path: String, tags: [String] = []) -> Bool {
        GraphSearch(filter).matches(path: path, tags: tags)
    }

    func testAMinusLeavesOutTheFilesThatMatch() {
        XCTAssertFalse(matches("-archive", path: "Archive/old.md"))
        XCTAssertTrue(matches("-archive", path: "Notes/lecture.md"))
        XCTAssertTrue(matches("lecture -archive", path: "Notes/lecture.md"))
        XCTAssertFalse(matches("lecture -archive", path: "Archive/lecture.md"))
        XCTAssertFalse(matches("-tag:#draft", path: "a.md", tags: ["#draft"]))
        XCTAssertTrue(matches("-tag:#draft", path: "a.md", tags: ["#final"]))
        XCTAssertFalse(matches("-path:Archive", path: "Archive/x.md"))
    }

    func testFileMatchesTheNameAndNotTheFolders() {
        XCTAssertTrue(matches("file:lecture", path: "Notes/lecture.md"))
        XCTAssertFalse(matches("file:notes", path: "Notes/lecture.md"), "Notes is a folder.")
        XCTAssertTrue(matches("path:notes", path: "Notes/lecture.md"))
    }

    func testORKeepsAFileThatMatchesEitherSide() {
        XCTAssertTrue(matches("lecture OR exam", path: "Notes/lecture.md"))
        XCTAssertTrue(matches("lecture OR exam", path: "Notes/exam.md"))
        XCTAssertFalse(matches("lecture OR exam", path: "Notes/other.md"))
        XCTAssertTrue(matches("tag:#a OR tag:#b", path: "x.md", tags: ["#b"]))
        XCTAssertTrue(matches("notes lecture OR exam", path: "Notes/lecture.md"), "Words before OR belong to its left side.")
        XCTAssertFalse(matches("notes lecture OR exam", path: "Other/lecture.md"))
    }

    func testAFilterOfNothingButOperatorsKeepsEveryFile() {
        XCTAssertTrue(matches("OR", path: "x.md"))
        XCTAssertTrue(matches("tag:", path: "x.md"))
        XCTAssertTrue(GraphSearch("OR").isEmpty)
    }

    func testTheGraphFiltersByThemInsteadOfShowingNoMatches() throws {
        let notes = try ["Notes/lecture.md", "Archive/lecture.md", "Notes/exam.md"].map { text in try XCTUnwrap(try? VaultPath(text)) }
        let graph = LinkGraph.build(files: notes, links: [], unresolvedLinks: [], tags: [])

        XCTAssertEqual(graph.filtered(by: GraphFilterOptions(searchText: "lecture -archive")).nodes.map(\.id), ["Notes/lecture.md"])
        XCTAssertEqual(graph.filtered(by: GraphFilterOptions(searchText: "file:exam OR file:lecture")).nodes.map(\.id).sorted(),
                       ["Archive/lecture.md", "Notes/exam.md", "Notes/lecture.md"])
    }
}
