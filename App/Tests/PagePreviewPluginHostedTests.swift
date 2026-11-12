/**
 * File: PagePreviewPluginHostedTests.swift
 * ----------------------------------------
 * Layer: Tests
 * Description: A community plugin's hover-link from its view shows Page Preview's card in the hosted app on the iPad.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 12/11/2026
 */
#if os(iOS)
import XCTest
import SwiftUI
import WebKit
import GraphiteApple
import GraphiteCore
@testable import GraphiteUI

/// A plugin's `hover-link` in the hosted app on the iPad: a view in a tab, shown as a copy of
/// what the plugin drew, asks to preview a note when the pointer comes onto one of its rows,
/// as Recent Files' list does, and the window's card shows that note beside the row. Recent
/// Files itself is built only for the Node tests (`npm run build-compatibility-plugins`), so
/// the test plugin triggers `hover-link` with the arguments Recent Files gives it.
@MainActor
final class PagePreviewPluginHostedTests: XCTestCase {
    private var window: UIWindow?
    private var vaultDirectory: URL?
    private var openedVaultIdentifier: UUID?
    private var workspace: WorkspaceModel?

    private static let pluginIdentifier = "graphite-recent-rows"

    /// A view listing one note, `Other.md`, by its path; the pointer on its row asks Graphite
    /// to preview it, from the plugin's own hover link source.
    private static let pluginSource = """
    'use strict';
    const { Plugin, ItemView } = require('obsidian');
    class RecentRowsView extends ItemView {
        constructor(leaf, plugin) { super(leaf); this.plugin = plugin; }
        getViewType() { return 'recent-rows'; }
        getDisplayText() { return 'Recent rows'; }
        async onOpen() {
            const row = this.contentEl.createDiv({ cls: 'nav-file recent-row', text: 'Other' });
            row.addEventListener('mouseover', (event) => {
                this.app.workspace.trigger('hover-link', { event, source: 'recent-rows', hoverParent: this.contentEl, targetEl: row, linktext: 'Other.md', sourcePath: '' });
            });
        }
    }
    module.exports = class RecentRowsPlugin extends Plugin {
        onload() {
            this.registerHoverLinkSource('recent-rows', { display: 'Recent rows', defaultMod: true });
            this.registerView('recent-rows', (leaf) => new RecentRowsView(leaf, this));
            this.addCommand({ id: 'open-view', name: 'Open view', callback: async () => {
                await this.app.workspace.getLeaf('tab').setViewState({ type: 'recent-rows', active: true });
            } });
        }
    };
    """

    override func tearDown() async throws {
        if let workspace {
            await workspace.communityPlugins.vaultWillClose()
            if let openedVaultIdentifier {
                workspace.vaultLibrary.remove(openedVaultIdentifier)
                CommunityPluginHost.forgetVault(openedVaultIdentifier)
            }
        }
        workspace = nil
        window?.isHidden = true
        window?.rootViewController = nil
        window = nil
        if let vaultDirectory { try? FileManager.default.removeItem(at: vaultDirectory) } // Best-effort removal of a temporary folder.
        vaultDirectory = nil
        openedVaultIdentifier = nil
    }

    func testAPluginsHoverLinkInItsViewShowsTheNotesCardBesideItsRow() async throws {
        let workspace = try await workspaceWithRunningPlugin()
        let host = workspace.communityPlugins
        let command = try XCTUnwrap(host.commands.first { command in command.id == Self.pluginIdentifier + ":open-view" })
        await host.run(command)
        try await waitUntil("the view opens in a tab") { workspace.tabDocuments.values.contains { document in document.pluginViewIdentifier != nil } }
        // An item view is shown as a copy of what the plugin drew, as Recent Files' list is.
        var copy: WKWebView?
        try await waitUntil("the tab shows the view's copy", timeoutSeconds: 15) {
            copy = self.webViews().first { webView in webView !== host.webView }
            return copy != nil
        }
        let webView = try XCTUnwrap(copy)
        try await waitUntil("the copy shows the plugin's row", timeoutSeconds: 10) {
            try await webView.callAsyncJavaScript("return document.querySelector('.recent-row[data-graphite-listens~=hover]') !== null;",
                                                  arguments: [:], in: nil, contentWorld: .defaultClient) as? Bool == true
        }
        let coordinator = try XCTUnwrap(webView.navigationDelegate as? CommunityPluginCodeBlockDisplayCoordinator)
        let cards = try XCTUnwrap(coordinator.linkPreviews.linkPreviews, "The copy shows the window's cards.")

        // A mouse's pointer coming onto the row, as WebKit reports it to the copy's own script.
        let moveOntoRow = """
        const row = document.querySelector('.recent-row');
        const bounds = row.getBoundingClientRect();
        row.dispatchEvent(new PointerEvent('pointermove', { bubbles: true, pointerType: 'mouse', buttons: 0, clientX: bounds.left + 4, clientY: bounds.top + 4 }));
        """
        _ = try await webView.callAsyncJavaScript(moveOntoRow, arguments: [:], in: nil, contentWorld: .defaultClient)
        try await waitUntil("the plugin's row asks for its card", timeoutSeconds: 5) { cards.phase.request?.target == "Other.md" }
        let request = try XCTUnwrap(cards.phase.request)
        XCTAssertEqual(request.source, .plugin)
        XCTAssertEqual(request.trigger, .hover)
        let window = try XCTUnwrap(window)
        XCTAssertGreaterThan(request.anchor.width, 0)
        XCTAssertTrue(webView.convert(webView.bounds, to: nil).intersects(request.anchor), "The card goes beside the row, measured in the copy: \(request.anchor)")
        try await waitUntil("the card shows the note once the delay ends") {
            if case .shown(_, let content) = cards.phase { content.path.rawValue == "Other.md" } else { false }
        }
        XCTAssertTrue(window.bounds.contains(request.anchor.origin))
        attachScreenshot(named: "The plugin's row with its card")

        _ = try await webView.callAsyncJavaScript("document.dispatchEvent(new PointerEvent('pointerleave', { pointerType: 'mouse' }));",
                                                  arguments: [:], in: nil, contentWorld: .defaultClient)
        try await waitUntil("leaving the view closes the card") { if case .hidden = cards.phase { true } else { false } }
    }

    // MARK: Helpers

    private func webViews() -> [WKWebView] {
        guard let window else { return [] }
        func descendants(of view: UIView) -> [WKWebView] {
            view.subviews.flatMap { child in ((child as? WKWebView).map { webView in [webView] } ?? []) + descendants(of: child) }
        }
        return descendants(of: window)
    }

    /// A vault with the test plugin, opened as the app opens one, in a window with the plugin
    /// panel and the window's preview cards, with community plugins turned on and the plugin
    /// running. The window comes first, as in the app.
    private func workspaceWithRunningPlugin() async throws -> WorkspaceModel {
        let directory = hostedTemporaryLocation(named: "PagePreviewPlugin")
        vaultDirectory = directory
        let pluginFolder = directory.appendingPathComponent(".obsidian/plugins/\(Self.pluginIdentifier)")
        try FileManager.default.createDirectory(at: pluginFolder, withIntermediateDirectories: true)
        try Data("# Other\n\nThe note the row names.\n".utf8).write(to: directory.appendingPathComponent("Other.md"))
        let manifest = "{\"id\": \"\(Self.pluginIdentifier)\", \"name\": \"Recent Rows\", \"version\": \"1.0.0\", \"minAppVersion\": \"1.0.0\", \"author\": \"Graphite\"}"
        try Data(manifest.utf8).write(to: pluginFolder.appendingPathComponent("manifest.json"))
        try Data(Self.pluginSource.utf8).write(to: pluginFolder.appendingPathComponent("main.js"))
        try Data("[\n  \"\(Self.pluginIdentifier)\"\n]".utf8).write(to: directory.appendingPathComponent(".obsidian/community-plugins.json"))

        let workspace = WorkspaceModel()
        self.workspace = workspace
        try await workspace.openFolderAsVault(directory)
        openedVaultIdentifier = try XCTUnwrap(workspace.currentVaultIdentifier)
        let rootView = AnyView(NavigationStack {
            WorkspacePanes(workspace: workspace, showsLinksInspector: .constant(false), create: { _ in }, showQuickSwitcher: {})
        }
        .modifier(CommunityPluginPresentation(workspace: workspace) {})
        .modifier(LinkPreviewLayer(isEnabled: true, vault: workspace.linkPreviewVault)))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { scene in scene as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.effectiveGeometry.coordinateSpace.bounds
        window.rootViewController = UIHostingController(rootView: rootView)
        window.makeKeyAndVisible()
        self.window = window

        let host = workspace.communityPlugins
        await host.reloadInventory() // opening lists nothing while plugins are off
        try await waitUntil { host.inventory.plugins.contains { plugin in plugin.id == Self.pluginIdentifier } }
        await host.setTurnedOnForVault(true)
        try await waitUntil("the plugin loads", timeoutSeconds: 15) { host.loadStates[Self.pluginIdentifier] == .loaded }
        try await waitUntil { host.commands.contains { command in command.id == Self.pluginIdentifier + ":open-view" } }
        return workspace
    }

    private func attachScreenshot(named name: String) {
        guard let window else { return }
        let screenshot = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
#endif
