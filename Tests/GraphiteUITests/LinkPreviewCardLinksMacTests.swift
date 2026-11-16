/**
 * File: LinkPreviewCardLinksMacTests.swift
 * ----------------------------------------
 * Layer: Tests
 * Description: On the Mac, a click on a link inside Page Preview's card opens the linked note in the workspace and closes the card.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 12/11/2026
 */
#if os(macOS)
import AppKit
import SwiftUI
import XCTest
import GraphiteCore
import GraphiteIndex
import GraphiteApple
@testable import GraphiteUI
import GraphiteTestSupport

/// A link inside a preview card on the Mac: the card's text is the reading view's selectable
/// text, and a click on its link opens the linked note in the workspace, as the card's own
/// actions open it in the app (`WorkspaceModel.linkPreviewVault`), and closes the card.
@MainActor
final class LinkPreviewCardLinksMacTests: XCTestCase {
    private var windows: [NSWindow] = []

    override func tearDown() async throws {
        for window in windows {
            window.contentView = nil
            window.orderOut(nil)
        }
        windows = []
        try await super.tearDown()
    }

    private static let notes = [
        "Note.md": "Plain words, then [[Target]].\n",
        // The link first on its line, so a click near the line's start finds it.
        "Target.md": "[[Other]] comes next.\n\nThe target's own words.\n",
        "Other.md": "The other note.\n",
    ]

    func testAClickOnALinkInsideTheCardOpensItsNoteAndClosesTheCard() async throws {
        let workspace = try await makeWorkspace()
        let note = try VaultPath("Note.md")
        await workspace.open(note, placement: .currentTab)
        XCTAssertEqual(workspace.markdownSession?.path, note)

        let cards = LinkPreviewModel(clock: ManualClock(), announceHover: { _ in })
        let reading = try XCTUnwrap(workspace.linkPreviewReading(at: .large))
        cards.useReading(reading)
        cards.show(LinkPreviewRequest(target: "Target", isWiki: true, sourceNote: note, anchor: .zero, trigger: .press, source: .editor))
        try await waitUntil("the card's note is read") { if case .shown = cards.phase { true } else { false } }
        guard case .shown(let request, let content) = cards.phase else { return XCTFail("\(cards.phase)") }
        XCTAssertEqual(content.path, try VaultPath("Target.md"))

        let card = LinkPreviewCard(request: request, content: content, root: reading.vault.root, textSize: reading.configuration.textSize,
                                   actions: workspace.linkPreviewVault.actions, model: cards, naturalHeightDidChange: { _ in })
        let hostingView = showInWindow(card.frame(width: 360, height: 300))
        var interactionViews: [NSView] = []
        try await waitUntil("the card's text takes clicks") {
            hostingView.layoutSubtreeIfNeeded()
            interactionViews = Self.textInteractionViews(in: hostingView)
            return !interactionViews.isEmpty
        }

        let clicked = try clickAlongTheFirstLine(of: interactionViews) { workspace.markdownSession?.path.rawValue == "Other.md" || cards.phase.request == nil }
        XCTAssertTrue(clicked, "Some point of the card's first line is on its link.")
        try await waitUntil("the card's link opens Other") { workspace.markdownSession?.path.rawValue == "Other.md" }
        guard case .hidden = cards.phase else { return XCTFail("Following a link of the card closes it: \(cards.phase)") }
    }

    // MARK: Helpers

    private func makeWorkspace() async throws -> WorkspaceModel {
        let vault = try TemporaryVault.make(prefix: "LinkPreviewCardLinks", files: Self.notes, for: self)
        try FileManager.default.createDirectory(at: vault.cacheDirectory, withIntermediateDirectories: true)
        let workspace = try IsolatedWorkspaceDevice.make(for: self).makeWorkspace()
        workspace.folderAccess = FolderAccess(root: vault.root)
        workspace.store = VaultStore(root: vault.root)
        let index = try VaultIndex(databaseURL: vault.cacheDirectory.appendingPathComponent("index.sqlite"))
        try await index.refresh(paths: Self.notes.keys.map { name in try VaultPath(name) }, root: vault.root)
        workspace.index = index
        return workspace
    }

    private func showInWindow(_ view: some View) -> NSView {
        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = NSRect(x: 0, y: 0, width: 360, height: 300)
        let window = NSWindow(contentRect: hostingView.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        windows.append(window)
        window.contentView = hostingView
        window.showInvisibly()
        hostingView.layoutSubtreeIfNeeded()
        return hostingView
    }

    /// Clicks, left to right along the first line of each selectable text, until `isDone`;
    /// answers whether it was.
    private func clickAlongTheFirstLine(of interactionViews: [NSView], until isDone: () -> Bool) throws -> Bool {
        for view in interactionViews {
            for offset in stride(from: CGFloat(4), through: min(view.bounds.width - 4, 200), by: 6) {
                try click(at: view.convert(CGPoint(x: offset, y: 8), to: nil), on: view)
                if isDone() { return true }
            }
        }
        return false
    }

    private func click(at windowPoint: CGPoint, on view: NSView) throws {
        let windowNumber = view.window?.windowNumber ?? 0
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = try XCTUnwrap(NSEvent.mouseEvent(with: type, location: windowPoint, modifierFlags: [], timestamp: 0, windowNumber: windowNumber,
                                                         context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
            if type == .leftMouseDown { view.mouseDown(with: event) } else { view.mouseUp(with: event) }
        }
    }

    private static func textInteractionViews(in view: NSView) -> [NSView] {
        let own = String(describing: type(of: view)) == "NSTextInteractionView" ? [view] : []
        return own + view.subviews.flatMap(textInteractionViews)
    }
}
#endif
