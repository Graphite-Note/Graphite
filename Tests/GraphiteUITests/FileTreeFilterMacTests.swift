/**
 * File: FileTreeFilterMacTests.swift
 * ----------------------------------
 * Layer: Tests
 * Description: The Files panel's filter on the Mac's outline: typing part of a folder's name shows that folder, the
 *              folders above matches expanded and the match marked, clearing brings the tree's expanded folders back
 *              with the folder chosen while filtering, the sidebar's search stays as it was, a folder search result
 *              reveals its folder, and the command that puts the cursor in the field.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 11/11/2026
 */

#if os(macOS)
import AppKit
import SwiftUI
import XCTest
import GraphiteApple
import GraphiteCore
@testable import GraphiteIndex
@testable import GraphiteUI
import GraphiteTestSupport

@MainActor
final class FileTreeFilterMacTests: XCTestCase {
    private var windows: [NSWindow] = []
    private var device: IsolatedWorkspaceDevice!

    override func setUp() async throws {
        device = try IsolatedWorkspaceDevice.make(for: self)
    }

    override func tearDown() async throws {
        for window in windows { window.close() }
        windows = []
        try await super.tearDown()
    }

    private static let files = ["Batikha-hour/Steak.md", "Courses/Week 1.md", "Courses/Week 2.md", "Deep/Inner/Batikha notes.md", "Root.md"]

    private func indexedWorkspace(files: [String] = files) async throws -> WorkspaceModel {
        let vault = try TemporaryVault.make(prefix: "FileTreeFilterVault", for: self).root.resolvingSymlinksInPath()
        for file in files {
            let location = vault.appendingPathComponent(file)
            try FileManager.default.createDirectory(at: location.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("# \(file)\nsteak\n".utf8).write(to: location)
        }
        let indexFolder = try TemporaryVault.make(prefix: "FileTreeFilterIndex", for: self).root
        let index = try VaultIndex(databaseURL: indexFolder.appendingPathComponent("index.sqlite"))
        _ = try await index.reconcile(root: vault)
        let workspace = device.makeWorkspace()
        workspace.folderAccess = FolderAccess(root: vault)
        workspace.store = VaultStore(root: vault)
        workspace.index = index
        workspace.hasCompletedIndexScan = true
        await workspace.refreshDirectory()
        return workspace
    }

    private func showSidebar(of workspace: WorkspaceModel) async throws -> (window: NSWindow, outlineView: NSOutlineView) {
        let sidebar = VaultSidebar(workspace: workspace, creation: .constant(nil), showsSettings: .constant(false), showsVaultManager: .constant(false))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 700), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: NavigationStack { sidebar })
        window.showInvisibly()
        windows.append(window)
        var outlineView: NSOutlineView?
        try await waitUntil {
            outlineView = Self.firstView(of: NSOutlineView.self, in: window.contentView)
            return outlineView != nil
        }
        return (window, try XCTUnwrap(outlineView))
    }

    private static func firstView<View: NSView>(of type: View.Type, in view: NSView?, matching matches: (View) -> Bool = { _ in true }) -> View? {
        guard let view else { return nil }
        if let found = view as? View, matches(found) { return found }
        for subview in view.subviews {
            if let found = firstView(of: type, in: subview, matching: matches) { return found }
        }
        return nil
    }

    private func filterField(in window: NSWindow) -> NSTextField? {
        Self.firstView(of: NSTextField.self, in: window.contentView) { field in field.placeholderString == "Filter" && field.isEditable }
    }

    /// The rows the outline shows, each indented by its depth.
    private func shownRows(of outlineView: NSOutlineView) -> [String] {
        (0..<outlineView.numberOfRows).compactMap { row in
            (outlineView.item(atRow: row) as? FileTreeNode).map { node in String(repeating: "  ", count: outlineView.level(forRow: row)) + node.path.name }
        }
    }

    private func node(named path: String, in outlineView: NSOutlineView) throws -> FileTreeNode {
        let node = (0..<outlineView.numberOfRows).lazy.compactMap { row in outlineView.item(atRow: row) as? FileTreeNode }.first { node in node.path.rawValue == path }
        return try XCTUnwrap(node, "\(path) is shown")
    }

    func testTypingPartOfAFolderNameShowsItAndClearingBringsBackTheExpandedFoldersWithTheChosenOne() async throws {
        let workspace = try await indexedWorkspace()
        let courses = try VaultPath("Courses")
        workspace.expandedFolders = [courses]
        let (window, outlineView) = try await showSidebar(of: workspace)
        try await waitUntil { self.shownRows(of: outlineView) == ["Batikha-hour", "Courses", "  Week 1.md", "  Week 2.md", "Deep", "Root.md"] }

        // Typed into the field itself, as a person types.
        let field = try XCTUnwrap(filterField(in: window), "The Files panel has a filter field of its own")
        XCTAssertTrue(window.makeFirstResponder(field))
        let editor = try XCTUnwrap(window.firstResponder as? NSTextView)
        editor.insertText("bati", replacementRange: editor.selectedRange())
        let filter = workspace.fileTreeContents.filter
        try await waitUntil { filter.text == "bati" }
        try await waitUntil { self.shownRows(of: outlineView) == ["Batikha-hour", "Deep", "  Inner", "    Batikha notes.md"] }
        let batikha = try node(named: "Batikha-hour", in: outlineView)
        XCTAssertFalse(outlineView.isItemExpanded(batikha), "A matching folder stays collapsed")
        XCTAssertTrue(outlineView.isExpandable(batikha))
        let cell = try XCTUnwrap(outlineView.view(atColumn: 0, row: 0, makeIfNecessary: true) as? FileTreeCellView)
        XCTAssertNotNil(cell.drawnTitle.attribute(.backgroundColor, at: 0, effectiveRange: nil), "The matched part of the name is marked")
        XCTAssertNil(cell.drawnTitle.attribute(.backgroundColor, at: 5, effectiveRange: nil))
        XCTAssertEqual(workspace.expandedFolders, [courses], "The tree's own expanded folders are left as they were")

        // Choosing the folder expands it with its whole content.
        outlineView.expandItem(batikha)
        try await waitUntil { self.shownRows(of: outlineView).prefix(2) == ["Batikha-hour", "  Steak.md"] }
        XCTAssertEqual(workspace.expandedFolders, [courses])

        // Escape empties the field; the tree comes back with its folders, and the folder chosen stays expanded and in sight.
        let escape = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
                                                    context: nil, characters: "\u{1B}", charactersIgnoringModifiers: "\u{1B}", isARepeat: false, keyCode: 53))
        window.sendEvent(escape)
        try await waitUntil { filter.text.isEmpty }
        try await waitUntil {
            self.shownRows(of: outlineView) == ["Batikha-hour", "  Steak.md", "Courses", "  Week 1.md", "  Week 2.md", "Deep", "Root.md"]
        }
        XCTAssertEqual(workspace.expandedFolders, [courses, try VaultPath("Batikha-hour")])
        try await waitUntil { outlineView.selectedRow == 0 }
    }

    func testArrowKeysMoveThroughTheFilteredRowsAndOpenFiles() async throws {
        let workspace = try await indexedWorkspace()
        let (window, outlineView) = try await showSidebar(of: workspace)
        try await waitUntil { outlineView.numberOfRows == 4 }
        let filter = workspace.fileTreeContents.filter
        filter.text = "week"
        try await waitUntil { self.shownRows(of: outlineView) == ["Courses", "  Week 1.md", "  Week 2.md"] }
        // Down arrow moves to the next row and opens its file, as it does in the tree.
        outlineView.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
        try await waitUntil { workspace.selection?.rawValue == "Courses/Week 1.md" }
        XCTAssertTrue(window.makeFirstResponder(outlineView))
        let downArrow = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.numericPad, .function], timestamp: 0,
                                                       windowNumber: window.windowNumber, context: nil, characters: "\u{F701}",
                                                       charactersIgnoringModifiers: "\u{F701}", isARepeat: false, keyCode: 125))
        outlineView.keyDown(with: downArrow)
        try await waitUntil { workspace.selection?.rawValue == "Courses/Week 2.md" }
        XCTAssertEqual(self.shownRows(of: outlineView), ["Courses", "  Week 1.md", "  Week 2.md"], "Opening a file keeps the filter")

        // Emptied, the tree comes back as it was. The clear button itself is checked on the iPad, where SwiftUI's
        // controls are found as VoiceOver finds them.
        filter.clear()
        try await waitUntil { outlineView.numberOfRows == 4 }
    }

    func testTheSidebarsSearchIsUnchangedByTheFilter() async throws {
        let workspace = try await indexedWorkspace()
        let (window, outlineView) = try await showSidebar(of: workspace)
        try await waitUntil { outlineView.numberOfRows == 4 }
        workspace.fileTreeContents.filter.text = "bati"
        workspace.searchQuery = "steak"
        await workspace.search()
        XCTAssertEqual(Set(workspace.searchResults.map(\.path.rawValue)), Set(Self.files), "Full-text results, every note mentioning steak")
        XCTAssertTrue(workspace.searchResults.allSatisfy { result in result.kind == .file }, "No folder without folder:")
        try await waitUntil { self.filterField(in: window) == nil }
        workspace.searchQuery = ""
        try await waitUntil { self.filterField(in: window) != nil }
    }

    func testAFolderSearchResultRevealsItsFolderExpandedAndSelected() async throws {
        let workspace = try await indexedWorkspace()
        workspace.searchQuery = "folder:bati steak"
        await workspace.search()
        XCTAssertEqual(workspace.searchResults.first.map { result in [result.path.rawValue, "\(result.kind)"] }, ["Batikha-hour", "folder"])
        XCTAssertEqual(workspace.searchResults.filter { result in result.kind == .file }.map(\.path.rawValue), ["Batikha-hour/Steak.md"],
                       "Notes narrowed to those inside a matching folder")
        workspace.revealFolder(try VaultPath("Batikha-hour"))
        XCTAssertEqual(workspace.searchQuery, "", "Choosing a folder clears the search")
        let (_, outlineView) = try await showSidebar(of: workspace)
        XCTAssertTrue(workspace.expandedFolders.contains(try VaultPath("Batikha-hour")))
        try await waitUntil { (outlineView.item(atRow: outlineView.selectedRow) as? FileTreeNode)?.path.rawValue == "Batikha-hour" }
        XCTAssertTrue(outlineView.isItemExpanded(try node(named: "Batikha-hour", in: outlineView)))
    }

    /// The outline makes rows only for what it shows, so a keystroke in a 30,000-file vault redraws in a moment even when
    /// a third of the files match and all 300 folders open (measured on the Mac's debug build).
    func testThirtyThousandFilesFilterInTheOutlineQuickly() throws {
        let controller = FileTreeController(workspace: device.makeWorkspace())
        let scrollView = controller.makeScrollView()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 700), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = scrollView
        window.showInvisibly()
        windows.append(window)
        let outlineView = try XCTUnwrap(controller.outlineView)
        let entries = try (0..<30_000).map { fileIndex in
            VaultEntry(path: try VaultPath(String(format: "Course %03d/Lecture %05d.md", fileIndex % 300, fileIndex)), isDirectory: false, size: 1, modified: .now)
        }
        let nameIndex = FileTreeNameIndex(entries: entries, sortOrder: .alphabetical)
        let clock = ContinuousClock()
        var report: [String] = []
        for (query, expectedRows) in [("lecture 29999", 2), ("lecture 1", 10_300), ("course 01", 10), ("nothing", 0)] {
            let result = try XCTUnwrap(nameIndex.filter(query))
            let elapsed = clock.measure {
                controller.showFilter(FilteredFileTree.Filter(isFiltering: true, result: result, expandedFolders: result.foldersAboveMatches))
                outlineView.layoutSubtreeIfNeeded()
            }
            XCTAssertEqual(outlineView.numberOfRows, expectedRows, query)
            report.append("\(query): \(outlineView.numberOfRows) rows in \(elapsed)")
            XCTAssertLessThan(elapsed, .milliseconds(500), report.joined(separator: "; "))
        }
        print("FileTreeFilterMacTests outline: " + report.joined(separator: "; "))
    }

    func testTheCommandPutsTheCursorInTheFilterField() async throws {
        let workspace = try await indexedWorkspace()
        let (shownWindow, _) = try await showSidebar(of: workspace)
        workspace.searchQuery = "steak"
        try await waitUntil { self.filterField(in: shownWindow) == nil }
        XCTAssertTrue(GraphiteCommand.filterFiles.isAvailable(on: .macOS) && GraphiteCommand.filterFiles.isAvailable(on: .iPadOS))
        let window = WindowActions(showQuickSwitcher: {}, showSettings: {}, showVaultManager: {}, toggleLinksInspector: {}, toggleSidebar: {},
                                   showSidebar: {}, showLinksInspector: {}, create: { _ in }, showTemplatePicker: {}, showTabOverview: {})
        let command = try XCTUnwrap(WorkspaceCommandList.commands(for: workspace, window: window).first { command in command.id == "filter-files" })
        command.run()
        XCTAssertEqual(workspace.searchQuery, "", "The Files panel comes back in place of the search")
        try await waitUntil { (shownWindow.firstResponder as? NSTextView)?.delegate === self.filterField(in: shownWindow) }
    }
}
#endif
