/**
 * File: LivePreviewTableCommandsHostedTests.swift
 * -----------------------------------------------
 * Layer: Tests
 * Description: On the iPad, the command palette offers the table commands of the cell being edited, and running one
 *              changes the note in the iPad's own editor as one undoable edit.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 12/11/2026
 */
#if os(iOS)
import XCTest
import SwiftUI
import GraphiteApple
@testable import GraphiteCore
import GraphiteIndex
@testable import GraphiteUI

/// The hosted workspace's own Live Preview of a note with a table. The table's cell is edited
/// through an editor given what the note's editor gives the table's view: synthesized touches
/// reach UIKit's gesture recognizers but not SwiftUI's tap on the table.
@MainActor
final class LivePreviewTableCommandsHostedTests: XCTestCase {
    private var window: UIWindow?

    private static let note = "Intro line\n\n| Year | Rate |\n| --- | --- |\n| 2024 | 2.0 |\n| 2025 | 1.8 |\n\nAfter the table\n"

    override func tearDown() async throws {
        window?.isHidden = true
        window?.rootViewController = nil
        window = nil
    }

    func testThePalettesTableCommandChangesTheNoteInTheIPadsEditor() async throws {
        let (workspace, session, textView) = try await openNote(Self.note)
        let coordinator = try XCTUnwrap(textView.delegate as? NativeMarkdownEditor.Coordinator)
        XCTAssertFalse(paletteIdentifiers(in: workspace).contains { identifier in identifier.contains(":table-") },
                       "No table command while no cell has been edited.")

        let editor = try editFirstBodyCell(coordinator: coordinator, textView: textView, session: session)
        defer { withExtendedLifetime(editor) {} }
        let tableIdentifiers = paletteIdentifiers(in: workspace).filter { identifier in identifier.contains(":table-") }
        XCTAssertEqual(tableIdentifiers, TableCellCommand.allCases.filter { command in command != .moveRowUp && command != .moveColumnLeft }
            .map(\.graphiteCommand.identifier), "The first body row's first cell can move neither up nor left.")

        // Opening the palette takes the keyboard from the cell, which closes its editor.
        editor.focusDidLeave()
        let moveDown = try XCTUnwrap(WorkspaceCommandList.commands(for: workspace, window: makeWindowActions()).first { command in
            command.id == GraphiteCommand.tableMoveRowDown.identifier
        })
        moveDown.run()
        let moved = Self.note.replacingOccurrences(of: "| 2024 | 2.0 |\n| 2025 | 1.8 |\n", with: "| 2025 | 1.8 |\n| 2024 | 2.0 |\n")
        try await waitUntil("the row moves down in the editor") { textView.text == moved }
        try await waitUntil("the session has the edit") { session.text == moved }
        textView.undoManager?.undo()
        try await waitUntil("one undo puts the row back") { textView.text == Self.note }

        // The note's text taking the keyboard leaves the palette without table commands.
        textView.beginEditing()
        try await waitUntil("the table commands leave the palette") {
            !self.paletteIdentifiers(in: workspace).contains { identifier in identifier.contains(":table-") }
        }
    }

    // MARK: The table's cell

    /// Begins editing the first body row's first cell, with the table's editor given what the
    /// note's editor gives the table's view (`NativeMarkdownEditor.Coordinator.widgetRootView`).
    private func editFirstBodyCell(coordinator: NativeMarkdownEditor.Coordinator, textView: MarkdownTextView,
                                   session: MarkdownSession) throws -> LivePreviewTableEditor {
        let block = try XCTUnwrap(LivePreviewBlockScanner.blocks(in: textView.text as NSString).first { block in block.kind == .table })
        let key = try XCTUnwrap(LivePreviewBlockKey.keys(for: [block]).first)
        let editor = LivePreviewTableEditor()
        let sourceEditing = RenderedBlockSourceEditing(replaceSource: { [weak coordinator, weak textView] editor, transform in
            guard let coordinator, let textView else { return }
            coordinator.replaceSource(ofBlockWithKey: key, editedBy: editor, using: transform, in: textView)
        }, setIsEditingInView: { [weak coordinator] isEditing, editor in
            guard let coordinator else { return }
            if isEditing {
                coordinator.styling.renderedBlocks.beginEditingInView(blockWithKey: key, at: block.range.location, owner: editor)
            } else {
                coordinator.styling.renderedBlocks.endEditingInView(owner: editor)
            }
        }, offerCellCommands: { [weak session] target in session?.blockViews.takeTableCellCommands(target) })
        editor.update(source: block.sourceLines, textSize: 17, sourceEditing: sourceEditing)
        editor.beginEditing(TableCellPosition(row: 1, column: 0))
        return editor
    }

    private func paletteIdentifiers(in workspace: WorkspaceModel) -> [String] {
        WorkspaceCommandList.commands(for: workspace, window: makeWindowActions()).map(\.id)
    }

    private func makeWindowActions() -> WindowActions {
        WindowActions(showQuickSwitcher: {}, showSettings: {}, showVaultManager: {}, toggleLinksInspector: {}, toggleSidebar: {}, showSidebar: {},
                      showLinksInspector: {}, create: { _ in }, showTemplatePicker: {}, showTabOverview: {}, toggleFocusMode: {})
    }

    // MARK: Hosting

    private func openNote(_ text: String) async throws -> (WorkspaceModel, MarkdownSession, MarkdownTextView) {
        let directory = try TemporaryVault.make(prefix: "TableCommands", for: self).root
        try Data(text.utf8).write(to: directory.appendingPathComponent("Table.md"))
        let workspace = WorkspaceModel()
        workspace.folderAccess = FolderAccess(root: directory)
        workspace.store = VaultStore(root: directory)
        let index = try VaultIndex(databaseURL: directory.appendingPathComponent("index.sqlite"))
        workspace.index = index
        _ = try await index.reconcile(root: directory)
        let path = try VaultPath("Table.md")
        await workspace.open(path, placement: .currentTab)
        let tab = try XCTUnwrap(workspace.layout.tabID(showing: path))
        let session = try XCTUnwrap(workspace.document(for: tab).markdownSession)
        session.viewMode = .livePreview
        let controller = UIHostingController(rootView: AnyView(NavigationStack {
            WorkspacePanes(workspace: workspace, showsLinksInspector: .constant(false), create: { _ in }, showQuickSwitcher: {})
        }))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.effectiveGeometry.coordinateSpace.bounds
        window.overrideUserInterfaceStyle = .light
        window.rootViewController = controller
        window.makeKeyAndVisible()
        self.window = window
        var editor: MarkdownTextView?
        try await waitUntil("the note is shown") {
            editor = self.descendants(of: controller.view, matching: MarkdownTextView.self).first { editor in
                editor.window != nil && editor.text == session.text && editor.bounds.width > 0
            }
            return editor != nil
        }
        return (workspace, session, try XCTUnwrap(editor))
    }

    private func descendants<View: UIView>(of parent: UIView, matching type: View.Type) -> [View] {
        parent.subviews.flatMap { child in ((child as? View).map { [$0] } ?? []) + descendants(of: child, matching: type) }
    }
}
#endif
