/**
 * File: EmbeddedPDFViewerReloadPlaceTests.swift
 * ---------------------------------------------
 * Layer: Tests
 * Description: An embedded PDF stays on its page when another device's version replaces the file.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 07/11/2026
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

@MainActor @Observable
private final class EmbeddedPDFFileVersion {
    var drawingVersion = 0
}

private struct EmbeddedPDFReloadHost: View {
    let location: URL
    let fileVersion: EmbeddedPDFFileVersion
    let sessions: EmbeddedPDFSessions

    var body: some View {
        EmbeddedPDFViewer(location: location, height: 500, drawingVersion: fileVersion.drawingVersion, openInPane: { _ in })
            .environment(\.embeddedPDFSessions, sessions)
    }
}

@MainActor
final class EmbeddedPDFViewerReloadPlaceTests: XCTestCase {
    private var directory: URL!
    private var windows: [NSWindow] = []

    override func setUp() async throws {
        directory = try TemporaryVault.make(prefix: "EmbeddedPDFReloadPlace", for: self).root
    }

    override func tearDown() async throws {
        for window in windows { window.close() }
        windows = []
        try? FileManager.default.removeItem(at: directory)
        try await super.tearDown()
    }

    private func pdfData(pageCount: Int) throws -> Data {
        try PDFTemplateGenerator.documentData(paper: PaperSpecification(template: .blank), pageCount: pageCount)
    }

    /// iCloud delivers a PDF annotated on the iPad as a whole new file. The embed read it
    /// again from its first page, so a person reading page 6 on the Mac was sent to the top.
    func testAnEmbedStaysOnItsPageWhenTheFileIsReplaced() async throws {
        let location = directory.appendingPathComponent("Lecture.pdf")
        try pdfData(pageCount: 10).write(to: location)
        let sessions = EmbeddedPDFSessions()
        let fileVersion = EmbeddedPDFFileVersion()
        let probe = try await PDFSession.open(location)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 700), styleMask: [.titled], backing: .buffered, defer: false)
        // Swift owns the window; closing it in tearDown must not release it a second time.
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: EmbeddedPDFReloadHost(location: location, fileVersion: fileVersion, sessions: sessions))
        window.showInvisibly()
        windows.append(window)

        try await waitUntil("the PDF is shown") { sessions.otherSessions(showing: location, besides: probe).first?.pdfView != nil }
        let firstSession = try XCTUnwrap(sessions.otherSessions(showing: location, besides: probe).first)
        firstSession.go(to: 5)
        try await waitUntil("page 6 is at the top") { firstSession.placeToRemember().pageIndex == 5 }

        // Another device's version, written as a sync writes it: a new file in its place.
        let replacement = directory.appendingPathComponent(".Lecture.pdf.sync")
        try pdfData(pageCount: 11).write(to: replacement)
        _ = try FileManager.default.replaceItemAt(location, withItemAt: replacement)
        fileVersion.drawingVersion += 1

        try await waitUntil("the new version is shown") {
            guard let session = sessions.otherSessions(showing: location, besides: probe).first else { return false }
            return session !== firstSession && session.pageCount == 11 && session.pdfView != nil
        }
        let reloadedSession = try XCTUnwrap(sessions.otherSessions(showing: location, besides: probe).first)
        XCTAssertEqual(reloadedSession.currentPageIndex, 5)
        try await waitUntil("page 6 is still at the top") { reloadedSession.placeToRemember().pageIndex == 5 }
    }

    func testAPlaceOnAPageTheNewVersionNoLongerHasIsDropped() {
        let place = PDFPagePlace(pageIndex: 7, fractionFromTop: 0.4)
        XCTAssertEqual(EmbeddedPDFViewer.place(keptThroughReload: place, pageCount: 8), place)
        XCTAssertNil(EmbeddedPDFViewer.place(keptThroughReload: place, pageCount: 7))
        XCTAssertNil(EmbeddedPDFViewer.place(keptThroughReload: nil, pageCount: 7))
    }
}
#endif
