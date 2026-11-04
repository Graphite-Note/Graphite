/**
 * File: PDFAnnotationCoordinatorInkRecords.swift
 * ----------------------------------------------
 * Layer: UI
 * Description: How a PDF view's canvases read a page's stored ink and write it back: what grows with the
 *              page's strokes runs away from the main actor, a stroke drawn while it does is kept, and a save
 *              compares only what was touched.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 04/11/2026
 */
#if canImport(UIKit)
import PDFKit
import PencilKit
import GraphiteApple

/// A page's stored ink as its decode gave it, and the count of the page's edits when it was read.
struct HeldStoredInk {
    let restored: (tracker: PDFPageInkTracker, drawing: PKDrawing)?
    let editCountWhenRead: Int
}

/// How a PDF view's canvases read a page's stored ink and write it back.
extension PDFAnnotationCoordinator {
    /// Reading a page's annotations stays here, on the main actor that owns the document, and
    /// is done once. All the rest grows with the page's strokes and runs in the background: the
    /// record's base64 and names, the drawing, and the fingerprint of each stroke (HUNT-015). The
    /// count of the page's edits says whether undo or redo changed its ink meanwhile.
    ///
    /// The canvas takes touches and has its delegate from the start: a stroke drawn while the
    /// ink is decoded stays on the canvas, unrecorded, and is recorded after the stored strokes
    /// once they arrive (HUNT-307). A page shown in the middle of a zoom or a quick scroll took no
    /// touches for that moment, so the first stroke on it went to the PDF view, which scrolled.
    func restoreStoredInkIfNeeded(on canvas: PDFPageCanvasView, knownStoredInk: PDFStoredInk? = nil) {
        guard !canvas.hasRestoredStoredInk, let page = canvas.page else { return }
        canvas.hasRestoredStoredInk = true
        canvas.delegate = self
        let storedInk = knownStoredInk ?? PDFInkGroups.storedInk(on: page)
        guard storedInk.mayHaveEditableGroup else {
            // A read begun again after an edit can find no ink left; strokes drawn meanwhile are recorded now.
            if !canvas.drawing.strokes.isEmpty { mergeStoredInk(nil, into: canvas) }
            return
        }
        canvas.isRestoringStoredInk = true
        canvas.storedInkRestoreCount += 1
        let restoreNumber = canvas.storedInkRestoreCount
        let editCountWhenRead = session.editCount(of: page)
        Task { [weak self, weak canvas] in
            // Made there and handed over whole, so nothing of it is shared; a mask's CGPath is not Sendable.
            let restored: (tracker: PDFPageInkTracker, drawing: PKDrawing)? = await withCheckedContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    continuation.resume(returning: storedInk.editableGroup().flatMap { editableGroup in PDFPageInkTracker.restoring(editableGroup) })
                }
            }
            guard let self, let canvas, canvas.isRestoringStoredInk, canvas.storedInkRestoreCount == restoreNumber, canvas.page === page,
                  self.canvasesByPage[ObjectIdentifier(page)] === canvas else { return }
            canvas.heldStoredInk = HeldStoredInk(restored: restored, editCountWhenRead: editCountWhenRead)
            self.applyHeldStoredInk(on: canvas)
        }
    }

    /// Shows the decoded stored ink unless a stroke is under way, which holds it back until the
    /// stroke has arrived: setting the canvas's drawing under PencilKit's live stroke would lose
    /// the stroke. The stroke's arrival, or the end of a tool's use that brings no stroke, looks
    /// again (`applyHeldStoredInkOnTheNextTurn`).
    func applyHeldStoredInk(on canvas: PDFPageCanvasView) {
        guard let heldStoredInk = canvas.heldStoredInk, canvas.isRestoringStoredInk, !canvas.hasStrokeUnderWay, let page = canvas.page,
              canvasesByPage[ObjectIdentifier(page)] === canvas else { return }
        canvas.heldStoredInk = nil
        guard session.editCount(of: page) == heldStoredInk.editCountWhenRead else {
            // Undo or redo changed the page's ink while it was decoded: it is read again.
            canvas.isRestoringStoredInk = false
            canvas.hasRestoredStoredInk = false
            restoreStoredInkIfNeeded(on: canvas)
            configure(canvas)
            return
        }
        mergeStoredInk(heldStoredInk.restored, into: canvas)
        configure(canvas)
    }

    /// A stroke arrived or a tool's use ended: held stored ink is looked at once PencilKit has
    /// ended the use, which it reports in the same turn or the next.
    func applyHeldStoredInkOnTheNextTurn(on canvas: PDFPageCanvasView) {
        guard canvas.heldStoredInk != nil else { return }
        Task { @MainActor [weak self, weak canvas] in
            guard let self, let canvas else { return }
            self.applyHeldStoredInk(on: canvas)
        }
    }

    /// Shows the page's stored ink, then records what was drawn while it was decoded as the
    /// person's edit, after it. Loading the stored ink is not an edit, so undo takes back the
    /// strokes drawn meanwhile and nothing of the stored ink, and the tracker, read with the
    /// stored strokes' names, adds only the new strokes to the page.
    private func mergeStoredInk(_ restored: (tracker: PDFPageInkTracker, drawing: PKDrawing)?, into canvas: PDFPageCanvasView) {
        // Nothing is recorded while the ink is decoded, so all the canvas shows was drawn meanwhile.
        let strokesDrawnMeanwhile = canvas.drawing.strokes
        if let restored {
            canvas.inkTracker = restored.tracker
            // Set while still restoring, so the delegate does not record the stored drawing as an edit.
            canvas.drawing = restored.drawing
            canvas.recordedDrawing = restored.drawing
        }
        canvas.isRestoringStoredInk = false
        guard !strokesDrawnMeanwhile.isEmpty else {
            canvas.mayHoldUnrecordedInk = false
            return
        }
        if restored != nil {
            canvas.showWithoutRecording(PKDrawing(strokes: canvas.recordedDrawing.strokes + strokesDrawnMeanwhile))
        }
        canvasViewDrawingDidChange(canvas)
    }

    /// A save, or the canvas going away, while the stored ink is still decoded: strokes drawn
    /// meanwhile are recorded with the stored ink, read here at once, so none is lost and the
    /// record keeps every stored stroke. The decode under way is then dropped. A stroke under
    /// way holds this back for a save, as it holds back the decode.
    private func finishRestoringAtOnce(_ canvas: PDFPageCanvasView, evenDuringAStroke: Bool) {
        guard canvas.isRestoringStoredInk, !canvas.drawing.strokes.isEmpty, evenDuringAStroke || !canvas.hasStrokeUnderWay,
              let page = canvas.page else { return }
        canvas.heldStoredInk = nil
        canvas.storedInkRestoreCount += 1
        let restored = PDFInkGroups.editableGroup(on: page).flatMap { editableGroup in PDFPageInkTracker.restoring(editableGroup) }
        mergeStoredInk(restored, into: canvas)
        if canvasesByPage[ObjectIdentifier(page)] === canvas { configure(canvas) }
    }

    /// Writes the re-editing records that drawing deferred, for every canvas.
    func writeDeferredInkRecords() {
        for canvas in canvasesByPage.values {
            recordInkIfTheCanvasChanged(canvas)
            writeDeferredInkRecord(of: canvas)
        }
    }

    /// The same for a save, with each record archived away from the main actor: the archive
    /// grows with the page's strokes, and a stroke begun meanwhile does not wait (HUNT-017). A
    /// stroke that comes before an archive is done leaves its record deferred.
    func writeDeferredInkRecordsInBackground() async {
        for canvas in Array(canvasesByPage.values) {
            recordInkIfTheCanvasChanged(canvas)
            guard let archive = canvas.inkTracker.deferredRecordArchive(for: canvas.recordedDrawing) else { continue }
            let record = await Task.detached(priority: .userInitiated) { archive.archived() }.value
            guard !isDetached, canvasesByPage.values.contains(where: { keptCanvas in keptCanvas === canvas }), let page = canvas.page else { continue }
            let pageIndex = session.document.index(for: page)
            guard pageIndex != NSNotFound,
                  let update = canvas.inkTracker.deferredEditableRecordUpdate(archived: record, from: archive, pageIndex: pageIndex) else { continue }
            apply(update)
        }
    }

    /// Records ink a canvas shows that the PDF does not have yet, as when a change of the
    /// canvas never reached its delegate. A stroke still being drawn is not part of it.
    /// `evenDuringAStroke` is for a canvas going away, whose live stroke is lost anyway.
    func recordUnrecordedInk(of canvas: PDFPageCanvasView, evenDuringAStroke: Bool = false) {
        finishRestoringAtOnce(canvas, evenDuringAStroke: evenDuringAStroke)
        guard canvas.delegate === self, canvas.hasRestoredStoredInk, !canvas.isRestoringStoredInk else { return }
        everyStrokeComparisonCount += 1
        guard PencilDrawingChange(from: canvas.recordedDrawing, to: canvas.drawing) != nil else {
            canvas.mayHoldUnrecordedInk = false
            return
        }
        canvasViewDrawingDidChange(canvas)
    }

    /// The same for what happens at every save: the comparison fingerprints every stroke of
    /// both drawings on the main actor, so it runs only for a canvas something touched since it
    /// was last recorded (HUNT-017). A canvas going away, or rebuilt, always compares.
    private func recordInkIfTheCanvasChanged(_ canvas: PDFPageCanvasView) {
        guard canvas.mayHoldUnrecordedInk || canvas.drawing.strokes.count != canvas.recordedDrawing.strokes.count else { return }
        recordUnrecordedInk(of: canvas)
    }

    func writeDeferredInkRecord(of canvas: PDFPageCanvasView) {
        guard canvas.inkTracker.hasDeferredEditableRecord, let page = canvas.page else { return }
        let pageIndex = session.document.index(for: page)
        // A deleted page's ink went with it.
        guard pageIndex != NSNotFound,
              let update = canvas.inkTracker.deferredEditableRecordUpdate(for: canvas.recordedDrawing, pageIndex: pageIndex) else { return }
        apply(update)
    }

    private func apply(_ update: PDFInkUpdate) {
        do {
            try session.apply(.updateInk(update))
        } catch {
            session.errorMessage = error.localizedDescription
        }
    }
}
#endif
