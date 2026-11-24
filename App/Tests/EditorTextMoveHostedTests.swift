/**
 * File: EditorTextMoveHostedTests.swift
 * -------------------------------------
 * Layer: Tests
 * Description: Text dragged within a note on the iPad and dropped back into it moves to the place it was let go as
 *              one step of the note's history (HUNT-377), in the hosted workspace.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

#if os(iOS)
import XCTest
import SwiftUI
import GraphiteApple
import GraphiteCore
import GraphiteIndex
@testable import GraphiteUI

/// Text dragged within a note and dropped back into it (HUNT-377). The drag itself is UIKit's
/// and is not synthesized: the test notes the dragged text as the drag delegate does, the place
/// it was let go as the drop delegate does, and moves it as the paste delegate does when UIKit
/// hands it the drop's item.
@MainActor
final class EditorTextMoveHostedTests: XCTestCase {
    private var window: UIWindow?

    override func tearDown() async throws {
        window?.isHidden = true
        window?.rootViewController = nil
        window = nil
    }

    func testTextDroppedWithinTheNoteMovesAsOneStepThatUndoAndRedoFollow() async throws {
        let original = "## Second law\n\n- Heat flows from hot to cold.\n"
        let (session, editor, coordinator) = try await openEditor(noteText: original)
        let dragged = (original as NSString).range(of: "Second ")

        coordinator.recordTextDraggedWithinNote(dragged, in: editor)
        coordinator.textDraggedWithinNote?.dropLocation = (original as NSString).length
        XCTAssertTrue(coordinator.moveTextDraggedWithinNote(to: (original as NSString).length, in: editor))

        let moved = "## law\n\n- Heat flows from hot to cold.\nSecond "
        try await waitUntil { session.text == moved }
        XCTAssertEqual(editor.text, moved, "The text is moved once, not inserted again beside the original.")
        XCTAssertEqual((editor.text as NSString).substring(with: editor.selectedRange), "Second ", "The moved text is selected at its new place.")
        XCTAssertNil(coordinator.textDraggedWithinNote)
        try await waitUntil("the move is a step of the history") { editor.undoManager?.canUndo == true }

        editor.undoManager?.undo()
        try await waitUntil { session.text == original }
        XCTAssertEqual(editor.text, original, "One undo puts the text back where it was.")
        editor.undoManager?.redo()
        try await waitUntil { session.text == moved }
    }

    func testNothingMovesWhenTheNoteChangedUnderTheDrag() async throws {
        let original = "Alpha beta gamma.\n"
        let (session, editor, coordinator) = try await openEditor(noteText: original)

        // The note changed under the drag: the text is no longer where it was, so nothing is
        // moved and the drop is left to UIKit, which inserts the dropped text as a copy.
        coordinator.recordTextDraggedWithinNote((original as NSString).range(of: "beta"), in: editor)
        coordinator.textDraggedWithinNote?.dropLocation = 0
        editor.selectedRange = NSRange(location: 0, length: 0)
        editor.insertText("X")
        try await waitUntil { session.text == "XAlpha beta gamma.\n" }
        XCTAssertFalse(coordinator.moveTextDraggedWithinNote(to: 0, in: editor))
        XCTAssertEqual(session.text, "XAlpha beta gamma.\n")
        XCTAssertNil(coordinator.textDraggedWithinNote, "The drag is forgotten either way.")

        // A drop that is not the note's own drag moves nothing.
        XCTAssertFalse(coordinator.moveTextDraggedWithinNote(to: 0, in: editor))
    }

    // MARK: Hosting

    private func openEditor(noteText: String) async throws -> (MarkdownSession, MarkdownTextView, NativeMarkdownEditor.Coordinator) {
        let directory = try TemporaryVault.make(prefix: "EditorTextMove", files: ["Thermodynamics.md": noteText], for: self).root
        let workspace = WorkspaceModel()
        workspace.folderAccess = FolderAccess(root: directory)
        workspace.store = VaultStore(root: directory)
        workspace.index = try VaultIndex(databaseURL: directory.appendingPathComponent("index.sqlite"))
        let path = try VaultPath("Thermodynamics.md")
        await workspace.open(path, placement: .currentTab)
        let tab = try XCTUnwrap(workspace.layout.tabID(showing: path))
        let session = try XCTUnwrap(workspace.document(for: tab).markdownSession)
        session.viewMode = .source

        let controller = UIHostingController(rootView: AnyView(NavigationStack {
            WorkspacePanes(workspace: workspace, showsLinksInspector: .constant(false), create: { _ in }, showQuickSwitcher: {})
        }))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.effectiveGeometry.coordinateSpace.bounds
        window.rootViewController = controller
        window.makeKeyAndVisible()
        self.window = window

        try await waitUntil { self.editors(in: controller.view).contains { editor in editor.text == session.text && editor.bounds.width > 0 } }
        let editor = try XCTUnwrap(editors(in: controller.view).first { editor in editor.text == session.text })
        let coordinator = try XCTUnwrap(editor.textDropDelegate as? NativeMarkdownEditor.Coordinator, "The editor takes drops of its own text.")
        XCTAssertTrue(editor.pasteDelegate === coordinator, "Drops of text pass through the editor's paste delegate.")
        editor.becomeFirstResponder()
        return (session, editor, coordinator)
    }

    private func editors(in view: UIView) -> [MarkdownTextView] {
        view.subviews.flatMap { child in ((child as? MarkdownTextView).map { [$0] } ?? []) + editors(in: child) }.filter { editor in editor.window != nil }
    }
}
#endif
