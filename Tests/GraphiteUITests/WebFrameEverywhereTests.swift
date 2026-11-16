/**
 * File: WebFrameEverywhereTests.swift
 * -----------------------------------
 * Layer: Tests
 * Description: Web frames wherever else a note is shown, on the Mac: a note embedded in another shows its frame's page,
 *              a link's preview card shows only the frame's box, Export to PDF prints the box cut to a printable height
 *              with the address as a link, and Read Aloud reads the text around a frame and nothing of its tag.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 12/11/2026
 */

import XCTest
import SwiftUI
import PDFKit
import WebKit
import GraphiteCore
import GraphiteIndex
@testable import GraphiteUI
import GraphiteTestSupport

@MainActor
final class WebFrameEverywhereTests: XCTestCase {
    private static let address = "https://research.cs.wisc.edu/multifacet/amdahl/"
    private static let ownersLine = #"<iframe src="https://research.cs.wisc.edu/multifacet/amdahl/" title="Amdahl grapher" width="100%" height="900" style="border:1px solid #ccc; border-radius:6px"></iframe>"#

    private var vault: TemporaryVault!
    private var index: VaultIndex!
    private var server: LoopbackWebServer?

    override func setUp() async throws {
        vault = try TemporaryVault.make(prefix: "WebFrameEverywhereVault", for: self)
        index = try VaultIndex(databaseURL: vault.cacheDirectory.appendingPathComponent("index.sqlite"))
    }

    override func tearDown() async throws {
        server?.stop()
        server = nil
        index = nil
        try? FileManager.default.removeItem(at: vault.cacheDirectory) // Best-effort removal of a temporary folder.
    }

    // MARK: Embedded notes and preview cards

    func testANoteEmbeddedInAnotherShowsItsFramesPageAndAPreviewCardOnlyItsBox() async throws {
        let server = try await LoopbackWebServer(pages: ["/grapher": "<html><body><h1>Embedded grapher</h1></body></html>"])
        self.server = server
        try vault.writeFile("Grapher.md", text: "# Grapher\n\n<iframe src=\"\(server.address("/grapher").absoluteString)\" height=\"300\"></iframe>\n")
        _ = try await index.reconcile(root: vault.root)
        let build = try await ReadingViewBuilder().build(source: "# Homework\n\n![[Grapher]]\n\nAfter.", note: try VaultPath("Homework.md"), root: vault.root,
                                                         index: index, configuration: ReadingConfiguration())
        let transclusion = try XCTUnwrap(build.blocks.first { block in if case .transclusion = block { true } else { false } })
        guard case .transclusion(_, _, _, let body) = transclusion else { return XCTFail("An embedded note") }
        XCTAssertTrue(body.contains { block in if case .webFrame = block { true } else { false } }, "The embedded note's frame is a block.")

        let reading = host(ReadingBlocksView(blocks: build.blocks, root: vault.root, textSize: 17, navigate: { _, _ in }, scrollToHeading: { _ in },
                                             openPDF: { _, _ in }, updateProperties: nil).environment(\.webFramePresentation, .live))
        try await waitUntil("the embedded note's frame loads its page", timeoutSeconds: 30) {
            reading.contentView?.layoutSubtreeIfNeeded()
            return self.webViews(in: reading).contains { webView in webView.url == server.address("/grapher") && !webView.isLoading }
        }

        // A card shown from a reading view, whose frames are live, still shows only the frame's box.
        let content = try XCTUnwrap(LinkPreviewContent(embedPreview: transclusion))
        let request = LinkPreviewRequest(target: "Grapher", isWiki: true, sourceNote: try VaultPath("Homework.md"), anchor: .zero, trigger: .hover, source: .reading)
        let card = LinkPreviewCard(request: request, content: content, root: vault.root, textSize: 17,
                                   actions: LinkPreviewActions(follow: { _, _, _ in }, openPDF: { _, _ in }),
                                   model: LinkPreviewModel(clock: ManualClock(), announceHover: { _ in }), naturalHeightDidChange: { _ in })
        let cardWindow = host(card.environment(\.webFramePresentation, .live), height: 600)
        try await settle(cardWindow)
        XCTAssertTrue(webViews(in: cardWindow).isEmpty, "A preview card makes no web view.")
        XCTAssertEqual(server.requestedPaths.count, 1, "Only the embedded note in the reading view loaded the page.")
    }

    // MARK: Export to PDF

    func testExportToPDFPrintsTheFramesBoxWithItsNameAndItsAddressAsALink() async throws {
        let note = "# Amdahl's Law in the Multicore Era\n\nThe grapher:\n\n" + Self.ownersLine + "\n\nAfter the frame.\n"
        let source = NotePDFSource(text: note, path: try VaultPath("Amdahl.md"), vault: try XCTUnwrap(ReadingVault(vault.root, index, store: VaultStore(root: vault.root))),
                                   readingConfiguration: ReadingConfiguration(), title: "Amdahl",
                                   appearance: NotePDFAppearance(typography: .standard, codeColorTheme: .obsidian, accent: .blue))
        let pdf = try await NotePDFRenderer(source: source, options: NotePDFOptions()).render { _ in }
        let document = try XCTUnwrap(PDFDocument(data: pdf.data))
        let firstPage = try XCTUnwrap(document.page(at: 0))
        let text = firstPage.string ?? ""
        XCTAssertTrue(text.contains("Amdahl grapher"), "The frame's title: \(text)")
        XCTAssertTrue(text.contains(Self.address), "The frame's address: \(text)")
        XCTAssertTrue(text.contains("After the frame."), "The box is cut to a printable height, so the text after it stays on the first page: \(text)")
        XCTAssertFalse(text.contains("iframe"), text)
        let links = firstPage.annotations.compactMap(\.url)
        XCTAssertTrue(links.contains(try XCTUnwrap(URL(string: Self.address))), "The address opens the page: \(links)")
        if let outputPath = ProcessInfo.processInfo.environment["GRAPHITE_WEB_FRAME_PDF"] {
            try pdf.data.write(to: URL(fileURLWithPath: outputPath))
        }
    }

    // MARK: Read Aloud

    /// Read Aloud reads the text around a frame and nothing of its tag, and where it starts and stops in the note is
    /// the text's own place, as without the frame.
    func testReadAloudSkipsTheFrameAndReadsTheTextAroundIt() throws {
        let note = "Before the frame.\n\n" + Self.ownersLine + "\n\nAfter the frame."
        let document = try ReadAloudDocument.markdown(note)
        let spoken = document.passages.map(\.text).joined(separator: " ")
        XCTAssertTrue(spoken.contains("Before the frame."), spoken)
        XCTAssertTrue(spoken.contains("After the frame."), spoken)
        XCTAssertFalse(spoken.contains("iframe") || spoken.contains("research") || spoken.contains("ccc"), spoken)
        let after = try XCTUnwrap(document.passages.first { passage in passage.text.contains("After the frame.") })
        let afterRange = try XCTUnwrap(after.sourceRange(for: NSRange(location: 0, length: after.text.utf16.count)))
        XCTAssertEqual((note as NSString).substring(with: afterRange), "After the frame.")
    }

    // MARK: Helpers

    private func host<Content: View>(_ view: Content, width: CGFloat = 700, height: CGFloat = 1_200) -> NSWindow {
        let hosting = NSHostingView(rootView: view.frame(width: width, height: height, alignment: .top))
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: width, height: height), styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = hosting
        window.showInvisibly()
        addTeardownBlock { @MainActor in window.contentView = nil; window.orderOut(nil) }
        return window
    }

    private func webViews(in window: NSWindow) -> [WKWebView] {
        window.contentView.map { view in webViews(in: view) } ?? []
    }

    private func webViews(in view: NSView) -> [WKWebView] {
        ((view as? WKWebView).map { webView in [webView] } ?? []) + view.subviews.flatMap { subview in webViews(in: subview) }
    }

    private func settle(_ window: NSWindow) async throws {
        var polls = 0
        try await waitUntil("the window settles") {
            window.contentView?.layoutSubtreeIfNeeded()
            polls += 1
            return polls >= 20
        }
    }
}
