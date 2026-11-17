/**
 * File: PencilColorTouchRecognizers.swift
 * ---------------------------------------
 * Layer: UI
 * Description: The touches of the Pencil bar's row of colors: a UIKit view over the row whose recognizers find the color
 *              under a tap, the drag that arranges one (a press held a moment, since a swipe scrolls the strip) and a
 *              color's menu (the hold let go where it lifted), and report them to the row, which draws.
 *
 * Authors: Bahey Shalash
 * Version: 0.3
 * Date: 17/11/2026
 */

#if canImport(UIKit)
import SwiftUI
import UIKit
import UIKit.UIGestureRecognizerSubclass

/// What the row's touches report, by the place of the color touched in the row (the first color is place 0).
struct PencilColorRowTouches {
    /// What a drag reports as it moves and ends.
    enum DragPhase {
        /// The finger has gone `translation` from where the drag began; `visibleLocation` is how far it stands from
        /// the left edge of the row's visible part (the strip's, when the row scrolls).
        case moved(translation: CGSize, visibleLocation: Double)
        /// The finger lifted after going `translation`.
        case ended(translation: CGSize)
        /// The system took the touch (a menu, another gesture): nothing is stored.
        case cancelled
    }

    /// The width of one place of the row, in points.
    let swatchPitch: Double
    /// Whether a place can be dragged (a color, not the empty end of the row).
    let canArrange: (Int) -> Bool
    /// How long a color is held before it lifts: a finger that moves sooner swipes the strip, which scrolls sideways
    /// only, so a quick drag in any direction never moves or removes a color (the owner's report of 2026-11-14).
    static let holdSeconds = 0.25
    /// How far a lifted color may go and still count as held still, so letting go opens its menu, in points.
    static let stillHoldTravel = 6.0

    let tapped: (Int) -> Void
    let dragged: (Int, DragPhase) -> Void
    /// The menu of the color at a place, opened by a hold let go where it lifted; nil where a place has none.
    let menu: (Int) -> UIMenu?
}

/// A clear view over the row that takes its touches by UIKit's own recognizers, so they settle with the strip's scroll
/// view and Apple Pencil, the pointer and touches delivered through UIKit's event path (as the hosted tests make them)
/// reach them. It shows nothing and is hidden from VoiceOver: the row's colors carry their own actions.
struct PencilColorRowTouchSurface: UIViewRepresentable {
    let touches: PencilColorRowTouches

    func makeUIView(context: Context) -> PencilColorRowTouchView {
        let view = PencilColorRowTouchView()
        view.touches = touches
        return view
    }

    func updateUIView(_ view: PencilColorRowTouchView, context: Context) {
        view.touches = touches
    }
}

/// One hold does both a color's jobs, as on the Home Screen: held, the color lifts; dragged, it is arranged; let go where
/// it lifted, its menu opens. The menu is an edit menu opened on that release, not a context menu interaction, whose
/// own recognizers made every long press on the view wait for them, so the hold never lifted a color. The hold is a
/// recognizer of the row's own (`PencilColorHoldRecognizer`), not UIKit's long press, and once a color is lifted no
/// other recognizer begins from its touch (the owner's report of 2026-11-17 on the iPad: the colors "seem to be fixed").
final class PencilColorRowTouchView: UIView, @preconcurrency UIEditMenuInteractionDelegate {
    /// The row's latest answers; replaced on every update of the row.
    var touches: PencilColorRowTouches?
    private let arrangingRecognizer = PencilColorHoldRecognizer()
    private lazy var menuInteraction = UIEditMenuInteraction(delegate: self)
    /// The place and the window point a drag began at.
    private var dragStart: (place: Int, windowLocation: CGPoint)?
    /// Whether the lifted color has gone far enough to be a drag rather than a hold for its menu.
    private var liftedColorHasMoved = false
    /// The strip held still while a color is lifted: its own pan would take the touch and drop the color.
    private weak var stillStrip: UIScrollView?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isAccessibilityElement = false
        accessibilityElementsHidden = true
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleTap(_:))))
        arrangingRecognizer.addTarget(self, action: #selector(handleDrag(_:)))
        addGestureRecognizer(arrangingRecognizer)
        addInteraction(menuInteraction)
    }

    required init?(coder: NSCoder) { nil }

    /// The strip hands a touch to the row at once rather than after its usual pause, so the hold that lifts a color
    /// counts from the moment the finger lands; a finger that moves sooner still scrolls the strip.
    override func didMoveToWindow() {
        super.didMoveToWindow()
        enclosingStrip()?.delaysContentTouches = false
    }

    private func place(at point: CGPoint) -> Int? {
        guard let touches, touches.swatchPitch > 0, bounds.contains(point) else { return nil }
        return Int(point.x / touches.swatchPitch)
    }

    @objc private func handleTap(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .ended, let place = place(at: recognizer.location(in: self)) else { return }
        touches?.tapped(place)
    }

    /// UIKit asks the touched view about every recognizer the touch reaches, its ancestors' too. While a color is lifted
    /// none but the hold begins: the split view's swipe that shows the sidebar took a lifted color's sideways drag.
    override func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
        guard recognizer === arrangingRecognizer else { return dragStart == nil && super.gestureRecognizerShouldBegin(recognizer) }
        guard let place = place(at: recognizer.location(in: self)) else { return false }
        return touches?.canArrange(place) ?? false
    }

    @objc private func handleDrag(_ recognizer: UIGestureRecognizer) {
        guard let touches else { return }
        let windowLocation = recognizer.location(in: nil)
        switch recognizer.state {
        case .began:
            guard let place = place(at: convert(windowLocation, from: nil)) else { return }
            dragStart = (place, windowLocation)
            liftedColorHasMoved = false
            holdStripStill()
            touches.dragged(place, .moved(translation: translation(to: windowLocation), visibleLocation: visibleLocation(of: recognizer)))
        case .changed:
            guard let dragStart else { return }
            let translation = translation(to: windowLocation)
            if hypot(translation.width, translation.height) > PencilColorRowTouches.stillHoldTravel { liftedColorHasMoved = true }
            touches.dragged(dragStart.place, .moved(translation: translation, visibleLocation: visibleLocation(of: recognizer)))
        case .ended:
            guard let dragStart else { return }
            touches.dragged(dragStart.place, .ended(translation: translation(to: windowLocation)))
            let opensMenu = !liftedColorHasMoved
            finishDrag()
            if opensMenu { presentMenu(at: dragStart.place) }
        case .cancelled, .failed:
            guard let dragStart else { return }
            touches.dragged(dragStart.place, .cancelled)
            finishDrag()
        case .possible:
            return
        @unknown default:
            return
        }
    }

    /// Stops the strip's own scrolling under the finger while a color is lifted; the drag scrolls it near either end.
    private func holdStripStill() {
        guard let strip = enclosingStrip() else { return }
        strip.isScrollEnabled = false
        stillStrip = strip
    }

    private func finishDrag() {
        dragStart = nil
        liftedColorHasMoved = false
        stillStrip?.isScrollEnabled = true
        stillStrip = nil
    }

    private func enclosingStrip() -> UIScrollView? {
        var ancestor = superview
        while let view = ancestor, !(view is UIScrollView) { ancestor = view.superview }
        return ancestor as? UIScrollView
    }

    /// In window points, which a strip scrolling under a still finger does not change.
    private func translation(to windowLocation: CGPoint) -> CGSize {
        guard let start = dragStart?.windowLocation else { return .zero }
        return CGSize(width: windowLocation.x - start.x, height: windowLocation.y - start.y)
    }

    /// How far the finger stands from the left edge of the strip's visible part.
    private func visibleLocation(of recognizer: UIGestureRecognizer) -> Double {
        guard let scrollView = enclosingStrip() else { return recognizer.location(in: self).x }
        return recognizer.location(in: scrollView).x - scrollView.contentOffset.x
    }

    /// Opens the menu of the color at `place`, above it.
    private func presentMenu(at place: Int) {
        guard let touches, touches.menu(place) != nil else { return }
        let sourcePoint = CGPoint(x: (Double(place) + 0.5) * touches.swatchPitch, y: 0)
        menuInteraction.presentEditMenu(with: UIEditMenuConfiguration(identifier: NSNumber(value: place), sourcePoint: sourcePoint))
    }

    func editMenuInteraction(_ interaction: UIEditMenuInteraction, menuFor configuration: UIEditMenuConfiguration,
                             suggestedActions: [UIMenuElement]) -> UIMenu? {
        guard let place = (configuration.identifier as? NSNumber)?.intValue else { return nil }
        return touches?.menu(place)
    }
}
/// A finger, Apple Pencil or the pointer held still on a color for `PencilColorRowTouches.holdSeconds`, then followed until
/// it lifts. UIKit's long press could not do it in the app: with the system's own touches it began late or not at all,
/// behind the drag and drop lift that SwiftUI puts on the window's root view, and the split view's swipe took a sideways
/// drag (traced in a simulator on 2026-11-17; the hosted tests' touches start no drag lift, so they had passed).
/// Its own class keeps it out of the waits UIKit sets up between long presses, it waits for no other recognizer, and it
/// fails as soon as the touch moves sooner, so a swipe still scrolls the strip and a tap still chooses.
final class PencilColorHoldRecognizer: UIGestureRecognizer {
    /// How far the touch may move during the hold and still lift the color, in points, as UIKit's long press allows.
    static let allowableMovement = 10.0
    private weak var trackedTouch: UITouch?
    private var startLocation: CGPoint = .zero

    override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool {
        // Before the hold ends, only a movement fails it (a scroll of the strip, the split view's swipe).
        state == .possible ? false : super.canBePrevented(by: preventingGestureRecognizer)
    }

    override func shouldRequireFailure(of otherGestureRecognizer: UIGestureRecognizer) -> Bool { false }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        guard trackedTouch == nil, touches.count == 1, let touch = touches.first else {
            // A second finger is a pinch or a two-finger swipe, never a hold.
            if state == .possible { state = .failed }
            return
        }
        trackedTouch = touch
        startLocation = touch.location(in: nil)
        // In the common modes, so the hold ends on time while the strip or a page is tracking a touch.
        perform(#selector(holdEnded), with: nil, afterDelay: PencilColorRowTouches.holdSeconds, inModes: [.common])
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let trackedTouch, touches.contains(trackedTouch) else { return }
        switch state {
        case .possible:
            let location = trackedTouch.location(in: nil)
            if hypot(location.x - startLocation.x, location.y - startLocation.y) > Self.allowableMovement { state = .failed }
        case .began, .changed:
            state = .changed
        default:
            break
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let trackedTouch, touches.contains(trackedTouch) else { return }
        state = state == .possible ? .failed : .ended
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let trackedTouch, touches.contains(trackedTouch) else { return }
        state = state == .possible ? .failed : .cancelled
    }

    override func reset() {
        super.reset()
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(holdEnded), object: nil)
        trackedTouch = nil
    }

    @objc private func holdEnded() {
        guard state == .possible, trackedTouch != nil else { return }
        state = .began
    }
}
#endif
