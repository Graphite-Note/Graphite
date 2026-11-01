/**
 * File: LinkResolutionLikeObsidianTests.swift
 * -------------------------------------------
 * Layer: Tests
 * Description: A link whose name several files share means one of them, the same one for every resolver,
 *              in the order of `getLinkpathDest` in Obsidian 1.14.5, against a real temporary vault.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 01/11/2026
 */

import XCTest
import GRDB
import GraphiteCore
@testable import GraphiteIndex
import GraphiteTestSupport

final class LinkResolutionLikeObsidianTests: XCTestCase {
    /// Each row: the vault's files, the note the link is in, the written link, and the file
    /// Obsidian opens, worked out from its `getLinkpathDest`.
    private struct Row {
        let files: [String]
        let source: String
        let target: String
        var isWiki = true
        let expected: String?
    }

    private let rows: [Row] = [
        // The hunt's case: another file of the name appears elsewhere.
        Row(files: ["Course/attachments/figure1.png", "Other/attachments/figure1.png"], source: "Course/Lecture.md", target: "figure1.png", expected: "Course/attachments/figure1.png"),
        Row(files: ["Course/attachments/figure1.png", "Other/attachments/figure1.png"], source: "Other/Lecture.md", target: "figure1.png", expected: "Other/attachments/figure1.png"),
        // A path from the root goes before one beside the note.
        Row(files: ["Note.md", "Course/Note.md"], source: "Course/Lecture.md", target: "Note", expected: "Note.md"),
        Row(files: ["Sub/Note.md", "Course/Sub/Note.md"], source: "Course/Lecture.md", target: "Sub/Note", expected: "Sub/Note.md"),
        // Beside the note goes before anywhere else.
        Row(files: ["A/Note.md", "Course/Note.md"], source: "Course/Lecture.md", target: "Note", expected: "Course/Note.md"),
        // Inside the note's folder goes before a shorter path elsewhere.
        Row(files: ["A/Note.md", "Course/Deep/Down/Note.md"], source: "Course/Lecture.md", target: "Note", expected: "Course/Deep/Down/Note.md"),
        // Nothing near: the shortest path.
        Row(files: ["Long/Folder/Note.md", "Short/Note.md"], source: "Course/Lecture.md", target: "Note", expected: "Short/Note.md"),
        // At the vault root every file counts as near, so the shortest path wins.
        Row(files: ["Long/Folder/Note.md", "Short/Note.md"], source: "Lecture.md", target: "Note", expected: "Short/Note.md"),
        // The note's folder is a plain prefix in Obsidian.
        Row(files: ["Course 2/Note.md", "A/Note.md"], source: "Course/Lecture.md", target: "Note", expected: "Course 2/Note.md"),
        // Partial paths choose among their matches in the same way.
        Row(files: ["X/covers/Book.png", "Course/Y/covers/Book.png"], source: "Course/Lecture.md", target: "covers/Book.png", expected: "Course/Y/covers/Book.png"),
        // A relative path means that file and no other.
        Row(files: ["Note.md", "Course/Note.md"], source: "Course/Lecture.md", target: "./Note", expected: "Course/Note.md"),
        Row(files: ["Note.md", "Course/Note.md"], source: "Course/Lecture.md", target: "../Note", expected: "Note.md"),
        Row(files: ["Other/Note.md"], source: "Course/Lecture.md", target: "./Note", expected: nil),
        // A path from the root means that path only.
        Row(files: ["Other/Sub/Note.md"], source: "Course/Lecture.md", target: "/Sub/Note", expected: nil),
        // Markdown links follow the same order, percent-decoded.
        Row(files: ["Note.md", "Course/Note.md"], source: "Course/Lecture.md", target: "Note.md", isWiki: false, expected: "Note.md"),
        Row(files: ["A/My Note.md", "Course/My Note.md"], source: "Course/Lecture.md", target: "My%20Note.md", isWiki: false, expected: "Course/My Note.md"),
        // Letter case does not matter.
        Row(files: ["A/NOTE.md", "Course/Sub/note.md"], source: "Course/Lecture.md", target: "Note", expected: "Course/Sub/note.md"),
    ]

    func testEveryResolverChoosesTheFileObsidianOpens() async throws {
        for row in rows {
            let (index, root) = try await makeVault(row.files + [row.source])
            let source = try VaultPath(row.source)
            let description = "[[\(row.target)]] from \(row.source) among \(row.files)"

            let sqlResolution = try await index.resolve(row.target, from: source, isWiki: row.isWiki).first?.rawValue
            XCTAssertEqual(sqlResolution, row.expected, "The index, for \(description)")

            let memoryResolution = try await index.databasePool.read { database in
                try GraphLinkResolver(database: database).resolve(row.target, from: source, isWiki: row.isWiki).first
            }
            XCTAssertEqual(memoryResolution, row.expected, "The graph's resolver, for \(description)")

            // The direct lookup on disk agrees when it finds something: it comes first everywhere.
            if let directFile = WikiLinkResolver.existingDirectFile(target: row.target, source: source, isWiki: row.isWiki, in: root) {
                XCTAssertEqual(directFile.rawValue, row.expected, "The direct lookup, for \(description)")
            }

            if let expected = row.expected {
                try Data((row.isWiki ? "[[\(row.target)]]" : "[link](\(row.target))").utf8).write(to: root.appendingPathComponent(row.source))
                try await index.refresh(paths: [source], root: root)
                let backlinks = try await index.backlinks(to: try VaultPath(expected))
                XCTAssertEqual(backlinks, [source], "Backlinks, for \(description)")
                for otherFile in row.files where otherFile != expected {
                    let otherBacklinks = try await index.backlinks(to: try VaultPath(otherFile))
                    XCTAssertEqual(otherBacklinks, [], "\(otherFile) gets no backlink, for \(description)")
                }
            }
        }
    }

    func testTheInMemoryProviderOfBasesAgrees() throws {
        for row in rows where row.target != "My%20Note.md" {
            let records = try (row.files + [row.source]).map { path in
                BaseFileRecord(path: try VaultPath(path), size: 0, createdDate: .distantPast, modifiedDate: .distantPast, properties: [], tags: [], links: [])
            }
            let provider = BaseInMemoryRecordProvider(records: records)
            let resolved = provider.resolveLinkTarget(row.target, from: try VaultPath(row.source), isWiki: row.isWiki)
            XCTAssertEqual(resolved?.rawValue, row.expected, "[[\(row.target)]] from \(row.source) among \(row.files)")
        }
    }

    /// More files of one name than the old limit of 50, with the closest last by path order.
    func testTheClosestOfManyFilesOfANameIsFound() async throws {
        var files = (0..<60).map { number in "A\(number)/Untitled.md" }
        files.append("Z/Untitled.md")
        let (index, _) = try await makeVault(files + ["Z/Lecture.md"])
        let resolution = try await index.resolve("Untitled", from: try VaultPath("Z/Lecture.md")).first
        XCTAssertEqual(resolution?.rawValue, "Z/Untitled.md")
    }

    /// A file's own name goes before another note's alias.
    func testAFileNameGoesBeforeAnotherNotesAlias() async throws {
        let (index, root) = try await makeVault(["Far/Away/Ann.md", "Course/Person.md", "Course/Lecture.md"])
        try Data("---\naliases: [Ann]\n---\n".utf8).write(to: root.appendingPathComponent("Course/Person.md"))
        try await index.refresh(paths: [try VaultPath("Course/Person.md")], root: root)
        let resolution = try await index.resolve("Ann", from: try VaultPath("Course/Lecture.md")).first
        XCTAssertEqual(resolution?.rawValue, "Far/Away/Ann.md")
        let onlyAlias = try await index.resolve("Person", from: try VaultPath("Course/Lecture.md")).first
        XCTAssertEqual(onlyAlias?.rawValue, "Course/Person.md")
    }

    /// The hunt's rename case: a link the name of two files reaches was neither rewritten
    /// nor reported, and then broke. Now it follows the file it means.
    func testRenamingTheFileASharedNameMeansRewritesTheLink() async throws {
        let (index, root) = try await makeVault(["Course/figure1.png", "Other/figure1.png", "Course/Lecture.md"])
        try Data("![[figure1.png]]".utf8).write(to: root.appendingPathComponent("Course/Lecture.md"))
        try await index.refresh(paths: [try VaultPath("Course/Lecture.md")], root: root)
        let operations = VaultFileOperations(store: VaultStore(root: root), index: index)
        let path = try VaultPath("Course/figure1.png")
        let destination = try VaultPath("Course/diagram.png")

        let plan = try await operations.linkUpdates(forMoving: path, to: destination)
        XCTAssertEqual(plan.changedLinkCount, 1)
        _ = try await operations.move(path, to: destination, applying: plan)
        XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("Course/Lecture.md"), encoding: .utf8), "![[diagram.png]]")
    }

    /// Moving the file away from a note that links it by a shared name keeps the link on it:
    /// the name alone would now mean the other file, so it gets a path.
    func testMovingTheFileAwayKeepsTheLinkOnItWithAPath() async throws {
        let (index, root) = try await makeVault(["Course/figure1.png", "Other/figure1.png", "Course/Lecture.md", "Elsewhere/Keep.md"])
        try Data("![[figure1.png]]".utf8).write(to: root.appendingPathComponent("Course/Lecture.md"))
        try await index.refresh(paths: [try VaultPath("Course/Lecture.md")], root: root)
        let operations = VaultFileOperations(store: VaultStore(root: root), index: index)
        let path = try VaultPath("Course/figure1.png")
        let destination = try VaultPath("Elsewhere/figure1.png")

        let plan = try await operations.linkUpdates(forMoving: path, to: destination)
        _ = try await operations.move(path, to: destination, applying: plan)
        XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("Course/Lecture.md"), encoding: .utf8), "![[Elsewhere/figure1.png]]")
    }

    private func makeVault(_ files: [String]) async throws -> (VaultIndex, URL) {
        let root = try TemporaryVault.make(prefix: "LinkVault", for: self).root.resolvingSymlinksInPath()
        for relativePath in Set(files) {
            let location = root.appendingPathComponent(relativePath)
            try FileManager.default.createDirectory(at: location.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data().write(to: location)
        }
        let indexFolder = try TemporaryVault.make(prefix: "LinkIndex", for: self).root
        let index = try VaultIndex(databaseURL: indexFolder.appendingPathComponent("index.sqlite"))
        _ = try await index.reconcile(root: root)
        return (index, root)
    }
}
