/**
 * File: TextHighlighterTool.swift
 * -------------------------------
 * Layer: UI
 * Description: The text highlighter on one canvas of a PDF page: a drag of Apple Pencil, or of a finger where fingers
 *              draw, tells the canvas's owner where it began, moved and lifted, in the window, and a tap where it
 *              was. It draws no ink, and the canvas's `marksText` turns it on with PencilKit's drawing off.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 17/11/2026
 */

#if canImport(UIKit)
import UIKit

/// A drag of the text highlighter, in the window's points: the owner selects the PDF text from where it began to where
/// it is, and marks the selection when it lifts (`PDFTextHighlighterInteraction`).
enum TextHighlighterDrag: Equatable {
    case began(startPoint: CGPoint, currentPoint: CGPoint)
    case moved(to: CGPoint)
    case lifted
    case cancelled
    /// A tap without a drag, as on a mark to remove or recolour it.
    case tapped(at: CGPoint)
}

/// The text highlighter on one canvas of a PDF page. While it is chosen the canvas draws nothing
/// (`HistoryCanvasView.marksText` turns PencilKit's drawing off), so no ink is ever drawn; its drag recognizer takes
/// Apple Pencil, and fingers only where fingers draw (`PKCanvasView.drawingPolicy` `.anyInput`). Elsewhere a finger
/// scrolls the page as with any tool, and its long press selects text, which the tool marks when the finger lifts
/// (`PDFAnnotationCoordinator.handleTextSelection`). A hand resting while the Pencil writes takes no part
/// (`CanvasToolTouches`). A Pencil tap selects nothing: the drag begins only once the touch moves.
@MainActor
final class TextHighlighterToolController: NSObject, UIGestureRecognizerDelegate {
    private unowned let canvas: HistoryCanvasView
    private lazy var dragRecognizer: UIPanGestureRecognizer = {
        let recognizer = UIPanGestureRecognizer(target: self, action: #selector(handleDrag(_:)))
        recognizer.maximumNumberOfTouches = 1
        recognizer.delegate = self
        return recognizer
    }()

    private lazy var tapRecognizer: UITapGestureRecognizer = {
        let recognizer = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        recognizer.delegate = self
        return recognizer
    }()

    init(canvas: HistoryCanvasView) {
        self.canvas = canvas
    }

    var isActive = false {
        didSet {
            guard isActive != oldValue else { return }
            if isActive, dragRecognizer.view == nil {
                canvas.addGestureRecognizer(dragRecognizer)
                canvas.addGestureRecognizer(tapRecognizer)
            }
            dragRecognizer.isEnabled = isActive
            tapRecognizer.isEnabled = isActive
        }
    }

    /// A tap of the Pencil, or of a finger where fingers draw: on a mark, its menu offers Remove and its colours.
    @objc private func handleTap(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .ended, let window = canvas.window else { return }
        canvas.textHighlighterDragged?(.tapped(at: recognizer.location(in: window)))
    }

    /// Apple Pencil always; a finger only where fingers draw, and never a hand resting while the Pencil writes.
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        Self.takesTouch(ofType: touch.type, fingersDraw: canvas.drawingPolicy == .anyInput) && !CanvasToolTouches.isHandResting(touch)
    }

    /// Whether the tool takes a touch of this type: the Pencil, or a finger where fingers draw (a pointer selects as
    /// PDFKit lets it, and fingers otherwise scroll).
    nonisolated static func takesTouch(ofType touchType: UITouch.TouchType, fingersDraw: Bool) -> Bool {
        switch touchType {
        case .pencil: true
        case .direct: fingersDraw
        case .indirect, .indirectPointer: false
        @unknown default: false
        }
    }

    @objc private func handleDrag(_ recognizer: UIPanGestureRecognizer) {
        guard let window = canvas.window else { return }
        let currentPoint = recognizer.location(in: window)
        switch recognizer.state {
        case .began:
            // The pan begins once the touch has moved; it selects from where the touch landed.
            let translation = recognizer.translation(in: window)
            let startPoint = CGPoint(x: currentPoint.x - translation.x, y: currentPoint.y - translation.y)
            canvas.textHighlighterDragged?(.began(startPoint: startPoint, currentPoint: currentPoint))
        case .changed:
            canvas.textHighlighterDragged?(.moved(to: currentPoint))
        case .ended:
            canvas.textHighlighterDragged?(.moved(to: currentPoint))
            canvas.textHighlighterDragged?(.lifted)
        case .cancelled, .failed:
            canvas.textHighlighterDragged?(.cancelled)
        case .possible:
            break
        @unknown default:
            break
        }
    }
}

extension HistoryCanvasView {
    /// Whether the canvas marks the text it is dragged over instead of drawing: PencilKit draws no ink meanwhile.
    var marksText: Bool {
        get { textHighlighter?.isActive ?? false }
        set {
            guard newValue != marksText else { return }
            if newValue, textHighlighter == nil { textHighlighter = TextHighlighterToolController(canvas: self) }
            textHighlighter?.isActive = newValue
            applyDrawingEnabled()
        }
    }
}
#endif
