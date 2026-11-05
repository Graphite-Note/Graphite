/**
 * File: PDFPageSharpnessHostedTests.swift
 * ---------------------------------------
 * Layer: Tests
 * Description: The iPad's PDF view shows a page's own text, a placed picture and the page's ink as
 *              sharp as PDFKit's own drawing of the page at the screen's resolution, at fit and
 *              zoomed in, and prints what it measured.
 *
 * Authors: Bahey Shalash
 * Version: 0.5
 * Date: 05/11/2026
 */
#if os(iOS)
import XCTest
import SwiftUI
import PDFKit
import PencilKit
import ImageIO
import IOSurface
import UniformTypeIdentifiers
import GraphiteCore
import GraphiteApple
@testable import GraphiteUI

/// HUNT-320. The owner saw PDFs pixelated on the iPad that Preview shows sharp. What is measured
/// is what the screen shows (the window drawn with `drawHierarchy` at the screen's scale): how
/// many screen pixels a hard edge is spread over along one row, against PDFKit's `PDFPage.draw`
/// of the same row of the page at the same pixels per point, which is what Preview shows. Each
/// case prints `PDF-SHARP` lines with the numbers, so a run on a device tells them.
@MainActor
final class PDFPageSharpnessHostedTests: XCTestCase {
    private static let pageSize = CGSize(width: 595.28, height: 841.89)
    private static let textFont = UIFont.systemFont(ofSize: 24)
    private static let textOrigin = CGPoint(x: 40, y: 90)
    private static let text = "Rank 0 (front of a DIMM) Local Row Buffer"
    private static let zoomsOfFit: [CGFloat] = [1, 2, 4]

    private var temporaryLocations: [URL] = []
    /// The session of the PDF `show` showed last.
    private var shownSession: PDFSession?

    override func tearDown() async throws {
        for location in temporaryLocations { try? FileManager.default.removeItem(at: location) } // A file left in the temporary folder harms nothing.
        temporaryLocations = []
        shownSession = nil
    }

    // MARK: The page's own text

    /// The page's own drawing is PDFKit's tiles: as sharp as `PDFPage.draw` at every zoom.
    func testThePagesOwnTextIsAsSharpAsPDFKitDrawsItAtFitAndZoomedIn() async throws {
        let (pdfView, window) = try await show(try await makePDF(pageCount: 1, withPicture: false))
        defer { window.isHidden = true; window.rootViewController = nil }
        let page = try XCTUnwrap(pdfView.document?.page(at: 0))
        let textSize = (Self.text as NSString).size(withAttributes: [.font: Self.textFont])
        let rowY = Self.pageSize.height - (Self.textOrigin.y + Self.textFont.ascender - Self.textFont.xHeight / 2)
        let fit = pdfView.scaleFactor
        pdfView.autoScales = false
        for zoomOfFit in Self.zoomsOfFit {
            let row = CGRect(x: Self.textOrigin.x, y: rowY, width: textSize.width, height: 0)
            let measured = try await settledEdgeWidths(along: row, of: page, in: pdfView, window: window, zoom: fit * zoomOfFit)
            print("PDF-SHARP text at \(format(zoomOfFit))x fit (zoom \(format(pdfView.scaleFactor)), \(format(measured.screenPixelsPerPoint)) px/pt): screen \(format(measured.onScreen)) px, PDFPage.draw \(format(measured.reference)) px")
            XCTAssertLessThanOrEqual(measured.onScreen, measured.reference + 0.75, "The page's text at \(zoomOfFit)x fit is as sharp as PDFKit draws it")
            print("PDF-SHARP text at zoom \(format(pdfView.scaleFactor)): PDFKit's tiles drawn at \(Self.tileScales(in: pdfView)) px/pt; the page's corner \(Self.pageCornerInScreenPixels(of: page, in: pdfView, window: window)) screen pixels from the window's")
        }
    }

    // MARK: A placed picture

    /// A picture placed on the page is a stamp PDFKit draws into a layer of its own, which it
    /// left at one pixel per page point while the page's tiles follow the screen, as on the Mac
    /// (HUNT-314). Measured first as PDFKit leaves it, then with Graphite's resolution.
    func testAPlacedPictureIsAsSharpAsPDFKitDrawsThePageAtFitAndZoomedIn() async throws {
        let (pdfView, window) = try await show(try await makePDF(pageCount: 1, withPicture: true))
        defer { window.isHidden = true; window.rootViewController = nil }
        let page = try XCTUnwrap(pdfView.document?.page(at: 0))
        let picture = try XCTUnwrap(page.annotations.first { annotation in annotation.type == PDFPicture.annotationTypeName })
        let resolution = pdfView.annotationLayerResolution
        let fit = pdfView.scaleFactor
        pdfView.autoScales = false
        let row = CGRect(x: picture.bounds.minX + 4, y: picture.bounds.midY, width: picture.bounds.width - 8, height: 0)
        for zoomOfFit in Self.zoomsOfFit {
            resolution.stop()
            pdfView.scaleFactor = min(max(fit * zoomOfFit, pdfView.minScaleFactor), pdfView.maxScaleFactor)
            let pdfKitScales = try await layerScalesAsPDFKitDrawsThem(on: page, in: pdfView)
            let before = try await settledEdgeWidths(along: row, of: page, in: pdfView, window: window, zoom: fit * zoomOfFit)
            resolution.start()
            try await waitUntil("the picture's layer is drawn at the screen's resolution") {
                Self.annotationLayers(in: pdfView).allSatisfy { layer in layer.contentsScale >= self.wantedScale(of: layer, in: window) * 0.97 }
            }
            let after = try await settledEdgeWidths(along: row, of: page, in: pdfView, window: window, zoom: fit * zoomOfFit)
            let afterScales = Self.annotationLayers(in: pdfView).map { layer in format(layer.contentsScale) }
            print("PDF-SHARP picture at \(format(zoomOfFit))x fit (zoom \(format(pdfView.scaleFactor)), \(format(after.screenPixelsPerPoint)) px/pt): PDFKit's layers \(pdfKitScales) px/pt, edge \(format(before.onScreen)) px; Graphite's layers \(afterScales) px/pt, edge \(format(after.onScreen)) px; PDFPage.draw \(format(after.reference)) px")
            let pictureLayers = Self.annotationLayers(in: pdfView).filter(PDFAnnotationLayerResolution.showsAPicture)
            try await reportWhatTheScreenShows(of: pictureLayers, along: row, of: page, in: pdfView, window: window, label: "\(format(zoomOfFit))x fit")
            XCTAssertLessThanOrEqual(after.onScreen, after.reference + 0.75, "The picture at \(zoomOfFit)x fit is as sharp as PDFKit draws the page")
            XCTAssertFalse(pictureLayers.isEmpty, "The picture's layer is known as a picture's")
            XCTAssertTrue(pictureLayers.allSatisfy { layer in !layer.drawsAsynchronously }, "Core Graphics draws the picture, as PDFPage.draw does")
            try await reportTheRecordedDrawing(of: pictureLayers, along: row, of: page, in: pdfView, window: window, zoom: fit * zoomOfFit)
        }
    }

    /// Prints what Core Animation is given to show for the picture, and the edge in the layer's own pixels and on
    /// screen, below the window's bars. On the owner's iPad (2026-11-05) the layer held 2,848 by 2,144 sharp pixels at
    /// 7.91 px/pt at twice fit (edge 0.82 in its own pixels) while the screen measured 16.07: the row measured lay at
    /// 109 points, under the 130-point glass of the navigation and tab bars, which blurs what is under it; hiding any
    /// layer under the row, drawing it again, at a whole scale or with other filters changed nothing (HUNT-320).
    private func reportWhatTheScreenShows(of pictureLayers: [CALayer], along row: CGRect, of page: PDFPage, in pdfView: PDFView, window: UIWindow, label: String) async throws {
        guard let layer = pictureLayers.first else { return }
        let shownRow = shownPart(of: row, on: page, in: pdfView)
        let onScreen = try edgeWidthOnScreen(along: shownRow, of: page, in: pdfView, window: window)
        let ownPixels = try Self.edgeWidthInOwnPixels(of: layer)
        let rowInWindow = pdfView.convert(pdfView.convert(CGPoint(x: shownRow.midX, y: shownRow.midY), from: page), to: window)
        print("PDF-SHARP layers at \(label): screen edge \(format(onScreen)) px, own pixels edge \(format(ownPixels)) px, row at \(format(rowInWindow.y)) pt below the bars' \(format(pdfView.safeAreaInsets.top)); " + Self.describe(layer, in: window))
        XCTAssertLessThanOrEqual(ownPixels, 1.5, "The picture's layer holds sharp pixels at \(label)")
    }

    /// One line about a layer: its class, size, place on screen, resolution, contents, and what Core Animation does to it.
    private static func describe(_ layer: CALayer, in window: UIWindow) -> String {
        let frame = layer.convert(layer.bounds, to: window.layer)
        let transform = layer.transform, sublayerTransform = layer.sublayerTransform
        return "\(type(of: layer)) bounds \(Self.rounded(layer.bounds.size)) on screen \(Self.rounded(frame.size)) at \(Self.rounded(frame.origin)), "
            + "scale \(String(format: "%.2f", Double(layer.contentsScale))), contents \(contentsDescription(layer.contents)), "
            + "rasterize \(layer.shouldRasterize) \(String(format: "%.2f", Double(layer.rasterizationScale))), filters \(layer.magnificationFilter.rawValue)/\(layer.minificationFilter.rawValue), "
            + "transform \(String(format: "%.3f", Double(transform.m11))) sublayers \(String(format: "%.3f", Double(sublayerTransform.m11))), "
            + "hidden \(layer.isHidden) opacity \(layer.opacity), async \(layer.drawsAsynchronously), format \(layer.contentsFormat.rawValue), "
            + "rect \(layer.contentsRect), gravity \(layer.contentsGravity.rawValue), filters \(layer.filters?.count ?? 0), mask \(layer.mask != nil), delegate \(layer.delegate.map { String(describing: type(of: $0)) } ?? "none")"
    }

    private static func rounded(_ size: CGSize) -> String { "\(Int(size.width.rounded()))x\(Int(size.height.rounded()))" }
    private static func rounded(_ point: CGPoint) -> String { "(\(Int(point.x.rounded())), \(Int(point.y.rounded())))" }

    /// What a layer's contents are and how many pixels they hold.
    private static func contentsDescription(_ contents: Any?) -> String {
        guard let contents else { return "none" }
        let object = contents as CFTypeRef
        if CFGetTypeID(object) == CGImage.typeID {
            let image = unsafeDowncast(contents as AnyObject, to: CGImage.self)
            return "CGImage \(image.width)x\(image.height)"
        }
        if CFGetTypeID(object) == IOSurfaceGetTypeID() {
            let surface = unsafeDowncast(contents as AnyObject, to: IOSurface.self)
            return "IOSurface \(surface.width)x\(surface.height)"
        }
        return "\(type(of: contents)) " + String(String(describing: contents).prefix(140))
    }

    /// The edge along the layer's middle row in its own pixels, as Core Animation holds them (`render(in:)`).
    private static func edgeWidthInOwnPixels(of layer: CALayer) throws -> CGFloat {
        let scale = layer.contentsScale
        let width = max(1, Int((layer.bounds.width * scale).rounded(.up))), height = 3
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                              space: try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB)), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.translateBy(x: 0, y: CGFloat(height) / 2)
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: -layer.bounds.minX, y: -layer.bounds.midY)
        layer.render(in: context)
        return averageEdgeWidth(try greenLevels(ofMiddleRowOf: try XCTUnwrap(context.makeImage())))
    }

    /// Prints how long Core Graphics takes to draw the picture's layers, and what the screen shows
    /// when Core Animation renders their recorded drawing instead, as PDFKit sets them up, which
    /// left the picture soft at twice fit on the owner's iPad; then draws them as Graphite does.
    private func reportTheRecordedDrawing(of pictureLayers: [CALayer], along row: CGRect, of page: PDFPage, in pdfView: PDFView, window: UIWindow, zoom: CGFloat) async throws {
        // Core Graphics's drawing of each layer, timed into a bitmap of the layer's own pixels.
        var drawingTime = Duration.zero
        for layer in pictureLayers {
            let width = Int((layer.bounds.width * layer.contentsScale).rounded(.up)), height = Int((layer.bounds.height * layer.contentsScale).rounded(.up))
            let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                                  space: try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB)), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.scaleBy(x: layer.contentsScale, y: layer.contentsScale)
            drawingTime += ContinuousClock().measure { layer.draw(in: context) }
        }
        for layer in pictureLayers { layer.drawsAsynchronously = true; layer.setNeedsDisplay() }
        let recorded = try await settledEdgeWidths(along: row, of: page, in: pdfView, window: window, zoom: zoom)
        for layer in pictureLayers { layer.drawsAsynchronously = false; layer.setNeedsDisplay() }
        let milliseconds = Double(drawingTime.components.seconds) * 1_000 + Double(drawingTime.components.attoseconds) / 1e15
        print("PDF-SHARP picture at zoom \(format(pdfView.scaleFactor)): Core Graphics drew it in \(format(CGFloat(milliseconds))) ms; recorded and rendered by Core Animation, edge \(format(recorded.onScreen)) px")
    }

    /// The page's annotations taken off and put back, with Graphite's resolution stopped, so
    /// PDFKit makes their layers anew as it makes them for any page: what the iPad showed
    /// before HUNT-320. Returns the pixels per point PDFKit gave them.
    private func layerScalesAsPDFKitDrawsThem(on page: PDFPage, in pdfView: PDFView) async throws -> [String] {
        let oldLayers = Set(Self.annotationLayers(in: pdfView).map(ObjectIdentifier.init))
        for annotation in page.annotations {
            page.removeAnnotation(annotation)
            page.addAnnotation(annotation)
        }
        try await waitUntil("PDFKit makes the annotations' layers again") {
            let layers = Self.annotationLayers(in: pdfView)
            return !layers.isEmpty && layers.allSatisfy { layer in !oldLayers.contains(ObjectIdentifier(layer)) && layer.contents != nil }
        }
        return Self.annotationLayers(in: pdfView).map { layer in format(layer.contentsScale) }
    }

    // MARK: The page's ink, zoomed far in

    /// Settled ink is the page's Pencil canvas, drawn at the zoom. A canvas the size of the page
    /// took more pixels than a page may past about 4.2 times on A4 at 2x, and it then drew the
    /// whole page at that scale, magnified to the zoom. Now it draws the part of the page around
    /// the screen at the zoom. Each zoom is measured both ways: as it drew before (the whole
    /// page at the largest scale within the bound) and as it draws now, with the canvas's
    /// pixels, which stay within the bound.
    func testSettledInkZoomedFarInIsDrawnAtTheZoomWithinTheBound() async throws {
        let location = try makeHostedBlankNotebook(named: "DeepZoomInk")
        temporaryLocations.append(location)
        let (pdfView, window) = try await show(location)
        defer { window.isHidden = true; window.rootViewController = nil }
        let page = try XCTUnwrap(pdfView.document?.page(at: 0))
        let coordinator = try XCTUnwrap(pdfView.annotationCoordinator)
        try await waitUntil("the page's canvas") { coordinator.editingCanvas(for: page)?.overlayView != nil }
        let canvas = try XCTUnwrap(coordinator.editingCanvas(for: page))
        let overlay = try XCTUnwrap(canvas.overlayView)
        var points: [PKStrokePoint] = []
        for step in 0...40 {
            points.append(PKStrokePoint(location: CGPoint(x: 100 + CGFloat(step) * 10, y: 300), timeOffset: Double(step) / 60, size: CGSize(width: 4, height: 4),
                                        opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2))
        }
        canvas.drawing = PKDrawing(strokes: [PKStroke(ink: PKInk(.monoline, color: .black), path: PKStrokePath(controlPoints: points, creationDate: Date()))])
        pdfView.autoScales = false
        let pageSize = page.bounds(for: .cropBox).size
        let screenScale = window.traitCollection.displayScale
        let largestWholePageScale = (PDFCanvasShownRegion.maximumCanvasPixelCount / (pageSize.width * pageSize.height * screenScale * screenScale)).squareRoot()

        func softness(atZoom zoom: CGFloat, drawnAt scale: CGFloat?) async throws -> (rows: Double, pixelCount: CGFloat) {
            if abs(pdfView.scaleFactor - zoom) > 0.001 {
                pdfView.scaleFactor = zoom
                try await waitUntil("the canvas draws at \(zoom)") { abs(canvas.zoomScale - pdfView.scaleFactor) < 0.02 }
            }
            overlay.setRenderingScale(scale ?? PDFPageOverlayView.renderingScale(forZoom: pdfView.scaleFactor))
            overlay.layoutIfNeeded()
            pdfView.go(to: CGRect(x: 296, y: pageSize.height - 304, width: 8, height: 8), on: page)
            var lastRows = -1.0
            var rows = 0.0
            try await waitUntil("the ink shows the same twice", pollingIntervalSeconds: 0.3) {
                let point = canvas.convert(CGPoint(x: 300 * canvas.zoomScale, y: 300 * canvas.zoomScale), to: window)
                rows = try self.softEdgeRows(in: window, atWindowPoint: point)
                defer { lastRows = rows }
                return abs(rows - lastRows) < 0.01
            }
            return (rows, canvas.bounds.width * canvas.bounds.height * screenScale * screenScale)
        }

        let atTwo = try await softness(atZoom: 2, drawnAt: nil)
        print("PDF-SHARP ink at zoom 2: \(format(CGFloat(atTwo.rows))) rows, canvas \(format(atTwo.pixelCount / 1_000_000)) megapixels; whole page fits up to \(format(largestWholePageScale))")
        for zoom: CGFloat in [3.3, 6, 8] where zoom <= pdfView.maxScaleFactor {
            let before = try await softness(atZoom: zoom, drawnAt: zoom > largestWholePageScale ? largestWholePageScale : nil)
            let after = try await softness(atZoom: zoom, drawnAt: nil)
            print("PDF-SHARP ink at zoom \(format(zoom)): before \(format(CGFloat(before.rows))) rows (scale \(format(min(zoom, largestWholePageScale))), \(format(before.pixelCount / 1_000_000)) megapixels), after \(format(CGFloat(after.rows))) rows (scale \(format(canvas.zoomScale)), region \(overlay.shownRegion), \(format(after.pixelCount / 1_000_000)) megapixels)")
            XCTAssertEqual(canvas.zoomScale, zoom, accuracy: 0.02, "The canvas draws at the zoom \(zoom)")
            XCTAssertLessThanOrEqual(after.pixelCount, PDFCanvasShownRegion.maximumCanvasPixelCount * 1.01, "Within the bound at \(zoom)")
            XCTAssertLessThanOrEqual(after.rows, before.rows + 0.1, "No softer than before at \(zoom)")
            if zoom > largestWholePageScale * 1.4 { XCTAssertLessThan(after.rows, before.rows, "Sharper than the magnified canvas at \(zoom)") }
        }
        XCTAssertEqual(canvas.drawingSize.width, pageSize.width, accuracy: 0.5, "The drawing keeps the page's points")
    }

    /// How many rows of a column of the window cross a stroke's edge, neither page nor ink: the
    /// softness of what is on screen, in the screen's pixels (as `InkWidthAtZoomTests` measures).
    private func softEdgeRows(in window: UIWindow, atWindowPoint point: CGPoint) throws -> Double {
        let area = CGRect(x: point.x - 1, y: point.y - 30, width: 2, height: 60)
        let format = UIGraphicsImageRendererFormat()
        format.scale = window.traitCollection.displayScale
        let picture = UIGraphicsImageRenderer(bounds: area, format: format).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let image = try XCTUnwrap(picture.cgImage)
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = try XCTUnwrap(CGContext(data: &bytes, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                              space: XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB)), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let reds = (0..<image.height).map { row in Double(bytes[row * image.width * 4]) }
        guard let darkest = reds.min(), let lightest = reds.max(), lightest > darkest else { return 0 }
        return reds.reduce(0) { softness, red in softness + 2 * min(red - darkest, lightest - red) / (lightest - darkest) }
    }

    // MARK: A text box with emoji

    /// A text box with emoji is a picture of its own over the page. It was made for a zoom of 3
    /// at most and magnified past that; now it is drawn at the zoom times the screen's scale once
    /// the zoom settles, within its 16 megapixels.
    func testATextBoxWithEmojiIsDrawnAtTheZoomsResolutionOnceTheZoomSettles() async throws {
        let location = try makeHostedBlankNotebook(named: "EmojiTextBox")
        temporaryLocations.append(location)
        let (pdfView, window) = try await show(location)
        defer { window.isHidden = true; window.rootViewController = nil }
        let page = try XCTUnwrap(pdfView.document?.page(at: 0))
        let coordinator = try XCTUnwrap(pdfView.annotationCoordinator)
        try await waitUntil("the page's canvas") { coordinator.editingCanvas(for: page)?.overlayView != nil }
        let canvas = try XCTUnwrap(coordinator.editingCanvas(for: page))
        let overlay = try XCTUnwrap(canvas.overlayView)
        let cropBox = page.bounds(for: .cropBox)
        let box = PDFTextBox(name: "emoji", runs: [PDFTextRun(text: "Rank 0 \u{1F600}", attributes: .plain)],
                             origin: CGPoint(x: cropBox.minX + 100, y: cropBox.maxY - 200), width: 220, height: 40)
        let session = try XCTUnwrap(shownSession)
        try session.changeTextBox(from: nil, to: box, on: PDFHistoryPage(page), actionName: "Add Text Box")
        func pictureLayer() -> PDFTextBoxPictureLayer? {
            func layers(under layer: CALayer) -> [CALayer] { [layer] + (layer.sublayers ?? []).flatMap(layers(under:)) }
            return layers(under: overlay.textBoxesView.layer).lazy.compactMap { layer in layer as? PDFTextBoxPictureLayer }.first
        }
        let screenScale = window.traitCollection.displayScale
        pdfView.autoScales = false
        for zoom: CGFloat in [1, 2, 5, 8] where zoom <= pdfView.maxScaleFactor {
            pdfView.scaleFactor = zoom
            try await waitUntil("the canvas draws at \(zoom)") { abs(canvas.zoomScale - zoom) < 0.02 }
            let layer = try XCTUnwrap(pictureLayer(), "The box with emoji is drawn as a picture")
            let wanted = PDFTextBoxPictureLayer.boundedScale(forPixelsPerPoint: zoom * screenScale, size: layer.bounds.size)
            let before = PDFTextBoxPictureLayer.boundedScale(forPixelsPerPoint: screenScale * 3, size: layer.bounds.size)
            try await waitUntil("the box is drawn at the zoom's resolution") { abs(layer.contentsScale - wanted) <= wanted * 0.02 }
            let pixelCount = layer.bounds.width * layer.bounds.height * layer.contentsScale * layer.contentsScale
            print("PDF-SHARP emoji text box at zoom \(format(zoom)): screen \(format(zoom * screenScale)) px/pt, drawn at \(format(layer.contentsScale)) px/pt (before HUNT-320 \(format(before))), \(format(pixelCount / 1_000_000)) megapixels")
            XCTAssertGreaterThanOrEqual(layer.contentsScale, min(zoom * screenScale, wanted) * 0.98, "As many pixels as the screen shows at \(zoom)")
            XCTAssertLessThanOrEqual(pixelCount, PDFTextBoxPictureLayer.maximumPixelCount * 1.01, "Within the box's bound at \(zoom)")
        }
    }

    // MARK: Making and showing the PDF

    /// A page of text drawn into the PDF itself, and a picture of hard black and white stripes
    /// placed on it as `PDFSession.addPicture` places one: its own pixels, 60% of the page wide.
    private func makePDF(pageCount: Int, withPicture: Bool) async throws -> URL {
        let location = hostedTemporaryLocation(named: "PageSharpness").appendingPathExtension("pdf")
        temporaryLocations.append(location)
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: Self.pageSize))
        let documentData = renderer.pdfData { context in
            for _ in 0..<pageCount {
                context.beginPage()
                (Self.text as NSString).draw(at: Self.textOrigin, withAttributes: [.font: Self.textFont, .foregroundColor: UIColor.black])
            }
        }
        let service = PDFFileService()
        let revision = try await service.create(documentData: documentData, at: location)
        guard withPicture else { return location }
        let prepared = try DrawingPictures.pagePicture(from: try Self.stripedPicture(width: 4_000, height: 3_000, stripeWidth: 40))
        let width = Self.pageSize.width * PDFSession.newPictureWidthFraction
        let size = CGSize(width: width, height: width * prepared.pixelSize.height / prepared.pixelSize.width)
        let bounds = CGRect(x: (Self.pageSize.width - size.width) / 2, y: (Self.pageSize.height - size.height) / 2, width: size.width, height: size.height).integral
        _ = try await service.save(url: location, revision: revision, edits: (0..<pageCount).map { pageIndex in
            .addPicture(page: pageIndex, picture: PDFPicture(imageData: prepared.imageData, bounds: bounds, quarterTurns: 0))
        })
        return location
    }

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

    /// The PDF in the PDF pane, in a window filling the screen, as the owner reads it.
    private func show(_ location: URL) async throws -> (GraphitePDFDisplayView, UIWindow) {
        let session = try await PDFSession.open(location)
        shownSession = session
        let controller = UIHostingController(rootView: NavigationStack { PDFPane(session: session, resolveConflict: { _ in }) })
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.effectiveGeometry.coordinateSpace.bounds
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()
        try await waitUntil("the PDF view shows its page") {
            guard let pdfView = session.pdfView as? GraphitePDFDisplayView else { return false }
            return pdfView.window != nil && pdfView.bounds.width > 0 && pdfView.scaleFactor > 0
        }
        return (try XCTUnwrap(session.pdfView as? GraphitePDFDisplayView), window)
    }

    // MARK: Measuring

    private struct EdgeWidths {
        let screenPixelsPerPoint: CGFloat
        /// Screen pixels a hard edge is spread over along the row, on average.
        let onScreen: CGFloat
        /// The same for PDFKit's `PDFPage.draw` of the row at the same pixels per point.
        let reference: CGFloat
    }

    /// Zooms the view, brings the row's middle on screen, waits until what the screen shows of
    /// the row stops changing (PDFKit has drawn its tiles and layers for the zoom), and measures.
    private func settledEdgeWidths(along row: CGRect, of page: PDFPage, in pdfView: PDFView, window: UIWindow, zoom: CGFloat) async throws -> EdgeWidths {
        pdfView.scaleFactor = min(max(zoom, pdfView.minScaleFactor), pdfView.maxScaleFactor)
        // The row in the middle of the view, well below the bars over its top: there the bars' glass blurred the
        // picture measured at twice fit (HUNT-320).
        let halfShownHeight = pdfView.bounds.height * 0.45 / max(pdfView.scaleFactor, 0.01)
        pdfView.go(to: CGRect(x: row.midX - 1, y: row.midY - halfShownHeight, width: 2, height: 2 * halfShownHeight), on: page)
        var lastOnScreen: CGFloat = -1
        var measured: EdgeWidths?
        try await waitUntil("the row shows the same twice", pollingIntervalSeconds: 0.3) {
            let shownRow = self.shownPart(of: row, on: page, in: pdfView)
            let onScreen = try self.edgeWidthOnScreen(along: shownRow, of: page, in: pdfView, window: window)
            defer { lastOnScreen = onScreen }
            guard abs(onScreen - lastOnScreen) < 0.01 else { return false }
            let screenPixelsPerPoint = pdfView.scaleFactor * window.traitCollection.displayScale
            let rowInWindow = pdfView.convert(pdfView.convert(CGPoint(x: shownRow.midX, y: shownRow.midY), from: page), to: window)
            XCTAssertGreaterThan(rowInWindow.y, pdfView.convert(CGPoint(x: 0, y: pdfView.safeAreaInsets.top), to: window).y,
                                 "The row measured is below the bars over the page's top")
            measured = EdgeWidths(screenPixelsPerPoint: screenPixelsPerPoint, onScreen: onScreen,
                                  reference: try self.referenceEdgeWidth(along: shownRow, of: page, screenPixelsPerPoint: screenPixelsPerPoint))
            return true
        }
        return try XCTUnwrap(measured)
    }

    /// The part of a row of the page that is on screen, kept 8 points inside the view's edges.
    private func shownPart(of row: CGRect, on page: PDFPage, in pdfView: PDFView) -> CGRect {
        let visible = pdfView.convert(pdfView.bounds.insetBy(dx: 8, dy: 8), to: page)
        let minimumX = max(row.minX, visible.minX), maximumX = min(row.maxX, visible.maxX)
        return CGRect(x: minimumX, y: row.minY, width: max(0, maximumX - minimumX), height: 0)
    }

    /// The screen's pixels along the row, from the window as it is shown.
    private func edgeWidthOnScreen(along row: CGRect, of page: PDFPage, in pdfView: PDFView, window: UIWindow) throws -> CGFloat {
        let start = pdfView.convert(pdfView.convert(CGPoint(x: row.minX, y: row.minY), from: page), to: window)
        let end = pdfView.convert(pdfView.convert(CGPoint(x: row.maxX, y: row.minY), from: page), to: window)
        let screenScale = window.traitCollection.displayScale
        let area = CGRect(x: min(start.x, end.x), y: start.y - 1 / screenScale, width: abs(end.x - start.x), height: 2 / screenScale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = screenScale
        let picture = UIGraphicsImageRenderer(bounds: area, format: format).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        return Self.averageEdgeWidth(try Self.greenLevels(ofMiddleRowOf: try XCTUnwrap(picture.cgImage)))
    }

    /// PDFKit's own drawing of the row at the screen's pixels per point, as Preview shows it.
    private func referenceEdgeWidth(along row: CGRect, of page: PDFPage, screenPixelsPerPoint: CGFloat) throws -> CGFloat {
        let width = max(1, Int((row.width * screenPixelsPerPoint).rounded(.up))), height = 3
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                              space: try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB)), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.translateBy(x: 0, y: CGFloat(height) / 2)
        context.scaleBy(x: screenPixelsPerPoint, y: screenPixelsPerPoint)
        context.translateBy(x: -row.minX, y: -row.minY)
        context.interpolationQuality = .high
        page.draw(with: .cropBox, to: context)
        let image = try XCTUnwrap(context.makeImage())
        return Self.averageEdgeWidth(try Self.greenLevels(ofMiddleRowOf: image))
    }

    private static func greenLevels(ofMiddleRowOf image: CGImage) throws -> [Double] {
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = try XCTUnwrap(CGContext(data: &bytes, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                              space: XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB)), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let row = image.height / 2
        return (0..<image.width).map { column in Double(bytes[(row * image.width + column) * 4 + 1]) / 255 }
    }

    /// Pixels between 15% and 85% of the way from dark to light, per edge crossed; as
    /// `MacPDFAnnotationSharpnessTests` measures.
    private static func averageEdgeWidth(_ levels: [Double]) -> CGFloat {
        guard let darkest = levels.min(), let lightest = levels.max(), lightest - darkest > 0.3 else { return .infinity }
        var edgeCount = 0, betweenCount = 0
        var lastSide: Bool?
        for level in levels {
            let fraction = (level - darkest) / (lightest - darkest)
            if fraction > 0.15 && fraction < 0.85 { betweenCount += 1; continue }
            let side = fraction >= 0.85
            if let lastSide, lastSide != side { edgeCount += 1 }
            lastSide = side
        }
        return edgeCount == 0 ? .infinity : CGFloat(betweenCount) / CGFloat(edgeCount)
    }

    /// The pixels per point of PDFKit's tiles of the page's own drawing, each value once.
    private static func tileScales(in pdfView: PDFView) -> [String] {
        var scales: Set<String> = []
        func look(under layer: CALayer) {
            for sublayer in layer.sublayers ?? [] {
                if String(describing: type(of: sublayer)) == "PDFPageLayerTile" { scales.insert(String(format: "%.2f", Double(sublayer.contentsScale))) } else { look(under: sublayer) }
            }
        }
        if let documentLayer = pdfView.documentView?.layer { look(under: documentLayer) }
        return scales.sorted()
    }

    /// Where the page's top-left corner falls on the screen, in its pixels: a fraction is a tile
    /// placed between pixels, which Core Animation then samples between them.
    private static func pageCornerInScreenPixels(of page: PDFPage, in pdfView: PDFView, window: UIWindow) -> String {
        let box = page.bounds(for: .cropBox)
        let corner = pdfView.convert(pdfView.convert(CGPoint(x: box.minX, y: box.maxY), from: page), to: window)
        let screenScale = window.traitCollection.displayScale
        return String(format: "(%.2f, %.2f)", Double(corner.x * screenScale), Double(corner.y * screenScale))
    }

    /// PDFKit's layer for each annotation of the pages it has views for (`PDFAnnotationLayerResolution`).
    private static func annotationLayers(in pdfView: PDFView) -> [CALayer] {
        guard let documentLayer = pdfView.documentView?.layer,
              let annotationLayerClass = NSClassFromString(PDFAnnotationLayerResolution.annotationLayerClassName) else { return [] }
        return PDFAnnotationLayerResolution.annotationLayers(under: documentLayer, annotationLayerClass: annotationLayerClass)
    }

    /// The screen's pixels per point of a layer, through every transform above it.
    private func wantedScale(of layer: CALayer, in window: UIWindow) -> CGFloat {
        let shown = layer.convert(layer.bounds, to: window.layer)
        guard layer.bounds.width > 0, layer.bounds.height > 0 else { return 1 }
        let wanted = (shown.width * shown.height / (layer.bounds.width * layer.bounds.height)).squareRoot() * window.traitCollection.displayScale
        return PDFAnnotationLayerResolution.boundedScales(forLayerSizes: [layer.bounds.size], wantedScales: [wanted])[0]
    }

    private func format(_ value: CGFloat) -> String { String(format: "%.2f", Double(value)) }
}
#endif
