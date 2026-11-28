/**
 * File: TableCellMacFieldKeysTests.swift
 * --------------------------------------
 * Layer: Tests
 * Description: The keys of a Live Preview table's cell on the Mac, sent to the cell's real text field and its field editor as AppKit
 *              sends them: Tab, Shift-Tab, Return, Escape, the arrows inside a cell and at its edges, Shift-arrows, Backspace on
 *              selected cells, ⌘Z and ⇧⌘Z, ⌘C, ⌘X and ⌘V.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 27/11/2026
 */
#if os(macOS)
import AppKit
import SwiftUI
import XCTest
import GraphiteCore
import GraphiteTestSupport
@testable import GraphiteUI

@MainActor
final class TableCellMacFieldKeysTests: XCTestCase {
    private var window: NSWindow?
    private var note = ""
    private var undos: [Bool] = []
    private var caretSides: [RenderedBlockSide] = []
    private let editor = LivePreviewTableEditor()
    private var host: NSHostingView<AnyView>?

    private static let note = "Intro\n\n| Name | Value |\n| ---- | :---: |\n| alpha | 1 |\n| beta | 2 |\n\nAfter\n"

    override func setUp() async throws {
        try await super.setUp()
        note = Self.note
        editor.pasteboard = TablePasteboard(name: "TableCellMacFieldKeysTests-\(UUID().uuidString)")
        viewUpdates()
    }

    override func tearDown() async throws {
        window?.orderOut(nil)
        window?.contentView = nil
        window = nil
        try await super.tearDown()
    }

    private var tableBlock: LivePreviewBlock? {
        LivePreviewBlockScanner.blocks(in: note as NSString).first { block in block.kind == .table }
    }

    /// What the note's editor gives the table's editor at each update, as `LivePreviewTableKeysAndSelectionTests` does.
    private func viewUpdates() {
        guard let block = tableBlock else { return }
        editor.update(source: block.sourceLines, textSize: 16, sourceEditing: RenderedBlockSourceEditing(replaceSource: { [unowned self] _, transform in
            guard let block = self.tableBlock else { return }
            let source = self.note as NSString
            guard let replacement = transform(source.substring(with: block.range)) else { return }
            self.note = source.replacingCharacters(in: block.range, with: replacement)
            self.viewUpdates()
        }, setIsEditingInView: { _, _ in }, placeCaretBesideBlock: { [unowned self] _, side in self.caretSides.append(side) },
           undoInNote: { [unowned self] isRedo in self.undos.append(isRedo) }))
    }

    /// The cell's field as the editing layer makes it, in a window of its own, with the keyboard.
    private func fieldEditor(editing cell: TableCellPosition) async throws -> (TableCellMacTextField, NSTextView) {
        editor.beginEditing(cell)
        if host == nil {
            let editor = editor
            let view = CellField(editor: editor).frame(width: 240)
            let host = NSHostingView(rootView: AnyView(view))
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 240, height: 80), styleMask: [.titled], backing: .buffered, defer: true)
            window.isReleasedWhenClosed = false
            window.contentView = host
            self.window = window
            self.host = host
        }
        var found: (TableCellMacTextField, NSTextView)?
        try await waitUntil("the cell's field takes the keyboard", timeoutSeconds: 5) {
            self.host?.layoutSubtreeIfNeeded()
            guard let field = self.host.flatMap(Self.cellField(in:)), let fieldEditor = field.currentEditor() as? NSTextView,
                  fieldEditor.string == self.editor.draftText else { return false }
            found = (field, fieldEditor)
            return true
        }
        return try XCTUnwrap(found)
    }

    private struct CellField: View {
        @Bindable var editor: LivePreviewTableEditor
        var body: some View {
            TableCellTextField(text: $editor.draftText, font: .systemFont(ofSize: 16), focusRequest: editor.focusRequest, caret: { [editor] in editor.caret },
                               handleKey: editor.handle, actions: editor.fieldActions, hidesCaret: editor.hasCellSelection, focusDidChange: { _ in })
        }
    }

    private static func cellField(in view: NSView) -> TableCellMacTextField? {
        if let field = view as? TableCellMacTextField { return field }
        return view.subviews.lazy.compactMap(cellField(in:)).first
    }

    private func keyEquivalent(_ characters: String, _ modifiers: NSEvent.ModifierFlags) throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0, windowNumber: window?.windowNumber ?? 0,
                                       context: nil, characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: 0))
    }

    func testTabShiftTabReturnAndEscape() async throws {
        let (_, fieldEditor) = try await fieldEditor(editing: TableCellPosition(row: 1, column: 0))
        fieldEditor.doCommand(by: #selector(NSResponder.insertTab(_:)))
        XCTAssertEqual(editor.editingCell, TableCellPosition(row: 1, column: 1))
        XCTAssertEqual(fieldEditor.string, "1", "The next cell's text is in the field at once.")
        XCTAssertEqual(fieldEditor.selectedRange(), NSRange(location: 0, length: 1), "Tab selects the whole text of the cell it goes to.")
        fieldEditor.doCommand(by: #selector(NSResponder.insertBacktab(_:)))
        XCTAssertEqual(editor.editingCell, TableCellPosition(row: 1, column: 0))
        XCTAssertEqual(fieldEditor.selectedRange(), NSRange(location: 0, length: 5))
        fieldEditor.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        XCTAssertEqual(editor.editingCell, TableCellPosition(row: 2, column: 0), "Return goes to the cell below.")
        fieldEditor.doCommand(by: #selector(NSResponder.cancelOperation(_:)))
        XCTAssertNil(editor.editingCell, "Escape closes the editor.")
    }

    func testShiftReturnPutsALineBreakInTheCell() async throws {
        let (_, fieldEditor) = try await fieldEditor(editing: TableCellPosition(row: 1, column: 0))
        fieldEditor.doCommand(by: #selector(NSResponder.insertLineBreak(_:)))
        XCTAssertEqual(editor.editingCell, TableCellPosition(row: 1, column: 0))
        XCTAssertEqual(fieldEditor.string, "alpha\n")
    }

    func testArrowsMoveInsideACellAndLeaveItOnlyAtItsEdges() async throws {
        let (_, fieldEditor) = try await fieldEditor(editing: TableCellPosition(row: 1, column: 0))
        fieldEditor.setSelectedRange(NSRange(location: 2, length: 0))
        XCTAssertFalse(editor.handleArrowFromField(fieldEditor, #selector(NSResponder.moveLeft(_:))), "Inside the text, Left is the text's.")
        fieldEditor.setSelectedRange(NSRange(location: 5, length: 0))
        fieldEditor.doCommand(by: #selector(NSResponder.moveRight(_:)))
        XCTAssertEqual(editor.editingCell, TableCellPosition(row: 1, column: 1), "Right at the end goes to the next cell.")
        XCTAssertEqual(fieldEditor.selectedRange(), NSRange(location: 0, length: 0), "Its caret at the start.")
        fieldEditor.doCommand(by: #selector(NSResponder.moveLeft(_:)))
        XCTAssertEqual(editor.editingCell, TableCellPosition(row: 1, column: 0))
        XCTAssertEqual(fieldEditor.selectedRange(), NSRange(location: 5, length: 0), "Left at the start goes to the end of the cell before.")
        fieldEditor.doCommand(by: #selector(NSResponder.moveUp(_:)))
        XCTAssertEqual(editor.editingCell, TableCellPosition(row: 0, column: 0))
        fieldEditor.doCommand(by: #selector(NSResponder.moveUp(_:)))
        XCTAssertNil(editor.editingCell, "Up from the header leaves the table.")
        XCTAssertEqual(caretSides, [.before])
    }

    func testShiftArrowsSelectCellsAndBackspaceEmptiesThem() async throws {
        let (_, fieldEditor) = try await fieldEditor(editing: TableCellPosition(row: 1, column: 1))
        fieldEditor.setSelectedRange(NSRange(location: 1, length: 0))
        fieldEditor.doCommand(by: #selector(NSResponder.moveDownAndModifySelection(_:)))
        XCTAssertEqual(editor.selectedRange, MarkdownTableCellRange(rows: 1...2, columns: 1...1), "Shift-Down on the cell's last line starts a rectangle.")
        fieldEditor.doCommand(by: #selector(NSResponder.moveLeftAndModifySelection(_:)))
        XCTAssertEqual(editor.selectedRange, MarkdownTableCellRange(rows: 1...2, columns: 0...1), "While cells are selected the arrows grow it.")
        fieldEditor.doCommand(by: #selector(NSResponder.moveRightAndModifySelection(_:)))
        XCTAssertEqual(editor.selectedRange, MarkdownTableCellRange(rows: 1...2, columns: 1...1), "And shrink it.")
        fieldEditor.insertText("x", replacementRange: fieldEditor.selectedRange())
        XCTAssertEqual(editor.draftText, "1", "Typing is off while cells are selected.")
        fieldEditor.doCommand(by: #selector(NSResponder.deleteBackward(_:)))
        XCTAssertEqual(note, "Intro\n\n| Name | Value |\n| ---- | :---: |\n| alpha |  |\n| beta |  |\n\nAfter\n")
    }

    func testCommandZAndShiftCommandZWriteTheTypingThenUndoTheNote() async throws {
        let (field, fieldEditor) = try await fieldEditor(editing: TableCellPosition(row: 2, column: 0))
        fieldEditor.insertText("!", replacementRange: NSRange(location: 4, length: 0))
        XCTAssertEqual(editor.draftText, "beta!")
        XCTAssertTrue(field.performKeyEquivalent(with: try keyEquivalent("z", .command)))
        XCTAssertTrue(note.contains("| beta! | 2 |"), "The typing is in the note before the note's undo.")
        XCTAssertTrue(field.performKeyEquivalent(with: try keyEquivalent("z", [.command, .shift])))
        XCTAssertEqual(undos, [false, true])
    }

    func testCommandCXAndVCopyCutAndPasteSelectedCells() async throws {
        let (field, _) = try await fieldEditor(editing: TableCellPosition(row: 1, column: 0))
        XCTAssertFalse(field.performKeyEquivalent(with: try keyEquivalent("c", .command)), "With no cells selected ⌘C copies the text.")
        editor.selectCells(from: TableCellPosition(row: 1, column: 0), to: TableCellPosition(row: 2, column: 0))
        XCTAssertTrue(field.performKeyEquivalent(with: try keyEquivalent("c", .command)))
        XCTAssertTrue(field.performKeyEquivalent(with: try keyEquivalent("x", .command)))
        XCTAssertEqual(note, "Intro\n\n| Name | Value |\n| ---- | :---: |\n|  | 1 |\n|  | 2 |\n\nAfter\n", "⌘X empties the cells after copying them.")
        editor.beginEditing(TableCellPosition(row: 1, column: 1))
        XCTAssertTrue(field.performKeyEquivalent(with: try keyEquivalent("v", .command)))
        let cells = try XCTUnwrap(MarkdownTable.parse(editor.tableSource ?? "")).rows.map { $0.map(\.source) }
        XCTAssertEqual(cells, [["Name", "Value"], ["", "alpha"], ["", "beta"]], "⌘V writes the copied cells from the edited one.")
    }
}

private extension LivePreviewTableEditor {
    /// Sends `selector` as the field editor does and says whether the table took it.
    func handleArrowFromField(_ fieldEditor: NSTextView, _ selector: Selector) -> Bool {
        let before = (editingCell, fieldEditor.selectedRange())
        fieldEditor.doCommand(by: selector)
        return before.0 != editingCell
    }
}
#endif
