/**
 * File: FileTreeRowNamingHostedTests.swift
 * ----------------------------------------
 * Layer: Tests
 * Description: The iPad's file list names a new note in a row of its folder and renames in the item's row, in the
 *              window as the app draws it; a name the folder has keeps the field open; without the tree the sheet
 *              stands in.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 28/11/2026
 */

#if os(iOS)
import XCTest
import SwiftUI
import GraphiteCore
@testable import GraphiteUI

/// The whole window on the iPad simulator, its list found through UIKit's text fields and the workspace's rows.
@MainActor
final class FileTreeRowNamingHostedTests: SettingsHostedTestCase {
    private var vault: URL?

    private func openWorkspace() async throws -> WorkspaceModel {
        let files = ["Courses/Week 1.md": "Week one.\n", "Root.md": "Root.\n"]
        let vault = try TemporaryVault.make(prefix: "FileTreeRowNamingHosted", files: files, for: self).root
        self.vault = vault
        let workspace = device.makeWorkspace()
        try await workspace.openFolderAsVault(vault)
        try await waitUntil("the vault is indexed") { workspace.hasCompletedIndexScan }
        return workspace
    }

    /// The window with its sidebar shown: a window with no file open starts with the sidebar hidden.
    private func showWindow(of workspace: WorkspaceModel) async throws -> UIViewController {
        let controller = try host(GraphiteRootView(workspace: workspace), size: CGSize(width: 1180, height: 820), horizontalSizeClass: .regular)
        try await showSidebar(in: controller)
        try await waitUntil("the tree's rows") { workspace.fileTreeContents.shownRows.contains { row in row.entry.path.rawValue == "Root.md" } }
        return controller
    }

    /// The row's name field, once it shows and has the keyboard.
    private func nameField(in controller: UIViewController, placeholder: String?) async throws -> UITextField {
        var found: UITextField?
        try await waitUntil("the row's name field has the keyboard") {
            found = self.textFields(in: controller.view).first { field in
                field.window != nil && field.isFirstResponder && (placeholder == nil || field.placeholder == placeholder)
            }
            return found != nil
        }
        return try XCTUnwrap(found)
    }

    /// The keyboard's Return, as UIKit sends it to the field.
    private func pressReturn(in field: UITextField) {
        if field.delegate?.textFieldShouldReturn?(field) ?? true {
            field.sendActions(for: .editingDidEndOnExit)
        }
    }

    private func attachScreenshot(named name: String) {
        guard let window else { return }
        let screenshot = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
        let attachment = XCTAttachment(image: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func fileExists(_ path: String) -> Bool {
        guard let vault else { return false }
        return FileManager.default.fileExists(atPath: vault.appendingPathComponent(path).path)
    }

    /// New Note into a folded folder opens it and puts an empty field hinted "Untitled" in a row of it; Return makes
    /// the note there, with no sheet.
    func testANewNoteIsNamedInARowOfItsFolder() async throws {
        let workspace = try await openWorkspace()
        let controller = try await showWindow(of: workspace)
        let courses = try VaultPath("Courses")

        XCTAssertNil(workspace.creationSheet(.note, in: courses), "The tree names the note, so no sheet is asked for.")
        XCTAssertTrue(workspace.expandedFolders.contains(courses))
        let field = try await nameField(in: controller, placeholder: FileTreeNameDraft.untitledName)
        try await waitUntil("the field is the folder's first file") {
            workspace.fileTreeContents.shownRows.map(\.entry.path.rawValue) == ["Courses", "Courses/Week 1.md", "Root.md"]
        }
        field.insertText("Week 2")
        attachScreenshot(named: "A new note named in its folder's row")
        pressReturn(in: field)
        try await waitUntil("the note is made in its folder") { self.fileExists("Courses/Week 2.md") }
        XCTAssertNil(workspace.fileSheet)
    }

    /// Rename turns the item's row into a field holding its name; Return renames the file.
    func testARenameIsTypedInTheItemsRow() async throws {
        let workspace = try await openWorkspace()
        let controller = try await showWindow(of: workspace)

        workspace.requestRename(try VaultPath("Root.md"))
        XCTAssertNil(workspace.fileSheet, "No Rename sheet while the tree shows the row.")
        let field = try await nameField(in: controller, placeholder: nil)
        XCTAssertEqual(field.text, "Root")
        // The whole name is selected, as the Files app starts a rename, so typing replaces it.
        try await waitUntil("the whole name is selected") {
            field.selectedTextRange.map { range in
                field.offset(from: field.beginningOfDocument, to: range.start) == 0 && field.offset(from: range.start, to: range.end) == 4
            } ?? false
        }
        field.insertText("Start here")
        pressReturn(in: field)
        try await waitUntil("the file is renamed, not \((try? FileManager.default.contentsOfDirectory(atPath: self.vault?.path ?? "")) ?? [])") {
            self.fileExists("Start here.md") && !self.fileExists("Root.md")
        }
    }

    /// A name the folder already has is explained under the field, and Return leaves the field open with the keyboard.
    func testReturnOnATakenNameKeepsTheField() async throws {
        let workspace = try await openWorkspace()
        let controller = try await showWindow(of: workspace)

        XCTAssertTrue(workspace.beginNamingInFileTree(.note, in: nil))
        let field = try await nameField(in: controller, placeholder: FileTreeNameDraft.untitledName)
        field.insertText("root")
        _ = try await element(in: controller, "the problem under the field") { object in
            object.accessibilityLabel?.contains("is already in this folder") == true
        }
        pressReturn(in: field)
        attachScreenshot(named: "A taken name explained under the field")
        try await waitUntil("the field keeps the keyboard") { field.window != nil && field.isFirstResponder }
        XCTAssertNotNil(workspace.fileTreeContents.shownRows.first { row in row.entry.path.rawValue == "Root.md" })
        XCTAssertFalse(fileExists("root 1.md"))
        XCTAssertFalse(fileExists("Untitled.md"))
    }

    /// A hardware keyboard types as soon as the field has the keyboard: every letter stays, in order, with the cursor
    /// after the last. Seen 2026-11-28 in a simulator: "Week 1 Signals" typed at once came out "Week 1 S", the cursor at
    /// the start, as the selection meant for a rename was put on the new item's field after typing had begun.
    func testLettersTypedAtOnceIntoANewItemAreKept() async throws {
        let workspace = try await openWorkspace()
        let controller = try await showWindow(of: workspace)

        XCTAssertTrue(workspace.beginNamingInFileTree(.note, in: try VaultPath("Courses")))
        let field = try await nameField(in: controller, placeholder: FileTreeNameDraft.untitledName)
        for letter in "Week 1 Signals" {
            field.insertText(String(letter))
            await Task.yield()
        }
        // The cursor stays after the last letter typed.
        try await waitUntil("the field holds every letter, the cursor after them, not \(field.text ?? "")") {
            field.text == "Week 1 Signals" && field.selectedTextRange.map { range in
                range.isEmpty && field.offset(from: field.beginningOfDocument, to: range.start) == 14
            } == true
        }
        pressReturn(in: field)
        try await waitUntil("the note is made with every letter") { self.fileExists("Courses/Week 1 Signals.md") }
    }

    /// Escape drops the new item; the next new item's field starts empty and makes nothing until it is named. Seen
    /// 2026-11-28 in a simulator: New Note again right after an Escape made and opened the note the Escape dropped.
    func testANewItemAfterAnEscapeStartsEmpty() async throws {
        let workspace = try await openWorkspace()
        let controller = try await showWindow(of: workspace)
        let courses = try VaultPath("Courses")
        let naming = workspace.fileTreeContents.rowNaming

        XCTAssertTrue(workspace.beginNamingInFileTree(.note, in: courses))
        let first = try await nameField(in: controller, placeholder: FileTreeNameDraft.untitledName)
        first.insertText("Week 3 draft")
        try await waitUntil("the field holds the typed name") { first.text == "Week 3 draft" }
        naming.end(.escapeKey)
        try await waitUntil("the field is gone") { naming.field == nil }

        XCTAssertTrue(workspace.beginNamingInFileTree(.note, in: courses))
        // The dropped field's text field can hold the keyboard until the new one takes it; its leaving speaks for
        // nothing.
        var second: UITextField?
        try await waitUntil("an empty field has the keyboard, not \(self.textFields(in: controller.view).compactMap(\.text))") {
            second = self.textFields(in: controller.view).first { field in field.window != nil && field.isFirstResponder }
            return second?.text == ""
        }
        second?.insertText("Week 4")
        pressReturn(in: try XCTUnwrap(second))
        try await waitUntil("the named note is made") { self.fileExists("Courses/Week 4.md") }
        XCTAssertFalse(fileExists("Courses/Week 3 draft.md"), "The name Escape dropped is never made.")
    }

    /// While the list shows search results, no row can be named: the Rename sheet stands in.
    func testTheSheetStandsInWhenTheTreeIsNotShown() async throws {
        let workspace = try await openWorkspace()
        _ = try await showWindow(of: workspace)
        workspace.searchQuery = "Root"
        try await waitUntil("the list shows the search") { workspace.searchQuery == "Root" }
        // The list's host learns the tree is gone when the sidebar is drawn again.
        try await waitUntil("the list no longer offers its rows") {
            (workspace.fileTreeNaming as? FileTreeRowNaming).map { naming in !naming.isTreeOnScreen() } ?? true
        }

        workspace.requestRename(try VaultPath("Root.md"))
        guard case .rename(let renamed) = workspace.fileSheet else { return XCTFail("The Rename sheet stands in: \(String(describing: workspace.fileSheet))") }
        XCTAssertEqual(renamed, try VaultPath("Root.md"))
    }
}
#endif
