/**
 * File: CommunityPluginBasesEmbedHostedTests.swift
 * ------------------------------------------------
 * Layer: Tests
 * Description: Several plugin-drawn base embeds in the app's own panes on the simulator.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 01/11/2026
 */

import XCTest
import SwiftUI
import WebKit
import GraphiteCore
import GraphiteIndex
@testable import GraphiteUI

#if os(iOS)
/// A note with several embeds of a base whose views a community plugin draws, in the app's own
/// panes on the simulator: every embed shows what the plugin drew, in Live Preview and in the
/// reading view, at its own height. The plugin is a small fixture made here.
@MainActor
final class CommunityPluginBasesEmbedHostedTests: XCTestCase {
    private var window: UIWindow?
    private var vaultDirectories: [URL] = []
    private var openedVaultIdentifiers: [UUID] = []
    private var workspace: WorkspaceModel?

    private static let pluginSource = """
    'use strict';
    const { Plugin, BasesView, NullValue } = require('obsidian');
    class WeekTable extends BasesView {
        constructor(controller, parent) {
            super(controller);
            this.week = 1;
            this.containerEl = parent.createDiv('week-table');
        }
        onDataUpdated() {
            this.containerEl.empty();
            this.containerEl.createEl('h4', { text: String(this.config.get('title')) + ' week ' + this.week });
            this.containerEl.createEl('button', { cls: 'next-week', text: 'Next week' }).addEventListener('click', () => { this.week += 1; this.onDataUpdated(); });
            for (const entry of this.data.data) {
                const day = entry.getValue('note.day');
                const row = this.containerEl.createDiv({ cls: 'row', text: entry.file.basename + ': ' + (day instanceof NullValue ? 'Missing' : day.toString()) });
                row.style.height = '120px';
                row.style.background = '#dfe8ff';
                row.style.marginBottom = '4px';
            }
        }
    }
    module.exports = class extends Plugin {
        onload() { this.registerBasesView('week-table', { name: 'Week table', icon: 'calendar-days', factory: (controller, parent) => new WeekTable(controller, parent) }); }
    };
    """

    override func tearDown() async throws {
        if let workspace {
            await workspace.communityPlugins.vaultWillClose()
            for vaultIdentifier in openedVaultIdentifiers {
                workspace.vaultLibrary.remove(vaultIdentifier)
                CommunityPluginHost.forgetVault(vaultIdentifier)
            }
        }
        workspace = nil
        window?.isHidden = true
        window?.rootViewController = nil
        window = nil
        for directory in vaultDirectories { try? FileManager.default.removeItem(at: directory) }
        vaultDirectories = []
        openedVaultIdentifiers = []
    }

    func testEveryEmbedOfANoteDrawsInLivePreviewAndTheReadingViewAndStaysCurrent() async throws {
        let (workspace, vault, controller) = try await runningWorkspace()
        let host = workspace.communityPlugins
        await workspace.open(try VaultPath("Masters.md"), placement: .currentTab)
        let tab = try XCTUnwrap(workspace.layout.tabID(showing: try VaultPath("Masters.md")))
        let session = try XCTUnwrap(workspace.document(for: tab).markdownSession)

        // Live Preview, the default.
        XCTAssertNotEqual(session.viewMode, .reading)
        try await waitForEmbeds(in: controller, host: host)
        attachPicture(of: controller, named: "embeds in Live Preview")
        XCTAssertNil(host.liveViewIdentifier, "No embed took the one web view.")

        // The reading view.
        session.viewMode = .reading
        try await waitForEmbeds(in: controller, host: host)
        attachPicture(of: controller, named: "embeds in the reading view")

        // A property the views show changes in the file, and both redraw by themselves.
        try Data("---\nday: Friday\n---\n".utf8).write(to: vault.appendingPathComponent("Algebra.md"))
        try await waitUntil(timeoutSeconds: 20) { self.copies(in: host).joined().contains("Algebra: Friday") }

        // A tap in one embed reaches its own plugin view.
        let firstBlock = try XCTUnwrap(host.shownCodeBlocks.values.first { block in
            if case .drawn(let html) = block.appearance { return html.contains("First year") }
            return false
        })
        firstBlock.tap(elementPath: [0, 1])
        try await waitUntil(timeoutSeconds: 10) { self.copies(in: host).joined().contains("First year week 2") }
        XCTAssertTrue(copies(in: host).joined().contains("Second year week 1"), "The other embed is its own view.")
        attachPicture(of: controller, named: "after a tap and a property change")
    }

    // MARK: Narrow screens

    /// A sheet may not be wider than the screen it is on, or the plugin's controls are cut off.
    func testAPluginsPanelFitsAPhonesWidth() throws {
        let panel = UIHostingController(rootView: CommunityPluginPanel(host: CommunityPluginHost(defaults: UserDefaults(suiteName: UUID().uuidString) ?? .standard)))
        let width = panel.sizeThatFits(in: CGSize(width: 320, height: 800)).width
        XCTAssertLessThanOrEqual(width, 320)
    }

    /// The toolbar of a base in a note, with a long view name and a sort, in the narrowest note.
    func testAnEmbeddedBasesToolbarFitsANarrowNoteWithItsButtons() async throws {
        let vault = try TemporaryVault(prefix: "BasesToolbar").root
        vaultDirectories.append(vault)
        try Data("Body\n".utf8).write(to: vault.appendingPathComponent("Note.md"))
        try Data("views:\n  - type: table\n    name: One very long name of a view that goes on and on\n  - type: table\n    name: Second\n".utf8).write(to: vault.appendingPathComponent("Plan.base"))
        let indexFolder = vault.appendingPathComponent(".index", isDirectory: true)
        try FileManager.default.createDirectory(at: indexFolder, withIntermediateDirectories: true)
        let index = try VaultIndex(databaseURL: indexFolder.appendingPathComponent("index.sqlite"))
        _ = try await index.reconcile(root: vault)
        let path = try VaultPath("Plan.base")
        let model = BaseDocumentModel(source: .file(path), contextPath: path, store: VaultStore(root: vault), index: index)
        await model.reload()
        await model.toggleSort(on: .file("name"))
        let toolbar = BaseToolbar(model: model, isEmbedded: true, openBase: { _, _ in }, editView: {}, deleteView: {})
            .environment(\.horizontalSizeClass, .compact)
        let controller = UIHostingController(rootView: AnyView(toolbar))
        let window = UIWindow(windowScene: try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first))
        window.frame = CGRect(x: 0, y: 0, width: 320, height: 120)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        self.window = window
        controller.view.layoutIfNeeded()
        try await letTheScreenSettle()
        attachPicture(of: controller, named: "toolbar at 320 points")
        XCTAssertLessThanOrEqual(controller.sizeThatFits(in: CGSize(width: 320, height: 120)).width, 320)
        for button in descendants(of: controller.view, matching: UIView.self) where button.accessibilityLabel == "Reload" {
            XCTAssertLessThanOrEqual(button.convert(button.bounds, to: controller.view).maxX, 320, "The last button is on screen.")
        }
    }

    /// The options a plugin's view offers, in the view editor.
    func testTheViewEditorShowsThePluginsOptions() async throws {
        let registrationJSON = "{\"viewType\": \"week-table\", \"name\": \"Week table\", \"icon\": \"calendar-days\", \"options\": [{\"key\": \"title\", \"type\": \"text\", \"displayName\": \"Heading\", \"defaultValue\": \"A week\"}, {\"key\": \"firstHour\", \"type\": \"slider\", \"displayName\": \"First hour\", \"defaultValue\": 8, \"min\": 6, \"max\": 12}, {\"key\": \"rooms\", \"type\": \"toggle\", \"displayName\": \"Show rooms\"}, {\"key\": \"layout\", \"type\": \"dropdown\", \"displayName\": \"Layout\", \"choices\": [{\"value\": \"compact\", \"title\": \"Compact\"}]}]}"
        let registration = try JSONDecoder().decode(CommunityPluginBasesViewRegistration.self, from: Data(registrationJSON.utf8))
        XCTAssertEqual(registration.options.map(\.kind), [.text, .slider, .toggle, .dropdown])
        XCTAssertEqual(registration.options.first?.defaultValue, .text("A week"))
        XCTAssertEqual(registration.systemImage, "calendar")
        let definition = try BaseDefinition.parse("views:\n  - type: week-table\n    name: First\n    title: First year\n")
        let sheet = BaseViewEditorSheet(definition: definition, viewIndex: 0, availablePropertyKeys: [], pluginViews: ["week-table": registration]) { _, _, _ in nil }
        let controller = UIHostingController(rootView: AnyView(sheet))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        window.rootViewController = controller
        window.makeKeyAndVisible()
        self.window = window
        try await letTheScreenSettle()
        let table = try XCTUnwrap(descendants(of: controller.view, matching: UICollectionView.self).first)
        table.scrollToItem(at: IndexPath(item: 0, section: table.numberOfSections - 1), at: .top, animated: false)
        try await letTheScreenSettle()
        attachPicture(of: controller, named: "the view editor with the plugin's options")
    }

    private func waitForEmbeds(in controller: UIViewController, host: CommunityPluginHost) async throws {
        try await waitUntil(timeoutSeconds: 30) {
            let joined = self.copies(in: host).joined()
            return joined.contains("First year week") && joined.contains("Second year week")
        }
        try await waitUntil(timeoutSeconds: 15) {
            let webViews = self.descendants(of: controller.view, matching: WKWebView.self).filter { webView in webView !== host.webView && webView.window != nil }
            return webViews.count == 2 && webViews.allSatisfy { webView in webView.bounds.height > 150 }
        }
        // Each is as tall as what the plugin drew: a heading, a button and one 124 point row, not a spinner's height.
        try await waitUntil(timeoutSeconds: 15) { host.shownCodeBlocks.values.allSatisfy { block in block.height > 0 } }
        try await letTheScreenSettle()
        let heights = host.shownCodeBlocks.values.map(\.height)
        XCTAssertEqual(heights.count, 2)
        XCTAssertTrue(heights.allSatisfy { height in height > 150 && height < 400 }, "\(heights)")
    }

    private func copies(in host: CommunityPluginHost) -> [String] {
        host.shownCodeBlocks.values.compactMap { block in
            if case .drawn(let html) = block.appearance { return html }
            return nil
        }
    }

    private func attachPicture(of controller: UIViewController, named name: String) {
        let renderer = UIGraphicsImageRenderer(bounds: controller.view.bounds)
        let picture = renderer.image { _ in controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true) }
        let attachment = XCTAttachment(image: picture)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func runningWorkspace() async throws -> (WorkspaceModel, URL, UIViewController) {
        let vault = try TemporaryVault(prefix: "BasesEmbeds").root
        vaultDirectories.append(vault)
        let files = [
            ".obsidian/plugins/week-table/manifest.json": "{\"id\": \"week-table\", \"name\": \"Week Table\", \"version\": \"1.0.0\", \"minAppVersion\": \"1.0.0\", \"author\": \"Graphite\"}",
            ".obsidian/plugins/week-table/main.js": Self.pluginSource,
            ".obsidian/community-plugins.json": "[\"week-table\"]",
            "Plan.base": "filters: file.hasProperty(\"day\")\nviews:\n  - type: week-table\n    name: First\n    title: First year\n  - type: week-table\n    name: Second\n    title: Second year\n",
            "Algebra.md": "---\nday: Monday\n---\n",
            "Masters.md": "# Masters\n\nTwo years of courses.\n\n![[Plan.base#First]]\n\nThen the second year.\n\n![[Plan.base#Second]]\n",
        ]
        for (relativePath, text) in files {
            let location = vault.appendingPathComponent(relativePath)
            try FileManager.default.createDirectory(at: location.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(text.utf8).write(to: location)
        }
        let workspace = WorkspaceModel()
        self.workspace = workspace
        try await workspace.openFolderAsVault(vault)
        openedVaultIdentifiers.append(try XCTUnwrap(workspace.currentVaultIdentifier))
        let rootView = AnyView(NavigationStack {
            WorkspacePanes(workspace: workspace, showsLinksInspector: .constant(false), create: { _ in }, showQuickSwitcher: {})
        }.modifier(CommunityPluginPresentation(workspace: workspace) {}))
        let controller = UIHostingController(rootView: rootView)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        window.rootViewController = controller
        window.makeKeyAndVisible()
        self.window = window
        let host = workspace.communityPlugins
        await host.setTurnedOnForVault(true)
        try await waitUntil(timeoutSeconds: 20) { host.pluginBasesViews["week-table"] != nil }
        return (workspace, vault, controller)
    }

    /// Half a second of the run loop, for what is about to be pictured to be drawn.
    private func letTheScreenSettle() async throws {
        let deadline = Date.now.addingTimeInterval(0.5)
        try await waitUntil { Date.now >= deadline }
    }

    private func descendants<View: UIView>(of parent: UIView, matching type: View.Type) -> [View] {
        parent.subviews.flatMap { child in ((child as? View).map { [$0] } ?? []) + descendants(of: child, matching: type) }
    }
}
#endif
