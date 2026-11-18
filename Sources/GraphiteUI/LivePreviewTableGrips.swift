/**
 * File: LivePreviewTableGrips.swift
 * ---------------------------------
 * Layer: UI
 * Description: A Live Preview table's grips for its rows and columns, the outline of its selected cells, and selecting cells by dragging.
 *
 * Authors: Bahey Shalash
 * Version: 0.3
 * Date: 18/11/2026
 */

import GraphiteCore
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
        TableGripsGeometry(tableBounds: layout.bounds, placement: editor.tablePlacement)
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
        let isDragged = drag?.index == index && drag?.kind == kind
        return TableGripShape(kind: kind)
            .fill(isDragged ? accent : Color.clear)
            .overlay(TableGripDots(kind: kind).fill(isDragged ? AnyShapeStyle(Color.white) : AnyShapeStyle(.tertiary))
                .frame(width: TableGripDots.iconSize, height: TableGripDots.iconSize))
            .frame(width: frame.width, height: frame.height)
            .contentShape(Rectangle())
            #if canImport(UIKit)
            // A view of UIKit's own, which the note's text view knows not to scroll for: a row's
            // grip is dragged up and down, the way the note scrolls.
            .overlay {
                TableGripTouchArea(tapped: select, changed: { location in
                    dragChanged(kind, index: index, to: CGPoint(x: frame.minX + location.x, y: frame.minY + location.y))
                }, ended: dragEnded)
            }
            #else
            .onTapGesture(perform: select)
            .gesture(dragGesture(kind, index: index))
            #endif
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
            .onChanged { value in dragChanged(kind, index: index, to: value.location) }
            .onEnded { _ in dragEnded() }
    }

    /// The grip's row or column is selected as the drag starts; it lands beside the cell under
    /// `location`, in the table layer's coordinates.
    private func dragChanged(_ kind: TableGripDrag.Kind, index: Int, to location: CGPoint) {
        guard let cell = LivePreviewTableEditor.cell(at: location, in: layout) else { return }
        if drag == nil { if kind == .column { editor.selectColumn(index) } else { editor.selectRow(index) } }
        let target = kind == .column ? cell.column : cell.row
        if drag?.target != target { drag = TableGripDrag(kind: kind, index: index, target: target) }
    }

    private func dragEnded() {
        guard let finished = drag else { return }
        drag = nil
        switch finished.kind {
        case .column: editor.moveColumn(finished.index, to: finished.target)
        case .row: editor.moveRow(finished.index, to: finished.target)
        }
    }

    /// Obsidian's drop indicator: twice its `--table-drop-indicator-half-width` of 2 px.
    private static let dropLineWidth: CGFloat = 4

    /// Where the dragged row or column lands: beside its target, on the side it comes from.
    @ViewBuilder private func dropLine(for drag: TableGripDrag) -> some View {
        let bounds = layout.bounds
        switch drag.kind {
        case .column:
            let target = layout.columnBounds(drag.target)
            RoundedRectangle(cornerRadius: 2).fill(accent).frame(width: Self.dropLineWidth, height: bounds.height)
                .offset(x: (drag.target < drag.index ? target.minX : target.maxX) - Self.dropLineWidth / 2, y: bounds.minY).allowsHitTesting(false)
        case .row:
            let target = layout.rowBounds(drag.target)
            RoundedRectangle(cornerRadius: 2).fill(accent).frame(width: bounds.width, height: Self.dropLineWidth)
                .offset(x: bounds.minX, y: (drag.target < drag.index ? target.minY : target.maxY) - Self.dropLineWidth / 2).allowsHitTesting(false)
        }
    }
}

/// The room Live Preview keeps around a table for its grips and "+" strips, as Obsidian's
/// table widget has its handles' size as padding on every side and reaches that far into the
/// note's side margins (`.cm-table-widget`: `padding: var(--table-drag-handle-size)`,
/// `margin: 0 calc(-1 * var(--size-4-4))`), so a grip or a strip never covers a cell or a line.
enum RenderedBlockTableRoom {
    /// Past the column on either side, where the note has no text: a block holding a table.
    static func beside(_ block: LivePreviewBlock) -> CGFloat {
        block.holdsEditableTable ? TableGripsGeometry.thickness : 0
    }

    /// Above and below a table's own block; nil for others, a callout's tables having the
    /// callout's padding around them.
    static func aboveAndBelow(_ block: LivePreviewBlock) -> CGFloat? {
        block.kind == .table && block.holdsEditableTable ? TableGripsGeometry.thickness : nil
    }
}

/// The outline of the selected cells, as Obsidian's: a 2 pt accent border with corners rounded
/// 4 pt over a 10 % accent fill (`--table-selection-border-width`, `-border-radius`, `--table-selection`).
struct TableCellSelectionOutline: View {
    let frame: CGRect
    @Environment(\.accent) private var accent

    var body: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(accent.opacity(0.1))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(accent, lineWidth: 2))
            .frame(width: frame.width, height: frame.height)
            .offset(x: frame.minX, y: frame.minY)
            .allowsHitTesting(false)
    }
}

/// A grip's ground, as Obsidian's: its outer corners rounded 4 pt (the top ones above a column,
/// the leading ones beside a row), its corners against the table square.
private struct TableGripShape: Shape {
    let kind: TableGripDrag.Kind

    func path(in rect: CGRect) -> Path {
        let radii = kind == .column
            ? RectangleCornerRadii(topLeading: 4, bottomLeading: 0, bottomTrailing: 0, topTrailing: 4)
            : RectangleCornerRadii(topLeading: 4, bottomLeading: 4, bottomTrailing: 0, topTrailing: 0)
        return UnevenRoundedRectangle(cornerRadii: radii).path(in: rect)
    }
}

/// Obsidian's grip icons, Lucide's `grip-horizontal` above a column and `grip-vertical` beside
/// a row: six dots on a 24-unit grid (at 5, 12 and 19 along, 9 and 15 across, 2 units wide
/// with their stroke), drawn 16 pt as its `--icon-s`.
private struct TableGripDots: Shape {
    static let iconSize: CGFloat = 16
    let kind: TableGripDrag.Kind

    func path(in rect: CGRect) -> Path {
        let unit = min(rect.width, rect.height) / 24
        var path = Path()
        for along in [5.0, 12.0, 19.0] {
            for across in [9.0, 15.0] {
                let center = kind == .column ? CGPoint(x: along, y: across) : CGPoint(x: across, y: along)
                path.addEllipse(in: CGRect(x: rect.minX + (center.x - 2) * unit, y: rect.minY + (center.y - 2) * unit,
                                           width: 4 * unit, height: 4 * unit))
            }
        }
        return path
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

#if canImport(UIKit)
/// Takes a finger's tap and drag on a table's grip with recognizers of its own. The note's text
/// view scrolls for a drag over any other part of a rendered block; it leaves this view's touches
/// alone (`TableGripTouchView`), so dragging a row's grip moves the row instead of the note.
private struct TableGripTouchArea: UIViewRepresentable {
    let tapped: () -> Void
    let changed: (CGPoint) -> Void
    let ended: () -> Void

    func makeUIView(context: Context) -> TableGripTouchView {
        let view = TableGripTouchView()
        view.addGestureRecognizer(UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tap(_:))))
        view.addGestureRecognizer(UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.pan(_:))))
        return view
    }

    func updateUIView(_ view: TableGripTouchView, context: Context) {
        context.coordinator.tapped = tapped
        context.coordinator.changed = changed
        context.coordinator.ended = ended
    }

    func makeCoordinator() -> Coordinator { Coordinator(tapped: tapped, changed: changed, ended: ended) }

    @MainActor
    final class Coordinator: NSObject {
        var tapped: () -> Void
        var changed: (CGPoint) -> Void
        var ended: () -> Void

        init(tapped: @escaping () -> Void, changed: @escaping (CGPoint) -> Void, ended: @escaping () -> Void) {
            self.tapped = tapped
            self.changed = changed
            self.ended = ended
        }

        @objc func tap(_ recognizer: UITapGestureRecognizer) { tapped() }

        /// The finger's place in the grip's own view.
        @objc func pan(_ recognizer: UIPanGestureRecognizer) {
            switch recognizer.state {
            case .began, .changed: changed(recognizer.location(in: recognizer.view))
            case .ended, .cancelled, .failed: ended()
            case .possible: break
            @unknown default: break
            }
        }
    }
}

/// The view a table's grip takes touches with on iOS.
final class TableGripTouchView: UIView {}
#endif
