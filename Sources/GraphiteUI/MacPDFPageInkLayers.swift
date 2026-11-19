/**
 * File: MacPDFPageInkLayers.swift
 * -------------------------------
 * Layer: UI
 * Description: On the Mac, draws each shown page's Graphite ink in one layer over the page, from a separate copy of the
 *              file and off the main thread, instead of PDFKit drawing every stroke in a layer of its own.
 *
 * Authors: Bahey Shalash
 * Version: 0.4
 * Date: 19/11/2026
 */
#if os(macOS)
import AppKit
import IOSurface
import PDFKit
import Synchronization
import GraphiteApple

/// Draws each shown page's Graphite ink in one layer over the page, on the Mac (HUNT-357).
///
/// PDFKit gives every annotation a layer of its own and draws each stroke in it from its saved appearance, on the main
/// thread, the first time it makes a page's view: a page written with 520 strokes stopped a note's scrolling for 50 to
/// 66 ms each time a handwritten PDF came into view. Here a page of the file as it was read gets a view over it (a page
/// overlay) whose layer holds one picture of the page's ink, drawn from a separate copy of the file
/// (`PDFSession.originalFileData`) by `PDFPageInkRenderer`, off the main thread, at the screen's pixels per point, into
/// an IOSurface the layer shows as it is (a `CGImage` would be copied by Core Animation, so each page's picture took its
/// memory twice: 15 MB a page at fit width on a Retina screen); the strokes' own layers draw nothing meanwhile (`PDFPageInkLayerState`, `PDFShownInkAnnotation`). The picture comes a few
/// frames after the page, as PDFKit's own tiles do, and is drawn again at the end of a zoom.
///
/// The copy holds the file as it was read, so a page that has been edited (a stroke drawn, erased or undone, a
/// signature, a turn) is given back to PDFKit, which draws the live document's strokes as before, from then on; so is a
/// page from another PDF, or one whose picture could not be drawn. A page zoomed in so far that its picture would hold
/// more than `maximumPixelsPerPage` is drawn by PDFKit too, sharpened by `PDFAnnotationLayerResolution` within its bound,
/// until the zoom comes back. The file is never changed.
@MainActor
final class MacPDFPageInkLayers: NSObject, @preconcurrency PDFPageOverlayViewProvider {
    /// A page's picture holds at most this many pixels (64 MB, in one IOSurface); a page zoomed in further is drawn by PDFKit.
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
        shownPages.values.compactMap { shownPage in shownPage.overlay?.isShowingInk == true ? shownPage.page : nil }
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
        // The page's picture goes with it at once, not when PDFKit lets its overlay go.
        (overlayView as? MacPDFPageInkView)?.showInk(nil)
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
                                        pixelWidth: Int(pixelSize.width), pixelHeight: Int(pixelSize.height), drawsIntoSurface: true)
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
        case .surface(let surface): shownPages[identifier]?.overlay?.showInk(surface)
        case .noInk: shownPages[identifier]?.overlay?.showInk(nil)
        // A `CGImage` is drawn only for a request that does not ask for a surface, which this one did.
        case .picture, .unavailable: giveToPDFKit(page)
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
    private var surface: IOSurface?

    var isShowingInk: Bool { surface != nil }

    /// A copy of the picture the layer shows, which tests compare with PDFKit's drawing.
    var picture: CGImage? { surface.flatMap(PDFPageInkSurface.image(of:)) }

    func showInk(_ surface: IOSurface?) {
        self.surface = surface
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer?.contents = surface
        CATransaction.commit()
    }
}

#endif
