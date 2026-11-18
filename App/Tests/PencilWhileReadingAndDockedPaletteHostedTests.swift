/**
 * File: PencilWhileReadingAndDockedPaletteHostedTests.swift
 * ---------------------------------------------------------
 * Layer: Tests
 * Description: Hosted tests of two Pencil fixes of the bug hunt: a Pencil touching a PDF that is read starts writing
 *              through UIKit's own event path (HUNT-024), and on a phone the pages stay clear of the palette docked
 *              along the bottom of the screen (HUNT-273).
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 18/11/2026
 */

#if os(iOS)
import XCTest
import SwiftUI
import PDFKit
import GraphiteCore
@testable import GraphiteUI

@MainActor
final class PencilWhileReadingAndDockedPaletteHostedTests: XCTestCase {
    private var window: UIWindow?
    private var locations: [URL] = []

    override func tearDown() async throws {
        window?.isHidden = true
        window?.rootViewController = nil
        window = nil
        for location in locations { try? FileManager.default.removeItem(at: location) } // A file left in the temporary folder harms nothing.
        locations = []
    }

    /// A blank notebook of `pageCount` pages shown in a window of the whole screen, with its PDF view.
    private func showNotebook(named name: String, pageCount: Int) async throws -> (PDFSession, GraphitePDFDisplayView, UIWindow) {
        let location = try makeHostedBlankNotebook(named: name, pageCount: pageCount)
        locations.append(location)
        let session = try await PDFSession.open(location)
        try await waitUntil("the app's scene is connected") { UIApplication.shared.connectedScenes.contains { $0 is UIWindowScene } }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let shownWindow = UIWindow(windowScene: scene)
        shownWindow.frame = scene.effectiveGeometry.coordinateSpace.bounds
        shownWindow.rootViewController = UIHostingController(rootView: NavigationStack { PDFPane(session: session, resolveConflict: { _ in }) })
        shownWindow.makeKeyAndVisible()
        window = shownWindow
        try await waitUntil("the PDF shows") { (session.pdfView as? GraphitePDFDisplayView)?.window === shownWindow }
        return (session, try XCTUnwrap(session.pdfView as? GraphitePDFDisplayView), shownWindow)
    }

    private func attachScreenshot(of window: UIWindow, named name: String) {
        let screenshot = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
        let attachment = XCTAttachment(image: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    // MARK: HUNT-024

    /// The first stroke on a PDF being read only switched to writing. The Pencil's touch goes through UIKit's own event
    /// path, as the screen's does: the PDF is written on when it lifts, and the stroke is on the page, drawn by the canvas's
    /// drawing recognizer the touch is told to (`PencilTouchDownRecognizer`).
    func testAPencilStrokeOnAPDFBeingReadStartsWriting() async throws {
        XCTAssertNil(SynthesizedTouches.unavailableReason)
        XCTAssertTrue(SynthesizedTouches.canMakePencilTouches, "UIKit lets a made touch be Apple Pencil's.")
        let (session, pdfView, window) = try await showNotebook(named: "PencilWhileReading", pageCount: 1)
        session.isWriting = false
        try await waitUntil("the PDF is read: its page's canvas takes no touches") {
            let canvases = Self.canvases(in: pdfView)
            return !canvases.isEmpty && canvases.allSatisfy { canvas in !canvas.isUserInteractionEnabled }
        }
        let middle = pdfView.convert(CGPoint(x: pdfView.bounds.midX, y: pdfView.bounds.midY), to: window)
        // A finger's drag on a PDF being read scrolls it and starts no writing.
        await SynthesizedTouches(window: window).drag(from: middle, to: CGPoint(x: middle.x + 120, y: middle.y + 10), steps: 12)
        XCTAssertFalse(session.isWriting, "A finger reads on.")
        await SynthesizedTouches(window: window, touchType: .pencil).drag(from: middle, to: CGPoint(x: middle.x + 120, y: middle.y + 10), steps: 12)
        try await waitUntil("the Pencil's first stroke starts writing") { session.isWriting }
        try await waitUntil("the first stroke is drawn on the page") {
            Self.canvases(in: pdfView).reduce(0) { count, canvas in count + canvas.drawing.strokes.count } == 1
        }
        attachScreenshot(of: window, named: "Writing after the Pencil's first stroke")
    }

    private static func canvases(in view: UIView) -> [PDFPageCanvasView] {
        view.subviews.flatMap { child in ((child as? PDFPageCanvasView).map { [$0] } ?? []) + canvases(in: child) }
    }

    // MARK: HUNT-273

    /// On a phone the palette docks along the bottom of the screen over the PDF, which reaches under the bottom safe
    /// area: the pages scroll on by the height it covers while it shows, so the last lines of the last page show above
    /// it, and by nothing once it goes.
    func testOnAPhoneTheLastPageScrollsClearOfTheDockedPalette() async throws {
        let (session, pdfView, window) = try await showNotebook(named: "DockedPalette", pageCount: 3)
        let coordinator = try XCTUnwrap(pdfView.annotationCoordinator)
        let scrollView = try XCTUnwrap(pdfView.pagesScrollView)
        session.isWriting = true
        try await waitUntil("the palette shows") { coordinator.toolPicker.isVisible }
        try await waitUntil("the palette has settled", timeoutSeconds: 5) {
            !coordinator.toolPicker.frameObscured(in: pdfView).isEmpty || UIDevice.current.userInterfaceIdiom != .phone
        }
        let obscured = coordinator.toolPicker.frameObscured(in: pdfView)
        let covered = obscured.isNull || obscured.isEmpty ? 0 : pdfView.bounds.intersection(obscured).height
        if UIDevice.current.userInterfaceIdiom == .phone {
            XCTAssertGreaterThan(covered, 40, "A phone's palette docks along the bottom of the screen, over the pages.")
        }
        try await waitUntil("the pages scroll clear of the palette") { abs(scrollView.contentInset.bottom - covered) < 0.5 }
        // The end of the last page shows above the palette.
        scrollView.setContentOffset(CGPoint(x: scrollView.contentOffset.x,
                                            y: scrollView.contentSize.height + scrollView.adjustedContentInset.bottom - scrollView.bounds.height),
                                    animated: false)
        pdfView.layoutIfNeeded()
        let lastPage = try XCTUnwrap(session.document.page(at: session.document.pageCount - 1))
        let lastPageBottomInWindow = pdfView.convert(pdfView.convert(lastPage.bounds(for: pdfView.displayBox), from: lastPage), to: window).maxY
        let paletteTopInWindow = obscured.isNull || obscured.isEmpty ? window.bounds.maxY : pdfView.convert(obscured, to: window).minY
        attachScreenshot(of: window, named: "The last page's end above the palette")
        XCTAssertLessThanOrEqual(lastPageBottomInWindow, paletteTopInWindow + 1, "The last page's end is not under the palette.")
        session.isWriting = false
        try await waitUntil("the palette goes and the pages end at the screen's bottom") {
            !coordinator.toolPicker.isVisible && scrollView.contentInset.bottom < 0.5
        }
    }
}
#endif
