/**
 * File: CommunityPluginBasesViewChoiceTests.swift
 * -----------------------------------------------
 * Layer: Tests
 * Description: A timetable plugin's base view in a note and in the base's own tab, through the real views and
 *              WebKit: drawn when plugins are on, waited for while they start, and offered while they are off.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 05/11/2026
 */

import XCTest
import SwiftUI
import GraphiteCore
import GraphiteIndex
@testable import GraphiteUI
import GraphiteTestSupport

/// HUNT-322: a note embedding bases of a timetable plugin's view type showed "Views Aren't
/// Supported". The fixture plugin is made here, with made-up courses, in the shape of the
/// owner's: it extends `BasesView`, reads `ListValue`s, groups, `config.get` and `config.name`,
/// draws icons with `setIcon`, follows clicks with `registerDomEvent` and `Keymap`, and
/// registers a hover link source.
@MainActor
final class CommunityPluginBasesViewChoiceTests: XCTestCase {
    private let testBed = CommunityPluginHostTestBed()

    override func tearDown() async throws {
        await testBed.tearDown()
    }

    private static let viewType = "week-timetable"

    private static let timetablePlugin = """
    'use strict';
    const { Plugin, BasesView, ListValue, Keymap, setIcon } = require('obsidian');
    class WeekTimetable extends BasesView {
        constructor(controller, parentEl) {
            super(controller);
            this.type = 'week-timetable';
            this.containerEl = parentEl.createDiv('tt-view');
            this.register(() => this.containerEl.remove());
            this.registerDomEvent(this.containerEl, 'click', (event) => {
                const link = event.target.closest('a.tt-session');
                if (!link) return;
                event.preventDefault();
                void this.app.workspace.openLinkText(link.dataset.href, '', Keymap.isModEvent(event));
            });
        }
        onDataUpdated() {
            this.containerEl.empty();
            const title = String(this.config.get('title') || 'A week');
            for (const group of this.data.groupedData) {
                if (group.hasKey()) this.containerEl.createEl('h4', { text: 'Term ' + group.key.toString() });
                const board = this.containerEl.createDiv({ cls: 'tt-board', text: this.config.name + ': ' + title });
                setIcon(board.createEl('button', { cls: 'tt-arrow' }), 'chevron-left');
                for (const entry of group.entries) {
                    const days = entry.getValue('note.days');
                    const shown = days instanceof ListValue ? Array.from({ length: days.length() }, (_, index) => days.get(index).toString()) : [days.toString()];
                    for (const day of shown) board.createEl('a', { cls: 'tt-session', text: entry.file.basename + ' on ' + day, attr: { 'data-href': entry.file.path } });
                }
            }
        }
    }
    module.exports = class extends Plugin {
        onload() {
            this.registerBasesView('week-timetable', { name: 'Week timetable', icon: 'calendar-days',
                factory: (controller, containerEl) => new WeekTimetable(controller, containerEl),
                options: () => [{ type: 'text', displayName: 'Heading', key: 'title', default: 'A week' }] });
            this.registerHoverLinkSource('week-timetable', { display: 'Week timetable', defaultMod: true });
        }
    };
    """

    private static let files = [
        "Plan.base": "filters: file.inFolder(\"Courses\")\nviews:\n  - type: week-timetable\n    name: Autumn timetable\n    title: Teaching week\n    groupBy:\n      property: note.term\n",
        "Courses/Algebra.md": "---\nterm: Autumn\ndays: [Mon, Wed]\n---\n",
        "Courses/Physics.md": "---\nterm: Autumn\ndays: Tue\n---\n",
        "Plan.md": "# Plan\n\n![[Plan.base#Autumn timetable]]\n",
    ]

    /// What the fixture plugin draws for the files above, as text.
    private static let drawnTexts = ["Term Autumn", "Autumn timetable: Teaching week", "Algebra on Mon", "Algebra on Wed", "Physics on Tue"]

    private static func embedEntry(_ markdown: String) -> LivePreviewBlockEntry {
        let block = LivePreviewBlockScanner.blocks(in: (markdown + "\n") as NSString)[0]
        return LivePreviewBlockEntry(block: block, range: block.range, key: LivePreviewBlockKey.keys(for: [block])[0])
    }

    /// The environment Live Preview gives a note's rendered blocks, with the plugins as they are now.
    private func livePreviewEnvironment(in workspace: WorkspaceModel) throws -> LivePreviewEnvironment {
        let plugins = workspace.communityPlugins
        return LivePreviewEnvironment(root: try XCTUnwrap(workspace.folderAccess?.root), textSize: 17, colorsEnabled: true, paletteHexByName: [:], drawingVersion: 0,
                                      resolve: { _, _ in try? VaultPath("Plan.base") }, open: { _ in }, follow: { _, _ in }, updateProperties: nil,
                                      baseContext: workspace.baseEmbedContext(for: try VaultPath("Plan.md")),
                                      pluginCodeBlocks: plugins.hostWhilePluginsAreOn, pluginsTurnOnOffer: plugins.turnOnOfferWhilePluginsAreOff)
    }

    private func shownCopies(in host: CommunityPluginHost) -> String {
        host.shownCodeBlocks.values.compactMap { block in
            if case .drawn(let html) = block.appearance { return html }
            return nil
        }.joined()
    }

    private func assertDrawnByThePlugin(_ html: String, file: StaticString = #filePath, line: UInt = #line) {
        for text in Self.drawnTexts { XCTAssertTrue(html.contains(text), "Missing “\(text)” in \(html)", file: file, line: line) }
        XCTAssertTrue(html.contains("<svg"), "setIcon drew the arrow's icon: \(html)", file: file, line: line)
    }

    // MARK: Choosing what a base shows

    func testWhilePluginsAreOffABaseOfAPluginsTypeSaysSoAndOffersToTurnThemOn() async throws {
        let workspace = try await testBed.workspaceWithPlugins([("timetable", Self.timetablePlugin)], files: Self.files)
        let plugins = workspace.communityPlugins
        let offer = try XCTUnwrap(plugins.turnOnOfferWhilePluginsAreOff, "Plugins are off, so bases get the offer.")
        XCTAssertNil(plugins.hostWhilePluginsAreOn)
        XCTAssertEqual(CommunityPluginBasesViewChoice.choose(viewType: Self.viewType, host: nil, turnOnOffer: offer), .pluginsAreOff,
                       "Not “Views Aren't Supported”: the plugin that draws the type is not running.")
        let explanation = CommunityPluginsOffForBaseView.explanation(viewType: Self.viewType)
        XCTAssertTrue(explanation.contains("community plugins are off for this vault on this device"), explanation)
        XCTAssertTrue(explanation.contains("“week-timetable”"), explanation)

        offer.openCommunityPluginSettings()
        XCTAssertEqual(plugins.requestedSettingsPlugin, "", "The offer opens Settings › Community Plugins, which asks before plugins run.")

        await plugins.setTurnedOnForVault(true)
        XCTAssertNil(plugins.turnOnOfferWhilePluginsAreOff, "Once plugins are on, nothing offers to turn them on.")
        try await waitUntil("the plugin's view type is known", timeoutSeconds: 20) { plugins.pluginBasesViews[Self.viewType] != nil }
        XCTAssertEqual(CommunityPluginBasesViewChoice.choose(viewType: Self.viewType, host: plugins.hostWhilePluginsAreOn, turnOnOffer: nil), .drawnByPlugin)
        XCTAssertEqual(CommunityPluginBasesViewChoice.choose(viewType: "a-type-no-plugin-draws", host: plugins.hostWhilePluginsAreOn, turnOnOffer: nil), .unsupported)
        XCTAssertEqual(CommunityPluginBasesViewChoice.choose(viewType: Self.viewType, host: nil, turnOnOffer: nil), .unsupported,
                       "Without plugins at all (no vault), the type is unsupported.")
    }

    func testTurningPluginsOnGivesTheNotesRenderedBlocksTheHost() async throws {
        let workspace = try await testBed.workspaceWithPlugins([("timetable", Self.timetablePlugin)], files: Self.files)
        let whileOff = LivePreviewWidgetSignature(environment: try livePreviewEnvironment(in: workspace), accentHex: "#000000", notePath: "Plan.md")
        await workspace.communityPlugins.setTurnedOnForVault(true)
        let whileOn = LivePreviewWidgetSignature(environment: try livePreviewEnvironment(in: workspace), accentHex: "#000000", notePath: "Plan.md")
        // A block's hosted view keeps the environment it was made with until the signature
        // changes: an embed shown while plugins were off kept no host, and kept the placeholder.
        XCTAssertNotEqual(whileOff, whileOn)
        XCTAssertNotEqual(whileOff.appearance, whileOn.appearance, "Every block is given the new environment, not only those reading the index.")
    }

    func testTheTimetablePluginsManifestLoadsOnTheMacTheIPadAndTheIPhone() throws {
        let manifest = try CommunityPluginManifest(manifestData: Data("""
            {"id": "timetable", "name": "Timetable", "version": "1.0.0", "minAppVersion": "1.10.0", "isDesktopOnly": false}
            """.utf8))
        let compatibility = CommunityPluginCompatibility.assess(manifest: manifest, hasMainScript: true)
        XCTAssertTrue(compatibility.canLoad, "Obsidian 1.10.0 is older than the API Graphite provides, compared by number, not as text.")
        XCTAssertTrue(compatibility.blockers.isEmpty)
    }

    // MARK: Drawn through the real views and WebKit

    #if canImport(AppKit)
    private func host<Content: View>(_ view: Content, width: CGFloat = 640) -> NSWindow {
        let hosting = NSHostingView(rootView: view.frame(width: width, height: 900))
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: width, height: 900), styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = hosting
        window.showInvisibly()
        addTeardownBlock { @MainActor in window.contentView = nil; window.orderOut(nil) }
        return window
    }

    func testAnEmbedInALivePreviewNoteDrawsThePluginsViewNotThePlaceholder() async throws {
        let workspace = try await testBed.workspaceWithRunningPlugins([("timetable", Self.timetablePlugin)], files: Self.files)
        let plugins = workspace.communityPlugins
        try await waitUntil("the view type is known", timeoutSeconds: 10) { plugins.pluginBasesViews[Self.viewType] != nil }
        let embed = LivePreviewRenderedBlocks.rootView(for: Self.embedEntry("![[Plan.base#Autumn timetable]]"), environment: try livePreviewEnvironment(in: workspace),
                                                       accentHex: "#000000", colorScheme: .light, revealSource: {}, reportHeight: { _ in })
        _ = host(embed.view)

        try await waitUntil("the embed shows what the plugin drew", timeoutSeconds: 25) { self.shownCopies(in: plugins).contains("Physics on Tue") }
        assertDrawnByThePlugin(shownCopies(in: plugins))
        XCTAssertTrue(plugins.runtimeProblems.isEmpty, "\(plugins.runtimeProblems)")
    }

    func testTheBasesOwnTabDrawsThePluginsViewLive() async throws {
        let workspace = try await testBed.workspaceWithRunningPlugins([("timetable", Self.timetablePlugin)], files: Self.files)
        let plugins = workspace.communityPlugins
        try await waitUntil("the view type is known", timeoutSeconds: 10) { plugins.pluginBasesViews[Self.viewType] != nil }
        let store = try XCTUnwrap(workspace.store), index = try XCTUnwrap(workspace.index)
        _ = host(BaseDocumentView(path: try VaultPath("Plan.base"), store: store, index: index, open: { _ in })
            .environment(\.communityPluginCodeBlocks, plugins.hostWhilePluginsAreOn)
            .environment(\.communityPluginsTurnOnOffer, plugins.turnOnOfferWhilePluginsAreOff))

        try await waitUntil("the tab shows the plugin's view live", timeoutSeconds: 25) { plugins.liveViewIdentifier != nil }
        let drawn = try await testBed.evaluate("return Array.from(document.querySelectorAll('.tt-view')).map((element) => element.innerHTML).join('')", in: plugins) as? String
        assertDrawnByThePlugin(try XCTUnwrap(drawn))
    }

    func testAnEmbedShownWhilePluginsStartDrawsThePluginsViewOnceItRegisters() async throws {
        let workspace = try await testBed.workspaceWithPlugins([("timetable", Self.timetablePlugin)], files: Self.files)
        let plugins = workspace.communityPlugins
        let turningOn = Task { await plugins.setTurnedOnForVault(true) }
        await Task.yield()
        XCTAssertEqual(CommunityPluginBasesViewChoice.choose(viewType: Self.viewType, host: plugins.hostWhilePluginsAreOn, turnOnOffer: plugins.turnOnOfferWhilePluginsAreOff),
                       .waitingForPlugins, "Shown before the plugin registered its view, the embed waits.")
        let embed = LivePreviewRenderedBlocks.rootView(for: Self.embedEntry("![[Plan.base#Autumn timetable]]"), environment: try livePreviewEnvironment(in: workspace),
                                                       accentHex: "#000000", colorScheme: .light, revealSource: {}, reportHeight: { _ in })
        _ = host(embed.view)
        await turningOn.value

        try await waitUntil("the embed shows what the plugin drew once it registered", timeoutSeconds: 25) { self.shownCopies(in: plugins).contains("Physics on Tue") }
        assertDrawnByThePlugin(shownCopies(in: plugins))
    }
    #endif
}
