/**
 * File: LivePreviewTableCommands.swift
 * ------------------------------------
 * Layer: UI
 * Description: The commands of a Live Preview table's cell, declared once for its menu, the command palette and the
 *              Edit menu, and the cell they act on.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 11/11/2026
 */

import SwiftUI
import GraphiteCore

/// The commands of a Live Preview table's cell, in the order and words of Obsidian's cell
/// menu: Row ›, Column ›, then the two sorts. Each is one `MarkdownTableEditing` source edit,
/// written into the note as one undoable edit. The cell menu, the command palette and the Edit
/// menu are all made from this one declaration.
enum TableCellCommand: CaseIterable {
    case addRowAbove, addRowBelow, moveRowUp, moveRowDown, duplicateRow, deleteRow
    case addColumnToTheLeft, addColumnToTheRight, moveColumnLeft, moveColumnRight
    case alignLeft, alignCenter, alignRight, duplicateColumn, deleteColumn
    case sortAscending, sortDescending

    /// Where the command sits in the cell menu.
    enum Placement {
        case rowMenu, columnMenu, topLevel
    }

    var title: String {
        switch self {
        case .addRowAbove: "Add row above"
        case .addRowBelow: "Add row below"
        case .moveRowUp: "Move row up"
        case .moveRowDown: "Move row down"
        case .duplicateRow: "Duplicate row"
        case .deleteRow: "Delete row"
        case .addColumnToTheLeft: "Add column to the left"
        case .addColumnToTheRight: "Add column to the right"
        case .moveColumnLeft: "Move column left"
        case .moveColumnRight: "Move column right"
        case .alignLeft: "Align left"
        case .alignCenter: "Align center"
        case .alignRight: "Align right"
        case .duplicateColumn: "Duplicate column"
        case .deleteColumn: "Delete column"
        case .sortAscending: "Sort by column (A to Z)"
        case .sortDescending: "Sort by column (Z to A)"
        }
    }

    var symbolName: String {
        switch self {
        case .addRowAbove: "arrow.up.to.line"
        case .addRowBelow: "arrow.down.to.line"
        case .moveRowUp: "arrow.up"
        case .moveRowDown: "arrow.down"
        case .duplicateRow, .duplicateColumn: "plus.square.on.square"
        case .deleteRow, .deleteColumn: "trash"
        case .addColumnToTheLeft: "arrow.left.to.line"
        case .addColumnToTheRight: "arrow.right.to.line"
        case .moveColumnLeft: "arrow.left"
        case .moveColumnRight: "arrow.right"
        case .alignLeft: "text.alignleft"
        case .alignCenter: "text.aligncenter"
        case .alignRight: "text.alignright"
        // Both sorts take the system's sort symbol: "arrow.down.arrow.up" is no SF Symbol, and drew
        // no icon (HUNT-340).
        case .sortAscending, .sortDescending: "arrow.up.arrow.down"
        }
    }

    var placement: Placement {
        switch self {
        case .addRowAbove, .addRowBelow, .moveRowUp, .moveRowDown, .duplicateRow, .deleteRow: .rowMenu
        case .addColumnToTheLeft, .addColumnToTheRight, .moveColumnLeft, .moveColumnRight, .alignLeft, .alignCenter, .alignRight,
             .duplicateColumn, .deleteColumn: .columnMenu
        case .sortAscending, .sortDescending: .topLevel
        }
    }

    /// The command's entry in Graphite's command list, which gives it a place in Settings ›
    /// Keyboard Shortcuts and in the vault's `hotkeys.json`.
    var graphiteCommand: GraphiteCommand {
        switch self {
        case .addRowAbove: .tableAddRowAbove
        case .addRowBelow: .tableAddRowBelow
        case .moveRowUp: .tableMoveRowUp
        case .moveRowDown: .tableMoveRowDown
        case .duplicateRow: .tableDuplicateRow
        case .deleteRow: .tableDeleteRow
        case .addColumnToTheLeft: .tableAddColumnToTheLeft
        case .addColumnToTheRight: .tableAddColumnToTheRight
        case .moveColumnLeft: .tableMoveColumnLeft
        case .moveColumnRight: .tableMoveColumnRight
        case .alignLeft: .tableAlignLeft
        case .alignCenter: .tableAlignCenter
        case .alignRight: .tableAlignRight
        case .duplicateColumn: .tableDuplicateColumn
        case .deleteColumn: .tableDeleteColumn
        case .sortAscending: .tableSortAscending
        case .sortDescending: .tableSortDescending
        }
    }

    /// The alignment an Align command gives its column; nil for the other commands.
    private var alignment: MarkdownTable.ColumnAlignment? {
        switch self {
        case .alignLeft: .left
        case .alignCenter: .center
        case .alignRight: .right
        case .addRowAbove, .addRowBelow, .moveRowUp, .moveRowDown, .duplicateRow, .deleteRow, .addColumnToTheLeft, .addColumnToTheRight,
             .moveColumnLeft, .moveColumnRight, .duplicateColumn, .deleteColumn, .sortAscending, .sortDescending: nil
        }
    }

    /// Whether the command can apply to `cell`: the header row cannot move, be deleted or have a
    /// row added above it, the first body row cannot move up, nor the last one down, the last
    /// column cannot be deleted, and a table of fewer than two body rows has nothing to sort.
    func isAvailable(at cell: TableCellPosition, in table: MarkdownTable) -> Bool {
        guard cell.row >= 0, cell.row < table.rows.count, cell.column >= 0, cell.column < table.columnCount else { return false }
        let isHeader = cell.row == 0
        let bodyRowIndex = cell.row - 1
        switch self {
        case .addRowAbove, .deleteRow: return !isHeader
        case .moveRowUp: return bodyRowIndex > 0
        case .moveRowDown: return !isHeader && bodyRowIndex < table.bodyRowCount - 1
        case .moveColumnLeft: return cell.column > 0
        case .moveColumnRight: return cell.column < table.columnCount - 1
        case .deleteColumn: return table.columnCount > 1
        case .sortAscending, .sortDescending: return table.bodyRowCount > 1
        case .addRowBelow, .duplicateRow, .addColumnToTheLeft, .addColumnToTheRight, .alignLeft, .alignCenter, .alignRight, .duplicateColumn:
            return true
        }
    }

    /// Whether the column already has the command's alignment, which the menu marks; choosing
    /// it again clears the alignment.
    func isChosen(at cell: TableCellPosition, in table: MarkdownTable) -> Bool {
        guard let alignment, cell.column < table.alignments.count else { return false }
        return table.alignments[cell.column] == alignment
    }

    /// The source edit the command makes for `cell`, given the table as it is now; it is run on
    /// the table's source as the note has it when the edit is written.
    func edit(at cell: TableCellPosition, in table: MarkdownTable) -> (String) -> String? {
        let row = cell.row
        let bodyRowIndex = cell.row - 1
        let column = cell.column
        switch self {
        case .addRowAbove: return { source in MarkdownTableEditing.insertingRow(atBodyIndex: bodyRowIndex, in: source) }
        case .addRowBelow: return { source in MarkdownTableEditing.insertingRow(atBodyIndex: bodyRowIndex + 1, in: source) }
        case .moveRowUp: return { source in MarkdownTableEditing.movingRow(atBodyIndex: bodyRowIndex, by: -1, in: source) }
        case .moveRowDown: return { source in MarkdownTableEditing.movingRow(atBodyIndex: bodyRowIndex, by: 1, in: source) }
        case .duplicateRow: return { source in MarkdownTableEditing.duplicatingRow(row, in: source) }
        case .deleteRow: return { source in MarkdownTableEditing.removingRow(atBodyIndex: bodyRowIndex, in: source) }
        case .addColumnToTheLeft: return { source in MarkdownTableEditing.insertingColumn(at: column, in: source) }
        case .addColumnToTheRight: return { source in MarkdownTableEditing.insertingColumn(at: column + 1, in: source) }
        case .moveColumnLeft: return { source in MarkdownTableEditing.movingColumn(at: column, by: -1, in: source) }
        case .moveColumnRight: return { source in MarkdownTableEditing.movingColumn(at: column, by: 1, in: source) }
        case .alignLeft, .alignCenter, .alignRight:
            // Choosing the column's own alignment again takes it away, as Align › None did.
            let newAlignment = isChosen(at: cell, in: table) ? MarkdownTable.ColumnAlignment.none : alignment ?? .none
            return { source in MarkdownTableEditing.settingAlignment(newAlignment, ofColumn: column, in: source) }
        case .duplicateColumn: return { source in MarkdownTableEditing.duplicatingColumn(at: column, in: source) }
        case .deleteColumn: return { source in MarkdownTableEditing.removingColumn(at: column, in: source) }
        case .sortAscending: return { source in MarkdownTableEditing.sortingRows(byColumn: column, .ascending, in: source) }
        case .sortDescending: return { source in MarkdownTableEditing.sortingRows(byColumn: column, .descending, in: source) }
        }
    }

    /// The cell menu for `cell`: Row ›, Column ›, then the sorts. Commands that cannot apply are
    /// shown dimmed, the column's alignment is marked.
    @MainActor
    static func menuItems(at cell: TableCellPosition, in table: MarkdownTable,
                          perform: @escaping (TableCellCommand) -> Void) -> [RenderedBlockMenuItem] {
        func item(_ command: TableCellCommand) -> RenderedBlockMenuItem {
            RenderedBlockMenuItem(title: command.title, symbolName: command.symbolName, isEnabled: command.isAvailable(at: cell, in: table),
                                  isChosen: command.isChosen(at: cell, in: table), action: { perform(command) })
        }
        func commands(_ placement: Placement) -> [TableCellCommand] { allCases.filter { command in command.placement == placement } }
        return [
            RenderedBlockMenuItem(title: "Row", symbolName: "tablecells", children: commands(.rowMenu).map(item)),
            RenderedBlockMenuItem(title: "Column", symbolName: "tablecells", children: commands(.columnMenu).map(item)),
        ] + commands(.topLevel).map(item)
    }
}

/// The table cell whose commands the command palette and the Edit menu offer: the cell being
/// edited in a Live Preview table, or the one last edited there until the note's own text takes
/// the keyboard. Opening the palette takes the keyboard from the cell, which closes its editor,
/// so the commands stay with the cell the person was in. The table's editor is held weakly: a
/// table scrolled away and let go offers nothing.
@MainActor
struct TableCellCommandTarget {
    weak var editor: LivePreviewTableEditor?

    func isAvailable(_ command: TableCellCommand) -> Bool {
        editor?.isAvailable(command) ?? false
    }

    func perform(_ command: TableCellCommand) {
        editor?.perform(command)
    }
}

/// The Edit menu's Table submenu: the cell commands for the table cell the palette also acts
/// on, each with the shortcut Settings › Keyboard Shortcuts gives it (none by default), dimmed
/// where it cannot apply and as a whole while no table's cell has been edited.
struct TableCellCommandsMenu: View {
    let target: TableCellCommandTarget?
    let shortcut: (GraphiteCommand) -> KeyboardShortcut?

    var body: some View {
        Menu("Table") {
            Menu("Row") { buttons(.rowMenu) }
            Menu("Column") { buttons(.columnMenu) }
            buttons(.topLevel)
        }
        .disabled(target == nil)
    }

    private func buttons(_ placement: TableCellCommand.Placement) -> some View {
        ForEach(TableCellCommand.allCases.filter { command in command.placement == placement }, id: \.self) { command in
            Button(command.title) { target?.perform(command) }
                .keyboardShortcut(shortcut(command.graphiteCommand))
                .disabled(!(target?.isAvailable(command) ?? false))
        }
    }
}
