/**
 * File: FolderSearchTests.swift
 * -----------------------------
 * Layer: Tests
 * Description: The search's folder: through the index: folders found by name as results of their own, nested and
 *              accented names included, quoted names and patterns, notes narrowed to those inside a matching folder,
 *              and the file list the file tree's filter reads.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 11/11/2026
 */

import XCTest
@testable import GraphiteIndex
import GraphiteCore
import GraphiteTestSupport

final class FolderSearchTests: XCTestCase {
    private var index: VaultIndex!

    override func setUp() async throws {
        let directory = try TemporaryVault.make(prefix: "FolderSearch", for: self).root
        index = try VaultIndex(databaseURL: directory.appendingPathComponent("index.sqlite"))
        let notes: [(String, String)] = [
            ("Batikha-hour/Steak night.md", "We grilled steak."),
            ("Batikha-hour/Recipes/Marinade.md", "Steak marinade with garlic."),
            ("Batikha-hour/Guests.md", "Who comes."),
            ("Courses/Bâtiment/Plan.md", "Floor plan, no steak."),
            ("Courses/VLSI/Week 1.md", "Steak is not on the syllabus."),
            ("Other/Batikha.md", "A note named like the folder, with steak."),
        ]
        try await index.update(try notes.map { path, text in
            IndexedFile(path: try VaultPath(path), size: text.utf8.count, modified: Date(timeIntervalSince1970: 100), markdown: text)
        }, generation: "folders")
    }

    private func folders(_ query: String) async throws -> [String] {
        try await index.folderResults(for: query).map(\.path.rawValue)
    }

    private func notes(_ query: String) async throws -> [String] {
        try await index.search(query).results.map(\.path.rawValue).sorted()
    }

    func testFolderListsMatchingFoldersByNameNestedAndAccentedIncluded() async throws {
        let found = try await folders("folder:bati")
        XCTAssertEqual(found, ["Batikha-hour", "Courses/Bâtiment"], "Every folder whose name holds the text, by name; the note named Batikha is not a folder.")
        let results = try await index.folderResults(for: "folder:bati")
        XCTAssertTrue(results.allSatisfy { result in result.kind == .folder })
        XCTAssertEqual(results.first?.title, "Batikha-hour")
        let nested = try await folders("folder:recipes")
        XCTAssertEqual(nested, ["Batikha-hour/Recipes"])
        let quoted = try await folders("folder:\"Batikha-hour\"")
        XCTAssertEqual(quoted, ["Batikha-hour"])
        let pattern = try await folders("folder:/^(vlsi|recipes)$/")
        XCTAssertEqual(pattern, ["Batikha-hour/Recipes", "Courses/VLSI"])
        let withoutFolder = try await folders("steak")
        XCTAssertEqual(withoutFolder, [], "A search that names no folder lists none.")
    }

    func testFolderAloneFindsTheNotesInsideMatchingFolders() async throws {
        let found = try await notes("folder:bati")
        XCTAssertEqual(found, ["Batikha-hour/Guests.md", "Batikha-hour/Recipes/Marinade.md", "Batikha-hour/Steak night.md", "Courses/Bâtiment/Plan.md"])
    }

    func testFolderCombinedWithOtherTermsNarrowsNotesToThoseFolders() async throws {
        let found = try await notes("folder:bati steak")
        XCTAssertEqual(found, ["Batikha-hour/Recipes/Marinade.md", "Batikha-hour/Steak night.md", "Courses/Bâtiment/Plan.md"])
        let excluded = try await notes("steak -folder:bati")
        XCTAssertEqual(excluded, ["Courses/VLSI/Week 1.md", "Other/Batikha.md"])
        let byPattern = try await notes("folder:/^vlsi$/ steak")
        XCTAssertEqual(byPattern, ["Courses/VLSI/Week 1.md"])
        let caseSensitive = try await notes("match-case:folder:batikha")
        XCTAssertEqual(caseSensitive, [], "match-case: keeps the folder's capitals.")
    }

    func testFileEntriesListEveryIndexedFileWithoutReadingAny() async throws {
        let entries = try await index.fileEntries()
        XCTAssertEqual(entries.count, 6)
        XCTAssertTrue(entries.allSatisfy { entry in !entry.isDirectory && entry.modified == Date(timeIntervalSince1970: 100) })
        let nameIndex = FileTreeNameIndex(entries: entries, sortOrder: .alphabetical)
        let result = try XCTUnwrap(nameIndex.filter("bati"))
        XCTAssertTrue(result.isMatched(try VaultPath("Batikha-hour")), "Folders come from the files' paths.")
        XCTAssertTrue(result.isMatched(try VaultPath("Courses/Bâtiment")))
        XCTAssertTrue(result.isMatched(try VaultPath("Other/Batikha.md")))
    }
}
