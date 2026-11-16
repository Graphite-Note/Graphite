/**
 * File: WorkspaceReleaseHostedTests.swift
 * ---------------------------------------
 * Layer: Tests
 * Description: On the iPad, a window closed with a long note open in it gives back its workspace, the note and the
 *              note's editor with the views of its blocks.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 12/11/2026
 */
#if os(iOS)
import XCTest
import SwiftUI
import GraphiteApple
import GraphiteCore
import GraphiteIndex
@testable import GraphiteUI

/// Memory kept after a window closes (Docs/Editor-scrolling-todo.md). In the iPad's long-note
/// benchmark every run's workspace, editor and about 90 block views stayed after its window
/// closed: the note's editor, kept for its tab as its view went (`MarkdownEditorRetention`),
/// holds the workspace through its actions, and the workspace holds the editors it keeps.
@MainActor
final class WorkspaceReleaseHostedTests: XCTestCase {
    /// A weak reference, so the test's own frame holds nothing it checks.
    private final class WeakReference<Object: AnyObject> {
        weak var object: Object?
        init(_ object: Object) { self.object = object }
    }

    func testClosingAWindowWithANoteOpenReleasesItsWorkspaceAndTheNotesEditor() async throws {
        let references = try await showLongNoteInAWindowThenCloseIt()
        try await waitUntil("the closed window's workspace, its note and the note's editor are released", timeoutSeconds: 10) {
            references.workspace.object == nil && references.session.object == nil && references.editor.object == nil
        }
    }

    private func showLongNoteInAWindowThenCloseIt() async throws
        -> (workspace: WeakReference<WorkspaceModel>, session: WeakReference<MarkdownSession>, editor: WeakReference<MarkdownTextView>) {
        let directory = try TemporaryVault.make(prefix: "WorkspaceRelease", for: self).root
        let path = try VaultPath("Lecture.md")
        try Data(PerformanceBenchmarkTests.longLectureNote(sectionCount: 4).utf8).write(to: directory.appendingPathComponent(path.rawValue))
        let workspace = WorkspaceModel()
        workspace.folderAccess = FolderAccess(root: directory)
        workspace.store = VaultStore(root: directory)
        workspace.index = try VaultIndex(databaseURL: directory.appendingPathComponent("index.sqlite"))
        await workspace.open(path, placement: .currentTab)
        let session = try XCTUnwrap(workspace.markdownSession)
        session.viewMode = .livePreview
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { scene in scene as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.effectiveGeometry.coordinateSpace.bounds
        window.rootViewController = UIHostingController(rootView: AnyView(NavigationStack {
            WorkspacePanes(workspace: workspace, showsLinksInspector: .constant(false), create: { _ in }, showQuickSwitcher: {})
        }))
        window.makeKeyAndVisible()
        var shownEditor: MarkdownTextView?
        try await waitUntil("the note's editor shows its blocks") {
            window.layoutIfNeeded()
            shownEditor = Self.descendants(of: window, matching: MarkdownTextView.self).first { editor in
                editor.text == session.text && editor.bounds.width > 0 && editor.subviews.count > 4
            }
            return shownEditor != nil
        }
        let editor = try XCTUnwrap(shownEditor)
        shownEditor = nil
        // As the app closes a window: its views go, then its workspace hears that it closed.
        window.isHidden = true
        window.rootViewController = nil
        workspace.windowDidClose()
        return (WeakReference(workspace), WeakReference(session), WeakReference(editor))
    }

    private static func descendants<Found: UIView>(of parent: UIView, matching type: Found.Type) -> [Found] {
        parent.subviews.flatMap { child in ((child as? Found).map { [$0] } ?? []) + descendants(of: child, matching: type) }
    }
}
#endif
