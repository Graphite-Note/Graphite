/**
 * File: UiEditorMacWebLinksTests.swift
 * ------------------------------------
 * Layer: Tests
 * Description: In the Mac's Live Preview, a bare web address is drawn as a link and a click follows it, its right-click
 *              menu offers Use Page Title and Show Preview, and a YouTube embed on its line is a video card.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 16/11/2026
 */

#if os(macOS)
import AppKit
import SwiftUI
import XCTest
import GraphiteCore
@testable import GraphiteUI
import GraphiteTestSupport

@MainActor
final class UiEditorMacWebLinksTests: XCTestCase {
    private var windows: [NSWindow] = []

    override func tearDown() async throws {
        for window in windows {
            window.orderOut(nil)
            window.contentView = nil
        }
        windows = []
        try await super.tearDown()
    }

    private static let playlist = "https://www.youtube.com/playlist?list=PL5Q2soXY2Zi9OtbGJyUVHp1Gp3c_0Dymh"
    private static let note = "# Links\n\n\(playlist)\n\nSee [the course](https://example.com/course) and https://example.com/page.\n\n"
        + "![Computer Architecture lectures](\(playlist))\n\nAfter the card\n"

    func testABareAddressIsALinkThatAClickFollows() async throws {
        let (coordinator, textView) = try await makeEditor()
        let text = textView.string as NSString
        let bareAddress = text.range(of: "https://example.com/page")
        let markdownLinkText = text.range(of: "the course")
        let plainText = text.range(of: "See ")
        func color(at location: Int) -> NSColor? { textView.textStorage?.attribute(.foregroundColor, at: location, effectiveRange: nil) as? NSColor }
        XCTAssertNotEqual(color(at: markdownLinkText.location), color(at: plainText.location))
        XCTAssertEqual(color(at: bareAddress.location + 4), color(at: markdownLinkText.location), "The bare address is drawn as a link.")
        XCTAssertEqual(color(at: NSMaxRange(bareAddress)), color(at: plainText.location), "The full stop after it is not part of it.")
        XCTAssertEqual(coordinator.link(atCharacter: bareAddress.location + 4, in: textView), .web(try XCTUnwrap(URL(string: "https://example.com/page"))))
        XCTAssertEqual(coordinator.link(atCharacter: text.range(of: "playlist?list").location, in: textView), .web(try XCTUnwrap(URL(string: Self.playlist))))
        XCTAssertNil(coordinator.link(atCharacter: plainText.location, in: textView))
    }

    func testTheRightClickMenuOffersTheTitleAndAtYouTubeThePreview() async throws {
        let (_, textView) = try await makeEditor()
        let text = textView.string as NSString
        let actions = EditorContextMenuActions(
            run: { _ in }, noteState: { [weak textView] in (((textView?.string ?? "") as NSString), textView?.selectedRange() ?? NSRange()) },
            apply: { _ in }, insertBlock: { _ in }, colors: nil, insertColor: { _, _ in }, linkToNote: {}, template: nil)
        textView.contextMenuEntries = { EditorContextMenuContent.entries(actions: actions, editorActions: EditorActions()) }
        // AppKit's own menu puts the cursor where the click is, so the click is on the character: the first
        // point beside the character's line that the text view's hit testing places on it.
        func titles(at location: Int) throws -> [String] {
            let window = try XCTUnwrap(textView.window)
            let characterRect = textView.convert(window.convertFromScreen(textView.firstRect(forCharacterRange: NSRange(location: location, length: 1),
                                                                                             actualRange: nil)), from: nil)
            let point = try XCTUnwrap(stride(from: characterRect.minY - 60, through: characterRect.maxY + 60, by: 2).lazy
                .map { distanceFromTop in NSPoint(x: characterRect.minX + 2, y: distanceFromTop) }
                .first { candidate in textView.characterIndexForInsertion(at: candidate) == location }, "A point on character \(location).")
            let event = try XCTUnwrap(NSEvent.mouseEvent(with: .rightMouseDown, location: textView.convert(point, to: nil),
                                                         modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil,
                                                         eventNumber: 0, clickCount: 1, pressure: 1))
            func flattened(_ menu: NSMenu) -> [String] { menu.items.flatMap { item in [item.title] + (item.submenu.map(flattened) ?? []) } }
            return flattened(try XCTUnwrap(textView.menu(for: event)))
        }
        let pageTitles = try titles(at: text.range(of: "example.com/page").location)
        XCTAssertTrue(pageTitles.contains("Use Page Title"), "\(pageTitles)")
        XCTAssertFalse(pageTitles.contains("Show Preview"), "Only YouTube has a preview.")
        let youTubeTitles = try titles(at: text.range(of: "playlist?list").location)
        XCTAssertTrue(youTubeTitles.contains("Use Page Title") && youTubeTitles.contains("Show Preview"), "\(youTubeTitles)")
        XCTAssertFalse(try titles(at: text.range(of: "After").location).contains("Use Page Title"), "Plain text has no web link entries.")
    }

    func testAYouTubeEmbedIsACardOfItsMaximumWidthInAWideColumn() async throws {
        let (_, textView) = try await makeEditor()
        var card: RenderedBlockHostingView?
        try await waitUntil("the card is drawn", timeoutSeconds: 5) {
            windows.forEach { window in window.contentView?.layoutSubtreeIfNeeded(); window.displayIfNeeded() }
            card = textView.subviews.lazy.compactMap { subview in subview as? RenderedBlockHostingView }
                .first { view in !view.isHidden && view.frame.height > 100 }
            return card != nil
        }
        // The block spans the column; the card in it is at most its maximum width, a 16:9 picture over its title.
        let frame = try XCTUnwrap(card?.frame)
        XCTAssertGreaterThan(frame.width, WebVideoCard.maximumWidth, "The column is wider than the card: \(frame)")
        XCTAssertEqual(frame.height, WebVideoCard.maximumWidth * 9 / 16 + 44, accuracy: 24, "\(frame)")
    }

    private func makeEditor() async throws -> (NativeMarkdownEditor.Coordinator, MarkdownMacTextView) {
        let vault = try TemporaryVault.make(prefix: "Vault", for: self).root
        try Data(Self.note.utf8).write(to: vault.appendingPathComponent("Links.md"))
        let store = VaultStore(root: vault)
        let notePath = try VaultPath("Links.md")
        let session = try MarkdownSession(path: notePath, snapshot: try await store.read(notePath), store: store, didSave: { _ in })
        var configuration = EditorConfiguration()
        configuration.mode = .livePreview
        let coordinator = NativeMarkdownEditor.Coordinator(session: session, configuration: configuration)
        coordinator.environment = LivePreviewEnvironment(root: vault, textSize: 17, colorsEnabled: true, paletteHexByName: [:], drawingVersion: 0,
                                                         resolve: { _, _ in nil }, open: { _ in }, follow: { _, _ in }, updateProperties: nil)
        let scrollView = MarkdownMacTextView.makeScrollableTextView()
        let textView = try XCTUnwrap(scrollView.documentView as? MarkdownMacTextView)
        textView.isRichText = false
        textView.allowsUndo = true
        textView.textContainerInset = CGSize(width: 32, height: 32)
        textView.string = Self.note
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        textView.delegate = coordinator
        coordinator.connect(textView)
        coordinator.restyleEverything(in: textView)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 700), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        windows.append(window)
        window.contentView = scrollView
        window.showInvisibly()
        scrollView.frame = NSRect(x: 0, y: 0, width: 800, height: 700)
        textView.frame.size.width = 800
        scrollView.layoutSubtreeIfNeeded()
        return (coordinator, textView)
    }
}
#endif
