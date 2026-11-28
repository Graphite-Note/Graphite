/**
 * File: ReadingCoverTests.swift
 * -----------------------------
 * Layer: Tests
 * Description: The reading view finds a note's cover from its `banner` property only while covers are drawn, puts a
 *              linked note's emoji icon before the link's text only while icons are on, and builds a multi-column
 *              callout's paragraphs as blocks of their own.
 *
 * Authors: Bahey Shalash
 * Version: 0.5
 * Date: 28/11/2026
 */

import XCTest
import SwiftUI
@testable import Textual
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

    /// How an emoji icon is written before a link: a square picture whose description is the emoji, then a space.
    private static func emojiIcon(_ emoji: String) -> String {
        let address = NoteIconInlineAddress.url(of: .emoji(emoji), root: URL(fileURLWithPath: "/"), textSize: ReadingConfiguration().textSize)
        return "![\(emoji)](\(address.map(GraphiteOpenLink.markdownDestination) ?? "")) "
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
        XCTAssertEqual(drawn.pageLook.cover, ReadingCover(picture: .vaultFile(path: try VaultPath("Covers/Hills.png"),
                                                                    location: try VaultPath("Covers/Hills.png").url(in: vault)), verticalFocus: 0.25))
        configuration.drawsCover = false
        let notDrawn = try await build(note, configuration: configuration)
        XCTAssertNil(notDrawn.pageLook.cover, "Off, as on a phone by default: the note starts at its title.")
    }

    func testABannerThatNamesNoPictureOfTheVaultIsNoCover() async throws {
        var configuration = ReadingConfiguration()
        configuration.drawsCover = true
        let missing = try await build("---\nbanner: \"[[Missing.png]]\"\n---\n", configuration: configuration)
        XCTAssertNil(missing.pageLook.cover)
        let note = try await build("---\nbanner: \"[[Lab]]\"\n---\n", configuration: configuration)
        XCTAssertNil(note.pageLook.cover, "A note is not a picture.")
        let none = try await build("No frontmatter.", configuration: configuration)
        XCTAssertNil(none.pageLook.cover)
    }

    func testALinkToANoteWithAnEmojiIconShowsItFirstWhileIconsAreOn() async throws {
        var configuration = ReadingConfiguration()
        let withoutIcons = try await build("See [[Lab]].", configuration: configuration)
        XCTAssertFalse(markdownRuns(withoutIcons.blocks).joined().contains("🧪"))
        configuration.noteIconLinkPrefixes = NoteIconLinkPrefixes(iconsByPath: [try VaultPath("Lab.md"): .emoji("🧪")], root: vault, version: 1)
        let withIcons = try await build("See [[Lab]] and [[Lab|the lab]].", configuration: configuration)
        let text = markdownRuns(withIcons.blocks).joined()
        XCTAssertTrue(text.contains(Self.emojiIcon("🧪") + "[Lab]("), "The icon stands before the link, outside its text: \(text)")
        XCTAssertTrue(text.contains(Self.emojiIcon("🧪") + "[the lab]("), "An alias keeps the icon too: \(text)")
    }

    func testALinkToANoteWithAPictureOrSymbolIconShowsItAsASmallPicture() async throws {
        var configuration = ReadingConfiguration()
        let notion = try XCTUnwrap(URL(string: "https://example.com/icons/clock_gray.svg"))
        configuration.noteIconLinkPrefixes = NoteIconLinkPrefixes(iconsByPath: [
            try VaultPath("Lab.md"): .picture(.vaultFile(linkTarget: "Covers/Hills.png")),
            try VaultPath("Covers/Hills.png"): .picture(.webAddress(notion)),
        ], root: vault, version: 1)
        let pictureLink = markdownRuns(try await build("See [[Lab]].", configuration: configuration).blocks).joined()
        XCTAssertTrue(pictureLink.contains("![](graphite-note-icon://vault?address="), pictureLink)
        XCTAssertTrue(pictureLink.contains("Hills.png#"), "The vault's picture, sized to the text: \(pictureLink)")
        configuration.noteIconLinkPrefixes = NoteIconLinkPrefixes(iconsByPath: [try VaultPath("Lab.md"): .symbol(systemName: "atom")], root: vault, version: 2)
        let symbolLink = markdownRuns(try await build("See [[Lab]].", configuration: configuration).blocks).joined()
        XCTAssertTrue(symbolLink.contains("![](graphite-note-icon://symbol/atom"), symbolLink)
        let webAddress = try XCTUnwrap(NoteIconInlineAddress.url(of: .picture(.webAddress(notion)), root: vault, textSize: 17))
        XCTAssertEqual(NoteIconInlineAddress.named(by: webAddress), .webAddress(notion))
        XCTAssertEqual(NoteIconInlineAddress.named(by: try XCTUnwrap(URL(string: symbolLink.components(separatedBy: "![](")[1].components(separatedBy: ")")[0]))),
                       .symbol("atom"))
    }

    func testLinkPrefixesCompareByTheirVersion() throws {
        let path = try VaultPath("Lab.md")
        XCTAssertEqual(NoteIconLinkPrefixes(iconsByPath: [path: .emoji("🧪")], root: nil, version: 3), NoteIconLinkPrefixes(iconsByPath: [:], root: nil, version: 3),
                       "One version names one set of icons, so the reading configuration compares in constant time.")
        XCTAssertNotEqual(NoteIconLinkPrefixes(iconsByPath: [path: .emoji("🧪")], root: nil, version: 3),
                          NoteIconLinkPrefixes(iconsByPath: [path: .emoji("🧪")], root: nil, version: 4))
    }

    func testTurningCoversOrIconsOnBuildsTheNoteAgain() throws {
        let plain = ReadingConfiguration()
        var withCover = plain
        withCover.drawsCover = true
        XCTAssertNotEqual(plain.hashValueForReload, withCover.hashValueForReload)
        var withIcons = plain
        withIcons.noteIconLinkPrefixes = NoteIconLinkPrefixes(iconsByPath: [try VaultPath("Lab.md"): .emoji("🧪")], root: nil, version: 2)
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
        XCTAssertEqual(catalog.linkPrefixes.iconsByPath, [try VaultPath("Lab.md"): .emoji("🧪")])
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
        let openHeight = try drawnHeight()
        XCTAssertGreaterThanOrEqual(openHeight, ReadingCoverView.smallestExpandedHeightPoints, "A cover starts open.")
        store.setExpanded(false, notePath: notePath.rawValue, key: ReadingCoverView.foldKey)
        XCTAssertEqual(try drawnHeight(), ReadingCoverView.collapsedHeightPoints, "Folded, it is a strip.")
        XCTAssertTrue(store.isExpanded(notePath: "Other.md", key: ReadingCoverView.foldKey, initially: true), "Only that note's cover folds.")
        store.setExpanded(true, notePath: notePath.rawValue, key: ReadingCoverView.foldKey)
        XCTAssertEqual(try drawnHeight(), openHeight)
    }

    func testTheCoverTakesNotionsThirtyPercentOfTheViewBetweenItsBounds() {
        XCTAssertEqual(ReadingCoverView.expandedHeight(forViewHeight: 768), 230.4, accuracy: 0.01, "Notion's 230 of 768 points.")
        XCTAssertEqual(ReadingCoverView.expandedHeight(forViewHeight: 300), ReadingCoverView.smallestExpandedHeightPoints)
        XCTAssertEqual(ReadingCoverView.expandedHeight(forViewHeight: 1_400), ReadingCoverView.largestExpandedHeightPoints)
    }

    func testThePageLookFindsTheNotesIconAndResolvesAPictureOfTheVault() async throws {
        var configuration = ReadingConfiguration()
        configuration.drawsPageLook = true
        let emoji = try await build("---\nicon: 📚\n---\n# Course", configuration: configuration)
        XCTAssertEqual(emoji.pageLook.icon, .emoji("📚"))
        XCTAssertNil(emoji.pageLook.cover, "Covers are drawn only where drawsCover says.")
        let picture = try await build("---\nicon: \"[[Hills.png]]\"\n---\n", configuration: configuration)
        XCTAssertEqual(picture.pageLook.icon, .picture(.vaultFile(linkTarget: "Covers/Hills.png")))
        let missing = try await build("---\nicon: \"[[Gone.png]]\"\n---\n", configuration: configuration)
        XCTAssertNil(missing.pageLook.icon)
        configuration.drawsPageLook = false
        let off = try await build("---\nicon: 📚\n---\n", configuration: configuration)
        XCTAssertNil(off.pageLook.icon)
    }

    func testLinkLinesAreDrawnOnePerLineOnlyWhileThePluginIsOn() async throws {
        var configuration = ReadingConfiguration()
        let note = "[[Lab]]\n\n[[Course]]"
        let apartRuns = markdownRuns(try await build(note, configuration: configuration).blocks)
        XCTAssertEqual(apartRuns.count, 1)
        let apart = apartRuns.joined()
        configuration.drawsPageLook = true
        let together = markdownRuns(try await build(note, configuration: configuration).blocks).joined()
        XCTAssertTrue(apart.contains("\n\n["), "Two paragraphs: \(apart.debugDescription)")
        XCTAssertFalse(together.contains("\n\n["), "One line each: \(together.debugDescription)")
    }

    func testUnevenColumnsKeepTheirWeightsForTheReadingView() async throws {
        let note = "> [!multi-column]\n> > [!blank|wide-2]\n> > ## Lectures\n> > [[Lab]]\n>\n> > [!blank]\n> > ## Labs"
        let build = try await build(note, configuration: ReadingConfiguration())
        XCTAssertEqual(Array(build.foldKeys.columnWeightsByBlock.values), [[2, 1]])
        let even = try await self.build("> [!multi-column]\n> > [!blank]\n> > A\n>\n> > [!blank]\n> > B", configuration: ReadingConfiguration())
        XCTAssertTrue(even.foldKeys.columnWeightsByBlock.isEmpty, "Even columns need no weights.")
    }

    /// The Notion importer writes a page's list of links as one paragraph, each link ending in a hard line break.
    func testALinkListWithHardBreaksKeepsItsLinesAndAnIconBeforeEachLink() async throws {
        var configuration = ReadingConfiguration()
        configuration.drawsPageLook = true
        configuration.noteIconLinkPrefixes = NoteIconLinkPrefixes(iconsByPath: [try VaultPath("Lab.md"): .emoji("🧪")], root: vault, version: 1)
        let text = markdownRuns(try await build("[[Lab]]  \n[[Lab|Second lab]]  \n[[Course]]  \n", configuration: configuration).blocks).joined()
        XCTAssertTrue(text.contains(Self.emojiIcon("🧪") + "[Lab]("), text)
        XCTAssertTrue(text.contains(Self.emojiIcon("🧪") + "[Second lab]("), text)
        XCTAssertEqual(text.components(separatedBy: "  \n").count, 4, "Three lines, each ending in its hard break: \(text.debugDescription)")
        XCTAssertFalse(text.contains("\n\n"), text.debugDescription)
    }

    /// Spans in a heading, a link line and a table cell reach the renderer as colour markers, never as their tags.
    func testSpansInHeadingsLinkLinesAndTableCellsBecomeColours() async throws {
        let note = """
            ## <span style="color:#e05a52">Admin</span>

            [[Lab]] <span style="color:#d9730d">due Monday</span>  
            [[Course]]

            | Week | Topic |
            | --- | --- |
            | 1 | <span style="background-color:#fbf3db">Intro</span> |
            """
        let build = try await build(note, configuration: ReadingConfiguration())
        // What is drawn: the heading's text and the other blocks. Its anchor keeps the heading as written, as Obsidian's
        // heading links name it.
        let drawn = build.blocks.map { block in
            if case .heading(_, _, let text, _) = block { text } else { String(describing: block) }
        }.joined(separator: "\n")
        XCTAssertFalse(drawn.lowercased().contains("<span"), drawn)
        XCTAssertTrue(drawn.contains(String(ReadingMarkers.colorStartMarker) + "#e05a52"), drawn)
        XCTAssertTrue(drawn.contains(String(ReadingMarkers.colorStartMarker) + "#d9730d"), drawn)
        XCTAssertTrue(drawn.contains(String(ReadingMarkers.backgroundStartMarker) + "#fbf3db"), drawn)
    }

    func testAReloadAskedForDuringARunningReadIsAnsweredAfterItInsteadOfCancellingIt() async throws {
        let catalog = NoteIconCatalog()
        let later = FixedIconLookup(icons: [try VaultPath("Lab.md"): .emoji("🔧")])
        let first = FixedIconLookup(icons: [try VaultPath("Lab.md"): .emoji("🧪")]) {
            await MainActor.run { catalog.requestReload(from: later, root: nil) }
        }
        catalog.requestReload(from: first, root: nil)
        await catalog.finishReloading()
        XCTAssertEqual(catalog.icon(of: try VaultPath("Lab.md")), .emoji("🔧"), "The request made during the first read is read after it.")
        let firstReads = await first.readCount, laterReads = await later.readCount
        XCTAssertEqual(firstReads, 1)
        XCTAssertEqual(laterReads, 1)
        catalog.requestReload(from: first, root: nil)
        catalog.requestReload(from: later, root: nil)
        await catalog.finishReloading()
        let firstReadsAfter = await first.readCount
        XCTAssertEqual(firstReadsAfter, 1, "Two requests before a read starts make one read, of the newer source.")
    }

    func testTheReadingViewLeavesTheCoversAndIconsRowsToThePagesHeader() async throws {
        var configuration = ReadingConfiguration()
        let note = "---\nbanner: \"[[Covers/Hills.png]]\"\nbanner_y: 0.3\nicon: 🧪\ncourse: EE330\n---\nText"
        guard case .properties(let shown, let hiddenWithoutLook)? = try await build(note, configuration: configuration).blocks.first else {
            return XCTFail("No properties")
        }
        XCTAssertTrue(hiddenWithoutLook.isEmpty, "Without the plugin every row shows.")
        configuration.drawsCover = true
        configuration.drawsPageLook = true
        guard case .properties(let properties, let hidden)? = try await build(note, configuration: configuration).blocks.first else {
            return XCTFail("No properties")
        }
        XCTAssertEqual(properties.map(\.key), shown.map(\.key), "Every property stays in the panel's edits.")
        XCTAssertEqual(hidden, ["banner", "banner_y", "banner-y", "icon"])
        let onlyACover = try await build("---\nbanner: \"[[Covers/Hills.png]]\"\n---\nText", configuration: configuration)
        if case .properties? = onlyACover.blocks.first { XCTFail("A note whose only property is its cover shows no Properties panel.") }
        let missingPicture = try await build("---\nbanner: \"[[Nowhere.png]]\"\n---\nText", configuration: configuration)
        guard case .properties(_, let keptRows)? = missingPicture.blocks.first else { return XCTFail("A cover not drawn keeps its row.") }
        XCTAssertTrue(keptRows.isEmpty)
    }

    func testLinksWithoutAnIconInAListOfIconLinksGetAPageGlyphAndProseLinksDoNot() async throws {
        var configuration = ReadingConfiguration()
        configuration.drawsPageLook = true
        configuration.noteIconLinkPrefixes = NoteIconLinkPrefixes(iconsByPath: [try VaultPath("Lab.md"): .emoji("🧪")], root: vault, version: 1)
        let glyph = "graphite-note-icon://symbol/doc.text"
        let list = markdownRuns(try await build("[[Lab]]  \n[[Course]]  \n[[Missing]]", configuration: configuration).blocks).joined()
        XCTAssertTrue(list.contains(Self.emojiIcon("🧪") + "[Lab]("), list)
        XCTAssertEqual(list.components(separatedBy: glyph).count - 1, 2, "Each link without an icon gets the page: \(list)")
        let paragraphs = markdownRuns(try await build("[[Lab]]\n\n[[Course]]", configuration: configuration).blocks).joined()
        XCTAssertTrue(paragraphs.contains(glyph), "Paragraphs drawn as one list get it too: \(paragraphs)")
        let prose = markdownRuns(try await build("See [[Lab]] and [[Course]].\n\n[[Course]]  \n[[Missing]]", configuration: configuration).blocks).joined()
        XCTAssertFalse(prose.contains(glyph), "Prose, and a list with no icon, stay as written: \(prose)")
        configuration.noteIconLinkPrefixes = .none
        let noIcons = markdownRuns(try await build("[[Lab]]  \n[[Course]]", configuration: configuration).blocks).joined()
        XCTAssertFalse(noIcons.contains(glyph))
    }

    func testEveryIconBeforeALinkIsASquareOfTheSameSizeOnTheSameBaseline() throws {
        let side = NoteIconPictures.pixelDimension
        let emoji = try NoteIconSquarePicture.emoji("🏢", pixelDimension: side)
        XCTAssertEqual([emoji.width, emoji.height], [side, side])
        let wide = try XCTUnwrap(CGContext(data: nil, width: 400, height: 100, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                           bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.makeImage())
        let squared = try NoteIconSquarePicture.squared(wide, pixelDimension: side)
        XCTAssertEqual([squared.width, squared.height], [side, side], "A wide logo is fitted into the square.")
        for icon in [NoteIcon.emoji("🏢"), .symbol(systemName: "doc.text"), .picture(.vaultFile(linkTarget: "Covers/Hills.png")),
                     .picture(.webAddress(try XCTUnwrap(URL(string: "https://example.com/i.svg"))))] {
            let address = try XCTUnwrap(NoteIconInlineAddress.url(of: icon, root: vault, textSize: 16))
            XCTAssertNotNil(NoteIconInlineAddress.named(by: address), "\(icon)")
            XCTAssertEqual(PreviewImageFragment.displaySize(in: address)?.width, 20, "Notion's 20 points beside 16-point text: \(icon)")
        }
        XCTAssertEqual(NoteIconInlineAddress.named(by: try XCTUnwrap(NoteIconInlineAddress.url(of: .emoji("🏢"), root: vault, textSize: 16))), .emoji("🏢"))
        let attachment = VaultImageAttachment(image: emoji, description: "🏢", displaySize: nil, path: nil, iconSide: 20)
        let environment = TextEnvironmentValues()
        XCTAssertEqual(attachment.sizeThatFits(ProposedViewSize(width: 5, height: nil), in: environment), CGSize(width: 20, height: 20))
        XCTAssertLessThan(attachment.baselineOffset(in: environment), 0, "The square reaches below the baseline as an emoji does.")
    }
}

/// An index answering fixed icons, counting its reads, and running `duringRead` while it reads.
private actor FixedIconLookup: NoteIconLookup {
    let icons: [VaultPath: NoteIcon]
    let duringRead: (@Sendable () async -> Void)?
    private(set) var readCount = 0

    init(icons: [VaultPath: NoteIcon], duringRead: (@Sendable () async -> Void)? = nil) {
        self.icons = icons
        self.duringRead = duringRead
    }

    func noteIcons() async throws -> [VaultPath: NoteIcon] {
        readCount += 1
        if readCount == 1 { await duringRead?() }
        return icons
    }
}
