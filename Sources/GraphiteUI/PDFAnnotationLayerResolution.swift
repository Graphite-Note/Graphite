/**
 * File: PDFAnnotationLayerResolution.swift
 * ----------------------------------------
 * Layer: UI
 * Description: Keeps the layers PDFKit draws a PDF's annotations into (pictures, ink, text
 *              boxes) at the screen's resolution, within a memory bound, on the Mac and the iPad.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 04/11/2026
 */
import PDFKit
import SwiftUI
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// Keeps the layers PDFKit draws a PDF's annotations into at the screen's resolution.
///
/// PDFKit draws the page itself in tiles at the screen's pixels per page point (zoom times the
/// screen's scale), but each annotation (a placed picture, every ink stroke, a text box, a
/// highlight) into a layer of its own, a `PDFPageLayerAnnotationEffect`, which it leaves at a
/// `contentsScale` of 1: one pixel per page point at any zoom, and magnified by a transform
/// while zooming. At fit width on a Retina screen that is a third of the screen's pixels, so
/// pictures and ink were soft while the page's own text was sharp, and Preview showed the
/// same file sharp (HUNT-314 on the Mac, measured in `MacPDFAnnotationSharpnessTests`;
/// HUNT-320 on the iPad, whose PDFKit has the same class, measured in
/// `PDFPageSharpnessHostedTests`). The file is not involved: its pictures keep their pixels
/// and its ink is vector outlines.
///
/// This sets those layers' `contentsScale` to the screen's pixels per point of each layer, so
/// PDFKit draws each annotation again from the file at that resolution. It looks only at the
/// pages PDFKit has made views for and only for about a second after something that changes
/// them: the zoom, a scroll, the pages shown, the window's screen, the end of a pinch or an
/// edit of the document; PDFKit makes the layers of a page a few frames after such a change.
/// Nothing is done during a pinch; the layers are drawn again when it ends, as PDFKit draws
/// its tiles again. All the layers together hold at most `maximumPixelCount` pixels: when
/// zoomed in so far that they would hold more, every one is drawn at the same fraction of its
/// screen's resolution, never below PDFKit's own one pixel per point (invariant P-17).
///
/// The layers are found by PDFKit's class name, which is not public: should PDFKit rename the
/// class, annotations are drawn as PDFKit draws them, and the tests above fail.
@MainActor
final class PDFAnnotationLayerResolution: NSObject {
    static let annotationLayerClassName = "PDFPageLayerAnnotationEffect"
    /// Bound on the pixels of all the annotation layers of the pages PDFKit has views for:
    /// 96 MB at four bytes a pixel. Fit width on a Retina screen takes about 5 megapixels for
    /// a page whose annotations cover all of it.
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
    private var isStarted = false
    #if canImport(UIKit)
    private var scrollOffsetObservation: NSKeyValueObservation?
    private weak var observedPinchRecognizer: UIGestureRecognizer?
    #else
    private var isMagnifying = false
    #endif

    init(view: PDFView, contentChangeCount: @escaping () -> Int) {
        self.view = view
        self.contentChangeCount = contentChangeCount
        super.init()
    }

    /// Starts keeping the layers sharp while the view is in a window.
    func start() {
        guard !isStarted, Self.annotationLayerClass != nil, let view, view.window != nil else { return }
        isStarted = true
        let center = NotificationCenter.default
        for name in [Notification.Name.PDFViewScaleChanged, .PDFViewVisiblePagesChanged, .PDFViewPageChanged, .PDFViewDocumentChanged] {
            center.addObserver(self, selector: #selector(somethingShownChanged), name: name, object: view)
        }
        #if canImport(UIKit)
        if let scrollView = pagesScrollView {
            // Key-value observation of the offset reports on the thread that changed it, the
            // main thread for a scroll view; the look itself is made on the main actor.
            scrollOffsetObservation = scrollView.observe(\.contentOffset) { [weak self] _, _ in
                Task { @MainActor [weak self] in self?.somethingShownChanged() }
            }
            if let pinchRecognizer = scrollView.pinchGestureRecognizer {
                pinchRecognizer.addTarget(self, action: #selector(pinchChanged(_:)))
                observedPinchRecognizer = pinchRecognizer
            }
        }
        #else
        center.addObserver(self, selector: #selector(somethingShownChanged), name: NSWindow.didChangeBackingPropertiesNotification, object: view.window)
        if let scrollView = view.subviews.lazy.compactMap({ subview in subview as? NSScrollView }).first {
            center.addObserver(self, selector: #selector(magnificationBegan), name: NSScrollView.willStartLiveMagnifyNotification, object: scrollView)
            center.addObserver(self, selector: #selector(magnificationEnded), name: NSScrollView.didEndLiveMagnifyNotification, object: scrollView)
            scrollView.contentView.postsBoundsChangedNotifications = true
            center.addObserver(self, selector: #selector(somethingShownChanged), name: NSView.boundsDidChangeNotification, object: scrollView.contentView)
        }
        #endif
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
        #if canImport(UIKit)
        scrollOffsetObservation = nil
        observedPinchRecognizer?.removeTarget(self, action: #selector(pinchChanged(_:)))
        observedPinchRecognizer = nil
        #else
        isMagnifying = false
        #endif
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

    #if canImport(UIKit)
    /// A pinch's end is looked at, as its steps are not: PDFKit draws its tiles again then.
    @objc private func pinchChanged(_ recognizer: UIGestureRecognizer) {
        if recognizer.state == .ended || recognizer.state == .cancelled || recognizer.state == .failed { somethingShownChanged() }
    }

    /// The scroll view PDFKit scrolls and zooms the pages in: the nearest around its document view.
    private var pagesScrollView: UIScrollView? {
        var ancestor = view?.documentView?.superview
        while let candidate = ancestor {
            if let scrollView = candidate as? UIScrollView { return scrollView }
            ancestor = candidate.superview
        }
        return nil
    }

    /// Whether a pinch is under way or its zoom bounces back: PDFKit magnifies its layers then.
    private var isMagnifying: Bool {
        guard let scrollView = pagesScrollView else { return false }
        let pinchState = scrollView.pinchGestureRecognizer?.state
        return scrollView.isZooming || scrollView.isZoomBouncing || pinchState == .began || pinchState == .changed
    }
    #else
    @objc private func magnificationBegan() { isMagnifying = true }

    @objc private func magnificationEnded() {
        isMagnifying = false
        somethingShownChanged()
    }
    #endif

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

    /// Sets the resolution of the annotation layers of the pages shown to the screen's pixels
    /// per point, within the bound; a layer already there is left alone.
    func update() {
        guard !isMagnifying, let view, let window = view.window, let documentLayer = view.documentView?.layer,
              let annotationLayerClass = Self.annotationLayerClass else { return }
        let annotationLayers = Self.annotationLayers(under: documentLayer, annotationLayerClass: annotationLayerClass)
        guard !annotationLayers.isEmpty else { return }
        #if canImport(UIKit)
        let screenScale = view.traitCollection.displayScale
        let wantedScales = annotationLayers.map { layer in Self.screenPixelsPerPoint(of: layer, in: window.layer, screenScale: screenScale) }
        #else
        let screenPixelsPerPoint = view.scaleFactor * window.backingScaleFactor
        let wantedScales = annotationLayers.map { _ in screenPixelsPerPoint }
        #endif
        let targets = Self.boundedScales(forLayerSizes: annotationLayers.map(\.bounds.size), wantedScales: wantedScales)
        let layersToDraw = zip(annotationLayers, targets).filter { layer, target in
            abs(layer.contentsScale - target) > target * Self.resolutionTolerance
        }
        guard !layersToDraw.isEmpty else { return }
        CATransaction.begin()
        // No fade from the old pixels to the new ones.
        CATransaction.setDisableActions(true)
        for (layer, target) in layersToDraw {
            layer.contentsScale = target
            layer.setNeedsDisplay()
        }
        CATransaction.commit()
    }

    /// The pixels per point each layer is drawn at: the screen's for it, all of them reduced
    /// by the same fraction when together they would hold more than `maximumPixelCount`, none
    /// longer than `maximumLayerSidePixels` on a side and none below one pixel per point.
    /// Wanted scales that are not finite and positive leave a layer at one pixel per point.
    static func boundedScales(forLayerSizes sizes: [CGSize], wantedScales: [CGFloat]) -> [CGFloat] {
        let usableScales = wantedScales.map { scale in scale.isFinite && scale > 0 ? scale : 1 }
        let wantedPixelCount = zip(sizes, usableScales).reduce(0.0) { total, entry in total + entry.0.width * entry.0.height * entry.1 * entry.1 }
        let reduction = wantedPixelCount > CGFloat(maximumPixelCount) ? (CGFloat(maximumPixelCount) / wantedPixelCount).squareRoot() : 1
        return zip(sizes, usableScales).map { size, scale in
            let longestSide = max(size.width, size.height)
            let sideBound = longestSide > 0 ? maximumLayerSidePixels / longestSide : scale
            return max(1, min(scale * reduction, sideBound))
        }
    }

    #if canImport(UIKit)
    /// How many of the screen's pixels one point of the layer covers, through every transform
    /// above it: the zoom of PDFKit's scroll view and of the page's view, whatever space
    /// PDFKit lays its pages out in.
    private static func screenPixelsPerPoint(of layer: CALayer, in windowLayer: CALayer, screenScale: CGFloat) -> CGFloat {
        let bounds = layer.bounds
        guard bounds.width > 0, bounds.height > 0 else { return 1 }
        let shown = layer.convert(bounds, to: windowLayer)
        return (shown.width * shown.height / (bounds.width * bounds.height)).squareRoot() * screenScale
    }
    #endif

    /// Every annotation layer under the document's layer. The layers of Graphite's own views
    /// over a page (its Pencil canvas, with PencilKit's many tiles) are not looked into, nor
    /// an annotation layer's own sublayers.
    static func annotationLayers(under layer: CALayer, annotationLayerClass: AnyClass) -> [CALayer] {
        var found: [CALayer] = []
        func look(under layer: CALayer) {
            for sublayer in layer.sublayers ?? [] {
                if type(of: sublayer) == annotationLayerClass {
                    found.append(sublayer)
                } else if !isGraphitesOwnOverlay(sublayer) {
                    look(under: sublayer)
                }
            }
        }
        look(under: layer)
        return found
    }

    private static func isGraphitesOwnOverlay(_ layer: CALayer) -> Bool {
        #if canImport(UIKit)
        return layer.delegate is PDFPageOverlayView
        #else
        return false
        #endif
    }
}
