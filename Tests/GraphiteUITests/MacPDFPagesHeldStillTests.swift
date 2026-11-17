/**
 * File: MacPDFPagesHeldStillTests.swift
 * -------------------------------------
 * Layer: Tests
 * Description: A Mac PDF view whose top edge moves down or up (a row shown or hidden above it) keeps its pages where
 *              they are on screen; a view moved whole or made narrower is left as PDFKit lays it out.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 17/11/2026
 */

#if os(macOS)
import XCTest
import AppKit
import PDFKit
@testable import GraphiteUI
import GraphiteTestSupport

@MainActor
final class MacPDFPagesHeldStillTests: XCTestCase {
    private struct Fixture {
        let window: NSWindow
        let view: GraphiteMacPDFView
        let page: PDFPage
    }

    /// Three pages in a view 600 points tall inside a container 700 tall, scrolled into the second page, so the pages
    /// can move both ways.
    private func makeFixture() throws -> Fixture {
        let location = try TemporaryVault.make(prefix: "MacPDFPagesHeldStill", for: self).root.appendingPathComponent("Pages.pdf")
        var mediaBox = CGRect(x: 0, y: 0, width: 400, height: 600)
        let context = try XCTUnwrap(CGContext(location as CFURL, mediaBox: &mediaBox, nil))
        for _ in 0..<3 {
            context.beginPDFPage(nil)
            context.endPDFPage()
        }
        context.closePDF()
        let container = NSView(frame: CGRect(x: 0, y: 0, width: 400, height: 700))
        let window = NSWindow(contentRect: container.frame, styleMask: [.titled], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        window.contentView = container
        let view = GraphiteMacPDFView(frame: CGRect(x: 0, y: 0, width: 400, height: 600))
        container.addSubview(view)
        view.document = try XCTUnwrap(PDFDocument(url: location))
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        window.showInvisibly()
        addTeardownBlock { @MainActor in window.close() }
        view.layoutSubtreeIfNeeded()
        let page = try XCTUnwrap(view.document?.page(at: 1))
        view.go(to: PDFDestination(page: page, at: CGPoint(x: 0, y: 400)))
        view.layoutSubtreeIfNeeded()
        return Fixture(window: window, view: view, page: page)
    }

    /// The page point under a point of the window.
    private func pagePoint(underWindowPoint windowPoint: CGPoint, in fixture: Fixture) -> CGPoint {
        fixture.view.convert(fixture.view.convert(windowPoint, from: nil), to: fixture.page)
    }

    private func setFrame(_ frame: CGRect, of fixture: Fixture) {
        fixture.view.frame = frame
        fixture.view.layoutSubtreeIfNeeded()
    }

    func testARowShownAndHiddenAboveTheViewLeavesThePagesWhereTheyAre() throws {
        let fixture = try makeFixture()
        let windowPoint = CGPoint(x: 200, y: 300)
        let before = pagePoint(underWindowPoint: windowPoint, in: fixture)
        setFrame(CGRect(x: 0, y: 0, width: 400, height: 567), of: fixture)
        let withRow = pagePoint(underWindowPoint: windowPoint, in: fixture)
        XCTAssertEqual(withRow.y, before.y, accuracy: 0.5, "the row took the view's top 33 points, the pages stayed")
        XCTAssertEqual(withRow.x, before.x, accuracy: 0.5)
        setFrame(CGRect(x: 0, y: 0, width: 400, height: 600), of: fixture)
        XCTAssertEqual(pagePoint(underWindowPoint: windowPoint, in: fixture).y, before.y, accuracy: 0.5, "hidden again, the pages stayed")
    }

    func testAScrollBetweenRowsIsKept() throws {
        let fixture = try makeFixture()
        let clipView = try XCTUnwrap(fixture.view.documentView?.enclosingScrollView?.contentView)
        clipView.scroll(to: CGPoint(x: clipView.bounds.minX, y: clipView.bounds.minY + 50))
        clipView.enclosingScrollView?.reflectScrolledClipView(clipView)
        let windowPoint = CGPoint(x: 200, y: 300)
        let scrolled = pagePoint(underWindowPoint: windowPoint, in: fixture)
        setFrame(CGRect(x: 0, y: 0, width: 400, height: 567), of: fixture)
        XCTAssertEqual(pagePoint(underWindowPoint: windowPoint, in: fixture).y, scrolled.y, accuracy: 0.5, "measured from where the scroll left the pages")
    }

    func testAViewMovedWholeIsLeftToPDFKit() throws {
        let fixture = try makeFixture()
        let windowPoint = CGPoint(x: 200, y: 300)
        let before = pagePoint(underWindowPoint: windowPoint, in: fixture)
        // A PDF embedded in a note that scrolls by 40 points: the view moves, its pages with it.
        setFrame(CGRect(x: 0, y: 40, width: 400, height: 600), of: fixture)
        let scale = fixture.view.scaleFactor
        XCTAssertEqual(pagePoint(underWindowPoint: windowPoint, in: fixture).y, before.y - 40 / scale, accuracy: 0.5)
    }
}
#endif
