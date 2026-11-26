/**
 * File: SlashCommandListTests.swift
 * ---------------------------------
 * Layer: Tests
 * Description: What a `/` lists and in what order, what choosing an entry edits, and when the editors' suggestions
 *              open the slash commands (only on typing, only while they are on).
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

import XCTest
import GraphiteCore
@testable import GraphiteUI
import GraphiteTestSupport

@MainActor
final class SlashCommandListTests: XCTestCase {
    /// The note's menus' actions, recording what they were asked to do.
    private final class MenuRecorder {
        var commands: [String] = []
        var insertedBlocks: [String] = []
        var templateRequests = 0

        func actions() -> EditorContextMenuActions {
            EditorContextMenuActions(run: { [unowned self] command in commands.append(String(describing: command)) },
                                     noteState: { ("" as NSString, NSRange(location: 0, length: 0)) },
                                     apply: { _ in },
                                     insertBlock: { [unowned self] block in insertedBlocks.append(block) },
                                     colors: [PaletteColor(name: "Red", hex: "#ff0000")],
                                     insertColor: { _, _ in },
                                     linkToNote: {},
                                     template: { [unowned self] in templateRequests += 1 })
        }
    }

    private func entries(paletteCommands: [PaletteCommand] = [], recorder: MenuRecorder = MenuRecorder()) -> [SlashCommandEntry] {
        SlashCommandList.entries(menuEntries: EditorContextMenuContent.slashMenuEntries(actions: recorder.actions(), editorActions: EditorActions()),
                                 paletteCommands: paletteCommands)
    }

    /// The slash commands of a note whose text is `text()`, its menus acting through `recorder`.
    private func source(text: @escaping () -> String, recorder: MenuRecorder = MenuRecorder(), paletteCommands: [PaletteCommand] = []) -> SlashCommandSource {
        let menus = SlashCommandSource.NoteMenus(
            actions: recorder.actions(),
            entries: { actions in EditorContextMenuContent.slashMenuEntries(actions: actions, editorActions: EditorActions()) },
            commandEdit: { command, text, selection in MarkdownEditing.edit(for: command, in: text, selection: selection, indentUnit: "    ") },
            noteText: { text() as NSString })
        return SlashCommandSource(menus: menus, paletteCommands: { paletteCommands })
    }

    /// The query typed at the end of `text`.
    private func queryAtEnd(of text: String) throws -> SlashCommandQuery {
        try XCTUnwrap(SlashCommandTrigger.query(in: text as NSString, cursor: (text as NSString).length))
    }

    private func applying(_ edits: [MarkdownTextEdit], to text: String) -> String {
        edits.sorted { leftEdit, rightEdit in leftEdit.range.location > rightEdit.range.location }
            .reduce(text as NSString) { current, edit in current.replacingCharacters(in: edit.range, with: edit.replacement) as NSString } as String
    }

    private func choose(_ title: String, typing text: String, recorder: MenuRecorder = MenuRecorder(),
                        paletteCommands: [PaletteCommand] = []) async throws -> (edits: [MarkdownTextEdit], item: CompletionItem) {
        let query = try queryAtEnd(of: text)
        let items = source(text: { text }, recorder: recorder, paletteCommands: paletteCommands).items(for: query)
        let item = try XCTUnwrap(items.first { item in item.title == title }, "\(title) is listed for /\(query.text): \(items.map(\.title))")
        return (try await item.makeEdits(.slashCommand(query)), item)
    }

    // MARK: The list

    func testTheParagraphEntriesComeFirstThenInsertsThenFormatsWithoutTheColours() throws {
        let titles = entries().map(\.title)
        XCTAssertEqual(Array(titles.prefix(4)), ["Bulleted List", "Numbered List", "Task", "Heading 1"])
        for title in ["Heading 6", "Body", "Quote", "Table", "Callout", "Code Block", "Math Block", "Mermaid Diagram", "Horizontal Rule", "Tag",
                      "Link to Note…", "Embed", "Template…", "Bold", "Italic", "Inline Math", "Comment"] {
            XCTAssertTrue(titles.contains(title), "\(title) is listed: \(titles)")
        }
        XCTAssertFalse(titles.contains("Red"), "Colours need a selection; they stay in the Format menu.")
        XCTAssertLessThan(try XCTUnwrap(titles.firstIndex(of: "Quote")), try XCTUnwrap(titles.firstIndex(of: "Table")))
        XCTAssertLessThan(try XCTUnwrap(titles.firstIndex(of: "Template…")), try XCTUnwrap(titles.firstIndex(of: "Bold")))
        XCTAssertEqual(entries().first { entry in entry.title == "Heading 2" }?.systemImage, SlashCommandList.headingSymbol)
        XCTAssertEqual(Set(entries().map(\.identifier)).count, titles.count, "Each entry has its own identifier.")
    }

    func testThePalettesCommandsFollowWithoutThoseAMenuEntryAlreadyOffers() {
        var ran: [String] = []
        let palette = [
            PaletteCommand(id: "heading-2", title: "Set as heading 2", systemImage: "number") { ran.append("heading") },
            PaletteCommand(id: "table", title: "Insert table", systemImage: "tablecells") { ran.append("table") },
            PaletteCommand(id: "toggle-reading", title: "Toggle reading view", systemImage: "book") { ran.append("reading") },
        ]
        let listed = entries(paletteCommands: palette)
        XCTAssertEqual(listed.last?.title, "Toggle reading view")
        XCTAssertFalse(listed.contains { entry in entry.title == "Set as heading 2" || entry.title == "Insert table" })
        guard case .command(let run) = listed.last?.action else { return XCTFail("A palette command runs as a command.") }
        run()
        XCTAssertEqual(ran, ["reading"])
    }

    func testADisabledEntryIsLeftOut() {
        let menu: [EditorContextMenuEntry] = [.action("Shown", "a") {}, .group([.action("Dimmed", "b", isEnabled: false) {}, .submenu("More", "c", [.action("Nested", "d") {}])])]
        XCTAssertEqual(SlashCommandList.entries(menuEntries: menu, paletteCommands: []).map(\.title), ["Shown", "Nested"])
    }

    func testAnEmptyQueryKeepsTheOrderAndLettersRankTheBestMatchFirst() {
        let listed = entries()
        XCTAssertEqual(SlashCommandList.ranked(listed, query: "").map(\.entry.title), listed.map(\.title))
        XCTAssertEqual(SlashCommandList.ranked(listed, query: "tab").first?.entry.title, "Table")
        XCTAssertEqual(SlashCommandList.ranked(listed, query: "call").first?.entry.title, "Callout")
        XCTAssertEqual(SlashCommandList.ranked(listed, query: "merm").first?.entry.title, "Mermaid Diagram")
        XCTAssertEqual(Array(SlashCommandList.ranked(listed, query: "head").prefix(6).map(\.entry.title)),
                       (1...6).map { level in "Heading \(level)" }, "Equal scores keep the menu's order.")
        XCTAssertTrue(SlashCommandList.ranked(listed, query: "zzzq").isEmpty)
        XCTAssertFalse(SlashCommandList.ranked(listed, query: "tab").first?.match?.matchedRanges.isEmpty ?? true, "The matched letters are highlighted.")
    }

    // MARK: Choosing an entry

    func testABlockTakesTheQuerysPlaceInOneEdit() async throws {
        let recorder = MenuRecorder()
        let (edits, item) = try await choose("Table", typing: "Intro\n\n/tab", recorder: recorder)
        XCTAssertEqual(edits.count, 1, "One edit, so one undo gives the /tab back.")
        let expected = MarkdownSession.menuBlockEdit(EditorContextMenuContent.tableBlock, in: "Intro\n\n", after: 7)
        XCTAssertEqual(applying(edits, to: "Intro\n\n/tab"), applying([expected], to: "Intro\n\n"))
        XCTAssertEqual(edits.first?.selectionAfter, expected.selectionAfter, "The cursor goes to the table's first cell.")
        XCTAssertTrue(recorder.insertedBlocks.isEmpty, "The menu's own insertion is not made: its edit is.")
        XCTAssertNil(item.runAfterEdits)
    }

    func testAHeadingMarksTheQuerysLine() async throws {
        let (edits, _) = try await choose("Heading 2", typing: "Intro\n/h2")
        XCTAssertEqual(applying(edits, to: "Intro\n/h2"), "Intro\n## ")
        XCTAssertEqual(edits.first?.selectionAfter, NSRange(location: 9, length: 0))
        let (afterText, _) = try await choose("Heading 1", typing: "Notes /h1")
        XCTAssertEqual(applying(afterText, to: "Notes /h1"), "# Notes ", "After text, the line becomes the heading, as the Paragraph menu does.")
    }

    func testAnEntryThatOpensADialogOpensItAndTakesOutTheQuery() async throws {
        let recorder = MenuRecorder()
        let (edits, _) = try await choose("Template…", typing: "/temp", recorder: recorder)
        XCTAssertEqual(applying(edits, to: "/temp"), "")
        XCTAssertEqual(recorder.templateRequests, 1)
    }

    func testACommandRunsOnceItsQueryIsTakenOut() async throws {
        var ran = false
        let (edits, item) = try await choose("Toggle reading view", typing: "See /read",
                                             paletteCommands: [PaletteCommand(id: "toggle-reading", title: "Toggle reading view", systemImage: "book") { ran = true }])
        XCTAssertEqual(applying(edits, to: "See /read"), "See ")
        XCTAssertFalse(ran, "Not before the query is out.")
        item.runAfterEdits?()
        XCTAssertTrue(ran)
    }

    func testAQueryNoLongerTypedEditsNothing() async throws {
        var text = "/tab"
        let query = try queryAtEnd(of: text)
        let item = try XCTUnwrap(source(text: { text }).items(for: query).first { item in item.title == "Table" })
        text = "/tub"
        let edits = try await item.makeEdits(.slashCommand(query))
        XCTAssertTrue(edits.isEmpty)
        let otherContextEdits = try await item.makeEdits(.tag(query: "x", replacementRange: NSRange(location: 0, length: 1)))
        XCTAssertTrue(otherContextEdits.isEmpty, "Nothing is taken out once no slash command is typed.")
    }

    func testTheRemovalAndTheEntrysEditCombineWhereverTheEditIs() {
        let text = "ab /xy cd" as NSString
        let removal = MarkdownTextEdit(range: NSRange(location: 3, length: 3), replacement: "", selectionAfter: NSRange(location: 3, length: 0))
        func combinedText(_ edit: MarkdownTextEdit) -> String {
            let combined = SlashCommandList.combined(removal, then: edit, in: text)
            return text.replacingCharacters(in: combined.range, with: combined.replacement)
        }
        // On "ab  cd": before, at and after where the query was.
        XCTAssertEqual(combinedText(MarkdownTextEdit(range: NSRange(location: 0, length: 0), replacement: "# ", selectionAfter: NSRange())), "# ab  cd")
        XCTAssertEqual(combinedText(MarkdownTextEdit(range: NSRange(location: 3, length: 0), replacement: "X", selectionAfter: NSRange())), "ab X cd")
        XCTAssertEqual(combinedText(MarkdownTextEdit(range: NSRange(location: 4, length: 2), replacement: "Z", selectionAfter: NSRange())), "ab  Z")
        XCTAssertEqual(combinedText(MarkdownTextEdit(range: NSRange(location: 1, length: 4), replacement: "-", selectionAfter: NSRange())), "a-d", "Across where the query was.")
    }

    func testTheModelMakesTheEditsThenRunsACommandOnlyWhenTheyWereMade() async throws {
        var ranCount = 0
        let model = CompletionModel()
        var text = "/read"
        let slashCommands = source(text: { text }, paletteCommands: [PaletteCommand(id: "toggle-reading", title: "Toggle reading view", systemImage: "book") {
            ranCount += 1
        }])
        model.slashCommands = slashCommands
        var performedEdits: [[MarkdownTextEdit]] = []
        var editsAreMade = true
        model.performEdits = { edits in
            performedEdits.append(edits)
            return editsAreMade
        }
        model.update(context: .slashCommand(try queryAtEnd(of: text)), caretRect: .zero)
        try await waitUntil("the slash commands show") { model.isVisible }
        model.accept()
        try await waitUntil("the command runs") { ranCount == 1 }
        XCTAssertEqual(performedEdits.count, 1)

        editsAreMade = false
        text = "/readi"
        model.update(context: .slashCommand(try queryAtEnd(of: text)), caretRect: .zero)
        try await waitUntil("the slash commands show again") { model.isVisible }
        model.accept()
        try await waitUntil("the removal is refused") { performedEdits.count == 2 }
        // A command runs right after its edits are made, in the same step, or not at all.
        XCTAssertEqual(ranCount, 1, "A refused removal runs nothing.")
        withExtendedLifetime(slashCommands) {}
    }

    func testTheEntriesAreMadeOncePerSlashAndAgainForTheNext() {
        var madeCount = 0
        let menus = SlashCommandSource.NoteMenus(actions: MenuRecorder().actions(), entries: { _ in
            madeCount += 1
            return [.action("Table", "tablecells") {}]
        }, commandEdit: { _, _, _ in nil }, noteText: { "" })
        let source = SlashCommandSource(menus: menus, paletteCommands: { [] })
        _ = source.items(for: SlashCommandQuery(text: "", replacementRange: NSRange(location: 4, length: 1)))
        _ = source.items(for: SlashCommandQuery(text: "t", replacementRange: NSRange(location: 4, length: 2)))
        XCTAssertEqual(madeCount, 1, "Typing after the / only filters.")
        _ = source.items(for: SlashCommandQuery(text: "", replacementRange: NSRange(location: 9, length: 1)))
        XCTAssertEqual(madeCount, 2)
        source.forgetOpenList()
        _ = source.items(for: SlashCommandQuery(text: "", replacementRange: NSRange(location: 9, length: 1)))
        XCTAssertEqual(madeCount, 3)
    }

    func testMermaidAndEmbedBlocksPlaceTheCursorWhereTheyAreFilledIn() {
        XCTAssertEqual(EditorContextMenuContent.typingPlace(inBlock: EditorContextMenuContent.mermaidBlock), NSRange(location: 11, length: 0))
        XCTAssertEqual(EditorContextMenuContent.typingPlace(inBlock: EditorContextMenuContent.embedBlock), NSRange(location: 3, length: 0))
    }

    // MARK: When the editors open them

    func testTheSlashCommandsOpenOnlyOnTypingAndStayOpenWhileTheQueryIsTheSame() {
        var tracking = EditorCompletionTracking()
        func ask(_ text: NSString, cursor: Int, followsTyping: Bool) -> CompletionContext? {
            tracking.context(in: text, cursor: cursor, textRevision: 1, offersSlashCommands: true, followsTyping: followsTyping, pluginEditorDidChange: nil)
        }
        let placed = "Notes /old" as NSString
        XCTAssertNil(ask(placed, cursor: placed.length, followsTyping: false), "Placing the cursor after a / already written opens nothing.")
        let typed = "Notes /old /t" as NSString
        XCTAssertEqual(ask(typed, cursor: typed.length, followsTyping: true), .slashCommand(SlashCommandQuery(text: "t", replacementRange: NSRange(location: 11, length: 2))))
        XCTAssertEqual(ask(typed, cursor: typed.length - 1, followsTyping: false), .slashCommand(SlashCommandQuery(text: "", replacementRange: NSRange(location: 11, length: 1))),
                       "Moving the cursor within the query keeps the list open.")
        XCTAssertNil(ask(typed, cursor: 10, followsTyping: false), "Leaving it closes it.")
        XCTAssertNil(ask(typed, cursor: typed.length, followsTyping: false), "Coming back without typing does not open it again.")
        XCTAssertNotNil(ask("/" as NSString, cursor: 1, followsTyping: true), "The first key typed in a note can be a /.")
    }

    func testEscapeForgetsTheOpenSlashCommands() {
        var tracking = EditorCompletionTracking()
        let typed = "/ta" as NSString
        XCTAssertNotNil(tracking.context(in: typed, cursor: 3, textRevision: 2, offersSlashCommands: true, followsTyping: true, pluginEditorDidChange: nil))
        tracking.forgetOpenSuggestions()
        XCTAssertNil(tracking.context(in: typed, cursor: 2, textRevision: 2, offersSlashCommands: true, pluginEditorDidChange: nil))
    }

    func testOffTheEditorsLookForNoSlashAndLinksComeFirst() {
        var tracking = EditorCompletionTracking()
        XCTAssertNil(tracking.context(in: "/ta" as NSString, cursor: 3, textRevision: 2, offersSlashCommands: false, followsTyping: true, pluginEditorDidChange: nil))
        guard case .link = tracking.context(in: "/ [[No" as NSString, cursor: 6, textRevision: 3, offersSlashCommands: true, followsTyping: true,
                                            pluginEditorDidChange: nil) else {
            return XCTFail("A link being typed is suggested as a link.")
        }
        var heardPlugins = 0
        let pluginsHeard: () -> Int? = {
            heardPlugins += 1
            return heardPlugins
        }
        XCTAssertEqual(tracking.context(in: "a /b" as NSString, cursor: 4, textRevision: 4, offersSlashCommands: true, followsTyping: true,
                                        pluginEditorDidChange: pluginsHeard),
                       .slashCommand(SlashCommandQuery(text: "b", replacementRange: NSRange(location: 2, length: 2))))
        XCTAssertEqual(heardPlugins, 0, "The slash commands come before community plugins' suggestions, as Obsidian's core plugin does.")
    }

    func testSlashCommandsIsACorePluginOnByDefault() {
        XCTAssertTrue(CorePlugin.slashCommands.isEnabledByDefault)
        XCTAssertEqual(CorePlugin.slashCommands.title, "Slash Commands")
    }
}
