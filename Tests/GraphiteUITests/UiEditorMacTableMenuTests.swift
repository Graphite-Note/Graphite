/**
 * File: UiEditorMacTableMenuTests.swift
 * -------------------------------------
 * Layer: Tests
 * Description: In the Mac's Live Preview, a table's cell menu offers Obsidian's items and sorts the note's rows as one
 *              undoable edit; the Edit menu's Table submenu offers them for the cell being edited, with the shortcut
 *              Settings › Keyboard Shortcuts gives them.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 12/11/2026
 */

#if os(macOS)
import AppKit
import SwiftUI
import XCTest
import GraphiteCore
@testable import GraphiteUI
import GraphiteTestSupport

/// The table's view in the Mac's own text view, in a window shown invisibly, its menu asked for
/// as a secondary click asks for it.
@MainActor
final class UiEditorMacTableMenuTests: XCTestCase {
    private var windows: [NSWindow] = []

    override func tearDown() async throws {
        for window in windows {
            window.orderOut(nil)
            window.contentView = nil
        }
        windows = []
        try await super.tearDown()
    }

    private static let tableNote = "Intro line\n\n| Year | Rate |\n| --- | --- |\n| 2024 | 2.0 |\n| 2025 | 1.8 |\n\nAfter the table\n"

    private func makeEditor(text: String) async throws -> (NativeMarkdownEditor.Coordinator, MarkdownMacTextView, MarkdownSession) {
        let vault = try TemporaryVault.make(prefix: "Vault", for: self).root
        try Data(text.utf8).write(to: vault.appendingPathComponent("Note.md"))
        let store = VaultStore(root: vault)
        let notePath = try VaultPath("Note.md")
        let session = try MarkdownSession(path: notePath, snapshot: try await store.read(notePath), store: store, didSave: { _ in })
        var configuration = EditorConfiguration()
        configuration.mode = .livePreview
        let coordinator = NativeMarkdownEditor.Coordinator(session: session, configuration: configuration)
        coordinator.environment = LivePreviewEnvironment(root: vault, textSize: 17, colorsEnabled: true, paletteHexByName: [:], drawingVersion: 0,
                                                         resolve: { _, _ in nil }, open: { _ in }, follow: { _, _ in }, updateProperties: nil)
        let scrollView = MarkdownMacTextView.makeScrollableTextView()
        let textView = try XCTUnwrap(scrollView.documentView as? MarkdownMacTextView)
        textView.isRichText = false
        textView.allowsUndo = true
        textView.textContainerInset = CGSize(width: 32, height: 32)
        textView.string = text
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        textView.delegate = coordinator
        coordinator.connect(textView)
        coordinator.restyleEverything(in: textView)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 500), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        windows.append(window)
        window.contentView = scrollView
        window.showInvisibly()
        window.makeFirstResponder(textView)
        scrollView.frame = NSRect(x: 0, y: 0, width: 700, height: 500)
        textView.frame.size.width = 700
        scrollView.layoutSubtreeIfNeeded()
        return (coordinator, textView, session)
    }

    private func tableView(in textView: NSTextView) -> NSView? {
        textView.subviews.first { subview in subview is NSHostingView<AnyView> }
    }

    private func awaitConditionAfterLayout(_ description: String, timeoutSeconds: TimeInterval = 5, _ condition: () -> Bool) async throws {
        try await waitUntil(description, timeoutSeconds: timeoutSeconds) {
            windows.forEach { window in window.contentView?.layoutSubtreeIfNeeded(); window.displayIfNeeded() }
            return condition()
        }
    }

    /// A point in the first column of the table's first body row, in the table view: the
    /// header and two body rows are about as tall as each other.
    private func pointInFirstBodyCell(of tableView: NSView) -> CGPoint {
        CGPoint(x: 40, y: tableView.isFlipped ? tableView.bounds.height * 0.45 : tableView.bounds.height * 0.55)
    }

    func testTheCellMenuOffersObsidiansItemsAndSortsTheNotesRows() async throws {
        let (coordinator, textView, session) = try await makeEditor(text: Self.tableNote)
        defer { withExtendedLifetime(coordinator) {} }
        try await awaitConditionAfterLayout("The table is drawn") { self.tableView(in: textView) != nil }
        let tableView = try XCTUnwrap(tableView(in: textView) as? RenderedBlockHostingView)
        let window = try XCTUnwrap(tableView.window)
        let point = tableView.convert(pointInFirstBodyCell(of: tableView), to: nil)
        let rightClick = try XCTUnwrap(NSEvent.mouseEvent(with: .rightMouseDown, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                                          windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        let menu = try XCTUnwrap(tableView.menu(for: rightClick))
        XCTAssertEqual(menu.items.map(\.title), ["Row", "Column", "Sort by column (A to Z)", "Sort by column (Z to A)", "", "Edit Source"])
        XCTAssertEqual(menu.items[0].submenu?.items.map(\.title), ["Add row above", "Add row below", "Move row up", "Move row down", "Duplicate row", "Delete row"])
        XCTAssertEqual(menu.items[1].submenu?.items.filter { item in item.title.hasPrefix("Align") }.map(\.state), [.off, .off, .off])

        menu.performActionForItem(at: 3)
        XCTAssertEqual(textView.string, Self.tableNote.replacingOccurrences(of: "| 2024 | 2.0 |\n| 2025 | 1.8 |\n", with: "| 2025 | 1.8 |\n| 2024 | 2.0 |\n"))
        XCTAssertNil(session.blockViews.tableCellCommandTarget, "A menu opened without editing a cell gives the palette nothing.")
        textView.undoManager?.undo()
        XCTAssertEqual(textView.string, Self.tableNote, "The sort is one edit.")
    }

    /// Begins editing the first body row's first cell, with the table's editor given what the
    /// note's editor gives the table's view (`NativeMarkdownEditor.Coordinator.widgetRootView`):
    /// its edits go through the text view, and a cell beginning editing offers its commands to
    /// the note. Clicks sent to a test window do not reach SwiftUI's tap on the table.
    private func editFirstBodyCell(coordinator: NativeMarkdownEditor.Coordinator, textView: MarkdownMacTextView,
                                   session: MarkdownSession) throws -> LivePreviewTableEditor {
        let block = try XCTUnwrap(LivePreviewBlockScanner.blocks(in: textView.string as NSString).first { block in block.kind == .table })
        let key = try XCTUnwrap(LivePreviewBlockKey.keys(for: [block]).first)
        let editor = LivePreviewTableEditor()
        let sourceEditing = RenderedBlockSourceEditing(replaceSource: { [weak coordinator, weak textView] editor, transform in
            guard let coordinator, let textView else { return }
            coordinator.replaceSource(ofBlockWithKey: key, editedBy: editor, using: transform, in: textView)
        }, setIsEditingInView: { [weak coordinator] isEditing, editor in
            guard let coordinator else { return }
            if isEditing {
                coordinator.styling.renderedBlocks.beginEditingInView(blockWithKey: key, at: block.range.location, owner: editor)
            } else {
                coordinator.styling.renderedBlocks.endEditingInView(owner: editor)
            }
        }, offerCellCommands: { [weak session] target in session?.blockViews.takeTableCellCommands(target) })
        editor.update(source: block.sourceLines, textSize: 17, sourceEditing: sourceEditing)
        editor.beginEditing(TableCellPosition(row: 1, column: 0))
        return editor
    }

    /// The Edit menu's Table submenu as SwiftUI makes it into an AppKit menu: the same view the
    /// menu bar's Edit menu holds (`GraphiteCommands.textEditingItems`), in a view's menu, which
    /// a test can open without the app's menu bar.
    private func editMenu(target: TableCellCommandTarget?, shortcut: @escaping (GraphiteCommand) -> KeyboardShortcut?) throws -> NSMenu {
        let hosting = NSHostingView(rootView: Text("Note").frame(width: 200, height: 100).contentShape(Rectangle()).contextMenu {
            TableCellCommandsMenu(target: target, shortcut: shortcut)
        })
        hosting.frame = CGRect(x: 0, y: 0, width: 200, height: 100)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        windows.append(window)
        window.contentView = hosting
        window.showInvisibly()
        hosting.layoutSubtreeIfNeeded()
        let rightClick = try XCTUnwrap(NSEvent.mouseEvent(with: .rightMouseDown, location: CGPoint(x: 100, y: 50), modifierFlags: [], timestamp: 0,
                                                          windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        let menu = try XCTUnwrap(hosting.menu(for: rightClick), "The view has the Table submenu as its menu.")
        let table = try XCTUnwrap(menu.items.first { item in item.title == "Table" }?.submenu, "The Edit menu has Table.")
        table.update()
        table.items.compactMap(\.submenu).forEach { submenu in submenu.update() }
        return table
    }

    private func item(_ title: String, in menu: NSMenu) -> NSMenuItem? {
        menu.items.first { item in item.title == title } ?? menu.items.lazy.compactMap(\.submenu).compactMap { submenu in self.item(title, in: submenu) }.first
    }

    private func choose(_ item: NSMenuItem) throws {
        let menu = try XCTUnwrap(item.menu)
        menu.performActionForItem(at: menu.index(of: item))
    }

    /// While a cell is edited, Edit › Table shows the cell's commands, those that cannot apply
    /// dimmed, and choosing one changes the note's source as one undoable edit.
    func testEditTableShowsTheEditedCellsCommandsAndChoosingOneChangesTheNote() async throws {
        let (coordinator, textView, session) = try await makeEditor(text: Self.tableNote)
        defer { withExtendedLifetime(coordinator) {} }
        let noCell = try editMenu(target: session.blockViews.tableCellCommandTarget, shortcut: { _ in nil })
        XCTAssertNil(session.blockViews.tableCellCommandTarget)
        XCTAssertEqual(noCell.items.map(\.title), ["Row", "Column", "Sort by column (A to Z)", "Sort by column (Z to A)"])
        XCTAssertFalse(try XCTUnwrap(item("Sort by column (A to Z)", in: noCell)).isEnabled, "Nothing to act on before a cell is edited.")

        let editor = try editFirstBodyCell(coordinator: coordinator, textView: textView, session: session)
        let target = try XCTUnwrap(session.blockViews.tableCellCommandTarget, "The cell being edited offers its commands.")
        defer { withExtendedLifetime(editor) {} }
        XCTAssertTrue(target.editor === editor)
        let menu = try editMenu(target: target, shortcut: { _ in nil })
        XCTAssertEqual(menu.items.map(\.title), ["Row", "Column", "Sort by column (A to Z)", "Sort by column (Z to A)"])
        XCTAssertEqual(menu.items[0].submenu?.items.map(\.title), ["Add row above", "Add row below", "Move row up", "Move row down", "Duplicate row", "Delete row"])
        XCTAssertEqual(menu.items[1].submenu?.items.map(\.title), ["Add column to the left", "Add column to the right", "Move column left", "Move column right",
                                                                   "Align left", "Align center", "Align right", "Duplicate column", "Delete column"])
        XCTAssertFalse(try XCTUnwrap(item("Move row up", in: menu)).isEnabled, "The first body row cannot move up.")
        XCTAssertTrue(try XCTUnwrap(item("Move row down", in: menu)).isEnabled)

        try choose(try XCTUnwrap(item("Move row down", in: menu)))
        let moved = Self.tableNote.replacingOccurrences(of: "| 2024 | 2.0 |\n| 2025 | 1.8 |\n", with: "| 2025 | 1.8 |\n| 2024 | 2.0 |\n")
        XCTAssertEqual(textView.string, moved)
        textView.undoManager?.undo()
        XCTAssertEqual(textView.string, Self.tableNote, "The command is one edit.")
    }

    /// A shortcut given in Settings › Keyboard Shortcuts, written to the vault's hotkeys file,
    /// is the Table submenu item's key equivalent, and pressing it runs the command.
    func testAShortcutAssignedInSettingsRunsATableCommand() async throws {
        let (coordinator, textView, session) = try await makeEditor(text: Self.tableNote)
        defer { withExtendedLifetime(coordinator) {} }
        let shortcuts = VaultKeyboardShortcuts(platform: .macOS)
        XCTAssertNil(shortcuts.menuShortcut(for: .tableSortDescending), "No table command has a shortcut by default.")
        let combination = KeyCombination([.command, .control, .option], .character("Z"))
        try await shortcuts.apply(.assign(combination, commandIdentifier: GraphiteCommand.tableSortDescending.identifier), pluginCommands: [],
                                  in: VaultStore(root: session.vaultRoot))
        XCTAssertEqual(shortcuts.menuShortcut(for: .tableSortDescending), KeyboardShortcut("z", modifiers: [.command, .control, .option]))

        let editor = try editFirstBodyCell(coordinator: coordinator, textView: textView, session: session)
        defer { withExtendedLifetime(editor) {} }
        let menu = try editMenu(target: session.blockViews.tableCellCommandTarget, shortcut: shortcuts.menuShortcut)
        let sortItem = try XCTUnwrap(item("Sort by column (Z to A)", in: menu))
        XCTAssertEqual(sortItem.keyEquivalent.lowercased(), "z")
        XCTAssertEqual(sortItem.keyEquivalentModifierMask.intersection([.command, .control, .option, .shift]), [.command, .control, .option])
        XCTAssertEqual(try XCTUnwrap(item("Sort by column (A to Z)", in: menu)).keyEquivalent, "", "Commands without a shortcut keep none.")

        let window = try XCTUnwrap(textView.window)
        let press = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.command, .control, .option], timestamp: 0,
                                                   windowNumber: window.windowNumber, context: nil, characters: "z", charactersIgnoringModifiers: "z",
                                                   isARepeat: false, keyCode: 6))
        XCTAssertTrue(menu.performKeyEquivalent(with: press), "The shortcut is the item's.")
        let sorted = Self.tableNote.replacingOccurrences(of: "| 2024 | 2.0 |\n| 2025 | 1.8 |\n", with: "| 2025 | 1.8 |\n| 2024 | 2.0 |\n")
        try await awaitConditionAfterLayout("The rows are sorted from Z to A") { textView.string == sorted }
    }

    /// A table indented under a list item is a table of its own, its cells edited in place and
    /// its menu the same.
    func testATableInAListItemGetsTheSameMenu() async throws {
        let note = "- Item\n\n  | Year | Rate |\n  | --- | --- |\n  | 2024 | 2.0 |\n  | 2025 | 1.8 |\n\nAfter\n"
        let (coordinator, textView, _) = try await makeEditor(text: note)
        defer { withExtendedLifetime(coordinator) {} }
        try await awaitConditionAfterLayout("The table is drawn") { self.tableView(in: textView) != nil }
        let tableView = try XCTUnwrap(tableView(in: textView) as? RenderedBlockHostingView)
        let menu = try XCTUnwrap(tableView.blockMenu?.makeMenu(at: pointInFirstBodyCell(of: tableView), isFlipped: tableView.isFlipped, height: tableView.bounds.height))
        XCTAssertEqual(menu.items.map(\.title), ["Row", "Column", "Sort by column (A to Z)", "Sort by column (Z to A)", "", "Edit Source"])
        menu.performActionForItem(at: 3)
        XCTAssertEqual(textView.string, note.replacingOccurrences(of: "  | 2024 | 2.0 |\n  | 2025 | 1.8 |\n", with: "  | 2025 | 1.8 |\n  | 2024 | 2.0 |\n"))
    }
}
#endif
