/**
 * File: PDFResizeFittingHostedTests.swift
 * ---------------------------------------
 * Layer: Tests
 * Description: A PDF whose side was hidden and shown again through a window's resize fits its width again, or keeps
 *              how far past fitting it was zoomed (HUNT-378).
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

#if os(iOS)
import XCTest
import PDFKit
import UIKit
@testable import GraphiteUI

/// The widths a PDF's view went through on an iPad simulator in Stage Manager (2026-11-24): its
/// side hidden by a compact window (width 0), then shown again as the window grew, one width at
/// each frame of the animation. PDFKit's fitting zoom lagged those widths, and the pages ended
/// at 2.17 where 0.98 fitted.
@MainActor
final class PDFResizeFittingHostedTests: XCTestCase {
    private var window: UIWindow?
    private static let widthsAsTheWindowGrows: [CGFloat] = [588, 587.4, 691.9, 701.9, 613.6, 608.6, 606.2, 602.8, 601.8, 601, 600.3, 599.8, 599, 598.5, 598]

    override func tearDown() async throws {
        window?.isHidden = true
        window?.rootViewController = nil
        window = nil
    }

    func testTheWorkedOutFittingZoomIsPDFKitsOnceTheViewIsStill() async throws {
        let view = try await hostedPDFView(width: 890)
        let margins = view.pageBreakMargins.left + view.pageBreakMargins.right
        let span = try XCTUnwrap(PDFResizeZoom.fittedSpan(pageWidthsAsShown: [595.28], horizontalMargins: margins))
        for width in [890, 598, 414] as [CGFloat] {
            view.frame.size.width = width
            try await waitUntil("PDFKit fits \(Int(width)) points as worked out") {
                !view.isResizing && abs(width / span - view.scaleFactorForSizeToFit) <= view.scaleFactorForSizeToFit * 0.005
            }
        }
    }

    func testAPageThatFittedFitsAgainAfterItsSideIsShownThroughAResize() async throws {
        let view = try await hostedPDFView(width: 694)
        // Fitted, but no longer scaled by PDFKit, as after a resize that set the zoom.
        view.autoScales = false
        view.scaleFactor = view.scaleFactorForSizeToFit
        try await hideAndShowAgain(view)
        XCTAssertEqual(view.scaleFactor / view.scaleFactorForSizeToFit, 1, accuracy: PDFResizeZoom.fittingTolerance,
                       "The page fits its side, at \(view.scaleFactor) for \(view.scaleFactorForSizeToFit).")
        try assertPageFillsTheWidth(of: view)
    }

    func testAPageZoomedPastFittingStaysAsFarPastAfterItsSideIsShownThroughAResize() async throws {
        let view = try await hostedPDFView(width: 694)
        view.autoScales = false
        view.scaleFactor = view.scaleFactorForSizeToFit * 1.5
        // Zoomed with the side still shown, as a pinch leaves it.
        view.frame.size.width = 640
        try await waitUntil("the resize to 640 points has ended") { !view.isResizing }
        try await hideAndShowAgain(view)
        XCTAssertEqual(view.scaleFactor / view.scaleFactorForSizeToFit, 1.5, accuracy: 0.05)
    }

    // MARK: Steps

    private func hideAndShowAgain(_ view: GraphitePDFDisplayView) async throws {
        view.frame.size.width = 0
        // Hidden, the side keeps the resize that hid it open until it is shown again.
        turnRunLoop(forSeconds: 0.6)
        XCTAssertTrue(view.isResizing, "The hidden side keeps its zoom and place for when it is shown again.")
        // One width at each frame of the window's animation, the run loop turning between them.
        for width in Self.widthsAsTheWindowGrows {
            view.frame.size.width = width
            view.layoutIfNeeded()
            turnRunLoop(forSeconds: 0.025)
        }
        try await waitUntil("the resize has ended") { !view.isResizing }
        // PDFKit fits the pages once it scales them itself again, at its next layout.
        turnRunLoop(forSeconds: 0.1)
    }

    /// Lets the run loop lay out and draw, as between two frames of an animation.
    private func turnRunLoop(forSeconds seconds: TimeInterval) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    private func assertPageFillsTheWidth(of view: GraphitePDFDisplayView) throws {
        let page = try XCTUnwrap(view.document?.page(at: 0))
        let pageFrame = view.convert(page.bounds(for: view.displayBox), from: page)
        XCTAssertGreaterThanOrEqual(pageFrame.minX, -1, "The page does not run off the left edge.")
        XCTAssertLessThanOrEqual(pageFrame.maxX, view.bounds.width + 1, "The page does not run off the right edge.")
    }

    private func hostedPDFView(width: CGFloat) async throws -> GraphitePDFDisplayView {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.effectiveGeometry.coordinateSpace.bounds
        let controller = UIViewController()
        window.rootViewController = controller
        window.makeKeyAndVisible()
        self.window = window

        let view = GraphitePDFDisplayView(frame: CGRect(x: 0, y: 0, width: width, height: 500))
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.autoScales = true
        view.document = Self.lectureDocument()
        controller.view.addSubview(view)
        try await waitUntil("the PDF has laid out its pages") { view.scaleFactorForSizeToFit > 0 && view.documentView?.bounds.width ?? 0 > 0 }
        return view
    }

    /// Four A4 pages with a heading each.
    private static func lectureDocument() -> PDFDocument? {
        let pageBox = CGRect(x: 0, y: 0, width: 595.28, height: 841.89)
        let data = UIGraphicsPDFRenderer(bounds: pageBox).pdfData { context in
            for pageNumber in 1...4 {
                context.beginPage()
                ("\(pageNumber) Introduction" as NSString).draw(at: CGPoint(x: 60, y: 80), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 36)])
            }
        }
        return PDFDocument(data: data)
    }
}
#endif
