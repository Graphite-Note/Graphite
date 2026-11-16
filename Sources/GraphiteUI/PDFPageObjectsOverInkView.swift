/**
 * File: PDFPageObjectsOverInkView.swift
 * -------------------------------------
 * Layer: UI
 * Description: The objects of one PDF page that are over its Pencil ink in the file (`PDFPageStacking`), drawn
 *              over the page's Pencil canvas in their order: Graphite's text boxes and pictures, and shapes.
 *
 * Authors: Bahey Shalash
 * Version: 0.4
 * Date: 16/11/2026
 */
#if canImport(UIKit)
import UIKit
import PDFKit
import GraphiteCore
import GraphiteApple

/// One object drawn over the ink.
enum PDFOverInkObject: Equatable {
    case textBox(PDFTextBox)
    /// A picture Graphite placed, or a shape, drawn from its annotation.
    case annotation(PDFAnnotation, name: String?, bounds: CGRect)

    static func == (leftObject: PDFOverInkObject, rightObject: PDFOverInkObject) -> Bool {
        switch (leftObject, rightObject) {
        case (.textBox(let leftBox), .textBox(let rightBox)): leftBox == rightBox
        case (.annotation(let leftAnnotation, _, let leftBounds), .annotation(let rightAnnotation, _, let rightBounds)):
            leftAnnotation === rightAnnotation && leftBounds == rightBounds
        default: false
        }
    }
}

/// The objects of one PDF page that are over its ink in the file, drawn over the page's Pencil
/// canvas in the file's order, so the page on screen is stacked as every reader stacks it. It
/// sits in the page's overlay (`PDFPageOverlayView`), in the page's points with its top-left
/// corner at the origin, and takes no touches. What is under the ink, PDFKit draws under the
/// canvas, in the same order.
///
/// A text box's text is drawn as its outlines in shape layers (`PDFTextBoxLayout.textOutlines`),
/// which Core Animation draws at the resolution they are shown at: the text is as sharp as the
/// page at any zoom, without a bitmap the size of the zoomed page. A picture or a shape is drawn
/// from its annotation at the screen's pixels per point, again when the zoom settles. While a
/// page shows this view, the annotations it draws are hidden, so nothing is drawn twice.
/// Another application's box is left to PDFKit, which draws the appearance its application
/// wrote, under the ink.
final class PDFPageObjectsOverInkView: UIView {
    /// The box being typed in, which the text editor shows instead.
    private(set) var hiddenBoxName: String?
    /// The boxes and pictures the lasso's frame carries while it is dragged, which it shows instead.
    private var carriedObjectNames: Set<String> = []
    private var shownObjects: [PDFOverInkObject] = []
    /// The annotations this view draws, so the lasso does not show them through PDFKit too.
    private var drawnAnnotations: Set<ObjectIdentifier> = []
    private var cropBox: CGRect = .zero
    /// The objects in the page's points, scaled to the view's size in `layoutSubviews`: PDFKit
    /// may make a page's overlay another size than the page.
    private let pageLayer = CALayer()
    /// The screen's pixels per page point the page is seen at (the zoom times the screen's
    /// scale), set by the page's overlay when the zoom settles; 0 until then, when the
    /// screen's own scale is taken. A box with emoji, a picture and a shape are drawn at that resolution.
    var screenPixelsPerPagePoint: CGFloat = 0 {
        didSet {
            guard screenPixelsPerPagePoint != oldValue else { return }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            for sublayer in pageLayer.sublayers ?? [] {
                (sublayer as? PDFTextBoxPictureLayer)?.draw(atPixelsPerPoint: pictureResolution)
                (sublayer as? PDFAnnotationOverInkLayer)?.draw(atPixelsPerPoint: pictureResolution)
            }
            CATransaction.commit()
        }
    }

    /// The pixels per page point a box's picture is drawn at.
    private var pictureResolution: CGFloat { screenPixelsPerPagePoint > 0 ? screenPixelsPerPagePoint : traitCollection.displayScale }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
        isOpaque = false
        // Pages are white paper; the boxes keep their colors in dark appearance.
        overrideUserInterfaceStyle = .light
        pageLayer.anchorPoint = .zero
        layer.addSublayer(pageLayer)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard cropBox.width > 0, cropBox.height > 0 else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        pageLayer.bounds = CGRect(origin: .zero, size: cropBox.size)
        pageLayer.position = .zero
        pageLayer.setAffineTransform(CGAffineTransform(scaleX: bounds.width / cropBox.width, y: bounds.height / cropBox.height))
        CATransaction.commit()
    }

    required init?(coder: NSCoder) { nil }

    /// Draws the page's objects over the ink, the lowest first, except the box being typed in.
    func show(_ objects: [PDFOverInkObject], cropBox: CGRect, hiding hiddenBoxName: String?) {
        guard objects != shownObjects || cropBox != self.cropBox || hiddenBoxName != self.hiddenBoxName else { return }
        shownObjects = objects
        self.cropBox = cropBox
        self.hiddenBoxName = hiddenBoxName
        drawnAnnotations = Set(objects.compactMap { object in
            if case .annotation(let annotation, _, _) = object { return ObjectIdentifier(annotation) }
            return nil
        })
        rebuildLayers()
    }

    func setCarriedObjectNames(_ names: Set<String>) {
        guard names != carriedObjectNames else { return }
        carriedObjectNames = names
        rebuildLayers()
    }

    /// Whether this view draws the annotation, a picture or a shape over the ink.
    func draws(_ annotation: PDFAnnotation) -> Bool {
        drawnAnnotations.contains(ObjectIdentifier(annotation))
    }

    /// Whether this view draws the text box of this name over the ink.
    func drawsBox(named name: String?) -> Bool {
        guard let name else { return false }
        return shownObjects.contains { object in
            if case .textBox(let box) = object { return box.name == name }
            return false
        }
    }

    /// Whether the lasso's frame carries the object of this name.
    func isCarried(_ name: String) -> Bool {
        carriedObjectNames.contains(name)
    }

    /// The objects it shows, the lowest first, for a picture of an area of the page.
    var objects: [PDFOverInkObject] { shownObjects }

    private func rebuildLayers() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        pageLayer.sublayers?.forEach { sublayer in sublayer.removeFromSuperlayer() }
        let pageToView = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: -cropBox.minX, ty: cropBox.maxY)
        for object in shownObjects {
            switch object {
            case .textBox(let box):
                guard box.name != hiddenBoxName, !carriedObjectNames.contains(box.name) else { continue }
                pageLayer.addSublayer(Self.boxLayer(for: box, pageToView: pageToView, displayScale: traitCollection.displayScale,
                                                    pictureResolution: pictureResolution))
            case .annotation(let annotation, let name, _):
                if let name, carriedObjectNames.contains(name) { continue }
                pageLayer.addSublayer(PDFAnnotationOverInkLayer(annotation: annotation, pageToView: pageToView, pixelsPerPoint: pictureResolution))
            }
        }
        CATransaction.commit()
        setNeedsLayout()
    }

    /// The objects over the page's ink this view draws, the lowest first: Graphite's text
    /// boxes and pictures, and shapes. Another application's boxes and links are left to PDFKit.
    static func objectsOverInk(on page: PDFPage) -> [PDFOverInkObject] {
        PDFPageManager.annotationsOverInk(of: page).compactMap { annotation in
            if PDFTextBox.hasRecord(annotation) { return PDFTextBox(annotation: annotation).map(PDFOverInkObject.textBox) }
            guard PDFPageManager.isPicture(annotation) || PDFShape.isShape(annotation) else { return nil }
            return .annotation(annotation, name: annotation.persistentName, bounds: annotation.bounds)
        }
    }

    /// Whether the annotation is of a kind this view may draw, which is shown through PDFKit
    /// while it is under the ink: one of Graphite's text boxes or pictures, or a shape.
    static func drawsKind(of annotation: PDFAnnotation) -> Bool {
        PDFTextBox.hasRecord(annotation) || PDFPageManager.isPicture(annotation) || PDFShape.isShape(annotation)
    }

    /// One box: its fill, its text's outlines in each of its colors, and its border; or, for a
    /// box with emoji, whose glyphs are pictures, the whole box drawn as a picture.
    private static func boxLayer(for box: PDFTextBox, pageToView: CGAffineTransform, displayScale: CGFloat, pictureResolution: CGFloat) -> CALayer {
        let layout = PDFTextBoxLayout(box: box)
        if layout.usesColorGlyphs { return PDFTextBoxPictureLayer(layout: layout, pageToView: pageToView, pixelsPerPoint: pictureResolution) }
        var boxToView = layout.boxToPage.concatenating(pageToView)
        let container = CALayer()
        let outline = CGPath(rect: layout.boxRectangle, transform: &boxToView)
        if let fillColor = box.style.fillColor {
            container.addSublayer(shapeLayer(outline, fill: PDFTextBoxLayout.cgColor(fillColor), displayScale: displayScale))
        }
        for text in layout.textOutlines() {
            guard let path = text.path.copy(using: &boxToView) else { continue }
            container.addSublayer(shapeLayer(path, fill: PDFTextBoxLayout.cgColor(text.color), displayScale: displayScale))
        }
        if box.style.hasBorder, let borderColor = box.style.borderColor {
            let inset = CGFloat(box.style.borderWidth) / 2
            let borderPath = CGPath(rect: layout.boxRectangle.insetBy(dx: inset, dy: inset), transform: &boxToView)
            let border = shapeLayer(borderPath, fill: nil, displayScale: displayScale)
            border.strokeColor = PDFTextBoxLayout.cgColor(borderColor)
            border.lineWidth = CGFloat(box.style.borderWidth)
            container.addSublayer(border)
        }
        return container
    }

    private static func shapeLayer(_ path: CGPath, fill: CGColor?, displayScale: CGFloat) -> CAShapeLayer {
        let shape = CAShapeLayer()
        shape.path = path
        shape.fillColor = fill
        shape.strokeColor = nil
        // Core Animation draws the shape at the zoom it is shown at.
        shape.contentsScale = displayScale
        return shape
    }

}
/// A text box drawn as a picture, for one with emoji, whose glyphs have no outlines to draw
/// as shapes. It is drawn at the screen's pixels per point of the zoom it is seen at, drawn
/// again when the zoom settles, within a bound of pixels. Before HUNT-320 it was drawn for a
/// zoom of 3 at most and magnified past it.
final class PDFTextBoxPictureLayer: CALayer {
    private let layout: PDFTextBoxLayout?
    /// The most pixels one box is drawn with: 16 megapixels, 64 MB.
    static let maximumPixelCount: CGFloat = 16_777_216
    /// A change of resolution smaller than this fraction is not worth drawing the box again.
    private static let resolutionTolerance: CGFloat = 0.02

    init(layout: PDFTextBoxLayout, pageToView: CGAffineTransform, pixelsPerPoint: CGFloat) {
        self.layout = layout
        super.init()
        let bounds = layout.box.annotationBounds
        frame = bounds.applying(pageToView)
        contentsScale = Self.boundedScale(forPixelsPerPoint: pixelsPerPoint, size: frame.size)
        setNeedsDisplay()
    }

    /// Draws the box again at this many pixels per point, within the bound, when that is not
    /// what it is drawn at already.
    func draw(atPixelsPerPoint pixelsPerPoint: CGFloat) {
        let scale = Self.boundedScale(forPixelsPerPoint: pixelsPerPoint, size: bounds.size)
        guard abs(contentsScale - scale) > scale * Self.resolutionTolerance else { return }
        contentsScale = scale
        setNeedsDisplay()
    }

    /// The pixels per point a box of this size is drawn at: those asked for, at most
    /// `maximumPixelCount` pixels in all and at least one pixel per point.
    static func boundedScale(forPixelsPerPoint pixelsPerPoint: CGFloat, size: CGSize) -> CGFloat {
        let wantedScale = pixelsPerPoint.isFinite && pixelsPerPoint > 0 ? pixelsPerPoint : 1
        let pixelLimitedScale = (maximumPixelCount / max(size.width * size.height, 1)).squareRoot()
        return max(min(wantedScale, pixelLimitedScale), 1)
    }

    override init(layer: Any) {
        layout = (layer as? PDFTextBoxPictureLayer)?.layout
        super.init(layer: layer)
    }

    required init?(coder: NSCoder) { nil }

    override func draw(in context: CGContext) {
        guard let layout else { return }
        let pageBounds = layout.box.annotationBounds
        // The layer counts downward from the box's top; the page upward from its bottom.
        context.translateBy(x: 0, y: bounds.height)
        context.scaleBy(x: 1, y: -1)
        context.translateBy(x: -pageBounds.minX, y: -pageBounds.minY)
        layout.draw(inPageContext: context)
    }
}

/// A picture or a shape over the ink, drawn from its annotation at the screen's pixels per point
/// of the zoom it is seen at, within the bound of pixels a box's picture has.
final class PDFAnnotationOverInkLayer: CALayer {
    private let annotation: PDFAnnotation?
    private static let resolutionTolerance: CGFloat = 0.02

    init(annotation: PDFAnnotation, pageToView: CGAffineTransform, pixelsPerPoint: CGFloat) {
        self.annotation = annotation
        super.init()
        frame = annotation.bounds.applying(pageToView)
        contentsScale = PDFTextBoxPictureLayer.boundedScale(forPixelsPerPoint: pixelsPerPoint, size: frame.size)
        setNeedsDisplay()
    }

    override init(layer: Any) {
        annotation = (layer as? PDFAnnotationOverInkLayer)?.annotation
        super.init(layer: layer)
    }

    required init?(coder: NSCoder) { nil }

    func draw(atPixelsPerPoint pixelsPerPoint: CGFloat) {
        let scale = PDFTextBoxPictureLayer.boundedScale(forPixelsPerPoint: pixelsPerPoint, size: bounds.size)
        guard abs(contentsScale - scale) > scale * Self.resolutionTolerance else { return }
        contentsScale = scale
        setNeedsDisplay()
    }

    override func draw(in context: CGContext) {
        guard let annotation else { return }
        let pageBounds = annotation.bounds
        // The layer counts downward from the annotation's top; the page upward from its bottom.
        context.translateBy(x: 0, y: bounds.height)
        context.scaleBy(x: 1, y: -1)
        context.translateBy(x: -pageBounds.minX, y: -pageBounds.minY)
        if PDFPicture.drawShown(annotation, inPageCoordinates: context) { return }
        // PDFKit draws an annotation relative to the origin of the box it is given.
        if let cropBoxOrigin = annotation.page?.bounds(for: .cropBox).origin { context.translateBy(x: cropBoxOrigin.x, y: cropBoxOrigin.y) }
        annotation.drawAsShown(with: .cropBox, in: context)
    }
}
#endif
