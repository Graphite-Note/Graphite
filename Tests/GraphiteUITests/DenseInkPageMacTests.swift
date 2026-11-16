/**
 * File: DenseInkPageMacTests.swift
 * --------------------------------
 * Layer: Tests
 * Description: On the Mac, a page written as densely as a formula sheet (6,000 strokes) is shown sharp in its ink
 *              layer and drawn again at a zoom; the annotation layers kept sharp are only those shown, and a look draws
 *              them again only for its share of a frame.
 *
 * Authors: Bahey Shalash
 * Version: 0.3
 * Date: 16/11/2026
 */
import XCTest
import PDFKit
import SwiftUI
import GraphiteCore
import GraphiteApple
@testable import GraphiteUI

#if os(macOS)
import AppKit
import QuartzCore
import GraphiteTestSupport

/// The formula sheet's density on the Mac, where PDFKit shows every stroke's annotation in a layer of its own and
/// `PDFAnnotationLayerResolution` draws those layers at the screen's resolution. Measured 2026-11-12 (debug build, M5
/// Max): shown sharp 1.5 s after opening, a look at the layers with nothing to draw 6 ms, the 6,000 layers drawn again
/// at a new zoom in 0.39 s, all in one frame. Since 2026-11-16 a look draws for at most `drawingTimePerLook`, and the
/// looks that follow draw the rest; and a page of the file as read has its ink drawn in one layer, off the main thread
/// (`MacPDFPageInkLayers`, HUNT-357), so the strokes' own layers draw nothing and are not looked into.
@MainActor
final class DenseInkPageMacTests: XCTestCase {
    private var vault: TemporaryVault!

    override func setUp() async throws {
        vault = try TemporaryVault.make(prefix: "DenseInkPageMac", for: self)
    }

    func testADensePageIsShownSharpAndLookedAtQuicklyAndDrawnAgainAtAZoomWithinBudget() async throws {
        let location = vault.location(of: "Dense.pdf")
        let strokeCount = DenseHandwritingNotebook.formulaSheetStrokeCount
        try DenseHandwritingNotebook.write(pageCount: 1, strokesPerPage: strokeCount, to: location)
        let openStart = ContinuousClock.now
        let session = try await PDFSession.open(location)
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 1_400, height: 1_000), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let hostingView = NSHostingView(rootView: GraphitePDFView(session: session, input: PDFAnnotationInput(isEnabled: false, drawsWithFinger: false,
                                                                                                               showsToolPicker: false)))
        window.contentView = hostingView
        window.showInvisibly()
        hostingView.layoutSubtreeIfNeeded()
        let pdfView = try XCTUnwrap(session.pdfView as? GraphiteMacPDFView)
        let pageBox = try XCTUnwrap(session.document.page(at: 0)).bounds(for: .cropBox)
        func pictureIsAtTheScreensResolution() -> Bool {
            guard let picture = Self.inkPicture(in: pdfView) else { return false }
            return abs(CGFloat(picture.width) - pageBox.width * pdfView.scaleFactor * window.backingScaleFactor) <= 2
        }
        try await waitUntil("the page's ink is drawn in its layer at the screen's resolution", timeoutSeconds: 60) { pictureIsAtTheScreensResolution() }
        let shownDuration = ContinuousClock.now - openStart
        let strokes = try XCTUnwrap(session.document.page(at: 0)).annotations.filter { annotation in annotation.value(forAnnotationKey: PDFPageManager.groupKey) != nil }
        XCTAssertEqual(strokes.count, strokeCount)
        XCTAssertTrue(strokes.allSatisfy(\.isDrawnByPageInkLayer), "The strokes' own layers draw nothing.")

        var start = ContinuousClock.now
        pdfView.annotationLayerResolution.update()
        let lookDuration = ContinuousClock.now - start

        pdfView.scaleFactor *= 2
        let zoomedSize = CGSize(width: pageBox.width * pdfView.scaleFactor, height: pageBox.height * pdfView.scaleFactor)
        let fitsInAPicture = MacPDFPageInkLayers.fitsInAPicture(MacPDFPageInkLayers.pixelSize(shownSize: zoomedSize, backingScale: window.backingScaleFactor))
        start = ContinuousClock.now
        pdfView.annotationLayerResolution.update()
        let zoomLookDuration = ContinuousClock.now - start
        if fitsInAPicture {
            try await waitUntil("the page's ink is drawn again at the zoom", timeoutSeconds: 60) { pictureIsAtTheScreensResolution() }
        } else {
            // Zoomed in too far for one picture: PDFKit draws the strokes, and the looks sharpen them a share at a time.
            try await waitUntil("PDFKit draws the zoomed page's strokes", timeoutSeconds: 60) { !strokes.contains { stroke in stroke.isDrawnByPageInkLayer } }
        }
        let redrawDuration = ContinuousClock.now - start
        print("DenseInkPageMacTests timing: shown sharp \(shownDuration), a look \(lookDuration), a look after the zoom \(zoomLookDuration), "
              + "drawn again at the zoom (\(fitsInAPicture ? "in its layer" : "by PDFKit")) in \(redrawDuration)")
        XCTAssertLessThan(shownDuration, .seconds(20), "A page of 6,000 strokes shows sharp soon after opening.")
        XCTAssertLessThan(lookDuration, .milliseconds(60), "A look at the layers, made at every scroll, stays a small part of a frame.")
        XCTAssertLessThan(zoomLookDuration, .milliseconds(60), "A look after the zoom stays a small part of a frame.")
        XCTAssertLessThan(redrawDuration, .seconds(30), "The page's ink is drawn again at the zoom within seconds.")
    }

    /// The picture of the page's ink its layer shows (`MacPDFPageInkLayers`).
    private static func inkPicture(in view: NSView) -> CGImage? {
        for subview in view.subviews {
            if let inkView = subview as? MacPDFPageInkView, let picture = inkView.picture { return picture }
            if let picture = inkPicture(in: subview) { return picture }
        }
        return nil
    }

    /// A look draws layers while it has time and stops when it has none, after the first, which it always draws.
    func testALookDrawsLayersOnlyWhileItHasTime() {
        let layers = (0..<5).map { _ in TestAnnotationLayer() }
        var timeChecks = 0
        let drawnCount = PDFAnnotationLayerResolution.draw(layers.map { layer in (layer, 2) }) {
            timeChecks += 1
            return timeChecks <= 2
        }
        XCTAssertEqual(drawnCount, 3)
        XCTAssertEqual(layers.map(\.contentsScale), [2, 2, 2, 1, 1])
        XCTAssertEqual(layers.prefix(3).map(\.drawCount), [1, 1, 1], "Drawn in the look, so its time is counted.")

        let slowLayers = (0..<3).map { _ in TestAnnotationLayer() }
        XCTAssertEqual(PDFAnnotationLayerResolution.draw(slowLayers.map { layer in (layer, 3) }) { false }, 1,
                       "With no time left the first is still drawn, so the looks move on.")
        XCTAssertEqual(slowLayers.map(\.contentsScale), [3, 1, 1])
    }

    /// A hidden layer draws nothing anyone sees: it is not drawn again at the screen's resolution, nor looked into.
    func testOnlyShownAnnotationLayersAreKeptSharp() {
        let documentLayer = CALayer()
        let pageLayer = CALayer()
        documentLayer.addSublayer(pageLayer)
        let shownLayers = (0..<3).map { _ in TestAnnotationLayer() }
        let hiddenLayers = (0..<5).map { _ in TestAnnotationLayer() }
        for layer in shownLayers + hiddenLayers { pageLayer.addSublayer(layer) }
        for layer in hiddenLayers { layer.isHidden = true }
        let hiddenPageLayer = CALayer()
        hiddenPageLayer.isHidden = true
        hiddenPageLayer.addSublayer(TestAnnotationLayer())
        documentLayer.addSublayer(hiddenPageLayer)
        let found = PDFAnnotationLayerResolution.annotationLayers(under: documentLayer, annotationLayerClass: TestAnnotationLayer.self)
        XCTAssertEqual(found.map(ObjectIdentifier.init), shownLayers.map(ObjectIdentifier.init))
    }

}

/// Stands for PDFKit's annotation layer class, and counts its drawing.
private final class TestAnnotationLayer: CALayer {
    private(set) var drawCount = 0

    override func display() {
        drawCount += 1
    }
}
#endif
