/**
 * File: FileTreeNameFilterTests.swift
 * -----------------------------------
 * Layer: Tests
 * Description: The file tree's filter by name and the search's folder: on their own: matching ignoring case and
 *              accents, nested folders, a folder and a file of one name, what the filtered tree shows, and how folder:
 *              parses and which folders it lists.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 11/11/2026
 */

import XCTest
@testable import GraphiteCore

final class FileTreeNameFilterTests: XCTestCase {
    private func file(_ path: String) throws -> VaultEntry {
        VaultEntry(path: try VaultPath(path), isDirectory: false, size: 1, modified: Date(timeIntervalSince1970: 0))
    }

    private func folder(_ path: String) throws -> VaultEntry {
        VaultEntry(path: try VaultPath(path), isDirectory: true, size: 0, modified: Date(timeIntervalSince1970: 0))
    }

    private func makeIndex(_ entries: [VaultEntry]) -> FileTreeNameIndex {
        FileTreeNameIndex(entries: entries, sortOrder: .alphabetical)
    }

    private func shownPaths(_ result: FileTreeNameFilterResult?, expandedFolders: Set<VaultPath>? = nil) -> [String] {
        guard let result else { return [] }
        return result.rows(expandedFolders: expandedFolders ?? result.foldersAboveMatches).map { row in
            String(repeating: "  ", count: row.depth) + row.entry.path.name
        }
    }

    func testNamesMatchIgnoringCaseAccentsAndWidth() throws {
        XCTAssertTrue(VaultNameMatching.name("Batikha-hour", contains: "bati"))
        XCTAssertTrue(VaultNameMatching.name("BATIKHA", contains: "tikh"))
        XCTAssertTrue(VaultNameMatching.name("Été 2026", contains: "ete"))
        XCTAssertTrue(VaultNameMatching.name("ete", contains: "ÉTÉ"))
        XCTAssertTrue(VaultNameMatching.name("Cafe\u{301}", contains: "café"), "A name stored decomposed matches the composed text typed.")
        XCTAssertTrue(VaultNameMatching.name("ＶＬＳＩ", contains: "vlsi"), "Full-width letters match their ASCII forms.")
        XCTAssertFalse(VaultNameMatching.name("Batikha", contains: "bata"))
        let name = "Lecture Été"
        let range = try XCTUnwrap(VaultNameMatching.matchedRange(of: "ete", in: name))
        XCTAssertEqual(String(name[range]), "Été", "The part highlighted is the name's own, accents included.")
    }

    func testAMatchShowsWithTheFoldersAboveItExpandedAndOthersLeftOut() throws {
        let index = makeIndex([
            try file("Courses/VLSI/Batikha notes.md"), try file("Courses/VLSI/Other.md"), try file("Courses/Signals/Week 1.md"),
            try file("Root note.md"),
        ])
        let result = try XCTUnwrap(index.filter("bati"))
        XCTAssertEqual(result.matchCount, 1)
        XCTAssertEqual(result.foldersAboveMatches, [try VaultPath("Courses"), try VaultPath("Courses/VLSI")])
        XCTAssertEqual(shownPaths(result), ["Courses", "  VLSI", "    Batikha notes.md"])
    }

    func testAMatchingFolderStaysCollapsedWithItsWholeContentOnceExpanded() throws {
        let index = makeIndex([
            try file("Batikha-hour/Recipes/Steak.md"), try file("Batikha-hour/Guests.md"), try file("Other/Lunch.md"),
        ])
        let result = try XCTUnwrap(index.filter("BATI"))
        XCTAssertEqual(result.foldersAboveMatches, [], "Nothing inside the folder matched, so it shows collapsed.")
        XCTAssertEqual(shownPaths(result), ["Batikha-hour"])
        let batikha = try VaultPath("Batikha-hour")
        XCTAssertEqual(shownPaths(result, expandedFolders: [batikha]), ["Batikha-hour", "  Recipes", "  Guests.md"],
                       "Expanded, the matching folder shows all it holds, folders first.")
        XCTAssertEqual(shownPaths(result, expandedFolders: [batikha, try VaultPath("Batikha-hour/Recipes")]),
                       ["Batikha-hour", "  Recipes", "    Steak.md", "  Guests.md"])
    }

    func testAFolderAndAFileOfOneNameBothMatch() throws {
        let index = makeIndex([try file("Thesis/Draft.md"), try file("Archive/Thesis.md"), try file("Archive/Old.md")])
        let result = try XCTUnwrap(index.filter("thesis"))
        XCTAssertEqual(result.matchCount, 2)
        XCTAssertTrue(result.isMatched(try VaultPath("Thesis")))
        XCTAssertTrue(result.isMatched(try VaultPath("Archive/Thesis.md")))
        XCTAssertFalse(result.isMatched(try VaultPath("Archive/Old.md")))
        XCTAssertEqual(shownPaths(result), ["Archive", "  Thesis.md", "Thesis"])
    }

    func testNestedMatchesInsideAMatchingFolderShowItExpandedWithEverything() throws {
        let index = makeIndex([try file("Lab/Lab report.md"), try file("Lab/Data.csv"), try file("Notes/Lab safety.md")])
        let result = try XCTUnwrap(index.filter("lab"))
        XCTAssertEqual(shownPaths(result), ["Lab", "  Data.csv", "  Lab report.md", "Notes", "  Lab safety.md"],
                       "A match inside opens the matching folder, which then shows all it holds.")
    }

    func testANotesExtensionIsNotMatchedButAnAttachmentsIs() throws {
        let index = makeIndex([try file("Week.md"), try file("Slides.pdf")])
        XCTAssertEqual(index.filter("md")?.matchCount, 0, "Every note ends in .md, which the tree does not show.")
        XCTAssertEqual(shownPaths(index.filter("pdf")), ["Slides.pdf"])
    }

    func testFoldersOnlyListedAndFoldersKnownFromPathsAreBothFound() throws {
        let index = makeIndex([try file("A/B/C/Deep.md"), try folder("Empty folder"), try file("A/B/C/Deep.md")])
        XCTAssertEqual(index.entryCount, 5, "A, B and C come from the file's path; the empty folder from a listing; the file once.")
        XCTAssertEqual(shownPaths(index.filter("empty")), ["Empty folder"])
        XCTAssertEqual(shownPaths(index.filter("c")), ["A", "  B", "    C"], "Folders are found by name too.")
    }

    func testHiddenPathsAndBlankTextAreLeftOut() throws {
        let index = makeIndex([try file(".obsidian/workspace.json"), try file("Visible.md")])
        XCTAssertEqual(index.entryCount, 1)
        XCTAssertNil(index.filter("   "))
        XCTAssertNil(index.filter(""))
        XCTAssertEqual(index.filter(" visible ")?.text, "visible")
    }

    func testTheTreesSortOrderIsKept() throws {
        let older = VaultEntry(path: try VaultPath("Notes/Alpha.md"), isDirectory: false, size: 1, modified: Date(timeIntervalSince1970: 10))
        let newer = VaultEntry(path: try VaultPath("Notes/Beta.md"), isDirectory: false, size: 1, modified: Date(timeIntervalSince1970: 20))
        let index = FileTreeNameIndex(entries: [older, newer], sortOrder: .byModifiedTime)
        XCTAssertEqual(shownPaths(index.filter("a")), ["Notes", "  Beta.md", "  Alpha.md"], "Newest first, as the tree sorts them.")
    }

    /// 30,000 files in 300 folders: building happens once, off the main thread; filtering happens at each keystroke
    /// and must take well under a frame. Measured on the Mac's debug build, which is slower than the app's.
    func testFilteringThirtyThousandNamesIsFastEnoughForAKeystroke() throws {
        let entries = try (0..<30_000).map { fileIndex in try file(String(format: "Course %03d/Lecture %05d.md", fileIndex % 300, fileIndex)) }
        let index = makeIndex(entries)
        XCTAssertEqual(index.entryCount, 30_300)
        let clock = ContinuousClock()
        var durations: [Duration] = []
        var result: FileTreeNameFilterResult?
        for query in ["lecture 0001", "course 01", "29999", "nothing like this"] {
            let elapsed = clock.measure { result = index.filter(query) }
            durations.append(elapsed)
            XCTAssertNotNil(result)
        }
        let slowest = durations.max() ?? .zero
        XCTAssertLessThan(slowest, .milliseconds(16), "Filtering 30,300 names took \(slowest) at its slowest: \(durations)")
        XCTAssertEqual(index.filter("lecture 29999")?.matchCount, 1)
    }

    // MARK: folder: in the search

    func testFolderParsesLikeTheOtherScopes() {
        XCTAssertEqual(SearchQueryParser.parse("folder:bati"), .scoped(.folder, .term(SearchTerm(text: "bati", kind: .word))))
        XCTAssertEqual(SearchQueryParser.parse("folder:\"Batikha hour\""), .scoped(.folder, .term(SearchTerm(text: "Batikha hour", kind: .phrase))))
        XCTAssertEqual(SearchQueryParser.parse("FOLDER:/^bat/"), .scoped(.folder, .term(SearchTerm(text: "^bat", kind: .regularExpression))))
        XCTAssertEqual(SearchQueryParser.parse("folder:bati steak"),
                       .all([.scoped(.folder, .term(SearchTerm(text: "bati", kind: .word))), .term(SearchTerm(text: "steak", kind: .word))]))
    }

    func testOnlyTheFolderPartOfASearchListsFolders() throws {
        let folders = [try VaultPath("Batikha-hour"), try VaultPath("Courses/Bâtiment"), try VaultPath("Courses"), try VaultPath("Other")]
        XCTAssertEqual(SearchFolderQuery.matchingFolders(of: "folder:bati steak", among: folders)?.map(\.rawValue), ["Batikha-hour", "Courses/Bâtiment"])
        XCTAssertEqual(SearchFolderQuery.matchingFolders(of: "folder:\"Batikha-hour\"", among: folders)?.map(\.rawValue), ["Batikha-hour"])
        XCTAssertEqual(SearchFolderQuery.matchingFolders(of: "folder:/^bat/", among: folders)?.map(\.rawValue), ["Batikha-hour"],
                       "A pattern reads the folder's own name, not its path.")
        XCTAssertEqual(SearchFolderQuery.matchingFolders(of: "folder:bati folder:hour", among: folders)?.map(\.rawValue), ["Batikha-hour"])
        XCTAssertEqual(SearchFolderQuery.matchingFolders(of: "folder:other OR folder:courses", among: folders)?.map(\.rawValue), ["Courses", "Other"])
        XCTAssertNil(SearchFolderQuery.matchingFolders(of: "steak", among: folders), "A search without folder: lists no folder.")
        XCTAssertNil(SearchFolderQuery.matchingFolders(of: "-folder:bati", among: folders), "An excluded folder lists nothing.")
        XCTAssertEqual(SearchFolderQuery.folders(holding: [try VaultPath("A/B/Note.md"), try VaultPath("A/Other.md"), try VaultPath("Root.md")])
            .map(\.rawValue).sorted(), ["A", "A/B"])
    }

    func testFolderNarrowsNotesToThoseInsideAMatchingFolderAtAnyDepth() throws {
        var matcher = SearchMatcher(expression: try XCTUnwrap(SearchQueryParser.parse("folder:bati")))
        func note(_ path: String) throws -> SearchableFile { SearchableFile(path: try VaultPath(path), content: "steak", tags: [], properties: []) }
        XCTAssertTrue(matcher.matches(try note("Batikha-hour/Recipes/Steak.md")))
        XCTAssertTrue(matcher.matches(try note("Bâtiment/Plan.md")), "Accents are ignored, as in the file tree's filter.")
        XCTAssertFalse(matcher.matches(try note("Other/Batikha.md")), "The note's own name is not a folder.")
        var caseMatcher = SearchMatcher(expression: try XCTUnwrap(SearchQueryParser.parse("match-case:folder:Bati")))
        XCTAssertTrue(caseMatcher.matches(try note("Batikha/Note.md")))
        XCTAssertFalse(caseMatcher.matches(try note("batikha/Note.md")))
    }
}
