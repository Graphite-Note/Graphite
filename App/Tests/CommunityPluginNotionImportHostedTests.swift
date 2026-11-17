/**
 * File: CommunityPluginNotionImportHostedTests.swift
 * --------------------------------------------------
 * Layer: Tests
 * Description: Obsidian's Importer importing a made-up Notion export in WebKit, inside the app, on the iPad and the Mac.
 *
 * Authors: Bahey Shalash
 * Version: 1.0
 * Date: 17/11/2026
 */
import XCTest
import CryptoKit
import SwiftUI
import WebKit
import GraphiteCore
import GraphiteIndex
@testable import GraphiteUI

/// Obsidian's own Importer, unmodified, run on the plugin panel in WebKit inside the app, importing
/// the made-up Notion HTML export the Node tests import (`notion-small-export.zip`, made by
/// `support/notion-export-fixture.js`). The notes must come out byte for byte as the Node tests
/// expect (`notion-html-import-expected.json`), so WebKit's HTML parsing and Graphite's native
/// vault writes give the same notes as jsdom and the test host, and Graphite's own index must take
/// them in, with every link resolved but Importer's own shortened title.
///
/// With `GRAPHITE_NOTION_LARGE_EXPORT` naming a larger export (`node support/notion-export-fixture.js large`
/// makes one), the test imports it too and prints how long it took, how often the index refreshed and
/// the longest the main thread was held meanwhile. Skipped, as the other real plugins' tests here, when
/// Importer is not built (`npm run build-compatibility-plugins`).
@MainActor
extension CommunityPluginHostTests {
    private static let importerIdentifier = "obsidian-importer"
    private static let smallExport = runtimeTestsFolder.appendingPathComponent("fixtures/notion-small-export.zip")
    private static let expectedImport = runtimeTestsFolder.appendingPathComponent("fixtures/notion-html-import-expected.json")
    /// Where the vault keeps the export the page reads, as a picked file would be read.
    private static let exportPathInVault = "Notion export.zip"
    /// Importer's link to the page whose title it shortened with "...", which its own file name drops.
    private static let shortenedTitleLink = String(repeating: "A very long title ", count: 11) + "A..."

    func testImporterImportsTheNotionExportInWebKitAsTheNodeTestsExpectAndTheIndexResolvesItsLinks() async throws {
        let (workspace, vault) = try await workspaceWithImporter(exportArchive: Self.smallExport)
        let host = workspace.communityPlugins
        let summary = try await runNotionImport(in: host)
        XCTAssertEqual(summary["imported"] as? Int, 17, "\(summary)")
        XCTAssertEqual(summary["attachments"] as? Int, 2, "\(summary)")
        XCTAssertEqual(summary["failed"] as? Int, 0, "\(summary)")

        let expected = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: Self.expectedImport)) as? [String: String])
        let imported = try importedFiles(in: vault)
        XCTAssertEqual(imported.keys.sorted(), expected.keys.sorted(), "the same files, in the same folders")
        for (path, contents) in expected { XCTAssertEqual(imported[path], contents, path) }

        // Graphite's own index takes the notes in, and resolves their links as Obsidian does.
        let index = try XCTUnwrap(workspace.index)
        try await waitUntil("the index has the imported notes", timeoutSeconds: 30) {
            (try? await index.fileCount()) ?? 0 >= expected.count
        }
        var unresolvedLinks: [String] = []
        for path in expected.keys where path.hasSuffix(".md") {
            let source = try VaultPath(path)
            let targets = try await index.outgoingLinks(from: source)
            let resolved = try await index.resolve(wikilinks: targets, from: source)
            unresolvedLinks += targets.filter { target in resolved[target] == nil }
        }
        XCTAssertEqual(unresolvedLinks, [Self.shortenedTitleLink])
        try await measureLargeImportWhenAsked(in: workspace, vault: vault)
    }

    /// With `GRAPHITE_NOTION_LARGE_EXPORT` set, imports that export too, into the same vault, and prints how
    /// long it took, how often the index refreshed and the longest the main thread was held meanwhile.
    private func measureLargeImportWhenAsked(in workspace: WorkspaceModel, vault: URL) async throws {
        guard let largeExportPath = ProcessInfo.processInfo.environment["GRAPHITE_NOTION_LARGE_EXPORT"], !largeExportPath.isEmpty else { return }
        try FileManager.default.removeItem(at: vault.appendingPathComponent(Self.exportPathInVault))
        try Data(contentsOf: URL(fileURLWithPath: largeExportPath)).write(to: vault.appendingPathComponent(Self.exportPathInVault))
        let host = workspace.communityPlugins
        let notesBefore = try importedFiles(in: vault).keys.filter { path in path.hasSuffix(".md") }.count
        let indexVersionBefore = workspace.indexVersion
        let watch = MainThreadWatch()
        watch.start()
        let started = ContinuousClock.now
        let summary = try await runNotionImport(in: host, timeoutSeconds: 3_600)
        let importDuration = ContinuousClock.now - started
        let index = try XCTUnwrap(workspace.index)
        let allNoteCount = try importedFiles(in: vault).keys.filter { path in path.hasSuffix(".md") }.count
        let importedNoteCount = allNoteCount - notesBefore
        try await waitUntil("the index has the imported notes", timeoutSeconds: 600) {
            (try? await index.fileCount()) ?? 0 >= allNoteCount
        }
        let indexedDuration = ContinuousClock.now - started
        watch.stop()
        print("""
            Notion import measured: \(summary["imported"] ?? "?") notes, failed \(summary["failed"] ?? "?"); \
            import \(importDuration.formatted(.units(allowed: [.seconds], fractionalPart: .show(length: 1)))), \
            indexed \(indexedDuration.formatted(.units(allowed: [.seconds], fractionalPart: .show(length: 1)))); \
            index refreshes \(workspace.indexVersion - indexVersionBefore); \
            longest main-thread hold \(watch.longestGapMilliseconds) ms, holds over 50 ms \(watch.gapsOverFiftyMilliseconds)
            """)
        XCTAssertEqual(summary["failed"] as? Int, 0, "\(summary)")
        XCTAssertLessThan(workspace.indexVersion - indexVersionBefore, max(10, importedNoteCount / 10),
                          "the index refreshes in batches, not once per note")
    }

    // MARK: Driving Importer

    /// Walks Importer on the plugin panel as a person does: its settings, Notion, File import, the
    /// export chosen, then Continue until Start import and Done. The file input's click hands it the
    /// export, read from the vault as WebKit reads a picked file, since no person picks it here.
    private func runNotionImport(in host: CommunityPluginHost, timeoutSeconds: Double = 120) async throws -> [String: Any] {
        // An import shown as finished is closed with its Done first, as a person does before the next.
        let finishScript = "document.querySelectorAll('.importer-button-bar button.mod-cta')"
            + ".forEach((button) => { if (button.textContent === 'Done') button.click(); });"
        _ = try await host.webView?.callAsyncJavaScript(finishScript, arguments: [:], in: nil, contentWorld: .page)
        let hasSettings = await host.showSettings(of: Self.importerIdentifier)
        XCTAssertTrue(hasSettings, "Importer has its settings tab")
        let webView = try XCTUnwrap(host.webView)
        let script = """
            const pause = (milliseconds) => new Promise((resolve) => setTimeout(resolve, milliseconds));
            const app = window.GraphitePluginRuntime.app;
            const response = await fetch(app.vault.adapter.getResourcePath(exportPath));
            const exportFile = new File([await response.blob()], 'Export-study-notes.zip', { type: 'application/zip' });
            const originalClick = HTMLInputElement.prototype.click;
            HTMLInputElement.prototype.click = function () {
                if (this.type !== 'file') return originalClick.call(this);
                HTMLInputElement.prototype.click = originalClick;
                Object.defineProperty(this, 'files', { value: [exportFile], configurable: true });
                this.dispatchEvent(new Event('change'));
            };
            const clickSetting = (name) => {
                const row = Array.from(document.querySelectorAll('.setting-item'))
                    .find((element) => (element.querySelector('.setting-item-name') || {}).textContent === name);
                if (!row) throw new Error('No setting named ' + name);
                row.click();
            };
            const topPage = () => Array.from(document.querySelectorAll('.setting-page')).at(-1);
            const buttons = () => Array.from(document.querySelectorAll('.importer-button-bar button.mod-cta'));
            await pause(100);
            clickSetting('Notion');
            await pause(100);
            clickSetting('File import');
            await pause(100);
            topPage().querySelector('.setting-item.mod-add-item.mod-clickable').click();
            await pause(500);
            const deadline = Date.now() + timeoutMilliseconds;
            while (!buttons().some((button) => button.textContent === 'Done')) {
                if (Date.now() > deadline) throw new Error('The import did not finish: ' + topPage().textContent.slice(0, 300));
                const button = buttons()[0];
                if (button && !button.disabled && button.textContent !== 'Done' && !button.dataset.graphiteClicked) {
                    button.dataset.graphiteClicked = 'yes';
                    button.click();
                }
                await pause(200);
            }
            const count = (name) => {
                const element = document.querySelector('.importer-stat.mod-' + name + ' .importer-stat-count');
                return element ? Number(element.textContent.replace(/[^0-9]/g, '')) : -1;
            };
            return { imported: count('imported'), attachments: count('attachments'), skipped: count('skipped'), failed: count('failed'),
                     log: Array.from(topPage().querySelectorAll('.importer-log .list-item')).map((element) => element.textContent) };
            """
        let arguments: [String: Any] = ["exportPath": Self.exportPathInVault, "timeoutMilliseconds": timeoutSeconds * 1000]
        let answer = try await webView.callAsyncJavaScript(script, arguments: arguments, in: nil, contentWorld: .page)
        return try XCTUnwrap(answer as? [String: Any])
    }

    /// Every file the import wrote: notes as text, other files as `sha256:` and their digest, as the
    /// Node tests record them. The export itself and the hidden folders are left out.
    private func importedFiles(in vault: URL) throws -> [String: String] {
        var files: [String: String] = [:]
        let enumerator = try XCTUnwrap(FileManager.default.enumerator(at: vault, includingPropertiesForKeys: [.isDirectoryKey]))
        for case let location as URL in enumerator {
            let path = String(location.standardizedFileURL.path.dropFirst(vault.standardizedFileURL.path.count + 1))
            if path.hasPrefix(".") { enumerator.skipDescendants(); continue }
            guard try location.resourceValues(forKeys: [.isDirectoryKey]).isDirectory != true,
                  path != Self.exportPathInVault else { continue }
            let data = try Data(contentsOf: location)
            if ["md", "base", "json", "txt", "csv"].contains(location.pathExtension) {
                files[path] = String(decoding: data, as: UTF8.self)
            } else {
                files[path] = "sha256:" + SHA256.hash(data: data).map { byte in String(format: "%02x", byte) }.joined()
            }
        }
        return files
    }

    // MARK: The workspace

    /// A vault with Importer installed as Graphite installs it, turned on and loaded in a window (skipped
    /// when Importer is not built), with the export put beside its notes.
    private func workspaceWithImporter(exportArchive: URL) async throws -> (WorkspaceModel, URL) {
        let (workspace, vault) = try await workspaceAndVaultWithBuiltPlugins([Self.importerIdentifier], notes: ["Welcome.md": "# Welcome\n"])
        try Data(contentsOf: exportArchive).write(to: vault.appendingPathComponent(Self.exportPathInVault))
        return (workspace, vault)
    }
}

/// The longest the main thread went without running a timer due every 16 ms, as a typed key or a
/// Pencil sample would wait for it. The timer runs on the main run loop, so its action is on the main thread.
@MainActor
private final class MainThreadWatch: NSObject {
    private var timer: Timer?
    private var lastFire = ContinuousClock.now
    private(set) var longestGapMilliseconds = 0
    private(set) var gapsOverFiftyMilliseconds = 0

    func start() {
        lastFire = .now
        let timer = Timer(timeInterval: 0.016, target: self, selector: #selector(timerFired), userInfo: nil, repeats: true)
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    @objc private func timerFired() {
        let now = ContinuousClock.now
        let gap = now - lastFire
        lastFire = now
        let milliseconds = Int(gap.components.seconds * 1000 + gap.components.attoseconds / 1_000_000_000_000_000)
        longestGapMilliseconds = max(longestGapMilliseconds, milliseconds)
        if milliseconds > 50 { gapsOverFiftyMilliseconds += 1 }
    }
}

