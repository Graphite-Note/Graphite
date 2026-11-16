/**
 * File: WebFrameHostedTests.swift
 * -------------------------------
 * Layer: Tests
 * Description: Hosted tests of web frames (`<iframe>`) on the iPad: the reading view shows a page served by the test at
 *              the tag's size and look, makes no web view far below the screen and gives pages up far above it, says when
 *              a page cannot load, and Live Preview draws the frame, shows its source under the cursor and redraws an
 *              edited tag, with screenshots.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 12/11/2026
 */

#if os(iOS)
import XCTest
import SwiftUI
import WebKit
import GraphiteApple
import GraphiteCore
import GraphiteIndex
@testable import GraphiteUI

/// The owner's note `4_Amdahl's Law in the Multicore Era` shows a grapher in a frame in Obsidian and its tag as text in
/// Graphite (2026-11-12). The pages here are served by the test on the loopback address and hold only text and colour:
/// no test loads a page from the internet, and nothing plays.
@MainActor
final class WebFrameHostedTests: XCTestCase {
    private var window: UIWindow?
    private var server: LoopbackWebServer?

    private static func page(_ name: String, color: String) -> String {
        "<html><head><meta name=\"viewport\" content=\"width=device-width\"><title>\(name)</title></head>"
            + "<body style=\"margin:0;background:\(color);font:24px -apple-system\"><h1 style=\"margin:16px\">\(name)</h1>"
            + "<form style=\"margin:16px\"><input name=\"cores\" value=\"16\"> <button type=\"button\">Draw</button></form></body></html>"
    }

    override func tearDown() async throws {
        window?.isHidden = true
        window?.rootViewController = nil
        window = nil
        server?.stop()
        server = nil
    }

    // MARK: Reading view

    func testTheReadingViewShowsThePageAtTheTagsSizeAndLook() async throws {
        let server = try await LoopbackWebServer(pages: ["/grapher": Self.page("Amdahl's grapher", color: "#cfe8ff")])
        self.server = server
        let note = """
            # Amdahl's Law in the Multicore Era

            The grapher, as the course gives it:

            <iframe src="\(server.address("/grapher").absoluteString)" width="100%" height="500" style="border:1px solid #ccc; border-radius:6px"></iframe>

            Below the frame, a tag: #homework.

            """
        let controller = try await host(note: note, viewMode: .reading)
        let webView = try await loadedWebView(showing: server.address("/grapher"), in: controller)
        XCTAssertEqual(webView.bounds.height, 500, accuracy: 0.5, "The tag's height.")
        let column = try XCTUnwrap(webView.superview?.superview).bounds.width
        XCTAssertGreaterThan(webView.bounds.width, 300)
        XCTAssertLessThanOrEqual(webView.bounds.width, ReadingConfiguration.readableColumnWidth + 0.5, "Never wider than the column (\(column)).")
        XCTAssertEqual(webView.configuration.mediaTypesRequiringUserActionForPlayback, .all)
        XCTAssertTrue(webView.configuration.allowsInlineMediaPlayback)
        let heading = try await webView.evaluateJavaScript("document.querySelector('h1').textContent") as? String
        XCTAssertEqual(heading, "Amdahl's grapher", "The page's scripts run.")
        let snapshot = try await webView.takeSnapshot(configuration: nil)
        add(attachment(of: snapshot, named: "The page in its frame, as WebKit drew it"))
        attachScreenshot(named: "The reading view with the frame")
    }

    /// Ten frames 600 points tall: the reading view makes web views only for the few near the screen, and gives those
    /// far above up as the note scrolls to its end, never holding more than four.
    func testFramesFarFromTheScreenHoldNoPage() async throws {
        let paths = (1...10).map { number in "/frame\(number)" }
        let colors = ["#ffd6d6", "#d6ffd6", "#d6d6ff", "#fff3c4", "#e4d6ff", "#c4fff7", "#ffd6f3", "#e0e0e0", "#d6f0ff", "#f0ffd6"]
        let server = try await LoopbackWebServer(pages: Dictionary(uniqueKeysWithValues: paths.enumerated().map { index, path in
            (path, Self.page("Frame \(index + 1)", color: colors[index]))
        }))
        self.server = server
        let note = paths.enumerated().map { index, path in
            "## Frame \(index + 1)\n\n<iframe src=\"\(server.address(path).absoluteString)\" width=\"100%\" height=\"600\"></iframe>\n\nAfter frame \(index + 1)."
        }.joined(separator: "\n\n")
        let footprintBefore = Self.memoryFootprintMegabytes()
        let controller = try await host(note: note, viewMode: .reading)
        _ = try await loadedWebView(showing: server.address("/frame1"), in: controller)
        XCTAssertLessThanOrEqual(webViews(in: controller.view).count, WebFrameLiveSelection.maximumLiveCount)
        XCTAssertFalse(server.requestedPaths.contains("/frame10"), "The last frame, screens below, is not loaded: \(server.requestedPaths)")
        attachScreenshot(named: "Ten frames: the top of the note")

        let scrollView = try noteScrollView(in: controller)
        var mostWebViews = 0
        var offset: CGFloat = 0
        while offset < scrollView.contentSize.height - scrollView.bounds.height {
            offset = min(offset + scrollView.bounds.height / 2, scrollView.contentSize.height - scrollView.bounds.height)
            scrollView.setContentOffset(CGPoint(x: 0, y: offset), animated: false)
            try await settle(controller)
            mostWebViews = max(mostWebViews, webViews(in: controller.view).count)
        }
        _ = try await loadedWebView(showing: server.address("/frame10"), in: controller)
        let footprintScrolled = Self.memoryFootprintMegabytes()
        XCTAssertLessThanOrEqual(mostWebViews, WebFrameLiveSelection.maximumLiveCount, "At most four pages at once while scrolling.")
        XCTAssertEqual(Set(server.requestedPaths), Set(paths), "Every frame the note scrolled past loaded its page.")
        XCTAssertFalse(webViews(in: controller.view).contains { webView in webView.url == server.address("/frame1") }, "The first page is given up.")
        attachScreenshot(named: "Ten frames: the end of the note")
        window?.rootViewController = nil
        try await waitUntil("the note's web views go") { WebFrameHostedTests.liveWebViewCount() == 0 }
        let footprintClosed = Self.memoryFootprintMegabytes()
        let memory = "App memory footprint: before \(footprintBefore) MB, scrolled to the end \(footprintScrolled) MB, closed \(footprintClosed) MB; "
            + "most web views at once \(mostWebViews); pages asked for: \(server.requestedPaths.joined(separator: " "))"
        let record = XCTAttachment(string: memory)
        record.name = "Memory with ten frames"
        record.lifetime = .keepAlways
        add(record)
    }

    func testAPageThatCannotLoadSaysSoWithItsAddress() async throws {
        let closedServer = try await LoopbackWebServer(pages: [:])
        closedServer.stop()
        let address = closedServer.address("/gone")
        try Self.setAccessibilityRuntimeEnabled(true)
        defer { try? Self.setAccessibilityRuntimeEnabled(false) }
        let controller = try await host(note: "Before\n\n<iframe src=\"\(address.absoluteString)\" height=\"260\"></iframe>\n\nAfter", viewMode: .reading)
        try await waitUntil("the frame says the page can't be shown", timeoutSeconds: 30) {
            self.accessibilityLabels(in: controller.view).contains("This page can't be shown here.")
        }
        let labels = accessibilityLabels(in: controller.view)
        XCTAssertTrue(labels.contains("The site isn't answering."), "\(labels)")
        XCTAssertTrue(labels.contains("127.0.0.1"), "The site's address.")
        XCTAssertTrue(labels.contains("Open in Browser"))
        XCTAssertTrue(labels.contains("Try Again"))
        attachScreenshot(named: "A frame whose page cannot load")
    }

    // MARK: Live Preview

    func testLivePreviewDrawsTheFrameShowsItsSourceUnderTheCursorAndRedrawsAnEditedTag() async throws {
        let server = try await LoopbackWebServer(pages: ["/grapher": Self.page("Live grapher", color: "#ffe1c4"), "/other": Self.page("Other page", color: "#c4ffd0")])
        self.server = server
        let tag = "<iframe src=\"\(server.address("/grapher").absoluteString)\" width=\"100%\" height=\"420\" style=\"border:2px solid #f80; border-radius:12px\"></iframe>"
        let note = "# Live\n\nIntro line.\n\n" + tag + "\n\nAfter the frame.\n"
        let controller = try await host(note: note, viewMode: .livePreview)
        let editor = try await liveEditor(in: controller)
        let webView = try await loadedWebView(showing: server.address("/grapher"), in: controller)
        XCTAssertEqual(webView.bounds.height, 420, accuracy: 0.5)
        attachScreenshot(named: "Live Preview: the frame over its tag")

        editor.beginEditing()
        try await waitUntil("the editor has the keyboard") { editor.isFirstResponder }
        let source = editor.text as NSString
        select(NSRange(location: source.range(of: "Intro").location + 2, length: 0), in: editor)
        try await settle(controller)
        XCTAssertTrue(webViews(in: controller.view).contains { webView in webView.url == server.address("/grapher") }, "The cursor elsewhere keeps the page.")
        select(NSRange(location: source.range(of: "height=\"420\"").location + 9, length: 0), in: editor)
        try await waitUntil("the cursor on the tag shows its source") { self.webViews(in: controller.view).isEmpty }
        attachScreenshot(named: "Live Preview: the cursor on the tag shows its source")

        // The tag edited where the cursor is: a new height and address, drawn once the cursor leaves.
        let heightRange = source.range(of: "420")
        editor.textStorage.replaceCharacters(in: heightRange, with: "300")
        editor.delegate?.textViewDidChange?(editor)
        let edited = editor.text as NSString
        let addressRange = edited.range(of: "/grapher")
        editor.textStorage.replaceCharacters(in: addressRange, with: "/other")
        editor.delegate?.textViewDidChange?(editor)
        select(NSRange(location: (editor.text as NSString).range(of: "After the frame").location + 3, length: 0), in: editor)
        let redrawn = try await loadedWebView(showing: server.address("/other"), in: controller)
        XCTAssertEqual(redrawn.bounds.height, 300, accuracy: 0.5, "The edited height.")
        attachScreenshot(named: "Live Preview: the edited tag redrawn")
    }

    // MARK: Helpers

    private func host(note: String, viewMode: NoteViewMode) async throws -> UIHostingController<GraphiteRootView> {
        let vault = try TemporaryVault.make(prefix: "WebFrames", files: ["HW3/Frames.md": note], for: self)
        try FileManager.default.createDirectory(at: vault.cacheDirectory, withIntermediateDirectories: true)
        let workspace = WorkspaceModel()
        workspace.folderAccess = FolderAccess(root: vault.root)
        workspace.store = VaultStore(root: vault.root)
        let index = try VaultIndex(databaseURL: vault.cacheDirectory.appendingPathComponent("index.sqlite"))
        _ = try await index.reconcile(root: vault.root)
        workspace.index = index
        await workspace.open(try VaultPath("HW3/Frames.md"))
        try XCTUnwrap(workspace.markdownSession).viewMode = viewMode
        let controller = UIHostingController(rootView: GraphiteRootView(workspace: workspace))
        controller.traitOverrides.horizontalSizeClass = .regular
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { scene in scene as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.effectiveGeometry.coordinateSpace.bounds
        window.rootViewController = controller
        window.overrideUserInterfaceStyle = .light
        window.makeKeyAndVisible()
        self.window = window
        return controller
    }

    private func loadedWebView(showing address: URL, in controller: UIViewController) async throws -> WKWebView {
        var found: WKWebView?
        try await waitUntil("the frame shows \(address.path)", timeoutSeconds: 40) {
            found = self.webViews(in: controller.view).first { webView in webView.url == address && !webView.isLoading }
            guard let webView = found else { return false }
            return (try? await webView.evaluateJavaScript("document.readyState") as? String) == "complete"
        }
        // Drawn: a moment for WebKit to paint what it loaded.
        try await settle(controller)
        return try XCTUnwrap(found)
    }

    private func liveEditor(in controller: UIViewController) async throws -> MarkdownTextView {
        var editor: MarkdownTextView?
        try await waitUntil("the Live Preview editor is laid out") {
            editor = self.descendants(of: controller.view, matching: MarkdownTextView.self).first { editor in editor.bounds.width > 0 && editor.window != nil }
            return editor != nil
        }
        return try XCTUnwrap(editor)
    }

    private func select(_ range: NSRange, in editor: MarkdownTextView) {
        editor.selectedRange = range
        // UIKit reports a selection it changed itself; a selection set in code is reported here.
        editor.delegate?.textViewDidChangeSelection?(editor)
    }

    private func noteScrollView(in controller: UIViewController) throws -> UIScrollView {
        let scrollViews = descendants(of: controller.view, matching: UIScrollView.self).filter { scrollView in
            scrollView.window != nil && !(scrollView.superview is WKWebView) && scrollView.contentSize.height > scrollView.bounds.height
                && scrollView.bounds.width > 300 && !self.isInsideWebView(scrollView)
        }
        return try XCTUnwrap(scrollViews.max { leftView, rightView in leftView.contentSize.height < rightView.contentSize.height })
    }

    private func isInsideWebView(_ view: UIView) -> Bool {
        var ancestor = view.superview
        while let current = ancestor {
            if current is WKWebView { return true }
            ancestor = current.superview
        }
        return false
    }

    /// Lets the views lay out and the pages draw for a moment.
    private func settle(_ controller: UIViewController) async throws {
        var polls = 0
        try await waitUntil("the note settles") {
            controller.view.layoutIfNeeded()
            polls += 1
            return polls >= 25
        }
    }

    private func webViews(in view: UIView) -> [WKWebView] {
        descendants(of: view, matching: WKWebView.self).filter { webView in webView.window != nil }
    }

    private static func liveWebViewCount() -> Int {
        UIApplication.shared.connectedScenes.compactMap { scene in scene as? UIWindowScene }.flatMap(\.windows)
            .reduce(0) { count, window in count + WebFrameHostedTests.descendantWebViewCount(of: window) }
    }

    private static func descendantWebViewCount(of view: UIView) -> Int {
        (view is WKWebView ? 1 : 0) + view.subviews.reduce(0) { count, subview in count + descendantWebViewCount(of: subview) }
    }

    private func descendants<View: UIView>(of parent: UIView, matching type: View.Type) -> [View] {
        parent.subviews.flatMap { child in
            ((child as? View).map { matchingChild in [matchingChild] } ?? []) + descendants(of: child, matching: type)
        }
    }

    /// The app's own memory, as the system counts it against the app; web pages are drawn in WebKit's processes of
    /// their own, which this does not include.
    private static func memoryFootprintMegabytes() -> Int {
        var information = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &information) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { integers in
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), integers, &count)
            }
        }
        return result == KERN_SUCCESS ? Int(information.phys_footprint / 1_048_576) : -1
    }

    private func accessibilityLabels(in view: UIView) -> [String] {
        accessibilityElements(in: view).compactMap(\.accessibilityLabel)
    }

    private func accessibilityElements(in object: NSObject) -> [NSObject] {
        var elements: [NSObject] = object.isAccessibilityElement ? [object] : []
        let count = object.accessibilityElementCount()
        if let children = object.accessibilityElements {
            elements += children.compactMap { child in child as? NSObject }.flatMap(accessibilityElements)
        } else if count != NSNotFound, count > 0 {
            elements += (0..<count).compactMap { elementIndex in object.accessibilityElement(at: elementIndex) as? NSObject }.flatMap(accessibilityElements)
        } else if let view = object as? UIView {
            elements += view.subviews.flatMap(accessibilityElements)
        }
        return elements
    }

    private static func setAccessibilityRuntimeEnabled(_ isEnabled: Bool) throws {
        let library = try XCTUnwrap(dlopen("/usr/lib/libAccessibility.dylib", RTLD_NOW), "The simulator's accessibility library.")
        typealias Setter = @convention(c) (Int32) -> Void
        for name in ["_AXSSetAutomationEnabled", "_AXSApplicationAccessibilitySetEnabled"] {
            let symbol = try XCTUnwrap(dlsym(library, name), name)
            unsafeBitCast(symbol, to: Setter.self)(isEnabled ? 1 : 0)
        }
    }

    private func attachment(of image: UIImage, named name: String) -> XCTAttachment {
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        return attachment
    }

    private func attachScreenshot(named name: String) {
        guard let window else { return }
        let screenshot = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        add(attachment(of: screenshot, named: name))
    }
}
#endif
