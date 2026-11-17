/**
 * File: LivePreviewTableEditing.swift
 * -----------------------------------
 * Layer: UI
 * Description: Editing a rendered table's cells in place: the cell editor, its keys and moves, its cell commands, and the overlay that
 *              puts its layer over the table.
 *
 * Authors: Bahey Shalash
 * Version: 0.10
 * Date: 17/11/2026
 */

import SwiftUI
import GraphiteCore
import Textual

/// Which side of a rendered block the note's caret goes to.
enum RenderedBlockSide {
    case before, after
}

/// What a rendered block's view uses to change the block's own source in the note.
struct RenderedBlockSourceEditing {
    /// Replaces the block's source with what `transform` makes of it, as one edit that can be
    /// undone; a nil result leaves the note alone. `transform` is given the block's source as
    /// the note has it now, line endings included. `editor` is the one editing the block,
    /// whose block is found at its place rather than by a key an earlier edit replaced.
    let replaceSource: (_ editor: ObjectIdentifier, _ transform: @escaping (String) -> String?) -> Void
    /// While true, the block keeps its view across the new keys its edits give it.
    let setIsEditingInView: (_ isEditing: Bool, _ editor: ObjectIdentifier) -> Void
    /// What writes the editor's draft into the note before a save; nil once it holds none.
    var setDraftCommit: (_ editor: ObjectIdentifier, _ commit: (() -> Void)?) -> Void = { _, _ in }
    /// Gives the note's command palette and Edit menu the table's cell commands, as a cell begins editing.
    var offerCellCommands: (_ target: TableCellCommandTarget) -> Void = { _ in }
    /// Gives the note's text the keyboard, the caret at the start of the line before or after
    /// the block; an empty line is added first where the block starts or ends the note.
    var placeCaretBesideBlock: (_ editor: ObjectIdentifier, _ side: RenderedBlockSide) -> Void = { _, _ in }
    /// Undoes, or with `isRedo` redoes, the note's last change.
    var undoInNote: (_ isRedo: Bool) -> Void = { _ in }
}

/// A cell of a rendered table: row 0 is the header, then the body rows.
struct TableCellPosition: Hashable {
    let row: Int
    let column: Int
}

extension EnvironmentValues {
    /// Set on a Live Preview table, whose cells are then edited in place; nil in reading view.
    @Entry var livePreviewTableEditor: LivePreviewTableEditor? = nil
}

/// Edits a Live Preview table's cells in place, as Obsidian does: a click on a cell opens an
/// editor over it holding the cell's Markdown, the caret where the click was; Tab and Shift-Tab
/// go to the next and previous cell selecting its text, Return to the cell below, an arrow at a
/// cell's edge to the next cell that way and out of the table at its edge; Shift with an arrow,
/// a drag or a Shift-click selects a rectangle of cells to copy, cut, paste over, clear or
/// delete (`LivePreviewTableSelection.swift`); ⌘Z undoes the note's own history; the block's
/// menu and the grips add, move and remove rows and columns, a cell staying edited. Each change
/// is written into the note as one edit of the characters it changes (`MarkdownTableEditing`):
/// typing when it pauses, and when the editor moves or closes.
///
/// One per table view, kept by the view; what it reads from the view (the table's source and
/// the way to edit it) is given again at every update, without making the view draw again.
@MainActor
@Observable
final class LivePreviewTableEditor {
    /// The coordinate space of a rendered block's whole view, which its menu's points are in.
    nonisolated static let blockCoordinateSpaceName = "LivePreviewRenderedBlock"
    /// The coordinate space of a table's own piece where the block holds more than the table, as
    /// a callout does: what is above the piece is the block's text, not room for the grips.
    nonisolated static let tablePieceCoordinateSpaceName = "LivePreviewTablePiece"
    /// The space between the pieces of a callout's body, half of which a grip may reach into.
    nonisolated static let tablePieceSpacing: CGFloat = 8
    /// How long typing pauses before the cell is written into the note.
    private static let commitDelay: Duration = .milliseconds(400)

    private(set) var editingCell: TableCellPosition?
    /// The rectangle of selected cells, from the cell it began at to the one it reaches.
    var selectionAnchor: TableCellPosition?
    var selectionHead: TableCellPosition?
    /// The cell the command palette's and the Edit menu's table commands act on: the edited
    /// cell, or the one last edited once its editor closed, as when the palette took the keyboard.
    private(set) var commandCell: TableCellPosition?
    /// Asks the cell editor to take the keyboard: it changes when editing begins.
    private(set) var focusRequest = 0
    /// The edited cell's text, as `MarkdownTableEditing.editableText(ofCellSource:)` shows it.
    var draftText = "" {
        didSet { if draftText != oldValue { draftDidChange(from: oldValue) } }
    }

    /// Where the caret goes in the cell the editor opens next.
    @ObservationIgnored private(set) var caret: TableCellCaret = .end
    @ObservationIgnored private(set) var textSize: Double = 16
    @ObservationIgnored private(set) var tableSource: String?
    @ObservationIgnored private(set) var table: MarkdownTable?
    @ObservationIgnored private(set) var sourceEditing: RenderedBlockSourceEditing?
    /// The draft as last written into the note, or as the cell had it.
    @ObservationIgnored private var committedDraft = ""
    /// The cell's text in the table as this editor last left it: what the draft reads as once
    /// written, which can differ from the draft (spaces at its ends).
    @ObservationIgnored private var cellTextAsWritten: String?
    @ObservationIgnored private var commitTask: Task<Void, Never>?
    /// The table's cells as last laid out, and where the table is in the block's view, which
    /// the "+" strips stay inside.
    @ObservationIgnored var layout: TableCellGrid?
    @ObservationIgnored var tablePlacement = TablePlacementInBlock()
    var tableOriginInBlock: CGPoint { tablePlacement.origin }
    /// Where the vault's pictures in the table's cells are, in the block's coordinates: a tap
    /// on one zooms into it rather than editing its cell.
    @ObservationIgnored var pictureFrames: [ZoomablePictureFrame] = []
    /// Where the edited cell was last drawn, for a cell the table has not laid out yet (a
    /// row just added), so the editor and its keyboard stay.
    @ObservationIgnored var lastEditingFrame: CGRect?
    /// Where copied cells go and come from: the general pasteboard but in tests.
    @ObservationIgnored var pasteboard = TablePasteboard.general

    var canEdit: Bool { sourceEditing != nil && table != nil }

    /// Takes the view's current table source, text size and way to edit; called as the view
    /// updates, so it changes nothing the view draws.
    func update(source: String, textSize: Double, sourceEditing: RenderedBlockSourceEditing?) {
        if source != tableSource {
            tableSource = source
            table = MarkdownTable.parse(source)
            reloadDraftIfTheCellChangedElsewhere()
        }
        self.textSize = textSize
        self.sourceEditing = sourceEditing
    }

    /// The edited cell's text in the table now.
    private var cellTextInTable: String? {
        guard let cell = editingCell else { return nil }
        return Self.text(ofCell: cell, in: table)
    }

    static func text(ofCell cell: TableCellPosition, in table: MarkdownTable?) -> String? {
        guard let table, cell.row < table.rows.count, cell.column < table.columnCount else { return nil }
        let cellSource = cell.column < table.rows[cell.row].count ? table.rows[cell.row][cell.column].source : ""
        return MarkdownTableEditing.editableText(ofCellSource: cellSource)
    }

    /// The cell changed in the note, not through this editor, as an undo does: the field shows
    /// what the note has now. It kept the old text, and the next key wrote all of it back,
    /// redoing what was undone. A cell the change took away closes the editor. After the view's
    /// update, which this runs in.
    private func reloadDraftIfTheCellChangedElsewhere() {
        guard let cell = editingCell else { return }
        guard let cellText = cellTextInTable else {
            Task { @MainActor [weak self] in
                guard let self, self.editingCell == cell, self.cellTextInTable == nil else { return }
                self.endEditing()
            }
            return
        }
        guard cellText != cellTextAsWritten else { return }
        cellTextAsWritten = cellText
        Task { @MainActor [weak self] in
            guard let self, self.editingCell == cell else { return }
            self.commitTask?.cancel()
            self.commitTask = nil
            self.committedDraft = cellText
            self.draftText = cellText
        }
    }

    // MARK: Editing a cell

    /// The cell field's padding inside a cell, in text sizes, as the rendered cells have it.
    static let horizontalPaddingScale = 0.6
    static let verticalPaddingScale = 0.35

    /// Edits the cell at `point`, in the table's coordinates, the caret nearest the point.
    func beginEditing(at point: CGPoint) {
        guard let layout, let cell = Self.cell(at: point, in: layout) else { return }
        clearSelection()
        let cellBounds = layout.cellBounds(row: cell.row, column: cell.column)
        let pointInField = CGPoint(x: point.x - cellBounds.minX - textSize * Self.horizontalPaddingScale,
                                   y: point.y - cellBounds.minY - textSize * Self.verticalPaddingScale)
        beginEditing(cell, caret: .point(pointInField))
    }

    func beginEditing(_ cell: TableCellPosition, caret: TableCellCaret = .end) {
        guard let table, cell.row < table.rows.count, cell.column < table.columnCount else { return }
        startEditing(cell, text: Self.text(ofCell: cell, in: table) ?? "", caret: caret)
    }

    func startEditing(_ cell: TableCellPosition, text: String, caret: TableCellCaret = .end) {
        // The text and the place were worked out from the cells as they were before the draft.
        guard !draftMovesOtherCells else { return commitDraft() }
        commitDraft()
        if editingCell == nil {
            TableCellTextField.endEditingInOtherTables()
            sourceEditing?.setIsEditingInView(true, ObjectIdentifier(self))
            sourceEditing?.setDraftCommit(ObjectIdentifier(self)) { [weak self] in self?.commitDraft() }
        }
        self.caret = caret
        committedDraft = text
        cellTextAsWritten = text
        editingCell = cell
        commandCell = cell
        draftText = text
        focusRequest += 1
        sourceEditing?.offerCellCommands(TableCellCommandTarget(editor: self))
    }

    /// The cell editor lost the keyboard, as after a tap in the note's text: the editor closes.
    /// Moving between cells keeps the same text view, which keeps the keyboard.
    func focusDidLeave() {
        endEditing()
    }

    /// Writes the draft into the note and closes the editor.
    func endEditing() {
        guard editingCell != nil else { return }
        commitDraft()
        editingCell = nil
        clearSelection()
        lastEditingFrame = nil
        sourceEditing?.setDraftCommit(ObjectIdentifier(self), nil)
        sourceEditing?.setIsEditingInView(false, ObjectIdentifier(self))
    }

    func replaceSource(_ transform: @escaping (String) -> String?) {
        sourceEditing?.replaceSource(ObjectIdentifier(self), transform)
    }

    func commitDraft() {
        commitTask?.cancel()
        commitTask = nil
        guard let cell = editingCell, draftText != committedDraft else { return }
        let text = draftText
        let movesOtherCells = draftMovesOtherCells
        committedDraft = text
        cellTextAsWritten = tableSource.flatMap { source in MarkdownTableEditing.replacingCell(row: cell.row, column: cell.column, with: text, in: source) }
            .flatMap { written in Self.text(ofCell: cell, in: MarkdownTable.parse(written)) } ?? text
        replaceSource { source in
            MarkdownTableEditing.replacingCell(row: cell.row, column: cell.column, with: text, in: source)
        }
        // This row and column name another cell now, which the next key would write over.
        if movesOtherCells { endEditing() }
    }

    /// Whether writing the draft makes its `%%` pair with a marker in another cell.
    var draftMovesOtherCells: Bool {
        guard let cell = editingCell, draftText != committedDraft, let tableSource else { return false }
        return !MarkdownTableEditing.keepsOtherCellsInPlace(writing: draftText, row: cell.row, column: cell.column, in: tableSource)
    }

    /// Typing is written into the note once it pauses.
    private func draftDidChange(from oldText: String) {
        guard editingCell != nil, draftText != committedDraft else { return }
        commitTask?.cancel()
        commitTask = Task { [weak self] in
            try? await Task.sleep(for: Self.commitDelay)
            guard !Task.isCancelled else { return }
            self?.commitDraft()
        }
    }

    enum Movement {
        case next, previous, down
    }

    /// The keys of the cell editor, as in Obsidian: Return goes to the cell below, Tab and
    /// Shift-Tab to the next and previous cell selecting its text, an arrow at a cell's edge to
    /// the next cell that way (`leave`), Shift with an arrow selects cells, Escape ends a
    /// selection and then the editor. Whether the key was taken; one that was not is typed as usual.
    func handle(_ key: TableCellKey) -> Bool {
        guard editingCell != nil else { return false }
        switch key {
        case .returnKey, .tab, .backtab:
            clearSelection()
            move(key == .returnKey ? .down : key == .tab ? .next : .previous)
        case .escape:
            if hasCellSelection { clearSelection() } else { endEditing() }
        case .leave(let direction): leave(direction)
        case .extendSelection(let direction): extendSelection(direction)
        case .deleteSelection:
            guard hasCellSelection else { return false }
            deleteSelectedCells()
        case .undo, .redo:
            guard let sourceEditing else { return false }
            commitDraft()
            sourceEditing.undoInNote(key == .redo)
        }
        return true
    }

    /// Moves the editor; past the last cell (Tab) or the last row (Return) it adds a row, and
    /// Shift-Tab in the first cell adds a row above the header, as Obsidian does.
    func move(_ movement: Movement) {
        guard let cell = editingCell, let table else { return }
        let lastRow = table.rows.count - 1
        let lastColumn = table.columnCount - 1
        switch movement {
        case .next:
            if cell.column < lastColumn { beginEditing(TableCellPosition(row: cell.row, column: cell.column + 1), caret: .all) }
            else if cell.row < lastRow { beginEditing(TableCellPosition(row: cell.row + 1, column: 0), caret: .all) }
            else { appendRow(editingColumn: 0) }
        case .previous:
            if cell.column > 0 { beginEditing(TableCellPosition(row: cell.row, column: cell.column - 1), caret: .all) }
            else if cell.row > 0 { beginEditing(TableCellPosition(row: cell.row - 1, column: lastColumn), caret: .all) }
            else { changeTable(MarkdownTableEditing.insertingRowAboveHeader, editing: TableCellPosition(row: 0, column: lastColumn)) }
        case .down:
            if cell.row < lastRow { beginEditing(TableCellPosition(row: cell.row + 1, column: cell.column)) }
            else { appendRow(editingColumn: cell.column) }
        }
    }

    private func appendRow(editingColumn column: Int) {
        guard let table else { return }
        guard !draftMovesOtherCells else { return commitDraft() }
        commitDraft()
        let newRow = table.rows.count
        // The editor opens first, so the view is kept across the edit's new key.
        startEditing(TableCellPosition(row: newRow, column: column), text: "")
        replaceSource { source in
            guard let bodyRowCount = MarkdownTable.parse(source)?.bodyRowCount else { return nil }
            return MarkdownTableEditing.insertingRow(atBodyIndex: bodyRowCount, in: source)
        }
    }

    // MARK: Rows and columns

    /// The cell menu's commands (`TableCellCommand`) for the cell at `point`, in the block
    /// view's coordinates; for the edited cell when the point is not on one. On a grip, its row's
    /// or column's commands; on selected cells, the selection's menu.
    func menuItems(at point: CGPoint) -> [RenderedBlockMenuItem] {
        guard let table, sourceEditing != nil else { return [] }
        if let layout {
            let pointInTable = CGPoint(x: point.x - tableOriginInBlock.x, y: point.y - tableOriginInBlock.y)
            if let gripItems = gripMenuItems(at: pointInTable, layout: layout) { return gripItems }
            if let range = selectedRange, isOnTable(point), let pointed = Self.cell(at: pointInTable, in: layout),
               range.rows.contains(pointed.row), range.columns.contains(pointed.column) {
                return selectionMenuItems(range)
            }
        }
        clearSelection()
        guard let cell = menuCell(at: point) else { return [] }
        return TableCellCommand.menuItems(at: cell, in: table) { [weak self] command in self?.perform(command, at: cell) }
    }

    private func menuCell(at point: CGPoint) -> TableCellPosition? {
        let pointInTable = CGPoint(x: point.x - tableOriginInBlock.x, y: point.y - tableOriginInBlock.y)
        let pointedCell = isOnTable(point) ? layout.flatMap { layout in Self.cell(at: pointInTable, in: layout) } : nil
        return pointedCell ?? editingCell
    }

    /// Whether `point`, in the block view's coordinates, is on the table as last laid out, or
    /// within a few points of its edge: of a callout's tables, the one its menu is for.
    func isOnTable(_ point: CGPoint) -> Bool {
        let pointInTable = CGPoint(x: point.x - tableOriginInBlock.x, y: point.y - tableOriginInBlock.y)
        return (layout?.bounds ?? .null).insetBy(dx: -4, dy: -4).contains(pointInTable)
    }

    /// Whether the command palette's and the Edit menu's `command` applies to the cell they act on.
    func isAvailable(_ command: TableCellCommand) -> Bool {
        guard let table, sourceEditing != nil, let commandCell else { return false }
        return command.isAvailable(at: commandCell, in: table)
    }

    /// Runs `command` from the command palette or the Edit menu on the cell they act on.
    func perform(_ command: TableCellCommand) {
        guard let commandCell else { return }
        perform(command, at: commandCell)
    }

    func perform(_ command: TableCellCommand, at cell: TableCellPosition) {
        guard let table, command.isAvailable(at: cell, in: table) else { return }
        if command == .deleteColumn, table.columnCount == 1 { return deleteTable() }
        changeTable(command.edit(at: cell, in: table), editing: command.cellEdited(after: cell))
    }

    /// The "+" strip along the right edge: an empty last column, in one edit, with the editor
    /// in its header. The editor opens first, so the view is kept across the edit's new key.
    func addColumnAtTheEnd() {
        guard let table, !draftMovesOtherCells else { return commitDraft() }
        startEditing(TableCellPosition(row: 0, column: table.columnCount), text: "")
        replaceSource { source in
            guard let columnCount = MarkdownTable.parse(source)?.columnCount else { return nil }
            return MarkdownTableEditing.insertingColumn(at: columnCount, in: source)
        }
    }

    /// The "+" strip along the bottom edge: an empty last row, in one edit, with the editor in
    /// its first cell.
    func addRowAtTheEnd() {
        guard let table, !draftMovesOtherCells else { return commitDraft() }
        startEditing(TableCellPosition(row: table.rows.count, column: 0), text: "")
        replaceSource { source in
            guard let bodyRowCount = MarkdownTable.parse(source)?.bodyRowCount else { return nil }
            return MarkdownTableEditing.insertingRow(atBodyIndex: bodyRowCount, in: source)
        }
    }

    /// A change of rows or columns writes the draft first, as the cells move under it, then
    /// edits `nextCell` of the changed table, as Obsidian keeps a cell focused after each change.
    /// The editor opens before the edit, so the view is kept across the edit's new key. Without
    /// a next cell the editor closes.
    func changeTable(_ transform: @escaping (String) -> String?, editing nextCell: TableCellPosition? = nil) {
        guard !draftMovesOtherCells else { return commitDraft() }
        commitDraft()
        clearSelection()
        guard let nextCell, let tableSource, let written = transform(tableSource), let writtenTable = MarkdownTable.parse(written) else {
            endEditing()
            return replaceSource(transform)
        }
        let cell = TableCellPosition(row: min(max(nextCell.row, 0), writtenTable.rows.count - 1),
                                     column: min(max(nextCell.column, 0), writtenTable.columnCount - 1))
        startEditing(cell, text: Self.text(ofCell: cell, in: writtenTable) ?? "")
        replaceSource(transform)
    }

    // MARK: Geometry

    /// The cell whose row and column contain `point`, in the table's coordinates; a point in
    /// the gap between cells goes to the nearer one, and one past an edge to the edge cell.
    static func cell(at point: CGPoint, in layout: TableCellGrid) -> TableCellPosition? {
        guard layout.numberOfRows > 0, layout.numberOfColumns > 0 else { return nil }
        let row = layout.rowIndices.last { row in
            row == 0 || point.y >= (layout.rowBounds(row - 1).maxY + layout.rowBounds(row).minY) / 2
        } ?? 0
        let column = layout.columnIndices.last { column in
            column == 0 || point.x >= (layout.columnBounds(column - 1).maxX + layout.columnBounds(column).minX) / 2
        } ?? 0
        return TableCellPosition(row: row, column: column)
    }

    /// Where the edited cell is drawn, or, for a row not laid out yet, below the last row.
    func frame(of cell: TableCellPosition, in layout: TableCellGrid) -> CGRect? {
        if cell.row < layout.numberOfRows, cell.column < layout.numberOfColumns {
            return layout.cellBounds(row: cell.row, column: cell.column)
        }
        guard let lastEditingFrame else { return nil }
        guard cell.row >= layout.numberOfRows, layout.numberOfRows > 0, cell.column < layout.numberOfColumns else { return lastEditingFrame }
        let columnBounds = layout.cellBounds(row: layout.numberOfRows - 1, column: cell.column)
        return CGRect(x: columnBounds.minX, y: columnBounds.maxY, width: columnBounds.width, height: columnBounds.height)
    }
}

/// Puts the cell editing layer over a table while a `LivePreviewTableEditor` is in the
/// environment; reading view's tables get nothing.
struct LivePreviewTableEditingOverlay: ViewModifier {
    @Environment(\.livePreviewTableEditor) private var editor

    func body(content: Content) -> some View {
        if let editor, editor.canEdit {
            content
                .onPreferenceChange(ZoomablePictureFrame.Key.self) { frames in editor.pictureFrames = frames }
                .textual.interactiveTableOverlay { layout, links in
                    LivePreviewTableEditingLayer(layout: TableCellGrid(layout), linkAt: links.url(at:), editor: editor)
                }
        } else {
            content
        }
    }
}

/// Leaves a control of a table's editing layer out of the text selection's overlay, which covers the
/// block's text and took the touches of the "+" strips beside the table (HUNT-328).
struct TableControlOutsideTextSelection: ViewModifier {
    func body(content: Content) -> some View {
        content.textual.excludedFromTextInteraction()
    }
}

extension TableCellGrid {
    /// The cells as Textual laid them out.
    init(_ layout: StructuredText.TableLayout) {
        self.init(rowBounds: layout.rowIndices.map(layout.rowBounds), columnBounds: layout.columnIndices.map(layout.columnBounds), bounds: layout.bounds)
    }
}

/// Where a picture of the vault is drawn inside a rendered block, which the block's own tap
/// targets (a table's cell editor) need to leave the picture's tap to its zoom.
struct ZoomablePictureFrame: Equatable {
    let path: VaultPath
    /// In the block's coordinate space (`LivePreviewTableEditor.blockCoordinateSpaceName`).
    let frame: CGRect
    /// A Graphite drawing, which the menu offers to edit rather than to draw on.
    var isEditableDrawing = false
    /// The pixels shown, which the menu's "Copy Image" copies; nil where the menu has no copy.
    var shownImage: CGImage? = nil

    static func == (leftFrame: ZoomablePictureFrame, rightFrame: ZoomablePictureFrame) -> Bool {
        leftFrame.path == rightFrame.path && leftFrame.frame == rightFrame.frame && leftFrame.isEditableDrawing == rightFrame.isEditableDrawing
            && leftFrame.shownImage === rightFrame.shownImage
    }

    struct Key: PreferenceKey {
        static let defaultValue: [ZoomablePictureFrame] = []
        static func reduce(value: inout [ZoomablePictureFrame], nextValue: () -> [ZoomablePictureFrame]) { value += nextValue() }
    }
}
