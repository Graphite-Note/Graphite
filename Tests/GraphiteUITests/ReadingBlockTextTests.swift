/**
 * File: ReadingBlockTextTests.swift
 * ---------------------------------
 * Layer: Tests
 * Description: Reading view and Live Preview's rendered blocks read a note alike: line breaks, links, footnotes,
 *              tasks, callout fold keys, raw HTML, tags, reference links and nested heading links.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 02/11/2026
 */

import XCTest
import SwiftUI
import GraphiteCore
import GraphiteIndex
@testable import GraphiteUI
import GraphiteTestSupport

@MainActor
final class ReadingBlockTextTests: XCTestCase {
    private var vault: URL!
    private var index: VaultIndex!

    override func setUp() async throws {
        vault = try TemporaryVault.make(prefix: "MarkdownReadingFixVault", for: self).root
        index = try VaultIndex(databaseURL: vault.appendingPathComponent(".index.sqlite"))
    }

    override func tearDown() async throws {
        index = nil
        try? FileManager.default.removeItem(at: vault) // Best-effort removal of a temporary folder.
    }

    private func build(_ source: String) async throws -> ReadingViewBuild {
        try await ReadingViewBuilder().build(source: source, note: try VaultPath("Note.md"), root: vault, index: index, configuration: ReadingConfiguration())
    }

    private func markdownRuns(_ blocks: [RenderedBlock]) -> [String] {
        blocks.compactMap { block in
            if case .markdown(_, let text) = block { text } else { nil }
        }
    }

    // MARK: Lines in a callout body or a table (HUNT-119)

    func testLinesOfARenderedBlockAreSeparateUnlessTheVaultIsStrict() {
        let soft = LivePreviewText.prepared("first line\nsecond line", colorsEnabled: false, paletteHexByName: [:], usesStrictLineBreaks: false)
        XCTAssertEqual(soft, "first line  \nsecond line  ", "Each line ends the line, as the reading view makes it.")
        let strict = LivePreviewText.prepared("first line\nsecond line", colorsEnabled: false, paletteHexByName: [:], usesStrictLineBreaks: true)
        XCTAssertEqual(strict, "first line\nsecond line")
        let readingView = ReadingBlockText.readingText("first line\nsecond line", colorsEnabled: false, paletteHexByName: [:], usesStrictLineBreaks: false)
        XCTAssertEqual(soft, readingView, "Live Preview and the reading view make the same text of it.")
    }

    // MARK: Links in a callout or table (HUNT-120)

    func testMarkdownLinksToAHeadingOrAnotherFolderAreFollowedInRenderedBlocks() {
        let prepared = LivePreviewText.prepared("[see setup](#Setup) and [other](../Other.md) and [web](https://example.com)",
                                                colorsEnabled: false, paletteHexByName: [:])
        XCTAssertTrue(prepared.contains("](\(GraphiteOpenLink.markdownDestination(target: "#Setup", isWiki: false)))"), prepared)
        XCTAssertTrue(prepared.contains("](\(GraphiteOpenLink.markdownDestination(target: "../Other.md", isWiki: false)))"), prepared)
        XCTAssertTrue(prepared.contains("](https://example.com)"), "A web address is left to the system.")
    }

    // MARK: Footnotes and tasks in a callout (HUNT-131, HUNT-135)

    func testAFootnoteReferenceInACalloutIsTheSameRaisedNumberAsInTheReadingView() throws {
        let note = "Intro[^b]\n\n> [!note]\n> Claim[^a] and more[^b]\n\n[^a]: Alpha\n[^b]: Beta\n"
        let calloutStart = (note as NSString).range(of: "> [!note]").location
        let rest = String(note.dropFirst(calloutStart))
        let source = rest.components(separatedBy: "\n").prefix(2).joined(separator: "\n")
        let reading = RenderedBlockNoteReading(noteText: note, sourceMarkdown: source, sourceRange: NSRange(location: calloutStart, length: (source as NSString).length))
        let located = try XCTUnwrap(NotePreviewDocument.locatedBlocks(from: source).first?.body.first)
        guard case .markdown(let markdown) = located.block else { return XCTFail("\(located.block)") }
        let prepared = LivePreviewText.prepared(markdown, colorsEnabled: false, paletteHexByName: [:], place: RenderedBlockPlace(reading: reading, lineOffsets: located.lineStartOffsets))
        // Intro's [^b] is the first reference, so b is 1 and a is 2, in the reading view and here.
        XCTAssertEqual(prepared, "Claim[2](\(GraphiteOpenLink.footnoteDestination(number: 2))) and more[1](\(GraphiteOpenLink.footnoteDestination(number: 1)))")
        XCTAssertFalse(prepared.contains("[^"))
    }

    func testATaskInACalloutCanBeTickedFromLivePreview() throws {
        let note = "Before\n\n> [!todo]\n> - [ ] write it\n> - [x] done\n\nAfter\n"
        let calloutStart = (note as NSString).range(of: "> [!todo]").location
        let source = "> [!todo]\n> - [ ] write it\n> - [x] done"
        let reading = RenderedBlockNoteReading(noteText: note, sourceMarkdown: source, sourceRange: NSRange(location: calloutStart, length: (source as NSString).length))
        let located = try XCTUnwrap(NotePreviewDocument.locatedBlocks(from: source).first?.body.first)
        guard case .markdown(let markdown) = located.block else { return XCTFail("\(located.block)") }
        let prepared = LivePreviewText.prepared(markdown, colorsEnabled: false, paletteHexByName: [:], place: RenderedBlockPlace(reading: reading, lineOffsets: located.lineStartOffsets))
        let attributed = try ObsidianMarkdownParser(baseURL: vault, textSize: 17).attributedString(for: prepared)
        let tasks = attributed.runs.compactMap { run in attributed[run.range].runs.first?[ReadingTaskAttribute.self] }
        XCTAssertEqual(tasks.map(\.isChecked), [false, true])
        let location = try XCTUnwrap(tasks.first?.location, "A checkbox with no place is a picture.")
        let edit = try XCTUnwrap(ReadingTasks.togglingEdit(at: location.inNote(blockStart: calloutStart), in: note, selection: NSRange(location: 0, length: 0)))
        XCTAssertEqual((note as NSString).replacingCharacters(in: edit.range, with: edit.replacement),
                       "Before\n\n> [!todo]\n> - [x] write it\n> - [x] done\n\nAfter\n")
        // Without a place the checkbox stays a picture, as before.
        let picture = LivePreviewText.prepared(markdown, colorsEnabled: false, paletteHexByName: [:])
        let pictureTasks = try ObsidianMarkdownParser(baseURL: vault, textSize: 17).attributedString(for: picture)
        XCTAssertNil(pictureTasks.runs.compactMap { run in pictureTasks[run.range].runs.first?[ReadingTaskAttribute.self]?.location }.first)
    }

    // MARK: Tasks of a rendered block that moved, or of a Windows note

    /// The tasks a rendered callout's body draws, each with the place its checkbox was given.
    private func tasksDrawn(in block: LivePreviewBlock, note: String) throws -> [ReadingTasks.MarkedTask] {
        let reading = RenderedBlockNoteReading(noteText: note, sourceMarkdown: block.markdown, sourceLines: block.sourceLines, sourceRange: block.range)
        let located = try XCTUnwrap(NotePreviewDocument.locatedBlocks(from: block.markdown).first?.body.first)
        guard case .markdown(let markdown) = located.block else { throw GraphiteError.unavailable("\(located.block)") }
        let prepared = LivePreviewText.prepared(markdown, colorsEnabled: false, paletteHexByName: [:], place: RenderedBlockPlace(reading: reading, lineOffsets: located.lineStartOffsets))
        let attributed = try ObsidianMarkdownParser(baseURL: vault, textSize: 17).attributedString(for: prepared)
        return attributed.runs.compactMap { run in attributed[run.range].runs.first?[ReadingTaskAttribute.self] }
    }

    private func ticking(_ task: ReadingTasks.MarkedTask, blockStart: Int, in note: String) throws -> String {
        let location = try XCTUnwrap(task.location, "A checkbox with no place is a picture.")
        let edit = try XCTUnwrap(ReadingTasks.togglingEdit(at: location.inNote(blockStart: blockStart), in: note, selection: NSRange(location: 0, length: 0)),
                                 "The note has no such task there.")
        return (note as NSString).replacingCharacters(in: edit.range, with: edit.replacement)
    }

    /// The view of a callout stays while typing above moves it, keeping the place it was given.
    func testATaskOfACalloutThatMovedIsTickedWhereItIsNow() throws {
        let note = "Before\n\n> [!todo]\n> - [ ] same\n> - [ ] same\n"
        let callout = try XCTUnwrap(LivePreviewBlockScanner.blocks(in: note as NSString).first)
        let tasks = try tasksDrawn(in: callout, note: note)
        guard tasks.count == 2 else { return XCTFail("\(tasks)") }
        // Just as long as a task's line, so the second task's old place is now the first task, which reads the same.
        let typed = "123456789012\n"
        let noteAfterTyping = typed + note
        XCTAssertEqual(try ticking(tasks[1], blockStart: callout.range.location + (typed as NSString).length, in: noteAfterTyping),
                       typed + "Before\n\n> [!todo]\n> - [ ] same\n> - [x] same\n")
    }

    func testTheTapOfARenderedBlocksCheckboxAsksWhereTheBlockIsNow() async throws {
        var ticked: [ReadingTasks.Location] = []
        var environment = LivePreviewEnvironment(root: vault, textSize: 17, colorsEnabled: false, paletteHexByName: [:], drawingVersion: 0,
                                                 resolve: { _, _ in nil }, open: { _ in }, follow: { _, _ in }, updateProperties: nil)
        environment.toggleTask = { location in ticked.append(location); return true }
        var blockStart: Int? = 100
        let context = try XCTUnwrap(ReadingTaskContext.ofRenderedBlock(environment: environment) { blockStart })
        let tapped = ReadingTasks.Location(statusOffset: 7, lineChecksum: 9)
        let didTickAt100 = await context.toggle(context.note, tapped)
        XCTAssertTrue(didTickAt100)
        blockStart = 250
        let didTickAt250 = await context.toggle(context.note, tapped)
        XCTAssertTrue(didTickAt250)
        XCTAssertEqual(ticked.map(\.statusOffset), [107, 257])
        blockStart = nil
        let didTickWithoutABlock = await context.toggle(context.note, tapped)
        XCTAssertFalse(didTickWithoutABlock, "A block no longer in the note ticks nothing.")
        XCTAssertEqual(ticked.count, 2)
    }

    func testEveryTaskOfACalloutInAWindowsNoteIsTickedOnItsOwnLine() throws {
        let note = "Before\r\n\r\n> [!todo]\r\n> - [ ] one\r\n> - [ ] two\r\n\r\nAfter\r\n"
        let callout = try XCTUnwrap(LivePreviewBlockScanner.blocks(in: note as NSString).first)
        let tasks = try tasksDrawn(in: callout, note: note)
        guard tasks.count == 2 else { return XCTFail("\(tasks)") }
        XCTAssertEqual(try ticking(tasks[0], blockStart: callout.range.location, in: note), "Before\r\n\r\n> [!todo]\r\n> - [x] one\r\n> - [ ] two\r\n\r\nAfter\r\n")
        XCTAssertEqual(try ticking(tasks[1], blockStart: callout.range.location, in: note), "Before\r\n\r\n> [!todo]\r\n> - [ ] one\r\n> - [x] two\r\n\r\nAfter\r\n")
    }

    /// A line's checksum is of the line the note has, comment included.
    func testATaskWithACommentOnItsLineCanBeTicked() throws {
        let note = "> [!todo]\n> - [ ] one %%why%%\n> - [ ] two\n"
        let callout = try XCTUnwrap(LivePreviewBlockScanner.blocks(in: note as NSString).first)
        let tasks = try tasksDrawn(in: callout, note: note)
        guard tasks.count == 2 else { return XCTFail("\(tasks)") }
        XCTAssertEqual(try ticking(tasks[0], blockStart: 0, in: note), "> [!todo]\n> - [x] one %%why%%\n> - [ ] two\n")
        XCTAssertEqual(try ticking(tasks[1], blockStart: 0, in: note), "> [!todo]\n> - [ ] one %%why%%\n> - [x] two\n")
    }

    func testAFootnoteReferenceInACalloutOfAWindowsNoteHasItsNumber() throws {
        let note = "> [!note]\r\n> first\r\n> Claim[^a]\r\n\r\n[^a]: Alpha\r\n"
        let callout = try XCTUnwrap(LivePreviewBlockScanner.blocks(in: note as NSString).first)
        let reading = RenderedBlockNoteReading(noteText: note, sourceMarkdown: callout.markdown, sourceLines: callout.sourceLines, sourceRange: callout.range)
        let located = try XCTUnwrap(NotePreviewDocument.locatedBlocks(from: callout.markdown).first?.body.first)
        guard case .markdown(let markdown) = located.block else { return XCTFail("\(located.block)") }
        let prepared = LivePreviewText.prepared(markdown, colorsEnabled: false, paletteHexByName: [:], place: RenderedBlockPlace(reading: reading, lineOffsets: located.lineStartOffsets))
        XCTAssertFalse(prepared.contains("[^a]"), prepared)
        XCTAssertTrue(prepared.contains(GraphiteOpenLink.footnoteDestination(number: 1)), prepared)
    }

    func testRenderedBlockReadsTheRestOfTheNoteForItsReferenceLinks() throws {
        let note = "> [!note]\n> See [the docs][1].\n\n[1]: https://example.com\n"
        let source = "> [!note]\n> See [the docs][1]."
        let reading = RenderedBlockNoteReading(noteText: note, sourceMarkdown: source, sourceRange: NSRange(location: 0, length: (source as NSString).length))
        let prepared = LivePreviewText.prepared("See [the docs][1].", colorsEnabled: false, paletteHexByName: [:],
                                                place: RenderedBlockPlace(reading: reading, lineOffsets: [0]))
        XCTAssertTrue(prepared.hasSuffix("[1]: https://example.com"), prepared)
    }

    // MARK: Callouts that share a title (HUNT-121)

    func testReadingViewGivesCalloutsWithTheSameTitleDifferentFoldKeys() async throws {
        let source = "> [!question]- Answer\n> one\n\n> [!question]- Answer\n> two\n\n> [!tip]- Answer\n> x\n\n> [!question]- Answer\n> three\n"
        let build = try await build(source)
        let identifiers = build.blocks.compactMap { block -> String? in
            if case .callout = block { block.id } else { nil }
        }
        XCTAssertEqual(identifiers.map { build.foldKeys.calloutOccurrencesByBlock[$0] }, [0, 1, 0, 2])
    }

    func testCalloutsOfAnEmbeddedNoteDoNotShareKeysWithTheHostNote() async throws {
        try Data("> [!question]- Answer\n> embedded\n".utf8).write(to: vault.appendingPathComponent("Other.md"))
        let source = "> [!question]- Answer\n> host\n\n![[Other]]\n"
        let build = try await build(source)
        var titles: [String] = []
        func collect(_ blocks: [RenderedBlock]) {
            for block in blocks {
                switch block {
                case .callout(_, _, _, _, let body): titles.append(build.foldKeys.calloutTitlesByBlock[block.id] ?? ""); collect(body)
                case .transclusion(_, _, _, let body): collect(body)
                default: break
                }
            }
        }
        collect(build.blocks)
        XCTAssertEqual(titles, ["Answer", "Other.md#Answer"])
    }

    func testLivePreviewKnowsWhichCalloutOfTheNoteItIs() {
        let note = "> [!question]- Answer\n> one\n\n> [!question]- Answer\n> two\n"
        let secondStart = (note as NSString).range(of: "> [!question]- Answer", options: .backwards).location
        let source = String(note.dropFirst(secondStart))
        let reading = RenderedBlockNoteReading(noteText: note, sourceMarkdown: source, sourceRange: NSRange(location: secondStart, length: (source as NSString).length))
        XCTAssertEqual(reading.calloutOccurrence(atSourceOffset: 0), 1)
    }

    // MARK: Raw HTML (HUNT-122)

    func testRawHTMLIsDrawnNotPrinted() throws {
        func drawn(_ markdown: String) throws -> AttributedString {
            let text = ReadingBlockText.readingText(markdown, colorsEnabled: false, paletteHexByName: [:], usesStrictLineBreaks: true)
            return try ObsidianMarkdownParser(baseURL: vault, textSize: 17).attributedString(for: text)
        }
        let table = try drawn("| a | b |\n| - | - |\n| line one<br>line two | c |\n")
        XCTAssertTrue(String(table.characters).contains("line one\u{2028}line two"), String(table.characters))
        XCTAssertFalse(String(table.characters).contains("<br>"))
        let inline = try drawn("H<sub>2</sub>O<!-- hidden --> and <mark>hot</mark>")
        XCTAssertEqual(String(inline.characters).replacingOccurrences(of: "\n", with: ""), "H\u{2082}O and hot")
        let underlined = try drawn("plain <u>under</u> plain")
        XCTAssertEqual(underlined.runs.filter { $0.underlineStyle == .single }.map { String(underlined[$0.range].characters) }, ["under"])
    }

    // MARK: Tags (HUNT-137)

    func testTagsAreStyledAndLinkedWithoutATheme() throws {
        let linked = try ObsidianMarkdownParser(baseURL: vault, textSize: 17, linksTags: true).attributedString(for: "Filed under #project/alpha and #café and `#code`")
        let links = linked.runs.compactMap { run in run.link.flatMap(GraphiteOpenLink.tagName(of:)) }
        XCTAssertEqual(links, ["project/alpha", "café"])
        let styled = linked.runs.filter { $0.foregroundColor != nil }.map { String(linked[$0.range].characters) }
        XCTAssertEqual(styled, ["#project/alpha", "#café"])
        let plain = try ObsidianMarkdownParser(baseURL: vault, textSize: 17).attributedString(for: "Filed under #project/alpha")
        XCTAssertTrue(plain.runs.allSatisfy { $0.link == nil }, "Without a way to search, a tag is styled text.")
        XCTAssertEqual(plain.runs.filter { $0.foregroundColor != nil }.map { String(plain[$0.range].characters) }, ["#project/alpha"])
        let emoji = try ObsidianMarkdownParser(baseURL: vault, textSize: 17, linksTags: true).attributedString(for: "Rocket #🚀 here, and C# and a#b")
        XCTAssertEqual(emoji.runs.compactMap { run in run.link.flatMap(GraphiteOpenLink.tagName(of:)) }, ["🚀"])
    }

    func testATagInACodeBlockIsNotATag() throws {
        let attributed = try ObsidianMarkdownParser(baseURL: vault, textSize: 17, linksTags: true).attributedString(for: "```c\n#include <x>\n```\n")
        XCTAssertTrue(attributed.runs.allSatisfy { $0.link == nil && $0.foregroundColor == nil })
    }

    // MARK: Heading links (HUNT-136, HUNT-118)

    func testALinkToANestedHeadingNamesEveryHeading() {
        XCTAssertEqual(ReadingViewBuilder.displayText(target: "Note#Parent#Child", alias: nil), "Note > Parent > Child")
        XCTAssertEqual(ReadingViewBuilder.displayText(target: "#Parent#Child", alias: nil), "Parent > Child")
        XCTAssertEqual(ReadingViewBuilder.displayText(target: "Note#^abc", alias: nil), "Note > abc")
        XCTAssertEqual(ReadingViewBuilder.displayText(target: "Folder/Note.md#Heading", alias: nil), "Folder/Note > Heading")
        XCTAssertEqual(ReadingViewBuilder.displayText(target: "Note#Heading", alias: "Shown"), "Shown")
        XCTAssertEqual(ReadingViewBuilder.displayText(target: "Note", alias: nil), "Note")
    }

    func testReadingViewScrollsToAHeadingWhoseTitleHasAColon() async throws {
        let build = try await build("# One\n\n## Step 1: Setup\nthe steps\n")
        let target = HeadingScrollRequest.readingScrollTarget(forLinkAnchor: NotePreviewDocument.anchor(forHeading: "Step 1 Setup"), in: build.blocks)
        XCTAssertEqual(target, NotePreviewDocument.anchor(forHeading: "Step 1: Setup"))
    }

    // MARK: Reference links (HUNT-129)

    func testAReferenceLinkFindsItsDefinitionInAnotherBlock() async throws {
        let build = try await build("# A\nSee [the docs][1].\n\n## B\ntext\n\n[1]: https://example.com\n")
        let runs = markdownRuns(build.blocks)
        XCTAssertTrue(runs.first { $0.contains("See [the docs][1]") }?.contains("[1]: https://example.com") == true, "\(runs)")
    }

    // MARK: Long notes (HUNT-133)

    func testTheLinesOfALongNoteAreFoundWithOneScan() {
        let note = (0..<5_000).map { "line \($0) é" }.joined(separator: "\n")
        let index = NoteTextIndex(text: note)
        let source = note as NSString
        for offset in stride(from: 0, to: source.length, by: 211) {
            let expected = source.substring(to: offset).utf16.reduce(0) { lineCount, codeUnit in codeUnit == 10 ? lineCount + 1 : lineCount }
            XCTAssertEqual(index.lineIndex(containingOffset: offset), expected)
        }
        XCTAssertEqual(index.lineScanCount, 1, "One scan of the note answers every section, not one scan for each.")
    }
}
