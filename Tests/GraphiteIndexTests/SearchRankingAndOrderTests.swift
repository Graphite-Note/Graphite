/**
 * File: SearchRankingAndOrderTests.swift
 * --------------------------------------
 * Layer: Tests
 * Description: Notes lead attachments in search and Go to file, and results sorted by name sort numbers by value.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 01/11/2026
 */

import XCTest
import GraphiteCore
@testable import GraphiteIndex
import GraphiteTestSupport

final class SearchRankingAndOrderTests: XCTestCase {
    private var index: VaultIndex!

    override func setUp() async throws {
        let directory = try TemporaryVault.make(prefix: "SearchRanking", for: self).root
        index = try VaultIndex(databaseURL: directory.appendingPathComponent("index.sqlite"))
    }

    private func file(_ path: String, _ markdown: String? = "") throws -> IndexedFile {
        IndexedFile(path: try VaultPath(path), size: 1, modified: .now, markdown: markdown)
    }

    // MARK: Order by name

    func testNamesSortWithNumbersByValueAndAccentsBesideTheirLetters() async throws {
        try await index.update([
            try file("Note 10.md"), try file("Note 2.md"), try file("Zebra.md"), try file("Éclair.md"), try file("apple.md"), try file("Note 1.md"),
        ], generation: "test")

        let ascending = try await index.search("", sortOrder: .fileNameAscending, limit: 50).results.map(\.path.name)
        let descending = try await index.search("", sortOrder: .fileNameDescending, limit: 50).results.map(\.path.name)

        XCTAssertEqual(ascending, ["apple.md", "Éclair.md", "Note 1.md", "Note 2.md", "Note 10.md", "Zebra.md"])
        XCTAssertEqual(descending, ascending.reversed())
    }

    func testPagesOfANameSortedSearchFollowOneAnotherWithoutRepeats() async throws {
        try await index.update(try (1...120).map { number in try file("Lecture \(number).md", "word") }, generation: "test")

        var names: [String] = []
        var page = try await index.search("word", sortOrder: .fileNameAscending, limit: 50)
        names += page.results.map(\.path.name)
        while let continuation = page.continuation {
            page = try await index.search("word", sortOrder: .fileNameAscending, limit: 50, after: continuation)
            names += page.results.map(\.path.name)
        }

        XCTAssertEqual(names, (1...120).map { number in "Lecture \(number).md" })
    }

    func testTheSortKeyReadsNumbersByValue() {
        XCTAssertLessThan(VaultIndex.naturalSortKey("Lecture 2"), VaultIndex.naturalSortKey("Lecture 10"))
        XCTAssertEqual(VaultIndex.naturalSortKey("Note 007"), VaultIndex.naturalSortKey("Note 7"))
        XCTAssertLessThan(VaultIndex.naturalSortKey("éa"), VaultIndex.naturalSortKey("eb"))
    }

    // MARK: Notes before attachments

    func testGoToFileListsNotesBeforePicturesThatOnlyHoldTheLetters() async throws {
        try await index.update([
            try file("Figures/inverter 1.png", nil), try file("Figures/inverter 2.png", nil), try file("Figures/inverter 3.png", nil),
            try file("Figures/c a l l o u t.png", nil), try file("Callouts guide.md", "text"), try file("Inverter design.md", "text"),
        ], generation: "test")

        let inverter = try await index.quickSwitcherMatches(for: "inverter").map(\.path.rawValue)
        let callout = try await index.quickSwitcherMatches(for: "callout").map(\.path.rawValue)

        XCTAssertEqual(inverter.first, "Inverter design.md", "Four lines of pictures did not lead the note before.")
        XCTAssertEqual(Array(inverter.dropFirst()).sorted(), ["Figures/inverter 1.png", "Figures/inverter 2.png", "Figures/inverter 3.png"])
        XCTAssertEqual(callout.first, "Callouts guide.md")
    }

    func testSearchListsNotesWhoseNameHoldsTheWordsBeforeAttachments() async throws {
        try await index.update([
            try file("a/inverter 1.png", nil), try file("a/inverter 2.png", nil), try file("Inverter notes.md", "text"),
        ], generation: "test")

        let results = try await index.search("inverter").results.map(\.path.rawValue)

        XCTAssertEqual(results.first, "Inverter notes.md")
    }
}
