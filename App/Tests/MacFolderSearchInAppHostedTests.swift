/**
 * File: MacFolderSearchInAppHostedTests.swift
 * -------------------------------------------
 * Layer: Tests
 * Description: `folder:` in the sidebar's search inside the running Mac app: the folder listed above the notes with its
 *              path, the row's right-click menu and its Reveal in File Tree revealing it, and `folder:` with another term
 *              narrowing the notes to those inside it.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 27/11/2026
 */

#if os(macOS)
import XCTest
import AppKit
import GraphiteCore
@testable import GraphiteUI

/// `Docs/File-tree-filter-todo.md`, section 2, the Mac's check in the running app, with a made-up folder of the name in
/// the request ("Batikha-hour"). The search is typed through the model the field is bound to (a test in the app has no
/// accessibility tree to type into); the result row is found by asking the views down the sidebar for their right-click
/// menu. A click on the row is not checked here: the test app is not the active app while another keeps the front, and
/// neither a posted click nor one given to the row's views or its list reaches the row's button that way. Runs only with
/// `TEST_RUNNER_GRAPHITE_MAC_FOLDER_SEARCH` given to xcodebuild as a folder, where it writes a picture of each step and the
/// menu's items; a person looks at them.
@MainActor
final class MacFolderSearchInAppHostedTests: XCTestCase {
    static let switchVariable = "GRAPHITE_MAC_FOLDER_SEARCH"
    private var outputFolder: URL?
    private var pictureCount = 0

    func testAFolderResultIsListedFirstAndItsMenuRevealsIt() async throws {
        guard let outputPath = ProcessInfo.processInfo.environment[Self.switchVariable] else { return }
        outputFolder = URL(fileURLWithPath: outputPath, isDirectory: true)
        let vaultRoot = try TemporaryVault.make(prefix: "MacFolderSearch", files: [
            "Welcome.md": "# Demo vault\n\nA small vault for checking folder search.\n",
            "Courses/Batikha-hour/Batikha hour plan.md": "# Batikha hour plan\n\nGrill the steak at seven.\n",
            "Courses/Dinner.md": "# Dinner\n\nSteak and salad.\n",
            "Places/Lisbon.md": "# Lisbon\n\nA weekend away.\n",
        ], for: self).root
        let device = try IsolatedWorkspaceDevice.make(for: self)
        let workspace = device.makeWorkspace()
        try await workspace.openFolderAsVault(vaultRoot)
        try await waitUntil("the vault is indexed", timeoutSeconds: 60) { workspace.hasCompletedIndexScan && !workspace.isIndexing }
        let window = try ReleaseVaultWindow.show(GraphiteRootView(workspace: workspace), for: self)
        window.makeKey()
        let batikha = try VaultPath("Courses/Batikha-hour")
        let courses = try VaultPath("Courses")

        workspace.searchQuery = "folder:bati"
        try await waitUntil("the folder listed first", timeoutSeconds: 30) {
            workspace.searchResults.first.map { result in result.kind == .folder && result.path == batikha } == true
        }
        XCTAssertEqual(workspace.searchResults.filter { result in result.kind == .file }.map(\.path.rawValue), ["Courses/Batikha-hour/Batikha hour plan.md"])
        try await settle(window)
        try writePicture("folder bati results", of: window)

        let menu = try await folderResultMenu(in: window)
        try write(menu.items.map(\.title).joined(separator: "\n"), named: "folder result menu.txt")
        XCTAssertTrue(menu.items.contains { item in item.title == "Reveal in File Tree" }, menu.items.map(\.title).joined(separator: ", "))

        workspace.searchQuery = "folder:bati steak"
        try await waitUntil("the notes narrowed to the folder", timeoutSeconds: 30) {
            workspace.searchResults.first?.kind == .folder
                && workspace.searchResults.filter { result in result.kind == .file }.map(\.path.rawValue) == ["Courses/Batikha-hour/Batikha hour plan.md"]
        }
        try await settle(window)
        try writePicture("folder bati steak results", of: window)
        workspace.expandedFolders.remove(batikha)
        workspace.expandedFolders.remove(courses)

        let secondMenu = try await folderResultMenu(in: window)
        let reveal = try XCTUnwrap(secondMenu.items.first { item in item.title == "Reveal in File Tree" })
        secondMenu.performActionForItem(at: secondMenu.index(of: reveal))
        try await waitUntil("Reveal in File Tree reveals the folder", timeoutSeconds: 20) {
            workspace.searchQuery.isEmpty && workspace.expandedFolders.contains(batikha) && workspace.expandedFolders.contains(courses)
        }
        try await settle(window)
        try writePicture("revealed from the menu", of: window)
    }

    /// The first point down the sidebar whose view offers a right-click menu with Reveal in File Tree: the folder's row.
    private func folderResultMenu(in window: NSWindow) async throws -> NSMenu {
        var found: NSMenu?
        try await waitUntil("the folder result's row", timeoutSeconds: 20) {
            found = self.firstMenu(containing: "Reveal in File Tree", in: window)
            return found != nil
        }
        return try XCTUnwrap(found)
    }

    private func firstMenu(containing title: String, in window: NSWindow) -> NSMenu? {
        let height = window.contentView?.bounds.height ?? 860
        for distanceFromTop in stride(from: 40.0, through: 400.0, by: 6.0) {
            for x in [90.0, 140.0] {
                let point = CGPoint(x: x, y: height - distanceFromTop)
                guard let event = try? mouseEvent(.rightMouseDown, at: point, in: window) else { continue }
                // The view under the pointer or the first view above it that has a menu, as AppKit asks on a right-click.
                var candidate = window.contentView?.hitTest(point)
                while let view = candidate {
                    if let menu = view.menu(for: event) {
                        if menu.items.contains(where: { item in item.title == title }) { return menu }
                        break
                    }
                    candidate = view.superview
                }
            }
        }
        return nil
    }

    private func mouseEvent(_ type: NSEvent.EventType, at windowPoint: CGPoint, in window: NSWindow) throws -> NSEvent {
        try XCTUnwrap(NSEvent.mouseEvent(with: type, location: windowPoint, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                         windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
    }

    private func settle(_ window: NSWindow) async throws {
        _ = try await MainThreadQuietWatch(window: window, quietStepsToStop: 40).measure({}, until: { true })
    }

    private func write(_ text: String, named name: String) throws {
        try Data(text.utf8).write(to: try XCTUnwrap(outputFolder).appendingPathComponent(name))
    }

    private func writePicture(_ name: String, of window: NSWindow) throws {
        pictureCount += 1
        try XCTUnwrap(ReleaseVaultWindow.screenshot(of: window))
            .write(to: try XCTUnwrap(outputFolder).appendingPathComponent(String(format: "%02d %@.png", pictureCount, name)))
    }
}
#endif
