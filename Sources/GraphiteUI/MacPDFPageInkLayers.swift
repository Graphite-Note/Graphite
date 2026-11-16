/**
 * File: MacPDFPageInkLayers.swift
 * -------------------------------
 * Layer: UI
 * Description: On the Mac, draws each shown page's Graphite ink in one layer over the page, from a separate copy of the
 *              file and off the main thread, instead of PDFKit drawing every stroke in a layer of its own.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 16/11/2026
 */
#if os(macOS)
import AppKit
import PDFKit
import GraphiteApple

/// Draws each shown page's Graphite ink in one layer over the page, on the Mac (HUNT-357).
///
/// PDFKit gives every annotation a layer of its own and draws each stroke in it from its saved appearance, on the main
/// thread, the first time it makes a page's view: a page written with 520 strokes stopped a note's scrolling for 50 to
/// 66 ms each time a handwritten PDF came into view. Here a page of the file as it was read gets a view over it (a page
/// overlay) whose layer holds one picture of the page's ink, drawn from a separate copy of the file
/// (`PDFSession.originalFileData`) by `PDFPageInkRenderer`, off the main thread, at the screen's pixels per point; the
/// strokes' own layers draw nothing meanwhile (`PDFPageInkLayerState`, `PDFShownInkAnnotation`). The picture comes a few
/// frames after the page, as PDFKit's own tiles do, and is drawn again at the end of a zoom.
///
/// The copy holds the file as it was read, so a page that has been edited (a stroke drawn, erased or undone, a
/// signature, a turn) is given back to PDFKit, which draws the live document's strokes as before, from then on; so is a
/// page from another PDF, or one whose picture could not be drawn. A page zoomed in so far that its picture would hold
/// more than `maximumPixelsPerPage` is drawn by PDFKit too, sharpened by `PDFAnnotationLayerResolution` within its bound,
/// until the zoom comes back. The file is never changed.
@MainActor
final class MacPDFPageInkLayers: NSObject, @preconcurrency PDFPageOverlayViewProvider {
    /// A page's picture holds at most this many pixels (64 MB); a page zoomed in further is drawn by PDFKit.
    static let maximumPixelsPerPage = 16 * 1_048_576
    /// The pictures are drawn again this long after the zoom last changed, not at every step of a pinch.
    private static let redrawDelayAfterZoom: TimeInterval = 0.15

    private struct ShownPage {
        weak var page: PDFPage?
        weak var overlay: MacPDFPageInkView?
        var drawing: Task<Void, Never>?
        var drawnPixelSize: CGSize?
    }

    private weak var session: PDFSession?
    private weak var view: PDFView?
    private let document: PDFShownDocument
    private let fileData: Data
    private let renderer = PDFPageInkRenderer()
    private var claim: PDFPageInkLayerState.DrawingClaim?
    private var shownPages: [ObjectIdentifier: ShownPage] = [:]
    /// Pages PDFKit draws while they are zoomed in too far for one picture.
    private var pagesGivenForZoom = Set<ObjectIdentifier>()
    private var redrawTimer: Timer?

    /// Nil when the session's document cannot be drawn from a copy (an encrypted PDF, or a file that could not be
    /// mapped); PDFKit then draws every stroke. Make it before the view shows the document.
    init?(session: PDFSession, view: PDFView) {
        guard let document = session.document as? PDFShownDocument, let fileData = session.originalFileData else { return nil }
        self.session = session
        self.view = view
        self.document = document
        self.fileData = fileData
        super.init()
        claim = document.pageInkLayers.claimDrawing()
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(scheduleRedraw), name: .PDFViewScaleChanged, object: view)
        center.addObserver(self, selector: #selector(backingPropertiesChanged(_:)), name: NSWindow.didChangeBackingPropertiesNotification, object: nil)
        observeEdits()
    }

    /// Lets PDFKit draw every stroke again, as when the view is taken down.
    func stop() {
        NotificationCenter.default.removeObserver(self)
        redrawTimer?.invalidate()
        redrawTimer = nil
        for shownPage in shownPages.values { shownPage.drawing?.cancel() }
        shownPages.removeAll()
        claim = nil
    }

    /// Pages whose picture is shown, which a test asks.
    var pagesWithPictures: [PDFPage] {
        shownPages.values.compactMap { shownPage in shownPage.overlay?.picture == nil ? nil : shownPage.page }
    }

    // MARK: Page overlays

    func pdfView(_ view: PDFView, overlayViewFor page: PDFPage) -> NSView? {
        guard isUneditedFilePage(page) else {
            giveToPDFKit(page)
            return nil
        }
        let overlay = MacPDFPageInkView()
        shownPages[ObjectIdentifier(page)] = ShownPage(page: page, overlay: overlay)
        return overlay
    }

    func pdfView(_ pdfView: PDFView, willDisplayOverlayView overlayView: NSView, for page: PDFPage) {
        draw(page)
    }

    func pdfView(_ pdfView: PDFView, willEndDisplayingOverlayView overlayView: NSView, for page: PDFPage) {
        shownPages.removeValue(forKey: ObjectIdentifier(page))?.drawing?.cancel()
    }

    /// A page of the file, not edited since it was read, while the document is claimed.
    private func isUneditedFilePage(_ page: PDFPage) -> Bool {
        guard claim != nil, let session, session.editCount(of: page) == 0, let corePage = page.pageRef,
              let documentReference = document.documentRef else { return false }
        return corePage.document === documentReference
    }

    /// PDFKit draws the page's strokes, for good or, `forZoom`, until the zoom comes back; its picture goes.
    private func giveToPDFKit(_ page: PDFPage, forZoom: Bool = false) {
        let identifier = ObjectIdentifier(page)
        if let shownPage = shownPages[identifier] {
            shownPage.drawing?.cancel()
            shownPages[identifier]?.drawing = nil
            shownPages[identifier]?.drawnPixelSize = nil
            shownPage.overlay?.showInk(nil)
        }
        if forZoom { pagesGivenForZoom.insert(identifier) } else { pagesGivenForZoom.remove(identifier) }
        guard document.pageInkLayers.drawsInk(of: page, in: document) else { return }
        document.pageInkLayers.letPDFKitDraw(page)
        // The strokes' layers drew nothing until now: PDFKit draws them again.
        view?.annotationsChanged(on: page)
    }

    /// The page's layer draws its ink again after a zoom too deep for it; the strokes' own layers draw nothing again.
    private func takeBackFromPDFKit(_ page: PDFPage) {
        guard pagesGivenForZoom.remove(ObjectIdentifier(page)) != nil else { return }
        document.pageInkLayers.takeBack(page)
        view?.annotationsChanged(on: page)
    }

    // MARK: Drawing

    /// Draws the page's picture at the screen's pixels per point, unless it is already drawn at that size.
    private func draw(_ page: PDFPage) {
        let identifier = ObjectIdentifier(page)
        guard shownPages[identifier] != nil, let view, let window = view.window, isUneditedFilePage(page),
              let corePage = page.pageRef, let documentReference = document.documentRef else { return }
        let shownSize = view.convert(page.bounds(for: .cropBox), from: page).size
        let pixelSize = Self.pixelSize(shownSize: shownSize, backingScale: window.backingScaleFactor)
        guard Self.fitsInAPicture(pixelSize) else {
            if !pagesGivenForZoom.contains(identifier) { giveToPDFKit(page, forZoom: true) }
            return
        }
        takeBackFromPDFKit(page)
        guard let shownPage = shownPages[identifier], pixelSize.width >= 1, pixelSize.height >= 1, pixelSize != shownPage.drawnPixelSize else { return }
        let request = PDFPageInkRequest(fileData: fileData, pageNumber: corePage.pageNumber, filePageCount: documentReference.numberOfPages,
                                        cropBox: page.bounds(for: .cropBox), rotation: ((page.rotation % 360) + 360) % 360,
                                        pixelWidth: Int(pixelSize.width), pixelHeight: Int(pixelSize.height))
        shownPage.drawing?.cancel()
        let renderer = renderer
        shownPages[identifier]?.drawnPixelSize = pixelSize
        shownPages[identifier]?.drawing = Task { [weak self, weak page] in
            let drawing = await renderer.draw(request)
            guard !Task.isCancelled, let self, let page else { return }
            self.show(drawing, for: page)
        }
    }

    private func show(_ drawing: PDFPageInkDrawing, for page: PDFPage) {
        let identifier = ObjectIdentifier(page)
        shownPages[identifier]?.drawing = nil
        guard isUneditedFilePage(page) else {
            giveToPDFKit(page)
            return
        }
        guard !pagesGivenForZoom.contains(identifier) else { return }
        switch drawing {
        case .picture(let picture): shownPages[identifier]?.overlay?.showInk(picture)
        case .noInk: shownPages[identifier]?.overlay?.showInk(nil)
        case .unavailable: giveToPDFKit(page)
        }
    }

    /// The pixels of a page shown `shownSize` points large, at the screen's resolution.
    static func pixelSize(shownSize: CGSize, backingScale: CGFloat) -> CGSize {
        CGSize(width: (shownSize.width * backingScale).rounded(), height: (shownSize.height * backingScale).rounded())
    }

    /// Whether a picture of this many pixels is within `maximumPixelsPerPage`.
    static func fitsInAPicture(_ pixelSize: CGSize) -> Bool {
        pixelSize.width * pixelSize.height <= CGFloat(maximumPixelsPerPage)
    }

    /// Draws every shown page's picture again once the zoom or the screen has stopped changing.
    @objc private func scheduleRedraw() {
        redrawTimer?.invalidate()
        // A timer rather than a task, so it runs while a pinch keeps the run loop in tracking mode.
        let timer = Timer(timeInterval: Self.redrawDelayAfterZoom, target: self, selector: #selector(redrawShownPages), userInfo: nil, repeats: false)
        RunLoop.main.add(timer, forMode: .common)
        redrawTimer = timer
    }

    @objc private func backingPropertiesChanged(_ notification: Notification) {
        guard let window = view?.window, notification.object as? NSWindow === window else { return }
        scheduleRedraw()
    }

    @objc private func redrawShownPages() {
        redrawTimer = nil
        for shownPage in shownPages.values { if let page = shownPage.page { draw(page) } }
    }

    /// An edit of a shown page gives it to PDFKit, which draws the live document.
    private func observeEdits() {
        guard let session else { return }
        withObservationTracking {
            _ = session.changeVersion
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.claim != nil, let session = self.session else { return }
                for shownPage in self.shownPages.values {
                    if let page = shownPage.page, session.editCount(of: page) > 0 { self.giveToPDFKit(page) }
                }
                self.observeEdits()
            }
        }
    }
}

/// The view over a page that shows its ink's picture; it takes no clicks, which go on to the page.
final class MacPDFPageInkView: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layerContentsRedrawPolicy = .never
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { nil }

    override func makeBackingLayer() -> CALayer {
        let layer = CALayer()
        // The picture is the whole page as shown, so it fills the view at any size, softer during a pinch.
        layer.contentsGravity = .resize
        return layer
    }

    override var isOpaque: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// The picture of the page's ink the layer shows.
    private(set) var picture: CGImage?

    func showInk(_ picture: CGImage?) {
        self.picture = picture
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer?.contents = picture
        CATransaction.commit()
    }
}

/// What the renderer needs to draw a page's ink: the file as it was read and the page's place and geometry in it.
struct PDFPageInkRequest: Sendable {
    /// Mapped from a file that is never rewritten; the same for every request a renderer gets.
    let fileData: Data
    /// One-based page number in the file.
    let pageNumber: Int
    /// A copy with another page count is not the file the page came from.
    let filePageCount: Int
    let cropBox: CGRect
    /// Clockwise quarter turns, in degrees, as the live page shows it.
    let rotation: Int
    let pixelWidth: Int
    let pixelHeight: Int
}

/// A page's ink drawn by `PDFPageInkRenderer`.
enum PDFPageInkDrawing: Sendable {
    case picture(CGImage)
    /// The page has no Graphite ink.
    case noInk
    /// The copy does not have the page as shown (another page count, crop box or turn).
    case unavailable
}

/// Draws one PDF's pages' Graphite ink from a separate copy of its file, one page at a time, off the main thread. The
/// copy is opened again every few pages, so the strokes it read are let go as a scroll goes on.
actor PDFPageInkRenderer {
    private static let pagesPerSeparateDocument = 16

    private var separateDocument: (document: PDFDocument?, drawnPageCount: Int)?

    func draw(_ request: PDFPageInkRequest) -> PDFPageInkDrawing {
        guard !Task.isCancelled else { return .unavailable }
        if let separateDocument, separateDocument.drawnPageCount >= Self.pagesPerSeparateDocument {
            self.separateDocument = nil
        }
        if separateDocument == nil {
            separateDocument = (PDFDocument(data: request.fileData), 0)
        }
        separateDocument?.drawnPageCount += 1
        guard let document = separateDocument?.document, document.pageCount == request.filePageCount,
              let page = document.page(at: request.pageNumber - 1), page.bounds(for: .cropBox) == request.cropBox,
              ((page.rotation % 360) + 360) % 360 == request.rotation else { return .unavailable }
        let strokes = page.annotations.filter { annotation in annotation.value(forAnnotationKey: PDFPageManager.groupKey) != nil && annotation.shouldDisplay }
        guard !strokes.isEmpty else { return .noInk }
        guard let context = CGContext(data: nil, width: request.pixelWidth, height: request.pixelHeight, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return .unavailable }
        // As the thumbnails draw annotations: in a context with the PDF's upward y axis, scaled to the page as shown; each
        // annotation applies the crop box and the page's turn itself.
        let displayedWidth = request.rotation % 180 == 0 ? request.cropBox.width : request.cropBox.height
        guard displayedWidth > 0 else { return .unavailable }
        let pixelsPerPagePoint = CGFloat(request.pixelWidth) / displayedWidth
        context.scaleBy(x: pixelsPerPagePoint, y: pixelsPerPagePoint)
        for stroke in strokes { stroke.draw(with: .cropBox, in: context) }
        return context.makeImage().map(PDFPageInkDrawing.picture) ?? .unavailable
    }
}
#endif
