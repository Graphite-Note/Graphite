/**
 * File: PDFPageSharpnessHostedTests.swift
 * ---------------------------------------
 * Layer: Tests
 * Description: The iPad's PDF view shows a page's own text, a placed picture and the page's ink as
 *              sharp as PDFKit's own drawing of the page at the screen's resolution, at fit and
 *              zoomed in, and prints what it measured.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 04/11/2026
 */
#if os(iOS)
import XCTest
import SwiftUI
import PDFKit
import PencilKit
import ImageIO
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

    override func tearDown() async throws {
        for location in temporaryLocations { try? FileManager.default.removeItem(at: location) } // A file left in the temporary folder harms nothing.
        temporaryLocations = []
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
            XCTAssertLessThanOrEqual(after.onScreen, after.reference + 0.75, "The picture at \(zoomOfFit)x fit is as sharp as PDFKit draws the page")
        }
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
        pdfView.go(to: CGRect(x: row.midX - 1, y: row.midY - 1, width: 2, height: 2), on: page)
        var lastOnScreen: CGFloat = -1
        var measured: EdgeWidths?
        try await waitUntil("the row shows the same twice", pollingIntervalSeconds: 0.3) {
            let shownRow = self.shownPart(of: row, on: page, in: pdfView)
            let onScreen = try self.edgeWidthOnScreen(along: shownRow, of: page, in: pdfView, window: window)
            defer { lastOnScreen = onScreen }
            guard abs(onScreen - lastOnScreen) < 0.01 else { return false }
            let screenPixelsPerPoint = pdfView.scaleFactor * window.traitCollection.displayScale
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
