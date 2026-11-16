/**
 * File: DenseInkPageMacTests.swift
 * --------------------------------
 * Layer: Tests
 * Description: On the Mac, a page written as densely as a formula sheet (6,000 strokes) is shown, scrolled and zoomed
 *              with its main-thread work within budget; the annotation layers kept sharp are only those shown, and a
 *              look draws them again only for its share of a frame.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
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
/// looks that follow draw the rest.
@MainActor
final class DenseInkPageMacTests: XCTestCase {
    private var vault: TemporaryVault!

    override func setUp() async throws {
        vault = try TemporaryVault.make(prefix: "DenseInkPageMac", for: self)
    }

    func testADensePageIsShownSharpAndLookedAtQuicklyAndDrawnAgainAtAZoomWithinBudget() async throws {
        let location = vault.location(of: "Dense.pdf")
        let strokeCount = DenseHandwritingNotebook.formulaSheetStrokeCount
        _ = try await Task.detached { try DenseHandwritingNotebook.write(pageCount: 1, strokesPerPage: strokeCount, to: location) }.value
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
        try await waitUntil("every stroke has its layer", timeoutSeconds: 60) { Self.annotationLayers(in: session.pdfView).count == strokeCount }
        let pdfView = try XCTUnwrap(session.pdfView as? GraphiteMacPDFView)
        try await waitUntil("every stroke is drawn at the screen's resolution", timeoutSeconds: 60) {
            Self.annotationLayers(in: pdfView).allSatisfy { layer in layer.contentsScale > 1.01 }
        }
        let shownDuration = ContinuousClock.now - openStart

        var start = ContinuousClock.now
        pdfView.annotationLayerResolution.update()
        let lookDuration = ContinuousClock.now - start

        let scaleBeforeZoom = try XCTUnwrap(Self.annotationLayers(in: pdfView).first).contentsScale
        pdfView.scaleFactor *= 2
        start = ContinuousClock.now
        pdfView.annotationLayerResolution.update()
        let zoomLookDuration = ContinuousClock.now - start
        let layers = Self.annotationLayers(in: pdfView)
        let redrawnInOneLook = layers.filter { layer in layer.contentsScale > scaleBeforeZoom * 1.5 }.count
        try await waitUntil("every stroke is drawn again at the zoom by the looks that follow", timeoutSeconds: 60) {
            Self.annotationLayers(in: pdfView).allSatisfy { layer in layer.contentsScale > scaleBeforeZoom * 1.5 }
        }
        let redrawDuration = ContinuousClock.now - start
        print("DenseInkPageMacTests timing: shown sharp \(shownDuration), a look \(lookDuration), a look after the zoom \(zoomLookDuration) "
              + "drawing \(redrawnInOneLook) of \(layers.count) layers, all drawn again in \(redrawDuration)")
        XCTAssertLessThan(shownDuration, .seconds(20), "A page of 6,000 strokes shows sharp soon after opening.")
        XCTAssertLessThan(lookDuration, .milliseconds(60), "A look at the layers, made at every scroll, stays a small part of a frame.")
        XCTAssertLessThan(redrawnInOneLook, layers.count, "One look draws a share of the strokes, not all 6,000 in one frame.")
        XCTAssertLessThan(zoomLookDuration, .milliseconds(60), "A look after the zoom stays a small part of a frame.")
        XCTAssertLessThan(redrawDuration, .seconds(30), "Every stroke is drawn again at the zoom within seconds.")
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

    /// PDFKit's layer for each annotation (`PDFAnnotationLayerResolution`).
    private static func annotationLayers(in view: PDFView?) -> [CALayer] {
        guard let layer = view?.layer else { return [] }
        func layers(under layer: CALayer) -> [CALayer] {
            (NSStringFromClass(type(of: layer)) == PDFAnnotationLayerResolution.annotationLayerClassName ? [layer] : [])
                + (layer.sublayers ?? []).flatMap(layers(under:))
        }
        return layers(under: layer)
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
