/**
 * File: CanvasLeftDrawingWatch.swift
 * ----------------------------------
 * Layer: UI
 * Description: Finds a page canvas whose drawing recognizer stays finished with no touch down, which takes no new
 *              stroke, and resets its recognizers.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 18/11/2026
 */
#if os(iOS)
import UIKit
import PencilKit

/// Watches the page canvases' drawing recognizers for one left finished (HUNT-369).
///
/// UIKit resets a finished recognizer once the touches it took part in have all lifted. On a dedicated simulator on
/// 2026-11-18, PencilKit's drawing recognizer of a page was left ended and never reset, its canvas still drawing the
/// stroke of a touch long gone, and the page took no new stroke until the tab was switched. A canvas whose drawing
/// recognizer stays finished, no touch down anywhere in the window and the Pencil off the screen, for `seconds` has
/// every recognizer of its own switched off and on, which resets them, PencilKit's drawing recognizer ending its stroke.
@MainActor
struct CanvasLeftDrawingWatch {
    /// When each canvas's drawing recognizer was first seen finished with no touch down, by the uptime clock.
    private var leftFinishedSince: [ObjectIdentifier: TimeInterval] = [:]

    /// Resets the canvas's recognizers when its drawing recognizer has been left finished for `seconds`. True when it did.
    mutating func resetIfLeftDrawing(_ canvas: PKCanvasView, forLongerThan seconds: TimeInterval, touchIsDown: Bool, now: TimeInterval) -> Bool {
        let identifier = ObjectIdentifier(canvas)
        let drawing = canvas.drawingGestureRecognizer
        let isLeftFinished = drawing.isEnabled && (drawing.state == .ended || drawing.state == .cancelled || drawing.state == .failed)
            && drawing.numberOfTouches == 0 && !touchIsDown && !PencilActivity.isPencilTouching(at: now)
        guard isLeftFinished else {
            leftFinishedSince[identifier] = nil
            return false
        }
        let since = leftFinishedSince[identifier] ?? now
        leftFinishedSince[identifier] = since
        guard now - since >= seconds else { return false }
        leftFinishedSince[identifier] = nil
        for recognizer in PDFTouchEvidence.recognizers(in: canvas) where recognizer.isEnabled {
            recognizer.isEnabled = false
            recognizer.isEnabled = true
        }
        return true
    }

    /// Forgets canvases no longer shown.
    mutating func keepOnly(_ canvases: [PKCanvasView]) {
        let kept = Set(canvases.map(ObjectIdentifier.init))
        leftFinishedSince = leftFinishedSince.filter { entry in kept.contains(entry.key) }
    }
}
#endif
