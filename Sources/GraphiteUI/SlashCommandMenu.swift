/**
 * File: SlashCommandMenu.swift
 * ----------------------------
 * Layer: UI
 * Description: What a `/` lists in a note: the Paragraph, Insert and Format entries of the note's menus, then the
 *              command palette's commands, ranked as typed; choosing one takes out the `/query` with the entry's
 *              own edit, as one edit.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

import Foundation
import SwiftUI
import GraphiteCore

/// One entry a `/` lists: an item of the note's menus or a command of the command palette.
struct SlashCommandEntry {
    /// What choosing the entry does.
    enum Action {
        /// A menu item: its edit is made on the note with the `/query` taken out, as one edit
        /// with it (`SlashCommandEditRecorder`); an item that opens a dialog opens it.
        case menuItem(@MainActor () -> Void)
        /// A palette command, run once the `/query` is taken out.
        case command(@MainActor () -> Void)
    }

    let identifier: String
    let title: String
    let systemImage: String
    var shortcut: String?
    let action: Action
}

/// The entries a `/` lists in one note, made from the pane that shows it (`MarkdownPane`) and
/// kept by its editor (`EditorActions.slashCommands`). They are made when the list opens and
/// kept while the same `/` is being typed after, so each letter only filters them.
@MainActor
final class SlashCommandSource {
    /// What the pane's menus need to make the entries, and the note they act on.
    struct NoteMenus {
        /// The pane's own menu actions, whose dialogs the entries open.
        let actions: EditorContextMenuActions
        /// The note's Paragraph, Insert and Format entries made with the given actions
        /// (`EditorContextMenuContent.slashMenuEntries`).
        let entries: (EditorContextMenuActions) -> [EditorContextMenuEntry]
        /// The edit a text command makes, with the vault's indentation.
        let commandEdit: (EditorCommand, NSString, NSRange) -> MarkdownTextEdit?
        /// The note's text now, which the `/query` is taken out of.
        let noteText: () -> NSString
    }

    private let menus: NoteMenus
    private let makePaletteCommands: () -> [PaletteCommand]
    private let recorder = SlashCommandEditRecorder()
    /// The entries made for the `/` at this location, the list now open.
    private var entriesOfOpenList: (slashLocation: Int, entries: [SlashCommandEntry])?

    /// - Parameter paletteCommands: The window's command palette commands; none where no window offers them.
    init(menus: NoteMenus, paletteCommands: @escaping () -> [PaletteCommand]) {
        self.menus = menus
        makePaletteCommands = paletteCommands
    }

    func items(for query: SlashCommandQuery) -> [CompletionItem] {
        let slashLocation = query.replacementRange.location
        let entries: [SlashCommandEntry]
        if let entriesOfOpenList, entriesOfOpenList.slashLocation == slashLocation {
            entries = entriesOfOpenList.entries
        } else {
            let recordingActions = recorder.actions(passingOn: menus.actions, commandEdit: menus.commandEdit)
            entries = SlashCommandList.entries(menuEntries: menus.entries(recordingActions), paletteCommands: makePaletteCommands())
            entriesOfOpenList = (slashLocation, entries)
        }
        return SlashCommandList.items(for: query, entries: entries, recorder: recorder, noteText: menus.noteText)
    }

    /// Lets the next list make its entries again, as menus and commands change between lists.
    func forgetOpenList() {
        entriesOfOpenList = nil
    }
}

/// The menus' actions for the slash commands. A menu item chosen there edits the note through
/// the same actions as from a menu, but the slash commands must also take out the `/query`, and
/// as two edits Undo would take back the block and leave the note without the `/query` typed.
/// So the item runs on the note as it is once the `/query` is out, and the edit it asks for is
/// kept and made together with the removal, as one edit one Undo takes back.
@MainActor
final class SlashCommandEditRecorder {
    private var noteState = (text: "" as NSString, selection: NSRange(location: 0, length: 0))
    private var recordedEdit: MarkdownTextEdit?

    /// Actions that keep the edits asked for and pass the dialogs (a link, a template) on to `menuActions`.
    func actions(passingOn menuActions: EditorContextMenuActions,
                 commandEdit: @escaping (EditorCommand, NSString, NSRange) -> MarkdownTextEdit?) -> EditorContextMenuActions {
        EditorContextMenuActions(
            run: { [weak self] command in
                guard let self else { return }
                recordedEdit = commandEdit(command, noteState.text, noteState.selection)
            },
            noteState: { [weak self] in self?.noteState ?? ("" as NSString, NSRange(location: 0, length: 0)) },
            apply: { [weak self] edit in self?.recordedEdit = edit },
            insertBlock: { [weak self] block in
                guard let self else { return }
                recordedEdit = MarkdownSession.menuBlockEdit(block, in: noteState.text, after: NSMaxRange(noteState.selection))
            },
            colors: nil, insertColor: menuActions.insertColor, linkToNote: menuActions.linkToNote, template: menuActions.template)
    }

    /// Runs a menu item on `text` with the cursor at `cursor`, and returns the edit it asked
    /// for; nil when it edits nothing by itself, as an item that opens a dialog.
    func edit(running perform: @MainActor () -> Void, on text: NSString, cursor: Int) -> MarkdownTextEdit? {
        noteState = (text, NSRange(location: cursor, length: 0))
        recordedEdit = nil
        perform()
        defer { recordedEdit = nil }
        return recordedEdit
    }
}

/// The rules of the slash commands' list, built and tested from plain values.
@MainActor
enum SlashCommandList {
    /// The symbol of the menus' entries that have none, the headings.
    static let headingSymbol = "number"

    /// The menus' entries that can be chosen, in the menus' order, then the palette's
    /// commands, without those that do what a menu entry does
    /// (`WorkspaceCommandList.commandsTheInsertMenuAlsoOffers`).
    static func entries(menuEntries: [EditorContextMenuEntry], paletteCommands: [PaletteCommand]) -> [SlashCommandEntry] {
        var entries: [SlashCommandEntry] = []
        appendActions(of: menuEntries, to: &entries)
        for command in paletteCommands where !WorkspaceCommandList.commandsTheInsertMenuAlsoOffers.contains(command.id) {
            entries.append(SlashCommandEntry(identifier: "palette-" + command.id, title: command.title, systemImage: command.systemImage,
                                             shortcut: command.shortcut, action: .command({ command.run() })))
        }
        return entries
    }

    private static func appendActions(of menuEntries: [EditorContextMenuEntry], to entries: inout [SlashCommandEntry]) {
        for menuEntry in menuEntries {
            switch menuEntry.content {
            case .action(let isEnabled, let perform):
                guard isEnabled else { continue }
                entries.append(SlashCommandEntry(identifier: "menu-\(entries.count)-" + menuEntry.title, title: menuEntry.title,
                                                 systemImage: menuEntry.systemImage ?? headingSymbol, action: .menuItem(perform)))
            case .submenu(let children), .group(let children):
                appendActions(of: children, to: &entries)
            }
        }
    }

    /// Every entry for an empty query, in order; else the entries whose titles match it, best
    /// first, as the command palette ranks them, equal scores keeping their order.
    static func ranked(_ entries: [SlashCommandEntry], query: String) -> [(entry: SlashCommandEntry, match: FuzzyMatcher.Match?)] {
        guard !query.isEmpty else { return entries.map { entry in (entry, nil) } }
        let matched = entries.enumerated().compactMap { position, entry in
            FuzzyMatcher.match(query, in: entry.title).map { match in (position: position, entry: entry, match: match) }
        }
        return matched.sorted { leftMatch, rightMatch in
            leftMatch.match.score != rightMatch.match.score ? leftMatch.match.score > rightMatch.match.score : leftMatch.position < rightMatch.position
        }.map { candidate in (candidate.entry, candidate.match) }
    }

    /// The popup's rows. Choosing one takes out the `/query` typed now: with a menu item's edit
    /// as one edit, or before a command runs.
    static func items(for query: SlashCommandQuery, entries: [SlashCommandEntry], recorder: SlashCommandEditRecorder,
                      noteText: @escaping () -> NSString) -> [CompletionItem] {
        ranked(entries, query: query.text).map { entry, match in
            var runAfterEdits: (@MainActor () -> Void)?
            if case .command(let run) = entry.action { runAfterEdits = run }
            return CompletionItem(id: entry.identifier, title: entry.title, titleHighlights: match?.matchedRanges ?? [], systemImage: entry.systemImage,
                                  makeEdits: { context in
                                      guard case .slashCommand(let currentQuery) = context else { return [] }
                                      return edits(choosing: entry, for: currentQuery, in: noteText(), recorder: recorder)
                                  }, shortcut: entry.shortcut, runAfterEdits: runAfterEdits)
        }
    }

    /// The edits choosing `entry` makes for `query` typed in `text`: none when the query is
    /// no longer there as typed.
    static func edits(choosing entry: SlashCommandEntry, for query: SlashCommandQuery, in text: NSString,
                      recorder: SlashCommandEditRecorder) -> [MarkdownTextEdit] {
        let range = query.replacementRange
        guard NSMaxRange(range) <= text.length, text.substring(with: range) == "/" + query.text else { return [] }
        let removal = removal(of: query)
        guard case .menuItem(let perform) = entry.action else { return [removal] }
        let textAfterRemoval = text.replacingCharacters(in: range, with: "") as NSString
        guard let edit = recorder.edit(running: perform, on: textAfterRemoval, cursor: range.location) else { return [removal] }
        return [combined(removal, then: edit, in: text)]
    }

    /// Takes out the `/` and the letters after it, leaving the cursor where the `/` was.
    static func removal(of query: SlashCommandQuery) -> MarkdownTextEdit {
        MarkdownTextEdit(range: query.replacementRange, replacement: "",
                         selectionAfter: NSRange(location: query.replacementRange.location, length: 0))
    }

    /// `removal`, then `edit` made on the text it leaves, as one edit of `text`: from where the
    /// first starts to where the last ends, with the cursor where `edit` leaves it.
    static func combined(_ removal: MarkdownTextEdit, then edit: MarkdownTextEdit, in text: NSString) -> MarkdownTextEdit {
        let afterRemoval = text.replacingCharacters(in: removal.range, with: removal.replacement) as NSString
        let final = afterRemoval.replacingCharacters(in: edit.range, with: edit.replacement) as NSString
        let shift = removal.replacement.utf16.count - removal.range.length
        // Where the edit ends in `text`: past the removal, its places are moved back by it.
        let editEnd = NSMaxRange(edit.range) >= removal.range.location + removal.replacement.utf16.count
            ? NSMaxRange(edit.range) - shift : NSMaxRange(edit.range)
        let start = min(removal.range.location, edit.range.location)
        let end = max(NSMaxRange(removal.range), editEnd)
        let unchangedTailLength = text.length - end
        let replacement = final.substring(with: NSRange(location: start, length: final.length - unchangedTailLength - start))
        return MarkdownTextEdit(range: NSRange(location: start, length: end - start), replacement: replacement, selectionAfter: edit.selectionAfter)
    }
}

/// The command palette's commands of the window a note is shown in, for the note's slash
/// commands. The window sets them once it is shown (`WindowPaletteCommandsOffer`); the reference
/// stays the same for the window's life, so handing it down never updates the views below.
@MainActor
final class WindowPaletteCommands {
    private var makeCommands: () -> [PaletteCommand] = { [] }

    func offer(_ makeCommands: @escaping () -> [PaletteCommand]) {
        self.makeCommands = makeCommands
    }

    func commands() -> [PaletteCommand] { makeCommands() }
}

/// Hands the window's command palette commands to the notes below (`WindowPaletteCommands`),
/// as the command palette lists them for the window's width.
struct WindowPaletteCommandsOffer: ViewModifier {
    /// False in a compact width, as for the command palette (`WorkspaceCommandList.commands`).
    let offersSplit: Bool
    /// The window's commands, as the command palette lists them.
    let commands: (_ offersSplit: Bool) -> [PaletteCommand]
    @State private var windowPaletteCommands = WindowPaletteCommands()

    func body(content: Content) -> some View {
        content
            .environment(\.windowPaletteCommands, windowPaletteCommands)
            .onChange(of: offersSplit, initial: true) { _, offersSplit in
                windowPaletteCommands.offer { [commands] in commands(offersSplit) }
            }
    }
}

extension EnvironmentValues {
    /// The command palette's commands of the window, for the slash commands of its notes.
    @Entry var windowPaletteCommands: WindowPaletteCommands? = nil
}
