/**
 * File: EmbeddedPDFPageFitTests.swift
 * -----------------------------------
 * Layer: Tests
 * Description: HUNT-354: a PDF embed without `#height` is as tall as the page it opens at, shown whole at the column's
 *              width; `#height=N` keeps its height.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 13/11/2026
 */

#if os(macOS)
import AppKit
import PDFKit
import SwiftUI
import XCTest
import GraphiteApple
import GraphiteCore
@testable import GraphiteUI
import GraphiteTestSupport

@MainActor
final class EmbeddedPDFPageFitTests: XCTestCase {
    private var directory: URL!
    private var windows: [NSWindow] = []
    private static let columnWidth: CGFloat = 500

    override func setUp() async throws {
        directory = try TemporaryVault.make(prefix: "EmbeddedPDFPageFit", for: self).root
    }

    override func tearDown() async throws {
        for window in windows { window.close() }
        windows = []
        try? FileManager.default.removeItem(at: directory)
        try await super.tearDown()
    }

    func testTheFittedPageAreaIsThePageAtTheWidthLessItsMarginsPlusTheMargins() {
        let margins = 2 * PDFEmbedFitting.pageMargin
        XCTAssertEqual(PDFEmbedFitting.pageAreaHeight(showing: CGSize(width: 612, height: 792), width: 500),
                       ((500 - margins) * 792 / 612).rounded(.up) + margins)
        XCTAssertEqual(PDFEmbedFitting.pageAreaHeight(showing: CGSize(width: 792, height: 612), width: 500),
                       ((500 - margins) * 612 / 792).rounded(.up) + margins)
        XCTAssertNil(PDFEmbedFitting.pageAreaHeight(showing: .zero, width: 500))
        XCTAssertNil(PDFEmbedFitting.pageAreaHeight(showing: CGSize(width: 612, height: 792), width: 8))
    }

    /// A letter page, then a page as wide and half as tall: PDFKit shows the pages of a document
    /// at one scale, fitted to its widest page, so the pages here are as wide as each other.
    private func makePDF() throws -> URL {
        let location = directory.appendingPathComponent("Handout.pdf")
        let document = PDFDocument()
        for (pageIndex, size) in [CGSize(width: 612, height: 792), CGSize(width: 612, height: 396)].enumerated() {
            let page = PDFPage()
            page.setBounds(CGRect(origin: .zero, size: size), for: .mediaBox)
            document.insert(page, at: pageIndex)
        }
        XCTAssertTrue(document.write(to: location))
        return location
    }

    private func show(_ viewer: EmbeddedPDFViewer) -> NSHostingView<AnyView> {
        let host = NSHostingView(rootView: AnyView(viewer.frame(width: Self.columnWidth).environment(\.embeddedPDFSessions, EmbeddedPDFSessions())))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 1_000), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.showInvisibly()
        windows.append(window)
        return host
    }

    private func pdfView(in view: NSView) -> PDFView? {
        (view as? PDFView) ?? view.subviews.lazy.compactMap { subview in self.pdfView(in: subview) }.first
    }

    /// The PDF view of an embed without `#height` is as tall as the page it opens at, fitted
    /// to its width, and shows that page whole: its top and its foot inside the view.
    private func assertShowsItsPageWhole(_ viewer: EmbeddedPDFViewer, pageIndex: Int, file: StaticString = #filePath, line: UInt = #line) async throws {
        let host = show(viewer)
        var shownPDF: PDFView?
        try await waitUntil("the PDF is shown at its fitted height") {
            host.layoutSubtreeIfNeeded()
            shownPDF = self.pdfView(in: host)
            guard let shownPDF, let page = shownPDF.document?.page(at: pageIndex) else { return false }
            let expected = PDFEmbedFitting.pageAreaHeight(showing: page.bounds(for: .cropBox).size, width: shownPDF.bounds.width) ?? 0
            return abs(shownPDF.bounds.height - expected) < 1
        }
        let view = try XCTUnwrap(shownPDF, file: file, line: line)
        let page = try XCTUnwrap(view.document?.page(at: pageIndex), file: file, line: line)
        try await waitUntil("the page is in view") {
            view.layoutSubtreeIfNeeded()
            return view.currentPage == page
        }
        let pageInView = view.convert(page.bounds(for: .cropBox), from: page)
        // PDFKit keeps its own few points around a page; the page is whole and fills the view but for them.
        let slack = 2 * PDFEmbedFitting.pageMargin + 2
        XCTAssertTrue(view.bounds.insetBy(dx: -0.5, dy: -0.5).contains(pageInView), "The page is shown whole: \(pageInView) in \(view.bounds)", file: file, line: line)
        XCTAssertGreaterThan(pageInView.width, view.bounds.width - slack, "The page fills the width", file: file, line: line)
        XCTAssertGreaterThan(pageInView.height, view.bounds.height - slack, "The page fills the height", file: file, line: line)
    }

    func testAnEmbedWithoutAHeightShowsItsFirstPageWhole() async throws {
        try await assertShowsItsPageWhole(EmbeddedPDFViewer(location: try makePDF(), openInPane: { _ in }), pageIndex: 0)
    }

    func testAnEmbedOfAPageShowsThatPageWhole() async throws {
        try await assertShowsItsPageWhole(EmbeddedPDFViewer(location: try makePDF(), startPageNumber: 2, openInPane: { _ in }), pageIndex: 1)
    }

    func testAHeightWrittenInTheEmbedKeepsItsHeight() async throws {
        let host = show(EmbeddedPDFViewer(location: try makePDF(), height: 300, openInPane: { _ in }))
        try await waitUntil("the PDF is shown") {
            host.layoutSubtreeIfNeeded()
            return self.pdfView(in: host) != nil
        }
        XCTAssertEqual(host.fittingSize.height, 300, accuracy: 1)
    }
}
#endif
