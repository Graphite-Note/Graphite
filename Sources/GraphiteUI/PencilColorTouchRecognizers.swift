/**
 * File: PencilColorTouchRecognizers.swift
 * ---------------------------------------
 * Layer: UI
 * Description: The touches of the Pencil bar's row of colors: a UIKit view over the row whose recognizers find the color
 *              under a tap, the drag that arranges one (a pan on the bar, a press held a moment in a strip that
 *              scrolls) and a color's menu, and report them to the row, which draws.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 13/11/2026
 */

#if canImport(UIKit)
import SwiftUI
import UIKit

/// What the row's touches report, by the place of the color touched in the row (black, when shown, is place 0).
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
    /// Whether a place can be dragged (a favorite or highlighter color, not black or Undo).
    let canArrange: (Int) -> Bool
    /// The press held before a color lifts where a sideways drag scrolls instead; nil where a drag lifts it at once.
    let holdSeconds: Double?
    let tapped: (Int) -> Void
    let dragged: (Int, DragPhase) -> Void
    /// The menu of the color at a place, or nil where a place has none.
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

final class PencilColorRowTouchView: UIView, UIContextMenuInteractionDelegate {
    /// The row's latest answers; replaced on every update of the row.
    var touches: PencilColorRowTouches? {
        didSet { if arrangingRecognizer == nil || touches?.holdSeconds != oldValue?.holdSeconds { installArrangingRecognizer() } }
    }
    private var arrangingRecognizer: UIGestureRecognizer?
    /// The place and the window point a drag began at.
    private var dragStart: (place: Int, windowLocation: CGPoint)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isAccessibilityElement = false
        accessibilityElementsHidden = true
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleTap(_:))))
        addInteraction(UIContextMenuInteraction(delegate: self))
    }

    required init?(coder: NSCoder) { nil }

    private func installArrangingRecognizer() {
        if let arrangingRecognizer { removeGestureRecognizer(arrangingRecognizer) }
        let recognizer: UIGestureRecognizer
        if let holdSeconds = touches?.holdSeconds {
            let press = UILongPressGestureRecognizer(target: self, action: #selector(handleDrag(_:)))
            press.minimumPressDuration = holdSeconds
            recognizer = press
        } else {
            recognizer = UIPanGestureRecognizer(target: self, action: #selector(handleDrag(_:)))
        }
        addGestureRecognizer(recognizer)
        arrangingRecognizer = recognizer
    }

    private func place(at point: CGPoint) -> Int? {
        guard let touches, touches.swatchPitch > 0, bounds.contains(point) else { return nil }
        return Int(point.x / touches.swatchPitch)
    }

    @objc private func handleTap(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .ended, let place = place(at: recognizer.location(in: self)) else { return }
        touches?.tapped(place)
    }

    override func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
        guard recognizer === arrangingRecognizer else { return super.gestureRecognizerShouldBegin(recognizer) }
        // A pan begins after its threshold: where the finger touched down is where it is less what it has travelled.
        let travel = (recognizer as? UIPanGestureRecognizer)?.translation(in: self) ?? .zero
        let location = recognizer.location(in: self)
        guard let place = place(at: CGPoint(x: location.x - travel.x, y: location.y - travel.y)) else { return false }
        return touches?.canArrange(place) ?? false
    }

    @objc private func handleDrag(_ recognizer: UIGestureRecognizer) {
        guard let touches else { return }
        let windowLocation = recognizer.location(in: nil)
        switch recognizer.state {
        case .began:
            let travel = (recognizer as? UIPanGestureRecognizer)?.translation(in: nil) ?? .zero
            let startInWindow = CGPoint(x: windowLocation.x - travel.x, y: windowLocation.y - travel.y)
            guard let place = place(at: convert(startInWindow, from: nil)) else { return }
            dragStart = (place, startInWindow)
            touches.dragged(place, .moved(translation: translation(to: windowLocation), visibleLocation: visibleLocation(of: recognizer)))
        case .changed:
            guard let dragStart else { return }
            touches.dragged(dragStart.place, .moved(translation: translation(to: windowLocation), visibleLocation: visibleLocation(of: recognizer)))
        case .ended:
            guard let dragStart else { return }
            touches.dragged(dragStart.place, .ended(translation: translation(to: windowLocation)))
            self.dragStart = nil
        case .cancelled, .failed:
            guard let dragStart else { return }
            touches.dragged(dragStart.place, .cancelled)
            self.dragStart = nil
        case .possible:
            return
        @unknown default:
            return
        }
    }

    /// In window points, which a strip scrolling under a still finger does not change.
    private func translation(to windowLocation: CGPoint) -> CGSize {
        guard let start = dragStart?.windowLocation else { return .zero }
        return CGSize(width: windowLocation.x - start.x, height: windowLocation.y - start.y)
    }

    /// How far the finger stands from the left edge of the strip's visible part, or of this row when it does not scroll.
    private func visibleLocation(of recognizer: UIGestureRecognizer) -> Double {
        var ancestor = superview
        while let view = ancestor, !(view is UIScrollView) { ancestor = view.superview }
        guard let scrollView = ancestor as? UIScrollView else { return recognizer.location(in: self).x }
        return recognizer.location(in: scrollView).x - scrollView.contentOffset.x
    }

    func contextMenuInteraction(_ interaction: UIContextMenuInteraction, configurationForMenuAtLocation location: CGPoint) -> UIContextMenuConfiguration? {
        guard dragStart == nil, let place = place(at: location), let menu = touches?.menu(place) else { return nil }
        return UIContextMenuConfiguration(identifier: NSNumber(value: place), previewProvider: nil) { _ in menu }
    }

    /// The menu lifts the color held, drawn from the row under this clear view, not the whole row.
    func contextMenuInteraction(_ interaction: UIContextMenuInteraction, configuration: UIContextMenuConfiguration,
                                highlightPreviewForItemWithIdentifier identifier: any NSCopying) -> UITargetedPreview? {
        guard let touches, let place = (identifier as? NSNumber)?.intValue, let superview else { return nil }
        let swatchFrame = CGRect(x: Double(place) * touches.swatchPitch, y: 0, width: touches.swatchPitch, height: bounds.height)
        guard let snapshot = superview.resizableSnapshotView(from: convert(swatchFrame, to: superview), afterScreenUpdates: false,
                                                             withCapInsets: .zero) else { return nil }
        let parameters = UIPreviewParameters()
        parameters.visiblePath = UIBezierPath(ovalIn: snapshot.bounds.insetBy(dx: 2, dy: (snapshot.bounds.height - snapshot.bounds.width) / 2 + 2))
        parameters.backgroundColor = .clear
        return UITargetedPreview(view: snapshot, parameters: parameters,
                                 target: UIPreviewTarget(container: self, center: CGPoint(x: swatchFrame.midX, y: swatchFrame.midY)))
    }
}
#endif
