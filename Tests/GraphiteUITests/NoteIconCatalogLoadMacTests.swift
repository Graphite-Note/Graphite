/**
 * File: NoteIconCatalogLoadMacTests.swift
 * ---------------------------------------
 * Layer: Tests
 * Description: A window's note icons are read once the vault's index arrives, also for a vault unchanged since its
 *              last scan, which changes none of the index's properties.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 28/11/2026
 */

#if os(macOS)
import XCTest
import AppKit
import SwiftUI
import GraphiteCore
#if canImport(GraphiteTestSupport)
import GraphiteTestSupport
#endif
@testable import GraphiteUI

@MainActor
final class NoteIconCatalogLoadMacTests: XCTestCase {
    /// Holds the catalog the window's page-look layer gives its views.
    @MainActor private final class CatalogProbe {
        var catalog: NoteIconCatalog?
    }

    private struct CatalogReader: View {
        @Environment(\.noteIcons) private var noteIcons
        let probe: CatalogProbe
        var body: some View {
            Color.clear.onChange(of: noteIcons.map(ObjectIdentifier.init), initial: true) { probe.catalog = noteIcons }
        }
    }

    private func showPageLookLayer(of workspace: WorkspaceModel, probe: CatalogProbe) {
        let view = CatalogReader(probe: probe).modifier(PageLookLayer(isEnabled: true) { [workspace] in workspace.noteIconSource })
        let window = NSWindow(contentViewController: NSHostingController(rootView: view))
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 200, height: 200))
        window.showInvisibly()
        addTeardownBlock { @MainActor in window.contentViewController = nil; window.close() }
    }

    func testAVaultUnchangedSinceItsLastScanStillShowsItsIcons() async throws {
        let vault = try TemporaryVault.make(prefix: "IconLoad", files: [
            "Lab.md": "---\nicon: 🧪\n---\n",
            "Home.md": "[[Lab]]\n",
        ], for: self).root
        let device = try IsolatedWorkspaceDevice.make(for: self)
        let first = device.makeWorkspace()
        try await first.openFolderAsVault(vault)
        try await waitUntil("the vault is indexed", timeoutSeconds: 60) { first.hasCompletedIndexScan && !first.isIndexing }
        // Opened again, nothing changed: the window is up before the vault, as when the app restores its last vault.
        let second = device.makeWorkspace()
        let probe = CatalogProbe()
        showPageLookLayer(of: second, probe: probe)
        try await second.openFolderAsVault(vault)
        try await waitUntil("the vault is scanned", timeoutSeconds: 60) { second.hasCompletedIndexScan && !second.isIndexing }
        let lab = try VaultPath("Lab.md")
        try await waitUntil("the icons are read", timeoutSeconds: 20) { probe.catalog?.icon(of: lab) == .emoji("🧪") }
    }
}
#endif
