/**
 * File: SynthesizedStrokes.swift
 * ------------------------------
 * Layer: Tests
 * Description: Draws a real stroke on a real PencilKit canvas in a hosted test, by telling the
 *              canvas's own drawing recognizer of stand-in touches.
 *
 * Authors: Bahey Shalash
 * Version: 0.4
 * Date: 04/11/2026
 */
#if os(iOS)
import SwiftUI
import UIKit
import PencilKit
import PDFKit
@testable import GraphiteUI

/// PencilKit draws nothing from touches sent through UIKit's event path (`SynthesizedTouches`),
/// even when their coalesced samples are answered. Its recognizer takes stand-in touches told
/// to it directly, and the canvas then makes, shows and reports the stroke as for any other: the
/// stored sizes, the delegate's report and the saved ink are PencilKit's own. Whether a real
/// Pencil's force changes the sizes is outside this; `touchType` covers what the type changes.
@MainActor
enum SynthesizedStrokes {
    /// Waits while the page draws what it was just told to: PDFKit and PencilKit report no end
    /// to it, and the rendering scale takes a fixed time to settle after a zoom.
    static func waitForPageToDraw(milliseconds: Int = 400) async throws {
        try await Task.sleep(for: .milliseconds(milliseconds))
    }

    /// Waits until a PDF page's canvas draws at the scale its view's zoom calls for. The canvas
    /// takes a new zoom a moment after the view, and not while a stroke is under way: the touches
    /// UIKit gave its drawing recognizer hold the change back. The stand-in touches told straight
    /// to the recognizer are not among them, so a stroke begun before the canvas had the zoom was
    /// laid out again under PencilKit's live stroke, and PencilKit dropped it.
    static func waitForCanvasToDrawAtTheZoom(of canvas: PDFPageCanvasView, in pdfView: PDFView) async throws {
        guard canvas.page != nil else { return }
        try await waitUntil("the page's canvas draws at the PDF's zoom") {
            let scale = PDFPageOverlayView.renderingScale(forZoom: pdfView.scaleFactor)
            return canvas.window != nil && abs(canvas.zoomScale - scale) < 0.02
        }
    }

    /// Lets a finger draw on a PDF page, which reads the standard preference, until `restore` is called,
    /// which puts back what the device had: on a person's iPad the hosted tests run in their own app.
    static func letFingersDraw() -> () -> Void {
        let restore = HostedDevicePreferences.saving([PDFAnnotationPreferenceKey.drawsWithFinger])
        let preference = AppStorage(wrappedValue: false, PDFAnnotationPreferenceKey.drawsWithFinger)
        preference.wrappedValue = true
        return restore
    }

    /// One stroke through points in the window's coordinates. Returns when the canvas has
    /// reported the stroke, or after a second if PencilKit made none.
    /// `recognizer` is what is told of the touches, the canvas's own by default; `midway` runs
    /// at the middle of the stroke, while it is under way.
    @discardableResult
    static func draw(on canvas: PKCanvasView, through windowPoints: [CGPoint], in window: UIWindow, touchType: UITouch.TouchType = .direct,
                     toldTo recognizer: UIGestureRecognizer? = nil, midway: (() async throws -> Void)? = nil) async throws -> PKStroke? {
        guard let firstPoint = windowPoints.first else { return nil }
        let recognizer = recognizer ?? canvas.drawingGestureRecognizer
        let strokeCountBefore = canvas.drawing.strokes.count
        let touch = StrokeTouch(window: window, view: canvas, location: firstPoint, touchType: touchType)
        let event = StrokeEvent()
        recognizer.touchesBegan([touch], with: event)
        for (pointIndex, point) in windowPoints.enumerated().dropFirst() {
            touch.move(to: point, phase: .moved)
            recognizer.touchesMoved([touch], with: event)
            try await waitForPageToDraw(milliseconds: 8)
            if pointIndex == windowPoints.count / 2 { try await midway?() }
        }
        touch.move(to: windowPoints.last ?? firstPoint, phase: .ended)
        recognizer.touchesEnded([touch], with: event)
        // PencilKit finishes a stroke in its own time, and a busy machine has taken over a second.
        for _ in 0..<200 where canvas.drawing.strokes.count <= strokeCountBefore {
            try await waitForPageToDraw(milliseconds: 25)
        }
        return canvas.drawing.strokes.count > strokeCountBefore ? canvas.drawing.strokes.last : nil
    }

    /// A straight stroke of `steps` moves between two points of the window.
    static func line(from start: CGPoint, to end: CGPoint, steps: Int = 30) -> [CGPoint] {
        (0...steps).map { step in
            let fraction = CGFloat(step) / CGFloat(steps)
            return CGPoint(x: start.x + (end.x - start.x) * fraction, y: start.y + (end.y - start.y) * fraction)
        }
    }

    /// How wide a stroke along the rows draws in the drawing's points: the ink crossed by the
    /// columns of its picture, on average, each row counted by how opaque it is against the
    /// stroke's most opaque row. Rows are averaged over many columns of the stroke's middle half
    /// before the most opaque one is taken: a pencil's grain makes any one pixel vary widely, and
    /// counting against the single most opaque pixel, as until 2026-11-04, made the same pencil
    /// 2.4 measure 0.57 points at zoom 1 and 0.71 at 1.5, 2 and 3 on an iPad, its stored sizes all
    /// 1.2. A stroke drawn lighter or darker all over keeps its width in this measure.
    static func renderedWidth(of stroke: PKStroke, pixelsPerPoint: CGFloat = 8) -> CGFloat? {
        let region = stroke.renderBounds.insetBy(dx: -4, dy: -4)
        guard let picture = PKDrawing(strokes: [stroke]).image(from: region, scale: pixelsPerPoint).cgImage,
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        var bytes = [UInt8](repeating: 0, count: picture.width * picture.height * 4)
        guard let context = CGContext(data: &bytes, width: picture.width, height: picture.height, bitsPerComponent: 8, bytesPerRow: picture.width * 4,
                                      space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.draw(picture, in: CGRect(x: 0, y: 0, width: picture.width, height: picture.height))
        let columns = Array(stride(from: picture.width / 4, to: picture.width * 3 / 4, by: max(picture.width / 80, 1)))
        guard !columns.isEmpty else { return 0 }
        let rowOpacities = (0..<picture.height).map { row in
            columns.reduce(0.0) { total, column in total + Double(bytes[(row * picture.width + column) * 4 + 3]) } / Double(columns.count)
        }
        guard let mostOpaqueRow = rowOpacities.max(), mostOpaqueRow > 0 else { return 0 }
        return CGFloat(rowOpacities.reduce(0, +) / mostOpaqueRow) / pixelsPerPoint
    }
}

private final class StrokeTouch: UITouch {
    private let touchWindow: UIWindow
    private let touchView: UIView
    /// PencilKit reads a touch's type off the main thread when a stroke ends.
    private let touchTypeRawValue: Int
    private var currentLocation: CGPoint
    private var earlierLocation: CGPoint
    private var currentPhase = UITouch.Phase.began
    private var currentTime = ProcessInfo.processInfo.systemUptime

    init(window: UIWindow, view: UIView, location: CGPoint, touchType: UITouch.TouchType) {
        touchWindow = window
        touchView = view
        touchTypeRawValue = touchType.rawValue
        currentLocation = location
        earlierLocation = location
        super.init()
    }

    func move(to point: CGPoint, phase: UITouch.Phase) {
        earlierLocation = currentLocation
        currentLocation = point
        currentPhase = phase
        currentTime = ProcessInfo.processInfo.systemUptime
    }

    nonisolated override var type: UITouch.TouchType { UITouch.TouchType(rawValue: touchTypeRawValue) ?? .direct }
    override var phase: UITouch.Phase { currentPhase }
    override var timestamp: TimeInterval { currentTime }
    override var window: UIWindow? { touchWindow }
    override var view: UIView? { touchView }
    override var tapCount: Int { 1 }
    override var force: CGFloat { 1 }
    override var maximumPossibleForce: CGFloat { 4.17 }
    override var altitudeAngle: CGFloat { .pi / 3 }
    override func location(in view: UIView?) -> CGPoint { touchWindow.convert(currentLocation, to: view) }
    override func preciseLocation(in view: UIView?) -> CGPoint { location(in: view) }
    override func previousLocation(in view: UIView?) -> CGPoint { touchWindow.convert(earlierLocation, to: view) }
    override func precisePreviousLocation(in view: UIView?) -> CGPoint { previousLocation(in: view) }
}

private final class StrokeEvent: UIEvent {
    override func coalescedTouches(for touch: UITouch) -> [UITouch]? { [touch] }
    override func predictedTouches(for touch: UITouch) -> [UITouch]? { [] }
    override var type: UIEvent.EventType { .touches }
}
#endif
