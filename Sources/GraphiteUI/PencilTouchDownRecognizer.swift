/**
 * File: PencilTouchDownRecognizer.swift
 * -------------------------------------
 * Layer: UI
 * Description: Recognizes the moment a touch begins on a PDF page and hands it to the canvas under it.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 16/11/2026
 */

#if canImport(UIKit)
import UIKit
import UIKit.UIGestureRecognizerSubclass

/// Recognizes the moment a touch begins, without waiting for it to move or lift. It never
/// cancels or delays the touch for other views. It follows the touch to its end, telling a
/// canvas's drawing recognizer of it, so a touch that a canvas could not take draws all the same.
final class PencilTouchDownRecognizer: UIGestureRecognizer {
    /// The drawing recognizer of the canvas under a touch that begins, if it is to draw.
    var drawingRecognizerUnderTouch: ((UITouch) -> UIGestureRecognizer?)?
    private var followingDrawingRecognizer: UIGestureRecognizer?

    override init(target: Any?, action: Selector?) {
        super.init(target: target, action: action)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        guard state == .possible else { return }
        followingDrawingRecognizer = touches.first.flatMap { touch in drawingRecognizerUnderTouch?(touch) }
        followingDrawingRecognizer?.touchesBegan(touches, with: event)
        state = .began
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        followingDrawingRecognizer?.touchesMoved(touches, with: event)
        state = .changed
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        followingDrawingRecognizer?.touchesEnded(touches, with: event)
        followingDrawingRecognizer = nil
        state = .ended
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        followingDrawingRecognizer?.touchesCancelled(touches, with: event)
        followingDrawingRecognizer = nil
        state = .cancelled
    }
}
#endif
