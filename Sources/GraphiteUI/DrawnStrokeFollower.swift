/**
 * File: DrawnStrokeFollower.swift
 * -------------------------------
 * Layer: UI
 * Description: Follows every sample of the touch that draws a stroke on a canvas that shows the stroke itself, and
 *              fails once every touch has lifted so UIKit resets the canvas's recognizers.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 18/11/2026
 */
#if canImport(UIKit)
import UIKit
import UIKit.UIGestureRecognizerSubclass

/// Follows the touch that draws a stroke on a canvas, every sample of it, for a canvas that
/// shows the stroke itself (the even highlighter's band). It never recognizes, and neither
/// prevents another recognizer nor is prevented by one, so PencilKit draws as if it were not
/// there.
final class DrawnStrokeFollower: UIGestureRecognizer {
    /// Whether a touch that begins is one to follow.
    var followsTouch: (UITouch) -> Bool = { _ in false }
    /// The stroke began at a point in the view's coordinates.
    var strokeDidBegin: (CGPoint) -> Void = { _ in }
    /// The stroke went on through points, and UIKit predicts it goes on through others, in
    /// the view's coordinates. The predicted points are a guess, shown only until the next move.
    var strokeDidMove: (_ points: [CGPoint], _ predictedPoints: [CGPoint]) -> Void = { _, _ in }
    /// The touch lifted, or was cancelled.
    var strokeDidEnd: (_ wasCancelled: Bool) -> Void = { _ in }

    private weak var followedTouch: UITouch?

    override init(target: Any?, action: Selector?) {
        super.init(target: target, action: action)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
    }

    override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool { false }
    override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool { false }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        guard followedTouch == nil, let touch = touches.first(where: followsTouch) else { return }
        followedTouch = touch
        strokeDidBegin(touch.location(in: view))
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let followedTouch, touches.contains(followedTouch) else { return }
        let points = (event.coalescedTouches(for: followedTouch) ?? [followedTouch]).map { coalescedTouch in coalescedTouch.location(in: view) }
        let predictedPoints = (event.predictedTouches(for: followedTouch) ?? []).map { predictedTouch in predictedTouch.location(in: view) }
        strokeDidMove(points, predictedPoints)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        if let followedTouch, touches.contains(followedTouch) { endStroke(wasCancelled: false) }
        failOnceEveryTouchHasLifted(event)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        if let followedTouch, touches.contains(followedTouch) { endStroke(wasCancelled: true) }
        failOnceEveryTouchHasLifted(event)
    }

    override func reset() {
        super.reset()
        // A reset without the touch ending, as when the view leaves the window mid-stroke.
        if followedTouch != nil { endStroke(wasCancelled: true) }
    }

    private func endStroke(wasCancelled: Bool) {
        followedTouch = nil
        // It stays possible while another touch is down: a failed recognizer hears no more touches
        // until every touch has lifted, and a hand resting on the page keeps one down while
        // the Pencil draws the next stroke. Once none is, it fails (`failOnceEveryTouchHasLifted`).
        strokeDidEnd(wasCancelled)
    }
}

extension UIGestureRecognizer {
    /// Fails a recognizer that never recognizes, still possible, once no touch of the event is down.
    ///
    /// UIKit resets the recognizers that took part in a sequence of touches only once every one of them has finished.
    /// `StrokeHoldRecognizer` and `DrawnStrokeFollower` stayed possible after their stroke, so they would hear the next
    /// stroke while a hand rests on the page; when a touch's end reached them while they followed none, they stayed
    /// possible after the last touch lifted, and UIKit never reset the canvas's recognizers, PencilKit's drawing
    /// recognizer among them. That one was left ended with its canvas still drawing the stroke of a touch long gone, and
    /// the page took no more ink until the tab was switched, which takes the canvas out of the window (the
    /// simulator, 2026-11-18). A failed recognizer is reset with the others and hears the next touch.
    func failOnceEveryTouchHasLifted(_ event: UIEvent) {
        // An event without touches says nothing of the touches down; UIKit's own always carry the one that ended.
        guard state == .possible, let touches = event.allTouches, !touches.isEmpty, Self.everyTouchHasLifted(touches) else { return }
        state = .failed
    }

    /// Whether none of these touches is still down.
    static func everyTouchHasLifted(_ touches: Set<UITouch>) -> Bool {
        touches.allSatisfy { touch in touch.phase == .ended || touch.phase == .cancelled }
    }
}
#endif
