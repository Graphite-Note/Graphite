/**
 * File: MacMarkdownEditorFixture.swift
 * ------------------------------------
 * Layer: Tests
 * Description: A Mac note editor in a window, with a note in a temporary vault or one a workspace has open.
 *
 * Authors: Bahey Shalash
 * Version: 0.5
 * Date: 02/11/2026
 */

#if os(macOS)
import AppKit
import XCTest
import GraphiteCore
@testable import GraphiteUI
import GraphiteTestSupport

/// A Mac note editor in a window, built the way `NativeMarkdownEditor.makeNSView` builds
/// it, with a note in a temporary vault. Tests keep the fixture and call `tearDown`.
@MainActor
final class MacMarkdownEditorFixture {
    let session: MarkdownSession
    let coordinator: NativeMarkdownEditor.Coordinator
    let textView: MarkdownMacTextView
    let scrollView: NSScrollView
    let window: NSWindow
    /// The fixture's own vault; nil for a note of a workspace's vault.
    private let temporaryVault: TemporaryVault?

    /// `backingScale` is the window's pixels to the point: 2 on a Retina display, 1 on the virtual display of a CI machine.
    convenience init(text: String, backingScale: CGFloat = 2) async throws {
        let temporaryVault = try TemporaryVault(prefix: "Vault")
        try temporaryVault.writeFile("Note.md", text: text)
        let store = VaultStore(root: temporaryVault.root)
        let notePath = try VaultPath("Note.md")
        let session = try MarkdownSession(path: notePath, snapshot: try await store.read(notePath), store: store, didSave: { _ in })
        try self.init(session: session, temporaryVault: temporaryVault, backingScale: backingScale)
    }

    /// The editor of a note a workspace has open.
    convenience init(showing session: MarkdownSession) throws {
        try self.init(session: session, temporaryVault: nil, backingScale: 2)
    }

    private init(session: MarkdownSession, temporaryVault: TemporaryVault?, backingScale: CGFloat) throws {
        self.session = session
        self.temporaryVault = temporaryVault
        let text = session.text
        coordinator = NativeMarkdownEditor.Coordinator(session: session, configuration: EditorConfiguration())
        scrollView = MarkdownMacTextView.makeScrollableTextView()
        textView = try XCTUnwrap(scrollView.documentView as? MarkdownMacTextView)
        textView.isRichText = false
        textView.allowsUndo = true
        textView.string = text
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        textView.delegate = coordinator
        coordinator.connect(textView)
        coordinator.restyleEverything(in: textView)
        coordinator.scrollView = scrollView
        window = PinnedBackingScaleWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 400), styleMask: [.titled], backingScale: backingScale)
        window.contentView = scrollView
        scrollView.frame = NSRect(x: 0, y: 0, width: 600, height: 400)
        textView.frame.size.width = 600
        window.showInvisibly()
        scrollView.layoutSubtreeIfNeeded()
        textView.layoutSubtreeIfNeeded()
    }

    /// Scrolls so the line starting at `characterLocation` is at the top, as a person's scrolling does.
    func scrollToTop(ofCharacter characterLocation: Int) {
        coordinator.scrollToTop(of: characterLocation, in: textView)
    }

    /// Puts the editor's scroll view back in the window after `suspend` took it out, as the
    /// pane's container does when a kept editor is shown again.
    func hostScrollViewAgain() {
        window.contentView = scrollView
        scrollView.frame = NSRect(x: 0, y: 0, width: 600, height: 400)
        scrollView.layoutSubtreeIfNeeded()
        textView.layoutSubtreeIfNeeded()
    }

    func tearDown() {
        window.orderOut(nil)
        window.contentView = nil
        temporaryVault?.remove()
    }
}
#endif
