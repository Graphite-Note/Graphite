/**
 * File: DenseInkPageMacTests.swift
 * --------------------------------
 * Layer: Tests
 * Description: On the Mac, a page written as densely as a formula sheet (6,000 strokes) is shown, scrolled and zoomed
 *              with its main-thread work within budget; and the annotation layers kept sharp are only those shown.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 12/11/2026
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
/// at a new zoom in 0.39 s.
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

        pdfView.scaleFactor *= 2
        start = ContinuousClock.now
        pdfView.annotationLayerResolution.update()
        let layers = Self.annotationLayers(in: pdfView)
        for layer in layers { layer.displayIfNeeded() }
        let redrawDuration = ContinuousClock.now - start
        print("DenseInkPageMacTests timing: shown sharp \(shownDuration), a look \(lookDuration), "
              + "\(layers.count) layers drawn again at the zoom in \(redrawDuration)")
        XCTAssertLessThan(shownDuration, .seconds(20), "A page of 6,000 strokes shows sharp soon after opening.")
        XCTAssertLessThan(lookDuration, .milliseconds(60), "A look at the layers, made at every scroll, stays a small part of a frame.")
        XCTAssertLessThan(redrawDuration, .seconds(3), "Drawing every stroke again at a new zoom, once when the zoom ends.")
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

/// Stands for PDFKit's annotation layer class.
private final class TestAnnotationLayer: CALayer {}
#endif
