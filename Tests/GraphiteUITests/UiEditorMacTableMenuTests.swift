/**
 * File: UiEditorMacTableMenuTests.swift
 * -------------------------------------
 * Layer: Tests
 * Description: In the Mac's Live Preview, a table's cell menu offers Obsidian's items and sorts the note's rows as one
 *              undoable edit.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 11/11/2026
 */

#if os(macOS)
import AppKit
import SwiftUI
import XCTest
import GraphiteCore
@testable import GraphiteUI
import GraphiteTestSupport

/// The table's view in the Mac's own text view, in a window shown invisibly, its menu asked for
/// as a secondary click asks for it.
@MainActor
final class UiEditorMacTableMenuTests: XCTestCase {
    private var windows: [NSWindow] = []

    override func tearDown() async throws {
        for window in windows {
            window.orderOut(nil)
            window.contentView = nil
        }
        windows = []
        try await super.tearDown()
    }

    private static let tableNote = "Intro line\n\n| Year | Rate |\n| --- | --- |\n| 2024 | 2.0 |\n| 2025 | 1.8 |\n\nAfter the table\n"

    private func makeEditor(text: String) async throws -> (NativeMarkdownEditor.Coordinator, MarkdownMacTextView, MarkdownSession) {
        let vault = try TemporaryVault.make(prefix: "Vault", for: self).root
        try Data(text.utf8).write(to: vault.appendingPathComponent("Note.md"))
        let store = VaultStore(root: vault)
        let notePath = try VaultPath("Note.md")
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
        textView.string = text
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        textView.delegate = coordinator
        coordinator.connect(textView)
        coordinator.restyleEverything(in: textView)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 500), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        windows.append(window)
        window.contentView = scrollView
        window.showInvisibly()
        window.makeFirstResponder(textView)
        scrollView.frame = NSRect(x: 0, y: 0, width: 700, height: 500)
        textView.frame.size.width = 700
        scrollView.layoutSubtreeIfNeeded()
        return (coordinator, textView, session)
    }

    private func tableView(in textView: NSTextView) -> NSView? {
        textView.subviews.first { subview in subview is NSHostingView<AnyView> }
    }

    private func awaitConditionAfterLayout(_ description: String, timeoutSeconds: TimeInterval = 5, _ condition: () -> Bool) async throws {
        try await waitUntil(description, timeoutSeconds: timeoutSeconds) {
            windows.forEach { window in window.contentView?.layoutSubtreeIfNeeded(); window.displayIfNeeded() }
            return condition()
        }
    }

    /// A point in the first column of the table's first body row, in the table view: the
    /// header and two body rows are about as tall as each other.
    private func pointInFirstBodyCell(of tableView: NSView) -> CGPoint {
        CGPoint(x: 40, y: tableView.isFlipped ? tableView.bounds.height * 0.45 : tableView.bounds.height * 0.55)
    }

    func testTheCellMenuOffersObsidiansItemsAndSortsTheNotesRows() async throws {
        let (coordinator, textView, session) = try await makeEditor(text: Self.tableNote)
        defer { withExtendedLifetime(coordinator) {} }
        try await awaitConditionAfterLayout("The table is drawn") { self.tableView(in: textView) != nil }
        let tableView = try XCTUnwrap(tableView(in: textView) as? RenderedBlockHostingView)
        let window = try XCTUnwrap(tableView.window)
        let point = tableView.convert(pointInFirstBodyCell(of: tableView), to: nil)
        let rightClick = try XCTUnwrap(NSEvent.mouseEvent(with: .rightMouseDown, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                                          windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        let menu = try XCTUnwrap(tableView.menu(for: rightClick))
        XCTAssertEqual(menu.items.map(\.title), ["Row", "Column", "Sort by column (A to Z)", "Sort by column (Z to A)", "", "Edit Source"])
        XCTAssertEqual(menu.items[0].submenu?.items.map(\.title), ["Add row above", "Add row below", "Move row up", "Move row down", "Duplicate row", "Delete row"])
        XCTAssertEqual(menu.items[1].submenu?.items.filter { item in item.title.hasPrefix("Align") }.map(\.state), [.off, .off, .off])

        menu.performActionForItem(at: 3)
        XCTAssertEqual(textView.string, Self.tableNote.replacingOccurrences(of: "| 2024 | 2.0 |\n| 2025 | 1.8 |\n", with: "| 2025 | 1.8 |\n| 2024 | 2.0 |\n"))
        XCTAssertNil(session.blockViews.tableCellCommandTarget, "A menu opened without editing a cell gives the palette nothing.")
        textView.undoManager?.undo()
        XCTAssertEqual(textView.string, Self.tableNote, "The sort is one edit.")
    }

    /// A table indented under a list item is a table of its own, its cells edited in place and
    /// its menu the same.
    func testATableInAListItemGetsTheSameMenu() async throws {
        let note = "- Item\n\n  | Year | Rate |\n  | --- | --- |\n  | 2024 | 2.0 |\n  | 2025 | 1.8 |\n\nAfter\n"
        let (coordinator, textView, _) = try await makeEditor(text: note)
        defer { withExtendedLifetime(coordinator) {} }
        try await awaitConditionAfterLayout("The table is drawn") { self.tableView(in: textView) != nil }
        let tableView = try XCTUnwrap(tableView(in: textView) as? RenderedBlockHostingView)
        let menu = try XCTUnwrap(tableView.blockMenu?.makeMenu(at: pointInFirstBodyCell(of: tableView), isFlipped: tableView.isFlipped, height: tableView.bounds.height))
        XCTAssertEqual(menu.items.map(\.title), ["Row", "Column", "Sort by column (A to Z)", "Sort by column (Z to A)", "", "Edit Source"])
        menu.performActionForItem(at: 3)
        XCTAssertEqual(textView.string, note.replacingOccurrences(of: "  | 2024 | 2.0 |\n  | 2025 | 1.8 |\n", with: "  | 2025 | 1.8 |\n  | 2024 | 2.0 |\n"))
    }
}
#endif
