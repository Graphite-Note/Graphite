/**
 * File: LivePreviewTableEditing.swift
 * -----------------------------------
 * Layer: UI
 * Description: Editing a rendered table's cells in place, its cell commands and its "+" strips.
 *
 * Authors: Bahey Shalash
 * Version: 0.6
 * Date: 11/11/2026
 */

import SwiftUI
import GraphiteCore
import Textual

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

/// Edits a Live Preview table's cells in place, as Obsidian does: a tap on a cell opens an
/// editor over it holding the cell's Markdown, Tab and Shift-Tab go to the next and previous
/// cell, Return to the cell below, and the block's menu adds, moves and removes rows and
/// columns. Each change is written into the note as one edit of that cell's characters only
/// (`MarkdownTableEditing`): when typing pauses, and when the editor moves or closes.
///
/// One per table view, kept by the view; what it reads from the view (the table's source and
/// the way to edit it) is given again at every update, without making the view draw again.
@MainActor
@Observable
final class LivePreviewTableEditor {
    /// The coordinate space of a rendered block's whole view, which its menu's points are in.
    nonisolated static let blockCoordinateSpaceName = "LivePreviewRenderedBlock"
    /// How long typing pauses before the cell is written into the note.
    private static let commitDelay: Duration = .milliseconds(400)

    private(set) var editingCell: TableCellPosition?
    /// The cell the command palette's and the Edit menu's table commands act on: the edited
    /// cell, or the one last edited once its editor closed, as when the palette took the keyboard.
    private(set) var commandCell: TableCellPosition?
    /// Asks the cell editor to take the keyboard: it changes when editing begins.
    private(set) var focusRequest = 0
    /// The edited cell's text, as `MarkdownTableEditing.editableText(ofCellSource:)` shows it.
    var draftText = "" {
        didSet { if draftText != oldValue { draftDidChange(from: oldValue) } }
    }

    @ObservationIgnored private(set) var textSize: Double = 16
    @ObservationIgnored private var tableSource: String?
    @ObservationIgnored private var table: MarkdownTable?
    @ObservationIgnored private var sourceEditing: RenderedBlockSourceEditing?
    /// The draft as last written into the note, or as the cell had it.
    @ObservationIgnored private var committedDraft = ""
    /// The cell's text in the table as this editor last left it: what the draft reads as once
    /// written, which can differ from the draft (spaces at its ends).
    @ObservationIgnored private var cellTextAsWritten: String?
    @ObservationIgnored private var commitTask: Task<Void, Never>?
    /// The table's cells as last laid out, and where the table is in the block's view, which
    /// the "+" strips stay inside.
    @ObservationIgnored var layout: StructuredText.TableLayout?
    @ObservationIgnored var tablePlacement = TablePlacementInBlock()
    var tableOriginInBlock: CGPoint { tablePlacement.origin }
    /// Where the vault's pictures in the table's cells are, in the block's coordinates: a tap
    /// on one zooms into it rather than editing its cell.
    @ObservationIgnored var pictureFrames: [ZoomablePictureFrame] = []
    /// Where the edited cell was last drawn, for a cell the table has not laid out yet (a
    /// row just added), so the editor and its keyboard stay.
    @ObservationIgnored var lastEditingFrame: CGRect?

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

    private static func text(ofCell cell: TableCellPosition, in table: MarkdownTable?) -> String? {
        guard let table, cell.row < table.rows.count, cell.column < table.columnCount else { return nil }
        let cellSource = cell.column < table.rows[cell.row].count ? table.rows[cell.row][cell.column].source : ""
        return MarkdownTableEditing.editableText(ofCellSource: cellSource)
    }

    /// The cell changed in the note, not through this editor, as the top bar's Undo does: the
    /// field shows what the note has now. It kept the old text, and the next key wrote all of
    /// it back, redoing what was undone. After the view's update, which this runs in.
    private func reloadDraftIfTheCellChangedElsewhere() {
        guard let cell = editingCell, let cellText = cellTextInTable, cellText != cellTextAsWritten else { return }
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

    func beginEditing(at point: CGPoint) {
        guard let layout, let cell = Self.cell(at: point, in: layout) else { return }
        beginEditing(cell)
    }

    func beginEditing(_ cell: TableCellPosition) {
        guard let table, cell.row < table.rows.count, cell.column < table.columnCount else { return }
        let cellSource = cell.column < table.rows[cell.row].count ? table.rows[cell.row][cell.column].source : ""
        startEditing(cell, text: MarkdownTableEditing.editableText(ofCellSource: cellSource))
    }

    private func startEditing(_ cell: TableCellPosition, text: String) {
        // The text and the place were worked out from the cells as they were before the draft.
        guard !draftMovesOtherCells else { return commitDraft() }
        commitDraft()
        if editingCell == nil {
            TableCellTextField.endEditingInOtherTables()
            sourceEditing?.setIsEditingInView(true, ObjectIdentifier(self))
            sourceEditing?.setDraftCommit(ObjectIdentifier(self)) { [weak self] in self?.commitDraft() }
        }
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
        lastEditingFrame = nil
        sourceEditing?.setDraftCommit(ObjectIdentifier(self), nil)
        sourceEditing?.setIsEditingInView(false, ObjectIdentifier(self))
    }

    private func replaceSource(_ transform: @escaping (String) -> String?) {
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
    private var draftMovesOtherCells: Bool {
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
        case next, previous, up, down
    }

    /// The keys of the cell editor, as in Obsidian: Return goes to the cell below, Tab and
    /// Shift-Tab to the next and previous cell, Escape closes the editor, and the arrows leave
    /// a cell of one line. Whether the key was taken; one that was not is typed as usual.
    func handle(_ key: TableCellKey) -> Bool {
        guard editingCell != nil else { return false }
        switch key {
        case .returnKey: move(.down)
        case .tab: move(.next)
        case .backtab: move(.previous)
        case .escape: endEditing()
        case .upArrow, .downArrow:
            guard !draftText.contains(where: \.isNewline) else { return false }
            move(key == .upArrow ? .up : .down)
        }
        return true
    }

    /// Moves the editor; past the last cell (Tab) or the last row (Return) it adds a row, as
    /// Obsidian does.
    func move(_ movement: Movement) {
        guard let cell = editingCell, let table else { return }
        let lastRow = table.rows.count - 1
        let lastColumn = table.columnCount - 1
        switch movement {
        case .next:
            if cell.column < lastColumn { beginEditing(TableCellPosition(row: cell.row, column: cell.column + 1)) }
            else if cell.row < lastRow { beginEditing(TableCellPosition(row: cell.row + 1, column: 0)) }
            else { appendRow(editingColumn: 0) }
        case .previous:
            if cell.column > 0 { beginEditing(TableCellPosition(row: cell.row, column: cell.column - 1)) }
            else if cell.row > 0 { beginEditing(TableCellPosition(row: cell.row - 1, column: lastColumn)) }
        case .up:
            if cell.row > 0 { beginEditing(TableCellPosition(row: cell.row - 1, column: cell.column)) }
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
        replaceSource { source in
            guard let bodyRowCount = MarkdownTable.parse(source)?.bodyRowCount else { return nil }
            return MarkdownTableEditing.insertingRow(atBodyIndex: bodyRowCount, in: source)
        }
        startEditing(TableCellPosition(row: newRow, column: column), text: "")
    }

    // MARK: Rows and columns

    /// The cell menu's commands (`TableCellCommand`) for the cell at `point`, in the block
    /// view's coordinates; for the edited cell when the point is not on one.
    func menuItems(at point: CGPoint) -> [RenderedBlockMenuItem] {
        guard let table, sourceEditing != nil, let cell = menuCell(at: point) else { return [] }
        return TableCellCommand.menuItems(at: cell, in: table) { [weak self] command in self?.perform(command, at: cell) }
    }

    private func menuCell(at point: CGPoint) -> TableCellPosition? {
        let pointInTable = CGPoint(x: point.x - tableOriginInBlock.x, y: point.y - tableOriginInBlock.y)
        let tableBounds = layout?.bounds ?? .null
        let pointedCell = tableBounds.insetBy(dx: -4, dy: -4).contains(pointInTable) ? layout.flatMap { layout in Self.cell(at: pointInTable, in: layout) } : nil
        return pointedCell ?? editingCell
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

    private func perform(_ command: TableCellCommand, at cell: TableCellPosition) {
        guard let table, command.isAvailable(at: cell, in: table) else { return }
        changeTable(command.edit(at: cell, in: table))
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

    /// A change of rows or columns closes the cell editor first, writing its draft: the cells
    /// move under it.
    private func changeTable(_ transform: @escaping (String) -> String?) {
        let commandStillReachesItsCells = !draftMovesOtherCells
        endEditing()
        if commandStillReachesItsCells { replaceSource(transform) }
    }

    // MARK: Geometry

    /// The cell whose row and column contain `point`, in the table's coordinates; a point in
    /// the gap between cells goes to the nearer one, and one past an edge to the edge cell.
    static func cell(at point: CGPoint, in layout: StructuredText.TableLayout) -> TableCellPosition? {
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
    func frame(of cell: TableCellPosition, in layout: StructuredText.TableLayout) -> CGRect? {
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
                .textual.interactiveTableOverlay { layout in
                    LivePreviewTableEditingLayer(layout: layout, editor: editor)
                }
        } else {
            content
        }
    }
}

/// A tap target over the whole table, the edited cell's text field over that cell, and the
/// "+" strips that add a column and a row while the pointer is over the table or a cell is edited.
private struct LivePreviewTableEditingLayer: View {
    let layout: StructuredText.TableLayout
    @Bindable var editor: LivePreviewTableEditor
    @Environment(\.noteTypography) private var typography
    @Environment(\.noteTheme) private var theme
    @Environment(\.accent) private var accent
    @Environment(\.readingImageActions) private var imageActions
    @State private var isPointerOverTable = false
    @State private var isPointerOverStrip = false
    /// The picture the pointer rests on, whose magnifier and "Open in New Tab" show over it.
    @State private var hoveredPicture: ZoomablePictureFrame?

    private var showsAddStrips: Bool { isPointerOverTable || isPointerOverStrip || editor.editingCell != nil }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture(coordinateSpace: .local) { location in tapped(at: location) }
                #if os(macOS)
                // ⌘-click on a picture opens it in a new tab, as for a link; the gesture waits for ⌘.
                // SwiftUI gives the iPad no modifier keys on a tap; the table's menu has the command.
                .highPriorityGesture(SpatialTapGesture(coordinateSpace: .local).modifiers(.command).onEnded { tap in commandClicked(at: tap.location) },
                                     including: imageActions?.tabOpening == nil ? .none : .all)
                #endif
            if let cell = editor.editingCell, let frame = editor.frame(of: cell, in: layout) {
                cellField(for: cell, frame: frame)
            }
            if let hoveredPicture, let imageActions, editor.editingCell == nil {
                pictureButtons(for: hoveredPicture, actions: imageActions)
            }
            if showsAddStrips {
                LivePreviewTableAddStrips(geometry: TableAddStripsGeometry(tableBounds: layout.bounds, blockBounds: editor.tablePlacement.blockBoundsInTable),
                                          editor: editor, isPointerOverStrip: $isPointerOverStrip)
            }
        }
        .onGeometryChange(for: TablePlacementInBlock.self) { geometry in
            let frame = geometry.frame(in: .named(LivePreviewTableEditor.blockCoordinateSpaceName))
            let blockSize = geometry.bounds(of: .named(LivePreviewTableEditor.blockCoordinateSpaceName))?.size ?? frame.size
            return TablePlacementInBlock(origin: frame.origin, blockSize: blockSize)
        } action: { placement in
            editor.tablePlacement = placement
        }
        .onChange(of: layout, initial: true) { _, newLayout in editor.layout = newLayout }
        // The pointer, or an Apple Pencil held over the iPad's screen, shows the strips, and over a
        // picture its buttons; on the whole layer, so moving onto the buttons stays over the table.
        .onContinuousHover(coordinateSpace: .local) { phase in pointerMoved(phase) }
        // Text selection's overlay would otherwise take the taps.
        .textual.excludedFromTextInteraction()
    }

    private func pointerMoved(_ phase: HoverPhase) {
        switch phase {
        case .active(let location):
            if !isPointerOverTable { isPointerOverTable = true }
            let picture = imageActions == nil ? nil : editor.pictureFrames.last { picture in picture.frame.contains(pointInBlock(location)) }
            if picture != hoveredPicture { hoveredPicture = picture }
        case .ended:
            isPointerOverTable = false
            hoveredPicture = nil
        }
    }

    private func pointInBlock(_ location: CGPoint) -> CGPoint {
        CGPoint(x: location.x + editor.tableOriginInBlock.x, y: location.y + editor.tableOriginInBlock.y)
    }

    /// The magnifier and "Open in New Tab" at the picture's top-right corner, in the layer's coordinates.
    private func pictureButtons(for picture: ZoomablePictureFrame, actions: ReadingImageActions) -> some View {
        let frame = picture.frame.offsetBy(dx: -editor.tableOriginInBlock.x, dy: -editor.tableOriginInBlock.y)
        return PictureHoverButtons(zoom: { actions.perform(.zoomIn, on: picture.path) },
                                   openInNewTab: actions.tabOpening == nil ? nil : { actions.perform(.openInNewTab, on: picture.path) })
            .frame(width: frame.width, alignment: .topTrailing)
            .offset(x: frame.minX, y: frame.minY)
    }

    #if os(macOS)
    /// ⌘-click on a picture opens it in a tab; anywhere else it edits the cell, as a click does.
    private func commandClicked(at location: CGPoint) {
        if let imageActions, let picture = editor.pictureFrames.last(where: { picture in picture.frame.contains(pointInBlock(location)) }),
           imageActions.open(picture.path, clickedWith: .command) {
            return
        }
        tapped(at: location)
    }
    #endif

    /// A tap on a picture zooms into it; anywhere else in a cell edits the cell.
    private func tapped(at location: CGPoint) {
        if let viewImage = imageActions?.viewImage, let picture = editor.pictureFrames.last(where: { picture in picture.frame.contains(pointInBlock(location)) }) {
            viewImage(picture.path)
            return
        }
        editor.beginEditing(at: location)
    }

    private func cellField(for cell: TableCellPosition, frame: CGRect) -> some View {
        let textSize = editor.textSize
        return TableCellTextField(text: $editor.draftText,
                                  font: typography.textFont(ofSize: textSize, weight: cell.row == 0 ? .semibold : .regular),
                                  focusRequest: editor.focusRequest, handleKey: editor.handle,
                                  focusDidChange: { isFocused in
                                      // Focus going elsewhere, such as a tap in the note's text, closes the editor.
                                      if !isFocused { editor.focusDidLeave() }
                                  })
            .padding(.vertical, textSize * 0.35)
            .padding(.horizontal, textSize * 0.6)
            // Centered in the row's height, as the rendered cells are.
            .frame(width: frame.width, alignment: .leading)
            .frame(minHeight: frame.height, alignment: .leading)
            .background(theme?.background.map { color in AnyShapeStyle(Color(color)) } ?? AnyShapeStyle(.background))
            .overlay(Rectangle().stroke(accent, lineWidth: 2))
            .offset(x: frame.minX, y: frame.minY)
            .onAppear { editor.lastEditingFrame = frame }
            .onChange(of: frame) { _, newFrame in editor.lastEditingFrame = newFrame }
    }
}

/// Where a picture of the vault is drawn inside a rendered block, which the block's own tap
/// targets (a table's cell editor) need to leave the picture's tap to its zoom.
struct ZoomablePictureFrame: Equatable {
    let path: VaultPath
    /// In the block's coordinate space (`LivePreviewTableEditor.blockCoordinateSpaceName`).
    let frame: CGRect

    struct Key: PreferenceKey {
        static let defaultValue: [ZoomablePictureFrame] = []
        static func reduce(value: inout [ZoomablePictureFrame], nextValue: () -> [ZoomablePictureFrame]) { value += nextValue() }
    }
}
