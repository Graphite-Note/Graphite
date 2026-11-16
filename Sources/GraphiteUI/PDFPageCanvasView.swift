/**
 * File: PDFPageCanvasView.swift
 * -----------------------------
 * Layer: UI
 * Description: A PencilKit canvas over one PDF page, drawn as sharp as the page and recorded in the PDF's history.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 16/11/2026
 */

#if canImport(UIKit)
import SwiftUI
import PDFKit
import GraphiteCore
import GraphiteApple
import UIKit
import PencilKit

/// A PencilKit canvas over one PDF page. Its drawing is in the page's points; the canvas
/// zooms itself by its overlay's rendering scale (`PDFPageOverlayView`), so its ink is drawn
/// as sharp as the page around it. Its drawing changes are recorded in the PDF's own
/// history (`PDFSession.undoManager`), by page.
final class PDFPageCanvasView: HistoryCanvasView {
    weak var page: PDFPage?
    var inkTracker: PDFPageInkTracker
    /// The page's stored ink is decoded into the canvas the first time the page is shown,
    /// in Read mode too, since the canvas shows it there as well (`configure`).
    var hasRestoredStoredInk = false
    /// True while the stored drawing is decoded in the background. The page's ink annotations
    /// show the stored ink meanwhile, and the canvas takes touches over them: what is drawn
    /// then is recorded after the stored strokes once they arrive (`mergeStoredInk`), so a
    /// stroke begun as the page comes on screen is never lost (HUNT-307).
    var isRestoringStoredInk = false
    /// The decoded stored ink, held while a stroke is under way: setting the canvas's drawing
    /// under PencilKit's live stroke would lose that stroke (`applyHeldStoredInk`).
    var heldStoredInk: HeldStoredInk?
    /// Counts the restores begun, so the result of a decode that a newer read overtook is dropped.
    var storedInkRestoreCount = 0
    /// When PencilKit began using a tool on the canvas, until it ends.
    var toolUseBeginTime: TimeInterval?
    /// How many strokes the drawing had when PencilKit began using a tool: an inking tool's
    /// stroke arrives after the use ends, in PencilKit's own time.
    var strokeCountWhenToolUseBegan = 0
    /// How many edits the page had when the canvas was let go, while PDFKit may still show it
    /// again (`PDFAnnotationCoordinator.adoptCanvasShownAgain`); nil while it is the page's own.
    var editCountWhenLetGo: Int?
    /// What the page's ink annotations were last set to, and after how many edits of the page:
    /// setting them walks every annotation, and most configuring changes nothing of them.
    var inkAnnotationsState: (isHidden: Bool, pageEditCount: Int)?
    /// Whether the canvas may show ink the PDF does not have: set by what can change its drawing,
    /// cleared once that is recorded, so a save compares no strokes of a page nobody touched.
    var mayHoldUnrecordedInk = false
    /// The view PDFKit places over the page, which holds this canvas and the writing guides.
    private(set) weak var overlayView: PDFPageOverlayView?
    /// The owner of the PDF view's canvases, whose session the lasso's pictures belong to.
    weak var annotationCoordinator: PDFAnnotationCoordinator?

    init(page: PDFPage, inkTracker: PDFPageInkTracker) {
        self.page = page
        self.inkTracker = inkTracker
        super.init(frame: CGRect(origin: .zero, size: page.bounds(for: .cropBox).size))
    }

    required init?(coder: NSCoder) { nil }

    /// The longest a stroke is taken to last when only PencilKit's report of using a tool says
    /// it is under way, in case the report of its end never comes.
    private static let longestStrokeSeconds: TimeInterval = 10

    /// Whether a stroke is under way: PencilKit's recognizer stays `.possible` until a stroke
    /// has moved a little, so the touches it follows count, and touches another recognizer hands
    /// it (the Pencil's first touch while reading) are not among those, so its report counts too.
    var hasStrokeUnderWay: Bool {
        let recognizerState = drawingGestureRecognizer.state
        if recognizerState == .began || recognizerState == .changed || drawingGestureRecognizer.numberOfTouches > 0 { return true }
        guard let toolUseBeginTime else { return false }
        return PencilActivity.now - toolUseBeginTime < Self.longestStrokeSeconds
    }

    /// The size of the drawing's space: the page overlay's size, in the page's points,
    /// whatever the scale the canvas draws at and whatever part of the page it covers.
    var drawingSize: CGSize {
        if let overlaySize = overlayView?.bounds.size, overlaySize.width > 0, overlaySize.height > 0 { return overlaySize }
        guard zoomScale > 0 else { return bounds.size }
        return CGSize(width: bounds.width / zoomScale, height: bounds.height / zoomScale)
    }

    func showWritingGuides(_ guides: DrawingPaper) {
        overlayView?.writingGuides = guides
    }

    var writingGuides: DrawingPaper { overlayView?.writingGuides ?? .plain }

    /// Called by the overlay that holds the canvas (`PDFPageOverlayView`).
    func placeIn(_ overlayView: PDFPageOverlayView) {
        self.overlayView = overlayView
    }
}
#endif
