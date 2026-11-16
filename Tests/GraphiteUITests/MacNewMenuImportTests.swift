/**
 * File: MacNewMenuImportTests.swift
 * ---------------------------------
 * Layer: Tests
 * Description: The Mac sidebar's New menu offers Import…, which opens the file chooser for files to copy into the vault.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 12/11/2026
 */

#if os(macOS)
import AppKit
import XCTest
import GraphiteCore
@testable import GraphiteUI
import GraphiteTestSupport

/// The window's root view over a vault of one note, with its toolbar bridged as the app's scene does: the sidebar's New
/// button (a click makes a note, its arrow offers the other kinds) is a toolbar item, whose menu AppKit holds as the
/// item's menu form, the menu shown when the toolbar has no room for the button.
@MainActor
final class MacNewMenuImportTests: XCTestCase {
    func testTheSidebarsNewMenuOffersImportWhichOpensTheFileChooser() async throws {
        let vault = try TemporaryVault.make(prefix: "NewMenuImport", for: self).root
        try Data("# Note\n".utf8).write(to: vault.appendingPathComponent("Note.md"))
        let device = try IsolatedWorkspaceDevice.make(for: self)
        let workspace = device.makeWorkspace()
        try await workspace.openFolderAsVault(vault)
        let window = try ReleaseVaultWindow.show(GraphiteRootView(workspace: workspace), for: self)
        var newMenu: NSMenu?
        try await waitUntil("the sidebar's New button is in the toolbar") {
            window.layoutIfNeeded()
            newMenu = window.toolbar?.items.first { item in item.label == "New Note" }?.menuFormRepresentation?.submenu
            return newMenu != nil
        }
        let menu = try XCTUnwrap(newMenu)
        let importIndex = try XCTUnwrap(menu.items.firstIndex { item in item.title == "Import…" }, "New offers \(menu.items.map(\.title))")
        XCTAssertGreaterThan(importIndex, try XCTUnwrap(menu.items.firstIndex { item in item.title == "New Folder" }), "Import… comes last, after New Folder.")
        XCTAssertFalse(workspace.isChoosingFilesToImport)
        menu.performActionForItem(at: importIndex)
        try await waitUntil("Import… asks for the file chooser") { workspace.isChoosingFilesToImport }
    }
}
#endif
