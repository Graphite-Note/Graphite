/**
 * File: PixelEraserController.swift
 * ---------------------------------
 * Layer: UI
 * Description: Graphite's own pixel eraser on one canvas, for the widths PencilKit's eraser cannot make on the
 *              screen: it takes the touches PencilKit would erase with, hides the ink under the tip as it moves,
 *              and gives the canvas the erased drawing when the touch lifts.
 *
 * Authors: Bahey Shalash
 * Version: 0.3
 * Date: 05/11/2026
 */
#if canImport(UIKit)
import UIKit
import UIKit.UIGestureRecognizerSubclass
import PencilKit
import GraphiteApple

/// Graphite's pixel eraser on one canvas (HUNT-319). PencilKit makes its fixed-width eraser 16.4 to
/// 80.4 points of the screen wide, so at a page's usual zoom it cuts no narrower than about 12
/// points of the page. For any other width the canvas stops drawing with PencilKit and this
/// controller erases instead (`PixelEraserTouch`), with the chosen width on the page at any zoom.
///
/// It takes the touches PencilKit's eraser would take: the Pencil, and a finger when fingers draw,
/// but not a hand resting on the page. While the touch moves, PencilKit's views are masked to
/// what still shows, so the ink leaves from under the tip in the frame the touch reaches it. At the
/// lift the canvas is given the erased drawing once (`showErasedDrawing`), which
/// its owner records as one step of the history and saves like any change of the drawing. A
/// circle as wide as the eraser shows where it is while it erases, and fainter while the Pencil hovers.
@MainActor
final class PixelEraserController: NSObject, UIGestureRecognizerDelegate {
    private unowned let canvas: HistoryCanvasView
    private(set) lazy var touchRecognizer: PixelEraserTouchRecognizer = {
        let recognizer = PixelEraserTouchRecognizer(target: nil, action: nil)
        recognizer.delegate = self
        recognizer.touchDidBegin = { [weak self] point in self?.beginTouch(at: point) }
        recognizer.touchDidMove = { [weak self] points, predictedPoints in self?.moveTouch(through: points, predicted: predictedPoints) }
        recognizer.touchDidEnd = { [weak self] wasCancelled in self?.endTouch(wasCancelled: wasCancelled) }
        return recognizer
    }()
    private lazy var hoverRecognizer = UIHoverGestureRecognizer(target: self, action: #selector(handleHover(_:)))

    /// The eraser's width in the drawing's points, while this controller erases; nil while it does not.
    private(set) var width: CGFloat?
    /// The width chosen for Graphite's eraser, in the drawing's points; nil while PencilKit's tool is chosen.
    var chosenWidth: CGFloat?
    private var touch: PixelEraserTouch?
    /// Whether something gave the canvas another drawing while the touch moved.
    private var drawingWasReplaced = false
    /// PencilKit's views, each with the mask that shows its ink only where it still shows, and the mask it had before.
    private var maskedInkLayers: [(layer: CALayer, mask: CAShapeLayer, earlierMask: CALayer?)] = []
    private let cursorLayer = CAShapeLayer()

    init(canvas: HistoryCanvasView) {
        self.canvas = canvas
        super.init()
        cursorLayer.fillColor = nil
        cursorLayer.zPosition = 2
        cursorLayer.isHidden = true
    }

    /// The pixel eraser's width as chosen, in the drawing's points: PencilKit makes a tool of the
    /// bar's width no narrower than it can draw, so the bar's own is read.
    static func chosenWidth(of eraser: PKEraserTool, barTool: PencilToolSelection?) -> CGFloat {
        barTool.flatMap { barTool in barTool.kind == .eraser && !barTool.erasesWholeStrokes ? CGFloat(barTool.eraserWidth) : nil } ?? eraser.width
    }

    /// The width Graphite's eraser erases with for a chosen tool, in the drawing's points: the pixel
    /// eraser's when PencilKit's cannot make it on the screen, nil for any other tool or width.
    static func widthBeyondPencilKit(of chosenTool: PKTool, barTool: PencilToolSelection?, screenPointsPerDrawingPoint: CGFloat) -> CGFloat? {
        guard let eraser = chosenTool as? PKEraserTool, eraser.eraserType != .vector else { return nil }
        let width = chosenWidth(of: eraser, barTool: barTool)
        return PencilEraserWidths.erasesWithPencilKit(chosen: Double(width), screenPointsPerPagePoint: Double(screenPointsPerDrawingPoint)) ? nil : width
    }

    /// Erases with the chosen width unless another of Graphite's tools, such as the lasso, has the
    /// canvas; says whether it erases.
    func erases(whileAnotherToolIsInUse anotherToolIsInUse: Bool) -> Bool {
        erase(withWidth: anotherToolIsInUse ? nil : chosenWidth)
        return isErasing
    }

    /// Erases with a width in the drawing's points, or stops erasing with nil. A touch under way
    /// when it stops, as when the zoom brings the width within PencilKit's reach, keeps what it erased.
    private func erase(withWidth newWidth: CGFloat?) {
        guard newWidth != width else { return }
        if newWidth == nil, touch != nil { endTouch(wasCancelled: false) }
        width = newWidth
        if newWidth != nil, touchRecognizer.view == nil {
            canvas.addGestureRecognizer(touchRecognizer)
            hoverRecognizer.delegate = self
            canvas.addGestureRecognizer(hoverRecognizer)
        }
        touchRecognizer.isEnabled = newWidth != nil
        hoverRecognizer.isEnabled = newWidth != nil
        if newWidth == nil { hideCursor() }
    }

    var isErasing: Bool { width != nil }

    /// The canvas was given another drawing (`HistoryCanvasView.drawing`).
    func canvasDrawingWasReplaced() {
        if touch != nil { drawingWasReplaced = true }
    }

    /// The eraser takes the touches the canvas would draw with: the Pencil, and a finger when
    /// fingers draw. Other fingers scroll the page as they do while drawing.
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        canvas.drawingGestureRecognizer.allowedTouchTypes.contains(NSNumber(value: touch.type.rawValue))
            && !CanvasToolTouches.isHandResting(touch)
    }

    // MARK: The touch

    private func beginTouch(at canvasPoint: CGPoint) {
        // A PDF page's stored ink is still on its way: there is nothing on the canvas to erase.
        guard let width, canvas.zoomScale > 0, (canvas as? PDFPageCanvasView)?.isRestoringStoredInk != true else { return }
        let zoomScale = canvas.zoomScale
        let shownBounds = CGRect(x: 0, y: 0, width: max(canvas.contentSize.width, canvas.bounds.maxX) / zoomScale,
                                 height: max(canvas.contentSize.height, canvas.bounds.maxY) / zoomScale)
            .insetBy(dx: -Self.shownBoundsMargin, dy: -Self.shownBoundsMargin)
        touch = PixelEraserTouch(drawing: canvas.drawing, width: width, shownBounds: shownBounds)
        drawingWasReplaced = false
        maskInkLayers()
        moveTouch(through: [canvasPoint], predicted: [])
    }

    /// How far past the canvas's content its ink is shown while erasing, in the drawing's points,
    /// for a canvas that scrolls under the touch.
    private static let shownBoundsMargin: CGFloat = 4_000

    private func moveTouch(through canvasPoints: [CGPoint], predicted predictedCanvasPoints: [CGPoint]) {
        guard touch != nil, canvas.zoomScale > 0 else { return }
        let zoomScale = canvas.zoomScale
        let toDrawing = { (point: CGPoint) in CGPoint(x: point.x / zoomScale, y: point.y / zoomScale) }
        guard let shownArea = touch?.move(through: canvasPoints.map(toDrawing), predicted: predictedCanvasPoints.map(toDrawing)) else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for maskedLayer in maskedInkLayers {
            var drawingToLayer = CGAffineTransform(scaleX: zoomScale, y: zoomScale).concatenating(transform(fromCanvasTo: maskedLayer.layer))
            maskedLayer.mask.path = shownArea.copy(using: &drawingToLayer)
        }
        CATransaction.commit()
        if let lastPoint = canvasPoints.last { showCursor(at: lastPoint, isHovering: false) }
    }

    private func endTouch(wasCancelled: Bool) {
        hideCursor()
        guard let endedTouch = touch else { return }
        touch = nil
        // A touch taken back, as by a system gesture, leaves the drawing as it was, as PencilKit drops a cancelled stroke.
        guard !wasCancelled, let erasedDrawing = endedTouch.erasedDrawing(replacing: drawingWasReplaced ? canvas.drawing : nil) else {
            unmaskInkLayers()
            return
        }
        showErasedDrawing(erasedDrawing)
    }

    /// Gives the canvas the drawing the touch left, as one change its owner records; the canvas as it
    /// was, with the swept ink hidden, stays over it until PencilKit has drawn the new drawing.
    private func showErasedDrawing(_ erasedDrawing: PKDrawing) {
        canvas.coverUntilRendered()
        unmaskInkLayers()
        canvas.setDrawingMadeByCanvas(erasedDrawing)
    }

    // MARK: Hiding the ink swept

    /// PencilKit's views are the canvas's subviews over the topmost of its own, such as the
    /// drawing editor's paper and pictures, which stay as they are.
    private func maskInkLayers() {
        unmaskInkLayers()
        let subviews = canvas.subviews
        let firstInkIndex = canvas.topViewUnderInk.flatMap { topView in subviews.firstIndex(of: topView) }.map { index in index + 1 } ?? 0
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for inkView in subviews[firstInkIndex...] where !inkView.isHidden {
            let mask = CAShapeLayer()
            mask.fillColor = UIColor.black.cgColor
            // The mask's coordinates are its layer's own.
            mask.bounds = inkView.layer.bounds
            mask.position = CGPoint(x: inkView.layer.bounds.midX, y: inkView.layer.bounds.midY)
            maskedInkLayers.append((inkView.layer, mask, inkView.layer.mask))
            inkView.layer.mask = mask
        }
        CATransaction.commit()
    }

    private func unmaskInkLayers() {
        guard !maskedInkLayers.isEmpty else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for maskedLayer in maskedInkLayers where maskedLayer.layer.mask === maskedLayer.mask { maskedLayer.layer.mask = maskedLayer.earlierMask }
        CATransaction.commit()
        maskedInkLayers = []
    }

    /// From the canvas's coordinates to a layer inside it, through its position, bounds and transform.
    private func transform(fromCanvasTo innerLayer: CALayer) -> CGAffineTransform {
        let origin = canvas.layer.convert(CGPoint.zero, to: innerLayer)
        let alongX = canvas.layer.convert(CGPoint(x: 1, y: 0), to: innerLayer)
        let alongY = canvas.layer.convert(CGPoint(x: 0, y: 1), to: innerLayer)
        return CGAffineTransform(a: alongX.x - origin.x, b: alongX.y - origin.y, c: alongY.x - origin.x, d: alongY.y - origin.y, tx: origin.x, ty: origin.y)
    }

    var isHidingSweptInk: Bool { !maskedInkLayers.isEmpty }

    // MARK: The cursor

    /// The narrowest the circle is drawn, in points of the screen, to be seen at all.
    private static let narrowestCursorOnScreen: CGFloat = 3

    @objc private func handleHover(_ recognizer: UIHoverGestureRecognizer) {
        // Only Apple Pencil hovers over the page; a pointer's hover is not erasing.
        guard touch == nil else { return }
        switch recognizer.state {
        case .began, .changed:
            if recognizer.zOffset > 0 { showCursor(at: recognizer.location(in: canvas), isHovering: true) } else { hideCursor() }
        default:
            hideCursor()
        }
    }

    private func showCursor(at canvasPoint: CGPoint, isHovering: Bool) {
        guard let width, canvas.window != nil else { return }
        // The canvas's points on the screen: a PDF page's canvas is scaled as its page is.
        let screenPointsPerCanvasPoint = max(canvas.convert(CGRect(x: 0, y: 0, width: 1, height: 1), to: nil).width, 0.01)
        let diameter = max(width * canvas.zoomScale, Self.narrowestCursorOnScreen / screenPointsPerCanvasPoint)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let circleBounds = CGRect(x: canvasPoint.x - diameter / 2, y: canvasPoint.y - diameter / 2, width: diameter, height: diameter)
        cursorLayer.path = CGPath(ellipseIn: circleBounds, transform: nil)
        cursorLayer.lineWidth = 1 / screenPointsPerCanvasPoint
        cursorLayer.strokeColor = UIColor.systemGray.resolvedColor(with: canvas.traitCollection).cgColor
        cursorLayer.opacity = isHovering ? 0.5 : 1
        cursorLayer.isHidden = false
        if cursorLayer.superlayer == nil { canvas.layer.addSublayer(cursorLayer) }
        CATransaction.commit()
    }

    private func hideCursor() {
        guard !cursorLayer.isHidden else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        cursorLayer.isHidden = true
        CATransaction.commit()
    }

    var isShowingCursor: Bool { !cursorLayer.isHidden && cursorLayer.superlayer != nil }
}

/// Follows the one touch the pixel eraser erases with: its point as it lands, then each move with
/// the coalesced points UIKit gathered between frames and the points it predicts, then the lift.
/// It recognizes at the first move, so a second finger landing before then, for a pinch, takes
/// the touch instead; a touch that lifts without moving erases a spot where it landed.
///
/// It takes touches of more than one type, so the Pencil landing while a finger erases reaches it:
/// that finger, when fingers draw, is most often the hand holding the Pencil, which landed before
/// the Pencil was active and so is not known as a hand (`CanvasToolTouches.isHandResting`). The
/// Pencil then takes the eraser, and what the finger swept is left as it was, as palm rejection
/// takes back a hand's stroke. Until 2026-11-05 it took one type only, UIKit's default: while the
/// hand lay on the page the eraser held its touch, its circle stayed where the hand lay, and UIKit
/// kept every Pencil touch from it, so the Pencil erased nothing until the hand lifted or the
/// canvas left the screen (HUNT-326).
final class PixelEraserTouchRecognizer: UIGestureRecognizer {
    var touchDidBegin: (CGPoint) -> Void = { _ in }
    var touchDidMove: (_ points: [CGPoint], _ predictedPoints: [CGPoint]) -> Void = { _, _ in }
    var touchDidEnd: (_ wasCancelled: Bool) -> Void = { _ in }
    private weak var trackedTouch: UITouch?
    private var isTouchUnderWay = false

    override init(target: Any?, action: Selector?) {
        super.init(target: target, action: action)
        requiresExclusiveTouchType = false
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        let pencilTouch = touches.first { touch in touch.type == .pencil }
        if isTouchUnderWay, let trackedTouch, trackedTouch.type != .pencil, let pencilTouch {
            // The Pencil lands while a finger erases: the finger's touch is taken back, and the Pencil erases.
            finishTouch(wasCancelled: true)
            track(pencilTouch)
            return
        }
        guard trackedTouch == nil, !isTouchUnderWay, let touch = pencilTouch ?? touches.first else {
            if state == .possible, isTouchUnderWay, let trackedTouch, touches.contains(where: { touch in touch.type == trackedTouch.type }) {
                // A second touch of the same kind before the first moved: a pinch or a scroll, not erasing.
                finishTouch(wasCancelled: true)
                state = .failed
                return
            }
            for touch in touches where touch !== trackedTouch { ignore(touch, for: event) }
            return
        }
        track(touch)
    }

    private func track(_ touch: UITouch) {
        trackedTouch = touch
        isTouchUnderWay = true
        touchDidBegin(touch.location(in: view))
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let trackedTouch, touches.contains(trackedTouch), isTouchUnderWay else { return }
        let points = (event.coalescedTouches(for: trackedTouch) ?? [trackedTouch]).map { coalescedTouch in coalescedTouch.location(in: view) }
        let predictedPoints = (event.predictedTouches(for: trackedTouch) ?? []).map { predictedTouch in predictedTouch.location(in: view) }
        touchDidMove(points, predictedPoints)
        state = state == .possible ? .began : .changed
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let trackedTouch, touches.contains(trackedTouch), isTouchUnderWay else { return }
        touchDidMove([trackedTouch.location(in: view)], [])
        finishTouch(wasCancelled: false)
        state = .ended
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let trackedTouch, touches.contains(trackedTouch), isTouchUnderWay else { return }
        finishTouch(wasCancelled: true)
        state = .cancelled
    }

    override func reset() {
        super.reset()
        // A reset without the touch ending, as when the canvas leaves the window mid-touch.
        if isTouchUnderWay { finishTouch(wasCancelled: true) }
        trackedTouch = nil
    }

    private func finishTouch(wasCancelled: Bool) {
        isTouchUnderWay = false
        touchDidEnd(wasCancelled)
    }
}
#endif
