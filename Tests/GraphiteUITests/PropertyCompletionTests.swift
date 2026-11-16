/**
 * File: PropertyCompletionTests.swift
 * -----------------------------------
 * Layer: Tests
 * Description: Suggestions while a note's frontmatter is typed: the vault's property names with their types, a
 *              property's values, the vault's tags under `tags`, the note's own left out, and the text a choice writes.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 16/11/2026
 */

import XCTest
import GraphiteCore
import GraphiteTestSupport
@testable import GraphiteUI

/// `Docs/Property-and-tag-completion-todo.md`, section 2, through the editor's own suggestion provider.
@MainActor
final class PropertyCompletionTests: XCTestCase {
    private let testBed = WorkspaceModelTestBed()

    override func tearDown() async throws {
        testBed.tearDown()
    }

    private static let vault = [
        "Lectures/VLSI 1.md": "---\ncourse: VLSI 3\ndue: 2026-10-01\ntags: [eth/vlsi, exam]\n---\nText.",
        "Lectures/VLSI 2.md": "---\ncourse: VLSI 3\ntags:\n  - eth/vlsi\n---\nText.",
        "Lectures/Arch 1.md": "---\ncourse: Computer Architecture\ntags: [eth/comparch, exam]\n---\nText.",
    ]

    /// The suggestions and, for the first, the note's text after choosing it, with the cursor where `|` is in `marked`.
    private func suggestions(typing marked: String) async throws -> (titles: [String], subtitles: [String?], symbols: [String], textAfterFirst: String?) {
        let cursor = (marked as NSString).range(of: "|").location
        let text = (marked as NSString).replacingCharacters(in: NSRange(location: cursor, length: 1), with: "")
        var files = Self.vault
        files["Editing.md"] = text
        let (workspace, _) = try await testBed.openedWorkspace(files: files)
        try await waitUntil("the vault is indexed", timeoutSeconds: 20) { workspace.hasCompletedIndexScan }
        try await testBed.open("Editing.md", in: workspace)
        let session = try XCTUnwrap(workspace.markdownSession)
        let context = try XCTUnwrap(LinkCompletion.context(in: text as NSString, cursor: cursor))
        let items = await CompletionProvider(workspace: workspace, session: session).items(for: context)
        var textAfterFirst: String?
        if let first = items.first {
            let edits = try await first.makeEdits(context)
            textAfterFirst = edits.reduce(text) { written, edit in (written as NSString).replacingCharacters(in: edit.range, with: edit.replacement) }
        }
        return (items.map(\.title), items.map(\.subtitle), items.map(\.systemImage), textAfterFirst)
    }

    func testANewNameSuggestsTheVaultsNamesWithTheirTypesAndWritesTheKey() async throws {
        let found = try await suggestions(typing: "---\ntags: [x]\ncou|\n---\nBody")
        XCTAssertEqual(found.titles, ["course"], "`tags` is the note's own; `due` does not contain the letters typed.")
        XCTAssertEqual(found.subtitles, ["3 notes"])
        XCTAssertEqual(found.textAfterFirst, "---\ntags: [x]\ncourse: \n---\nBody")
        let dates = try await suggestions(typing: "---\ndu|\n---\n")
        XCTAssertEqual(dates.symbols, ["calendar"], "A date property shows the date type's icon.")
    }

    func testAValueSuggestsWhatThatPropertyTakesMostUsedFirst() async throws {
        let found = try await suggestions(typing: "---\ncourse: |\n---\n")
        XCTAssertEqual(found.titles, ["VLSI 3", "Computer Architecture"])
        XCTAssertEqual(found.textAfterFirst, "---\ncourse: VLSI 3\n---\n")
    }

    func testATagsItemSuggestsTheVaultsTagsAndSkipsOnesTheNoteHas() async throws {
        let found = try await suggestions(typing: "---\ntags:\n  - exam\n  - eth|\n---\n")
        XCTAssertEqual(found.titles, ["eth/vlsi", "eth/comparch"], "Without `#`, most used first, and not `exam`, which the note lists.")
        XCTAssertEqual(found.textAfterFirst, "---\ntags:\n  - exam\n  - eth/vlsi\n---\n")
        let inline = try await suggestions(typing: "---\ntags: [eth/vlsi, e|]\n---\n")
        XCTAssertEqual(inline.titles, ["exam", "eth/comparch"])
        XCTAssertEqual(inline.textAfterFirst, "---\ntags: [eth/vlsi, exam]\n---\n")
    }

    // MARK: Section 1: `[[` in the Properties panel's fields

    func testALinkTypedInAValueIsFoundAndClosedWhenANoteIsChosen() {
        XCTAssertNil(PropertyLinkTyping.openLink(in: "VLSI 3"))
        XCTAssertNil(PropertyLinkTyping.openLink(in: "[[Done]]"))
        let link = PropertyLinkTyping.openLink(in: "see [[Lec")
        XCTAssertEqual(link?.prefix, "see ")
        XCTAssertEqual(link?.query, "Lec")
        XCTAssertEqual(PropertyLinkTyping.completed(prefix: "", target: "Lectures/VLSI 1"), "[[Lectures/VLSI 1]]")
    }

    func testTheNotesALinkCanNameAreFoundWithTheirTargets() async throws {
        var files = Self.vault
        files["Editing.md"] = "---\nrelated:\n---\n"
        let (workspace, _) = try await testBed.openedWorkspace(files: files)
        try await waitUntil("the vault is indexed", timeoutSeconds: 20) { workspace.hasCompletedIndexScan }
        let notes = await workspace.propertySuggestions(linkingFrom: try VaultPath("Editing.md")).notes(matching: "Arch")
        XCTAssertEqual(notes.map(\.text), ["Arch 1"], "The vault's shortest link format names the note alone.")
        XCTAssertEqual(notes.map(\.shownTitle), ["Arch 1"])
    }
}
