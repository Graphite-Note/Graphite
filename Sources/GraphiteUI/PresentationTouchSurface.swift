/**
 * File: PresentationTouchSurface.swift
 * ------------------------------------
 * Layer: UI
 * Description: The touches on the device's presented slide: a finger's swipes and taps move between slides, and
 *              Apple Pencil, touching or hovering, draws the laser or fading ink, which every screen shows. The
 *              controls drawn over the slide keep their touches.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 27/11/2026
 */

#if canImport(UIKit)
import SwiftUI
import UIKit
import GraphiteCore

/// The device's slide's touches, over the slide (decision 6, decision 9). UIKit's recognizers, not SwiftUI's
/// gestures, so a Pencil touch is told from a finger's and a swipe from a stroke.
struct PresentationTouchSurface: UIViewRepresentable {
    let presentation: NotePresentation
    /// Whether a finger draws too, as on PDF pages when Draw with Finger is on: then two fingers swipe.
    let drawsWithFinger: Bool
    let idleClock: any ApplicationClock
    /// Where SwiftUI controls are drawn over the slide, in the window's coordinates: touches there are theirs.
    var controlRegions: [CGRect] = []

    func makeUIView(context: Context) -> PresentationTouchSurfaceView {
        let surface = PresentationTouchSurfaceView(idleClock: idleClock)
        surface.attach(to: presentation, drawsWithFinger: drawsWithFinger)
        surface.controlRegions = controlRegions
        return surface
    }

    func updateUIView(_ surface: PresentationTouchSurfaceView, context: Context) {
        surface.attach(to: presentation, drawsWithFinger: drawsWithFinger)
        surface.controlRegions = controlRegions
    }

    static func dismantleUIView(_ surface: PresentationTouchSurfaceView, coordinator: ()) {
        surface.detach()
    }
}

/// The view behind `PresentationTouchSurface`: it reads its touches into moves of the presentation and marks of
/// the Pencil, and draws the marks in its own layer (`PresentationMarksView`).
@MainActor
final class PresentationTouchSurfaceView: UIView, UIGestureRecognizerDelegate {
    /// The presentation it moves and marks: its one link to its owner (FR-43).
    private weak var presentation: NotePresentation?
    private let marksView: PresentationMarksView
    private lazy var nextSwipe = swipe(.left)
    private lazy var previousSwipe = swipe(.right)
    private lazy var tap: UITapGestureRecognizer = {
        let recognizer = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        recognizer.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        recognizer.delegate = self
        return recognizer
    }()
    private lazy var stroke: LaserTouchRecognizer = {
        let recognizer = LaserTouchRecognizer(target: self, action: #selector(handleStroke(_:)))
        recognizer.delegate = self
        return recognizer
    }()
    private lazy var hover = UIHoverGestureRecognizer(target: self, action: #selector(handleHover(_:)))
    /// Where controls are drawn over the slide, in the window's coordinates. A platform view is hit before the
    /// SwiftUI content drawn over it, so without this the slide took the taps meant for End and the Pencil menu.
    var controlRegions: [CGRect] = []

    init(idleClock: any ApplicationClock) {
        marksView = PresentationMarksView(idleClock: idleClock)
        super.init(frame: .zero)
        backgroundColor = .clear
        marksView.frame = bounds
        marksView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(marksView)
        for recognizer in [nextSwipe, previousSwipe, tap, stroke, hover] as [UIGestureRecognizer] { addGestureRecognizer(recognizer) }
        isAccessibilityElement = true
        accessibilityTraits = .allowsDirectInteraction
        accessibilityLabel = "Slide"
        accessibilityHint = "Swipe left or right to change slides."
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("PresentationTouchSurfaceView is created in code.") }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        let windowPoint = convert(point, to: nil)
        guard !controlRegions.contains(where: { region in region.contains(windowPoint) }) else { return false }
        return super.point(inside: point, with: event)
    }

    func attach(to newPresentation: NotePresentation, drawsWithFinger: Bool) {
        if presentation !== newPresentation {
            presentation?.marks.unregister(marksView)
            presentation = newPresentation
            newPresentation.marks.register(marksView)
        }
        let pencil = NSNumber(value: UITouch.TouchType.pencil.rawValue)
        let finger = NSNumber(value: UITouch.TouchType.direct.rawValue)
        stroke.allowedTouchTypes = drawsWithFinger ? [pencil, finger] : [pencil]
        for swipe in [nextSwipe, previousSwipe] { swipe.numberOfTouchesRequired = drawsWithFinger ? 2 : 1 }
    }

    func detach() {
        presentation?.marks.unregister(marksView)
        presentation = nil
    }

    /// The layer the marks are drawn in, for tests.
    var marksLayer: PresentationMarksView { marksView }

    private func swipe(_ direction: UISwipeGestureRecognizer.Direction) -> UISwipeGestureRecognizer {
        let recognizer = UISwipeGestureRecognizer(target: self, action: #selector(handleSwipe(_:)))
        recognizer.direction = direction
        recognizer.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        recognizer.delegate = self
        return recognizer
    }

    private var mapping: PresentationCanvasMapping { PresentationCanvasMapping(viewSize: bounds.size) }

    @objc private func handleSwipe(_ recognizer: UISwipeGestureRecognizer) {
        presentation?.move(recognizer.direction == .left ? .next : .previous)
    }

    @objc private func handleTap(_ recognizer: UITapGestureRecognizer) {
        presentation?.move(PresentationTouches.move(forTapAtX: recognizer.location(in: self).x, width: bounds.width))
    }

    @objc private func handleStroke(_ recognizer: LaserTouchRecognizer) {
        guard let presentation else { return }
        let mapping = mapping
        let point = mapping.canvasPoint(fromViewPoint: recognizer.location(in: self))
        let width = recognizer.lineWidth / max(mapping.scale, 0.01)
        switch recognizer.state {
        case .began: presentation.marks.draw(.begin(point: point, width: width))
        case .changed: presentation.marks.draw(.extend(point: point, width: width))
        default: presentation.marks.draw(.end)
        }
    }

    @objc private func handleHover(_ recognizer: UIHoverGestureRecognizer) {
        // Only Apple Pencil hovers over the slide; a pointer's hover is not pointing.
        guard let presentation, stroke.state == .possible || stroke.state == .failed else { return }
        switch recognizer.state {
        case .began, .changed:
            let point = recognizer.zOffset > 0 ? mapping.canvasPoint(fromViewPoint: recognizer.location(in: self)) : nil
            presentation.marks.draw(.dot(point: point, isHovering: true))
        default:
            presentation.marks.draw(.dot(point: nil, isHovering: false))
        }
    }

    /// A finger's tap moves slides even while fingers draw.
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        gestureRecognizer === tap || otherGestureRecognizer === tap
    }

    /// A hand resting on the screen while the Pencil writes neither draws nor moves slides.
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        !CanvasToolTouches.isHandResting(touch)
    }
}
#endif
