/**
 * File: UiEditorMacSlashCommandsTests.swift
 * -----------------------------------------
 * Layer: Tests
 * Description: The slash commands in the Mac's note editor: typed, filtered, moved through with the arrow keys,
 *              chosen with Return, closed with Escape, and undone.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

#if os(macOS)
import AppKit
import XCTest
import GraphiteCore
@testable import GraphiteUI
import GraphiteTestSupport

/// The slash commands of Docs/Slash-menu-and-block-handles-todo.md, section 1, in the Mac
/// editor connected as `makeNSView` connects it, with keys sent as key events.
@MainActor
final class UiEditorMacSlashCommandsTests: XCTestCase {
    private var windows: [NSWindow] = []
    private var slashCommandSources: [SlashCommandSource] = []

    override func tearDown() async throws {
        for window in windows {
            window.contentView = nil
            window.orderOut(nil)
        }
        windows = []
        slashCommandSources = []
        try await super.tearDown()
    }

    /// A focused editor whose `/` lists the note's menus' entries, which act on its session.
    private func makeFocusedEditor(text: String) async throws -> (NativeMarkdownEditor.Coordinator, MarkdownMacTextView) {
        let vault = try TemporaryVault.make(prefix: "Vault", for: self).root
        try Data(text.utf8).write(to: vault.appendingPathComponent("Note.md"))
        let store = VaultStore(root: vault)
        let notePath = try VaultPath("Note.md")
        let session = try MarkdownSession(path: notePath, snapshot: try await store.read(notePath), store: store, didSave: { _ in })
        var configuration = EditorConfiguration()
        configuration.mode = .source
        let coordinator = NativeMarkdownEditor.Coordinator(session: session, configuration: configuration)
        let scrollView = MarkdownMacTextView.makeScrollableTextView()
        let textView = try XCTUnwrap(scrollView.documentView as? MarkdownMacTextView)
        textView.isRichText = false
        textView.allowsUndo = true
        textView.string = text
        textView.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
        textView.delegate = coordinator
        coordinator.connect(textView)
        coordinator.restyleEverything(in: textView)
        let noteView = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        scrollView.frame = noteView.bounds
        noteView.addSubview(scrollView)
        let window = NSWindow(contentRect: noteView.frame, styleMask: [.titled], backing: .buffered, defer: false)
        windows.append(window)
        window.contentView = noteView
        window.showInvisibly()
        window.makeFirstResponder(textView)
        session.isEditorAttached = true
        let actions = EditorContextMenuActions(
            run: { _ in }, noteState: { (session.text as NSString, session.selection) }, apply: { edit in session.apply(edit) },
            insertBlock: { block in session.insertBlockFromMenu(block) }, colors: nil, insertColor: { _, _ in }, linkToNote: {}, template: nil)
        let menus = SlashCommandSource.NoteMenus(
            actions: actions,
            entries: { actions in EditorContextMenuContent.slashMenuEntries(actions: actions, editorActions: EditorActions()) },
            commandEdit: { command, text, selection in MarkdownEditing.edit(for: command, in: text, selection: selection, indentUnit: "    ") },
            noteText: { session.text as NSString })
        let slashCommands = SlashCommandSource(menus: menus, paletteCommands: { [] })
        // The pane owns the source in the app; the note's suggestions hold it weakly.
        slashCommandSources.append(slashCommands)
        session.completion.slashCommands = slashCommands
        return (coordinator, textView)
    }

    private func press(_ characters: String, keyCode: UInt16, in textView: NSTextView) throws {
        let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                                                   windowNumber: textView.window?.windowNumber ?? 0, context: nil,
                                                   characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: keyCode))
        textView.keyDown(with: event)
    }

    /// Types each character as a key press, as the keyboard sends it.
    private func type(_ text: String, in textView: NSTextView) throws {
        for character in text {
            try press(String(character), keyCode: character == " " ? Self.spaceKeyCode : 0, in: textView)
        }
    }

    private static let returnKeyCode: UInt16 = 36
    private static let escapeKeyCode: UInt16 = 53
    private static let downArrowKeyCode: UInt16 = 125
    private static let spaceKeyCode: UInt16 = 49

    func testSlashTabThenReturnInsertsATableAndUndoGivesTheTypedQueryBack() async throws {
        let (coordinator, textView) = try await makeFocusedEditor(text: "Intro\n\n")
        let session = coordinator.session
        try type("/tab", in: textView)
        try await waitUntil("Table is listed first") { session.completion.isVisible && session.completion.items.first?.title == "Table" }
        XCTAssertGreaterThan(session.completion.caretRect.height, 0, "The list is placed at the cursor.")
        try press("\r", keyCode: Self.returnKeyCode, in: textView)
        let tableInserted = MarkdownSession.menuBlockEdit(EditorContextMenuContent.tableBlock, in: "Intro\n\n", after: 7)
        try await waitUntil("the table is inserted") { textView.string == "Intro\n\n" + tableInserted.replacement }
        XCTAssertEqual(textView.selectedRange(), tableInserted.selectionAfter, "The cursor goes to the table's first cell.")
        XCTAssertFalse(session.completion.isVisible)
        textView.undoManager?.undo()
        XCTAssertEqual(textView.string, "Intro\n\n/tab", "One undo takes the table back and gives the typed /tab back.")
    }

    func testTheArrowKeysMoveThroughTheListAndEscapeClosesIt() async throws {
        let (coordinator, textView) = try await makeFocusedEditor(text: "")
        let session = coordinator.session
        try type("/list", in: textView)
        try await waitUntil("the lists are listed") { session.completion.items.prefix(2).map(\.title) == ["Bulleted List", "Numbered List"] }
        try press(String(UnicodeScalar(NSDownArrowFunctionKey)!), keyCode: Self.downArrowKeyCode, in: textView)
        XCTAssertEqual(session.completion.selectedIndex, 1)
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 5, length: 0), "The cursor stays where it was.")
        try press("\u{1b}", keyCode: Self.escapeKeyCode, in: textView)
        XCTAssertFalse(session.completion.isVisible)
        try press("\r", keyCode: Self.returnKeyCode, in: textView)
        XCTAssertEqual(textView.string, "/list\n", "With the list closed, Return is Return.")
        try type("/list", in: textView)
        try await waitUntil("typing opens it again") { session.completion.items.prefix(2).map(\.title) == ["Bulleted List", "Numbered List"] }
        try press(String(UnicodeScalar(NSDownArrowFunctionKey)!), keyCode: Self.downArrowKeyCode, in: textView)
        try press("\r", keyCode: Self.returnKeyCode, in: textView)
        try await waitUntil("the second entry runs") { textView.string == "/list\n1. " }
    }

    func testASpaceClosesTheListAndPlacingTheCursorAfterASlashOpensNothing() async throws {
        let (coordinator, textView) = try await makeFocusedEditor(text: "See /path here")
        let session = coordinator.session
        textView.setSelectedRange(NSRange(location: 9, length: 0))
        XCTAssertNil(session.completion.context, "Only typing opens the slash commands.")
        textView.setSelectedRange(NSRange(location: 14, length: 0))
        try type(" /ca", in: textView)
        try await waitUntil("the list shows") { session.completion.isVisible }
        try type(" ", in: textView)
        XCTAssertNil(session.completion.context, "A space closes it.")
        XCTAssertEqual(textView.string, "See /path here /ca ")
    }

    func testOffTheSlashIsJustTyped() async throws {
        let (coordinator, textView) = try await makeFocusedEditor(text: "")
        coordinator.session.completion.slashCommands = nil
        try type("/tab", in: textView)
        XCTAssertNil(coordinator.session.completion.context)
        try press("\r", keyCode: Self.returnKeyCode, in: textView)
        XCTAssertEqual(textView.string, "/tab\n")
    }
}
#endif
