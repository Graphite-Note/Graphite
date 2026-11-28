/**
 * File: LivePreviewTablePointer.swift
 * -----------------------------------
 * Layer: UI
 * Description: A Live Preview table following the pointer: its "+" strips while the pointer is over it or near a strip,
 *              the grips of the cell under it and the buttons of a picture under it.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 28/11/2026
 */

import CoreGraphics

/// The pointer over a table, told by the Mac's block view (`RenderedBlockHostingView`), where SwiftUI's hover does not
/// reach the table's layer under the text selection's AppKit view (HUNT-389).
extension LivePreviewTableEditor {
    /// How far outside the table the pointer still counts as over it, so moving onto a "+" strip keeps it shown.
    static var pointerReachOutsideTable: CGFloat { TableAddStripsGeometry.thickness + TableAddStripsGeometry.gap }

    /// The pointer moved to `pointInBlock`, in the block's top-down coordinates, or left the block (nil): the strips show
    /// while it is over the table or near enough to reach a strip, the cell under it shows its grips (kept as the pointer
    /// moves off the table onto a grip), and a picture under it its buttons.
    func pointerMoved(toPointInBlock pointInBlock: CGPoint?) {
        guard let pointInBlock, let layout else {
            if isPointerOverTable { isPointerOverTable = false }
            if hoveredPicture != nil { hoveredPicture = nil }
            return
        }
        let point = CGPoint(x: pointInBlock.x - tableOriginInBlock.x, y: pointInBlock.y - tableOriginInBlock.y)
        let reach = Self.pointerReachOutsideTable
        let isOver = layout.bounds.insetBy(dx: -reach, dy: -reach).contains(point)
        if isOver != isPointerOverTable { isPointerOverTable = isOver }
        if layout.bounds.contains(point), let cell = Self.cell(at: point, in: layout), cell != hoveredCell { hoveredCell = cell }
        let picture = pictureFrames.last { picture in picture.frame.contains(pointInBlock) }
        if picture != hoveredPicture { hoveredPicture = picture }
    }
}
