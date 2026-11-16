/**
 * File: WorkspaceReleaseTests.swift
 * ---------------------------------
 * Layer: Tests
 * Description: A note's session and editor are released when its tab closes, and a workspace when
 *              nothing holds it or its window closed, so memory comes back as notes and windows are closed.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 12/11/2026
 */

#if os(macOS)
import AppKit
import SwiftUI
import XCTest
import GraphiteCore
import GraphiteApple
import GraphiteIndex
@testable import GraphiteUI
import GraphiteTestSupport

/// Memory kept after a note is closed (Docs/Editor-scrolling-todo.md): the note's session, its
/// editor and the views of its blocks go with its tab.
@MainActor
final class WorkspaceReleaseTests: XCTestCase {
    /// A weak reference, so the test's own frame holds nothing it checks.
    private final class WeakReference<Object: AnyObject> {
        weak var object: Object?
        init(_ object: Object) { self.object = object }
    }

    private func makeWorkspace(files: [String: String]) throws -> WorkspaceModel {
        let vault = try TemporaryVault.make(prefix: "Release", for: self).root
        for (name, text) in files { try Data(text.utf8).write(to: vault.appendingPathComponent(name)) }
        let workspace = WorkspaceModel()
        workspace.folderAccess = FolderAccess(root: vault)
        workspace.store = VaultStore(root: vault)
        workspace.index = try VaultIndex(databaseURL: vault.appendingPathComponent("index.sqlite"))
        return workspace
    }

    /// The main actor runs what a change set off.
    private func settle(for duration: Duration) async throws {
        let end = ContinuousClock.now + duration
        try await waitUntil("a moment passes", timeoutSeconds: 10) { ContinuousClock.now >= end }
    }

    private func openedWorkspaceReference() async throws -> WeakReference<WorkspaceModel> {
        let workspace = try makeWorkspace(files: ["Note.md": "# Note\n\nText.\n"])
        await workspace.open(try VaultPath("Note.md"), placement: .currentTab)
        return WeakReference(workspace)
    }

    func testAWorkspaceWithAnOpenNoteIsReleasedOnceNothingHoldsIt() async throws {
        let workspace = try await openedWorkspaceReference()
        try await settle(for: .milliseconds(600))
        XCTAssertNil(workspace.object)
    }

    /// A long note's tab closed in a window that stays open: its session, and with it the editor
    /// and the views of its tables, formulas and callouts, are released.
    func testClosingANotesTabReleasesTheNoteAndItsEditor() async throws {
        let workspace = try makeWorkspace(files: ["Note.md": PerformanceBenchmarkTests.longLectureNote(sectionCount: 4), "Other.md": "Other.\n"])
        await workspace.open(try VaultPath("Other.md"), placement: .currentTab)
        let openedTab = await workspace.open(try VaultPath("Note.md"), placement: .newTab)
        let noteTab = try XCTUnwrap(openedTab)
        let session = WeakReference(try XCTUnwrap(workspace.markdownSession))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 900), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        window.contentView = NSHostingView(rootView: WorkspacePanes(workspace: workspace, showsLinksInspector: .constant(false), create: { _ in },
                                                                    showQuickSwitcher: {}))
        window.showInvisibly()
        try await waitUntil("the note's editor is shown") {
            window.contentView?.layoutSubtreeIfNeeded()
            return Self.firstTextView(in: window.contentView) != nil
        }
        await workspace.closeTab(noteTab)
        // Released about 2.8 s after the tab closed on the Mac (2026-11-11), the same at each run.
        try await waitUntil("the closed tab's note, and its editor, are released while the window stays open", timeoutSeconds: 10) {
            window.contentView?.layoutSubtreeIfNeeded()
            return session.object == nil
        }
    }

    /// A window closed with a long note open in it, as the app closes one (its view taken out, then
    /// `windowDidClose`): its workspace, the note's editor and the views of its blocks are released.
    /// The editor of a note whose view leaves the screen is kept for its tab
    /// (`MarkdownEditorRetention`), and it holds the workspace through its actions, so a closed
    /// window's workspace and everything it showed stayed until the process ended.
    func testClosingAWindowWithANoteOpenReleasesItsWorkspaceAndTheNotesEditor() async throws {
        let references = try await showLongNoteInAWindowThenCloseIt()
        try await waitUntil("the closed window's workspace, its note and the note's editor are released", timeoutSeconds: 10) {
            references.workspace.object == nil && references.session.object == nil && references.textView.object == nil
        }
    }

    private func showLongNoteInAWindowThenCloseIt() async throws
        -> (workspace: WeakReference<WorkspaceModel>, session: WeakReference<MarkdownSession>, textView: WeakReference<NSTextView>) {
        let workspace = try makeWorkspace(files: ["Note.md": PerformanceBenchmarkTests.longLectureNote(sectionCount: 4)])
        await workspace.open(try VaultPath("Note.md"), placement: .currentTab)
        let session = WeakReference(try XCTUnwrap(workspace.markdownSession))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 900), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: WorkspacePanes(workspace: workspace, showsLinksInspector: .constant(false), create: { _ in },
                                                                    showQuickSwitcher: {}))
        window.showInvisibly()
        let textView = try await waitForValue("the note's editor is shown") { () -> NSTextView? in
            window.contentView?.layoutSubtreeIfNeeded()
            return Self.firstTextView(in: window.contentView)
        }
        try await settle(for: .milliseconds(300))
        window.contentView = nil
        window.close()
        workspace.windowDidClose()
        return (WeakReference(workspace), session, WeakReference(textView))
    }

    private func waitForValue<Value>(_ description: String, _ value: () -> Value?) async throws -> Value {
        var found: Value?
        try await waitUntil(description, timeoutSeconds: 10) {
            found = value()
            return found != nil
        }
        return try XCTUnwrap(found)
    }

    private static func firstTextView(in view: NSView?) -> NSTextView? {
        guard let view else { return nil }
        if let textView = view as? NSTextView { return textView }
        for subview in view.subviews { if let found = firstTextView(in: subview) { return found } }
        return nil
    }
}
#endif
