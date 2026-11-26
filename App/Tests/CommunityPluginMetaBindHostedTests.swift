/**
 * File: CommunityPluginMetaBindHostedTests.swift
 * ----------------------------------------------
 * Layer: Tests
 * Description: Meta Bind's buttons and fields on the course page demo, pressed in the copies the reading view
 *              shows, in WebKit inside the app, on the iPad and the Mac.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 27/11/2026
 */
import XCTest
import SwiftUI
import WebKit
import GraphiteCore
@testable import GraphiteUI

/// Meta Bind 1.5.1 and Templater, unmodified, on the course page of the made-up demo vault
/// (`fixtures/meta-bind-course-vault`, which the Node tests walk too). The course page opens in the
/// reading view; its buttons and fields are pressed in the copies Graphite shows in the note, as a
/// person presses them, so the copy's element paths, the plugins' page and Graphite's native vault
/// writes are all on the way. Skipped, as the other real plugins' tests here, when Meta Bind is not
/// downloaded or Templater not built (`npm run build-compatibility-plugins`).
@MainActor
extension CommunityPluginHostTests {
    private static let metaBindIdentifier = "obsidian-meta-bind-plugin"
    private static let templaterIdentifier = "templater-obsidian"
    private static let courseVault = runtimeTestsFolder.appendingPathComponent("fixtures/meta-bind-course-vault")
    private static let coursePagePath = "Signals and Systems/Signals and Systems.md"

    func testMetaBindsCoursePageButtonsMakeNotesFromTemplatesAndItsFieldsWriteTheCoursesProperties() async throws {
        let (workspace, vault) = try await workspaceAndVaultWithBuiltPlugins([Self.templaterIdentifier, Self.metaBindIdentifier], notes: try courseVaultNotes())
        let host = workspace.communityPlugins
        try await waitUntil("Meta Bind draws its blocks", timeoutSeconds: 15) { host.codeBlockLanguages.contains("meta-bind-button") }
        try await openInReadingView(Self.coursePagePath, in: workspace)

        // The status field, in a line of text: Graphite's copy keeps the paragraph whole, so the
        // choice reaches Meta Bind's own select, which writes the property.
        let coursePage = vault.appendingPathComponent(Self.coursePagePath)
        try await choose("Done", inSelectOf: "mb-input-type-inlineSelect", host: host)
        try await waitUntil("the status field writes the property", timeoutSeconds: 10) {
            (try? String(contentsOf: coursePage, encoding: .utf8))?.contains("status: Done\n") == true
        }
        // For about a second after its own write Meta Bind ignores the note's changes, by its design
        // (five cycles of 200 ms), and later writes back what it holds: Templater's count of lectures, made
        // within that second, would be lost, in Obsidian too. A person is slower than this test.
        try await waitUntilMetaBindTakesChanges(of: Self.coursePagePath, host: host)

        try await press(button: "New assignment", host: host)
        let assignment = vault.appendingPathComponent("Signals and Systems/Assignments/New assignment.md")
        try await waitUntil("New assignment makes its note", timeoutSeconds: 15) { FileManager.default.fileExists(atPath: assignment.path) }
        let assignmentText = try await settledText(of: assignment)
        XCTAssertTrue(assignmentText.hasPrefix("---\ncourse: \"[[Signals and Systems]]\"\ntype: assignment\nstatus: To do\ndue: "), assignmentText)
        XCTAssertTrue(assignmentText.contains("\n# New assignment\n"), "Templater filled in the title: " + assignmentText)
        XCTAssertFalse(assignmentText.contains("<%"), "every Templater command ran: " + assignmentText)
        try await waitUntil("Graphite opens the new assignment") { workspace.layout.activeTab.path?.rawValue == "Signals and Systems/Assignments/New assignment.md" }

        try await openInReadingView(Self.coursePagePath, in: workspace)
        try await press(button: "Start lecture", host: host)
        let lecture = vault.appendingPathComponent("Signals and Systems/Lectures/Lecture 2.md")
        try await waitUntil("Start lecture makes the second lecture", timeoutSeconds: 15) { FileManager.default.fileExists(atPath: lecture.path) }
        let lectureText = try await settledText(of: lecture)
        XCTAssertTrue(lectureText.hasPrefix("---\ncourse: \"[[Signals and Systems]]\"\ntype: lecture\nnumber: 2\ndate: "), lectureText)
        try await waitUntil("Graphite opens the lecture") { workspace.layout.activeTab.path?.rawValue == "Signals and Systems/Lectures/Lecture 2.md" }
        try await waitUntil("the course page counts the lecture") { (try? String(contentsOf: coursePage, encoding: .utf8))?.contains("lectures_held: 2\n") == true }


        // The line of fields again, on the page opened again: drawn again while the reading view lays
        // the page out, it stays Meta Bind's (once in five runs on the Mac it came out as Graphite's
        // own text, issue #235: `CommunityPluginRedrawnSectionTests`).
        try await openInReadingView(Self.coursePagePath, in: workspace)
        try await choose("Not started", inSelectOf: "mb-input-type-inlineSelect", host: host)
        try await waitUntil("the status field writes the property again", timeoutSeconds: 10) {
            (try? String(contentsOf: coursePage, encoding: .utf8))?.contains("status: Not started\n") == true
        }

        let courseText = try String(contentsOf: coursePage, encoding: .utf8)
        let original = try String(contentsOf: Self.courseVault.appendingPathComponent(Self.coursePagePath), encoding: .utf8)
        XCTAssertEqual(courseText, original.replacingOccurrences(of: "lectures_held: 1", with: "lectures_held: 2")
            .replacingOccurrences(of: "status: In progress", with: "status: Not started"), "the course page changed in its two properties alone")
        XCTAssertNil(host.runtimeProblems[Self.metaBindIdentifier], "Meta Bind failed nowhere")
    }

    /// In Live Preview, Meta Bind's `meta-bind` block is drawn (its inline fields are CodeMirror widgets
    /// there and stay code), showing the course page's own value.
    func testMetaBindsBlockInLivePreviewShowsTheCoursesValue() async throws {
        let (workspace, _) = try await workspaceAndVaultWithBuiltPlugins([Self.templaterIdentifier, Self.metaBindIdentifier], notes: try courseVaultNotes())
        let host = workspace.communityPlugins
        try await waitUntil("Meta Bind draws its blocks", timeoutSeconds: 15) { host.codeBlockLanguages.contains("meta-bind") }
        let vaultPath = try VaultPath(Self.coursePagePath)
        await workspace.open(vaultPath, placement: .currentTab)
        let tab = try XCTUnwrap(workspace.layout.tabID(showing: vaultPath))
        workspace.document(for: tab).markdownSession?.viewMode = .livePreview
        let script = """
        const bar = document.querySelector('.mb-input-type-progressBar');
        return bar ? bar.getAttribute('data-internal-value') : null;
        """
        var shownValue: String?
        try await waitUntil("the copy shows the bar with the course's value", timeoutSeconds: 15) {
            for webView in self.copyWebViews(host: host) {
                if let value = try? await webView.callAsyncJavaScript(script, arguments: [:], in: nil, contentWorld: .defaultClient) as? String {
                    shownValue = value
                    if value == "1" { return true }
                }
            }
            return false
        }
        let pageValue = try await host.webView?.callAsyncJavaScript(script, arguments: [:], in: nil, contentWorld: .page) as? String
        let stateScript = """
        const app = window.GraphitePluginRuntime.app;
        const file = app.vault.getFileByPath(path);
        const cache = file ? app.metadataCache.getFileCache(file) : null;
        const source = app.plugins.plugins['obsidian-meta-bind-plugin'].mb.metadataManager.sources.get('frontmatter');
        const item = source && source.cache ? source.cache.get(path) : undefined;
        return JSON.stringify({ file: Boolean(file), frontmatter: cache && cache.frontmatter, metaBind: item ? item.data : null });
        """
        let state = try? await host.webView?.callAsyncJavaScript(stateScript, arguments: ["path": Self.coursePagePath], in: nil, contentWorld: .page) as? String
        XCTAssertEqual(shownValue, "1", "the plugins' page has \(pageValue ?? "no bar"); \(state ?? "no state")")
    }

    /// A `meta-bind-button` block in a note open in Live Preview: drawn there, and its press changes
    /// the note through the vault, which the open note's editor takes in.
    func testMetaBindsButtonInLivePreviewChangesTheOpenNote() async throws {
        let note = "---\nstatus: todo\n---\n# Week\n\n```meta-bind-button\nlabel: Mark done\nstyle: primary\naction:\n  type: updateMetadata\n"
            + "  bindTarget: status\n  evaluate: false\n  value: done\n```\n"
        let (workspace, vault) = try await workspaceAndVaultWithBuiltPlugins([Self.metaBindIdentifier], notes: ["Week.md": note])
        let host = workspace.communityPlugins
        try await waitUntil("Meta Bind draws its buttons", timeoutSeconds: 15) { host.codeBlockLanguages.contains("meta-bind-button") }
        let vaultPath = try VaultPath("Week.md")
        await workspace.open(vaultPath, placement: .currentTab)
        let tab = try XCTUnwrap(workspace.layout.tabID(showing: vaultPath))
        let session = try XCTUnwrap(workspace.document(for: tab).markdownSession)
        session.viewMode = .livePreview
        try await press(button: "Mark done", host: host)
        let changed = note.replacingOccurrences(of: "status: todo", with: "status: done")
        try await waitUntil("the button writes the note", timeoutSeconds: 10) {
            (try? String(contentsOf: vault.appendingPathComponent("Week.md"), encoding: .utf8)) == changed
        }
        try await waitUntil("the open note takes the change in", timeoutSeconds: 10) { session.text == changed }
    }

    /// Until Meta Bind's cache of the note takes another app's changes again (its write lock is over).
    private func waitUntilMetaBindTakesChanges(of path: String, host: CommunityPluginHost) async throws {
        let script = """
        const source = window.GraphitePluginRuntime.app.plugins.plugins['obsidian-meta-bind-plugin'].mb.metadataManager.sources.get('frontmatter');
        const item = source.cache.get(path);
        return !item || item.externalWriteLock === 0;
        """
        try await waitUntil("Meta Bind takes the note's changes again", timeoutSeconds: 10) {
            (try? await host.webView?.callAsyncJavaScript(script, arguments: ["path": path], in: nil, contentWorld: .page)) as? Bool == true
        }
    }

    #if os(macOS)
    /// The course page's buttons clicked with the mouse: a mouse-down and mouse-up at each button's place in
    /// the window, given to the web view under it, which WebKit makes a click in the copy as a person's.
    func testMetaBindsCoursePageButtonsAnswerMouseClicksOnTheMac() async throws {
        let (workspace, vault) = try await workspaceAndVaultWithBuiltPlugins([Self.templaterIdentifier, Self.metaBindIdentifier], notes: try courseVaultNotes())
        let host = workspace.communityPlugins
        try await waitUntil("Meta Bind draws its blocks", timeoutSeconds: 15) { host.codeBlockLanguages.contains("meta-bind-button") }
        try await openInReadingView(Self.coursePagePath, in: workspace)

        try await click(button: "New assignment", host: host)
        let assignment = vault.appendingPathComponent("Signals and Systems/Assignments/New assignment.md")
        try await waitUntil("a click on New assignment makes its note", timeoutSeconds: 15) { FileManager.default.fileExists(atPath: assignment.path) }
        try await waitUntil("Graphite opens the new assignment") { workspace.layout.activeTab.path?.rawValue == "Signals and Systems/Assignments/New assignment.md" }

        try await openInReadingView(Self.coursePagePath, in: workspace)
        try await click(button: "Start lecture", host: host)
        let lecture = vault.appendingPathComponent("Signals and Systems/Lectures/Lecture 2.md")
        try await waitUntil("a click on Start lecture makes the second lecture", timeoutSeconds: 15) { FileManager.default.fileExists(atPath: lecture.path) }
        try await waitUntil("Graphite opens the lecture") { workspace.layout.activeTab.path?.rawValue == "Signals and Systems/Lectures/Lecture 2.md" }
    }

    /// Posts a click at the middle of the button labelled `label` in whichever copy shows it.
    private func click(button label: String, host: CommunityPluginHost) async throws {
        let frameScript = """
        const button = Array.from(document.querySelectorAll('button.mb-button-inner')).find((candidate) => candidate.textContent.trim() === label);
        if (!button) return null;
        const bounds = button.getBoundingClientRect();
        return [bounds.left + bounds.width / 2, bounds.top + bounds.height / 2];
        """
        var target: (webView: WKWebView, point: CGPoint)?
        // Found once the copy shows it and the window's views under that point are the copy's: the
        // reading view settles its layout as the note opens.
        try await waitUntil("a copy shows \(label) under the pointer", timeoutSeconds: 15) {
            for webView in self.copyWebViews(host: host) {
                guard let middle = try? await webView.callAsyncJavaScript(frameScript, arguments: ["label": label], in: nil, contentWorld: .defaultClient) as? [Double],
                      middle.count == 2, let window = webView.window else { continue }
                let point = CGPoint(x: middle[0], y: middle[1])
                guard window.contentView?.hitTest(webView.convert(point, to: nil))?.isDescendant(of: webView) == true else { continue }
                target = (webView, point)
                return true
            }
            return false
        }
        guard let target, let window = target.webView.window else { return XCTFail("No copy shows \(label) in a window") }
        let location = target.webView.convert(target.point, to: nil)
        // The app is not active in a test run (macOS refuses a test's activation), and a web view in a
        // window that is not key takes a first click only to activate it: the mouse events are handed to
        // the web view, as AppKit hands them to the view under the pointer, and WebKit makes them a click.
        let down = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown, location: location, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                                    windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
        target.webView.mouseDown(with: down)
        let up = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseUp, location: location, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                                  windowNumber: window.windowNumber, context: nil, eventNumber: 2, clickCount: 1, pressure: 0))
        target.webView.mouseUp(with: up)
    }
    #endif

    // MARK: The demo vault

    /// The demo vault's files, as the Node tests read them.
    private func courseVaultNotes() throws -> [String: String] {
        var notes: [String: String] = [:]
        let enumerator = try XCTUnwrap(FileManager.default.enumerator(at: Self.courseVault, includingPropertiesForKeys: [.isDirectoryKey]))
        for case let location as URL in enumerator where try location.resourceValues(forKeys: [.isDirectoryKey]).isDirectory != true {
            let path = String(location.standardizedFileURL.path.dropFirst(Self.courseVault.standardizedFileURL.path.count + 1))
            notes[path] = try String(contentsOf: location, encoding: .utf8)
        }
        return notes
    }

    private func openInReadingView(_ path: String, in workspace: WorkspaceModel) async throws {
        let vaultPath = try VaultPath(path)
        await workspace.open(vaultPath, placement: .currentTab)
        let tab = try XCTUnwrap(workspace.layout.tabID(showing: vaultPath))
        workspace.document(for: tab).markdownSession?.viewMode = .reading
        // A note opened again keeps where it was scrolled to, and the reading view draws only the
        // plugins' blocks on screen: scrolled to its top, as a person scrolls back to the buttons.
        try await waitUntil("the reading view shows the plugins' copies", timeoutSeconds: 15) { !self.copyWebViews(host: workspace.communityPlugins).isEmpty }
        scrollEveryScrollViewToTheTop()
    }

    private func scrollEveryScrollViewToTheTop() {
        #if os(iOS)
        let roots: [UIView] = UIApplication.shared.connectedScenes.compactMap { scene in scene as? UIWindowScene }.flatMap(\.windows)
        func scrollViews(in view: UIView) -> [UIScrollView] {
            ((view as? UIScrollView).map { [$0] } ?? []) + view.subviews.flatMap { child in scrollViews(in: child) }
        }
        for scrollView in roots.flatMap({ root in scrollViews(in: root) }) where !(scrollView.superview is WKWebView) {
            scrollView.setContentOffset(CGPoint(x: scrollView.contentOffset.x, y: -scrollView.adjustedContentInset.top), animated: false)
        }
        #else
        func scrollViews(in view: NSView) -> [NSScrollView] {
            ((view as? NSScrollView).map { [$0] } ?? []) + view.subviews.flatMap { child in scrollViews(in: child) }
        }
        for scrollView in NSApp.windows.compactMap(\.contentView).flatMap({ root in scrollViews(in: root) }) {
            scrollView.contentView.scroll(to: .zero)
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
        #endif
    }

    /// A note's text once it has stopped changing: Templater writes a new note, then fills it in.
    private func settledText(of file: URL) async throws -> String {
        var lastText = ""
        try await waitUntil("\(file.lastPathComponent) settles", timeoutSeconds: 10) {
            let text = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
            defer { lastText = text }
            return !text.isEmpty && text == lastText
        }
        return lastText
    }

    // MARK: Pressing in the copies

    /// The copies the note shows: every web view in the app's windows but the plugins' own page.
    private func copyWebViews(host: CommunityPluginHost) -> [WKWebView] {
        #if os(iOS)
        let roots: [UIView] = UIApplication.shared.connectedScenes.compactMap { scene in scene as? UIWindowScene }.flatMap(\.windows)
        #else
        let roots: [NSView] = NSApp.windows.compactMap(\.contentView)
        #endif
        return roots.flatMap { root in webViews(in: root) }.filter { webView in webView !== host.webView && webView.window != nil }
    }

    #if os(iOS)
    private func webViews(in view: UIView) -> [WKWebView] {
        ((view as? WKWebView).map { [$0] } ?? []) + view.subviews.flatMap { child in webViews(in: child) }
    }
    #else
    private func webViews(in view: NSView) -> [WKWebView] {
        ((view as? WKWebView).map { [$0] } ?? []) + view.subviews.flatMap { child in webViews(in: child) }
    }
    #endif

    /// Runs `script` in Graphite's world of each copy until one answers true: the copy's own
    /// listeners hear the event it dispatches and send it to the plugin, as a person's tap is sent.
    private func runInCopies(_ description: String, script: String, arguments: [String: Any], host: CommunityPluginHost) async throws {
        var isDone = false
        try await waitUntil(description, timeoutSeconds: 15) {
            for webView in self.copyWebViews(host: host) {
                let answer = try? await webView.callAsyncJavaScript(script, arguments: arguments, in: nil, contentWorld: .defaultClient)
                if answer as? Bool == true { isDone = true; return true }
            }
            return isDone
        }
        guard !isDone else { return }
        var shown: [String] = []
        for webView in copyWebViews(host: host) {
            let text = try? await webView.callAsyncJavaScript("const root = document.querySelector('.graphite-code-block-root'); return root ? root.innerHTML.slice(0, 400) : '';",
                                                                arguments: [:], in: nil, contentWorld: .defaultClient) as? String
            shown.append(text ?? "?")
        }
        XCTFail("The copies show: \(shown)")
    }

    private func press(button label: String, host: CommunityPluginHost) async throws {
        let script = """
        const button = Array.from(document.querySelectorAll('button.mb-button-inner')).find((candidate) => candidate.textContent.trim() === label);
        if (!button) return false;
        button.click();
        return true;
        """
        try await runInCopies("the copy shows and presses \(label)", script: script, arguments: ["label": label], host: host)
    }

    private func choose(_ option: String, inSelectOf wrapperClass: String, host: CommunityPluginHost) async throws {
        let script = """
        const select = document.querySelector('.' + wrapperClass + ' select');
        if (!select) return false;
        if (select.closest('p') === null) throw new Error('The field is not inside its paragraph: ' + select.parentElement.parentElement.outerHTML);
        select.value = option;
        select.dispatchEvent(new Event('change', { bubbles: true }));
        return true;
        """
        try await runInCopies("the copy shows and changes the \(wrapperClass) field", script: script, arguments: ["option": option, "wrapperClass": wrapperClass], host: host)
    }
}
