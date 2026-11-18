/**
 * File: TableCellKeys.swift
 * -------------------------
 * Layer: UI
 * Description: What a Live Preview table's cell field tells its table: keys, where the caret goes, and copying and pasting cells.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 18/11/2026
 */

import Foundation
import CoreGraphics

/// A way out of a cell, in the table's reading order: backward is the cell before, forward the
/// cell after. The field turns the arrow keys into these for the text's own direction.
enum TableCellDirection: Equatable {
    case up, down, backward, forward
}

/// A key a table cell's editor gives the table, as Obsidian's cell editor does.
enum TableCellKey: Equatable {
    case returnKey, tab, backtab, escape
    /// An arrow pressed at the cell's edge: its first or last line, its start or end.
    case leave(TableCellDirection)
    /// Shift with an arrow at the cell's edge, or while cells are selected.
    case extendSelection(TableCellDirection)
    /// Backspace or Delete while cells are selected.
    case deleteSelection
    /// ⌘Z and ⇧⌘Z, which undo the note's own history.
    case undo, redo
}

/// Where the caret goes in a cell the editor opens.
enum TableCellCaret: Equatable {
    case end, start, all
    /// The start of the cell's last line, where Up from the cell below lands.
    case lastLineStart
    /// Nearest this point of the field, as where a click was.
    case point(CGPoint)
}

/// What the cell's field asks of its table besides keys: whether cells are selected (the
/// field then types nothing and the arrows move the selection), and copying and pasting them.
struct TableCellFieldActions {
    var hasCellSelection: () -> Bool = { false }
    /// Copies the selected cells, and with `cut` deletes them; false when none are selected.
    var copyCells: (_ cut: Bool) -> Bool = { _ in false }
    /// Pastes copied cells or a Markdown table into the table; false for other text.
    var pasteCells: () -> Bool = { false }
    /// Selects every cell of the table, for a fourth click on the edited cell.
    var selectAllCells: () -> Void = {}
}

/// The caret's place in a cell's text for a `TableCellCaret`, in UTF-16 offsets.
enum TableCellCaretRange {
    static func range(for caret: TableCellCaret, in text: String, pointIndex: (CGPoint) -> Int?) -> NSRange {
        let length = (text as NSString).length
        switch caret {
        case .end: return NSRange(location: length, length: 0)
        case .start: return NSRange(location: 0, length: 0)
        case .all: return NSRange(location: 0, length: length)
        case .lastLineStart:
            let lastBreak = (text as NSString).rangeOfCharacter(from: .newlines, options: .backwards)
            return NSRange(location: lastBreak.location == NSNotFound ? 0 : NSMaxRange(lastBreak), length: 0)
        case .point(let point):
            return NSRange(location: min(max(pointIndex(point) ?? length, 0), length), length: 0)
        }
    }
}
