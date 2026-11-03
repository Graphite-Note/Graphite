/**
 * File: LivePreviewBlockTests.swift
 * ---------------------------------
 * Layer: Tests
 * Description: What Live Preview draws as rendered blocks: properties, tables, math, embeds, callouts, rules.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.6
 * Date: 02/11/2026
 */

import XCTest
@testable import GraphiteCore

final class LivePreviewBlockTests: XCTestCase {
    func testFindsRenderedBlocks() {
        let source = """
        ---
        title: A
        ---
        Text
        | a | b |
        | --- | :-: |
        | 1 | $x$ |
        $$
        f = x
        $$
        ![[Figure.png|300]]
        ```base
        views: []
        ```
        ```swift
        | not | a table |
        | --- | --- |
        ```

        ---
        Heading
        ---
        """ as NSString
        let blocks = LivePreviewBlockScanner.blocks(in: source)
        guard blocks.count == 6 else { return XCTFail("Expected 6 blocks, found \(blocks.map(\.kind))") }
        XCTAssertEqual(blocks[0].kind, .frontmatter)
        XCTAssertEqual(source.substring(with: blocks[0].range), "---\ntitle: A\n---\n")
        XCTAssertEqual(blocks[1].kind, .table)
        XCTAssertEqual(blocks[1].markdown, "| a | b |\n| --- | :-: |\n| 1 | $x$ |")
        XCTAssertEqual(blocks[2].kind, .mathBlock)
        XCTAssertEqual(blocks[2].markdown, "$$\nf = x\n$$")
        guard case .embed(let embed) = blocks[3].kind else { return XCTFail("Expected an embed") }
        XCTAssertEqual(embed.target, "Figure.png")
        XCTAssertEqual(embed.displayWidth, 300)
        XCTAssertEqual(blocks[4].kind, .baseDefinition("views: []"))
        XCTAssertEqual(blocks[5].kind, .horizontalRule, "The rule after a blank line; the one after 'Heading' is an underline.")
        XCTAssertEqual(source.substring(with: blocks[5].range), "---\n")
    }

    func testCalloutIncludesItsQuotedBody() {
        let source = "Intro\n> [!note]- Folded title\n> Body with $x$\n>\n> - item\n\nAfter\n> plain quote\n" as NSString
        let blocks = LivePreviewBlockScanner.blocks(in: source)
        guard blocks.count == 1 else { return XCTFail("Expected only the callout; a plain quote stays text. Found \(blocks.map(\.kind))") }
        XCTAssertEqual(blocks[0].kind, .callout)
        XCTAssertEqual(blocks[0].markdown, "> [!note]- Folded title\n> Body with $x$\n>\n> - item")
        XCTAssertEqual(source.substring(with: blocks[0].range), "> [!note]- Folded title\n> Body with $x$\n>\n> - item\n")
    }

    func testTableNeedsDelimiterRow() {
        XCTAssertTrue(LivePreviewBlockScanner.blocks(in: "| just a pipe line |\nnext" as NSString).isEmpty)
    }

    func testPluginCodeBlocksAreBlocksOnlyInLanguagesPluginsDraw() {
        let source = "Intro\n```dataview\nLIST\n```\n```swift\nlet x = 1\n```\n~~~ad-note title\nBody\n~~~\n" as NSString
        XCTAssertTrue(LivePreviewBlockScanner.blocks(in: source).isEmpty, "Without plugins, fenced code stays text.")
        let blocks = LivePreviewBlockScanner.blocks(in: source, pluginCodeBlockLanguages: ["dataview", "ad-note"])
        XCTAssertEqual(blocks.map(\.kind), [.pluginCodeBlock(language: "dataview"), .pluginCodeBlock(language: "ad-note")])
        XCTAssertEqual(blocks[0].markdown, "LIST")
        XCTAssertEqual(source.substring(with: blocks[0].range), "```dataview\nLIST\n```\n")
        XCTAssertEqual(blocks[1].markdown, "Body")
    }

    /// A diagram is its whole fence, closing line and line break included, so the view covers it all; its code is what
    /// lies between the fences, as reading view reads it.
    func testAMermaidFenceIsADiagramBlockOfItsWholeFence() {
        let source = "Intro\n```mermaid\nflowchart TD\n  A --> B\n```\nAfter\n~~~Mermaid\npie\n~~~\n```mermaid\n```\n" as NSString
        let blocks = LivePreviewBlockScanner.blocks(in: source)
        XCTAssertEqual(blocks.map(\.kind), [.mermaidDiagram, .mermaidDiagram, .mermaidDiagram])
        XCTAssertEqual(blocks.map(\.markdown), ["flowchart TD\n  A --> B", "pie", ""])
        XCTAssertEqual(blocks.map { block in source.substring(with: block.range) },
                       ["```mermaid\nflowchart TD\n  A --> B\n```\n", "~~~Mermaid\npie\n~~~\n", "```mermaid\n```\n"])
    }

    func testAnUnclosedMermaidFenceRunsToTheEndOfTheNote() {
        let source = "Intro\n```mermaid\nflowchart TD\n  A --> B\n" as NSString
        let blocks = LivePreviewBlockScanner.blocks(in: source)
        XCTAssertEqual(blocks.map(\.kind), [.mermaidDiagram])
        XCTAssertEqual(blocks.first?.markdown, "flowchart TD\n  A --> B")
        XCTAssertEqual(blocks.first.map { block in NSMaxRange(block.range) }, source.length)
    }

    /// In a callout the diagram is part of the callout's block, which draws its body.
    func testAMermaidFenceInACalloutIsPartOfTheCallout() {
        let blocks = LivePreviewBlockScanner.blocks(in: "> [!note] Flow\n> ```mermaid\n> graph TD\n> ```\n" as NSString)
        XCTAssertEqual(blocks.map(\.kind), [.callout])
    }

    func testThePluginBlockIsFoundOnlyWhenOneBlockMatches() {
        let note = "# Title\n\n```dataview\nLIST\n```\n\n```dataview\nTABLE file.name\n```\n"
        let place = LivePreviewBlockScanner.onlyPluginCodeBlock(language: "dataview", code: "TABLE file.name", in: note)
        XCTAssertEqual(place?.firstLine, 6)
        XCTAssertEqual(place?.lineCount, 3)
        XCTAssertNil(LivePreviewBlockScanner.onlyPluginCodeBlock(language: "dataview", code: "LIST", in: note + "```dataview\nLIST\n```\n"),
                     "Two matching blocks: a plugin must not be given either's lines.")
        XCTAssertNil(LivePreviewBlockScanner.onlyPluginCodeBlock(language: "dataview", code: "TASK", in: note))
    }

    // MARK: A block's lines as the note has them

    /// What is drawn has no comment; what an edit starts from has it, or the edit would write the note without it.
    func testATableIsDrawnWithoutItsCommentsAndEditedWithThem() throws {
        let note = "Intro\n| a %% x | y %% | b |\n| - | - |\n| 1 %%n%% | 2 |\n\nAfter\n"
        let table = try XCTUnwrap(LivePreviewBlockScanner.blocks(in: note as NSString).first)
        XCTAssertFalse(table.markdown.contains("%%"), table.markdown)
        XCTAssertEqual(table.sourceLines, "| a %% x | y %% | b |\n| - | - |\n| 1 %%n%% | 2 |")
        XCTAssertFalse(table.isCutByComment)
        XCTAssertEqual(MarkdownTable.parse(table.sourceLines)?.columnCount, MarkdownTable.parse(table.markdown)?.columnCount,
                       "The cells edited are the cells drawn.")
        XCTAssertEqual(MarkdownTable.parse(table.sourceLines)?.rows.count, MarkdownTable.parse(table.markdown)?.rows.count)
    }

    /// The Markdown section's fix: a comment hides what is in it from what a callout draws.
    func testACalloutKeepsItsCommentsOutOfWhatItDraws() throws {
        let note = "> [!note] T\n> shown %%hidden[^1] ![[e.png]]%%\n> more\n"
        let callout = try XCTUnwrap(LivePreviewBlockScanner.blocks(in: note as NSString).first)
        XCTAssertEqual(callout.kind, .callout)
        XCTAssertEqual(callout.markdown, "> [!note] T\n> shown " + String(repeating: " ", count: "%%hidden[^1] ![[e.png]]%%".utf16.count) + "\n> more")
        XCTAssertEqual(callout.sourceLines, "> [!note] T\n> shown %%hidden[^1] ![[e.png]]%%\n> more")
    }

    func testAWindowsNotesBlockHasItsLinesAsTheNoteHasThem() throws {
        let note = "Text\r\n> [!todo] T\r\n> - [ ] one\r\n\r\n| a |\r\n| - |\r\n"
        let blocks = LivePreviewBlockScanner.blocks(in: note as NSString)
        XCTAssertEqual(blocks.map(\.markdown), ["> [!todo] T\n> - [ ] one", "| a |\n| - |"])
        XCTAssertEqual(blocks.map(\.sourceLines), ["> [!todo] T\r\n> - [ ] one", "| a |\r\n| - |"])
    }

    func testABlockWithNothingToKeepHasItsMarkdownAsItsLines() throws {
        let table = try XCTUnwrap(LivePreviewBlockScanner.blocks(in: "| a |\n| - |\n" as NSString).first)
        XCTAssertEqual(table.sourceLines, table.markdown)
        XCTAssertFalse(table.isCutByComment)
    }

    /// The lines alone would not say a comment is one, so their cells would not be the ones drawn.
    func testACommentRunningPastATablesEdgeCutsIt() throws {
        let past = try XCTUnwrap(LivePreviewBlockScanner.blocks(in: "| a | b |\n| - | - |\n| 1 %% x | 2 |\n\nAfter %% end\n" as NSString).first)
        XCTAssertEqual(past.kind, .table)
        XCTAssertTrue(past.isCutByComment)
        XCTAssertEqual(MarkdownTable.parse(past.markdown)?.rows[1].count, 1, "The rest of the row is hidden.")
        let before = LivePreviewBlockScanner.blocks(in: "Start %% hidden\nmore %% | a | b |\n| - | - |\n" as NSString).first { block in block.kind == .table }
        XCTAssertEqual(before?.isCutByComment, true)
    }

    /// Row commands move whole lines, so they would split this comment: what is left of it shows
    /// the hidden text, or pairs with a later marker and hides what lies between.
    func testACommentOverARowBreakLeavesTheTableToSourceEditing() throws {
        let table = try XCTUnwrap(LivePreviewBlockScanner.blocks(in: "| x | y |\n| - | - |\n| a | b %%\n| c %% | d |\n" as NSString).first)
        XCTAssertEqual(table.kind, .table)
        XCTAssertTrue(table.isCutByComment)
        let windows = try XCTUnwrap(LivePreviewBlockScanner.blocks(in: "| x | y |\r\n| - | - |\r\n| a | b %%\r\n| c %% | d |\r\n" as NSString).first)
        XCTAssertTrue(windows.isCutByComment)
        let oneRow = try XCTUnwrap(LivePreviewBlockScanner.blocks(in: "| x | y |\n| - | - |\n| a %%n%% | b |\n| c | d %%m%% |\n" as NSString).first)
        XCTAssertFalse(oneRow.isCutByComment, "Each comment moves with its row.")
    }
}
