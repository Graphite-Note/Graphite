/**
 * File: MarkdownTableRangeEditing.swift
 * -------------------------------------
 * Layer: Core
 * Description: Table edits Obsidian's table editor makes beyond one row or column: a row above the header, any row moved,
 *              ranges of cells, copying and pasting grids.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 17/11/2026
 */

import Foundation

/// A rectangle of a table's cells, both ends included. Row 0 is the header.
public struct MarkdownTableCellRange: Equatable, Sendable {
    public let rows: ClosedRange<Int>
    public let columns: ClosedRange<Int>

    public init(rows: ClosedRange<Int>, columns: ClosedRange<Int>) {
        self.rows = rows
        self.columns = columns
    }

    /// The rectangle with these two cells at its corners, in any order.
    public init(anchorRow: Int, anchorColumn: Int, headRow: Int, headColumn: Int) {
        rows = min(anchorRow, headRow)...max(anchorRow, headRow)
        columns = min(anchorColumn, headColumn)...max(anchorColumn, headColumn)
    }
}

/// Cells copied from a table: their source text as written (escapes and `<br>` kept) and the
/// copied columns' alignment, which a paste on a header row brings along.
public struct MarkdownTableGrid: Equatable, Sendable, Codable {
    public let rows: [[String]]
    public let alignments: [MarkdownTable.ColumnAlignment]

    public init(rows: [[String]], alignments: [MarkdownTable.ColumnAlignment]) {
        self.rows = rows
        self.alignments = alignments
    }

    /// The cells of a whole Markdown table, as text copied from elsewhere gives it; nil for
    /// text that is not a table.
    public init?(markdownTable text: String) {
        guard let table = MarkdownTable.parse(text.trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
        rows = table.rows.map { cells in (0..<table.columnCount).map { column in column < cells.count ? cells[column].source : "" } }
        alignments = table.alignments
    }

    /// An aligned Markdown table of the grid, as Obsidian copies cells: the first row is the
    /// header, each column padded to its widest cell (at least three characters).
    public var markdownTable: String {
        let columnCount = rows.map(\.count).max() ?? 0
        guard columnCount > 0 else { return "" }
        let widths = (0..<columnCount).map { column in
            max(Self.minimumColumnWidth, rows.map { cells in column < cells.count ? cells[column].count : 0 }.max() ?? 0)
        }
        func line(_ cells: [String]) -> String {
            "|" + (0..<columnCount).map { column in
                let text = column < cells.count ? cells[column] : ""
                return " " + Self.padded(text, to: widths[column], alignment: column < alignments.count ? alignments[column] : .none) + " |"
            }.joined()
        }
        let delimiter = "|" + (0..<columnCount).map { column in
            " " + Self.delimiter(column < alignments.count ? alignments[column] : .none, width: widths[column]) + " |"
        }.joined()
        var lines = [line(rows[0]), delimiter]
        lines += rows.dropFirst().map(line)
        return lines.joined(separator: "\n")
    }

    /// The grid as an HTML table, for apps that paste rich text.
    public var htmlTable: String {
        func escaped(_ text: String) -> String {
            MarkdownTableEditing.editableText(ofCellSource: text)
                .replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\n", with: "<br>")
        }
        guard let header = rows.first else { return "" }
        let head = "<thead><tr>" + header.map { "<th>" + escaped($0) + "</th>" }.joined() + "</tr></thead>"
        let body = "<tbody>" + rows.dropFirst().map { cells in "<tr>" + cells.map { "<td>" + escaped($0) + "</td>" }.joined() + "</tr>" }.joined() + "</tbody>"
        return "<table>" + head + body + "</table>"
    }

    private static let minimumColumnWidth = 3

    private static func padded(_ text: String, to width: Int, alignment: MarkdownTable.ColumnAlignment) -> String {
        let room = max(0, width - text.count)
        switch alignment {
        case .right: return String(repeating: " ", count: room) + text
        case .center: return String(repeating: " ", count: room / 2) + text + String(repeating: " ", count: room - room / 2)
        case .left, .none: return text + String(repeating: " ", count: room)
        }
    }

    private static func delimiter(_ alignment: MarkdownTable.ColumnAlignment, width: Int) -> String {
        switch alignment {
        case .none: return String(repeating: "-", count: width)
        case .left: return ":" + String(repeating: "-", count: width - 1)
        case .right: return String(repeating: "-", count: width - 1) + ":"
        case .center: return ":" + String(repeating: "-", count: width - 2) + ":"
        }
    }
}

extension MarkdownTableGrid {
    private enum CodingKeys: String, CodingKey { case rows, alignments }

    /// The alignments as Obsidian names them in its own table pasteboard type.
    private static let alignmentNames: [(MarkdownTable.ColumnAlignment, String)] = [(.none, ""), (.left, "left"), (.center, "center"), (.right, "right")]

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        rows = try container.decode([[String]].self, forKey: .rows)
        let names = try container.decode([String].self, forKey: .alignments)
        alignments = names.map { name in Self.alignmentNames.first { $0.1 == name }?.0 ?? .none }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(rows, forKey: .rows)
        try container.encode(alignments.map { alignment in Self.alignmentNames.first { $0.0 == alignment }?.1 ?? "" }, forKey: .alignments)
    }
}

public extension MarkdownTableEditing {
    // MARK: Rows

    /// Inserts an empty header above the table: the old header becomes the first body row, as
    /// Obsidian's Shift-Tab in the first cell does.
    static func insertingRowAboveHeader(in source: String) -> String? {
        guard let layout = MarkdownTableLayout(source: source) else { return nil }
        let header = layout.header
        let oldHeader = Array(layout.units[header.contentRange])
        let emptyHeader = layout.emptyRowUnits()
        return layout.applying([MarkdownTableReplacement(range: header.contentRange, units: emptyHeader),
                                layout.insertionOfLine(oldHeader, after: layout.delimiter)])
    }

    /// Moves row `row` (0 is the header) to `targetRow`, shifting the rows between; the header
    /// can move into the body and a body row into the header, as Obsidian's grips do.
    static func movingRow(_ row: Int, to targetRow: Int, in source: String) -> String? {
        guard let layout = MarkdownTableLayout(source: source), row >= 0, row <= layout.bodyRowCount,
              targetRow >= 0, targetRow <= layout.bodyRowCount else { return nil }
        guard row != targetRow else { return source }
        var order = Array(0...layout.bodyRowCount)
        order.insert(order.remove(at: row), at: targetRow)
        return layout.applying(layout.replacements(reorderingRowsTo: order))
    }

    // MARK: Columns

    /// Inserts an empty column at `columnIndex` with the given alignment, as Obsidian's new
    /// column takes the alignment of the one it is added beside.
    static func insertingColumn(at columnIndex: Int, alignment: MarkdownTable.ColumnAlignment, in source: String) -> String? {
        guard let inserted = insertingColumn(at: columnIndex, in: source) else { return nil }
        return settingAlignment(alignment, ofColumn: columnIndex, in: inserted)
    }

    // MARK: Ranges

    /// Empties every cell of the range that has text, in one edit.
    static func clearingCells(in range: MarkdownTableCellRange, in source: String) -> String? {
        guard let layout = MarkdownTableLayout(source: source) else { return nil }
        let empty = Dictionary(uniqueKeysWithValues: range.columns.map { column in (column, "") })
        let replacements = range.rows.filter { $0 <= layout.bodyRowCount }.flatMap { row in
            layout.replacements(settingCellTexts: empty, in: layout.rowLine(row))
        }
        return layout.applying(replacements)
    }

    /// What Backspace on a selection of cells does, as in Obsidian: whole rows selected are
    /// removed, whole columns are removed, anything else is emptied. Nil when every cell is
    /// selected: the whole table goes, which is the note's edit, not the table's.
    static func deletingCells(in range: MarkdownTableCellRange, in source: String) -> String? {
        guard let table = MarkdownTable.parse(source) else { return nil }
        let allColumns = range.columns.lowerBound == 0 && range.columns.upperBound >= table.columnCount - 1
        let allRows = range.rows.lowerBound == 0 && range.rows.upperBound >= table.bodyRowCount
        if allColumns && allRows { return nil }
        if allColumns && range.rows.lowerBound > 0 {
            var edited = source
            for row in range.rows.reversed() { edited = removingRow(atBodyIndex: row - 1, in: edited) ?? edited }
            return edited
        }
        if allRows {
            var edited = source
            for column in range.columns.reversed() { edited = removingColumn(at: column, in: edited) ?? edited }
            return edited
        }
        return clearingCells(in: range, in: source)
    }

    /// The cells of the range as a grid to copy.
    static func grid(of range: MarkdownTableCellRange, in source: String) -> MarkdownTableGrid? {
        guard let table = MarkdownTable.parse(source) else { return nil }
        let rows = range.rows.filter { $0 < table.rows.count }.map { row in
            range.columns.map { column in column < table.rows[row].count ? table.rows[row][column].source : "" }
        }
        let alignments = range.columns.map { column in column < table.alignments.count ? table.alignments[column] : .none }
        return rows.isEmpty ? nil : MarkdownTableGrid(rows: rows, alignments: alignments)
    }

    /// Writes the grid's cells from `row`, `column` on, adding rows and columns where the table
    /// is too small, as Obsidian pastes copied cells. Pasted on the header, the copied columns
    /// bring their alignment; elsewhere only columns the paste adds take it.
    static func pasting(_ grid: MarkdownTableGrid, atRow row: Int, column: Int, in source: String) -> String? {
        guard var table = MarkdownTable.parse(source), row >= 0, column >= 0, !grid.rows.isEmpty else { return nil }
        var edited = source
        let gridWidth = grid.rows.map(\.count).max() ?? 0
        let originalColumnCount = table.columnCount
        while table.columnCount < column + gridWidth {
            let added = table.columnCount
            let alignment = added - column < grid.alignments.count ? grid.alignments[added - column] : .none
            guard let widened = insertingColumn(at: added, alignment: alignment, in: edited), let parsed = MarkdownTable.parse(widened) else { return nil }
            edited = widened
            table = parsed
        }
        while table.bodyRowCount < row + grid.rows.count - 1 {
            guard let lengthened = insertingRow(atBodyIndex: table.bodyRowCount, in: edited), let parsed = MarkdownTable.parse(lengthened) else { return nil }
            edited = lengthened
            table = parsed
        }
        let columns = (0..<gridWidth).map { offset in
            (column + offset, grid.rows.map { cells in offset < cells.count ? cells[offset] : "" })
        }
        edited = settingCellSources(columns, startingAtRow: row, in: edited) ?? edited
        if row == 0 {
            for (offset, alignment) in grid.alignments.enumerated() where column + offset < originalColumnCount {
                edited = settingAlignment(alignment, ofColumn: column + offset, in: edited) ?? edited
            }
        }
        return edited
    }

    /// Sets each listed column's cells, from `startRow` down, to source text as written (already
    /// escaped for a cell), in one pass over the lines.
    private static func settingCellSources(_ columns: [(column: Int, texts: [String])], startingAtRow startRow: Int, in source: String) -> String? {
        guard let layout = MarkdownTableLayout(source: source) else { return nil }
        let rowCount = columns.map(\.texts.count).max() ?? 0
        var replacements: [MarkdownTableReplacement] = []
        for offset in 0..<rowCount where startRow + offset <= layout.bodyRowCount {
            var texts: [Int: String] = [:]
            for (column, columnTexts) in columns where offset < columnTexts.count { texts[column] = columnTexts[offset] }
            replacements += layout.replacements(settingCellTexts: texts, in: layout.rowLine(startRow + offset))
        }
        return layout.applying(replacements)
    }
}

extension MarkdownTableLayout {
    /// A new line holding `content`, right after `line`, with the table's line ending; after a
    /// last line without a line break, the break goes before the new line.
    func insertionOfLine(_ content: [UInt16], after line: MarkdownTableLineLayout) -> MarkdownTableReplacement {
        if line.endingRange.isEmpty {
            let end = line.contentRange.upperBound
            return MarkdownTableReplacement(range: end..<end, units: lineEnding + content)
        }
        let end = line.endingRange.upperBound
        return MarkdownTableReplacement(range: end..<end, units: content + lineEnding)
    }

    /// An empty row as `insertingRow` writes it, with the header's indentation.
    func emptyRowUnits() -> [UInt16] {
        let hasOuterPipes = header.hasLeadingPipe || header.hasTrailingPipe
        let rowText = hasOuterPipes ? "|" + String(repeating: "  |", count: columnCount)
                                    : Array(repeating: "", count: columnCount).joined(separator: " | ")
        let indentation = Array(units[header.contentRange.lowerBound..<header.trimmedRange.lowerBound].prefix(while: MarkdownTableUnit.isSpace))
        return indentation + Array(rowText.utf16)
    }

    /// Puts row `order[index]`'s text on row `index`'s line (0 is the header); each line
    /// break stays where it is.
    func replacements(reorderingRowsTo order: [Int]) -> [MarkdownTableReplacement] {
        order.enumerated().compactMap { destination, sourceRow in
            guard destination != sourceRow else { return nil }
            return MarkdownTableReplacement(range: rowLine(destination).contentRange, units: Array(units[rowLine(sourceRow).contentRange]))
        }
    }
}
