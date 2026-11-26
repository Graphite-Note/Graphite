/**
 * File: NoteIconQueriesTests.swift
 * --------------------------------
 * Layer: Tests
 * Description: Every note's icon is read from the index in one query, in any capitals of the key, and a vault without
 *              icons reads none.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

import XCTest
@testable import GraphiteIndex
import GraphiteCore
import GraphiteTestSupport

final class NoteIconQueriesTests: XCTestCase {
    private func index(with notes: [(path: String, markdown: String)]) async throws -> VaultIndex {
        let directory = try TemporaryVault.make(prefix: "NoteIcons", for: self).root
        let index = try VaultIndex(databaseURL: directory.appendingPathComponent("index.sqlite"))
        try await index.update(try notes.map { note in
            IndexedFile(path: try VaultPath(note.path), size: 1, modified: .now, markdown: note.markdown)
        }, generation: "test")
        return index
    }

    func testTheIconsOfTheNotesThatHaveOneAreReadByPath() async throws {
        let index = try await index(with: [
            ("Physics/Mechanics.md", "---\nicon: 🧲\ntags: [physics]\n---\n# Mechanics"),
            ("Chemistry.md", "---\nIcon: LiFlaskConical\n---\n"),
            ("Electronics.md", "---\nicon: \"cpu\"\n---\n"),
            ("Plain.md", "---\ncourse: VLSI\n---\nNo icon."),
            ("Unknown pack.md", "---\nicon: FasBell\n---\n"),
            ("List.md", "---\nicon: [📚, 📐]\n---\n"),
        ])
        let icons = try await index.noteIcons()
        XCTAssertEqual(icons, [
            try VaultPath("Physics/Mechanics.md"): .emoji("🧲"),
            try VaultPath("Chemistry.md"): .symbol(systemName: "flask"),
            try VaultPath("Electronics.md"): .symbol(systemName: "cpu"),
        ], "A Font Awesome name and a list name no icon Graphite draws.")
    }

    func testAVaultWithoutIconsReadsNone() async throws {
        let index = try await index(with: [("One.md", "---\ncourse: VLSI\n---\n"), ("Two.md", "Text")])
        let icons = try await index.noteIcons()
        XCTAssertTrue(icons.isEmpty)
    }

    func testAnUnreadableRowNamesNoIcon() {
        let icons = VaultIndex.noteIcons(fromRows: [(path: "A.md", node: "not json"), (path: "B.md", node: #"{"scalar":{"text":"📚","isPlain":true}}"#)])
        XCTAssertEqual(icons.count, 1)
    }
}
