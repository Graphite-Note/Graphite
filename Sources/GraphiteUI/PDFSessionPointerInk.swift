/**
 * File: PDFSessionPointerInk.swift
 * --------------------------------
 * Layer: UI
 * Description: Ink a mouse or trackpad draws and erases on a PDF page, written into the page's editable ink group as
 *              the iPad's Pencil ink is, with one step of the PDF's history per stroke drawn or per pass of the eraser.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 13/11/2026
 */

import Foundation
import PDFKit
import PencilKit
import GraphiteCore
import GraphiteApple

/// A page's editable ink as the pointer's tools change it: the tracker that names its
/// annotations, the drawing they show, and the page's edit count when both were read, so
/// a change made elsewhere (an undo, the iPad's file) is read again rather than overwritten.
struct PDFPointerPageInk {
    var tracker: PDFPageInkTracker
    var drawing: PKDrawing
    var pageEditCount: Int
}

extension PDFSession {
    /// The page's editable ink to change, as kept in `cached` while the page has not
    /// changed since, otherwise read from the page's stored record.
    func pointerInk(on page: PDFPage, cached: PDFPointerPageInk?) throws -> PDFPointerPageInk {
        let pageEditCount = editCount(of: page)
        if let cached, cached.pageEditCount == pageEditCount { return cached }
        let stored = try Self.editableInk(on: page)
        return PDFPointerPageInk(tracker: stored.tracker, drawing: stored.drawing, pageEditCount: pageEditCount)
    }

    /// Adds one stroke after the page's others, as one step of the history named as the
    /// iPad's strokes are ("Drawing"). Returns the page's ink with the stroke.
    func addPointerStroke(_ stroke: PKStroke, on page: PDFPage, to ink: PDFPointerPageInk) throws -> PDFPointerPageInk {
        let drawingAfter = PKDrawing(strokes: ink.drawing.strokes + [stroke])
        let changed = try changePointerInk(ink, to: drawingAfter, on: page)
        if let change = PencilDrawingChange(appendingLastStrokeOf: drawingAfter, to: ink.drawing) {
            registerInkChange(change, on: page, overlaySize: page.bounds(for: .cropBox).size)
        }
        return changed
    }

    /// Removes the strokes at `strokeIndices` of the page's drawing. The eraser removes
    /// strokes as it passes them and records the whole pass as one step when it is let go
    /// (`registerPointerInkStep`).
    func removePointerStrokes(at strokeIndices: [Int], on page: PDFPage, from ink: PDFPointerPageInk) throws -> PDFPointerPageInk {
        let removed = Set(strokeIndices)
        let remaining = ink.drawing.strokes.enumerated().filter { position, _ in !removed.contains(position) }.map { _, stroke in stroke }
        guard remaining.count != ink.drawing.strokes.count else { return ink }
        return try changePointerInk(ink, to: PKDrawing(strokes: remaining), on: page)
    }

    /// Records, as one step, everything the pointer changed of a page's ink since `drawingBefore`.
    func registerPointerInkStep(from drawingBefore: PKDrawing, to drawingAfter: PKDrawing, on page: PDFPage) {
        guard let change = PencilDrawingChange(from: drawingBefore, to: drawingAfter) else { return }
        registerInkChange(change, on: page, overlaySize: page.bounds(for: .cropBox).size)
    }

    /// Writes the page's annotations and re-editing record for `drawingAfter`. The record is
    /// written at once, not deferred as the iPad's canvas defers it: no canvas keeps the
    /// drawing on the Mac, and the pointer's strokes come seconds apart, not many a second.
    private func changePointerInk(_ ink: PDFPointerPageInk, to drawingAfter: PKDrawing, on page: PDFPage) throws -> PDFPointerPageInk {
        let pageIndex = try currentIndex(of: historyPage(for: page))
        var tracker = ink.tracker
        let coordinates = try PDFPointerInk.coordinates(of: page.bounds(for: .cropBox))
        try apply(.updateInk(tracker.update(for: drawingAfter, pageIndex: pageIndex, coordinates: coordinates)))
        return PDFPointerPageInk(tracker: tracker, drawing: drawingAfter, pageEditCount: editCount(of: page))
    }
}
