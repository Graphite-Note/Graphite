/**
 * File: TableCellFieldEditing.swift
 * ---------------------------------
 * Layer: UI
 * Description: A Live Preview table cell's undo manager, which undoes the note, and on the Mac its own field editor, which takes the
 *              Edit menu's clipboard items and a fourth click to the table.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 18/11/2026
 */

import Foundation
#if os(macOS)
import AppKit
#endif

/// A table cell's undo manager: it records no typing, and its undo and redo are the note's
/// (`TableCellTextView.cellUndoManager`, `TableCellMacTextField.cellUndoManager`).
final class TableCellUndoManager: UndoManager {
    private let undoInNote: (_ isRedo: Bool) -> Void

    init(undoInNote: @escaping (_ isRedo: Bool) -> Void) {
        self.undoInNote = undoInNote
        super.init()
        disableUndoRegistration()
    }

    override var canUndo: Bool { true }
    override var canRedo: Bool { true }
    override func undo() { undoInNote(false) }
    override func redo() { undoInNote(true) }
}

#if os(macOS)
/// The cell of a table cell's field on the Mac, which edits with a `TableCellFieldEditor`.
final class TableCellMacTextFieldCell: NSTextFieldCell {
    private lazy var tableFieldEditor: TableCellFieldEditor = {
        let editor = TableCellFieldEditor()
        editor.isFieldEditor = true
        return editor
    }()

    override func fieldEditor(for controlView: NSView) -> NSTextView? {
        tableFieldEditor.tableField = controlView as? TableCellMacTextField
        return tableFieldEditor
    }
}

/// The field editor of a table cell's field on the Mac. AppKit sends the Edit menu's Copy, Cut
/// and Paste, and the clicks after the first, to the field editor, not to the field: with cells selected and no text, Copy and
/// Cut were dimmed and Paste pasted text into the cell. They go to the table's cells here, as
/// the field's ⌘C, ⌘X and ⌘V do (`TableCellMacTextField.performKeyEquivalent`).
final class TableCellFieldEditor: NSTextView {
    weak var tableField: TableCellMacTextField?

    /// A fourth click on the edited cell selects the table, as on any other cell: the clicks
    /// after the first reach this editor, not the table's layer, which counts them elsewhere.
    override func mouseDown(with event: NSEvent) {
        if event.clickCount >= 4, let tableField {
            tableField.actions.selectAllCells()
            return
        }
        super.mouseDown(with: event)
    }

    override func copy(_ sender: Any?) {
        if tableField?.actions.copyCells(false) != true { super.copy(sender) }
    }

    override func cut(_ sender: Any?) {
        if tableField?.actions.copyCells(true) != true { super.cut(sender) }
    }

    override func paste(_ sender: Any?) {
        if tableField?.actions.pasteCells() != true { super.paste(sender) }
    }

    override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        let clipboardActions: [Selector] = [#selector(copy(_:)), #selector(cut(_:)), #selector(paste(_:))]
        if let action = item.action, clipboardActions.contains(action), tableField?.actions.hasCellSelection() == true { return true }
        return super.validateUserInterfaceItem(item)
    }
}
#endif
