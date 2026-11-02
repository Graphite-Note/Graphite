/**
 * File: EmbeddedPDFViewerLocationChangeTests.swift
 * ------------------------------------------------
 * Layer: Tests
 * Description: An embedded PDF follows its place in the note when that place names another PDF (HUNT-104).
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 01/11/2026
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
private final class EmbeddedPDFPlace {
    var location: URL

    init(location: URL) { self.location = location }
}

private struct EmbeddedPDFPlaceHost: View {
    let place: EmbeddedPDFPlace
    let sessions: EmbeddedPDFSessions

    var body: some View {
        EmbeddedPDFViewer(location: place.location, openInPane: { _ in })
            .environment(\.embeddedPDFSessions, sessions)
    }
}

@MainActor
final class EmbeddedPDFViewerLocationChangeTests: XCTestCase {
    private var directory: URL!
    private var windows: [NSWindow] = []

    override func setUpWithError() throws {
        directory = try TemporaryVault.make(prefix: "EmbeddedPDFLocationChange", for: self).root
    }

    override func tearDown() async throws {
        for window in windows { window.close() }
        windows = []
        try? FileManager.default.removeItem(at: directory)
        try await super.tearDown()
    }

    private func makePDF(named name: String) throws -> URL {
        let location = directory.appendingPathComponent(name)
        try PDFTemplateGenerator.documentData(paper: PaperSpecification(template: .blank), pageCount: 2).write(to: location)
        return location
    }

    /// Reading blocks are numbered, so a row keeps its place in the view when the note above it changes and
    /// its embed then names another PDF. The viewer showed the old PDF, and annotating saved into it.
    func testAnEmbedShowsTheNewPDFAndReleasesTheOldOneWhenItsLocationChanges() async throws {
        let firstLocation = try makePDF(named: "First.pdf"), secondLocation = try makePDF(named: "Second.pdf")
        let sessions = EmbeddedPDFSessions()
        let place = EmbeddedPDFPlace(location: firstLocation)
        let probe = try await PDFSession.open(firstLocation)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 700), styleMask: [.titled], backing: .buffered, defer: false)
        // Swift owns the window; closing it in tearDown must not release it a second time.
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: EmbeddedPDFPlaceHost(place: place, sessions: sessions))
        window.showInvisibly()
        windows.append(window)

        try await waitUntil("the first PDF is shown") { !sessions.otherSessions(showing: firstLocation, besides: probe).isEmpty }

        place.location = secondLocation

        try await waitUntil("the second PDF is shown") { !sessions.otherSessions(showing: secondLocation, besides: probe).isEmpty }
        try await waitUntil("the first PDF is released") { sessions.otherSessions(showing: firstLocation, besides: probe).isEmpty }
    }
}
#endif
