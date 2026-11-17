/**
 * File: LivePreviewTableGrips.swift
 * ---------------------------------
 * Layer: UI
 * Description: A Live Preview table's grips for its rows and columns, the outline of its selected cells, and selecting cells by dragging.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 17/11/2026
 */

import SwiftUI

/// A grip being dragged: the row or column it moves, and where it would land.
private struct TableGripDrag: Equatable {
    enum Kind { case row, column }
    let kind: Kind
    let index: Int
    var target: Int
}

/// The grips of a table, as Obsidian's: one above a column and one left of a row, for the
/// pointer's cell and the edited cell (the edited cell's alone on the iPad and the iPhone,
/// where nothing hovers), and for each selected whole row or column. A click selects the row
/// or column; a drag moves it, a line showing where it lands; a secondary click or a long
/// press opens its menu (`LivePreviewTableEditor.gripMenuItems`). Drawn only while the "+"
/// strips show, in the table's editing layer, so they cost a table nothing otherwise.
struct LivePreviewTableGrips: View {
    let layout: TableCellGrid
    let editor: LivePreviewTableEditor
    let hoveredCell: TableCellPosition?
    @Environment(\.accent) private var accent
    @State private var drag: TableGripDrag?

    private var geometry: TableGripsGeometry {
        TableGripsGeometry(tableBounds: layout.bounds, blockBounds: editor.tablePlacement.blockBoundsInTable)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(columns, id: \.self) { column in
                grip(.column, index: column, frame: geometry.columnGrip(for: layout.columnBounds(column)))
            }
            ForEach(rows, id: \.self) { row in
                grip(.row, index: row, frame: geometry.rowGrip(for: layout.rowBounds(row)))
            }
            if let drag, drag.target != drag.index { dropLine(for: drag) }
        }
    }

    private var columns: [Int] {
        var columns = Set([hoveredCell?.column, editor.editingCell?.column, drag?.kind == .column ? drag?.index : nil].compactMap { $0 })
        if let range = editor.selectedRange, range.rows.count == layout.numberOfRows { columns.formUnion(range.columns) }
        return columns.filter { $0 < layout.numberOfColumns }.sorted()
    }

    private var rows: [Int] {
        var rows = Set([hoveredCell?.row, editor.editingCell?.row, drag?.kind == .row ? drag?.index : nil].compactMap { $0 })
        if let range = editor.selectedRange, range.columns.count == layout.numberOfColumns { rows.formUnion(range.rows) }
        return rows.filter { $0 < layout.numberOfRows }.sorted()
    }

    private func grip(_ kind: TableGripDrag.Kind, index: Int, frame: CGRect) -> some View {
        let title = kind == .column ? "Column \(index + 1)" : "Row \(index + 1)"
        let select = { if kind == .column { editor.selectColumn(index) } else { editor.selectRow(index) } }
        return RoundedRectangle(cornerRadius: 3)
            .fill(accent.opacity(drag?.index == index && drag?.kind == kind ? 0.35 : 0.16))
            .overlay(Image(systemName: "ellipsis").font(.system(size: 9, weight: .bold)).foregroundStyle(accent)
                .rotationEffect(.degrees(kind == .row ? 90 : 0)))
            .frame(width: frame.width, height: frame.height)
            .contentShape(Rectangle())
            .onTapGesture(perform: select)
            .gesture(dragGesture(kind, index: index))
            .modifier(TableControlOutsideTextSelection())
            .help(kind == .column ? "Click to select the column, drag to move it" : "Click to select the row, drag to move it")
            .accessibilityElement()
            .accessibilityLabel(title)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(.default, select)
            .offset(x: frame.minX, y: frame.minY)
    }

    private func dragGesture(_ kind: TableGripDrag.Kind, index: Int) -> some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .named(TableCellSelectionGesture.coordinateSpaceName))
            .onChanged { value in
                guard let cell = LivePreviewTableEditor.cell(at: value.location, in: layout) else { return }
                if drag == nil { if kind == .column { editor.selectColumn(index) } else { editor.selectRow(index) } }
                let target = kind == .column ? cell.column : cell.row
                if drag?.target != target { drag = TableGripDrag(kind: kind, index: index, target: target) }
            }
            .onEnded { _ in
                guard let finished = drag else { return }
                drag = nil
                switch finished.kind {
                case .column: editor.moveColumn(finished.index, to: finished.target)
                case .row: editor.moveRow(finished.index, to: finished.target)
                }
            }
    }

    /// Where the dragged row or column lands: beside its target, on the side it comes from.
    @ViewBuilder private func dropLine(for drag: TableGripDrag) -> some View {
        let bounds = layout.bounds
        switch drag.kind {
        case .column:
            let target = layout.columnBounds(drag.target)
            Rectangle().fill(accent).frame(width: 3, height: bounds.height)
                .offset(x: (drag.target < drag.index ? target.minX : target.maxX) - 1.5, y: bounds.minY).allowsHitTesting(false)
        case .row:
            let target = layout.rowBounds(drag.target)
            Rectangle().fill(accent).frame(width: bounds.width, height: 3)
                .offset(x: bounds.minX, y: (drag.target < drag.index ? target.minY : target.maxY) - 1.5).allowsHitTesting(false)
        }
    }
}

/// The outline of the selected cells.
struct TableCellSelectionOutline: View {
    let frame: CGRect
    @Environment(\.accent) private var accent

    var body: some View {
        Rectangle()
            .fill(accent.opacity(0.12))
            .overlay(Rectangle().stroke(accent, lineWidth: 2))
            .frame(width: frame.width, height: frame.height)
            .offset(x: frame.minX, y: frame.minY)
            .allowsHitTesting(false)
    }
}

/// Selecting cells by dragging across them: at once with the Mac's pointer, after a press held
/// a fifth of a second with a finger while a cell of the table is edited, as on Obsidian's
/// mobile apps, so a quick swipe still scrolls the note.
struct TableCellSelectionGesture: ViewModifier {
    /// The table layer's coordinate space, in which the layout's cells are.
    static let coordinateSpaceName = "LivePreviewTableEditingLayer"
    let layout: TableCellGrid
    let editor: LivePreviewTableEditor

    func body(content: Content) -> some View {
        #if canImport(UIKit)
        content.gesture(LongPressGesture(minimumDuration: 0.2)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.coordinateSpaceName)))
            .onChanged { value in
                guard case .second(true, let drag?) = value else { return }
                select(from: drag.startLocation, to: drag.location)
            }, including: editor.editingCell != nil ? .all : .subviews)
        #else
        content.gesture(DragGesture(minimumDistance: 4, coordinateSpace: .named(Self.coordinateSpaceName))
            .onChanged { value in select(from: value.startLocation, to: value.location) })
        #endif
    }

    private func select(from start: CGPoint, to end: CGPoint) {
        guard let anchor = LivePreviewTableEditor.cell(at: start, in: layout), let head = LivePreviewTableEditor.cell(at: end, in: layout) else { return }
        if anchor == head, !editor.hasCellSelection { return }
        editor.selectCells(from: anchor, to: head)
    }
}
