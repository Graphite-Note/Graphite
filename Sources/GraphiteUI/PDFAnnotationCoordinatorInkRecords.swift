/**
 * File: PDFAnnotationCoordinatorInkRecords.swift
 * ----------------------------------------------
 * Layer: UI
 * Description: How a PDF view's canvases read a page's stored ink and write it back: what grows with the
 *              page's strokes runs away from the main actor, and a save compares only what was touched.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 02/11/2026
 */
#if canImport(UIKit)
import PDFKit
import PencilKit
import GraphiteApple

/// How a PDF view's canvases read a page's stored ink and write it back.
extension PDFAnnotationCoordinator {
    /// Reading a page's annotations stays here, on the main actor that owns the document, and
    /// is done once. All the rest grows with the page's strokes and runs in the background: the
    /// record's base64 and names, the drawing, and the fingerprint of each stroke (HUNT-015). The
    /// count of the page's edits says whether undo or redo changed its ink meanwhile.
    func restoreStoredInkIfNeeded(on canvas: PDFPageCanvasView, knownStoredInk: PDFStoredInk? = nil) {
        guard !canvas.hasRestoredStoredInk, let page = canvas.page else { return }
        canvas.hasRestoredStoredInk = true
        let storedInk = knownStoredInk ?? PDFInkGroups.storedInk(on: page)
        guard storedInk.mayHaveEditableGroup else {
            canvas.delegate = self
            return
        }
        canvas.isRestoringStoredInk = true
        let editCountWhenRead = session.editCount(of: page)
        Task { [weak self, weak canvas] in
            // Made there and handed over whole, so nothing of it is shared; a mask's CGPath is not Sendable.
            let restored: (tracker: PDFPageInkTracker, drawing: PKDrawing)? = await withCheckedContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    continuation.resume(returning: storedInk.editableGroup().flatMap { editableGroup in PDFPageInkTracker.restoring(editableGroup) })
                }
            }
            guard let self, let canvas, canvas.page === page, self.canvasesByPage[ObjectIdentifier(page)] === canvas else { return }
            canvas.isRestoringStoredInk = false
            guard self.session.editCount(of: page) == editCountWhenRead else {
                canvas.hasRestoredStoredInk = false
                self.restoreStoredInkIfNeeded(on: canvas)
                self.configure(canvas)
                return
            }
            if let restored {
                canvas.inkTracker = restored.tracker
                // Set before the delegate, so loading the stored drawing is not recorded as an edit.
                canvas.drawing = restored.drawing
                canvas.recordedDrawing = restored.drawing
            }
            canvas.delegate = self
            self.configure(canvas)
        }
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
    func recordUnrecordedInk(of canvas: PDFPageCanvasView) {
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
