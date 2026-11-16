/**
 * File: EvenStrokePicturer.swift
 * ------------------------------
 * Layer: UI
 * Description: Pictures the even highlighter's stroke being drawn as PencilKit draws it, away from the main thread, for
 *              the canvas to show until the stroke kept at the lift takes its place.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 16/11/2026
 */
#if canImport(UIKit)
import UIKit
import PencilKit

/// Pictures the even highlighter's stroke being drawn (`EvenHighlighter.evenStroke(through:width:ink:)`) as PencilKit
/// draws it, so the stroke shown while drawing is the one kept at the lift (HUNT-356). Drawn on the main thread, a move of
/// a stroke across a page took 7 ms on the simulator, most of a frame at 120 Hz. One picture is made at a time; the moves
/// that come meanwhile are pictured together once it is done, so the stroke shown follows the Pencil a frame behind at most.
@MainActor
final class EvenStrokePicturer {
    /// The stroke being drawn, to be pictured at the canvas's zoom on the screen, in the canvas's light or dark ink colors.
    struct Request: Sendable {
        let stroke: PKStroke
        let zoomScale: CGFloat
        let displayScale: CGFloat
        let interfaceStyle: UIUserInterfaceStyle
    }

    /// The stroke as PencilKit draws it, and where it goes on the canvas, in the canvas's points.
    struct Picture {
        let image: CGImage
        let frameOnCanvas: CGRect
    }

    private let show: (Picture) -> Void
    private var isPicturing = false
    private var nextRequest: Request?
    /// Counts the strokes let go of, so a picture made for one is dropped.
    private var cancelCount = 0

    init(show: @escaping (Picture) -> Void) {
        self.show = show
    }

    func picture(_ request: Request) {
        guard !isPicturing else {
            nextRequest = request
            return
        }
        isPicturing = true
        let cancelCountWhenAsked = cancelCount
        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
            let picture = EvenStrokePicturer.picture(of: request)
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isPicturing = false
                if let picture, cancelCountWhenAsked == self.cancelCount { self.show(picture) }
                if let nextRequest = self.nextRequest {
                    self.nextRequest = nil
                    self.picture(nextRequest)
                }
            }
        }
    }

    /// The stroke shown goes: a picture of it still being made is not shown.
    func cancel() {
        cancelCount += 1
        nextRequest = nil
    }

    /// The most pixels a picture takes: a long stroke across a page zoomed in is drawn a little softer
    /// rather than taking tens of megabytes at every move.
    nonisolated private static let largestPixelCount: CGFloat = 4_000_000

    nonisolated private static func picture(of request: Request) -> Picture? {
        let region = request.stroke.renderBounds.insetBy(dx: -1, dy: -1).integral
        let scale = request.zoomScale * request.displayScale
        guard !region.isEmpty, region.width.isFinite, region.height.isFinite, scale > 0 else { return nil }
        let pixelScale = min(scale, (largestPixelCount / (region.width * region.height)).squareRoot())
        var image: CGImage?
        UITraitCollection(userInterfaceStyle: request.interfaceStyle).performAsCurrent {
            image = PKDrawing(strokes: [request.stroke]).image(from: region, scale: pixelScale).cgImage
        }
        let zoomScale = request.zoomScale
        return image.map { image in
            Picture(image: image, frameOnCanvas: CGRect(x: region.minX * zoomScale, y: region.minY * zoomScale,
                                                        width: region.width * zoomScale, height: region.height * zoomScale))
        }
    }
}
#endif
