/**
 * File: MacPDFPagesHeldStill.swift
 * --------------------------------
 * Layer: UI
 * Description: Keeps a Mac PDF view's pages where they are on screen when something shown or hidden above the view
 *              (the markup row, a banner) moves its top edge, so a picture dropped as the row unfolds stays under the
 *              pointer.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 17/11/2026
 */

#if os(macOS)
import AppKit
import PDFKit

/// Holds a PDF view's pages still on screen while its top edge moves and its bottom edge stays: the markup row or a
/// banner shown or hidden above the view. PDFKit keeps the pages' distance from the view's top, so they moved down
/// with the row, and a picture dropped as the drop unfolded the row ended up the row's height below the pointer that
/// dropped it (2026-11-17). A window resized, a view made wider or narrower, and a view moved whole (a PDF embedded in
/// a note that scrolls) are left as PDFKit lays them out.
@MainActor
final class MacPDFPagesHeldStill {
    /// Where the view and its pages stand in the window, in the window's points.
    private struct Place: Equatable {
        let pagesTop: CGFloat
        let viewTop: CGFloat
        let viewBottom: CGFloat
        let viewWidth: CGFloat
        let windowSize: CGSize

        func hasSameView(as other: Place) -> Bool {
            viewTop == other.viewTop && viewBottom == other.viewBottom && viewWidth == other.viewWidth && windowSize == other.windowSize
        }
    }

    private weak var view: PDFView?
    private var lastPlace: Place?

    init(view: PDFView) {
        self.view = view
    }

    /// Called at the end of each layout of the view: scrolls the pages back to where they stood when only the view's
    /// top edge moved, then notes where everything stands.
    func viewDidLayOut() {
        guard let clipView = view?.documentView?.enclosingScrollView?.contentView, let now = currentPlace() else {
            lastPlace = nil
            return
        }
        if let before = lastPlace, now.viewTop != before.viewTop, now.viewBottom == before.viewBottom, now.viewWidth == before.viewWidth,
           now.windowSize == before.windowSize, view?.inLiveResize == false {
            scroll(clipView, byWindowPoints: now.pagesTop - before.pagesTop)
        }
        lastPlace = currentPlace()
    }

    private func currentPlace() -> Place? {
        guard let view, let window = view.window, let documentView = view.documentView else { return nil }
        let viewFrame = view.convert(view.bounds, to: nil)
        return Place(pagesTop: documentView.convert(documentView.bounds, to: nil).maxY, viewTop: viewFrame.maxY, viewBottom: viewFrame.minY,
                     viewWidth: viewFrame.width, windowSize: window.frame.size)
    }

    /// Moves the visible part of the pages so what moved `shift` points up the window (down when negative) comes back.
    private func scroll(_ clipView: NSClipView, byWindowPoints shift: CGFloat) {
        let clipHeightInWindow = clipView.convert(clipView.bounds, to: nil).height
        guard shift != 0, clipHeightInWindow > 0 else { return }
        // In the clip view's own units, which a zoom scales and whose axis may run down.
        let shiftInClipView = shift * clipView.bounds.height / clipHeightInWindow * (clipView.isFlipped ? -1 : 1)
        var visible = clipView.bounds
        visible.origin.y += shiftInClipView
        clipView.scroll(to: clipView.constrainBoundsRect(visible).origin)
        clipView.enclosingScrollView?.reflectScrolledClipView(clipView)
    }

    /// Called as the view's frame is about to change: notes where the pages stand now, so a scroll since the last
    /// layout is kept. Only the first call of a change notes it; the view has moved by the next.
    func viewWillMove() {
        guard let before = lastPlace, let now = currentPlace(), now.hasSameView(as: before) else { return }
        lastPlace = now
    }
}
#endif
