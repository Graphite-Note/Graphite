/**
 * File: HighlightAfterReopeningTests.swift
 * ----------------------------------------
 * Layer: Tests
 * Description: A highlight drawn over a PDF's text with the bar's highlighter leaves the text readable once the
 *              PDF is saved and opened again: on Graphite's screen and in the page as PDFKit draws it.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 04/11/2026
 */
#if os(iOS)
import XCTest
import SwiftUI
import PencilKit
import PDFKit
import GraphiteCore
import GraphiteApple
@testable import GraphiteUI

/// HUNT-002: a highlight turned into a solid band hiding the text under it once saved. The
/// page's "text" is a black bar; the bar's highlighter is drawn along it through the real
/// canvas, the PDF is saved, closed and opened in a new view, as after a relaunch.
@MainActor
final class HighlightAfterReopeningTests: XCTestCase {
    private static let pageSize = CGSize(width: 600, height: 400)
    /// The black bar across the page, in the page's coordinates (origin at the bottom).
    private static let bar = CGRect(x: 100, y: 198, width: 400, height: 4)

    private var temporaryLocations: [URL] = []
    private var windows: [UIWindow] = []

    override func tearDown() async throws {
        for window in windows { window.isHidden = true; window.rootViewController = nil }
        windows = []
        for location in temporaryLocations { try? FileManager.default.removeItem(at: location) } // A file left in the temporary folder harms nothing.
        temporaryLocations = []
    }

    private func pdfWithBlackBar() throws -> URL {
        let location = hostedTemporaryLocation(named: "HighlightOverText").appendingPathExtension("pdf")
        temporaryLocations.append(location)
        var mediaBox = CGRect(origin: .zero, size: Self.pageSize)
        let context = try XCTUnwrap(CGContext(location as CFURL, mediaBox: &mediaBox, nil))
        context.beginPDFPage(nil)
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fill(Self.bar)
        context.endPDFPage()
        context.closePDF()
        return location
    }

    /// The PDF's pane in a window of its own, with its first page's canvas once it shows.
    private func show(_ session: PDFSession) async throws -> (PDFPageCanvasView, GraphitePDFDisplayView, UIWindow) {
        let controller = UIHostingController(rootView: NavigationStack { PDFPane(session: session, resolveConflict: { _ in }) })
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        window.rootViewController = controller
        window.makeKeyAndVisible()
        windows.append(window)
        controller.view.layoutIfNeeded()
        try await waitUntil("the page's canvas is shown") { self.canvases(in: controller.view).contains { canvas in !canvas.isHidden } }
        let canvas = try XCTUnwrap(canvases(in: controller.view).first { canvas in !canvas.isHidden })
        let pdfView = try XCTUnwrap(session.pdfView as? GraphitePDFDisplayView)
        try await SynthesizedStrokes.waitForCanvasToDrawAtTheZoom(of: canvas, in: pdfView)
        return (canvas, pdfView, window)
    }

    private func canvases(in view: UIView) -> [PDFPageCanvasView] {
        view.subviews.flatMap { child in ((child as? PDFPageCanvasView).map { [$0] } ?? []) + canvases(in: child) }
    }

    /// The average color of a 3 by 3 point square of the window around a point of the page.
    private func shownColor(atPagePoint pagePoint: CGPoint, of page: PDFPage, in pdfView: PDFView, window: UIWindow) throws -> (red: Double, green: Double, blue: Double) {
        let windowPoint = pdfView.convert(pdfView.convert(pagePoint, from: page), to: window)
        let area = CGRect(x: windowPoint.x - 1.5, y: windowPoint.y - 1.5, width: 3, height: 3)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let picture = UIGraphicsImageRenderer(bounds: area, format: format).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        return try averageColor(of: XCTUnwrap(picture.cgImage))
    }

    private func averageColor(of image: CGImage) throws -> (red: Double, green: Double, blue: Double) {
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = try XCTUnwrap(CGContext(data: &bytes, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                              space: XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB)), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let pixelCount = Double(image.width * image.height)
        func channel(_ offset: Int) -> Double {
            stride(from: offset, to: bytes.count, by: 4).reduce(0.0) { total, byteIndex in total + Double(bytes[byteIndex]) } / pixelCount
        }
        return (channel(0), channel(1), channel(2))
    }

    /// The color PDFKit draws at a point of the page, annotations included, as the Mac's
    /// viewer and Graphite before the canvas covers the page draw it.
    private func drawnColor(atPagePoint pagePoint: CGPoint, of page: PDFPage) throws -> (red: Double, green: Double, blue: Double) {
        let scale: CGFloat = 2
        let width = Int(Self.pageSize.width * scale), height = Int(Self.pageSize.height * scale)
        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        let context = try XCTUnwrap(CGContext(data: &bytes, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                              space: XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB)), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.scaleBy(x: scale, y: scale)
        page.draw(with: .mediaBox, to: context)
        let image = try XCTUnwrap(context.makeImage())
        // The bitmap's rows run from the top; the page's from the bottom.
        let square = CGRect(x: pagePoint.x * scale - 3, y: (Self.pageSize.height - pagePoint.y) * scale - 3, width: 6, height: 6)
        return try averageColor(of: XCTUnwrap(image.cropping(to: square)))
    }

    private func luminance(_ color: (red: Double, green: Double, blue: Double)) -> Double {
        0.2126 * color.red + 0.7152 * color.green + 0.0722 * color.blue
    }

    private func attachScreenshot(of window: UIWindow, named name: String) {
        let screenshot = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
        let attachment = XCTAttachment(image: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testAHighlightOverTextLeavesItReadableOnTheScreenAndInThePageAfterThePDFIsOpenedAgain() async throws {
        // The highlighter as Apple Notes' draws it, the default (`EvenHighlighterPreference` is off unless turned on).
        XCTAssertFalse(EvenHighlighterPreference.isOn())
        let restoreFingers = SynthesizedStrokes.letFingersDraw()
        defer { restoreFingers() }
        let location = try pdfWithBlackBar()

        let session = try await PDFSession.open(location)
        let (canvas, pdfView, window) = try await show(session)
        canvas.takeTool(from: PKToolPicker(), fixedTool: PencilToolSelection(kind: .ink, preset: InkPreset(ink: .highlighter), erasesWholeStrokes: true,
                                                                             eraserWidth: 18, isRulerActive: false))
        let page = try XCTUnwrap(canvas.page)
        let start = pdfView.convert(pdfView.convert(CGPoint(x: 130, y: Self.bar.midY), from: page), to: window)
        let end = pdfView.convert(pdfView.convert(CGPoint(x: 470, y: Self.bar.midY), from: page), to: window)
        let drawnStroke = try await SynthesizedStrokes.draw(on: canvas, through: SynthesizedStrokes.line(from: start, to: end, steps: 40), in: window)
        let highlight = try XCTUnwrap(drawnStroke, "The highlighter drew")
        XCTAssertEqual(highlight.ink.inkType, .marker)
        // The band's half height on the page, to find paper inside it beside the bar.
        let bandHalfHeight = highlight.renderBounds.height / 2
        XCTAssertGreaterThan(bandHalfHeight, Self.bar.height, "The band is wider than the bar it covers")
        let besideTheBar = CGPoint(x: 300, y: Self.bar.maxY + (bandHalfHeight - Self.bar.height / 2) / 2)
        try await session.save()
        window.isHidden = true
        window.rootViewController = nil

        // As after a relaunch: the file read again, in a new view.
        let reopenedSession = try await PDFSession.open(location)
        let (reopenedCanvas, reopenedPDFView, reopenedWindow) = try await show(reopenedSession)
        try await waitUntil("the stored highlight is on the canvas") { reopenedCanvas.hasRestoredStoredInk && reopenedCanvas.drawing.strokes.count == 1 }
        try await SynthesizedStrokes.waitForPageToDraw(milliseconds: 500)
        attachScreenshot(of: reopenedWindow, named: "Highlight over the bar, opened again")
        let reopenedPage = try XCTUnwrap(reopenedCanvas.page)
        let barOnScreen = try shownColor(atPagePoint: CGPoint(x: 300, y: Self.bar.midY), of: reopenedPage, in: reopenedPDFView, window: reopenedWindow)
        let bandOnScreen = try shownColor(atPagePoint: besideTheBar, of: reopenedPage, in: reopenedPDFView, window: reopenedWindow)
        let paperOnScreen = try shownColor(atPagePoint: CGPoint(x: 300, y: 300), of: reopenedPage, in: reopenedPDFView, window: reopenedWindow)
        print("HIGHLIGHT on screen: bar under the band \(barOnScreen), band on paper \(bandOnScreen), paper \(paperOnScreen)")
        // A solid band draws the bar under it as the band's own color, a ratio of 1.
        XCTAssertLessThan(luminance(barOnScreen) / luminance(bandOnScreen), 0.6, "On the screen the bar under the band stays much darker than the band: \(barOnScreen)")
        XCTAssertLessThan(bandOnScreen.blue, paperOnScreen.blue - 60, "The band is there, yellow on the paper: \(bandOnScreen)")
        XCTAssertGreaterThan(bandOnScreen.red, 170)

        // The page as PDFKit draws it from the saved file, the highlight's annotation included.
        let savedDocument = try XCTUnwrap(PDFDocument(url: location))
        let savedPage = try XCTUnwrap(savedDocument.page(at: 0))
        XCTAssertTrue(savedPage.annotations.contains { annotation in annotation.type == "Ink" }, "The highlight is saved as an annotation other apps show")
        let barDrawn = try drawnColor(atPagePoint: CGPoint(x: 300, y: Self.bar.midY), of: savedPage)
        let bandDrawn = try drawnColor(atPagePoint: besideTheBar, of: savedPage)
        print("HIGHLIGHT drawn by PDFKit: bar under the band \(barDrawn), band on paper \(bandDrawn)")
        XCTAssertLessThan(max(barDrawn.red, barDrawn.green, barDrawn.blue), 90, "In the page's own drawing the bar under the band stays dark: \(barDrawn)")
        XCTAssertLessThan(luminance(barDrawn) / luminance(bandDrawn), 0.6)
        XCTAssertLessThan(bandDrawn.blue, 190, "The band is there in the page's own drawing: \(bandDrawn)")
    }
}
#endif
