/**
 * File: MacSlashAndHandlesInAppHostedTests.swift
 * ----------------------------------------------
 * Layer: Tests
 * Description: The slash commands and the block handle in Graphite's own window inside the running Mac app, with key
 *              and mouse events sent through AppKit as a person's arrive.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

#if os(macOS)
import XCTest
import AppKit
import SwiftUI
import GraphiteCore
@testable import GraphiteUI

/// The Mac checks of `Docs/Slash-menu-and-block-handles-todo.md` (sections 1 and 2) inside the app, as a hosted test:
/// Graphite's root view in a window of the app, typed into and pointed at with events put in the application's queue.
/// Runs only with `TEST_RUNNER_GRAPHITE_MAC_SLASH` given to xcodebuild as a folder, where it writes a picture of each step
/// and notes; a person looks at them.
@MainActor
final class MacSlashAndHandlesInAppHostedTests: XCTestCase {
    static let switchVariable = "GRAPHITE_MAC_SLASH"
    private var outputFolder: URL?
    private var pictureCount = 0
    private var notes: [String] = []

    private static let vaultNotes: [String: String] = [
        "Welcome.md": "Type a slash below.\n\n",
        "Signals.md": "# Sampling\n\nA signal sampled fast enough can be rebuilt.\n\n- first item\n- second item\n\n# Aliasing\n\nHigh frequencies fold back.\n",
    ]

    func testTheSlashCommandsInsertATableAndUndoGivesTheQueryBack() async throws {
        guard try start() else { return }
        let (window, workspace) = try await openWindow()
        let session = try await openNote("Welcome.md", in: workspace)
        let textView = try await editor(in: window)
        window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: (session.text as NSString).length, length: 0))
        // XCTest runs inside one turn of the run loop, so AppKit's undo group of each event never closes: each step
        // gets a group of its own, as a person's keys get one each.
        let undoManager = try XCTUnwrap(textView.undoManager)
        undoManager.groupsByEvent = false
        defer { undoManager.groupsByEvent = true }
        undoManager.beginUndoGrouping()
        try await type("/", in: window)
        try await waitUntil("the slash commands show", timeoutSeconds: 15) { session.completion.isVisible }
        try note("after /: \(session.completion.items.count) entries, first \(session.completion.items.prefix(6).map(\.title)), "
                 + "palette commands among them: \(session.completion.items.contains { item in item.id.hasPrefix("palette-") })")
        try writePicture("the list after a slash", of: window)
        try await type("tab", in: window)
        try await waitUntil("Table first", timeoutSeconds: 15) { session.completion.items.first?.title == "Table" }
        try writePicture("the list after slash tab", of: window)
        undoManager.endUndoGrouping()
        undoManager.beginUndoGrouping()
        try await pressKey("\r", keyCode: 36, in: window)
        try await waitUntil("the table is inserted", timeoutSeconds: 15) { session.text.contains("| Column | Column |") }
        try note("after Return: \(session.text.debugDescription)")
        try writePicture("the table inserted", of: window)
        XCTAssertFalse(session.text.contains("/tab"))
        undoManager.endUndoGrouping()
        try await undoFromTheEditMenu(in: window)
        try await waitUntil("one undo gives the query back", timeoutSeconds: 15) { !session.text.contains("| Column |") }
        try note("after Undo: \(session.text.debugDescription)")
        XCTAssertTrue(session.text.hasSuffix("/tab"), "One undo gives /tab back: \(session.text.debugDescription)")
        try writePicture("after undo", of: window)
        undoManager.beginUndoGrouping()
        defer { undoManager.endUndoGrouping() }
        try await type(" ", in: window)
        try note("after a space: list open \(session.completion.isVisible)")
        XCTAssertFalse(session.completion.isVisible, "A space closes it")
        try await type("/h2", in: window)
        try await waitUntil("the headings are listed", timeoutSeconds: 15) { session.completion.isVisible }
        try await press(escape: true, in: window)
        try note("after Escape: list open \(session.completion.isVisible), text \(session.text.debugDescription)")
        XCTAssertFalse(session.completion.isVisible, "Escape closes it")
        try writePicture("after escape", of: window)
    }

    func testTheBlockHandleShowsOnHoverAndADragMovesAHeadingsSection() async throws {
        guard try start() else { return }
        let (window, workspace) = try await openWindow()
        let session = try await openNote("Signals.md", in: workspace)
        let original = session.text
        let textView = try await editor(in: window)
        let coordinator = try XCTUnwrap(textView.delegate as? NativeMarkdownEditor.Coordinator)
        // A posted move reaches no tracking area, which follows the real cursor; with the window taking mouse moves, it
        // reaches the text view's own `mouseMoved` as the tracking area's events do.
        window.acceptsMouseMovedEvents = true
        window.makeFirstResponder(textView)
        try note("pointer watched: \(coordinator.blockHandles.watchesPointer), tracking areas \(textView.trackingAreas.count)")
        let paragraph = try windowPoint(ofText: "A signal", in: textView, session: session)
        try await moveMouse(to: paragraph, in: window)
        try note("hover over the paragraph: shown \(coordinator.blockHandles.isShown), block \(String(describing: coordinator.blockHandles.shownBlock))")
        XCTAssertEqual(coordinator.blockHandles.shownBlock?.kind, .paragraph, "Hovering shows the paragraph's handle")
        try writePicture("the handle beside the paragraph", of: window)
        let heading = try windowPoint(ofText: "Sampling", in: textView, session: session)
        try await moveMouse(to: heading, in: window)
        XCTAssertEqual(coordinator.blockHandles.shownBlock?.kind, .heading(level: 1))
        let handle = try XCTUnwrap(textView.subviews.compactMap { view in view as? MacBlockHandleView }.first { view in !view.isHidden })
        let handleCenter = textView.convert(CGPoint(x: handle.frame.midX, y: handle.frame.midY), to: nil)
        try writePicture("the handle beside the heading", of: window)
        let lastLine = try windowPoint(ofText: "High frequencies", in: textView, session: session)
        let undoManager = try XCTUnwrap(textView.undoManager)
        undoManager.groupsByEvent = false
        defer { undoManager.groupsByEvent = true }
        undoManager.beginUndoGrouping()
        try post(.leftMouseDown, at: handleCenter, in: window)
        try await settle(window)
        for step in 1...8 {
            let fraction = CGFloat(step) / 8
            let point = CGPoint(x: handleCenter.x, y: handleCenter.y + (lastLine.y - 30 - handleCenter.y) * fraction)
            try post(.leftMouseDragged, at: point, in: window)
            try await settle(window)
        }
        try note("dragging: destination \(String(describing: coordinator.blockHandles.dragDestination)) of \((session.text as NSString).length)")
        try writePicture("dragging below the last line", of: window)
        try post(.leftMouseUp, at: CGPoint(x: handleCenter.x, y: lastLine.y - 30), in: window)
        try await settle(window)
        undoManager.endUndoGrouping()
        try note("after the drop: \(session.text.debugDescription)")
        XCTAssertTrue(session.text.hasPrefix("# Aliasing"), "The first section went below the second")
        try writePicture("after the drop", of: window)
        window.makeFirstResponder(textView)
        try await undoFromTheEditMenu(in: window)
        try writePicture("after undo", of: window)
        try await waitUntil("one undo puts it back", timeoutSeconds: 15) { session.text == original }
        try note("after Undo: back as it was \(session.text == original)")
        let block = try XCTUnwrap(BlockHandleEditing.block(at: (session.text as NSString).range(of: "High").location,
                                                           in: BlockHandleEditing.blocks(in: session.text)))
        let menu = coordinator.blockHandles.menu(for: block)
        try note("the paragraph's menu: \(menu.items.map(\.title)), Turn Into: \(menu.items.first?.submenu?.items.map(\.title) ?? [])")
    }

    // MARK: Setting up

    private func start() throws -> Bool {
        // Returns rather than skipping: the suites' skip count may not rise (FR-93), and this is not a missing capability.
        guard let outputPath = ProcessInfo.processInfo.environment[Self.switchVariable] else { return false }
        let testName = String(String(name.split(separator: " ").last ?? "test").dropLast())
        let folder = URL(fileURLWithPath: outputPath, isDirectory: true).appendingPathComponent(testName)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        outputFolder = folder
        return true
    }

    private func openWindow() async throws -> (NSWindow, WorkspaceModel) {
        let vaultRoot = try TemporaryVault.make(prefix: "MacSlashInApp", for: self).root
        for (name, text) in Self.vaultNotes { try Data(text.utf8).write(to: vaultRoot.appendingPathComponent(name)) }
        let device = try IsolatedWorkspaceDevice.make(for: self)
        let workspace = device.makeWorkspace()
        try await workspace.openFolderAsVault(vaultRoot)
        try await waitUntil("the vault is indexed", timeoutSeconds: 60) { workspace.hasCompletedIndexScan && !workspace.isIndexing }
        let window = try ReleaseVaultWindow.show(GraphiteRootView(workspace: workspace), for: self)
        window.makeKey()
        return (window, workspace)
    }

    private func openNote(_ name: String, in workspace: WorkspaceModel) async throws -> MarkdownSession {
        _ = await workspace.open(try VaultPath(name), placement: .currentTab)
        try await waitUntil("the note is open", timeoutSeconds: 20) { workspace.markdownSession != nil }
        let session = try XCTUnwrap(workspace.markdownSession)
        session.viewMode = .livePreview
        return session
    }

    private func editor(in window: NSWindow) async throws -> MarkdownMacTextView {
        let root = try XCTUnwrap(window.contentView)
        try await waitUntil("the note's editor is shown", timeoutSeconds: 20) { ReleaseVaultViews.noteTextView(in: root) != nil }
        try await settle(window)
        return try XCTUnwrap(ReleaseVaultViews.noteTextView(in: root))
    }

    /// The middle of the first character of `text` in the editor, in the window's coordinates.
    private func windowPoint(ofText text: String, in textView: MarkdownMacTextView, session: MarkdownSession) throws -> CGPoint {
        let range = (session.text as NSString).range(of: text)
        XCTAssertNotEqual(range.location, NSNotFound, "no \(text) in the note")
        var actualRange = NSRange()
        let screenRect = textView.firstRect(forCharacterRange: NSRange(location: range.location, length: 1), actualRange: &actualRange)
        let windowRect = textView.window?.convertFromScreen(screenRect) ?? .zero
        return CGPoint(x: windowRect.midX, y: windowRect.midY)
    }

    private func settle(_ window: NSWindow) async throws {
        _ = try await MainThreadQuietWatch(window: window, quietStepsToStop: 20).measure({}, until: { true })
    }

    // MARK: Events

    private func moveMouse(to windowPoint: CGPoint, in window: NSWindow) async throws {
        // Two moves, as a pointer arriving does: the tracking area reports the second.
        try post(.mouseMoved, at: CGPoint(x: windowPoint.x - 2, y: windowPoint.y), in: window)
        try post(.mouseMoved, at: windowPoint, in: window)
        try await settle(window)
    }

    private func post(_ type: NSEvent.EventType, at windowPoint: CGPoint, in window: NSWindow) throws {
        NSApp.postEvent(try XCTUnwrap(NSEvent.mouseEvent(with: type, location: windowPoint, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                                         windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1,
                                                         pressure: type == .mouseMoved ? 0 : 1)), atStart: false)
    }

    private func type(_ text: String, in window: NSWindow) async throws {
        for character in text {
            try postKey(String(character), keyCode: character == " " ? 49 : 0, in: window)
            try await settle(window)
        }
    }

    private func pressKey(_ characters: String, keyCode: UInt16, modifiers: NSEvent.ModifierFlags = [], in window: NSWindow) async throws {
        try postKey(characters, keyCode: keyCode, modifiers: modifiers, in: window)
        try await settle(window)
    }

    /// Undo of the note: its own undo manager, the one the editor gives its text view. A posted ⌘Z needs the menu bar,
    /// which answers only while the app is in front, and a test cannot bring it there (macOS refuses the activation).
    private func undoFromTheEditMenu(in window: NSWindow) async throws {
        let textView = try XCTUnwrap(ReleaseVaultViews.noteTextView(in: try XCTUnwrap(window.contentView)))
        let undoManager = try XCTUnwrap(textView.undoManager)
        XCTAssertTrue(undoManager.canUndo, "The note has a step to undo")
        undoManager.undo()
        try await settle(window)
    }

    private func press(escape: Bool, in window: NSWindow) async throws {
        try postKey(String(UnicodeScalar(UInt8(27))), keyCode: 53, in: window)
        try await settle(window)
    }

    private func postKey(_ characters: String, keyCode: UInt16, modifiers: NSEvent.ModifierFlags = [], in window: NSWindow) throws {
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            let timestamp = ProcessInfo.processInfo.systemUptime
            NSApp.postEvent(try XCTUnwrap(NSEvent.keyEvent(with: type, location: .zero, modifierFlags: modifiers, timestamp: timestamp,
                                                           windowNumber: window.windowNumber, context: nil, characters: characters,
                                                           charactersIgnoringModifiers: characters, isARepeat: false, keyCode: keyCode)), atStart: false)
        }
    }

    // MARK: Output

    private func note(_ line: String) throws {
        notes.append(line)
        try Data(notes.joined(separator: "\n").utf8).write(to: try XCTUnwrap(outputFolder).appendingPathComponent("notes.txt"))
    }

    private func writePicture(_ name: String, of window: NSWindow) throws {
        let pngData = try XCTUnwrap(ReleaseVaultWindow.screenshot(of: window))
        pictureCount += 1
        try pngData.write(to: try XCTUnwrap(outputFolder).appendingPathComponent(String(format: "%02d %@.png", pictureCount, name)))
    }
}
#endif
