/**
 * File: ReadingCoverTests.swift
 * -----------------------------
 * Layer: Tests
 * Description: The reading view finds a note's cover from its `banner` property only while covers are drawn, puts a
 *              linked note's emoji icon before the link's text only while icons are on, and builds a multi-column
 *              callout's paragraphs as blocks of their own.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

import XCTest
import SwiftUI
import GraphiteCore
import GraphiteIndex
@testable import GraphiteUI
import GraphiteTestSupport

@MainActor
final class ReadingCoverTests: XCTestCase {
    private var vault: URL!
    private var index: VaultIndex!

    override func setUp() async throws {
        vault = try TemporaryVault.make(prefix: "ReadingCover", for: self).root
        try FileManager.default.createDirectory(at: vault.appendingPathComponent("Covers"), withIntermediateDirectories: true)
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: vault.appendingPathComponent("Covers/Hills.png"))
        index = try VaultIndex(databaseURL: vault.appendingPathComponent(".index.sqlite"))
        try await index.update([
            IndexedFile(path: try VaultPath("Covers/Hills.png"), size: 4, modified: .now, markdown: nil),
            IndexedFile(path: try VaultPath("Lab.md"), size: 1, modified: .now, markdown: "---\nicon: 🧪\n---\n"),
        ], generation: "test")
    }

    private func build(_ source: String, configuration: ReadingConfiguration) async throws -> ReadingViewBuild {
        try await ReadingViewBuilder().build(source: source, note: try VaultPath("Course.md"), root: vault, index: index, configuration: configuration)
    }

    private func markdownRuns(_ blocks: [RenderedBlock]) -> [String] {
        blocks.compactMap { block in
            if case .markdown(_, let text) = block { text } else { nil }
        }
    }

    func testTheBannerIsFoundInTheVaultWhileCoversAreDrawn() async throws {
        let note = "---\nbanner: \"[[Hills.png]]\"\nbanner-y: 25\n---\n# Course"
        var configuration = ReadingConfiguration()
        configuration.drawsCover = true
        let drawn = try await build(note, configuration: configuration)
        XCTAssertEqual(drawn.cover, ReadingCover(picture: .vaultFile(path: try VaultPath("Covers/Hills.png"),
                                                                    location: try VaultPath("Covers/Hills.png").url(in: vault)), verticalFocus: 0.25))
        configuration.drawsCover = false
        let notDrawn = try await build(note, configuration: configuration)
        XCTAssertNil(notDrawn.cover, "Off, as on a phone by default: the note starts at its title.")
    }

    func testABannerThatNamesNoPictureOfTheVaultIsNoCover() async throws {
        var configuration = ReadingConfiguration()
        configuration.drawsCover = true
        let missing = try await build("---\nbanner: \"[[Missing.png]]\"\n---\n", configuration: configuration)
        XCTAssertNil(missing.cover)
        let note = try await build("---\nbanner: \"[[Lab]]\"\n---\n", configuration: configuration)
        XCTAssertNil(note.cover, "A note is not a picture.")
        let none = try await build("No frontmatter.", configuration: configuration)
        XCTAssertNil(none.cover)
    }

    func testALinkToANoteWithAnEmojiIconShowsItFirstWhileIconsAreOn() async throws {
        var configuration = ReadingConfiguration()
        let withoutIcons = try await build("See [[Lab]].", configuration: configuration)
        XCTAssertFalse(markdownRuns(withoutIcons.blocks).joined().contains("🧪"))
        configuration.noteIconLinkPrefixes = NoteIconLinkPrefixes(emojiByPath: [try VaultPath("Lab.md"): "🧪"], version: 1)
        let withIcons = try await build("See [[Lab]] and [[Lab|the lab]].", configuration: configuration)
        let text = markdownRuns(withIcons.blocks).joined()
        XCTAssertTrue(text.contains("[🧪 Lab]("), text)
        XCTAssertTrue(text.contains("[🧪 the lab]("), "An alias keeps the icon too: \(text)")
    }

    func testLinkPrefixesCompareByTheirVersion() throws {
        let path = try VaultPath("Lab.md")
        XCTAssertEqual(NoteIconLinkPrefixes(emojiByPath: [path: "🧪"], version: 3), NoteIconLinkPrefixes(emojiByPath: [:], version: 3),
                       "One version names one set of icons, so the reading configuration compares in constant time.")
        XCTAssertNotEqual(NoteIconLinkPrefixes(emojiByPath: [path: "🧪"], version: 3), NoteIconLinkPrefixes(emojiByPath: [path: "🧪"], version: 4))
        XCTAssertEqual(NoteIconLinkPrefixes(icons: [path: .emoji("🧪"), try VaultPath("B.md"): .symbol(systemName: "atom")], version: 1).emojiByPath,
                       [path: "🧪"], "A symbol cannot be written into a link's text.")
    }

    func testTurningCoversOrIconsOnBuildsTheNoteAgain() throws {
        let plain = ReadingConfiguration()
        var withCover = plain
        withCover.drawsCover = true
        XCTAssertNotEqual(plain.hashValueForReload, withCover.hashValueForReload)
        var withIcons = plain
        withIcons.noteIconLinkPrefixes = NoteIconLinkPrefixes(emojiByPath: [try VaultPath("Lab.md"): "🧪"], version: 2)
        XCTAssertNotEqual(plain.hashValueForReload, withIcons.hashValueForReload)
    }

    func testEachParagraphOfAMultiColumnCalloutIsABlockOfItsOwn() async throws {
        let build = try await build("> [!multi-column]\n> First column.\n>\n> - a list\n> - of two\n>\n> Third column.", configuration: ReadingConfiguration())
        guard case .callout(_, let type, _, _, let body) = try XCTUnwrap(build.blocks.first) else { return XCTFail("A callout") }
        XCTAssertEqual(type, "multi-column")
        XCTAssertEqual(body.count, 3, "\(body)")
        let other = try await self.build("> [!note]\n> First.\n>\n> Second.", configuration: ReadingConfiguration())
        guard case .callout(_, _, _, _, let noteBody) = try XCTUnwrap(other.blocks.first) else { return XCTFail("A callout") }
        XCTAssertEqual(noteBody.count, 1, "Other callouts keep their run of paragraphs whole.")
    }

    func testACalloutWithMetadataIsACallout() async throws {
        let build = try await build("> [!note|wide-2] Title\n> Body.", configuration: ReadingConfiguration())
        guard case .callout(_, let type, let title, _, _) = try XCTUnwrap(build.blocks.first) else { return XCTFail("A callout, as Obsidian reads it") }
        XCTAssertEqual(type, "note")
        XCTAssertEqual(title.trimmingCharacters(in: .whitespaces), "Title")
    }

    func testTheCatalogReadsTheIndexsIconsAndForgetsThemWithoutAnIndex() async throws {
        let catalog = NoteIconCatalog()
        await catalog.reload(from: index)
        XCTAssertEqual(catalog.icon(of: try VaultPath("Lab.md")), .emoji("🧪"))
        XCTAssertEqual(catalog.linkPrefixes.emojiByPath, [try VaultPath("Lab.md"): "🧪"])
        let version = catalog.linkPrefixes.version
        await catalog.reload(from: index)
        XCTAssertEqual(catalog.linkPrefixes.version, version, "The same icons change nothing, so nothing is drawn again.")
        await catalog.reload(from: nil)
        XCTAssertNil(catalog.icon(of: try VaultPath("Lab.md")))
    }

    func testTheIconChosenIsWrittenIntoTheNotesFrontmatterAndSaved() async throws {
        try Data("---\ncourse: EE330\n---\n# Lab\n".utf8).write(to: vault.appendingPathComponent("Lab notes.md"))
        let store = VaultStore(root: vault)
        let path = try VaultPath("Lab notes.md")
        let session = try MarkdownSession(path: path, snapshot: try await store.read(path), store: store, didSave: { _ in })
        try session.setIcon(.symbol(systemName: "flask"))
        XCTAssertEqual(session.text, "---\ncourse: EE330\nicon: LiFlaskConical\n---\n# Lab\n")
        try await session.save()
        XCTAssertEqual(try String(contentsOf: vault.appendingPathComponent("Lab notes.md"), encoding: .utf8), session.text)
        try session.setIcon(nil)
        XCTAssertEqual(session.text, "---\ncourse: EE330\n---\n# Lab\n")
    }

    func testTheCoverFoldsToAStripForTheNoteAndOpensAgain() throws {
        let store = CalloutFoldStore()
        let notePath = try VaultPath("Course.md")
        let cover = ReadingCover(picture: .webAddress(try XCTUnwrap(URL(string: "https://example.com/cover.jpg"))), verticalFocus: 0.5)
        func drawnHeight() throws -> CGFloat {
            let view = ReadingCoverView(cover: cover, notePath: notePath).environment(\.calloutFoldNote, (store, notePath.rawValue)).frame(width: 600)
            let renderer = ImageRenderer(content: view)
            return CGFloat(try XCTUnwrap(renderer.cgImage).height) / renderer.scale
        }
        XCTAssertEqual(try drawnHeight(), ReadingCoverView.expandedHeightPoints, "A cover starts open.")
        store.setExpanded(false, notePath: notePath.rawValue, key: ReadingCoverView.foldKey)
        XCTAssertEqual(try drawnHeight(), ReadingCoverView.collapsedHeightPoints, "Folded, it is a strip.")
        XCTAssertTrue(store.isExpanded(notePath: "Other.md", key: ReadingCoverView.foldKey, initially: true), "Only that note's cover folds.")
        store.setExpanded(true, notePath: notePath.rawValue, key: ReadingCoverView.foldKey)
        XCTAssertEqual(try drawnHeight(), ReadingCoverView.expandedHeightPoints)
    }
}
