/**
 * File: PDFPageOverlayView.swift
 * ------------------------------
 * Layer: UI
 * Description: What PDFKit places over a PDF page on the iPad: the page's Pencil canvas, drawn at the zoom
 *              over the whole page or the part of it on screen, the writing guides, the pictures of the page's combined
 *              ink groups and the objects over the ink.
 *
 * Authors: Bahey Shalash
 * Version: 0.4
 * Date: 19/11/2026
 */
#if canImport(UIKit)
import UIKit
import GraphiteCore

/// What PDFKit places over a page: the page's canvas, and the writing guides under it.
///
/// PDFKit zooms a page by scaling the view that draws it, overlays included, so a canvas
/// the size of the page drew its ink at the screen's resolution and PDFKit magnified it:
/// zoomed in to write on a slide, the ink was soft and showed the edges of PencilKit's
/// tiles. PencilKit draws its tiles at its own zoom, so the canvas is made
/// `renderingScale` times the part of the page it covers, zoomed by as much, and scaled back
/// down to the page: its ink is drawn at the resolution it is seen at, and its drawing stays
/// in the page's points. It covers the whole page while that fits its bound of pixels, and
/// otherwise the part around what is on screen (`PDFCanvasShownRegion`), scrolled within its
/// drawing to that part, so zoomed far in it is as sharp as at any other zoom (HUNT-320).
/// The writing guides stay at the page's size; they are only a guide.
final class PDFPageOverlayView: UIView {
    let canvas: PDFPageCanvasView
    private let guideView = DrawingPaperView()
    /// The pictures of the page's combined ink groups (`PDFCombinedInkPictures`), under the canvas: a layer's contents,
    /// which Core Animation shows without the main thread drawing anything.
    private let combinedInkView = PDFCombinedInkView()
    /// The page's objects over the ink: text boxes, pictures and shapes (`PDFPageObjectsOverInkView`).
    let objectsOverInkView = PDFPageObjectsOverInkView(frame: .zero)
    /// How many times the page's size the canvas draws at (`renderingScale(forZoom:)`).
    private(set) var renderingScale: CGFloat = 1
    /// The part of the page the canvas covers, in the page's points; null before the first layout.
    private(set) var shownRegion: CGRect = .null
    /// The most pixels the canvas takes (`PDFCanvasShownRegion.maximumCanvasPixelCount`, less
    /// after a memory warning). Only the pages on screen are drawn at the zoom
    /// (`PDFAnnotationCoordinator.updateRenderingScale`).
    var canvasPixelBudget = PDFCanvasShownRegion.maximumCanvasPixelCount {
        didSet { if canvasPixelBudget != oldValue { setNeedsLayout() } }
    }
    /// The view whose bounds are what is on screen: the PDF view; the window without it.
    weak var visibleAreaView: UIView?
    /// Whether the canvas's content size was set for a part of the page, to be set back.
    private var hasContentSizeForAPart = false

    /// A change of zoom smaller than this, as a fraction, is not worth drawing the page again.
    static let smallestScaleChange: CGFloat = 0.01

    /// The scale to draw ink at for a PDF view's zoom: the zoom itself, so a pixel of the ink's
    /// tiles is a pixel of the screen and settled ink is as sharp as a line can be, at any zoom;
    /// the memory a page may take bounds the part drawn instead (`PDFCanvasShownRegion`). It
    /// does not depend on the tool in hand: a tool's width is its width in the drawing at any
    /// zoom of the canvas (`Docs/solid/invariants.md`, INK-22).
    static func renderingScale(forZoom zoom: CGFloat) -> CGFloat {
        PDFCanvasShownRegion.renderingScale(forZoom: zoom)
    }

    init(canvas: PDFPageCanvasView) {
        self.canvas = canvas
        super.init(frame: canvas.frame)
        backgroundColor = .clear
        isOpaque = false
        addSubview(guideView)
        addSubview(combinedInkView)
        addSubview(canvas)
        addSubview(objectsOverInkView)
        canvas.placeIn(self)
    }

    required init?(coder: NSCoder) { nil }

    /// Shows the pictures of the page's combined ink groups as the page is shown, over each other, or hides them while
    /// the canvas shows the page's ink.
    func showCombinedInk(_ pictures: [CGImage], isShown: Bool) {
        combinedInkView.show(pictures, isShown: isShown)
    }

    /// The pictures shown, which a test asks.
    var shownCombinedInk: [CGImage] { combinedInkView.isHidden ? [] : combinedInkView.pictures }

    /// Writing guides under the ink, which the page's file never gets.
    var writingGuides: DrawingPaper {
        get { guideView.paper }
        set { guideView.paper = newValue }
    }

    /// Whether the guides show: only while writing, like the canvas over them.
    var showsWritingGuides = true {
        didSet { guideView.alpha = showsWritingGuides ? 1 : 0 }
    }

    /// The scale the canvas is to draw at.
    func setRenderingScale(_ scale: CGFloat) {
        guard abs(scale - renderingScale) / renderingScale >= Self.smallestScaleChange else { return }
        renderingScale = scale
        setNeedsLayout()
    }

    /// Moves the part of the page the canvas covers with what is on screen, once that nears
    /// its edge; nothing changes while the canvas covers the whole page. Returns whether it moved.
    @discardableResult
    func followVisibleArea() -> Bool {
        guard wantedRegion() != shownRegion else { return false }
        setNeedsLayout()
        layoutIfNeeded()
        return true
    }

    private func wantedRegion() -> CGRect {
        let screenScale = window?.screen.scale ?? traitCollection.displayScale
        return PDFCanvasShownRegion.region(pageSize: bounds.size, visibleRegion: visibleRegion, currentRegion: shownRegion.isNull ? nil : shownRegion,
                                           scale: renderingScale, screenScale: screenScale, pixelBudget: canvasPixelBudget)
    }

    /// What is on screen, in the page's points; nil outside a window.
    private var visibleRegion: CGRect? {
        guard let window else { return nil }
        let areaView = visibleAreaView.flatMap { view in view.window === window ? view : nil } ?? window
        return convert(areaView.bounds, from: areaView)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // The guides and the objects over the ink start at the page's top-left corner, in its points.
        guideView.frame = bounds
        guideView.drawingRegion = bounds
        combinedInkView.frame = bounds
        objectsOverInkView.frame = bounds
        // A box with emoji, a picture or a shape is drawn at the zoom's resolution once the zoom settles.
        objectsOverInkView.screenPixelsPerPagePoint = renderingScale * (window?.screen.scale ?? traitCollection.displayScale)
        let scale = renderingScale
        let region = wantedRegion()
        shownRegion = region
        let canvasBounds = CGRect(x: 0, y: 0, width: region.width * scale, height: region.height * scale)
        if canvas.bounds.size != canvasBounds.size || canvas.zoomScale != scale {
            canvas.transform = .identity
            canvas.bounds = canvasBounds
            canvas.minimumZoomScale = min(scale, canvas.zoomScale)
            canvas.maximumZoomScale = max(scale, canvas.zoomScale)
            canvas.zoomScale = scale
            canvas.minimumZoomScale = scale
            canvas.maximumZoomScale = scale
            canvas.contentOffset = .zero
            canvas.transform = CGAffineTransform(scaleX: 1 / scale, y: 1 / scale)
        }
        // A part of the page is the canvas scrolled to it within the page's drawing, as a
        // scrolling canvas is: the drawing keeps the page's points.
        let isWholePage = region.size == bounds.size
        if !isWholePage {
            let pageContentSize = CGSize(width: bounds.width * scale, height: bounds.height * scale)
            if canvas.contentSize != pageContentSize { canvas.contentSize = pageContentSize }
            hasContentSizeForAPart = true
        } else if hasContentSizeForAPart {
            canvas.contentSize = canvasBounds.size
            hasContentSizeForAPart = false
        }
        let contentOffset = CGPoint(x: region.minX * scale, y: region.minY * scale)
        if canvas.contentOffset != contentOffset { canvas.contentOffset = contentOffset }
        canvas.center = CGPoint(x: region.midX, y: region.midY)
    }

    /// Touches outside the canvas are the page's: PDFKit's scrolling and selection.
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let touchedView = super.hitTest(point, with: event)
        return touchedView === self ? nil : touchedView
    }
}
/// The pictures of a page's combined ink groups, each a layer filling the page, as the page is shown.
private final class PDFCombinedInkView: UIView {
    private(set) var pictures: [CGImage] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isHidden = true
    }

    required init?(coder: NSCoder) { nil }

    func show(_ pictures: [CGImage], isShown: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if pictures.map(ObjectIdentifier.init) != self.pictures.map(ObjectIdentifier.init) {
            self.pictures = pictures
            layer.sublayers?.forEach { sublayer in sublayer.removeFromSuperlayer() }
            for picture in pictures {
                let pictureLayer = CALayer()
                pictureLayer.contents = picture
                // The picture is the whole page as shown; magnified while a zoom settles, as PDFKit's tiles are.
                pictureLayer.contentsGravity = .resize
                pictureLayer.frame = bounds
                layer.addSublayer(pictureLayer)
            }
        }
        isHidden = !isShown || pictures.isEmpty
        CATransaction.commit()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.sublayers?.forEach { sublayer in sublayer.frame = bounds }
        CATransaction.commit()
    }
}
#endif
