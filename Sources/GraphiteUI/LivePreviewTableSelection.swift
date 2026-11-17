/**
 * File: LivePreviewTableSelection.swift
 * -------------------------------------
 * Layer: UI
 * Description: Leaving a Live Preview table's cell by its edges, selecting a rectangle of cells, and copying, cutting, pasting,
 *              clearing and deleting them, as Obsidian's table editor does.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 17/11/2026
 */

import SwiftUI
import GraphiteCore
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

extension LivePreviewTableEditor {
    // MARK: Leaving a cell by its edge

    /// An arrow at a cell's edge: the next cell that way, the caret where Obsidian puts it, or
    /// the note's line beside the table past its edge. With cells selected, the arrow ends the
    /// selection in its corner that way.
    func leave(_ direction: TableCellDirection) {
        guard let cell = editingCell, let table else { return }
        if let range = selectedRange {
            clearSelection()
            let towardStart = direction == .up || direction == .backward
            let corner = towardStart ? TableCellPosition(row: range.rows.lowerBound, column: range.columns.lowerBound)
                                     : TableCellPosition(row: range.rows.upperBound, column: range.columns.upperBound)
            return beginEditing(corner, caret: towardStart ? .start : .end)
        }
        let lastRow = table.rows.count - 1
        let lastColumn = table.columnCount - 1
        switch direction {
        case .up:
            guard cell.row > 0 else { return leaveTable(.before) }
            beginEditing(TableCellPosition(row: cell.row - 1, column: cell.column), caret: .lastLineStart)
        case .down:
            guard cell.row < lastRow else { return leaveTable(.after) }
            beginEditing(TableCellPosition(row: cell.row + 1, column: cell.column), caret: .start)
        case .backward:
            if cell.column > 0 { return beginEditing(TableCellPosition(row: cell.row, column: cell.column - 1), caret: .end) }
            guard cell.row > 0 else { return leaveTable(.before) }
            beginEditing(TableCellPosition(row: cell.row - 1, column: lastColumn), caret: .end)
        case .forward:
            if cell.column < lastColumn { return beginEditing(TableCellPosition(row: cell.row, column: cell.column + 1), caret: .start) }
            guard cell.row < lastRow else { return leaveTable(.after) }
            beginEditing(TableCellPosition(row: cell.row + 1, column: 0), caret: .start)
        }
    }

    /// The caret goes to the note's line before or after the table. The draft is written first,
    /// while the block is still found by this editor; the note's text taking the keyboard then
    /// closes the cell's editor.
    private func leaveTable(_ side: RenderedBlockSide) {
        commitDraft()
        sourceEditing?.placeCaretBesideBlock(ObjectIdentifier(self), side)
        endEditing()
    }

    // MARK: Selecting cells

    /// The selected rectangle; nil when no cells are selected.
    var selectedRange: MarkdownTableCellRange? {
        guard let selectionAnchor, let selectionHead else { return nil }
        return MarkdownTableCellRange(anchorRow: selectionAnchor.row, anchorColumn: selectionAnchor.column,
                                      headRow: selectionHead.row, headColumn: selectionHead.column)
    }

    var hasCellSelection: Bool { selectionAnchor != nil && selectionHead != nil }

    /// Selects the rectangle from `anchor` to `head`; one cell alone is no selection. The cell
    /// editor stays open in the anchor, typing nothing, so the keys keep coming to the table.
    func selectCells(from anchor: TableCellPosition, to head: TableCellPosition) {
        guard anchor != head else { return clearSelection() }
        if editingCell == nil { beginEditing(anchor) } else { commitDraft() }
        if selectionAnchor != anchor { selectionAnchor = anchor }
        if selectionHead != head { selectionHead = head }
    }

    func selectAllCells() {
        guard let table else { return }
        selectCells(from: TableCellPosition(row: 0, column: 0), to: TableCellPosition(row: table.rows.count - 1, column: table.columnCount - 1))
    }

    func selectRow(_ row: Int) {
        guard let table, row < table.rows.count else { return }
        selectCells(from: TableCellPosition(row: row, column: 0), to: TableCellPosition(row: row, column: table.columnCount - 1))
    }

    func selectColumn(_ column: Int) {
        guard let table, column < table.columnCount else { return }
        selectCells(from: TableCellPosition(row: 0, column: column), to: TableCellPosition(row: table.rows.count - 1, column: column))
    }

    func clearSelection() {
        if selectionAnchor != nil { selectionAnchor = nil }
        if selectionHead != nil { selectionHead = nil }
    }

    /// Shift with an arrow: the selection's far corner moves one cell that way, starting from
    /// the edited cell.
    func extendSelection(_ direction: TableCellDirection) {
        guard let cell = editingCell, let table else { return }
        let head = selectionHead ?? cell
        let next: TableCellPosition = switch direction {
        case .up: TableCellPosition(row: head.row - 1, column: head.column)
        case .down: TableCellPosition(row: head.row + 1, column: head.column)
        case .backward: TableCellPosition(row: head.row, column: head.column - 1)
        case .forward: TableCellPosition(row: head.row, column: head.column + 1)
        }
        guard next.row >= 0, next.row < table.rows.count, next.column >= 0, next.column < table.columnCount else { return }
        selectCells(from: selectionAnchor ?? cell, to: next)
    }

    /// The bounds of the selected cells, in the table's coordinates.
    func selectionFrame(in layout: TableCellGrid) -> CGRect? {
        guard let range = selectedRange, range.rows.upperBound < layout.numberOfRows, range.columns.upperBound < layout.numberOfColumns else { return nil }
        return layout.cellBounds(row: range.rows.lowerBound, column: range.columns.lowerBound)
            .union(layout.cellBounds(row: range.rows.upperBound, column: range.columns.upperBound))
    }

    // MARK: What selected cells do

    /// Backspace or Delete on selected cells: whole rows or columns go, every cell takes the
    /// table away, anything else is emptied.
    func deleteSelectedCells() {
        guard let range = selectedRange, let table else { return }
        if range.rows == 0...(table.rows.count - 1), range.columns == 0...(table.columnCount - 1) { return deleteTable() }
        let wholeRows = range.columns == 0...(table.columnCount - 1)
        let wholeColumns = range.rows == 0...(table.rows.count - 1)
        let nextCell = TableCellPosition(row: wholeRows ? range.rows.lowerBound - 1 : range.rows.lowerBound,
                                         column: wholeColumns ? range.columns.lowerBound - 1 : range.columns.lowerBound)
        changeTable({ source in MarkdownTableEditing.deletingCells(in: range, in: source) }, editing: nextCell)
    }

    /// Empties the selected cells, keeping them.
    func clearSelectedCells() {
        guard let range = selectedRange else { return }
        changeTable({ source in MarkdownTableEditing.clearingCells(in: range, in: source) },
                    editing: TableCellPosition(row: range.rows.lowerBound, column: range.columns.lowerBound))
    }

    /// Takes the whole table out of the note.
    func deleteTable() {
        clearSelection()
        commitDraft()
        endEditing()
        replaceSource { _ in "" }
    }

    /// ⌘C and ⌘X on selected cells: the cells as a Markdown table, as HTML and as cells.
    func copySelectedCells(cut: Bool) -> Bool {
        guard let range = selectedRange, let tableSource, let grid = MarkdownTableEditing.grid(of: range, in: tableSource) else { return false }
        pasteboard.write(grid)
        if cut { deleteSelectedCells() }
        return true
    }

    /// ⌘V of copied cells, or of a whole Markdown table, from the selection's first cell or the
    /// edited cell on, the table growing as needed; false for other text, which the cell takes.
    func pasteCells() -> Bool {
        guard let grid = pasteboard.readGrid() else { return false }
        guard let start = selectedRange.map({ TableCellPosition(row: $0.rows.lowerBound, column: $0.columns.lowerBound) }) ?? editingCell else { return false }
        let lastCell = TableCellPosition(row: start.row + grid.rows.count - 1, column: start.column + (grid.rows.map(\.count).max() ?? 1) - 1)
        changeTable({ source in MarkdownTableEditing.pasting(grid, atRow: start.row, column: start.column, in: source) }, editing: lastCell)
        return true
    }

    /// What the cell's field asks of the table besides keys.
    var fieldActions: TableCellFieldActions {
        TableCellFieldActions(hasCellSelection: { [weak self] in self?.hasCellSelection ?? false },
                              copyCells: { [weak self] cut in self?.copySelectedCells(cut: cut) ?? false },
                              pasteCells: { [weak self] in self?.pasteCells() ?? false })
    }

    /// The selected cells' menu, as Obsidian's: the clipboard, the selected columns' alignment,
    /// Clear cells and Delete cells.
    func selectionMenuItems(_ range: MarkdownTableCellRange) -> [RenderedBlockMenuItem] {
        let alignments: [(String, String, MarkdownTable.ColumnAlignment)] = [
            ("Align left", "text.alignleft", .left), ("Align center", "text.aligncenter", .center), ("Align right", "text.alignright", .right),
        ]
        let alignmentItems = alignments.map { title, symbolName, alignment in
            RenderedBlockMenuItem(title: title, symbolName: symbolName, action: { [weak self] in
                self?.changeTable({ source in
                    range.columns.reduce(source as String?) { edited, column in
                        edited.flatMap { MarkdownTableEditing.settingAlignment(alignment, ofColumn: column, in: $0) }
                    }
                }, editing: TableCellPosition(row: range.rows.lowerBound, column: range.columns.lowerBound))
            })
        }
        return [
            RenderedBlockMenuItem(title: "Cut", symbolName: "scissors", action: { [weak self] in _ = self?.copySelectedCells(cut: true) }),
            RenderedBlockMenuItem(title: "Copy", symbolName: "doc.on.doc", action: { [weak self] in _ = self?.copySelectedCells(cut: false) }),
            RenderedBlockMenuItem(title: "Paste", symbolName: "doc.on.clipboard", isEnabled: pasteboard.mayHoldCells,
                                  action: { [weak self] in _ = self?.pasteCells() }),
        ] + alignmentItems + [
            RenderedBlockMenuItem(title: "Clear cells", symbolName: "eraser", action: { [weak self] in self?.clearSelectedCells() }),
            RenderedBlockMenuItem(title: "Delete cells", symbolName: "trash", action: { [weak self] in self?.deleteSelectedCells() }),
        ]
    }

    // MARK: The grips

    /// A grip dropped: its row or column moves there and stays selected, as on Obsidian's desktop.
    func moveRow(_ row: Int, to targetRow: Int) {
        if row != targetRow {
            changeTable({ source in MarkdownTableEditing.movingRow(row, to: targetRow, in: source) }, editing: TableCellPosition(row: targetRow, column: 0))
        }
        selectRow(targetRow)
    }

    func moveColumn(_ column: Int, to targetColumn: Int) {
        if column != targetColumn {
            changeTable({ source in MarkdownTableEditing.movingColumn(at: column, by: targetColumn - column, in: source) },
                        editing: TableCellPosition(row: 0, column: targetColumn))
        }
        selectColumn(targetColumn)
    }

    /// A grip's menu: a row's Row commands, a column's Column commands and the sorts.
    func gripMenuItems(at pointInTable: CGPoint, layout: TableCellGrid) -> [RenderedBlockMenuItem]? {
        guard let table, let cell = Self.cell(at: pointInTable, in: layout) else { return nil }
        let grips = TableGripsGeometry(tableBounds: layout.bounds, blockBounds: tablePlacement.blockBoundsInTable)
        let menuCell: TableCellPosition
        let placements: [TableCellCommand.Placement]
        if grips.columnGrip(for: layout.columnBounds(cell.column)).contains(pointInTable) {
            menuCell = TableCellPosition(row: 0, column: cell.column)
            placements = [.columnMenu, .topLevel]
        } else if grips.rowGrip(for: layout.rowBounds(cell.row)).contains(pointInTable) {
            menuCell = TableCellPosition(row: cell.row, column: 0)
            placements = [.rowMenu]
        } else {
            return nil
        }
        return TableCellCommand.allCases.filter { placements.contains($0.placement) }.map { command in
            RenderedBlockMenuItem(title: command.title, symbolName: command.symbolName, isEnabled: command.isAvailable(at: menuCell, in: table),
                                  isChosen: command.isChosen(at: menuCell, in: table), action: { [weak self] in self?.perform(command, at: menuCell) })
        }
    }
}

extension TableCellCommand {
    /// The cell edited after the command, as Obsidian moves its focus: the added, moved or
    /// copied row or column, or the one before a removed one.
    func cellEdited(after cell: TableCellPosition) -> TableCellPosition {
        let row = cell.row
        let column = cell.column
        switch self {
        case .addRowAbove, .alignLeft, .alignCenter, .alignRight, .sortAscending, .sortDescending, .addColumnToTheLeft: return cell
        case .addRowBelow, .moveRowDown, .duplicateRow: return TableCellPosition(row: row + 1, column: column)
        case .moveRowUp, .deleteRow: return TableCellPosition(row: max(row - 1, 0), column: column)
        case .addColumnToTheRight, .moveColumnRight, .duplicateColumn: return TableCellPosition(row: row, column: column + 1)
        case .moveColumnLeft, .deleteColumn: return TableCellPosition(row: row, column: max(column - 1, 0))
        }
    }
}

/// Where the grips go, in the table's coordinates: a column's above its header, a row's left
/// of its first cell, `gap` outside the table where the block has the room, and otherwise moved
/// in over the cells' padding, as the "+" strips are: they take no room of their own in the note.
struct TableGripsGeometry: Equatable {
    let tableBounds: CGRect
    let blockBounds: CGRect

    static let thickness: CGFloat = 12
    static let gap: CGFloat = 2

    func columnGrip(for columnBounds: CGRect) -> CGRect {
        CGRect(x: columnBounds.minX, y: Self.gripStart(edge: tableBounds.minY, blockEdge: blockBounds.minY),
               width: columnBounds.width, height: Self.thickness)
    }

    func rowGrip(for rowBounds: CGRect) -> CGRect {
        CGRect(x: Self.gripStart(edge: tableBounds.minX, blockEdge: blockBounds.minX), y: rowBounds.minY,
               width: Self.thickness, height: rowBounds.height)
    }

    /// Before the edge when it fits, else starting at the block's edge, and at most a grip's
    /// thickness inside the table.
    private static func gripStart(edge: CGFloat, blockEdge: CGFloat) -> CGFloat {
        min(max(edge - gap - thickness, blockEdge), edge)
    }
}

/// The pasteboard of a table's cells: a Markdown table as text, HTML, and Graphite's own cells.
struct TablePasteboard {
    static let cellsTypeIdentifier = "app.graphite.table-cells"
    /// The general pasteboard, which a person's copies and pastes use.
    static let general = TablePasteboard(name: nil)
    /// A pasteboard of its own instead of the general one, as tests give an editor so that they
    /// leave the person's clipboard alone; nil for the general pasteboard.
    let name: String?

    #if canImport(UIKit)
    @MainActor private var pasteboard: UIPasteboard {
        name.flatMap { UIPasteboard(name: UIPasteboard.Name($0), create: true) } ?? .general
    }
    #else
    @MainActor private var pasteboard: NSPasteboard {
        name.map { NSPasteboard(name: NSPasteboard.Name($0)) } ?? .general
    }
    #endif

    @MainActor
    func write(_ grid: MarkdownTableGrid) {
        let cellsData = (try? JSONEncoder().encode(grid)) ?? Data() // Strings only, which always encode.
        #if canImport(UIKit)
        pasteboard.items = [["public.utf8-plain-text": grid.markdownTable, "public.html": grid.htmlTable, Self.cellsTypeIdentifier: cellsData]]
        #else
        pasteboard.clearContents()
        pasteboard.setString(grid.markdownTable, forType: .string)
        pasteboard.setString(grid.htmlTable, forType: .html)
        pasteboard.setData(cellsData, forType: NSPasteboard.PasteboardType(Self.cellsTypeIdentifier))
        #endif
    }

    /// Whether the pasteboard may hold cells, found from its types alone: reading it on the
    /// iPad would ask to allow pasting each time the menu opens.
    @MainActor
    var mayHoldCells: Bool {
        #if canImport(UIKit)
        pasteboard.contains(pasteboardTypes: [Self.cellsTypeIdentifier]) || pasteboard.hasStrings
        #else
        pasteboard.availableType(from: [NSPasteboard.PasteboardType(Self.cellsTypeIdentifier), .string]) != nil
        #endif
    }

    /// Copied cells, else a whole Markdown table copied as text; nil for other text.
    @MainActor
    func readGrid() -> MarkdownTableGrid? {
        #if canImport(UIKit)
        let cellsData = pasteboard.data(forPasteboardType: Self.cellsTypeIdentifier)
        let text = pasteboard.hasStrings ? pasteboard.string : nil
        #else
        let cellsData = pasteboard.data(forType: NSPasteboard.PasteboardType(Self.cellsTypeIdentifier))
        let text = pasteboard.string(forType: .string)
        #endif
        // Unreadable cells, as another version may write, fall back to the text.
        if let cellsData, let grid = try? JSONDecoder().decode(MarkdownTableGrid.self, from: cellsData) { return grid } // see above
        guard let text, text.contains("\n") else { return nil }
        return MarkdownTableGrid(markdownTable: text)
    }
}
