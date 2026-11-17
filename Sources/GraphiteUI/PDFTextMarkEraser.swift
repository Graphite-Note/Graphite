/**
 * File: PDFTextMarkEraser.swift
 * -----------------------------
 * Layer: UI
 * Description: The eraser on a PDF page on the iPad also erases highlights, underlines and strikethroughs: each mark
 *              it passes over disappears at once and is removed when it lifts, all of a stroke's marks as one step.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 17/11/2026
 */

#if canImport(UIKit)
import UIKit
import UIKit.UIGestureRecognizerSubclass
import PDFKit
import PencilKit
import GraphiteApple

/// Erases text marks with the eraser, PencilKit's or Graphite's pixel eraser, chosen on the bar or in the palette: the
/// owner found no way to erase a highlight on 2026-11-17. A mark the eraser touches is hidden at once; when it lifts, the
/// marks touched are removed as one step of the PDF's history (`PDFSession.removeMarkups`), so one Undo puts them all
/// back; a stroke cancelled shows them again. The eraser's own strokes are PencilKit's or `PixelEraserController`'s,
/// untouched: this only follows the same touch (`TextMarkEraserTouchRecognizer`).
@MainActor
final class PDFTextMarkEraser {
    private let session: PDFSession
    private weak var pdfView: PDFView?
    /// The marks the stroke under way passed over, hidden until it lifts.
    private var erasedMarks: [(annotation: PDFAnnotation, page: PDFPage)] = []
    private var lastWindowPoint: CGPoint?

    /// How far from the eraser's point a mark is touched, in the screen's points.
    static let reachInScreenPoints: CGFloat = 6
    /// The distance between the points tested along a stroke, in the screen's points, so a quick stroke misses no line.
    static let sampleSpacingInScreenPoints: CGFloat = 4

    init(session: PDFSession, pdfView: PDFView) {
        self.session = session
        self.pdfView = pdfView
    }

    /// Follows the eraser's touches on a page's canvas.
    func follow(_ canvas: PDFPageCanvasView) {
        let recognizer = TextMarkEraserTouchRecognizer { [weak canvas] touch in
            guard let canvas else { return false }
            return canvas.isUserInteractionEnabled && canvas.chosenTool is PKEraserTool
                && TextHighlighterToolController.takesTouch(ofType: touch.type, fingersDraw: canvas.drawingPolicy == .anyInput)
                && !CanvasToolTouches.isHandResting(touch)
        } report: { [weak self] event in
            self?.handle(event)
        }
        canvas.addGestureRecognizer(recognizer)
    }

    func handle(_ event: TextMarkEraserTouchRecognizer.Event) {
        switch event {
        case .touched(let windowPoint):
            eraseAlong(to: windowPoint)
        case .lifted:
            lastWindowPoint = nil
            removeErasedMarks()
        case .cancelled:
            lastWindowPoint = nil
            for (annotation, _) in erasedMarks { annotation.shouldDisplay = true }
            erasedMarks = []
        }
    }

    /// Erases at the points from the last one to `windowPoint`, a few screen points apart.
    private func eraseAlong(to windowPoint: CGPoint) {
        let start = lastWindowPoint ?? windowPoint
        lastWindowPoint = windowPoint
        let distance = hypot(windowPoint.x - start.x, windowPoint.y - start.y)
        let stepCount = max(Int((distance / Self.sampleSpacingInScreenPoints).rounded(.up)), 1)
        for step in 1...stepCount {
            let fraction = CGFloat(step) / CGFloat(stepCount)
            erase(at: CGPoint(x: start.x + (windowPoint.x - start.x) * fraction, y: start.y + (windowPoint.y - start.y) * fraction))
        }
    }

    private func erase(at windowPoint: CGPoint) {
        guard let pdfView else { return }
        let viewPoint = pdfView.convert(windowPoint, from: nil)
        guard let page = pdfView.page(for: viewPoint, nearest: false) else { return }
        let pagePoint = pdfView.convert(viewPoint, to: page)
        let reach = Self.reachInScreenPoints / max(pdfView.scaleFactor, 0.01)
        for annotation in page.annotations where annotation.shouldDisplay && PDFMarkupKind(annotationType: annotation.type) != nil {
            let isTouched = PDFMarkup.lineRectangles(of: annotation).contains { lineRectangle in
                lineRectangle.insetBy(dx: -reach, dy: -reach).contains(pagePoint)
            }
            guard isTouched else { continue }
            annotation.shouldDisplay = false
            erasedMarks.append((annotation, page))
        }
    }

    /// The marks touched are removed as one step, shown again first so the step keeps them as they were.
    private func removeErasedMarks() {
        let marks = erasedMarks
        erasedMarks = []
        guard !marks.isEmpty else { return }
        for (annotation, _) in marks { annotation.shouldDisplay = true }
        do { try session.removeMarkups(marks) } catch { session.errorMessage.report(error) }
    }
}

/// Follows one touch on a page's canvas for `PDFTextMarkEraser`, never taking part: it never recognizes, never cancels,
/// delays or prevents a touch, and nothing prevents it, so the eraser erases ink as if it were not there. `follows`
/// decides at each touch's start whether it is the eraser's.
final class TextMarkEraserTouchRecognizer: UIGestureRecognizer {
    enum Event {
        /// The touch is at this point, in the window.
        case touched(CGPoint)
        case lifted
        case cancelled
    }

    private let follows: (UITouch) -> Bool
    private let report: (Event) -> Void
    private weak var followedTouch: UITouch?

    init(follows: @escaping (UITouch) -> Bool, report: @escaping (Event) -> Void) {
        self.follows = follows
        self.report = report
        super.init(target: nil, action: nil)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
    }

    override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool { false }
    override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool { false }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        for touch in touches {
            if followedTouch == nil, follows(touch) {
                followedTouch = touch
                report(.touched(touch.location(in: nil)))
            } else {
                ignore(touch, for: event)
            }
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let followedTouch, touches.contains(followedTouch) else { return }
        for sample in event.coalescedTouches(for: followedTouch) ?? [followedTouch] { report(.touched(sample.location(in: nil))) }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let followedTouch, touches.contains(followedTouch) else { return }
        report(.touched(followedTouch.location(in: nil)))
        report(.lifted)
        self.followedTouch = nil
        state = .failed
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let followedTouch, touches.contains(followedTouch) else { return }
        report(.cancelled)
        self.followedTouch = nil
        state = .failed
    }

    override func reset() {
        super.reset()
        // A touch still followed when UIKit resets the recognizer ended unreported: its marks show again.
        if followedTouch != nil { report(.cancelled) }
        followedTouch = nil
    }
}
#endif
