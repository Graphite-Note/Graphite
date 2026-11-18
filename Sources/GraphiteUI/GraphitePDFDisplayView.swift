/**
 * File: GraphitePDFDisplayView.swift
 * ----------------------------------
 * Layer: UI
 * Description: The iPad's and iPhone's PDFView: its pages, zoom across resizes, and where touches go.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 16/11/2026
 */

#if canImport(UIKit)
import SwiftUI
import PDFKit
import os
import GraphiteCore
import GraphiteApple
import UIKit
import PencilKit

/// PDFView that routes touches on a page to its Pencil canvas while annotating.
final class GraphitePDFDisplayView: PDFView {
    weak var annotationCoordinator: PDFAnnotationCoordinator?
    /// The PDF's own history (`PDFSession.undoManager`), for ⌘Z while the PDF has focus.
    weak var documentUndoManager: UndoManager?
    override var undoManager: UndoManager? { documentUndoManager ?? super.undoManager }
    /// PDFKit makes its document view first responder, and a view without an accessory of
    /// its own shows its ancestor's: a PDF embedded in a note raised the note's formatting
    /// toolbar as the note opened, over the bottom of the screen with no text to format.
    private let emptyInputAccessoryView = UIView(frame: .zero)
    override var inputAccessoryView: UIView? { emptyInputAccessoryView }
    /// PDFKit scrolls to a page reliably only after the first layout.
    var pendingInitialPage: PDFPage?
    /// How far down `pendingInitialPage` the view's top edge goes then, as a fraction of the
    /// page's height; nil for its top.
    var pendingInitialFractionFromTop: CGFloat?

    /// Where the view is: the page at its top edge and how far down that page. Nil before
    /// the view has shown its first page, when it is not yet anywhere.
    var pagePlace: PDFPagePlace? {
        guard pendingInitialPage == nil, bounds.width > 0, bounds.height > 0, let document, let place = currentPlace() else { return nil }
        let pageIndex = document.index(for: place.page)
        guard pageIndex != NSNotFound else { return nil }
        return PDFPagePlace(pageIndex: pageIndex, fractionFromTop: Double(place.fractionFromTop))
    }

    /// The shown document's change count (`PDFSession.changeVersion`).
    var contentChangeCount: () -> Int = { 0 }
    /// Draws pictures and other annotations at the screen's resolution, as on the Mac (HUNT-320);
    /// tests stop it to measure what PDFKit draws by itself.
    lazy var annotationLayerResolution = PDFAnnotationLayerResolution(view: self) { [weak self] in self?.contentChangeCount() ?? 0 }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { annotationLayerResolution.stop() } else { annotationLayerResolution.start() }
        // The tool picker needs a first responder in a window.
        annotationCoordinator?.windowDidChange()
    }

    /// The place on screen when the width began to change: the page at the top of the
    /// view and how far down that page the top edge was. Autoscaling changes the zoom when
    /// the width changes (the sidebar, the split divider) but keeps the scroll offset,
    /// which then lands on another page; this place is shown again after the change.
    private var placeBeforeResize: (page: PDFPage, fractionFromTop: CGFloat)?
    /// Ends a resize once the width has stopped changing for a moment.
    private var resizeEndWorkItem: DispatchWorkItem?

    override var frame: CGRect {
        willSet { rememberPlaceBeforeResizing(to: newValue.size) }
    }

    override var bounds: CGRect {
        willSet { rememberPlaceBeforeResizing(to: newValue.size) }
    }

    /// The zoom when the width began to change: whether the pages fitted the width, and
    /// how far past that they were zoomed. PDFKit fits the pages to a new width only while
    /// it scales them itself, which a pinch, even one back to the fitting size, turns off:
    /// a page zoomed in a wide window then kept its size in a narrower one, running off one
    /// edge with empty space at the other (reported by the owner, 2026-10-13).
    private var zoomBeforeResize: PDFResizeZoom?
    /// The width the zoom was last chosen for. The zoom is chosen again only when the
    /// view's width really changes, never at a layout pass of the same width.
    private var widthOfLastZoom: CGFloat = 0
    /// How many times the view's width changed and the zoom was chosen again for it, for
    /// tests that check a resize settles at once and stays settled.
    private(set) var zoomChangesForWidth = 0

    /// The scroll view PDFKit scrolls and zooms the pages in.
    var pagesScrollView: UIScrollView? { documentView?.enclosingScrollView }

    /// Whether a finger is pinching, scrolling or flinging the pages, or they are bouncing
    /// back after it: the person moves the pages then, and a resize does not move them too.
    var isMovedByPerson: Bool {
        guard let scrollView = pagesScrollView else { return false }
        let pinchState = scrollView.pinchGestureRecognizer?.state
        return scrollView.isZooming || scrollView.isZoomBouncing || scrollView.isTracking || scrollView.isDragging
            || scrollView.isDecelerating || pinchState == .began || pinchState == .changed
    }

    private func rememberPlaceBeforeResizing(to newSize: CGSize) {
        // UIKit sets the frame while the view is still being created, before PDFKit is
        // ready to be asked anything; a view that is not on screen has no place to keep.
        guard window != nil, pendingInitialPage == nil, bounds.width > 0,
              abs(newSize.width - bounds.width) > 0.5, document != nil else { return }
        // A pinch or a scroll under way when the width changes wins: the pages stay where
        // the person puts them.
        guard !isMovedByPerson else {
            forgetResize()
            return
        }
        // The place and the zoom are read once, when a resize begins, and kept until it
        // ends: read again at every step of a divider drag, small errors would add up, and
        // a width that changes back and forth comes back to the same zoom and place.
        if placeBeforeResize == nil { placeBeforeResize = currentPlace() }
        if zoomBeforeResize == nil {
            zoomBeforeResize = PDFResizeZoom(isScaledByPDFKit: autoScales, scale: scaleFactor, fittingScale: scaleFactorForSizeToFit)
        }
        resizeEndWorkItem?.cancel()
        // PDFKit may finish rescaling after the last layout, so the zoom and the place are
        // shown once more when the width has settled, and then forgotten.
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if !self.isMovedByPerson {
                self.applyZoomAfterResize()
                if let placeBeforeResize = self.placeBeforeResize { self.show(placeBeforeResize) }
            }
            self.forgetResize()
        }
        resizeEndWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: workItem)
    }

    /// Ends a resize: the zoom and place it keeps are not shown again.
    private func forgetResize() {
        resizeEndWorkItem?.cancel()
        resizeEndWorkItem = nil
        zoomBeforeResize = nil
        placeBeforeResize = nil
    }

    private func currentPlace() -> (page: PDFPage, fractionFromTop: CGFloat)? {
        let topPoint = CGPoint(x: bounds.midX, y: bounds.minY + 1)
        guard let page = page(for: topPoint, nearest: true) else { return nil }
        // Measured on the page as shown, as `show` applies it: in the page's own space, a
        // page turned 180° gave its bottom for its top, and one turned 90° its width.
        let pageRect = convert(page.bounds(for: displayBox), from: page)
        guard pageRect.height > 0 else { return nil }
        return (page, min(max((topPoint.y - pageRect.minY) / pageRect.height, -0.2), 1))
    }

    /// Scrolls so the top edge is the same way down the same page as before.
    private func show(_ place: (page: PDFPage, fractionFromTop: CGFloat)) {
        guard let scrollView = documentView?.enclosingScrollView else { return }
        let pageRect = convert(place.page.bounds(for: displayBox), from: place.page)
        let offsetChange = pageRect.minY + place.fractionFromTop * pageRect.height - (bounds.minY + 1)
        let minimumOffset = -scrollView.adjustedContentInset.top
        let maximumOffset = max(minimumOffset, scrollView.contentSize.height - scrollView.bounds.height + scrollView.adjustedContentInset.bottom)
        let offset = min(max(scrollView.contentOffset.y + offsetChange, minimumOffset), maximumOffset)
        scrollView.setContentOffset(CGPoint(x: scrollView.contentOffset.x, y: offset), animated: false)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if let pendingInitialPage, bounds.width > 0, bounds.height > 0 {
            self.pendingInitialPage = nil
            placeBeforeResize = nil
            go(to: pendingInitialPage)
            if let fractionFromTop = pendingInitialFractionFromTop {
                pendingInitialFractionFromTop = nil
                show((page: pendingInitialPage, fractionFromTop: fractionFromTop))
                // PDFKit can lay its pages out once more after going to one; the place is
                // shown again then, as after a resize. The page is found again by its index.
                let pageIndex = document?.index(for: pendingInitialPage)
                DispatchQueue.main.async { [weak self] in
                    guard let self, let pageIndex, pageIndex != NSNotFound, let page = self.document?.page(at: pageIndex) else { return }
                    self.show((page: page, fractionFromTop: fractionFromTop))
                }
            }
        } else if let placeBeforeResize {
            if isMovedByPerson {
                forgetResize()
            } else {
                if abs(bounds.width - widthOfLastZoom) > 0.5 { applyZoomAfterResize() }
                show(placeBeforeResize)
            }
        }
        limitZoomingOut()
        if bounds.width > 0, abs(bounds.width - widthOfLastZoom) > 0.5 {
            pdfResizeLog.debug("PDF view width \(self.widthOfLastZoom, privacy: .public) -> \(self.bounds.width, privacy: .public), scale \(self.scaleFactor, privacy: .public)")
            widthOfLastZoom = bounds.width
        }
    }

    /// How far a pinch may shrink the pages, as a fraction of the zoom that fits the width: down to half of it, so
    /// a whole page of a portrait iPad can be seen, and never to the 20 percent stamp PDFKit allows (HUNT-266).
    static let smallestZoomAsFractionOfFitting: CGFloat = 0.5

    /// PDFKit resets its zoom limits as the view's size changes, so they are set again at each layout, to the same
    /// values (which changes nothing).
    private func limitZoomingOut() {
        let fittingScale = scaleFactorForSizeToFit
        guard bounds.width > 0, fittingScale.isFinite, fittingScale > 0 else { return }
        let smallestScale = fittingScale * Self.smallestZoomAsFractionOfFitting
        if abs(minScaleFactor - smallestScale) > 0.0001 { minScaleFactor = smallestScale }
    }

    /// Fits the pages to the new width when they fitted the old one, and keeps them as far
    /// past fitting as they were otherwise, so a page never runs off one edge with empty
    /// space at the other.
    /// It changes nothing when the zoom already is what the width calls for, so it can run
    /// at every step of a resize and once more after it without moving anything.
    private func applyZoomAfterResize() {
        guard let zoomBeforeResize, bounds.width > 0 else { return }
        let fittingScale = scaleFactorForSizeToFit
        guard fittingScale.isFinite, fittingScale > 0 else { return }
        let scaleBefore = scaleFactor
        switch zoomBeforeResize.scaleAfterResize(fittingScale: fittingScale) {
        case .fitsByPDFKit:
            if !autoScales { autoScales = true }
        case .scale(let scale):
            let clampedScale = min(max(scale, minScaleFactor), maxScaleFactor)
            if abs(scaleFactor - clampedScale) > 0.0001 { scaleFactor = clampedScale }
        }
        if abs(scaleFactor - scaleBefore) > 0.0001 {
            zoomChangesForWidth += 1
            pdfResizeLog.debug("PDF zoom for width \(self.bounds.width, privacy: .public): \(scaleBefore, privacy: .public) -> \(self.scaleFactor, privacy: .public)")
        }
        keepPagesInView()
    }

    /// Pages narrower than the view are centered; wider ones are scrolled no further than
    /// their edges.
    private func keepPagesInView() {
        guard let scrollView = documentView?.enclosingScrollView else { return }
        let insets = scrollView.adjustedContentInset
        let minimumOffset = -insets.left
        let maximumOffset = max(minimumOffset, scrollView.contentSize.width - scrollView.bounds.width + insets.right)
        let offset = min(max(scrollView.contentOffset.x, minimumOffset), maximumOffset)
        if abs(offset - scrollView.contentOffset.x) > 0.5 {
            scrollView.setContentOffset(CGPoint(x: offset, y: scrollView.contentOffset.y), animated: false)
        }
    }

    /// The system's menu for text selected with PDFKit's own selection (when not
    /// annotating) gets the links and quotes too.
    override func buildMenu(with builder: any UIMenuBuilder) {
        super.buildMenu(with: builder)
        guard builder.system == .context, let linkActions = annotationCoordinator?.linkActions, let document,
              let selection = currentSelection, let text = selection.string, !text.isEmpty,
              let page = selection.pages.first else { return }
        let pageIndex = document.index(for: page)
        guard pageIndex != NSNotFound else { return }
        builder.insertSibling(UIMenu(title: "", identifier: UIMenu.Identifier("com.graphite.study.pdf-links"), options: .displayInline,
                                     children: linkActions.menuElements(pageIndex: pageIndex, text: text)), afterMenu: .standardEdit)
    }

    /// UIKit cannot tell a Pencil from a finger during hit-testing (the event carries no
    /// touches yet), so while annotating every touch on a page goes to its canvas. The
    /// canvas draws only the input its drawing policy allows; the other touches still
    /// reach the scrolling, zooming, and text selection gestures of this view.
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        // A selection's floating toolbar is over everything, the frame it stands beside included.
        for case let toolbar as FloatingSelectionToolbar in subviews where toolbar.isShown {
            if let touchedView = toolbar.hitTest(toolbar.convert(point, from: self), with: event) { return touchedView }
        }
        // The text box being typed in, and the frame of a picture or box being arranged, are
        // over the page and its canvas: Scribble and the caret take the Pencil there.
        for case let editingView as PDFTextBoxEditingView in subviews {
            if let touchedView = editingView.hitTest(editingView.convert(point, from: self), with: event) { return touchedView }
        }
        for case let pictureSelection as SelectionFrameView in subviews {
            if let touchedView = pictureSelection.hitTest(pictureSelection.convert(point, from: self), with: event) { return touchedView }
        }
        if let canvas = annotationCoordinator?.canvas(at: point, in: self) {
            // The drawing gesture lives on a subview of the canvas.
            return canvas.hitTest(canvas.convert(point, from: self), with: event) ?? canvas
        }
        return super.hitTest(point, with: event)
    }
}

/// Each width a PDF's view takes and the zoom chosen for it, in the debug log, to tell a
/// resize from a width that changes back and forth.
private let pdfResizeLog = Logger(subsystem: "com.graphite.study", category: "PDFResize")
#endif
