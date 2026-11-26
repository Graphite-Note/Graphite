/**
 * File: CommunityPluginCopyParagraphsInWebKitTests.swift
 * ------------------------------------------------------
 * Layer: Tests
 * Description: A paragraph a plugin put a block into, shown whole in the copy of its block in WebKit, with a
 *              tap in the copy reaching the plugin's element, and elements sized by their border box as in Obsidian.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */
#if os(macOS)
import AppKit
import SwiftUI
import WebKit
import XCTest
import GraphiteCore
@testable import GraphiteUI
import GraphiteTestSupport

/// A plugin can put a block into a paragraph with the DOM (Meta Bind draws an inline field as a
/// `div` in the paragraph's inline code), which the HTML parser does not allow: parsed from HTML,
/// the copy would end the paragraph at the block, and the element paths of its taps would miss the
/// plugin's elements. The plugins' page sends such a paragraph as `graphite-p` and the copy's own
/// script makes it a `p` again (`keepParagraphsWhole`); this checks the copy in WebKit, in a window,
/// with the plugin running.
@MainActor
final class CommunityPluginCopyParagraphsInWebKitTests: XCTestCase {
    private let testBed = CommunityPluginHostTestBed()
    private var windows: [NSWindow] = []

    override func tearDown() async throws {
        for window in windows {
            window.contentView = nil
            window.orderOut(nil)
        }
        windows = []
        await testBed.tearDown()
    }

    /// Its `field` block draws a line of text with a button inside a `div` inside the line's code;
    /// the button switches between todo and done.
    private static let pluginSource = """
    'use strict';
    const { Plugin } = require('obsidian');
    module.exports = class FieldPlugin extends Plugin {
        onload() {
            this.registerMarkdownCodeBlockProcessor('field', (source, element) => {
                const line = element.createEl('p', { text: 'Status ' });
                const code = line.createEl('code');
                const wrapper = code.createDiv({ cls: 'field-wrapper' });
                const button = wrapper.createEl('button', { cls: 'field-button', text: 'todo' });
                button.addEventListener('click', () => { button.setText(button.getText() === 'todo' ? 'done' : 'todo'); });
                line.appendText(' today.');
                // As Meta Bind's card: the column's width, with padding and a border.
                element.createDiv({ cls: 'card', text: 'Lectures held', attr: { style: 'width: 100%; padding: 8px; border: 1px solid gray;' } });
            });
        }
    };
    """

    private func showInWindow(_ view: some View) -> NSView {
        let hostingView = NSHostingView(rootView: view.frame(width: 400, height: 200))
        hostingView.frame = NSRect(x: 0, y: 0, width: 400, height: 200)
        let window = NSWindow(contentRect: hostingView.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        windows.append(window)
        window.contentView = hostingView
        window.showInvisibly()
        hostingView.layoutSubtreeIfNeeded()
        return hostingView
    }

    private func evaluate(_ script: String, in webView: WKWebView) async throws -> Any? {
        try await webView.callAsyncJavaScript(script, arguments: [:], in: nil, contentWorld: .defaultClient)
    }

    func testTheCopyShowsTheParagraphWholeAndATapOnItsButtonReachesThePlugin() async throws {
        let workspace = try await testBed.workspaceWithRunningPlugins([("field-plugin", Self.pluginSource)], files: ["Note.md": "```field\n```\n"])
        let host = workspace.communityPlugins
        try await waitUntil("the plugin draws fields") { host.codeBlockLanguages.contains("field") }
        let block = CommunityPluginShownCodeBlock(host: host)
        await block.draw(CommunityPluginReadingBlockRequest(kind: .codeBlock(language: "field"), source: "", note: try VaultPath("Note.md"), firstLine: 0, lineCount: 2),
                         width: 400)
        guard case .drawn(let html) = block.appearance else { return XCTFail("The block is drawn: \(block.appearance)") }
        XCTAssertTrue(html.contains("<graphite-p>Status <code><div class=\"field-wrapper\">"), html)

        let display = CommunityPluginCodeBlockDisplay(block: block, html: html, styleSheets: "", isDark: false, textSize: 16, accentHex: nil)
        let hostingView = showInWindow(display)
        let webView = try XCTUnwrap(Self.firstWebView(in: hostingView), "The copy builds its web view.")
        try await waitUntil("the copy shows the plugin's button") {
            (try? await self.evaluate("return document.querySelector('.field-button') !== null;", in: webView)) as? Bool == true
        }
        let shape = try await evaluate("""
            const root = document.querySelector('.graphite-code-block-root').firstElementChild;
            return Array.from(root.children).map((child) => child.tagName).join(' ') + ' | '
                + (document.querySelector('p > code > div.field-wrapper > button.field-button') !== null) + ' | '
                + document.querySelectorAll('graphite-p').length;
            """, in: webView) as? String
        XCTAssertEqual(shape, "P DIV | true | 0", "one paragraph holding the field, as the plugin drew it, then the card")

        // Elements are sized by their border box, as in Obsidian, in the copy and in the plugins' page:
        // a box of the column's width with padding and a border stays within the column.
        let copyFit = try await evaluate("""
            const card = document.querySelector('.card');
            return getComputedStyle(card).boxSizing + ' ' + (card.getBoundingClientRect().width <= card.parentElement.getBoundingClientRect().width);
            """, in: webView) as? String
        XCTAssertEqual(copyFit, "border-box true")
        let pageSizing = try await testBed.evaluate("return getComputedStyle(document.querySelector('.card')).boxSizing;", in: host) as? String
        XCTAssertEqual(pageSizing, "border-box")

        _ = try await evaluate("document.querySelector('.field-button').click(); return true;", in: webView)
        // The tap went by its path to the plugin's own button, whose new text comes back as the
        // block's new copy (the note's view hands it to the display).
        try await waitUntil("the plugin's button heard the tap") {
            if case .drawn(let changed) = block.appearance { changed.contains("<button class=\"field-button\">done</button>") } else { false }
        }
        block.release()
    }

    private static func firstWebView(in view: NSView) -> WKWebView? {
        if let webView = view as? WKWebView { return webView }
        for subview in view.subviews {
            if let found = firstWebView(in: subview) { return found }
        }
        return nil
    }
}
#endif
