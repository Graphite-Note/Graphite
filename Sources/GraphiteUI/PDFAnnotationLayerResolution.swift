/**
 * File: PDFAnnotationLayerResolution.swift
 * ----------------------------------------
 * Layer: UI
 * Description: Keeps the layers PDFKit draws a Mac PDF's annotations into (pictures, ink, text
 *              boxes) at the screen's resolution, within a memory bound.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 04/11/2026
 */
#if os(macOS)
import AppKit
import PDFKit
import SwiftUI

/// Keeps the layers PDFKit draws a Mac PDF's annotations into at the screen's resolution.
///
/// PDFKit on macOS draws the page itself in tiles at the screen's pixels per page point
/// (zoom times the window's backing scale), but each annotation (a placed picture, every ink
/// stroke, a text box, a highlight) into a layer of its own, a `PDFPageLayerAnnotationEffect`,
/// which it leaves at a `contentsScale` of 1: one pixel per page point at any zoom. At fit
/// width on a Retina screen that is a third of the screen's pixels, so pictures and ink were
/// soft while the page's own text was sharp, and Preview showed the same file sharp
/// (HUNT-314, measured in `MacPDFAnnotationSharpnessTests`). The file is not involved: its
/// pictures keep their pixels and its ink is vector outlines.
///
/// This sets those layers' `contentsScale` to the screen's pixels per point, so PDFKit draws
/// each annotation again from the file at that resolution. It looks only at the pages PDFKit
/// has on screen and only for about a second after something that changes them: the zoom, a
/// scroll, the pages shown, the window's screen, the end of a pinch or an edit of the
/// document; PDFKit makes the layers of a page a few frames after such a change. Nothing is
/// done during a pinch; the layers are drawn again when it ends, as PDFKit draws its tiles
/// again. All the layers together hold at most `maximumPixelCount` pixels: when zoomed in so
/// far that they would hold more, every one is drawn at the same lower resolution, never below
/// PDFKit's own one pixel per point (invariant P-17).
///
/// The layers are found by PDFKit's class name, which is not public: should PDFKit rename the
/// class, annotations are drawn as PDFKit draws them, and the tests above fail.
@MainActor
final class PDFAnnotationLayerResolution: NSObject {
    static let annotationLayerClassName = "PDFPageLayerAnnotationEffect"
    /// Bound on the pixels of all the annotation layers of the pages on screen: 96 MB at four
    /// bytes a pixel. Fit width on a Retina screen takes about 5 megapixels for a page whose
    /// annotations cover all of it.
    static let maximumPixelCount = 24 * 1_048_576
    /// The longest side of a layer Core Animation keeps as one surface.
    static let maximumLayerSidePixels: CGFloat = 16_384
    /// A change of resolution smaller than this fraction is not worth drawing an annotation again.
    private static let resolutionTolerance: CGFloat = 0.02
    /// How often the layers are looked at after a change, and how many times: for about a
    /// second, since PDFKit makes the layers of an edited or newly shown page a few frames
    /// after the change.
    private static let lookInterval: TimeInterval = 1.0 / 30
    private static let looksAfterAChange = 30

    private static let annotationLayerClass: AnyClass? = NSClassFromString(annotationLayerClassName)

    private weak var view: PDFView?
    /// The edits of the document shown (`PDFSession.changeVersion`), read under observation.
    private let contentChangeCount: () -> Int
    private var lookTimer: Timer?
    private var looksLeft = 0
    private var isMagnifying = false
    private var isStarted = false

    init(view: PDFView, contentChangeCount: @escaping () -> Int) {
        self.view = view
        self.contentChangeCount = contentChangeCount
        super.init()
    }

    /// Starts keeping the layers sharp while the view is in a window.
    func start() {
        guard !isStarted, Self.annotationLayerClass != nil, let view, let window = view.window else { return }
        isStarted = true
        let center = NotificationCenter.default
        for name in [Notification.Name.PDFViewScaleChanged, .PDFViewVisiblePagesChanged, .PDFViewPageChanged, .PDFViewDocumentChanged] {
            center.addObserver(self, selector: #selector(somethingShownChanged), name: name, object: view)
        }
        center.addObserver(self, selector: #selector(somethingShownChanged), name: NSWindow.didChangeBackingPropertiesNotification, object: window)
        if let scrollView = view.subviews.lazy.compactMap({ subview in subview as? NSScrollView }).first {
            center.addObserver(self, selector: #selector(magnificationBegan), name: NSScrollView.willStartLiveMagnifyNotification, object: scrollView)
            center.addObserver(self, selector: #selector(magnificationEnded), name: NSScrollView.didEndLiveMagnifyNotification, object: scrollView)
            scrollView.contentView.postsBoundsChangedNotifications = true
            center.addObserver(self, selector: #selector(somethingShownChanged), name: NSView.boundsDidChangeNotification, object: scrollView.contentView)
        }
        observeContentChanges()
        somethingShownChanged()
    }

    func stop() {
        guard isStarted else { return }
        isStarted = false
        NotificationCenter.default.removeObserver(self)
        lookTimer?.invalidate()
        lookTimer = nil
        looksLeft = 0
        isMagnifying = false
    }

    /// Looks at the layers now and for about a second.
    @objc private func somethingShownChanged() {
        guard isStarted else { return }
        looksLeft = Self.looksAfterAChange
        if lookTimer == nil {
            // A timer rather than a display link, which a window that is not on a screen never runs.
            let timer = Timer(timeInterval: Self.lookInterval, target: self, selector: #selector(lookAgain), userInfo: nil, repeats: true)
            timer.tolerance = Self.lookInterval / 2
            RunLoop.main.add(timer, forMode: .common)
            lookTimer = timer
        }
        update()
    }

    @objc private func magnificationBegan() { isMagnifying = true }

    @objc private func magnificationEnded() {
        isMagnifying = false
        somethingShownChanged()
    }

    @objc private func lookAgain() {
        update()
        looksLeft -= 1
        if looksLeft <= 0 {
            lookTimer?.invalidate()
            lookTimer = nil
        }
    }

    /// An edit adds or replaces annotations, whose new layers PDFKit makes at one pixel a point.
    private func observeContentChanges() {
        withObservationTracking {
            _ = contentChangeCount()
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.isStarted else { return }
                self.somethingShownChanged()
                self.observeContentChanges()
            }
        }
    }

    /// Sets the resolution of the annotation layers of the pages on screen to the screen's
    /// pixels per point, within the bound; a layer already there is left alone.
    func update() {
        guard !isMagnifying, let view, let window = view.window, let documentView = view.documentView,
              let annotationLayerClass = Self.annotationLayerClass else { return }
        let screenPixelsPerPoint = view.scaleFactor * window.backingScaleFactor
        guard screenPixelsPerPoint.isFinite, screenPixelsPerPoint > 0 else { return }
        let annotationLayers = documentView.subviews.flatMap { pageView in
            pageView.layer.flatMap { pageLayer in Self.annotationLayerContainer(under: pageLayer, annotationLayerClass: annotationLayerClass) }
                .map { container in (container.sublayers ?? []).filter { layer in type(of: layer) == annotationLayerClass } } ?? []
        }
        let pointCount = annotationLayers.reduce(0.0) { total, layer in total + layer.bounds.width * layer.bounds.height }
        let pixelsPerPointWithinBound = pointCount > 0 ? (CGFloat(Self.maximumPixelCount) / pointCount).squareRoot() : screenPixelsPerPoint
        let boundedPixelsPerPoint = min(screenPixelsPerPoint, pixelsPerPointWithinBound)
        let layersToDraw = annotationLayers.compactMap { layer -> (CALayer, CGFloat)? in
            let longestSide = max(layer.bounds.width, layer.bounds.height)
            let sideBound = longestSide > 0 ? Self.maximumLayerSidePixels / longestSide : boundedPixelsPerPoint
            let layerPixelsPerPoint = max(1, min(boundedPixelsPerPoint, sideBound))
            let isOffTarget = abs(layer.contentsScale - layerPixelsPerPoint) > layerPixelsPerPoint * Self.resolutionTolerance
            return isOffTarget ? (layer, layerPixelsPerPoint) : nil
        }
        guard !layersToDraw.isEmpty else { return }
        CATransaction.begin()
        // No fade from the old pixels to the new ones.
        CATransaction.setDisableActions(true)
        for (layer, layerPixelsPerPoint) in layersToDraw {
            layer.contentsScale = layerPixelsPerPoint
            layer.setNeedsDisplay()
        }
        CATransaction.commit()
    }

    /// The layer under a page's layer that holds its annotation layers, found by looking at
    /// each layer's sublayers until one is an annotation layer; tiles have none.
    private static func annotationLayerContainer(under layer: CALayer, annotationLayerClass: AnyClass) -> CALayer? {
        guard let sublayers = layer.sublayers else { return nil }
        if sublayers.contains(where: { sublayer in type(of: sublayer) == annotationLayerClass }) { return layer }
        for sublayer in sublayers where type(of: sublayer) != annotationLayerClass {
            if let container = annotationLayerContainer(under: sublayer, annotationLayerClass: annotationLayerClass) { return container }
        }
        return nil
    }
}
#endif
