/**
 * File: TableCellGrid.swift
 * -------------------------
 * Layer: UI
 * Description: A rendered table's cells as last laid out, as plain rectangles, for its editor, grips and selected cells.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 17/11/2026
 */

import CoreGraphics

/// A rendered table's rows and columns as last laid out, in the table's coordinates. Textual's
/// table layout is read into it once per layout (`LivePreviewTableEditingOverlay`), so the
/// table's editor, its grips and its selected cells work from plain rectangles: a cell spans
/// its column's width and its row's height, as in Textual.
struct TableCellGrid: Equatable {
    private let rowRectangles: [CGRect]
    private let columnRectangles: [CGRect]
    /// The cells' union.
    let bounds: CGRect

    init(rowBounds: [CGRect], columnBounds: [CGRect], bounds: CGRect) {
        rowRectangles = rowBounds
        columnRectangles = columnBounds
        self.bounds = bounds
    }

    var numberOfRows: Int { rowRectangles.count }
    var numberOfColumns: Int { columnRectangles.count }
    var rowIndices: Range<Int> { rowRectangles.indices }
    var columnIndices: Range<Int> { columnRectangles.indices }

    func rowBounds(_ row: Int) -> CGRect { rowRectangles[row] }
    func columnBounds(_ column: Int) -> CGRect { columnRectangles[column] }

    func cellBounds(row: Int, column: Int) -> CGRect {
        CGRect(x: columnRectangles[column].minX, y: rowRectangles[row].minY, width: columnRectangles[column].width, height: rowRectangles[row].height)
    }
}
