/**
 * File: MacPDFPageInkLayersTests.swift
 * ------------------------------------
 * Layer: Tests
 * Description: On the Mac, a page's saved ink is drawn in one layer over the page, where and as PDFKit draws it, upright
 *              and turned, from an IOSurface held once; an edit gives the page back to PDFKit; thumbnails still show the
 *              ink; pictures stay bounded and go with their page.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 19/11/2026
 */
import XCTest
import PDFKit
import SwiftUI
import GraphiteCore
import GraphiteApple
@testable import GraphiteUI

#if os(macOS)
import AppKit
import IOSurface
import GraphiteTestSupport

@MainActor
final class MacPDFPageInkLayersTests: XCTestCase {
    private var vault: TemporaryVault!

    override func setUp() async throws {
        vault = try TemporaryVault.make(prefix: "MacPDFPageInkLayers", for: self)
    }

    func testAPagesInkIsDrawnInOneLayerAsPDFKitDrawsIt() async throws {
        try await checkThePagesInkIsDrawnInOneLayerAsPDFKitDrawsIt(rotation: 0)
    }

    func testATurnedPagesInkIsDrawnInOneLayerAsPDFKitDrawsIt() async throws {
        try await checkThePagesInkIsDrawnInOneLayerAsPDFKitDrawsIt(rotation: 90)
    }

    private func checkThePagesInkIsDrawnInOneLayerAsPDFKitDrawsIt(rotation: Int) async throws {
        let location = try await makeSavedPDF(rotation: rotation)
        let (window, pdfView, _) = try await show(location)
        defer { window.close() }
        let page = try XCTUnwrap(pdfView.document?.page(at: 0))
        let picture = try await waitForPicture(of: page, in: pdfView)

        let strokes = page.annotations.filter { annotation in annotation.value(forAnnotationKey: PDFPageManager.groupKey) != nil }
        XCTAssertEqual(strokes.count, Self.strokes.count)
        XCTAssertTrue(strokes.allSatisfy(\.isDrawnByPageInkLayer), "The strokes' own layers draw nothing.")
        XCTAssertTrue(sharpenedAnnotationLayers(in: pdfView).isEmpty, "No stroke's own layer is drawn again at the screen's resolution.")

        let overlay = try XCTUnwrap(Self.inkViews(in: pdfView).first)
        let pageRectangle = pdfView.convert(page.bounds(for: .cropBox), from: page)
        let overlayRectangle = pdfView.convert(overlay.bounds, from: overlay)
        XCTAssertEqual(overlayRectangle.minX, pageRectangle.minX, accuracy: 1)
        XCTAssertEqual(overlayRectangle.minY, pageRectangle.minY, accuracy: 1)
        XCTAssertEqual(overlayRectangle.width, pageRectangle.width, accuracy: 1)
        XCTAssertEqual(overlayRectangle.height, pageRectangle.height, accuracy: 1)
        let screenPixelsPerPoint = pdfView.scaleFactor * window.backingScaleFactor
        XCTAssertEqual(CGFloat(picture.width), pageRectangle.width / pdfView.scaleFactor * screenPixelsPerPoint, accuracy: 2,
                       "The picture is drawn at the screen's pixels per point.")

        // PDFKit's own drawing of the page as read from the file, at the picture's size, against the picture over white.
        let reference = try Self.pdfKitDrawing(of: try XCTUnwrap(PDFDocument(url: location)?.page(at: 0)), width: picture.width, height: picture.height)
        let shown = try Self.composite(picture, overWhiteOf: picture.width, height: picture.height)
        let comparison = Self.compare(shown, reference)
        print("PAGE-INK rotation \(rotation): \(comparison.inkPixels) ink pixels, \(comparison.differingPixels) differ, picture \(picture.width)x\(picture.height)")
        XCTAssertGreaterThan(comparison.inkPixels, 1_000)
        XCTAssertLessThan(Double(comparison.differingPixels), Double(comparison.inkPixels) * 0.02, "The picture is PDFKit's drawing of the ink.")
        let shownCenter = try XCTUnwrap(comparison.shownInkCenter), referenceCenter = try XCTUnwrap(comparison.referenceInkCenter)
        XCTAssertEqual(shownCenter.x, referenceCenter.x, accuracy: 2)
        XCTAssertEqual(shownCenter.y, referenceCenter.y, accuracy: 2, "Upright as PDFKit draws the page.")
        XCTAssertFalse(overlay.layer?.contentsAreFlipped() ?? true, "The layer shows the picture upright.")
        let contents = try XCTUnwrap(overlay.layer?.contents)
        XCTAssertEqual(CFGetTypeID(contents as CFTypeRef), IOSurfaceGetTypeID(),
                       "The layer shows an IOSurface, which Core Animation does not copy as it copies a CGImage.")
    }

    /// A page PDFKit stops showing lets its picture go at once (a picture of a page at fit width on a Retina screen is
    /// about 7.5 MB), rather than when PDFKit lets go of its overlay.
    func testAPageNoLongerShownLetsItsPictureGo() async throws {
        let location = try await makeSavedPDF(rotation: 0)
        let (window, pdfView, _) = try await show(location)
        defer { window.close() }
        let page = try XCTUnwrap(pdfView.document?.page(at: 0))
        _ = try await waitForPicture(of: page, in: pdfView)
        let overlay = try XCTUnwrap(Self.inkViews(in: pdfView).first)
        let pageInkLayers = try XCTUnwrap(pdfView.pageInkLayers)

        pageInkLayers.pdfView(pdfView, willEndDisplayingOverlayView: overlay, for: page)

        XCTAssertFalse(overlay.isShowingInk)
        XCTAssertNil(overlay.layer?.contents, "The layer holds no picture.")
        XCTAssertTrue(pageInkLayers.pagesWithPictures.isEmpty)
    }

    func testAnEditGivesThePageBackToPDFKit() async throws {
        let location = try await makeSavedPDF(rotation: 0)
        let (window, pdfView, session) = try await show(location)
        defer { window.close() }
        let page = try XCTUnwrap(pdfView.document?.page(at: 0))
        _ = try await waitForPicture(of: page, in: pdfView)

        let added = PortableInkStroke(name: "added", segments: [[CGPoint(x: 300, y: 300), CGPoint(x: 360, y: 340)]], width: 4,
                                      red: 0, green: 0, blue: 0, alpha: 1, outline: nil)
        try session.apply(.updateInk(PDFInkUpdate(pageIndex: 0, group: PDFInkGroups.defaultGroup, removal: .strokes([]), addedStrokes: [added], editableRecord: nil)))
        try await waitUntil("the page is given back to PDFKit") {
            pdfView.pageInkLayers?.pagesWithPictures.isEmpty == true
                && !page.annotations.contains { annotation in annotation.isDrawnByPageInkLayer }
        }
        try await waitUntil("PDFKit draws every stroke in its own layer again") {
            self.sharpenedAnnotationLayers(in: pdfView).count == Self.strokes.count + 1
        }
    }

    func testTheThumbnailOfAPageDrawnByItsLayerShowsTheInk() async throws {
        let location = try await makeSavedPDF(rotation: 0)
        let (window, pdfView, session) = try await show(location)
        defer { window.close() }
        let page = try XCTUnwrap(pdfView.document?.page(at: 0))
        _ = try await waitForPicture(of: page, in: pdfView)
        let renderer = PDFThumbnailRenderer()
        renderer.prepare(for: session.document)
        let rendered = await renderer.thumbnail(for: page, version: 0, fitting: CGSize(width: 200, height: 260), scale: 2)
        let thumbnail = try XCTUnwrap(rendered)
        let image = try XCTUnwrap(thumbnail.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let shown = try Self.composite(image, overWhiteOf: image.width, height: image.height)
        XCTAssertGreaterThan(Self.compare(shown, shown).inkPixels, 50, "The thumbnail shows the ink its page's layer draws.")
    }

    func testAPageAtFitWidthFitsInAPictureAndAPageZoomedFarInDoesNot() {
        let atFit = MacPDFPageInkLayers.pixelSize(shownSize: CGSize(width: 760, height: 983), backingScale: 2)
        XCTAssertEqual(atFit, CGSize(width: 1_520, height: 1_966))
        XCTAssertTrue(MacPDFPageInkLayers.fitsInAPicture(atFit))
        XCTAssertFalse(MacPDFPageInkLayers.fitsInAPicture(MacPDFPageInkLayers.pixelSize(shownSize: CGSize(width: 3_040, height: 3_932), backingScale: 2)))
    }

    /// Zoomed in so far that one picture would hold more than its bound, PDFKit draws the page's strokes, sharpened by
    /// `PDFAnnotationLayerResolution`; zoomed out again, the page's layer draws them.
    func testAPageZoomedInTooFarIsDrawnByPDFKitUntilTheZoomComesBack() async throws {
        let location = try await makeSavedPDF(rotation: 0)
        let (window, pdfView, _) = try await show(location)
        defer { window.close() }
        let page = try XCTUnwrap(pdfView.document?.page(at: 0))
        _ = try await waitForPicture(of: page, in: pdfView)
        let fitScale = pdfView.scaleFactor
        pdfView.scaleFactor = fitScale * 4
        try await waitUntil("PDFKit draws the zoomed page's strokes") {
            !page.annotations.contains { annotation in annotation.isDrawnByPageInkLayer }
                && self.sharpenedAnnotationLayers(in: pdfView).count == Self.strokes.count
                && pdfView.pageInkLayers?.pagesWithPictures.isEmpty == true
        }
        pdfView.scaleFactor = fitScale
        _ = try await waitForPicture(of: page, in: pdfView)
        XCTAssertTrue(page.annotations.filter { annotation in annotation.value(forAnnotationKey: PDFPageManager.groupKey) != nil }.allSatisfy(\.isDrawnByPageInkLayer))
    }

    // MARK: Making and showing the PDF

    /// Strokes away from the page's middle, so a picture upside down or mirrored does not match.
    private static let strokes: [PortableInkStroke] = (0..<12).map { index in
        let start = CGPoint(x: 60 + Double(index % 4) * 30, y: 640 + Double(index / 4) * 40)
        let outline = [[start, CGPoint(x: start.x + 4, y: start.y), CGPoint(x: start.x + 24, y: start.y + 26), CGPoint(x: start.x + 20, y: start.y + 26)]]
        return PortableInkStroke(name: "stroke-\(index)", segments: [[CGPoint(x: start.x + 2, y: start.y), CGPoint(x: start.x + 22, y: start.y + 26)]],
                                 width: 4, red: 0.2, green: 0.1, blue: 0.8, alpha: 1, outline: outline)
    }

    private func makeSavedPDF(rotation: Int) async throws -> URL {
        let location = vault.location(of: "Q\(rotation).pdf")
        let revision = try await PDFFileService().create(documentData: PDFTemplateGenerator.documentData(paper: PaperSpecification(template: .blank), pageCount: 1), at: location)
        var edits: [PDFEdit] = [.updateInk(PDFInkUpdate(pageIndex: 0, group: PDFInkGroups.defaultGroup, removal: .strokes([]), addedStrokes: Self.strokes, editableRecord: nil))]
        if rotation != 0 { edits.append(.rotate(page: 0, clockwise: true)) }
        _ = try await PDFFileService().save(url: location, revision: revision, edits: edits)
        return location
    }

    private func show(_ location: URL) async throws -> (NSWindow, GraphiteMacPDFView, PDFSession) {
        let session = try await PDFSession.open(location)
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 900, height: 1_000), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let hostingView = NSHostingView(rootView: GraphitePDFView(session: session, input: PDFAnnotationInput(isEnabled: false, drawsWithFinger: false, showsToolPicker: false)))
        window.contentView = hostingView
        hostingView.layoutSubtreeIfNeeded()
        try await waitUntil("the PDF view is laid out") { (session.pdfView?.frame.height ?? 0) > 0 }
        return (window, try XCTUnwrap(session.pdfView as? GraphiteMacPDFView), session)
    }

    private func waitForPicture(of page: PDFPage, in pdfView: GraphiteMacPDFView) async throws -> CGImage {
        try await waitUntil("the page's ink picture is shown") {
            pdfView.pageInkLayers?.pagesWithPictures.contains { shownPage in shownPage === page } == true
        }
        return try XCTUnwrap(Self.inkViews(in: pdfView).first?.picture)
    }

    // MARK: Looking at the result

    private static func inkViews(in view: NSView) -> [MacPDFPageInkView] {
        view.subviews.flatMap { subview in ((subview as? MacPDFPageInkView).map { [$0] } ?? []) + inkViews(in: subview) }
    }

    private func sharpenedAnnotationLayers(in view: PDFView) -> [CALayer] {
        guard let documentLayer = view.documentView?.layer, let layerClass = NSClassFromString(PDFAnnotationLayerResolution.annotationLayerClassName) else { return [] }
        return PDFAnnotationLayerResolution.annotationLayers(under: documentLayer, annotationLayerClass: layerClass)
    }

    private static func pdfKitDrawing(of page: PDFPage, width: Int, height: Int) throws -> Bitmap {
        let context = try whiteContext(width: width, height: height)
        let cropBox = page.bounds(for: .cropBox)
        let displayedWidth = (page.rotation / 90) % 2 != 0 ? cropBox.height : cropBox.width
        context.scaleBy(x: CGFloat(width) / displayedWidth, y: CGFloat(width) / displayedWidth)
        page.draw(with: .cropBox, to: context)
        return try Bitmap(context)
    }

    private static func composite(_ picture: CGImage, overWhiteOf width: Int, height: Int) throws -> Bitmap {
        let context = try whiteContext(width: width, height: height)
        context.draw(picture, in: CGRect(x: 0, y: 0, width: width, height: height))
        return try Bitmap(context)
    }

    private static func whiteContext(width: Int, height: Int) throws -> CGContext {
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                              space: try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB)), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context
    }

    /// A bitmap's RGBX bytes, rows from the top.
    private struct Bitmap {
        let width: Int
        let bytes: [UInt8]

        init(_ context: CGContext) throws {
            width = context.width
            let data = try XCTUnwrap(context.data)
            bytes = Array(UnsafeBufferPointer(start: data.assumingMemoryBound(to: UInt8.self), count: context.bytesPerRow * context.height))
        }

        func isInk(at offset: Int) -> Bool { bytes[offset] < 200 || bytes[offset + 1] < 200 || bytes[offset + 2] < 200 }
    }

    private struct Comparison {
        let inkPixels: Int
        let differingPixels: Int
        let shownInkCenter: CGPoint?
        let referenceInkCenter: CGPoint?
    }

    /// Ink pixels (not near white) of the reference, pixels that differ by more than a sixth of full scale, and the
    /// centers of the ink in each, in pixels from the top left.
    private static func compare(_ shown: Bitmap, _ reference: Bitmap) -> Comparison {
        var inkPixels = 0, differingPixels = 0, shownCount = 0
        var shownSum = CGPoint.zero, referenceSum = CGPoint.zero
        for pixel in 0..<(reference.bytes.count / 4) {
            let offset = pixel * 4
            let point = CGPoint(x: pixel % reference.width, y: pixel / reference.width)
            if reference.isInk(at: offset) { inkPixels += 1; referenceSum.x += point.x; referenceSum.y += point.y }
            if shown.isInk(at: offset) { shownCount += 1; shownSum.x += point.x; shownSum.y += point.y }
            if (0..<3).contains(where: { channel in abs(Int(shown.bytes[offset + channel]) - Int(reference.bytes[offset + channel])) > 42 }) { differingPixels += 1 }
        }
        return Comparison(inkPixels: inkPixels, differingPixels: differingPixels,
                          shownInkCenter: shownCount == 0 ? nil : CGPoint(x: shownSum.x / CGFloat(shownCount), y: shownSum.y / CGFloat(shownCount)),
                          referenceInkCenter: inkPixels == 0 ? nil : CGPoint(x: referenceSum.x / CGFloat(inkPixels), y: referenceSum.y / CGFloat(inkPixels)))
    }
}
#endif
