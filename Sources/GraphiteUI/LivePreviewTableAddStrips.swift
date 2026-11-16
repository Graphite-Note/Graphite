/**
 * File: LivePreviewTableAddStrips.swift
 * -------------------------------------
 * Layer: UI
 * Description: The "+" strips along a Live Preview table's right and bottom edges that add a column and a row, as in
 *              Obsidian.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 12/11/2026
 */

import SwiftUI

/// Where the table is in its block's view, read in one pass of the layer's geometry.
struct TablePlacementInBlock: Equatable {
    var origin: CGPoint = .zero
    var blockSize: CGSize = .zero

    /// The block's view in the table's coordinates: what a touch or a click can reach, and so
    /// where the strips must stay, since they take no room of their own in the note.
    var blockBoundsInTable: CGRect { CGRect(x: -origin.x, y: -origin.y, width: blockSize.width, height: blockSize.height) }
}

/// Where the two strips go, in the table's coordinates. Each runs the length of its edge,
/// `gap` outside it where the block has the room, and otherwise moved in until its far side is
/// the block's edge, over the cells' padding: it never reaches past the block, so it never
/// covers the next line of the note.
struct TableAddStripsGeometry: Equatable {
    /// Along the right edge: "Add column to the right".
    let columnStrip: CGRect
    /// Along the bottom edge: "Add row below".
    let rowStrip: CGRect

    static let thickness: CGFloat = 14
    static let gap: CGFloat = 2

    /// - Parameter blockBounds: The block's view, in the table's coordinates.
    init(tableBounds: CGRect, blockBounds: CGRect, thickness: CGFloat = Self.thickness, gap: CGFloat = Self.gap) {
        let columnStripMinX = Self.stripStart(edge: tableBounds.maxX, room: blockBounds.maxX - tableBounds.maxX, thickness: thickness, gap: gap)
        let rowStripMinY = Self.stripStart(edge: tableBounds.maxY, room: blockBounds.maxY - tableBounds.maxY, thickness: thickness, gap: gap)
        columnStrip = CGRect(x: columnStripMinX, y: tableBounds.minY, width: thickness, height: tableBounds.height)
        rowStrip = CGRect(x: tableBounds.minX, y: rowStripMinY, width: tableBounds.width, height: thickness)
    }

    /// Outside the edge when it fits, else ending at the block's edge, and at most a strip's
    /// thickness inside the table.
    private static func stripStart(edge: CGFloat, room: CGFloat, thickness: CGFloat, gap: CGFloat) -> CGFloat {
        max(min(edge + gap, edge + room - thickness), edge - thickness)
    }
}

/// The two strips, drawn over the table's editing layer while the pointer or an Apple Pencil
/// hovers over the table or a strip, and while a cell of the table is being edited, which is
/// when the iPad and the iPhone, where nothing hovers, show them. A click or a tap adds an empty
/// last column or row and opens its first cell's editor (`LivePreviewTableEditor`).
///
/// They live in the overlay every editable table already has, so a table costs no view or
/// tracking area of its own for them; and an overlay changes nothing of the table's layout, so
/// they appear and go without a layout pass.
struct LivePreviewTableAddStrips: View {
    let geometry: TableAddStripsGeometry
    let editor: LivePreviewTableEditor
    /// Whether the pointer is over a strip, which keeps them shown past the table's edge.
    @Binding var isPointerOverStrip: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            AddStrip(title: "Add column to the right", frame: geometry.columnStrip, isPointerOverStrip: $isPointerOverStrip) {
                editor.addColumnAtTheEnd()
            }
            AddStrip(title: "Add row below", frame: geometry.rowStrip, isPointerOverStrip: $isPointerOverStrip) {
                editor.addRowAtTheEnd()
            }
        }
    }
}

/// One thin strip with a "+" in its middle. The whole strip takes a click; with touch, which
/// needs a target of 44 points, the "+" takes a tap 44 points across around it, the rest of the
/// strip leaving its touches to the cells under it.
private struct AddStrip: View {
    let title: String
    let frame: CGRect
    @Binding var isPointerOverStrip: Bool
    let add: () -> Void
    @Environment(\.accent) private var accent
    @State private var isHighlighted = false

    #if canImport(UIKit)
    private static let touchTargetSide: CGFloat = 44
    #endif

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 3)
                .fill(isHighlighted ? AnyShapeStyle(accent.opacity(0.22)) : AnyShapeStyle(.secondary.opacity(0.14)))
            Image(systemName: "plus")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(isHighlighted ? AnyShapeStyle(accent) : AnyShapeStyle(.secondary))
        }
        .frame(width: frame.width, height: frame.height)
        .contentShape(Rectangle())
        #if canImport(UIKit)
        .allowsHitTesting(false)
        .overlay {
            Color.clear
                .frame(width: Self.touchTargetSide, height: Self.touchTargetSide)
                .contentShape(Rectangle())
                .onTapGesture(perform: add)
                // Outside the table, the text selection's overlay took the tap (HUNT-328): only
                // the table layer itself was left out of it.
                .modifier(TableControlOutsideTextSelection())
        }
        #else
        .onTapGesture(perform: add)
        .modifier(TableControlOutsideTextSelection())
        #endif
        .onHover { isOver in
            isHighlighted = isOver
            isPointerOverStrip = isOver
        }
        .help(title)
        .accessibilityElement()
        .accessibilityLabel(title)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(.default, add)
        .offset(x: frame.minX, y: frame.minY)
    }
}
