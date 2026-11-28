/**
 * File: UiFileTreeInlineNamingMacTests.swift
 * ------------------------------------------
 * Layer: Tests
 * Description: The Mac file tree names new items and renames in its own rows, as VSCodium's explorer does, and the
 *              sheets stand in when no tree is on screen.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 27/11/2026
 */

#if os(macOS)
import AppKit
import SwiftUI
import XCTest
import GraphiteApple
import GraphiteCore
import GraphiteIndex
@testable import GraphiteUI
import GraphiteTestSupport

@MainActor
final class UiFileTreeInlineNamingMacTests: XCTestCase {
    private var windows: [NSWindow] = []

    override func tearDown() async throws {
        for window in windows { window.close() }
        windows = []
        try await super.tearDown()
    }

    /// New Note in a folded folder opens it and adds an empty field in its row of the tree, where the folder's files
    /// begin; Return makes the note there and the row goes.
    func testANewNoteIsNamedInARowOfItsFolder() async throws {
        let (workspace, vault) = try makeWorkspace(files: ["Course/Week 1.md", "Root.md"])
        await workspace.refreshDirectory()
        let outlineView = try await showSidebar(of: workspace)
        try await waitUntil { outlineView.numberOfRows == 2 }
        let course = try VaultPath("Course")

        XCTAssertTrue(workspace.beginNamingInFileTree(.note, in: course))
        try await waitUntil { outlineView.numberOfRows == 4 }
        XCTAssertTrue(workspace.expandedFolders.contains(course))
        XCTAssertTrue(outlineView.item(atRow: 1) is FileTreeNewItemRow, "The field is the folder's first file.")
        let cell = try XCTUnwrap(outlineView.view(atColumn: 0, row: 1, makeIfNecessary: false) as? FileTreeCellView)
        XCTAssertTrue(cell.showsNameField)
        let fieldEditor = try typingEditor(in: outlineView)
        XCTAssertEqual(fieldEditor.string, "")

        fieldEditor.insertText("Week 2", replacementRange: fieldEditor.selectedRange())
        fieldEditor.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        XCTAssertFalse(outlineView.item(atRow: 1) is FileTreeNewItemRow)
        try await waitUntil { FileManager.default.fileExists(atPath: vault.appendingPathComponent("Course/Week 2.md").path) }
        XCTAssertNil(workspace.fileSheet)
    }

    /// The vault's folder for new notes two levels down, inside folders never opened: they open one level at a time as
    /// their contents are listed, and the field appears in the deepest. A folder that is not there yet keeps the sheet.
    func testANewNoteInAFolderNeverOpenedOpensTheFoldersAboveIt() async throws {
        let (workspace, _) = try makeWorkspace(files: ["Signals/Labs/Lab 1.md", "Signals/Week 1.md", "Root.md"])
        await workspace.refreshDirectory()
        let outlineView = try await showSidebar(of: workspace)
        try await waitUntil { outlineView.numberOfRows == 2 }

        XCTAssertFalse(workspace.beginNamingInFileTree(.note, in: try VaultPath("Signals/Missing")))
        XCTAssertTrue(workspace.beginNamingInFileTree(.note, in: try VaultPath("Signals/Labs")))
        // Signals, Labs, the field, Lab 1, Week 1, Root.
        try await waitUntil { outlineView.numberOfRows == 6 }
        XCTAssertTrue(outlineView.item(atRow: 2) is FileTreeNewItemRow)
        XCTAssertEqual(outlineView.level(forRow: 2), 2)
        _ = try typingEditor(in: outlineView)
    }

    /// Escape takes the row away and makes nothing.
    func testEscapeLeavesTheVaultAsItWas() async throws {
        let (workspace, vault) = try makeWorkspace(files: ["Root.md"])
        await workspace.refreshDirectory()
        let outlineView = try await showSidebar(of: workspace)
        try await waitUntil { outlineView.numberOfRows == 1 }

        XCTAssertTrue(workspace.beginNamingInFileTree(.note, in: .root))
        XCTAssertEqual(outlineView.numberOfRows, 2)
        let fieldEditor = try typingEditor(in: outlineView)
        fieldEditor.insertText("Draft", replacementRange: fieldEditor.selectedRange())
        fieldEditor.doCommand(by: #selector(NSResponder.cancelOperation(_:)))
        XCTAssertEqual(outlineView.numberOfRows, 1)
        await ManualClock.letResumedTasksRun()
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: vault.path).filter { name in !name.hasPrefix(".") }, ["Root.md"])
    }

    /// A second new item reuses the first one's cell, which shows only the new field: the first field stayed under it,
    /// its "Untitled" drawn through the typed name (seen in the app on 2026-11-28).
    func testASecondNewItemShowsOneField() async throws {
        let (workspace, _) = try makeWorkspace(files: ["Root.md"])
        await workspace.refreshDirectory()
        let outlineView = try await showSidebar(of: workspace)
        try await waitUntil { outlineView.numberOfRows == 1 }

        XCTAssertTrue(workspace.beginNamingInFileTree(.note, in: .root))
        try typingEditor(in: outlineView).doCommand(by: #selector(NSResponder.cancelOperation(_:)))
        XCTAssertTrue(workspace.beginNamingInFileTree(.canvas, in: .root))
        let row = try XCTUnwrap((0..<outlineView.numberOfRows).first { row in outlineView.item(atRow: row) is FileTreeNewItemRow })
        let cell = try XCTUnwrap(outlineView.view(atColumn: 0, row: row, makeIfNecessary: false) as? FileTreeCellView)
        XCTAssertEqual(cell.nameFieldCount, 1)
        try typingEditor(in: outlineView).doCommand(by: #selector(NSResponder.cancelOperation(_:)))
        XCTAssertEqual(cell.nameFieldCount, 0)
    }

    /// A typed name left by a click elsewhere is kept, as in VSCodium, but the new note does not open: the click chose
    /// another row, whose item opens (seen in the app on 2026-11-28, where the new note opened over the note clicked).
    func testAClickElsewhereKeepsTheNameWithoutOpeningTheNewNote() async throws {
        let (workspace, vault) = try makeWorkspace(files: ["Root.md"])
        await workspace.refreshDirectory()
        let outlineView = try await showSidebar(of: workspace)
        try await waitUntil { outlineView.numberOfRows == 1 }
        let root = try VaultPath("Root.md")
        await workspace.open(root)
        XCTAssertEqual(workspace.selection, root)

        XCTAssertTrue(workspace.beginNamingInFileTree(.note, in: .root))
        let fieldEditor = try typingEditor(in: outlineView)
        fieldEditor.insertText("Click check", replacementRange: fieldEditor.selectedRange())
        outlineView.window?.makeFirstResponder(outlineView)
        try await waitUntil { FileManager.default.fileExists(atPath: vault.appendingPathComponent("Click check.md").path) }
        await ManualClock.letResumedTasksRun()
        XCTAssertEqual(workspace.selection, root, "The new note is made without taking the place of what the click opens.")
        try await waitUntil { outlineView.numberOfRows == 2 && !(outlineView.item(atRow: 1) is FileTreeNewItemRow) }
    }

    /// Rename turns the row's name into a field with the name selected; Return renames the file, and the row is a
    /// row again.
    func testARenameIsTypedInTheItemsRow() async throws {
        let (workspace, vault) = try makeWorkspace(files: ["Lecture.md", "Other.md"])
        // A move plans its link updates with the index.
        let indexFolder = try TemporaryVault.make(prefix: "TreeNamingIndex", for: self).root
        let index = try VaultIndex(databaseURL: indexFolder.appendingPathComponent("index.sqlite"))
        _ = try await index.reconcile(root: vault)
        workspace.index = index
        workspace.hasCompletedIndexScan = true
        await workspace.refreshDirectory()
        let outlineView = try await showSidebar(of: workspace)
        try await waitUntil { outlineView.numberOfRows == 2 }

        workspace.requestRename(try VaultPath("Lecture.md"))
        XCTAssertNil(workspace.fileSheet, "No sheet: the row is the field.")
        let cell = try XCTUnwrap(outlineView.view(atColumn: 0, row: 0, makeIfNecessary: false) as? FileTreeCellView)
        XCTAssertTrue(cell.showsNameField)
        let fieldEditor = try typingEditor(in: outlineView)
        XCTAssertEqual(fieldEditor.string, "Lecture")
        XCTAssertEqual(fieldEditor.selectedRange(), NSRange(location: 0, length: 7), "Typing replaces the whole name.")

        fieldEditor.insertText("Lecture 1", replacementRange: fieldEditor.selectedRange())
        fieldEditor.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        XCTAssertFalse(cell.showsNameField)
        try await waitUntil("“Lecture 1.md” on disk (notice: \(workspace.notice ?? "none"), error: \(workspace.errorMessage ?? "none"))") {
            FileManager.default.fileExists(atPath: vault.appendingPathComponent("Lecture 1.md").path)
        }
    }

    /// A PDF's rename types its name alone: its extension stays after the field, muted, where it is drawn (issue #270).
    func testAPDFsRenameShowsItsExtensionMutedAfterTheField() async throws {
        let (workspace, _) = try makeWorkspace(files: ["Handout.pdf", "Welcome.md"])
        await workspace.refreshDirectory()
        let outlineView = try await showSidebar(of: workspace)
        try await waitUntil { outlineView.numberOfRows == 2 }
        workspace.requestRename(try VaultPath("Handout.pdf"))
        let row = (0..<outlineView.numberOfRows).first { row in
            (outlineView.view(atColumn: 0, row: row, makeIfNecessary: false) as? FileTreeCellView)?.showsNameField == true
        }
        let cell = try XCTUnwrap(row.flatMap { row in outlineView.view(atColumn: 0, row: row, makeIfNecessary: false) as? FileTreeCellView })
        cell.layoutSubtreeIfNeeded()
        XCTAssertEqual(try typingEditor(in: outlineView).string, "Handout", "The name alone is typed.")
        let suffix = try XCTUnwrap(cell.shownNameFieldSuffix, "The extension shows after the field.")
        XCTAssertEqual(suffix.text, ".pdf")
        XCTAssertEqual(suffix.color, .secondaryLabelColor, "Muted, as the tree's extensions are.")
        let field = try XCTUnwrap(cell.subviews.first { subview in subview is FileTreeNameField })
        XCTAssertGreaterThanOrEqual(suffix.frame.minX, field.frame.maxX, "After the field.")
        XCTAssertLessThanOrEqual(suffix.frame.maxX, cell.bounds.maxX + 0.5, "Inside the row.")
        XCTAssertGreaterThan(suffix.frame.width, 10, "Wide enough to read: \(suffix.frame).")
        // Drawn: the extension's part of the row has the text's pixels.
        let picture = try XCTUnwrap(cell.bitmapImageRepForCachingDisplay(in: cell.bounds))
        cell.cacheDisplay(in: cell.bounds, to: picture)
        let background = picture.colorAt(x: 1, y: 1)
        var drawnPixels = 0
        let scale = CGFloat(picture.pixelsWide) / cell.bounds.width
        for x in Int(suffix.frame.minX * scale)..<Int(suffix.frame.maxX * scale) {
            for y in Int((cell.bounds.height - suffix.frame.maxY) * scale)..<Int((cell.bounds.height - suffix.frame.minY) * scale)
            where picture.colorAt(x: x, y: y) != background { drawnPixels += 1 }
        }
        XCTAssertGreaterThan(drawnPixels, 20, "The extension's text is drawn.")
    }

    /// A name another item of the folder has keeps the field open on Return, and renames nothing.
    func testReturnOnATakenNameKeepsTheField() async throws {
        let (workspace, vault) = try makeWorkspace(files: ["Lecture.md", "Other.md"])
        await workspace.refreshDirectory()
        let outlineView = try await showSidebar(of: workspace)
        try await waitUntil { outlineView.numberOfRows == 2 }

        workspace.requestRename(try VaultPath("Lecture.md"))
        let fieldEditor = try typingEditor(in: outlineView)
        fieldEditor.insertText("other", replacementRange: fieldEditor.selectedRange())
        fieldEditor.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        let cell = try XCTUnwrap(outlineView.view(atColumn: 0, row: 0, makeIfNecessary: false) as? FileTreeCellView)
        XCTAssertTrue(cell.showsNameField)
        fieldEditor.doCommand(by: #selector(NSResponder.cancelOperation(_:)))
        XCTAssertFalse(cell.showsNameField)
        await ManualClock.letResumedTasksRun()
        XCTAssertTrue(FileManager.default.fileExists(atPath: vault.appendingPathComponent("Lecture.md").path))
    }

    /// A listing that arrives while a name is typed waits: the field stays in its row, and the new file shows once the
    /// field is left.
    func testAListingWhileTypingKeepsTheField() async throws {
        let (workspace, vault) = try makeWorkspace(files: ["Root.md"])
        await workspace.refreshDirectory()
        let outlineView = try await showSidebar(of: workspace)
        try await waitUntil { outlineView.numberOfRows == 1 }

        XCTAssertTrue(workspace.beginNamingInFileTree(.base, in: .root))
        let fieldEditor = try typingEditor(in: outlineView)
        try Data("# Synced\n".utf8).write(to: vault.appendingPathComponent("Synced.md"))
        await workspace.refreshDirectory()
        await ManualClock.letResumedTasksRun()
        XCTAssertEqual(outlineView.numberOfRows, 2)
        XCTAssertIdentical(outlineView.window?.firstResponder, fieldEditor, "The field keeps the keyboard.")

        fieldEditor.doCommand(by: #selector(NSResponder.cancelOperation(_:)))
        try await waitUntil { outlineView.numberOfRows == 2 && !(outlineView.item(atRow: 1) is FileTreeNewItemRow) }
    }

    /// With no tree on screen, Rename and New Folder ask in their sheets, and a notebook always does.
    func testTheSheetsStandInWithoutATree() throws {
        let (workspace, _) = try makeWorkspace(files: ["Lecture.md"])
        workspace.requestRename(try VaultPath("Lecture.md"))
        XCTAssertEqual(workspace.fileSheet?.id, "rename|Lecture.md")
        workspace.requestNewFolder(in: .root)
        XCTAssertEqual(workspace.fileSheet?.id, "folder|")
        XCTAssertFalse(workspace.beginNamingInFileTree(.note, in: nil))
    }

    func testANotebookKeepsItsSheetBesideATree() async throws {
        let (workspace, _) = try makeWorkspace(files: ["Root.md"])
        await workspace.refreshDirectory()
        let outlineView = try await showSidebar(of: workspace)
        try await waitUntil { outlineView.numberOfRows == 1 }
        XCTAssertFalse(workspace.beginNamingInFileTree(.notebook, in: nil))
        XCTAssertEqual(outlineView.numberOfRows, 1)
    }

    // MARK: Helpers

    /// The field editor the name is typed in, which has the window's keyboard.
    private func typingEditor(in outlineView: NSOutlineView) throws -> NSTextView {
        let fieldEditor = try XCTUnwrap(outlineView.window?.firstResponder as? NSTextView)
        XCTAssertTrue(fieldEditor.delegate.map { delegate in delegate as AnyObject } is FileTreeNameField)
        return fieldEditor
    }

    private func makeWorkspace(files: [String]) throws -> (WorkspaceModel, URL) {
        let vault = try TemporaryVault.make(prefix: "TreeNamingVault", for: self).root
        for file in files {
            let location = vault.appendingPathComponent(file)
            try FileManager.default.createDirectory(at: location.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("# \(file)\n".utf8).write(to: location)
        }
        let workspace = WorkspaceModel()
        workspace.folderAccess = FolderAccess(root: vault)
        workspace.store = VaultStore(root: vault)
        return (workspace, vault)
    }

    private func showSidebar(of workspace: WorkspaceModel) async throws -> NSOutlineView {
        let sidebar = VaultSidebar(workspace: workspace, creation: .constant(nil), showsSettings: .constant(false), showsVaultManager: .constant(false))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 700), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: NavigationStack { sidebar })
        window.showInvisibly()
        windows.append(window)
        var outlineView: NSOutlineView?
        try await waitUntil {
            outlineView = Self.firstOutlineView(in: window.contentView)
            return outlineView != nil
        }
        return try XCTUnwrap(outlineView)
    }

    private static func firstOutlineView(in view: NSView?) -> NSOutlineView? {
        guard let view else { return nil }
        if let outlineView = view as? NSOutlineView { return outlineView }
        for subview in view.subviews {
            if let outlineView = firstOutlineView(in: subview) { return outlineView }
        }
        return nil
    }
}
#endif
