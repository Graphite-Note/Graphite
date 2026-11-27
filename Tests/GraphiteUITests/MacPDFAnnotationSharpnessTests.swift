/**
 * File: MacPDFAnnotationSharpnessTests.swift
 * ------------------------------------------
 * Layer: Tests
 * Description: The Mac's PDF view draws a placed picture and saved Pencil ink at the screen's
 *              resolution, as sharp as PDFKit's own drawing of the page, at fit and zoomed in,
 *              and within its memory bound; saved ink in its page's ink layer since HUNT-357, and ink
 *              drawn with the mouse at one, two and four times fit.
 *
 * Authors: Bahey Shalash
 * Version: 0.3
 * Date: 27/11/2026
 */
import XCTest
import PDFKit
import SwiftUI
import ImageIO
import IOSurface
import UniformTypeIdentifiers
import GraphiteCore
import GraphiteApple
@testable import GraphiteUI

#if os(macOS)
import AppKit
import QuartzCore
import GraphiteTestSupport

/// HUNT-314. PDFKit on macOS draws each annotation into a layer of its own, which it leaves at
/// one pixel per page point: at fit width on a Retina screen a picture or a stroke was drawn
/// from about a third of the pixels the screen shows, while the page's own text was sharp.
///
/// What is measured is what the screen shows: the pixels of the layer's own backing surface
/// (read back through IOSurface), how many of them there are per page point against the
/// screen's pixels per page point, and how many screen pixels a hard edge of the picture or
/// of the ink is spread over. The reference is PDFKit's `PDFPage.draw` of the same page at the
/// screen's resolution, which is what Preview shows.
@MainActor
final class MacPDFAnnotationSharpnessTests: XCTestCase {
    private var vault: TemporaryVault!

    override func setUp() async throws {
        vault = try TemporaryVault.make(prefix: "MacPDFAnnotationSharpness", for: self)
    }

    // MARK: The picture

    /// The reported case: a large picture placed the way the iPad places it now, at 60% of the
    /// page width, saved, opened on the Mac at fit width and at twice fit width.
    func testAPlacedPictureIsDrawnAtTheScreensResolutionAtFitAndZoomedIn() async throws {
        let location = try await makeSavedPDF(withPicture: true, withInk: false)
        let (window, pdfView) = try await show(location)
        defer { window.close() }
        let picture = try XCTUnwrap(pdfView.document?.page(at: 0)?.annotations.first { annotation in annotation.type == PDFPicture.annotationTypeName })

        for zoom in [1.0, 2.0] {
            if zoom != 1 { pdfView.scaleFactor = pdfView.scaleFactor * zoom }
            let measurement = try await settledMeasurement(of: picture, in: pdfView)
            let reference = try referenceEdgeWidth(of: picture, in: pdfView, screenPixelsPerPoint: measurement.screenPixelsPerPoint)
            print("HUNT-314 picture at \(zoom)x fit: layer \(format(measurement.layerPixelsPerPoint)) px/pt, screen \(format(measurement.screenPixelsPerPoint)) px/pt, edge \(format(measurement.edgeWidthOnScreen)) screen px, PDFPage.draw \(format(reference)) screen px")
            XCTAssertGreaterThanOrEqual(measurement.layerPixelsPerPoint, measurement.screenPixelsPerPoint * 0.97,
                                        "At \(zoom)x fit the picture is drawn from as many pixels as the screen shows.")
            XCTAssertLessThanOrEqual(measurement.edgeWidthOnScreen, reference + 0.75,
                                     "At \(zoom)x fit an edge of the picture is as hard as in PDFKit's own drawing of the page.")
        }
    }

    // MARK: The ink

    /// Ink read back from the saved file, drawn from the outline appearance Graphite wrote, in the
    /// page's ink layer since HUNT-357 (`MacPDFPageInkLayers`): its picture holds as many pixels per
    /// point as the screen shows, and a hard edge is as clean as in PDFKit's drawing of the page.
    func testSavedInkIsDrawnAtTheScreensResolutionAtFitAndZoomedIn() async throws {
        try await assertInkIsDrawnAtTheScreensResolution(in: try await makeSavedPDF(withPicture: false, withInk: true), zooms: [1, 2], label: "ink")
    }

    /// Ink drawn with the mouse by the markup row's Draw tool (`MacPDFPointerInkTool`), saved and
    /// opened again: at one, two and four times fit it is drawn at the screen's resolution.
    func testInkDrawnWithTheMouseIsDrawnAtTheScreensResolutionAtOneTwoAndFourTimesFit() async throws {
        let harness = try await MacPDFPageToolHarness.open(for: self, prefix: "MacPDFMouseInkSharpness")
        harness.toolbar.useInkStyle(PDFMarkupInkStyle(color: .black, width: .bold))
        harness.choose(.draw)
        // A slanted line through the row 240 points up the page, as the saved ink above.
        try harness.drag(through: (0...30).map { index in CGPoint(x: 100 + Double(index) * 3, y: 200 + Double(index) * 2.67) })
        try await harness.session.save()
        try await assertInkIsDrawnAtTheScreensResolution(in: harness.location, zooms: [1, 2, 4], label: "mouse ink")
    }

    /// Opens the saved PDF and measures its ink, which crosses the row 240 points up the page, at each zoom of fit.
    private func assertInkIsDrawnAtTheScreensResolution(in location: URL, zooms: [CGFloat], label: String) async throws {
        let (window, pdfView) = try await show(location)
        defer { window.close() }
        let page = try XCTUnwrap(pdfView.document?.page(at: 0))
        let pageBox = page.bounds(for: .cropBox)
        let fitScale = pdfView.scaleFactor

        for zoom in zooms {
            pdfView.scaleFactor = fitScale * zoom
            let screenPixelsPerPoint = pdfView.scaleFactor * (window.backingScaleFactor)
            let shownSize = CGSize(width: pageBox.width * pdfView.scaleFactor, height: pageBox.height * pdfView.scaleFactor)
            guard MacPDFPageInkLayers.fitsInAPicture(MacPDFPageInkLayers.pixelSize(shownSize: shownSize, backingScale: window.backingScaleFactor)) else {
                // Zoomed in too far for one picture: PDFKit draws the stroke in its own layer, sharpened as before HUNT-357.
                let ink = try XCTUnwrap(page.annotations.first { annotation in annotation.type == "Ink" })
                try await waitUntil("PDFKit draws the zoomed page's ink") { !ink.isDrawnByPageInkLayer }
                let measurement = try await settledMeasurement(of: ink, in: pdfView)
                let reference = try referenceEdgeWidth(of: ink, in: pdfView, screenPixelsPerPoint: measurement.screenPixelsPerPoint)
                print("HUNT-314 \(label) at \(zoom)x fit, drawn by PDFKit: layer \(format(measurement.layerPixelsPerPoint)) px/pt, screen \(format(measurement.screenPixelsPerPoint)) px/pt, edge \(format(measurement.edgeWidthOnScreen)) screen px, PDFPage.draw \(format(reference)) screen px")
                XCTAssertGreaterThanOrEqual(measurement.layerPixelsPerPoint, measurement.screenPixelsPerPoint * 0.97,
                                            "At \(zoom)x fit the ink is drawn at the screen's resolution.")
                XCTAssertLessThanOrEqual(measurement.edgeWidthOnScreen, reference + 0.75,
                                         "At \(zoom)x fit the ink's edge is as clean as in PDFKit's own drawing of the page.")
                continue
            }
            var picture: CGImage?
            try await waitUntil("the page's ink is drawn for the zoom") {
                picture = Self.inkPicture(in: pdfView)
                return picture.map { picture in abs(CGFloat(picture.width) - pageBox.width * screenPixelsPerPoint) <= 2 } ?? false
            }
            let shownPicture = try XCTUnwrap(picture)
            let pixelsPerPoint = CGFloat(shownPicture.width) / pageBox.width
            // The stroke's middle, 240 points up the page, in rows from the picture's top.
            let row = Int(((pageBox.maxY - 240) * pixelsPerPoint).rounded())
            let edgeWidth = try Self.averageEdgeWidth(Self.levels(ofRow: row, in: shownPicture))
            // The file's page drawn by PDFKit; the shown page's strokes are drawn by its ink layer.
            let filePage = try XCTUnwrap(PDFDocument(url: location)?.page(at: 0))
            let reference = try referenceEdgeWidth(ofRowAt: 240, on: filePage, screenPixelsPerPoint: screenPixelsPerPoint)
            print("HUNT-314 \(label) at \(zoom)x fit: page layer \(format(pixelsPerPoint)) px/pt, screen \(format(screenPixelsPerPoint)) px/pt, edge \(format(edgeWidth)) screen px, PDFPage.draw \(format(reference)) screen px")
            XCTAssertGreaterThanOrEqual(pixelsPerPoint, screenPixelsPerPoint * 0.97, "At \(zoom)x fit the ink is drawn at the screen's resolution.")
            XCTAssertLessThanOrEqual(edgeWidth, reference + 0.75, "At \(zoom)x fit the ink's edge is as clean as in PDFKit's own drawing of the page.")
        }
    }

    // MARK: Cost

    /// A page written full, as a lecture's worked answer is: 1,500 strokes. Its ink layer draws them
    /// all again at a zoom's resolution off the main thread, once when a zoom ends, quickly.
    func testAPageOfManyStrokesIsDrawnAgainQuickly() async throws {
        let location = vault.location(of: "Written.pdf")
        let revision = try await PDFFileService().create(documentData: PDFTemplateGenerator.documentData(paper: PaperSpecification(template: .blank), pageCount: 1), at: location)
        var strokes: [PortableInkStroke] = []
        for row in 0..<50 {
            for column in 0..<30 {
                let start = CGPoint(x: 20 + Double(column) * 19, y: 30 + Double(row) * 16)
                let outline = [[start, CGPoint(x: start.x + 2, y: start.y), CGPoint(x: start.x + 14, y: start.y + 10), CGPoint(x: start.x + 12, y: start.y + 10)]]
                strokes.append(PortableInkStroke(name: "stroke-\(row)-\(column)", segments: [[CGPoint(x: start.x + 1, y: start.y), CGPoint(x: start.x + 13, y: start.y + 10)]],
                                                 width: 2, red: 0, green: 0, blue: 0, alpha: 1, outline: outline))
            }
        }
        _ = try await PDFFileService().save(url: location, revision: revision, edits: [
            .updateInk(PDFInkUpdate(pageIndex: 0, group: PDFInkGroups.defaultGroup, removal: .strokes([]), addedStrokes: strokes, editableRecord: nil)),
        ])
        let fileData = try Data(contentsOf: location, options: .alwaysMapped)
        let pageBox = try XCTUnwrap(PDFDocument(url: location)?.page(at: 0)).bounds(for: .cropBox)
        // Twice fit width on a Retina screen, about 4.6 pixels per point.
        let pixelsPerPoint: CGFloat = 4.6
        let request = PDFPageInkRequest(fileData: fileData, pageNumber: 1, filePageCount: 1, cropBox: pageBox, rotation: 0,
                                        pixelWidth: Int(pageBox.width * pixelsPerPoint), pixelHeight: Int(pageBox.height * pixelsPerPoint))
        let renderer = PDFPageInkRenderer()
        _ = await renderer.draw(request)
        let start = ContinuousClock.now
        let drawing = await renderer.draw(request)
        let duration = ContinuousClock.now - start
        guard case .picture = drawing else { return XCTFail("The page's ink is drawn.") }
        print("HUNT-314 \(strokes.count) strokes drawn again in the page's ink layer at \(format(pixelsPerPoint)) px/pt in \(duration)")
        XCTAssertLessThan(duration, .milliseconds(500), "Drawing a full page's ink again stays well under a second, off the main thread.")
    }

    // MARK: Memory

    /// Pictures covering a page, zoomed in to eight times fit width: the layers of all the
    /// annotations together stay within the bound, and are never drawn below PDFKit's own
    /// one pixel per point.
    func testDeepZoomOnAPageFullOfPicturesStaysWithinTheMemoryBound() async throws {
        let location = vault.location(of: "Full.pdf")
        let revision = try await PDFFileService().create(documentData: PDFTemplateGenerator.documentData(paper: PaperSpecification(template: .blank), pageCount: 1), at: location)
        let picture = try DrawingPictures.pagePicture(from: try Self.stripedPicture(width: 1_600, height: 1_200, stripeWidth: 40))
        var edits: [PDFEdit] = []
        for row in 0..<4 {
            for column in 0..<2 {
                edits.append(.addPicture(page: 0, picture: PDFPicture(imageData: picture.imageData,
                                                                      bounds: CGRect(x: 10 + column * 290, y: 10 + row * 205, width: 285, height: 200), quarterTurns: 0)))
            }
        }
        _ = try await PDFFileService().save(url: location, revision: revision, edits: edits)
        let (window, pdfView) = try await show(location)
        defer { window.close() }
        pdfView.scaleFactor = pdfView.scaleFactor * 8
        let screenPixelsPerPoint = pdfView.scaleFactor * (window.backingScaleFactor)
        let fitPixelsPerPoint = screenPixelsPerPoint / 8
        // Eight pictures of 285 by 200 points at 26 pixels a point would be 290 megapixels.
        try await waitUntil("the annotations' layers are drawn for the deep zoom") {
            let layers = Self.annotationLayers(in: pdfView)
            return layers.count == 8 && layers.allSatisfy { layer in layer.contentsScale > fitPixelsPerPoint * 1.5 }
        }
        let layers = Self.annotationLayers(in: pdfView)
        let pixelCount = layers.reduce(0.0) { total, layer in total + layer.bounds.width * layer.bounds.height * layer.contentsScale * layer.contentsScale }
        print("HUNT-314 deep zoom: screen \(format(screenPixelsPerPoint)) px/pt, layers \(layers.map { format($0.contentsScale) }), \(format(pixelCount / 1_048_576)) megapixels")
        XCTAssertLessThanOrEqual(pixelCount, CGFloat(PDFAnnotationLayerResolution.maximumPixelCount) * 1.01)
        XCTAssertGreaterThan(pixelCount, CGFloat(PDFAnnotationLayerResolution.maximumPixelCount) * 0.9, "As sharp as the bound allows.")
        XCTAssertTrue(layers.allSatisfy { layer in layer.contentsScale >= 1 })
    }

    // MARK: Making and showing the PDF

    /// Black and white stripes, each `stripeWidth` pixels wide: every stripe's side is a hard edge.
    private static func stripedPicture(width: Int, height: Int, stripeWidth: Int) throws -> Data {
        let colorSpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
                                              bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
        for column in stride(from: 0, to: width, by: stripeWidth * 2) { context.fill(CGRect(x: column, y: 0, width: stripeWidth, height: height)) }
        let output = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try XCTUnwrap(context.makeImage()), nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return output as Data
    }

    /// One page with a 4000 by 3000 picture prepared and placed as `PDFSession.addPicture`
    /// does (its own pixels, 60% of the page wide, in the middle), or a broad stroke whose
    /// saved outline has straight slanted sides.
    private func makeSavedPDF(withPicture: Bool, withInk: Bool) async throws -> URL {
        let location = vault.location(of: "Q3.pdf")
        let revision = try await PDFFileService().create(documentData: PDFTemplateGenerator.documentData(paper: PaperSpecification(template: .blank), pageCount: 1), at: location)
        var edits: [PDFEdit] = []
        if withPicture {
            let prepared = try DrawingPictures.pagePicture(from: try Self.stripedPicture(width: 4_000, height: 3_000, stripeWidth: 40))
            XCTAssertEqual(prepared.pixelSize, CGSize(width: 4_000, height: 3_000), "The file keeps every pixel (HUNT-001).")
            let pageBox = CGRect(x: 0, y: 0, width: 595.28, height: 841.89)
            let width = pageBox.width * PDFSession.newPictureWidthFraction
            let size = CGSize(width: width, height: width * prepared.pixelSize.height / prepared.pixelSize.width)
            let bounds = CGRect(x: pageBox.midX - size.width / 2, y: pageBox.midY - size.height / 2, width: size.width, height: size.height).integral
            edits.append(.addPicture(page: 0, picture: PDFPicture(imageData: prepared.imageData, bounds: bounds, quarterTurns: 0)))
        }
        if withInk {
            // Sides slanted at 45 degrees, as a stroke's edges mostly are: no side lies on the
            // pixel grid, so its softness shows at any resolution.
            let outline = [[CGPoint(x: 100, y: 200), CGPoint(x: 112, y: 200), CGPoint(x: 192, y: 280), CGPoint(x: 180, y: 280)]]
            let stroke = PortableInkStroke(name: "stroke", segments: [[CGPoint(x: 106, y: 200), CGPoint(x: 186, y: 280)]], width: 12,
                                           red: 0, green: 0, blue: 0, alpha: 1, outline: outline)
            edits.append(.updateInk(PDFInkUpdate(pageIndex: 0, group: PDFInkGroups.defaultGroup, removal: .strokes([]), addedStrokes: [stroke], editableRecord: nil)))
        }
        _ = try await PDFFileService().save(url: location, revision: revision, edits: edits)
        return location
    }

    /// The PDF in the Mac's PDF view, in a window that is never shown, as wide as the reported one.
    private func show(_ location: URL) async throws -> (NSWindow, PDFView) {
        let session = try await PDFSession.open(location)
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 1_000, height: 900), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let hostingView = NSHostingView(rootView: GraphitePDFView(session: session, input: PDFAnnotationInput(isEnabled: false, drawsWithFinger: false, showsToolPicker: false)))
        window.contentView = hostingView
        hostingView.layoutSubtreeIfNeeded()
        try await waitUntil("the PDF view is laid out") { (session.pdfView?.frame.height ?? 0) > 0 && !Self.annotationLayers(in: session.pdfView).isEmpty }
        return (window, try XCTUnwrap(session.pdfView))
    }

    // MARK: Measuring

    private struct Measurement {
        let layerPixelsPerPoint: CGFloat
        let screenPixelsPerPoint: CGFloat
        /// Screen pixels a hard edge is spread over, on average.
        let edgeWidthOnScreen: CGFloat
    }

    /// PDFKit's layer for each annotation shown (`PDFAnnotationLayerResolution`).
    private static func annotationLayers(in view: PDFView?) -> [CALayer] {
        guard let layer = view?.layer else { return [] }
        func layers(under layer: CALayer) -> [CALayer] {
            (NSStringFromClass(type(of: layer)) == PDFAnnotationLayerResolution.annotationLayerClassName ? [layer] : [])
                + (layer.sublayers ?? []).flatMap(layers(under:))
        }
        return layers(under: layer)
    }

    /// The layer that shows this annotation: the smallest one around the middle of its bounds.
    private static func layer(showing annotation: PDFAnnotation, in view: PDFView) -> CALayer? {
        let middle = CGPoint(x: annotation.bounds.midX, y: annotation.bounds.midY)
        return annotationLayers(in: view).filter { layer in layer.frame.contains(middle) }.min { first, second in
            first.frame.width * first.frame.height < second.frame.width * second.frame.height
        }
    }

    /// Waits until the annotation's layer has drawn for the current zoom, or for up to three
    /// seconds when it never does, and measures it.
    private func settledMeasurement(of annotation: PDFAnnotation, in view: PDFView) async throws -> Measurement {
        let screenPixelsPerPoint = view.scaleFactor * (view.window?.backingScaleFactor ?? 1)
        let deadline = ContinuousClock.now + .seconds(3)
        var measurement: Measurement?
        try await waitUntil("the annotation's layer is measured") {
            guard let layer = Self.layer(showing: annotation, in: view), let measured = try self.measure(layer, screenPixelsPerPoint: screenPixelsPerPoint) else { return false }
            measurement = measured
            return measured.layerPixelsPerPoint >= screenPixelsPerPoint * 0.97 || ContinuousClock.now > deadline
        }
        return try XCTUnwrap(measurement)
    }

    /// The layer's own pixels: how many there are per page point, and how many of them, along
    /// the middle row, are between dark and light at each hard edge. They are read from the
    /// layer's backing surface when Core Animation names it, and otherwise drawn by the layer
    /// itself into a bitmap of its size at its `contentsScale`, which is what it holds.
    private func measure(_ layer: CALayer, screenPixelsPerPoint: CGFloat) throws -> Measurement? {
        guard layer.contents != nil else { return nil }
        let levels: [Double]
        let layerPixelsPerPoint: CGFloat
        if let surface = Self.surface(of: layer) {
            IOSurfaceLock(surface, .readOnly, nil)
            defer { IOSurfaceUnlock(surface, .readOnly, nil) }
            let width = IOSurfaceGetWidth(surface), height = IOSurfaceGetHeight(surface)
            layerPixelsPerPoint = CGFloat(width) / layer.bounds.width
            let bytesPerElement = IOSurfaceGetBytesPerElement(surface), bytesPerRow = IOSurfaceGetBytesPerRow(surface)
            let rowStart = IOSurfaceGetBaseAddress(surface) + (height / 2) * bytesPerRow
            levels = (0..<width).map { column in
                let element = rowStart + column * bytesPerElement
                switch bytesPerElement {
                case 1: return 1 - Double(element.load(as: UInt8.self)) / 255 // coverage only: dark where it covers
                case 2: return Double(element.load(as: UInt8.self)) / 255
                case 8: return Double(element.load(fromByteOffset: 2, as: Float16.self))
                default: return Double(element.load(fromByteOffset: 1, as: UInt8.self)) / 255
                }
            }
        } else {
            layerPixelsPerPoint = layer.contentsScale
            let width = max(1, Int((layer.bounds.width * layerPixelsPerPoint).rounded())), height = max(1, Int((layer.bounds.height * layerPixelsPerPoint).rounded()))
            guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                          space: try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB)), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
                  let data = context.data else { return nil }
            context.scaleBy(x: layerPixelsPerPoint, y: layerPixelsPerPoint)
            layer.draw(in: context)
            let pixels = data.assumingMemoryBound(to: UInt8.self)
            let row = height / 2
            // Over white paper: what is drawn darkens the page by its coverage.
            levels = (0..<width).map { column in
                let pixel = pixels + (row * width + column) * 4
                let alpha = Double(pixel[3]) / 255
                return 1 - alpha + Double(pixel[1]) / 255
            }
        }
        let edgeWidthInLayerPixels = Self.averageEdgeWidth(levels)
        return Measurement(layerPixelsPerPoint: layerPixelsPerPoint, screenPixelsPerPoint: screenPixelsPerPoint,
                           edgeWidthOnScreen: edgeWidthInLayerPixels * screenPixelsPerPoint / layerPixelsPerPoint)
    }

    /// PDFKit's own drawing of the page at the screen's resolution, measured on the same row.
    private func referenceEdgeWidth(of annotation: PDFAnnotation, in view: PDFView, screenPixelsPerPoint: CGFloat) throws -> CGFloat {
        let page = try XCTUnwrap(annotation.page)
        let layer = try XCTUnwrap(Self.layer(showing: annotation, in: view))
        let rowRectangle = CGRect(x: layer.frame.minX, y: layer.frame.midY, width: layer.frame.width, height: 1)
        let width = Int((rowRectangle.width * screenPixelsPerPoint).rounded(.up)), height = max(1, Int(screenPixelsPerPoint.rounded(.up)))
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                              space: try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB)), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.scaleBy(x: screenPixelsPerPoint, y: screenPixelsPerPoint)
        context.translateBy(x: -rowRectangle.minX, y: -rowRectangle.minY)
        context.interpolationQuality = .high
        page.draw(with: .mediaBox, to: context)
        let pixels = try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self)
        let levels = (0..<width).map { column in Double(pixels[column * 4 + 1]) / 255 }
        return Self.averageEdgeWidth(levels)
    }

    /// The picture of page 0's ink its layer shows (`MacPDFPageInkLayers`).
    private static func inkPicture(in view: NSView) -> CGImage? {
        for subview in view.subviews {
            if let inkView = subview as? MacPDFPageInkView, let picture = inkView.picture { return picture }
            if let picture = inkPicture(in: subview) { return picture }
        }
        return nil
    }

    /// How light each pixel of a row of the picture is over white paper, from 0 to 1.
    private static func levels(ofRow row: Int, in picture: CGImage) throws -> [Double] {
        let width = picture.width, height = picture.height
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                              space: try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB)), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.draw(picture, in: CGRect(x: 0, y: 0, width: width, height: height))
        let pixels = try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self)
        let clampedRow = min(max(0, row), height - 1)
        return (0..<width).map { column in Double(pixels[(clampedRow * width + column) * 4 + 1]) / 255 }
    }

    /// PDFKit's own drawing of the page's row `pageY` points up, at the screen's resolution.
    private func referenceEdgeWidth(ofRowAt pageY: CGFloat, on page: PDFPage, screenPixelsPerPoint: CGFloat) throws -> CGFloat {
        let pageBox = page.bounds(for: .cropBox)
        let width = Int((pageBox.width * screenPixelsPerPoint).rounded(.up)), height = max(1, Int(screenPixelsPerPoint.rounded(.up)))
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                              space: try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB)), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.scaleBy(x: screenPixelsPerPoint, y: screenPixelsPerPoint)
        context.translateBy(x: -pageBox.minX, y: -(pageBox.minY + pageY))
        context.interpolationQuality = .high
        page.draw(with: .cropBox, to: context)
        let pixels = try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self)
        return Self.averageEdgeWidth((0..<width).map { column in Double(pixels[column * 4 + 1]) / 255 })
    }

    /// Pixels between 15% and 85% of the way from dark to light, per edge crossed.
    private static func averageEdgeWidth(_ levels: [Double]) -> CGFloat {
        var edgeCount = 0, betweenCount = 0
        var lastSide: Bool?
        for level in levels {
            if level > 0.15 && level < 0.85 { betweenCount += 1; continue }
            let side = level >= 0.85
            if let lastSide, lastSide != side { edgeCount += 1 }
            lastSide = side
        }
        return edgeCount == 0 ? .infinity : CGFloat(betweenCount) / CGFloat(edgeCount)
    }

    /// The IOSurface that holds a layer's pixels, which Core Animation names in the
    /// description of the layer's backing store.
    private static func surface(of layer: CALayer) -> IOSurfaceRef? {
        guard let contents = layer.contents else { return nil }
        if CFGetTypeID(contents as CFTypeRef) == IOSurfaceGetTypeID() { return (contents as! IOSurfaceRef) }
        let description = String(describing: CFCopyDescription(contents as CFTypeRef))
        guard let range = description.range(of: "surface 0x"), let identifier = UInt32(description[range.upperBound...].prefix { character in character.isHexDigit }, radix: 16) else { return nil }
        return IOSurfaceLookup(identifier)
    }

    private func format(_ value: CGFloat) -> String { String(format: "%.2f", Double(value)) }
}
#endif
