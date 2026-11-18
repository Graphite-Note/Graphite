/**
 * File: SelectionFrameTwoFingerGesture.swift
 * ------------------------------------------
 * Layer: UI
 * Description: Two fingers on a selected picture's frame turn it (twist), resize it (pinch) and move it with them,
 *              reported to the frame's owner once, when the fingers lift, as one change.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 17/11/2026
 */

#if canImport(UIKit)
import UIKit
import GraphiteCore

/// A pinch and a twist on a `SelectionFrameView`, recognized together. The frame follows the
/// fingers as `PictureTwoFingerTransform` says; its owner is told the frame and the angle
/// when the gesture ends, and nothing when it is cancelled, after which the frame is back.
/// The frame's own handles stay as they are; a one-finger drag that has begun is cancelled.
@MainActor
final class SelectionFrameTwoFingerGesture: NSObject, UIGestureRecognizerDelegate {
    private weak var frameView: SelectionFrameView?
    private(set) lazy var pinchRecognizer = UIPinchGestureRecognizer(target: self, action: #selector(handleGesture(_:)))
    private(set) lazy var twistRecognizer = UIRotationGestureRecognizer(target: self, action: #selector(handleGesture(_:)))
    /// Called when the fingers begin to change the frame.
    var changeDidBegin: (() -> Void)?
    /// Called when the fingers lift, with the frame before it is turned and the angle.
    var changeDidEnd: ((CGRect, CGFloat) -> Void)?
    /// The largest the frame's longer side can become, in the superview's points.
    var maximumSideLength: CGFloat = .greatestFiniteMagnitude
    private var start: (transform: PictureTwoFingerTransform, fingersMiddle: CGPoint)?
    private var isHeldAtQuarterTurn = false
    private lazy var snapFeedback = UISelectionFeedbackGenerator()

    /// Whether two fingers are changing the frame now.
    var isChanging: Bool { start != nil }

    init(frameView: SelectionFrameView) {
        self.frameView = frameView
        super.init()
        for recognizer in [pinchRecognizer, twistRecognizer] as [UIGestureRecognizer] {
            // Fingers and a trackpad's pinch and turn, not the Pencil, which draws.
            recognizer.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue), NSNumber(value: UITouch.TouchType.indirectPointer.rawValue)]
            recognizer.delegate = self
            frameView.addGestureRecognizer(recognizer)
        }
    }

    func stop() {
        frameView?.removeGestureRecognizer(pinchRecognizer)
        frameView?.removeGestureRecognizer(twistRecognizer)
    }

    // MARK: The gesture

    /// The fingers came down and began to move, with the point between them in the frame's superview.
    func begin(fingersMiddle: CGPoint) {
        guard let frameView, start == nil else { return }
        let rotation = Double(frameView.rotation)
        start = (PictureTwoFingerTransform(frame: frameView.unrotatedFrame, rotationRadians: rotation), fingersMiddle)
        // A one-finger move, resize or turn that began first gives way to the two fingers,
        // which go on from where it had got to.
        for recognizer in frameView.dragRecognizers where recognizer.state == .began || recognizer.state == .changed {
            recognizer.isEnabled = false
            recognizer.isEnabled = true
        }
        isHeldAtQuarterTurn = PictureRotation.isNearQuarterTurn(rotation)
        snapFeedback.prepare()
        changeDidBegin?()
        frameView.showsDragPreview(true)
    }

    /// The fingers moved: the point between them, how much further apart they are, and how
    /// far the line between them has turned since they came down.
    func change(fingersMiddle: CGPoint, scale: CGFloat, turn: CGFloat) {
        guard let frameView, let start else { return }
        let freeAngle = start.transform.rotationRadians + Double(turn)
        let isAtQuarterTurn = PictureRotation.isNearQuarterTurn(freeAngle)
        if isAtQuarterTurn, !isHeldAtQuarterTurn { snapFeedback.selectionChanged() }
        isHeldAtQuarterTurn = isAtQuarterTurn
        let transform = PictureTwoFingerTransform.transformed(start.transform, fingersMiddleAtStart: start.fingersMiddle, fingersMiddle: fingersMiddle,
                                                              scale: scale, turn: Double(turn), minimumSideLength: frameView.minimumSideLength,
                                                              maximumSideLength: maximumSideLength, centerLimits: frameView.centerLimits)
        // The angle first: the frame is placed turned about its own middle.
        frameView.rotation = CGFloat(transform.rotationRadians)
        frameView.unrotatedFrame = transform.frame
        frameView.showsDragPreview(true)
    }

    /// The fingers lifted: the owner is told the frame where they left it.
    func end() {
        guard let frameView, start != nil else { return }
        start = nil
        frameView.showsDragPreview(false)
        changeDidEnd?(frameView.unrotatedFrame, frameView.rotation)
    }

    /// The gesture was cancelled: the frame goes back where it was.
    func cancel() {
        guard let frameView, let start else { return }
        self.start = nil
        frameView.showsDragPreview(false)
        frameView.rotation = CGFloat(start.transform.rotationRadians)
        frameView.unrotatedFrame = start.transform.frame
    }

    @objc private func handleGesture(_ recognizer: UIGestureRecognizer) {
        guard let superview = frameView?.superview else { return }
        let fingersMiddle = recognizer.location(in: superview)
        switch recognizer.state {
        case .began, .changed:
            if start == nil { begin(fingersMiddle: fingersMiddle) }
            change(fingersMiddle: fingersMiddle, scale: Self.isActive(pinchRecognizer) ? pinchRecognizer.scale : 1,
                   turn: Self.isActive(twistRecognizer) ? twistRecognizer.rotation : 0)
        case .ended:
            // The other recognizer may still be following the fingers; the change ends with both.
            let other: UIGestureRecognizer = recognizer === pinchRecognizer ? twistRecognizer : pinchRecognizer
            if !Self.isActive(other) { end() }
        case .cancelled:
            cancel()
        default: break
        }
    }

    private static func isActive(_ recognizer: UIGestureRecognizer) -> Bool {
        recognizer.state == .began || recognizer.state == .changed
    }

    // MARK: UIGestureRecognizerDelegate

    /// Not while a picture is cropped, whose crop frame neither turns nor moves.
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        frameView?.cropLimits == nil
    }

    /// The pinch and the twist are one gesture.
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        (gestureRecognizer === pinchRecognizer && otherGestureRecognizer === twistRecognizer)
            || (gestureRecognizer === twistRecognizer && otherGestureRecognizer === pinchRecognizer)
    }
}
#endif
