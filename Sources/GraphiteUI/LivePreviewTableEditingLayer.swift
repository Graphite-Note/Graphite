/**
 * File: LivePreviewTableEditingLayer.swift
 * ----------------------------------------
 * Layer: UI
 * Description: The layer a Live Preview table's editor draws over the table: its tap target, the edited cell's field, the selected
 *              cells' outline, the "+" strips and the grips, from the table's cells as laid out (`TableCellGrid`).
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 17/11/2026
 */

import SwiftUI
import GraphiteCore

/// A tap target over the whole table, the edited cell's text field over that cell, and the
/// "+" strips that add a column and a row while the pointer is over the table or a cell is edited.
struct LivePreviewTableEditingLayer: View {
    let layout: TableCellGrid
    /// The link at a point of the table: this layer takes the table's taps from the text
    /// selection overlay, which would otherwise follow them.
    let linkAt: (CGPoint) -> URL?
    @Bindable var editor: LivePreviewTableEditor
    @Environment(\.openURL) private var openURL
    @Environment(\.noteTypography) private var typography
    @Environment(\.noteTheme) private var theme
    @Environment(\.accent) private var accent
    @Environment(\.readingImageActions) private var imageActions
    @State private var isPointerOverTable = false
    @State private var isPointerOverStrip = false
    /// The picture the pointer rests on, whose magnifier and "Open in New Tab" show over it.
    @State private var hoveredPicture: ZoomablePictureFrame?
    /// The cell under the pointer, whose row and column show their grips.
    @State private var hoveredCell: TableCellPosition?

    private var showsAddStrips: Bool { isPointerOverTable || isPointerOverStrip || editor.editingCell != nil }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture(coordinateSpace: .local) { location in tapped(at: location) }
                .modifier(TableCellSelectionGesture(layout: layout, editor: editor))
                #if os(macOS)
                // ⌘-click on a picture opens it in a new tab, as for a link; the gesture waits for ⌘.
                // SwiftUI gives the iPad no modifier keys on a tap; the table's menu has the command.
                .highPriorityGesture(SpatialTapGesture(coordinateSpace: .local).modifiers(.command).onEnded { tap in commandClicked(at: tap.location) },
                                     including: imageActions?.tabOpening == nil ? .none : .all)
                #endif
            if let cell = editor.editingCell, let frame = editor.frame(of: cell, in: layout) {
                cellField(for: cell, frame: frame)
            }
            if let selection = editor.selectionFrame(in: layout) {
                TableCellSelectionOutline(frame: selection)
            }
            if let hoveredPicture, let imageActions, editor.editingCell == nil {
                pictureButtons(for: hoveredPicture, actions: imageActions)
            }
            if showsAddStrips {
                LivePreviewTableAddStrips(geometry: TableAddStripsGeometry(tableBounds: layout.bounds, blockBounds: editor.tablePlacement.blockBoundsInTable),
                                          editor: editor, isPointerOverStrip: $isPointerOverStrip)
                LivePreviewTableGrips(layout: layout, editor: editor, hoveredCell: hoveredCell)
            }
        }
        .coordinateSpace(.named(TableCellSelectionGesture.coordinateSpaceName))
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
        .modifier(TableControlOutsideTextSelection())
    }

    private func pointerMoved(_ phase: HoverPhase) {
        switch phase {
        case .active(let location):
            if !isPointerOverTable { isPointerOverTable = true }
            let cell = layout.bounds.contains(location) ? LivePreviewTableEditor.cell(at: location, in: layout) : hoveredCell
            if cell != hoveredCell { hoveredCell = cell }
            let picture = imageActions == nil ? nil : editor.pictureFrames.last { picture in picture.frame.contains(pointInBlock(location)) }
            if picture != hoveredPicture { hoveredPicture = picture }
        case .ended:
            isPointerOverTable = false
            hoveredPicture = nil
            // The cell stays: moving onto its grip, outside the table, keeps the grip shown.
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

    /// A tap on a picture zooms into it and one on a link follows it, as in Obsidian's Live
    /// Preview; anywhere else in a cell edits the cell, the caret where the tap was. On the Mac
    /// a Shift-click selects from the edited cell, a fourth click the table.
    private func tapped(at location: CGPoint) {
        if let viewImage = imageActions?.viewImage, let picture = editor.pictureFrames.last(where: { picture in picture.frame.contains(pointInBlock(location)) }) {
            viewImage(picture.path)
            return
        }
        if let url = linkAt(location) {
            editor.endEditing()
            openURL(url)
            return
        }
        #if os(macOS)
        if let event = NSApp?.currentEvent {
            if event.clickCount >= 4 { return editor.selectAllCells() }
            if event.modifierFlags.contains(.shift), let editedCell = editor.editingCell,
               let tappedCell = LivePreviewTableEditor.cell(at: location, in: layout) {
                return editor.selectCells(from: editedCell, to: tappedCell)
            }
        }
        #endif
        editor.beginEditing(at: location)
    }

    private func cellField(for cell: TableCellPosition, frame: CGRect) -> some View {
        let textSize = editor.textSize
        return TableCellTextField(text: $editor.draftText,
                                  font: typography.textFont(ofSize: textSize, weight: cell.row == 0 ? .semibold : .regular),
                                  focusRequest: editor.focusRequest, caret: { [editor] in editor.caret }, handleKey: editor.handle,
                                  actions: editor.fieldActions,
                                  focusDidChange: { isFocused in
                                      // Focus going elsewhere, such as a tap in the note's text, closes the editor.
                                      if !isFocused { editor.focusDidLeave() }
                                  })
            .padding(.vertical, textSize * LivePreviewTableEditor.verticalPaddingScale)
            .padding(.horizontal, textSize * LivePreviewTableEditor.horizontalPaddingScale)
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
