#if os(macOS)
import AppKit
import SwiftUI
import XCTest
import GraphiteCore
@testable import GraphiteUI
import GraphiteTestSupport

/// A web page pasted into the Mac editor becomes Markdown unless "Auto Convert HTML on
/// Paste" is off (HUNT-249). The paste reads a pasteboard of the test's own, never the clipboard.
@MainActor
final class MacEditorPastedHTMLTests: XCTestCase {
    private var window: NSWindow?

    override func tearDown() async throws {
        window?.orderOut(nil)
        window?.contentView = nil
        window = nil
        try await super.tearDown()
    }

    private static func textView(in view: NSView) -> MarkdownMacTextView? {
        if let textView = view as? MarkdownMacTextView { return textView }
        for subview in view.subviews {
            if let textView = textView(in: subview) { return textView }
        }
        return nil
    }

    private func showEditor() async throws -> MarkdownMacTextView {
        let vault = try TemporaryVault.make(prefix: "PasteVault", for: self).root
        try Data("".utf8).write(to: vault.appendingPathComponent("Note.md"))
        let store = VaultStore(root: vault)
        let path = try VaultPath("Note.md")
        let session = try MarkdownSession(path: path, snapshot: try await store.read(path), store: store, didSave: { _ in })
        let editor = NativeMarkdownEditor(session: session, configuration: EditorConfiguration(), headingScrollRequest: nil, follow: { _, _ in })
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 400), styleMask: [.titled], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        self.window = window
        window.contentView = NSHostingView(rootView: editor)
        window.showInvisibly()
        var foundTextView: MarkdownMacTextView?
        try await waitUntil("SwiftUI makes the editor") {
            window.contentView?.layoutSubtreeIfNeeded()
            foundTextView = window.contentView.flatMap { contentView in Self.textView(in: contentView) }
            return foundTextView != nil
        }
        return try XCTUnwrap(foundTextView)
    }

    private func makePasteboard() -> NSPasteboard {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("GraphiteMacEditorPastedHTMLTests-" + UUID().uuidString))
        addTeardownBlock { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        pasteboard.setString("<p>See <strong>this</strong> page</p>", forType: .html)
        pasteboard.setString("See this page", forType: .string)
        return pasteboard
    }

    func testPastedHTMLBecomesMarkdown() async throws {
        let textView = try await showEditor()
        textView.pastingPasteboard = makePasteboard()
        textView.convertsPastedHTML = true

        textView.paste(nil)
        try await waitUntil("the converted text is in the note", timeoutSeconds: 10) { !textView.string.isEmpty }

        XCTAssertEqual(textView.string, "See **this** page")
    }

    func testWithTheOptionOffTheHTMLIsNotConverted() async throws {
        let textView = try await showEditor()
        textView.convertsPastedHTML = false
        XCTAssertFalse(textView.pasteConvertedHTML(from: makePasteboard()))
        XCTAssertEqual(textView.string, "")
    }
}
#endif
