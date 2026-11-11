/**
 * File: FileTreeFilterHostedTests.swift
 * -------------------------------------
 * Layer: Tests
 * Description: The Files panel's filter and the search's folder: in the iPad's window: typing part of a folder's name
 *              in the filter shows that folder, choosing it keeps it open, the clear button brings the tree's expanded
 *              folders back, the sidebar's search is unaffected, a folder result reveals its folder, and a keystroke's
 *              filtering of 30,000 files fits in a frame.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 11/11/2026
 */

#if os(iOS)
import XCTest
import SwiftUI
import GraphiteCore
@testable import GraphiteUI

/// The whole window on the iPad simulator, found by what an assistive technology reads. Nothing here plays sound.
@MainActor
final class FileTreeFilterHostedTests: SettingsHostedTestCase {
    private func openWorkspace() async throws -> WorkspaceModel {
        let files = ["Batikha-hour/Steak.md": "We grilled steak.\n", "Courses/Week 1.md": "Steak is not on the syllabus.\n",
                     "Deep/Inner/Batikha notes.md": "Notes.\n", "Root.md": "Root.\n"]
        let vault = try TemporaryVault.make(prefix: "FileTreeFilterHosted", files: files, for: self).root
        let workspace = device.makeWorkspace()
        try await workspace.openFolderAsVault(vault)
        try await waitUntil("the vault is indexed") { workspace.hasCompletedIndexScan }
        workspace.expandedFolders = [try VaultPath("Courses")]
        return workspace
    }

    /// The window with its sidebar shown: a window with no file open starts with the sidebar hidden.
    private func showWindow(of workspace: WorkspaceModel) async throws -> UIViewController {
        let controller = try host(GraphiteRootView(workspace: workspace), size: CGSize(width: 1180, height: 820), horizontalSizeClass: .regular)
        let showSidebar = try await element(in: controller, "Show Sidebar") { object in object.accessibilityLabel == "Show Sidebar" }
        await follow(showSidebar)
        return controller
    }

    /// A file's row is named by its file name, which shows `.md` where Settings shows extensions.
    private func isNamed(_ object: NSObject, _ name: String) -> Bool {
        object.accessibilityLabel == name || object.accessibilityLabel == name + ".md"
    }

    private func shownRows(of workspace: WorkspaceModel) -> [String] {
        workspace.fileTreeContents.shownRows.map(\.entry.path.rawValue)
    }

    private func filterField(in controller: UIViewController) -> UITextField? {
        textFields(in: controller.view).first { field in field.placeholder == "Filter" && field.window != nil }
    }

    private func attachScreenshot(named name: String) {
        guard let window else { return }
        let screenshot = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
        let attachment = XCTAttachment(image: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testTypingPartOfAFolderNameShowsThatFolderAndClearingBringsTheTreeBack() async throws {
        let workspace = try await openWorkspace()
        let controller = try await showWindow(of: workspace)
        _ = try await element(in: controller, "the tree with Courses expanded") { object in self.isNamed(object, "Week 1") }

        var field: UITextField?
        try await waitUntil("the Files panel's filter field") {
            field = self.filterField(in: controller)
            return field != nil
        }
        let filterField = try XCTUnwrap(field)
        XCTAssertTrue(filterField.becomeFirstResponder())
        filterField.insertText("bati")
        let batikha = try await element(in: controller, "the matching folder, collapsed") { object in
            object.accessibilityLabel == "Batikha-hour" && object.accessibilityValue == "Collapsed"
        }
        // The list's own rows: its accessibility elements include the cells it keeps for reuse.
        try await waitUntil("only the matches and the folders above them show") {
            self.shownRows(of: workspace) == ["Batikha-hour", "Deep", "Deep/Inner", "Deep/Inner/Batikha notes.md"]
        }
        attachScreenshot(named: "Filtered by bati")

        // Choosing the matching folder opens it with all it holds, and keeps it open once the filter is cleared.
        await follow(batikha)
        try await waitUntil("the chosen folder shows all it holds") { self.shownRows(of: workspace).prefix(2) == ["Batikha-hour", "Batikha-hour/Steak.md"] }
        XCTAssertEqual(workspace.expandedFolders, [try VaultPath("Courses")], "The tree's own expanded folders wait as they were")

        let clearButton = try await element(in: controller, "the clear button") { object in
            object.accessibilityLabel == "Clear Filter" && object.accessibilityTraits.contains(.button)
        }
        XCTAssertEqual(clearButton.accessibilityHint, "Clear Filter", "Its tooltip (`help`) says what it does")
        await follow(clearButton)
        try await waitUntil("the field is empty") { workspace.fileTreeContents.filter.text.isEmpty }
        try await waitUntil("the tree as it was, with the folder chosen while filtering still open") {
            self.shownRows(of: workspace) == ["Batikha-hour", "Batikha-hour/Steak.md", "Courses", "Courses/Week 1.md", "Deep", "Root.md"]
        }
        XCTAssertEqual(workspace.expandedFolders, [try VaultPath("Courses"), try VaultPath("Batikha-hour")])
        attachScreenshot(named: "Filter cleared")
    }

    func testTheSidebarsSearchIsUnaffectedAndAFolderResultRevealsItsFolder() async throws {
        let workspace = try await openWorkspace()
        let controller = try await showWindow(of: workspace)
        _ = try await element(in: controller, "the tree") { object in self.isNamed(object, "Week 1") }
        workspace.fileTreeContents.filter.text = "root"
        try await waitUntil("the filtered tree") { self.shownRows(of: workspace) == ["Root.md"] }

        // The sidebar's search runs as before: full-text results, no folder without folder:, and no filter field.
        workspace.searchQuery = "steak"
        try await waitUntil("full-text results") { Set(workspace.searchResults.map(\.path.rawValue)) == ["Batikha-hour/Steak.md", "Courses/Week 1.md"] }
        XCTAssertTrue(workspace.searchResults.allSatisfy { result in result.kind == .file })
        try await waitUntil("the filter field gives way to the results") { self.filterField(in: controller) == nil }

        workspace.searchQuery = "folder:bati"
        let folderResult = try await element(in: controller, "the folder result, above the notes") { object in
            object.accessibilityLabel == "Batikha-hour" && object.accessibilityHint == "Folder. Reveals it in the file tree"
        }
        attachScreenshot(named: "folder:bati results")
        await follow(folderResult)
        try await waitUntil("the search is cleared") { workspace.searchQuery.isEmpty }
        XCTAssertTrue(workspace.fileTreeContents.filter.text.isEmpty, "Revealing a folder shows the whole tree")
        try await waitUntil("the folder revealed, expanded") { self.shownRows(of: workspace).prefix(2) == ["Batikha-hour", "Batikha-hour/Steak.md"] }
        attachScreenshot(named: "Folder revealed")
        XCTAssertEqual(workspace.fileTreeContents.revealedFolder?.rawValue, "Batikha-hour", "Marked as the selected row is")
    }

    /// One keystroke's work on the iPad: matching 30,000 file names in 300 folders and laying out the rows shown, within
    /// a frame (16 ms). The names are read and put in order once, off the main thread, before the first letter.
    func testFilteringThirtyThousandFilesFitsInAFrame() async throws {
        try TimingBudgets.requireTheOwnersDevice()
        let entries = try (0..<30_000).map { fileIndex in
            VaultEntry(path: try VaultPath(String(format: "Course %03d/Lecture %05d.md", fileIndex % 300, fileIndex)), isDirectory: false, size: 1, modified: .now)
        }
        let nameIndex = await Task.detached { FileTreeNameIndex(entries: entries, sortOrder: .alphabetical) }.value
        let filter = FileTreeFilter()
        filter.setNameIndex(nameIndex)
        let clock = ContinuousClock()
        var report: [String] = []
        var slowest = Duration.zero
        for text in ["l", "le", "lec", "lecture 1", "lecture 12", "lecture 123", "course 07", "nothing here"] {
            var rowCount = 0
            let elapsed = clock.measure {
                filter.text = text
                rowCount = filter.rows.count
            }
            slowest = max(slowest, elapsed)
            report.append("\(text): \(rowCount) rows in \(elapsed)")
        }
        print("FileTreeFilterHostedTests timing: " + report.joined(separator: "; "))
        XCTAssertLessThan(slowest, .milliseconds(16), report.joined(separator: "; "))
    }
}
#endif
