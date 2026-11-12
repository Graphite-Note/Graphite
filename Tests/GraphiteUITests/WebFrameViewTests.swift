/**
 * File: WebFrameViewTests.swift
 * -----------------------------
 * Layer: Tests
 * Description: Web frames on the Mac: the reading view's block for the owner's note, tags inside HTML left as text, the
 *              frame's web view at the tag's size with a page served by the test, the web view's limits, a failed load,
 *              placeholders where a live page does not fit, and the page given up when its view leaves the window.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 12/11/2026
 */

import XCTest
import SwiftUI
import WebKit
import GraphiteCore
import GraphiteIndex
@testable import GraphiteUI
import GraphiteTestSupport

@MainActor
final class WebFrameViewTests: XCTestCase {
    private static let ownersLine = #"<iframe src="https://research.cs.wisc.edu/multifacet/amdahl/" width="100%" height="900" style="border:1px solid #ccc; border-radius:6px"></iframe>"#
    /// The test's page: text only, nothing that plays.
    private static let page = "<html><head><title>Grapher</title></head><body style=\"margin:0\"><h1>Amdahl</h1><form><input name=\"f\"></form></body></html>"

    private var vault: URL!
    private var server: LoopbackWebServer?

    override func setUp() async throws {
        vault = try TemporaryVault.make(prefix: "WebFrameVault", for: self).root
    }

    override func tearDown() async throws {
        server?.stop()
        server = nil
        try? FileManager.default.removeItem(at: vault) // Best-effort removal of a temporary folder.
    }

    // MARK: Tags inside HTML (section 1)

    /// The owner's line coloured `#ccc` as a tag. HTML runs, a block of it or a tag in a sentence, are now passed over;
    /// a tag beside the HTML still is one, in the reading view and in Live Preview's rendered blocks alike.
    func testAHashInsideHTMLIsNotATagAndATagBesideItStillIs() throws {
        let parser = ObsidianMarkdownParser(baseURL: vault, textSize: 17, linksTags: true)
        for markdown in [Self.ownersLine, "<div style=\"border: 1px solid #ccc\">\n#inside\n</div>"] {
            let block = try parser.attributedString(for: ReadingBlockText.readingText(markdown, colorsEnabled: false, paletteHexByName: [:], usesStrictLineBreaks: false))
            XCTAssertTrue(block.runs.allSatisfy { run in run.link == nil && run.foregroundColor == nil }, markdown)
        }
        let sentence = try parser.attributedString(for: LivePreviewText.prepared("Red <span style=\"color:#f00\">text</span> and #real",
                                                                                 colorsEnabled: false, paletteHexByName: [:]))
        XCTAssertEqual(sentence.runs.compactMap { run in run.link.flatMap(GraphiteOpenLink.tagName(of:)) }, ["real"])
    }

    // MARK: The reading view's block

    func testTheOwnersNoteReadsAsAFrameBetweenItsText() async throws {
        let index = try VaultIndex(databaseURL: vault.appendingPathComponent(".index.sqlite"))
        let note = "# Amdahl's Law in the Multicore Era\n\nThe grapher:\n\n" + Self.ownersLine + "\n\nSee #homework."
        let build = try await ReadingViewBuilder().build(source: note, note: try VaultPath("HW3/4_Amdahl's Law in the Multicore Era.md"), root: vault,
                                                         index: index, configuration: ReadingConfiguration())
        let frames = build.blocks.compactMap { block -> WebFrameEmbed? in if case .webFrame(_, let frame) = block { frame } else { nil } }
        XCTAssertEqual(frames.map(\.address.absoluteString), ["https://research.cs.wisc.edu/multifacet/amdahl/"])
        XCTAssertEqual(frames.first?.shownHeight, 900)
        let texts = build.blocks.compactMap { block -> String? in if case .markdown(_, let text) = block { text } else { nil } }
        XCTAssertFalse(texts.contains { text in text.contains("iframe") }, "The tag is not shown as text.")
        XCTAssertTrue(NotePDFBlocks.markdownTexts(in: try XCTUnwrap(build.blocks.first { block in if case .webFrame = block { true } else { false } }))
            .contains("<https://research.cs.wisc.edu/multifacet/amdahl/>"), "A printed frame's address is a link.")
    }

    // MARK: The live page

    func testTheFrameShowsThePageAtTheTagsSizeAndLook() async throws {
        let server = try await LoopbackWebServer(pages: ["/grapher": Self.page])
        self.server = server
        let frame = try XCTUnwrap(frame(src: server.address("/grapher").absoluteString, attributes: #"width="400" height="200" style="border: 2px solid #f00; border-radius: 8px""#))
        let window = host(WebFrameBlock(frame: frame).environment(\.webFramePresentation, .live))
        let webView = try await loadedWebView(in: window)
        XCTAssertEqual(webView.url, server.address("/grapher"))
        XCTAssertEqual(webView.bounds.size, CGSize(width: 400, height: 200), "The tag's size.")
        XCTAssertEqual(server.requestedPaths.filter { path in path == "/grapher" }.count, 1)
        let title = try await webView.evaluateJavaScript("document.title") as? String
        XCTAssertEqual(title, "Grapher", "The page's scripts run.")
        // The web view's limits: Graphite's own data store, nothing plays by itself, and no way into the app.
        let configuration = webView.configuration
        XCTAssertEqual(configuration.websiteDataStore.identifier, WebFrameWebViews.dataStoreIdentifier)
        XCTAssertEqual(configuration.mediaTypesRequiringUserActionForPlayback, .all)
        XCTAssertFalse(configuration.preferences.javaScriptCanOpenWindowsAutomatically)
        let messageHandlers = try await webView.evaluateJavaScript("typeof window.webkit === 'undefined' || typeof window.webkit.messageHandlers === 'undefined' ? 0 : Object.keys(window.webkit.messageHandlers).length") as? Int
        XCTAssertEqual(messageHandlers ?? 0, 0, "No message reaches Graphite.")
        XCTAssertNil(configuration.urlSchemeHandler(forURLScheme: CommunityPluginSchemeHandler.scheme), "No vault files.")
        XCTAssertTrue(configuration.userContentController.userScripts.isEmpty)
    }

    func testTheFrameAllowsOnlyWebPagesAndSendsNewWindowsToTheBrowser() async throws {
        XCTAssertTrue(WebFrameWebViews.allowsNavigation(to: URL(string: "https://example.com/next"), isMainFrame: true))
        XCTAssertFalse(WebFrameWebViews.allowsNavigation(to: vault.appendingPathComponent("Note.md"), isMainFrame: true), "No file of the vault.")
        XCTAssertFalse(WebFrameWebViews.allowsNavigation(to: URL(string: "graphite://open?path=Note.md"), isMainFrame: true), "Not Graphite's own links.")
        XCTAssertFalse(WebFrameWebViews.allowsNavigation(to: URL(string: "about:blank"), isMainFrame: true))
        XCTAssertTrue(WebFrameWebViews.allowsNavigation(to: URL(string: "about:blank"), isMainFrame: false), "A page's own blank frame.")
        let server = try await LoopbackWebServer(pages: ["/links": "<html><body><a id=\"out\" href=\"https://example.com/elsewhere\" target=\"_blank\">Out</a></body></html>"])
        self.server = server
        let controller = WebFramePageController()
        var opened: [URL] = []
        controller.openExternally = { address in opened.append(address) }
        let webView = WebFrameWebViews.make()
        let window = host(WebViewHost(webView: webView))
        _ = window
        controller.attach(webView, address: server.address("/links"))
        try await waitUntil("the page loads") { controller.loadState == .loaded }
        _ = try await webView.evaluateJavaScript("document.getElementById('out').click(); 0")
        try await waitUntil("the link opens in the browser") { !opened.isEmpty }
        XCTAssertEqual(opened, [URL(string: "https://example.com/elsewhere")])
        XCTAssertEqual(webView.url, server.address("/links"), "The frame keeps its page.")
        controller.detach(webView)
    }

    func testAPageThatCannotLoadSaysSo() async throws {
        let controller = WebFramePageController()
        let webView = WebFrameWebViews.make()
        let window = host(WebViewHost(webView: webView))
        _ = window
        // A port of the loopback address that a server of the test held and let go: nothing listens there, so the
        // connection is refused at once, with no internet asked.
        let closedServer = try await LoopbackWebServer(pages: [:])
        closedServer.stop()
        controller.attach(webView, address: closedServer.address("/missing"))
        try await waitUntil("the load fails") { if case .failed = controller.loadState { true } else { false } }
        XCTAssertEqual(controller.loadState, .failed("The site isn't answering."))
        controller.detach(webView)
        XCTAssertNil(webView.navigationDelegate)
    }

    // MARK: The Mac reading view

    /// The reading view of a note of eight frames 400 points tall: the frames near the screen hold their pages, at the
    /// column's width and the tag's height, the others wait; scrolled to the end, the first frames give their pages up
    /// and the last ones load theirs, never more than four at once.
    func testTheMacReadingViewLoadsOnlyTheFramesNearTheScreen() async throws {
        let pages = Dictionary(uniqueKeysWithValues: (1...8).map { number in ("/frame\(number)", "<html><body><h1>Frame \(number)</h1></body></html>") })
        let server = try await LoopbackWebServer(pages: pages)
        self.server = server
        let note = (1...8).map { number in
            "## Frame \(number)\n\n<iframe src=\"\(server.address("/frame\(number)").absoluteString)\" width=\"100%\" height=\"400\"></iframe>\n\nText after \(number)."
        }.joined(separator: "\n\n")
        let index = try VaultIndex(databaseURL: vault.appendingPathComponent(".index.sqlite"))
        let preview = MarkdownPreview(source: note, path: try VaultPath("Frames.md"), root: vault, index: index, configuration: ReadingConfiguration(),
                                      headingScrollRequest: .constant(nil), handledScrollToken: .constant(nil),
                                      navigate: { _, _ in }, openPDF: { _, _ in }, updateProperties: nil)
        let window = host(preview, width: 900, height: 900)
        try await waitUntil("the first frame's page loads", timeoutSeconds: 30) {
            window.contentView?.layoutSubtreeIfNeeded()
            return self.webViews(in: window).contains { webView in webView.url == server.address("/frame1") && !webView.isLoading }
        }
        let first = try XCTUnwrap(webViews(in: window).first { webView in webView.url == server.address("/frame1") })
        XCTAssertEqual(first.bounds.height, 400, accuracy: 0.5)
        XCTAssertEqual(first.bounds.width, ReadingConfiguration.readableColumnWidth, accuracy: 0.5, "100% of the readable column.")
        XCTAssertLessThanOrEqual(webViews(in: window).count, WebFrameLiveSelection.maximumLiveCount)
        XCTAssertFalse(server.requestedPaths.contains("/frame8"), "The last frame, screens below, is not loaded.")
        let scrollView = try XCTUnwrap(scrollViews(in: try XCTUnwrap(window.contentView)).max { leftView, rightView in
            (leftView.documentView?.frame.height ?? 0) < (rightView.documentView?.frame.height ?? 0)
        })
        try await waitUntil("the last frame's page loads once the note is scrolled to its end", timeoutSeconds: 30) {
            let bottom = max(0, (scrollView.documentView?.frame.height ?? 0) - scrollView.contentView.bounds.height)
            scrollView.contentView.scroll(to: CGPoint(x: 0, y: bottom))
            scrollView.reflectScrolledClipView(scrollView.contentView)
            window.contentView?.layoutSubtreeIfNeeded()
            return self.webViews(in: window).contains { webView in webView.url == server.address("/frame8") }
        }
        try await waitUntil("the first frame's page is given up") {
            window.contentView?.layoutSubtreeIfNeeded()
            return !self.webViews(in: window).contains { webView in webView.url == server.address("/frame1") }
        }
        XCTAssertLessThanOrEqual(webViews(in: window).count, WebFrameLiveSelection.maximumLiveCount)
    }

    // MARK: Live Preview's reserved height and kept views

    /// Live Preview reserves the tag's height (and the block's padding) before the page loads, and never keeps a frame's
    /// view, or a callout's that holds one, off screen or makes it ahead.
    func testLivePreviewReservesTheTagsHeightAndKeepsNoFrameOffScreen() throws {
        let note = "Intro\n\n" + Self.ownersLine + "\n\n> [!tip] Grapher\n> " + Self.ownersLine + "\n\n> [!note] Plain\n> Text only.\n"
        let blocks = LivePreviewBlockScanner.blocks(in: note as NSString)
        let frame = try XCTUnwrap(blocks.first { block in if case .webFrame = block.kind { true } else { false } })
        XCTAssertEqual(LivePreviewBlockHeightEstimate.height(of: frame, columnWidth: 700), 908, "The tag's 900 points and the block's 8 of padding.")
        XCTAssertNil(DetachedWidgetPool<Int>.estimatedMegabytes(of: frame))
        let callouts = blocks.filter { block in block.kind == .callout }
        XCTAssertEqual(callouts.count, 2)
        XCTAssertNil(DetachedWidgetPool<Int>.estimatedMegabytes(of: callouts[0]), "A callout holding a frame is not kept off screen.")
        XCTAssertNotNil(DetachedWidgetPool<Int>.estimatedMegabytes(of: callouts[1]))
    }

    // MARK: Where no live page is made

    func testPlaceholdersPrintedFramesAndANoteWithoutFramesMakeNoWebView() async throws {
        let frame = try XCTUnwrap(frame(src: "https://example.com/page", attributes: #"height="600""#))
        for presentation in [WebFramePresentation.placeholder, .printed] {
            let window = host(WebFrameBlock(frame: frame).environment(\.webFramePresentation, presentation))
            try await settle(window)
            XCTAssertTrue(webViews(in: window).isEmpty, "\(presentation)")
            window.contentView = nil
        }
        // The default, for any new place that shows a note's blocks, is the placeholder.
        let unset = host(WebFrameBlock(frame: frame))
        try await settle(unset)
        XCTAssertTrue(webViews(in: unset).isEmpty)
        let index = try VaultIndex(databaseURL: vault.appendingPathComponent(".index.sqlite"))
        let plain = try await ReadingViewBuilder().build(source: "# Plain\n\nNo frames here.", note: try VaultPath("Plain.md"), root: vault, index: index,
                                                         configuration: ReadingConfiguration())
        let readingWindow = host(ReadingBlocksView(blocks: plain.blocks, root: vault, textSize: 17, navigate: { _, _ in }, scrollToHeading: { _ in },
                                                   openPDF: { _, _ in }, updateProperties: nil).environment(\.webFramePresentation, .live))
        try await settle(readingWindow)
        XCTAssertTrue(webViews(in: readingWindow).isEmpty, "A note without frames makes no web view.")
    }

    /// A Live Preview block's view taken off screen into the pool of kept views leaves the window: its page goes with it.
    /// YouTube's player refused the frame's embed with Error 153 on the Mac (2026-11-12): a web view loading a page by
    /// itself sends no `Referer`, and YouTube asks an application that embeds it to send `https://` and its bundle identifier.
    func testThePageIsAskedForWithGraphitesIdentityAsItsReferrer() async throws {
        let address = try XCTUnwrap(URL(string: "https://www.youtube.com/embed/example"))
        XCTAssertEqual(WebFrameWebViews.request(for: address, bundleIdentifier: "com.graphite.study").value(forHTTPHeaderField: "Referer"),
                       "https://com.graphite.study/")
        XCTAssertNil(WebFrameWebViews.request(for: address, bundleIdentifier: nil).value(forHTTPHeaderField: "Referer"))
        XCTAssertEqual(WebFrameWebViews.request(for: address, bundleIdentifier: "com.graphite.study").url, address)
        let server = try await LoopbackWebServer(pages: ["/grapher": Self.page])
        self.server = server
        let controller = WebFramePageController()
        let webView = WebFrameWebViews.make()
        let window = host(WebViewHost(webView: webView))
        _ = window
        controller.attach(webView, address: server.address("/grapher"))
        try await waitUntil("the page loads") { controller.loadState == .loaded }
        let expected = Bundle.main.bundleIdentifier.map { identifier in "https://\(identifier)/" } ?? ""
        XCTAssertEqual(server.requestedReferrers.first, expected, "The web view sends the request's referrer.")
        controller.detach(webView)
    }

    /// A page that could not load showed a white box with only its buttons in the dark appearance (2026-11-12): the failed
    /// web view's white showed through the placeholder's tint, under the appearance's white message. The web view is now
    /// hidden until its page has loaded, and shown once it has.
    func testAFramesWebViewIsHiddenUntilItsPageHasLoaded() async throws {
        let closedServer = try await LoopbackWebServer(pages: [:])
        closedServer.stop()
        let failing = try XCTUnwrap(frame(src: closedServer.address("/missing").absoluteString, attributes: #"width="400" height="200""#))
        let failingWindow = host(WebFrameBlock(frame: failing).environment(\.webFramePresentation, .live))
        var failedWebView: WKWebView?
        try await waitUntil("the failing frame's web view has tried its page") {
            failedWebView = self.webViews(in: failingWindow).first
            return failedWebView.map { webView in !webView.isLoading } ?? false
        }
        try await settle(failingWindow)
        XCTAssertEqual(effectiveOpacity(of: try XCTUnwrap(failedWebView)), 0, "A page that failed is not shown under its message.")

        let server = try await LoopbackWebServer(pages: ["/grapher": Self.page])
        self.server = server
        let loading = try XCTUnwrap(frame(src: server.address("/grapher").absoluteString, attributes: #"width="400" height="200""#))
        let window = host(WebFrameBlock(frame: loading).environment(\.webFramePresentation, .live))
        let webView = try await loadedWebView(in: window)
        try await settle(window)
        XCTAssertEqual(effectiveOpacity(of: webView), 1, "A loaded page is shown.")
    }

    func testAFrameGivesItsPageUpWhenItsViewLeavesTheWindowAndLoadsItAgainWhenBack() async throws {
        let server = try await LoopbackWebServer(pages: ["/grapher": Self.page])
        self.server = server
        let frame = try XCTUnwrap(frame(src: server.address("/grapher").absoluteString, attributes: #"height="300""#))
        let hosting = NSHostingView(rootView: AnyView(WebFrameBlock(frame: frame).environment(\.webFramePresentation, .live).frame(width: 500, height: 320)))
        let window = host(Color.clear)
        try XCTUnwrap(window.contentView).addSubview(hosting)
        hosting.frame = CGRect(x: 0, y: 0, width: 500, height: 320)
        _ = try await loadedWebView(in: window)
        hosting.removeFromSuperview()
        XCTAssertTrue(webViews(in: hosting).isEmpty, "The page is given up as its view leaves the window.")
        try XCTUnwrap(window.contentView).addSubview(hosting)
        _ = try await loadedWebView(in: window)
        XCTAssertEqual(server.requestedPaths.filter { path in path == "/grapher" }.count, 2)
    }

    // MARK: Helpers

    private func frame(src: String, attributes: String) -> WebFrameEmbed? {
        let line = "<iframe src=\"\(src)\" \(attributes)></iframe>"
        return WebFrameSyntax.frame(startingAt: 0, lineCount: 1, line: { _ in line })?.frame
    }

    private func host<Content: View>(_ view: Content, width: CGFloat = 640, height: CGFloat = 900) -> NSWindow {
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

    private func scrollViews(in view: NSView) -> [NSScrollView] {
        ((view as? NSScrollView).map { scrollView in [scrollView] } ?? []) + view.subviews.flatMap { subview in scrollViews(in: subview) }
    }

    private func loadedWebView(in window: NSWindow) async throws -> WKWebView {
        var found: WKWebView?
        try await waitUntil("the frame's web view loads its page", timeoutSeconds: 30) {
            found = self.webViews(in: window).first
            guard let webView = found, !webView.isLoading, webView.url != nil else { return false }
            return (try? await webView.evaluateJavaScript("document.readyState") as? String) == "complete"
        }
        return try XCTUnwrap(found)
    }

    /// The opacity a view is drawn with: its own and every view's above it, by their alpha and their layers'.
    private func effectiveOpacity(of view: NSView) -> CGFloat {
        var opacity: CGFloat = 1
        var current: NSView? = view
        while let shown = current {
            opacity *= shown.alphaValue * CGFloat(shown.layer?.opacity ?? 1)
            current = shown.superview
        }
        return opacity
    }

    /// Lets the window lay out and the views' tasks run a few times.
    private func settle(_ window: NSWindow) async throws {
        var polls = 0
        try await waitUntil("the window settles") {
            window.contentView?.layoutSubtreeIfNeeded()
            polls += 1
            return polls >= 20
        }
    }
}

/// A web view in a window, made and kept by the test.
private struct WebViewHost: NSViewRepresentable {
    let webView: WKWebView
    func makeNSView(context: Context) -> WKWebView { webView }
    func updateNSView(_ webView: WKWebView, context: Context) {}
}
