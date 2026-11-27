/**
 * File: CommunityPluginNotionImporterPluginHostedTests.swift
 * ----------------------------------------------------------
 * Layer: Tests
 * Description: The Notion Importer plugin (the Swift Importer compiled to WebAssembly) importing Notion exports in
 *              WebKit inside the app, on the iPad and the Mac, compared file by file with the linked package's import.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 27/11/2026
 */
import XCTest
import Darwin
import WebKit
import GraphiteCore
@testable import GraphiteUI

/// The plugin of `Graphite-Note/Importer` (`Plugin/build-plugin.sh`), installed as Graphite installs it, run on the
/// plugin panel as a person runs it: its settings tab's Import button, the export given to the window's file input,
/// Import, then the report. The made-up export of the Node tests (`notion-small-export.zip`) imports with nothing
/// failed. Each export of `GRAPHITE_NOTION_PLUGIN_EXPORTS` (`export.zip=expected vault` pairs separated by `|`, the
/// expected vault written by the Importer's `importer` command with `--into Notion`) is then imported into a vault of
/// its own and must come out as the expected vault, file by file and byte by byte. The test prints how long each
/// import took and the most memory the plugins' web content process used. Skipped, as the other real plugins' tests
/// here, when the plugin is not built into `compatibility/built/graphite-notion-importer`.
@MainActor
extension CommunityPluginHostTests {
    private static let notionPluginIdentifier = "graphite-notion-importer"

    func testNotionImporterPluginImportsEachExportAsTheLinkedPackageDoes() async throws {
        let pairs = (ProcessInfo.processInfo.environment["GRAPHITE_NOTION_PLUGIN_EXPORTS"] ?? "")
            .split(separator: "|").compactMap { pair -> (URL, URL)? in
                let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
                return parts.count == 2 ? (URL(fileURLWithPath: parts[0]), URL(fileURLWithPath: parts[1])) : nil
            }
        let madeUpExport = Self.runtimeTestsFolder.appendingPathComponent("fixtures/notion-small-export.zip")
        let exports: [(URL, URL?)] = [(madeUpExport, nil)] + pairs.map { pair in (pair.0, pair.1) }
        for (export, expectedVault) in exports {
            let (workspace, vault) = try await workspaceAndVaultWithBuiltPlugins([Self.notionPluginIdentifier],
                                                                                 notes: ["Welcome.md": "# Welcome\n"])
            let pieces = try writeInPieces(export, into: vault)
            let host = workspace.communityPlugins
            let memoryBefore = webContentFootprint(of: host)
            let summary = try await runNotionImporterPlugin(in: host, exportPieces: pieces, exportName: export.lastPathComponent)
            let memory = webContentFootprint(of: host)
            print("""
                Notion Importer plugin, \(export.lastPathComponent): \(summary["notes"] ?? "?") notes, \(summary["bases"] ?? "?") bases, \
                \(summary["attachments"] ?? "?") attachments, failed \(summary["failed"] ?? "?"), in \(summary["seconds"] ?? "?") s, \
                \(summary["hostCalls"] ?? "?") host calls; web content \(memoryBefore.current) MB before, \(memory.current) MB after, \
                \(memory.peak) MB at most (process \(memory.process)); the module's memory \(summary["moduleMemoryMB"] ?? "?") MB
                """)
            XCTAssertEqual(summary["failed"] as? Int, 0, "\(summary)")
            XCTAssertTrue(FileManager.default.fileExists(atPath: vault.appendingPathComponent("Notion/Notion import report.md").path))
            guard let expectedVault else {
                await host.setTurnedOnForVault(false)
                continue
            }
            let differences = try vaultDifferences(expected: expectedVault.appendingPathComponent("Notion"),
                                                   imported: vault.appendingPathComponent("Notion"))
            XCTAssertEqual(differences, [], "\(export.lastPathComponent) imports as the linked package does")
            try assertSamePropertyTypes(expected: expectedVault, imported: vault, export: export.lastPathComponent)
            await host.setTurnedOnForVault(false)
        }
    }

    /// The export copied into the vault's `Picked` folder in pieces of 64 MB, since the plugin panel serves no file over
    /// 256 MB, and the pieces' paths in order.
    private func writeInPieces(_ export: URL, into vault: URL) throws -> [String] {
        let folder = vault.appendingPathComponent("Picked")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let reader = try FileHandle(forReadingFrom: export)
        defer { try? reader.close() }
        var paths: [String] = []
        while let piece = try reader.read(upToCount: 64 * 1_048_576), !piece.isEmpty {
            let path = "Picked/\(export.lastPathComponent).\(paths.count)"
            try piece.write(to: vault.appendingPathComponent(path))
            paths.append(path)
        }
        return paths
    }

    /// Opens the plugin's settings, its import window, gives the file input the export (its pieces read from the vault
    /// and joined into one `File`, since no person picks it here), presses Import and waits for the report.
    private func runNotionImporterPlugin(in host: CommunityPluginHost, exportPieces: [String], exportName: String) async throws -> [String: Any] {
        let hasSettings = await host.showSettings(of: Self.notionPluginIdentifier)
        XCTAssertTrue(hasSettings, "the plugin has its settings tab")
        let webView = try XCTUnwrap(host.webView)
        let script = """
            const pause = (milliseconds) => new Promise((resolve) => setTimeout(resolve, milliseconds));
            const app = window.GraphitePluginRuntime.app;
            const pieces = [];
            for (const piecePath of exportPieces) {
                const response = await fetch(app.vault.adapter.getResourcePath(piecePath));
                if (!response.ok) throw new Error('The test could not read ' + piecePath + ': ' + response.status);
                pieces.push(await response.blob());
            }
            const exportFile = new File(pieces, exportName, { type: 'application/zip' });
            const importButton = Array.from(document.querySelectorAll('.setting-item button')).find((button) => button.textContent === 'Import…');
            if (!importButton) throw new Error('No Import… button in the settings tab');
            importButton.click();
            await pause(200);
            const input = document.querySelector('.notion-importer input[type=file]');
            if (!input) throw new Error('No file input in the import window');
            Object.defineProperty(input, 'files', { value: [exportFile], configurable: true });
            input.dispatchEvent(new Event('change'));
            const windowButtons = () => Array.from(document.querySelectorAll('.notion-importer button'));
            const start = windowButtons().find((button) => button.textContent === 'Import');
            if (!start || start.disabled) throw new Error('The Import button is not ready');
            start.click();
            const deadline = Date.now() + timeoutMilliseconds;
            while (!windowButtons().some((button) => button.textContent === 'Open the report')) {
                const status = (document.querySelector('.notion-importer-status') || {}).textContent || '';
                if (status.startsWith('The import failed')) throw new Error(status);
                if (Date.now() > deadline) throw new Error('The import did not finish: ' + status);
                await pause(200);
            }
            const plugin = app.plugins.plugins[pluginIdentifier];
            const summary = Object.assign({}, plugin.lastSummary);
            summary.status = document.querySelector('.notion-importer-status').textContent;
            document.querySelector('.notion-importer').closest('.modal-container')?.querySelector('.modal-close-button')?.click();
            return summary;
            """
        let arguments: [String: Any] = ["exportPieces": exportPieces, "exportName": exportName, "timeoutMilliseconds": 3_600_000,
                                        "pluginIdentifier": Self.notionPluginIdentifier]
        let answer = try await webView.callAsyncJavaScript(script, arguments: arguments, in: nil, contentWorld: .page)
        return try XCTUnwrap(answer as? [String: Any])
    }

    /// The memory of the web content process running the plugins, in MB: now and the most it used, from the system's
    /// accounting of that process (its physical footprint, which Jetsam limits on the iPad), with the process's number.
    /// The iPad's SDK has no `proc_pid_rusage`: there the number alone is given, for a sampler outside the simulator.
    private func webContentFootprint(of host: CommunityPluginHost) -> (current: Int, peak: Int, process: Int32) {
        guard let webView = host.webView, let identifier = webView.value(forKey: "_webProcessIdentifier") as? Int32, identifier > 0 else {
            return (-1, -1, -1)
        }
        #if os(macOS)
        var usage = rusage_info_v4()
        let result = withUnsafeMutablePointer(to: &usage) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(identifier, RUSAGE_INFO_V4, $0) }
        }
        guard result == 0 else { return (-1, -1, identifier) }
        return (Int(usage.ri_phys_footprint / 1_048_576), Int(usage.ri_lifetime_max_phys_footprint / 1_048_576), identifier)
        #else
        return (-1, -1, identifier)
        #endif
    }

    /// The files that differ between two folders, compared byte by byte, paths in Unicode's composed form (Foundation
    /// and WebKit may write a name decomposed or composed).
    private func vaultDifferences(expected: URL, imported: URL) throws -> [String] {
        func files(in folder: URL) throws -> [String: URL] {
            var found: [String: URL] = [:]
            guard let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.isDirectoryKey]) else { return [:] }
            for case let location as URL in enumerator where try location.resourceValues(forKeys: [.isDirectoryKey]).isDirectory != true {
                let path = String(location.standardizedFileURL.path.dropFirst(folder.standardizedFileURL.path.count + 1))
                found[path.precomposedStringWithCanonicalMapping] = location
            }
            return found
        }
        let expectedFiles = try files(in: expected)
        let importedFiles = try files(in: imported)
        var differences = Set(expectedFiles.keys).symmetricDifference(importedFiles.keys).map { path in "only in one: " + path }
        for (path, location) in expectedFiles {
            guard let other = importedFiles[path] else { continue }
            if try Data(contentsOf: location) != Data(contentsOf: other) { differences.append("differs: " + path) }
        }
        return differences.sorted()
    }

    private func assertSamePropertyTypes(expected: URL, imported: URL, export: String) throws {
        let expectedTypes = expected.appendingPathComponent(".obsidian/types.json")
        guard FileManager.default.fileExists(atPath: expectedTypes.path) else { return }
        let read = { (location: URL) in try JSONSerialization.jsonObject(with: Data(contentsOf: location)) as? NSDictionary }
        XCTAssertEqual(try read(imported.appendingPathComponent(".obsidian/types.json")), try read(expectedTypes),
                       "\(export): the same property types")
    }
}
