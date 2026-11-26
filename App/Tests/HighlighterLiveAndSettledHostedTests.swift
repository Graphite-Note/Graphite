/**
 * File: HighlighterLiveAndSettledHostedTests.swift
 * ------------------------------------------------
 * Layer: Tests
 * Description: A highlighter stroke on a PDF page looks the same while it is drawn and once the Pencil lifts, over
 *              text and over another highlight, with the even highlighter on and off (HUNT-356).
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 16/11/2026
 */
#if os(iOS)
import XCTest
import SwiftUI
import PencilKit
import PDFKit
import GraphiteCore
import GraphiteApple
@testable import GraphiteUI

/// Reported 2026-11-14: the highlighter's stroke looked one way while drawn and another once
/// it settled. With the even highlighter on, as on the physical iPad, the canvas showed a band of
/// one flat color with square ends and hard edges while the stroke was drawn, and PencilKit's
/// softer, rounded even stroke replaced it at the lift.
@MainActor
final class HighlighterLiveAndSettledHostedTests: XCTestCase {
    private var temporaryLocations: [URL] = []

    override func tearDown() async throws {
        for location in temporaryLocations { try? FileManager.default.removeItem(at: location) } // A file left in the temporary folder harms nothing.
        temporaryLocations = []
    }

    func testTheEvenHighlightersStrokeLooksTheSameWhileDrawnAndOnceTheStrokeIsKept() async throws {
        try await compareStrokeWhileDrawnAndKept(evenHighlighter: true)
    }

    func testTheHighlightersOwnStrokeLooksTheSameWhileDrawnAndOnceTheStrokeIsKept() async throws {
        try await compareStrokeWhileDrawnAndKept(evenHighlighter: false)
    }

    /// Draws a highlight along a line of text, then a second one across the text and the first,
    /// and compares the second's first half on the screen while it is drawn and after the lift.
    private func compareStrokeWhileDrawnAndKept(evenHighlighter: Bool) async throws {
        let restoreFingers = SynthesizedStrokes.letFingersDraw()
        defer { restoreFingers() }
        let restoreEvenHighlighter = HostedDevicePreferences.set(evenHighlighter, forKey: EvenHighlighterPreference.key)
        defer { restoreEvenHighlighter() }
        let (session, canvas, window) = try await hostedPageWithText()
        defer { window.isHidden = true; window.rootViewController = nil }
        var preset = InkPreset(ink: .highlighter)
        preset.width = 18
        canvas.takeTool(from: PKToolPicker(), fixedTool: PencilToolSelection(kind: .ink, preset: preset, erasesWholeStrokes: true, eraserWidth: 18, isRulerActive: false))
        XCTAssertEqual(EvenHighlighter.isInvisible(try XCTUnwrap(canvas.tool as? PKInkingTool).ink), evenHighlighter)
        try await SynthesizedStrokes.waitForPageToDraw(milliseconds: 600)
        let page = try XCTUnwrap(canvas.page)
        let pdfView = try XCTUnwrap(session.pdfView)
        func windowPoint(_ pagePoint: CGPoint) -> CGPoint { pdfView.convert(pdfView.convert(pagePoint, from: page), to: window) }

        let alongTheText = SynthesizedStrokes.line(from: windowPoint(CGPoint(x: 60, y: 692)), to: windowPoint(CGPoint(x: 420, y: 692)))
        let firstHighlight = try await SynthesizedStrokes.draw(on: canvas, through: alongTheText, in: window)
        XCTAssertNotNil(firstHighlight, "The first highlight was drawn")
        try await SynthesizedStrokes.waitForPageToDraw(milliseconds: 1_000)

        let across = SynthesizedStrokes.line(from: windowPoint(CGPoint(x: 100, y: 740)), to: windowPoint(CGPoint(x: 380, y: 640)))
        let drawnHalf = Array(across.prefix(across.count / 2 + 1))
        // The part drawn by the middle of the stroke, without its end there, which goes on after it.
        let comparedHalf = Array(drawnHalf.dropLast(4))
        let compared = comparedHalf.dropFirst().reduce(CGRect(origin: comparedHalf[0], size: .zero)) { region, point in region.union(CGRect(origin: point, size: .zero)) }
            .insetBy(dx: -16, dy: -16)
        var whileDrawn: [UInt8] = []
        let secondHighlight = try await SynthesizedStrokes.draw(on: canvas, through: across, in: window, midway: {
            if evenHighlighter {
                // The stroke shown follows a real touch, which the stand-in touches do not reach.
                canvas.showEvenStrokeBeingDrawn(through: drawnHalf.map { point in window.convert(point, to: canvas) })
            }
            // PencilKit draws the touches told to it a little later on a busy machine.
            try await SynthesizedStrokes.waitForPageToDraw(milliseconds: 150)
            whileDrawn = self.pixels(of: window, in: compared, named: "While drawn, \(evenHighlighter ? "even" : "own") highlighter")
        })
        XCTAssertNotNil(secondHighlight, "The second highlight was drawn")
        try await waitUntil("the stroke shown while drawn has gone") { !canvas.isShowingEvenStroke && !canvas.isCoveredWhileRendering }
        try await SynthesizedStrokes.waitForPageToDraw(milliseconds: 1_000)
        let afterTheLift = pixels(of: window, in: compared, named: "After the lift, \(evenHighlighter ? "even" : "own") highlighter")

        XCTAssertEqual(whileDrawn.count, afterTheLift.count)
        let pixelCount = whileDrawn.count / 4
        var inked = 0, changed = 0, largestDifference = 0
        for pixelIndex in 0..<pixelCount {
            let offset = pixelIndex * 4
            if whileDrawn[offset + 2] < 200 || afterTheLift[offset + 2] < 200 { inked += 1 }
            let difference = (0..<3).map { channel in abs(Int(whileDrawn[offset + channel]) - Int(afterTheLift[offset + channel])) }.max() ?? 0
            largestDifference = max(largestDifference, difference)
            if difference > 24 { changed += 1 }
        }
        print("HIGHLIGHTER-LIVE-SETTLED even \(evenHighlighter): \(changed) of \(pixelCount) pixels changed by more than 24, largest \(largestDifference), inked \(inked)")
        XCTAssertGreaterThan(inked, pixelCount / 5, "The highlight is in the compared part")
        if evenHighlighter {
            // Each move of the Pencil pictures the stroke so far again, away from the main thread: drawn on it, a
            // move of this stroke took 7 ms on the simulator, most of a frame at 120 Hz.
            let longStroke = SynthesizedStrokes.line(from: windowPoint(CGPoint(x: 30, y: 760)), to: windowPoint(CGPoint(x: 470, y: 420)), steps: 400)
                .map { point in window.convert(point, to: canvas) }
            let start = ContinuousClock.now
            for pointCount in stride(from: 300, through: longStroke.count, by: 20) { canvas.showEvenStrokeBeingDrawn(through: Array(longStroke.prefix(pointCount))) }
            let millisecondsPerMove = (ContinuousClock.now - start) / .milliseconds(1) / 6
            print("HIGHLIGHTER-LIVE-SETTLED a move of a 550-point stroke takes \(millisecondsPerMove) ms of the main thread")
            XCTAssertLessThan(millisecondsPerMove, 2, "The main thread stays free for PencilKit's own stroke")
            try await waitUntil("the long stroke is shown") { canvas.isShowingEvenStroke }
        }
        XCTAssertLessThan(Double(changed), Double(pixelCount) * 0.004, "The stroke looks as it did while it was drawn")
    }

    /// The window's pixels in a rectangle of window points, RGBA at the screen's scale.
    private func pixels(of window: UIWindow, in rectangle: CGRect, named name: String) -> [UInt8] {
        let format = UIGraphicsImageRendererFormat()
        format.scale = window.screen.scale
        let image = UIGraphicsImageRenderer(bounds: rectangle, format: format).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: false)
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        guard let picture = image.cgImage, let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return [] }
        var bytes = [UInt8](repeating: 0, count: picture.width * picture.height * 4)
        guard let context = CGContext(data: &bytes, width: picture.width, height: picture.height, bitsPerComponent: 8, bytesPerRow: picture.width * 4,
                                      space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return [] }
        context.draw(picture, in: CGRect(x: 0, y: 0, width: picture.width, height: picture.height))
        return bytes
    }

    /// A page of black text open for writing in a PDF view, and its canvas.
    private func hostedPageWithText() async throws -> (PDFSession, PDFPageCanvasView, UIWindow) {
        let location = hostedTemporaryLocation(named: "HighlighterLiveAndSettled").appendingPathExtension("pdf")
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 500, height: 800))
        try renderer.pdfData { context in
            context.beginPage()
            let attributes: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 20), .foregroundColor: UIColor.black]
            for line in 0..<8 {
                ("The quick brown fox jumps over the lazy dog" as NSString).draw(at: CGPoint(x: 40, y: 60 + CGFloat(line) * 30), withAttributes: attributes)
            }
        }.write(to: location)
        temporaryLocations.append(location)
        let session = try await PDFSession.open(location)
        session.isWriting = true
        let controller = UIHostingController(rootView: NavigationStack { PDFPane(session: session, resolveConflict: { _ in }) })
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.effectiveGeometry.coordinateSpace.bounds
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()
        try await waitUntil("the page's canvas is shown") { self.canvases(in: controller.view).contains { canvas in !canvas.isHidden && canvas.delegate != nil } }
        return (session, try XCTUnwrap(canvases(in: controller.view).first { canvas in !canvas.isHidden }), window)
    }

    private func canvases(in view: UIView) -> [PDFPageCanvasView] {
        view.subviews.flatMap { child in ((child as? PDFPageCanvasView).map { [$0] } ?? []) + canvases(in: child) }
    }
}
#endif
